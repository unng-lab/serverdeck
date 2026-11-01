import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:serverdeck_engine/remote/direct_ssh.dart';
import 'package:serverdeck_engine/remote/ssh_transport.dart';
import 'package:test/test.dart';

import 'ssh_io_policy_test.dart' as io;
import 'ssh_pool_lifecycle_test.dart' show settle, failure;

final class _ManualTimer implements Timer {
  _ManualTimer(this.callback);
  final void Function() callback;
  bool _active = true;
  int _tick = 0;
  @override
  bool get isActive => _active;
  @override
  int get tick => _tick;
  @override
  void cancel() => _active = false;
  void fire() {
    if (!_active) return;
    _active = false;
    _tick++;
    callback();
  }
}

void main() {
  test('pre-dispatch proof waits inside the physical channel lifetime and cancel sends no bytes', () async {
    final provider = io.Io(), pool = SshTransportPool(io: provider);
    final lease = await io.connect(pool), proof = Completer<void>();
    final call = lease.execute(
      DirectSshCommand.inspect(),
      beforeDispatch: () => proof.future,
    );
    final failedResult = expectLater(
      call.result,
      failure(SshTransportCode.CANCELLED),
    );
    await settle();
    final session = provider.attempts.single.client.sessions.single;
    expect(session.received, isEmpty);
    call.cancel();
    await failedResult;
    var settled = false;
    call.settled.then((_) => settled = true).ignore();
    await settle();
    expect(settled, isFalse);
    proof.complete();
    await call.settled;
    expect(session.received, isEmpty);
    await pool.close();
  });
  test(
    'missing bootstrap tools and denied sudo retain specific safe failures',
    () async {
      final provider = io.Io(), pool = SshTransportPool(io: provider);
      final lease = await io.connect(pool);
      final replies = [
        (
          'SDSSH_ERROR\tPREREQUISITE_UNAVAILABLE\n',
          127,
          'PREREQUISITE_UNAVAILABLE',
        ), // Missing sudo.
        (
          'SDSSH_ERROR\tPREREQUISITE_UNAVAILABLE\n',
          127,
          'PREREQUISITE_UNAVAILABLE',
        ), // Missing id.
        ('', 1, 'FORBIDDEN'), // Installed noninteractive sudo refuses access.
        ('', 255, 'UNKNOWN_OUTCOME'), // No trustworthy completion evidence.
      ];
      for (final reply in replies) {
        final call = lease.execute(DirectSshCommand.inspect());
        await settle();
        final session = provider.attempts.single.client.sessions.last;
        session.exitCode = reply.$2;
        if (reply.$1.isNotEmpty) {
          session.output.add(Uint8List.fromList(ascii.encode(reply.$1)));
        }
        await session.finish();
        final output = await call.result;
        expect(
          () => output.textRows(DirectSshIdentity.fields),
          throwsA(
            isA<DirectSshFailure>().having(
              (error) => error.code,
              'safe category',
              reply.$3,
            ),
          ),
        );
        await call.settled;
      }
      await pool.close();
      expect(pool.activeTransports, 0);
    },
  );

  test(
    'inspection enforces its10s clock cap but retains unconfirmed cleanup',
    () async {
      final provider = io.Io(), pool = SshTransportPool(io: provider);
      final lease = await io.connect(pool);
      provider.attempts.single.client.onExecute = (session, _) {
        session.autoClose = false;
      };
      final timers = <_ManualTimer>[];
      final call = runZoned(
        () => lease.execute(
          DirectSshCommand.inspect(),
          deadline: const Duration(seconds: 90),
        ),
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            if (duration == const Duration(seconds: 10)) {
              final timer = _ManualTimer(callback);
              timers.add(timer);
              return timer;
            }
            return parent.createTimer(zone, duration, callback);
          },
        ),
      );
      await settle();
      expect(timers, hasLength(1));
      final timedOut = expectLater(
        call.result,
        failure(SshTransportCode.TIMEOUT),
      );
      var drained = false;
      call.settled.then<void>((_) => drained = true).ignore();
      timers.single.fire();
      await timedOut;
      await settle();
      expect(drained, isFalse);
      final reads = [
        for (var index = 0; index < 3; index++)
          lease.read(const SshReadRequest.system()),
      ];
      expect(
        () => lease.execute(DirectSshCommand.inspect()),
        failure(SshTransportCode.RESOURCE_LIMIT),
      );
      final failures = [
        for (final read in reads)
          expectLater(read.result, failure(SshTransportCode.CANCELLED)),
      ];
      for (final read in reads) {
        read.cancel();
      }
      await settle();
      for (final session in provider.attempts.single.client.sessions) {
        await session.finish();
      }
      await Future.wait(failures);
      await call.settled;
      await Future.wait([for (final read in reads) read.settled]);
      await pool.close();
    },
  );

  test(
    'observation exact128KiB fits; plus1 retains occupancy until completion',
    () async {
      final provider = io.Io(), pool = SshTransportPool(io: provider);
      final lease = await io.connect(pool);
      provider.attempts.single.client.onExecute = (session, _) {
        session.autoClose = false;
      };
      final command = DirectSshCommand.observation('system.motd');
      expect(command.outputLimit, 128 * 1024);
      final exact = lease.execute(command);
      await settle();
      final client = provider.attempts.single.client;
      client.sessions.last.output.add(Uint8List(128 * 1024));
      await client.sessions.last.finish();
      expect((await exact.result).truncated, isFalse);
      await exact.settled;
      final over = lease.execute(command);
      final rest = [
        for (var index = 0; index < 3; index++) lease.execute(command),
      ];
      await settle();
      client.sessions[1].output.add(Uint8List(128 * 1024 + 1));
      await settle();
      expect(
        () => lease.execute(command),
        failure(SshTransportCode.RESOURCE_LIMIT),
      );
      await client.sessions[1].finish();
      final output = await over.result;
      expect(output.truncated, isTrue);
      expect(output.bytes.length, 128 * 1024);
      await over.settled;
      final failures = [
        for (final call in rest)
          expectLater(call.result, failure(SshTransportCode.CANCELLED)),
      ];
      for (final call in rest) {
        call.cancel();
      }
      for (final session in client.sessions.skip(2)) {
        await session.finish();
      }
      await Future.wait(failures);
      await Future.wait([for (final call in rest) call.settled]);
      await pool.close();
    },
  );

  test(
    'typed exec writes only compiler input and drains both streams',
    () async {
      final provider = io.Io(), pool = SshTransportPool(io: provider);
      final lease = await io.connect(pool);
      final command = DirectSshCommand.inspect();
      final attempt = lease.execute(command);
      await settle();
      final client = provider.attempts.single.client;
      final session = client.sessions.single;
      expect(client.commands.single.operation, same(command));
      expect(client.commands.single.isExecutor, isFalse);
      expect(
        utf8.decode(session.received.expand((chunk) => chunk).toList()),
        command.script,
      );
      session.output.add(Uint8List.fromList(utf8.encode('key\tdmFsdWU=\n')));
      session.errors.add(Uint8List.fromList(utf8.encode('private stderr')));
      await session.finish();
      expect((await attempt.result).textRows({'key'}), {'key': 'value'});
      await attempt.settled;
      await pool.close();
      expect(pool.activeTransports, 0);
    },
  );

  test(
    'cancellation retains a shared channel slot until physical completion',
    () async {
      final provider = io.Io(), pool = SshTransportPool(io: provider);
      final lease = await io.connect(pool);
      provider.attempts.single.client.onExecute = (session, _) {
        session.autoClose = false;
      };
      final calls = [
        for (var i = 0; i < 4; i++) lease.execute(DirectSshCommand.inspect()),
      ];
      await settle();
      final firstFailure = expectLater(
        calls.first.result,
        failure(SshTransportCode.CANCELLED),
      );
      calls.first.cancel();
      await firstFailure;
      expect(
        () => lease.read(const SshReadRequest.system()),
        failure(SshTransportCode.RESOURCE_LIMIT),
      );
      expect(
        () => lease.execute(DirectSshCommand.inspect()),
        failure(SshTransportCode.RESOURCE_LIMIT),
      );
      final client = provider.attempts.single.client;
      await client.sessions.first.finish();
      await calls.first.settled;
      final replacement = lease.execute(DirectSshCommand.inspect());
      final rest = [...calls.skip(1), replacement];
      final failures = [
        for (final call in rest)
          expectLater(call.result, failure(SshTransportCode.CANCELLED)),
      ];
      for (final call in rest) {
        call.cancel();
      }
      await settle();
      for (final session in client.sessions.skip(1)) {
        await session.finish();
      }
      await Future.wait(failures);
      await Future.wait([for (final call in rest) call.settled]);
      await pool.close();
    },
  );

  test(
    'oversized output stays explicitly incomplete even with exit zero',
    () async {
      final provider = io.Io(), pool = SshTransportPool(io: provider);
      final lease = await io.connect(pool);
      final command = DirectSshCommand.inspect();
      final call = lease.execute(command);
      await settle();
      final session = provider.attempts.single.client.sessions.single;
      session.output.add(Uint8List(command.outputLimit + 1));
      final output = await call.result;
      expect(output.truncated, isTrue);
      expect(output.bytes.length, command.outputLimit);
      expect(() => output.textRows({'key'}), throwsA(isA<DirectSshFailure>()));
      await call.settled;
      await pool.close();
    },
  );

  test(
    'session failure while stdin drains poisons rather than frees the pool',
    () async {
      final provider = io.Io(), pool = SshTransportPool(io: provider);
      final lease = await io.connect(pool);
      provider.attempts.single.client.onExecute = (session, _) {
        session.stdinPause = Completer<void>();
      };
      final call = lease.execute(DirectSshCommand.inspect());
      final resultFailure = expectLater(call.result, failure());
      final drainFailure = expectLater(call.settled, failure());
      await settle();
      final session = provider.attempts.single.client.sessions.single;
      session.completed.completeError(StateError('PRIVATE_DRAIN_FAILURE'));
      await Future.wait([resultFailure, drainFailure]);
      expect(() => pool.reserve(), failure());
      await expectLater(pool.close(), failure());
      expect(pool.activeTransports, 1);
      session.stdinPause!.complete();
      await session.finish().then<void>((_) {}, onError: (Object _) {});
    },
  );
}
