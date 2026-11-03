import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/src/ssh_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/connections/host_signature.dart';
import 'package:serverdeck/profiles/credential_parser.dart';
import 'package:serverdeck/runtime/owned_work.dart';

typedef Vector = (SSHHostkeyType, Uint8List, Uint8List, Uint8List);
Vector vector([String name = 'ed25519']) {
  final parsed = parseOpenSshKey(
    File('test/fixtures/ssh/$name.txt').readAsBytesSync(),
  );
  try {
    final hash = Uint8List.fromList(List.filled(32, 7));
    return (
      name == 'ed25519' ? SSHHostkeyType.ed25519 : SSHHostkeyType.rsaSha256,
      parsed.key.toPublicKey().encode(),
      parsed.key.sign(hash).encode(),
      hash,
    );
  } finally {
    parsed.dispose();
  }
}

Future<bool> verify(
  HostSignatureVerifier verifier,
  Vector v, {
  WorkCancellation? cancellation,
  Duration timeout = OwnedWorkerPool.maxDuration,
}) => verifier.verify(
  v.$1,
  v.$2,
  v.$3,
  v.$4,
  cancellation: cancellation,
  timeout: timeout,
);
Future<void> turn() => Future<void>.delayed(Duration.zero);
Matcher reason(SSHSignatureFailure value) =>
    isA<SSHSignatureVerificationError>().having(
      (e) => e.reason,
      'reason',
      value,
    );

final class Worker implements HostSignatureWorker {
  final value = Completer<bool>(), exited = Completer<void>();
  bool failStop = false, failGetter = false;
  int stops = 0;
  @override
  Future<bool> get result {
    if (failGetter) throw StateError('SYNTHETIC_WORKER_DETAIL');
    return value.future;
  }

  @override
  Future<void> stop() {
    stops++;
    return failStop
        ? Future.error(StateError('SYNTHETIC_STOP_DETAIL'))
        : exited.future;
  }
}

