import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:serverdeck_engine/remote/connections.dart';
import 'package:serverdeck_engine/remote/direct_ssh.dart';
import 'package:test/test.dart';

import '../support/schema3_fixture.dart' as fixture;
import '../support/remote_read_setup.dart' as mcpFixture;
import 'connection_drain_test.dart' as connection;
import 'direct_ssh_jobs_test.dart' show attemptFixture;
import 'ssh_pool_lifecycle_test.dart' show settle;

Matcher failed(String code) => throwsA(
  isA<StateError>().having((error) => error.message, 'safe code', code),
);

void main() {
  test('cancel before first write rejects handoff and suppresses delayed native dispatch', () async {
    final s = await connection.Setup.create(), context = await s.context();
    final held = s.runtime.proof = Completer<void>();
    final work = s.connections.executeDirectOwner(
      context,
      fixture.profile,
      DirectSshCommand.inspect(),
    );
    final handoff = expectLater(work.dispatched, failed('CANCELLED'));
    await settle();
    final stopping = work.cancelInterest();
    await handoff;
    held.complete();
    s.runtime.proof = null;
    await stopping;
    expect(s.io.attempts.single.client.sessions, isEmpty);
  });
  test('dispatch handoff follows first stdin add while ACK and physical work remain owned', () async {
    final s = await connection.Setup.create(), context = await s.context();
    s.io.attempts.single.client.onExecute = (session, _) {
      session.onInput = (_) {};
    };
    final work = s.connections.executeDirectOwner(
      context,
      fixture.profile,
      DirectSshCommand.inspect(),
    );
    var result = false, done = false;
    work.result
        .then<void>((_) => result = true, onError: (Object _, StackTrace __) {})
        .ignore();
    work.done.then((_) => done = true).ignore();
    await work.dispatched;
    await settle();
    expect(s.io.attempts.single.client.sessions.single.received, hasLength(1));
    expect(result, isFalse);
    expect(done, isFalse);
    s.io.attempts.single.client.sessions.single.output.add(
      Uint8List.fromList(ascii.encode('facts')),
    );
    await s.io.attempts.single.client.sessions.single.finish();
    await work.done;
    expect(result, isTrue);
  });
  test('unproved physical command drain poisons shared service and remains charged', () async {
    final s = await connection.Setup.create(), context = await s.context();
    s.io.attempts.single.client.onExecute = (session, _) {
      session.stdinPause = Completer<void>();
    };
    final work = s.connections.executeDirectOwner(
      context,
      fixture.profile,
      DirectSshCommand.inspect(),
    );
    work.result.ignore();
    final done = expectLater(work.done, failed('SERVICE_UNAVAILABLE'));
    await settle();
    final session = s.io.attempts.single.client.sessions.single;
    session.completed.completeError(StateError('PRIVATE_EARLY_COMPLETION'));
    await done;
    await expectLater(s.connections.suspend(), failed('SERVICE_UNAVAILABLE'));
    await expectLater(s.connections.close(), failed('SERVICE_UNAVAILABLE'));
    expect(s.pool.activeTransports, 1);
    expect(
      () => s.connections.executeDirectOwner(
        context,
        fixture.profile,
        DirectSshCommand.inspect(),
      ),
      failed('SERVICE_UNAVAILABLE'),
    );
  });
  test('late native proof suppresses output after detach and remains physically owned', () async {
    final s = await connection.Setup.create(), context = await s.context();
    final proof = Completer<void>();
    s.io.attempts.single.client.onExecute = (session, _) {
      session.onInput = (_) {
        s.runtime.proof = proof;
        session.output.add(
          Uint8List.fromList(ascii.encode('PRIVATE_LATE_OUTPUT')),
        );
        session.finish().ignore();
      };
    };
    final work = s.connections.executeDirectOwner(
      context,
      fixture.profile,
      DirectSshCommand.inspect(),
    );
    final result = expectLater(work.result, failed('CANCELLED'));
    await settle();
    final session = s.io.attempts.single.client.sessions.single;
    expect(session.received, hasLength(1));
    s.owner.close();
    await result;
    var done = false;
    work.done.then((_) => done = true).ignore();
    await settle();
    expect(done, isFalse);
    proof.complete();
    s.runtime.proof = null;
    await work.done;
    expect(done, isTrue);
  });

  test('new finite work is included in the shared48 intake limit', () async {
    final s = await connection.Setup.create(), context = await s.context();
    final proof = s.runtime.proof = Completer<void>();
    s.io.attempts.single.client.onExecute = (session, _) {
      session.onInput = (_) => session.finish().ignore();
    };
    final works = [
      for (var n = 0; n < 48; n++)
        s.connections.executeDirectOwner(
          context,
          fixture.profile,
          DirectSshCommand.inspect(),
        ),
    ];
    for (final work in works) {
      work.result.ignore();
    }
    expect(
      () => s.connections.executeDirectOwner(
        context,
        fixture.profile,
        DirectSshCommand.inspect(),
      ),
      failed('RESOURCE_LIMIT'),
    );
    proof.complete();
    s.runtime.proof = null;
    await Future.wait(works.map((work) => work.done));
  });
  test(
    'MCP read uses the same direct path without enrollment and cannot mutate',
    () async {
      final s = await mcpFixture.Setup.create(), client = await s.mcp();
      await s.attach(client);
      s.io.attempts.single.client.onExecute = (session, _) {
        session.onInput = (_) {
          session.output.add(
            Uint8List.fromList(ascii.encode('metadata bytes')),
          );
          session.finish().ignore();
        };
      };
      final work = s.connections.executeDirectMcp(
        client.context,
        fixture.profile,
        DirectSshCommand.inspect(),
      );
      expect(ascii.decode((await work.result).output.bytes), 'metadata bytes');
      await work.done;
      expect(s.store.enrollmentReads, 0);
      final attempt = await attemptFixture();
      expect(
        () => s.connections.executeDirectMcp(
          client.context,
          fixture.profile,
          DirectSshCommand.reserveAttempt(attempt),
        ),
        failed('FORBIDDEN'),
      );
      expect(s.io.attempts.single.client.sessions, hasLength(1));
    },
  );

  test(
    'grant revoke at the final continuation prevents script bytes',
    () async {
      final s = await mcpFixture.Setup.create(), client = await s.mcp();
      await s.attach(client);
      s.io.attempts.single.client.onExecute = (_, _) {};
      final work = s.connections.executeDirectMcp(
        client.context,
        fixture.profile,
        DirectSshCommand.inspect(),
        beforeDispatch: s.store.revoke,
      );
      await expectLater(work.result, failed('CANCELLED'));
      await work.done;
      expect(s.io.attempts.single.client.sessions.single.received, isEmpty);
      expect(() => client.context.authorize(), failed('UNAUTHORIZED'));
    },
  );

  test(
    'owner method restrictions distinguish reserve, cancel and reconciliation',
    () async {
      final s = await connection.Setup.create(),
          attempt = await attemptFixture();
      for (final method in [
        'plans.create',
        'jobs.cancel',
        'jobs.reconcile',
        'jobs.get',
      ]) {
        final request = s.owner.reserve(method);
        await s.owner.admit(request);
        final context = request.ownerAutomationContext();
        request.complete();
        expect(
          () => s.connections.executeDirectAutomationOwner(
            context,
            fixture.profile,
            DirectSshCommand.reserveAttempt(attempt),
          ),
          failed('FORBIDDEN'),
        );
        if (method != 'jobs.cancel') {
          expect(
            () => s.connections.executeDirectAutomationOwner(
              context,
              fixture.profile,
              DirectSshCommand.stopAttempt(attempt),
            ),
            failed('FORBIDDEN'),
          );
        }
      }
      expect(s.io.attempts.single.client.sessions, isEmpty);
    },
  );

  test('an explicit continuation refusal retains its safe reason and sends no bytes', () async {
    final s = await connection.Setup.create(), context = await s.context();
    final work = s.connections.executeDirectOwner(
      context,
      fixture.profile,
      DirectSshCommand.inspect(),
      beforeDispatch: () {
        throw StateError('FORBIDDEN');
      },
    );
    await expectLater(work.result, failed('FORBIDDEN'));
    await work.done;
    expect(s.io.attempts.single.client.sessions.single.received, isEmpty);
  });

  test(
    'connection pause at final continuation retires the opened direct channel',
    () async {
      final s = await connection.Setup.create(), context = await s.context();
      final work = s.connections.executeDirectOwner(
        context,
        fixture.profile,
        DirectSshCommand.inspect(),
        beforeDispatch: () {
          s.connections.suspend().ignore();
        },
      );
      await expectLater(work.result, failed('SERVICE_UNAVAILABLE'));
      await work.done;
      expect(s.io.attempts.single.client.sessions.single.received, isEmpty);
    },
  );
  test('finite direct exec revalidates native proof after channel opens before script bytes', () async {
    final s = await connection.Setup.create(), context = await s.context();
    final proof = Completer<void>();
    s.io.attempts.single.client.onExecute = (session, _) {
      s.runtime.proof = proof;
      session.onInput = (_) {
        session.output.add(Uint8List.fromList(ascii.encode('finite answer')));
        session.finish().ignore();
      };
    };
    var dispatches = 0;
    final work = s.connections.executeDirectOwner(
      context,
      fixture.profile,
      DirectSshCommand.inspect(),
      beforeDispatch: () {
        dispatches++;
      },
    );
    await settle();
    final session = s.io.attempts.single.client.sessions.single;
    expect(session.received, isEmpty);
    expect(dispatches, 0);
    proof.complete();
    s.runtime.proof = null;
    final value = await work.result;
    await work.done;
    expect(value.identity.profileId, fixture.profile);
    expect(ascii.decode(value.output.bytes), 'finite answer');
    expect(dispatches, 1);
    expect(session.received, hasLength(1));
    expect(
      utf8.decode(session.received.single),
      DirectSshCommand.inspect().script,
    );
  });

  test('native proof failure after channel open sends no script', () async {
    final s = await connection.Setup.create(), context = await s.context();
    final proof = Completer<void>();
    s.io.attempts.single.client.onExecute = (_, _) => s.runtime.proof = proof;
    final work = s.connections.executeDirectOwner(
      context,
      fixture.profile,
      DirectSshCommand.inspect(),
    );
    // Native failure detaches the session; detach cancels its work first.
    final result = expectLater(work.result, failed('CANCELLED'));
    await settle();
    final session = s.io.attempts.single.client.sessions.single;
    expect(session.received, isEmpty);
    proof.completeError(StateError('PRIVATE_NATIVE_PROOF_FAILURE'));
    s.runtime.proof = null;
    await result;
    await work.done;
    expect(session.received, isEmpty);
  });

  test('owner read identity cannot dispatch a mutating command', () async {
    final s = await connection.Setup.create(), context = await s.context();
    final attempt = await attemptFixture();
    expect(
      () => s.connections.executeDirectOwner(
        context,
        fixture.profile,
        DirectSshCommand.reserveAttempt(attempt),
      ),
      failed('FORBIDDEN'),
    );
    expect(s.io.attempts.single.client.sessions, isEmpty);
  });

  test(
    'detached owner at the final synchronous continuation sends no script',
    () async {
      final s = await connection.Setup.create(), context = await s.context();
      final work = s.connections.executeDirectOwner(
        context,
        fixture.profile,
        DirectSshCommand.inspect(),
        beforeDispatch: s.owner.close,
      );
      await expectLater(work.result, failed('CANCELLED'));
      await work.done;
      expect(s.io.attempts.single.client.sessions.single.received, isEmpty);
    },
  );

  test(
    'physical command drain remains owned after logical cancellation',
    () async {
      final s = await connection.Setup.create(), context = await s.context();
      s.io.attempts.single.client.onExecute = (session, _) =>
          session.autoClose = false;
      final work = s.connections.executeDirectOwner(
        context,
        fixture.profile,
        DirectSshCommand.inspect(),
      );
      final result = expectLater(work.result, failed('CANCELLED'));
      await settle();
      var done = false;
      work.done.then((_) => done = true).ignore();
      final cancel = work.cancelInterest();
      await result;
      await settle();
      expect(done, isFalse);
      await s.io.attempts.single.client.sessions.single.finish();
      await cancel;
      expect(done, isTrue);
    },
  );
}
