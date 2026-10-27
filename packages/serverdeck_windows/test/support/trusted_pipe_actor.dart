import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:serverdeck_windows/pipe_worker.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';
import 'package:serverdeck_windows/security.dart';

Future<void> denied(Future<Object?> Function() run) async {
  try {
    await run();
  } on StateError catch (e) {
    if (e.message == 'UNAUTHORIZED') return;
    rethrow;
  }
  throw StateError('EXPECTED_UNAUTHORIZED');
}

Future<void> main(List<String> args) async {
  final server = args[0].endsWith('server'),
      legacy = args[0].startsWith('legacy-'),
      operational = args[0].startsWith('operational-'),
      name = args[1],
      root = args[2];
  PipeWorker worker;
  try {
    worker = legacy
        ? (server
              ? await PipeWorker.createServer(name, currentUserSid())
              : await PipeWorker.openClient(name, currentUserSid()))
        : operational
        ? (server
              ? await PipeWorker.createOperationalServer(
                  name,
                  currentUserSid(),
                  root,
                )
              : await PipeWorker.openOperationalClient(
                  name,
                  currentUserSid(),
                  root,
                ))
        : server
        ? await PipeWorker.createTrustedServer(name, currentUserSid(), root)
        : await PipeWorker.openTrustedClient(name, currentUserSid(), root);
  } on StateError catch (e) {
    stdout.writeln('STARTUP_ERR:${e.message}');
    return;
  }
  TrustedPipePeer? peer, original;
  OperationalPublicationGate? gate;
  OperationalPublicationLease? lease;
  Future<String>? pendingRead, pendingAccept, pendingWrite, pendingDrain;
  Future<String> result(Future<Object?> operation) async {
    try {
      await operation;
      return 'OK';
    } on StateError catch (e) {
      return e.message.toString();
    }
  }

  var observedAdmissions = 0;
  var observedNativeSettled = false, observedPublicSettled = false;
  Future<String>? observedNative, observedWrite;
  void beginObservedWrite(
    Future<void> Function(void Function(Future<void>)) issue, {
    bool throwObserver = false,
  }) {
    observedAdmissions = 0;
    observedNativeSettled = false;
    observedPublicSettled = false;
    observedNative = null;
    observedWrite = null;
    final writing = issue((actual) {
      observedAdmissions++;
      // Install an error handler before deliberately throwing. This records
      // the supplied actual operation, independently of the public write.
      observedNative = actual.then<String>(
        (_) {
          observedNativeSettled = true;
          return 'OK';
        },
        onError: (Object error, StackTrace stack) {
          observedNativeSettled = true;
          if (error is StateError) return error.message.toString();
          Error.throwWithStackTrace(error, stack);
        },
      );
      if (throwObserver) throw ArgumentError('OWNED_OBSERVER_FAILURE');
    });
    observedWrite = result(writing).then((code) {
      observedPublicSettled = true;
      return observedNativeSettled ? code : 'EARLY_COMPLETION:$code';
    });
    observedWrite!.ignore();
    // Admission notification must happen before peer.write returns its future,
    // even when the caller's observer throws or the worker later rejects it.
    if (observedAdmissions != 1 || observedNative == null)
      throw StateError('EXPECTED_SYNCHRONOUS_WRITE_ADMISSION');
  }

  void requireObservedPending() {
    if (observedAdmissions != 1 ||
        observedNativeSettled ||
        observedPublicSettled)
      throw StateError('EXPECTED_NATIVE_AND_PUBLIC_WRITE_PENDING');
  }

  stdout.writeln('READY');
  await stdout.flush();
  try {
    await for (final command
        in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      try {
        switch (command) {
          case 'bootstrap-denied':
            final bootstrap = TrustedBootstrapClient(
              pipe: worker,
              generation: '10000000-0000-4000-8000-000000000001',
              token: List<int>.filled(32, 0),
            );
            await denied(bootstrap.authenticate);
            stdout.writeln('BOOTSTRAP_DENIED');
          case 'wrong-peer':
            await denied(() => worker.verifyOperationalPeer());
            stdout.writeln('WRONG_PEER_DENIED');
          case 'trusted-denied':
            await denied(() => worker.verifyTrustedPeer());
            stdout.writeln('TRUSTED_DENIED');
          case 'verify-operational':
            final old = await worker.verifyOperationalPeer();
            stdout.writeln('OPERATIONAL:${old.role.name}');
          case 'gate':
            gate = await peer!.publicationGate(
              '10000000-0000-4000-8000-000000000001',
            );
            stdout.writeln('GATE:${gate.localRole.name}');
          case 'gate-acquire':
            lease = await gate!.acquire();
            stdout.writeln('GATE_ACQUIRED');
          case 'gate-timeout':
            try {
              final unexpected = await gate!.acquire(
                deadline: const Duration(milliseconds: 40),
              );
              await unexpected.close();
              throw StateError('EXPECTED_GATE_TIMEOUT');
            } on StateError catch (error) {
              if (error.message != 'TIMEOUT') rethrow;
            }
            stdout.writeln('GATE_TIMEOUT');
          case 'gate-release':
            await lease!.close();
            lease = null;
            stdout.writeln('GATE_RELEASED');
          case 'gate-close':
            await gate!.close();
            gate = null;
            stdout.writeln('GATE_CLOSED');
          case 'accept':
            await worker.accept(deadline: const Duration(seconds: 3));
            stdout.writeln('ACCEPTED');
          case 'listen':
            pendingAccept = result(
              worker.accept(deadline: const Duration(seconds: 3)),
            );
            stdout.writeln('LISTENING');
          case 'accept-result':
            stdout.writeln('RESULT:${await pendingAccept!}');
          case 'verify':
            peer = await worker.verifyTrustedPeer();
            original ??= peer;
            stdout.writeln('ROLE:${peer.role.name}:${peer.buildId}');
          case 'raw':
            await denied(() => worker.read(count: 1));
            await denied(() => worker.write([99]));
            await denied(() => worker.drainOutput());
            await denied(
              () => worker.verifyPeer(currentUserSid(), 'claimed', '0' * 64),
            );
            stdout.writeln('RAW_DENIED');
          case 'old':
            await denied(() => original!.revalidate());
            await denied(() => original!.read(count: 1));
            await denied(() => original!.write([99]));
            await denied(() => original!.drainOutput());
            stdout.writeln('STALE_DENIED');
          case 'old-disconnect':
            await denied(() => original!.disconnect());
            stdout.writeln('STALE_DISCONNECT_DENIED');
          case 'write':
            if (legacy) {
              await worker.write([server ? 43 : 42]);
            } else {
              await peer!.write([server ? 43 : 42]);
            }
            stdout.writeln('WROTE');
          case 'read':
            final bytes = await peer!.read(count: 1);
            stdout.writeln('DATA:${bytes.single}');
          case 'drain':
            await peer!.drainOutput();
            stdout.writeln('DRAINED');
          case 'observed-size-refusal':
            var admissions = 0;
            void observe(Future<void> actual) {
              admissions++;
              actual.ignore();
            }
            final empty = await result(
              peer!.write([], observeNativeCompletion: observe),
            );
            final oversized = await result(
              peer.write(
                Uint8List(8 * 1024 * 1024 + 5),
                observeNativeCompletion: observe,
              ),
            );
            stdout.writeln('REFUSED:$empty,$oversized:$admissions');
          case 'observed-pending' || 'observed-throw':
            beginObservedWrite(
              (observe) => peer!.write(
                Uint8List(8 * 1024 * 1024),
                observeNativeCompletion: observe,
              ),
              throwObserver: command == 'observed-throw',
            );
            // Ordered worker messages: verification follows the admitted write's
            // pre-IO guard. No reader consumes this 8 MiB write yet.
            await worker.verifyTrustedPeer();
            await Future<void>.delayed(const Duration(milliseconds: 100));
            requireObservedPending();
            stdout.writeln('OBSERVED_PENDING:$observedAdmissions');
          case 'observed-quota':
            beginObservedWrite(
              (observe) => peer!.write(
                Uint8List(8 * 1024 * 1024),
                observeNativeCompletion: observe,
              ),
            );
            await worker.verifyTrustedPeer();
            pendingRead = result(peer!.read(count: 1));
            pendingDrain = result(peer.drainOutput());
            // All three commands are admitted before this fourth write. A
            // caller-side quota refusal must supply no actual completion.
            var refusedAdmissions = 0;
            final refused = await result(
              peer.write(
                [99],
                observeNativeCompletion: (actual) {
                  refusedAdmissions++;
                  actual.ignore();
                },
              ),
            );
            await Future<void>.delayed(const Duration(milliseconds: 50));
            requireObservedPending();
            stdout.writeln('QUOTA:$refused:$refusedAdmissions');
          case 'observed-result':
            stdout.writeln(
              'OBSERVED:$observedAdmissions:${await observedNative!}:${await observedWrite!}',
            );
          case 'observed-quota-result':
            stdout.writeln(
              'OBSERVED:$observedAdmissions:${await observedNative!}:${await observedWrite!}',
            );
            stdout.writeln(
              'RESULT:${await pendingRead!},${await pendingDrain!}',
            );
          case 'observed-old' || 'observed-old-throw':
            beginObservedWrite(
              (observe) =>
                  original!.write([99], observeNativeCompletion: observe),
              throwObserver: command == 'observed-old-throw',
            );
            stdout.writeln(
              'OBSERVED:$observedAdmissions:${await observedNative!}:${await observedWrite!}',
            );
          case 'read-observed':
            var remaining = 8 * 1024 * 1024;
            while (remaining > 0) {
              final bytes = await peer!.read(
                count: remaining < 65536 ? remaining : 65536,
              );
              if (bytes.isEmpty || bytes.any((byte) => byte != 0))
                throw StateError('EXPECTED_SINGLE_ZERO_WRITE');
              remaining -= bytes.length;
            }
            stdout.writeln('READ_OBSERVED:8388608');
          case 'observed-close-refusal':
            await worker.close();
            var admissions = 0;
            final refused = await result(
              peer!.write(
                [99],
                observeNativeCompletion: (actual) {
                  admissions++;
                  actual.ignore();
                },
              ),
            );
            stdout.writeln('REFUSED:$refused:$admissions');
            await stdout.flush();
            return;
          case 'pending':
            pendingRead = result(peer!.read(count: 1));
            stdout.writeln('PENDING');
          case 'pending-result':
            stdout.writeln('RESULT:${await pendingRead!}');
          case 'full':
            pendingWrite = result(peer!.write(Uint8List(8 * 1024 * 1024)));
            await Future<void>.delayed(const Duration(milliseconds: 100));
            pendingRead = result(peer.read(count: 1));
            pendingDrain = result(peer.drainOutput());
            await Future<void>.delayed(const Duration(milliseconds: 50));
            if (await result(worker.verifyTrustedPeer()) != 'RESOURCE_LIMIT')
              throw StateError('EXPECTED_FULL_PENDING_QUOTA');
            stdout.writeln('FULL_PENDING');
          case 'full-result':
            stdout.writeln(
              'RESULT:${await pendingWrite!},${await pendingRead!},${await pendingDrain!}',
            );
          case 'timeout':
            await peer!.read(
              count: 1,
              deadline: const Duration(milliseconds: 30),
            );
            throw StateError('EXPECTED_TIMEOUT');
          case 'disconnect':
            await worker.disconnect();
            stdout.writeln('DISCONNECTED');
          case 'disconnect-peer':
            await peer!.disconnect();
            stdout.writeln('DISCONNECTED');
          case 'close':
            await worker.close();
            stdout.writeln('CLOSED');
            await stdout.flush();
            return;
          default:
            throw StateError('INVALID_FIXTURE_COMMAND');
        }
      } on StateError catch (e) {
        stdout.writeln('ERR:${e.message}');
      }
      await stdout.flush();
    }
  } finally {
    if (lease != null) await lease.close();
    if (gate != null) await gate.close();
    await worker.close();
  }
}