void main() {
  for (final name in ['ed25519', 'rsa2048']) {
    test(
      'owned Dart isolate verifies $name and preserves caller buffers',
      () async {
        final verifier = HostSignatureVerifier(), v = vector(name);
        final key = Uint8List.fromList(v.$2),
            signature = Uint8List.fromList(v.$3),
            hash = Uint8List.fromList(v.$4);
        try {
          expect(await verify(verifier, v), isTrue);
          expect(v.$2, key);
          expect(v.$3, signature);
          expect(v.$4, hash);
        } finally {
          await verifier.dispose();
        }
        expect(verifier.activeWorkers, 0);
      },
    );
  }
  test(
    'bad cryptographic proof returns false without a host acceptance',
    () async {
      final verifier = HostSignatureVerifier(), v = vector();
      v.$3.last ^= 1;
      try {
        expect(await verify(verifier, v), isFalse);
      } finally {
        await verifier.dispose();
      }
    },
  );
  for (final name in ['ed25519', 'rsa2048']) {
    test(
      'format/bounds/legacy algorithm reject before any worker allocation: $name',
      () async {
        var starts = 0;
        final verifier = HostSignatureVerifier(
          spawn: (_) {
            starts++;
            throw StateError('unreachable');
          },
        );
        final v = vector(name);
        final cases = <Vector>[
          (v.$1, Uint8List(16385), v.$3, v.$4),
          (v.$1, v.$2, Uint8List(16385), v.$4),
          (v.$1, v.$2, v.$3, Uint8List(31)),
          (v.$1, Uint8List.fromList([...v.$2, 0]), v.$3, v.$4),
          (v.$1, v.$2, Uint8List.fromList([...v.$3, 0]), v.$4),
          (SSHHostkeyType.rsaSha1, v.$2, v.$3, v.$4),
        ];
        if (name == 'rsa2048') {
          final reader = SSHMessageReader(v.$2);
          final type = reader.readUtf8(),
              exponent = reader.readString(),
              modulus = reader.readString();
          final writer = SSHMessageWriter()
            ..writeUtf8(type)
            ..writeString(Uint8List.fromList([0, ...exponent]))
            ..writeString(modulus);
          cases.add((v.$1, writer.takeBytes(), v.$3, v.$4));
        }
        for (final input in cases) {
          expect(await verify(verifier, input), isFalse);
        }
        expect(starts, 0);
        expect(verifier.activeWorkers, 0);
        await verifier.dispose();
      },
    );
  }
  test('request copies clear on known spawn while reservation survives result until exit', () async {
    late HostSignatureRequest owned;
    final worker = Worker();
    final verifier = HostSignatureVerifier(
      spawn: (r) async {
        owned = r;
        return worker;
      },
    );
    final v = vector();
    final originalKey = Uint8List.fromList(v.$2);
    final result = verify(verifier, v);
    await turn();
    for (final bytes in [owned.key, owned.signature, owned.hash]) {
      expect(bytes.every((b) => b == 0), isTrue);
    }
    worker.value.complete(true);
    expect(await result, isTrue);
    expect(verifier.activeWorkers, 1);
    expect(v.$2, originalKey);
    worker.exited.complete();
    await verifier.drain();
    expect(verifier.activeWorkers, 0);
    await verifier.dispose();
  });
  test(
    'four successful jobs still reserve capacity until every exit is confirmed',
    () async {
      final workers = <Worker>[];
      final verifier = HostSignatureVerifier(
        spawn: (_) async {
          final worker = Worker();
          workers.add(worker);
          return worker;
        },
      );
      final futures = List.generate(4, (_) => verify(verifier, vector()));
      await turn();
      for (final worker in workers) {
        worker.value.complete(true);
      }
      expect(await Future.wait(futures), [true, true, true, true]);
      await expectLater(
        verify(verifier, vector()),
        throwsA(reason(SSHSignatureFailure.exhausted)),
      );
      for (final worker in workers) {
        worker.exited.complete();
      }
      await verifier.drain();
      await verifier.dispose();
    },
  );
  test(
    'cancelled pending spawns retain four slots and stop every late worker',
    () async {
      final starts = <Completer<HostSignatureWorker>>[];
      final verifier = HostSignatureVerifier(
        spawn: (_) {
          final started = Completer<HostSignatureWorker>();
          starts.add(started);
          return started.future;
        },
      );
      final tokens = List.generate(4, (_) => WorkCancellation());
      final outcomes = [
        for (final token in tokens)
          expectLater(
            verify(verifier, vector(), cancellation: token),
            throwsA(reason(SSHSignatureFailure.cancelled)),
          ),
      ];
      await turn();
      for (final token in tokens) {
        token.cancel();
      }
      await Future.wait(outcomes);
      expect(verifier.activeWorkers, 4);
      await expectLater(
        verify(verifier, vector()),
        throwsA(reason(SSHSignatureFailure.exhausted)),
      );
      final workers = List.generate(4, (_) => Worker());
      for (var i = 0; i < 4; i++) {
        starts[i].complete(workers[i]);
      }
      await turn();
      for (final worker in workers) {
        expect(worker.stops, 1);
        worker.exited.complete();
        worker.value.complete(true);
      }
      await verifier.drain();
      expect(verifier.activeWorkers, 0);
      await verifier.dispose();
    },
  );
  test('deadline is clamped and stop failure keeps reservation until cleanup retry', () async {
    final worker = Worker()..failStop = true;
    late void Function() expire;
    Duration? duration;
    final verifier = HostSignatureVerifier(
      spawn: (_) async => worker,
      schedule: (d, callback) {
        duration = d;
        expire = callback;
        return () {};
      },
    );
    final failed = expectLater(
      verify(verifier, vector(), timeout: const Duration(minutes: 1)),
      throwsA(reason(SSHSignatureFailure.timeout)),
    );
    await turn();
    expire();
    await failed;
    await turn();
    expect(duration, const Duration(seconds: 30));
    expect(verifier.activeWorkers, 1);
    expect(worker.stops, 1);
    worker.failStop = false;
    final draining = verifier.drain();
    expect(worker.stops, 2);
    worker.exited.complete();
    await draining;
    await verifier.dispose();
  });
  test(
    'spawn failure is fixed exhausted error and clears request copies',
    () async {
      late HostSignatureRequest owned;
      final verifier = HostSignatureVerifier(
        spawn: (r) {
          owned = r;
          throw StateError('SYNTHETIC_WORKER_DETAIL');
        },
      );
      await expectLater(
        verify(verifier, vector()),
        throwsA(reason(SSHSignatureFailure.exhausted)),
      );
      expect(owned.key.every((b) => b == 0), isTrue);
      expect(verifier.activeWorkers, 0);
      await verifier.dispose();
    },
  );
  for (final getter in [false, true]) {
    test(
      'worker error getter=$getter is sanitized and still waits for exit',
      () async {
        final worker = Worker()..failGetter = getter;
        final verifier = HostSignatureVerifier(spawn: (_) async => worker);
        final result = verify(verifier, vector());
        await turn();
        if (!getter)
          worker.value.completeError(StateError('SYNTHETIC_WORKER_DETAIL'));
        expect(await result, isFalse);
        expect(verifier.activeWorkers, 1);
        expect(worker.stops, 1);
        worker.exited.complete();
        await verifier.drain();
        await verifier.dispose();
      },
    );
  }
  test('shutdown cancels accepted work, blocks admission and drains confirmed exit', () async {
    final worker = Worker();
    final verifier = HostSignatureVerifier(spawn: (_) async => worker);
    final failed = expectLater(
      verify(verifier, vector()),
      throwsA(reason(SSHSignatureFailure.cancelled)),
    );
    await turn();
    var disposed = false;
    final cleanup = verifier.dispose().then((_) {
      disposed = true;
    });
    await failed;
    await turn();
    expect(disposed, isFalse);
    await expectLater(
      verify(verifier, vector()),
      throwsA(reason(SSHSignatureFailure.stopping)),
    );
    worker.exited.complete();
    await cleanup;
    expect(verifier.activeWorkers, 0);
  });
  test('pre-cancelled and zero-budget jobs never spawn', () async {
    var starts = 0;
    final verifier = HostSignatureVerifier(
      spawn: (_) {
        starts++;
        throw StateError('unreachable');
      },
    );
    await expectLater(
      verify(verifier, vector(), cancellation: WorkCancellation()..cancel()),
      throwsA(reason(SSHSignatureFailure.cancelled)),
    );
    await expectLater(
      verify(verifier, vector(), timeout: Duration.zero),
      throwsA(reason(SSHSignatureFailure.timeout)),
    );
    expect(starts, 0);
    await verifier.dispose();
  });
  test(
    'synchronous deadline and scheduler failure release request without spawn',
    () async {
      for (final timerThrows in [false, true]) {
        var starts = 0;
        final verifier = HostSignatureVerifier(
          spawn: (_) {
            starts++;
            throw StateError('unreachable');
          },
          schedule: (_, callback) {
            if (timerThrows) throw StateError('SYNTHETIC_TIMER_DETAIL');
            callback();
            return () {};
          },
        );
        await expectLater(
          verify(verifier, vector()),
          throwsA(
            reason(
              timerThrows
                  ? SSHSignatureFailure.exhausted
                  : SSHSignatureFailure.timeout,
            ),
          ),
        );
        expect(starts, 0);
        expect(verifier.activeWorkers, 0);
        await verifier.dispose();
      }
    },
  );
}
