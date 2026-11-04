import 'package:serverdeck/runtime/owned_work.dart';

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/profiles/credential_parser.dart';
import 'package:serverdeck/profiles/key_parse_worker.dart';

final class FakeWorker implements KeyParseWorker {
  final parsed = Completer<ParsedPrivateKey>();
  final exited = Completer<void>();
  int stops = 0;
  bool failStop = false;
  @override
  Future<ParsedPrivateKey> get result => parsed.future;
  @override
  Future<void> stop() {
    stops++;
    return failStop
        ? Future.error(StateError('synthetic stop'))
        : exited.future;
  }
}

Matcher code(FailureCode value) =>
    isA<OperationFailure>().having((e) => e.code, 'code', value);
Future<void> turn() => Future<void>.delayed(Duration.zero);
Uint8List vector() => File('test/fixtures/ssh/ed25519.txt').readAsBytesSync();

void main() {
  test('adapter parses a synthetic key in an owned Dart isolate', () async {
    final parser = CancellableKeyParser();
    final parsed = await parser.parse(vector());
    expect(parsed.inspection.keyType, 'ssh-ed25519');
    final direct = parsePrivateKey(vector());
    final message = Uint8List.fromList([1, 2, 3]);
    expect(
      parsed.key.sign(message).encode(),
      direct.key.sign(message).encode(),
    );
    direct.dispose();
    parsed.dispose();
    await parser.dispose();
    expect(parser.activeWorkers, 0);
  });

  test(
    'success clears request but reserves slot until exit is confirmed',
    () async {
      final worker = FakeWorker();
      late KeyParseRequest request;
      final parser = CancellableKeyParser(
        spawn: (r) async {
          request = r;
          return worker;
        },
      );
      final original = vector();
      final result = parser.parse(original, passphrase: 'synthetic');
      await turn();
      expect(request.bytes.every((b) => b == 0), isTrue);
      expect(request.passphrase, isNull);
      final parsed = parsePrivateKey(original);
      worker.parsed.complete(parsed);
      expect(await result, same(parsed));
      expect(parser.activeWorkers, 1);
      worker.exited.complete();
      await parser.drain();
      expect(parser.activeWorkers, 0);
      expect(original, vector());
      parsed.dispose();
      await parser.dispose();
    },
  );

  test(
    'cancelled pending spawn holds capacity and stops a late worker',
    () async {
      final starts = <Completer<KeyParseWorker>>[];
      final requests = <KeyParseRequest>[];
      final parser = CancellableKeyParser(
        spawn: (r) {
          requests.add(r);
          final start = Completer<KeyParseWorker>();
          starts.add(start);
          return start.future;
        },
      );
      final cancellations = List.generate(4, (_) => WorkCancellation());
      final expectations = [
        for (final c in cancellations)
          expectLater(
            parser.parse(vector(), cancellation: c),
            throwsA(isA<WorkCancelled>()),
          ),
      ];
      await turn();
      for (final c in cancellations) {
        c.cancel();
      }
      await Future.wait(expectations);
      expect(parser.activeWorkers, 4);
      await expectLater(
        parser.parse(vector()),
        throwsA(code(FailureCode.resourceExhausted)),
      );
      final workers = List.generate(4, (_) => FakeWorker());
      for (var i = 0; i < 4; i++) {
        starts[i].complete(workers[i]);
      }
      await turn();
      for (final w in workers) {
        expect(w.stops, 1);
        w.exited.complete();
      }
      await parser.drain();
      expect(parser.activeWorkers, 0);
      expect(requests.every((r) => r.bytes.every((b) => b == 0)), isTrue);
      // A cancelled worker's late key is disposed rather than published.
      final lateKey = parsePrivateKey(vector());
      workers.first.parsed.complete(lateKey);
      await turn();
      expect(() => lateKey.key, throwsStateError);
      await parser.dispose();
    },
  );

  test(
    'deadline is clamped and a failed stop retains slot for cleanup retry',
    () async {
      final worker = FakeWorker()..failStop = true;
      late void Function() expire;
      Duration? duration;
      var detached = false;
      final parser = CancellableKeyParser(
        spawn: (_) async => worker,
        schedule: (d, callback) {
          duration = d;
          expire = callback;
          return () {
            detached = true;
          };
        },
      );
      final failure = expectLater(
        parser.parse(vector(), timeout: const Duration(minutes: 1)),
        throwsA(code(FailureCode.timeout)),
      );
      await turn();
      expire();
      await failure;
      await turn();
      expect(duration, const Duration(seconds: 30));
      expect(detached, isTrue);
      expect(parser.activeWorkers, 1);
      expect(worker.stops, 1);
      worker.failStop = false;
      final drained = parser.drain();
      expect(worker.stops, 2);
      worker.exited.complete();
      await drained;
      expect(parser.activeWorkers, 0);
      await parser.dispose();
    },
  );

  test(
    'spawn failure drops request and does not expose factory error',
    () async {
      late KeyParseRequest request;
      final parser = CancellableKeyParser(
        spawn: (r) {
          request = r;
          throw StateError('SYNTHETIC_SECRET');
        },
      );
      await expectLater(
        parser.parse(vector()),
        throwsA(code(FailureCode.resourceExhausted)),
      );
      expect(request.bytes.every((b) => b == 0), isTrue);
      expect(parser.activeWorkers, 0);
      await parser.dispose();
    },
  );

  test(
    'rejects cancelled, oversized, expired and stopped requests before spawn',
    () async {
      var starts = 0;
      final parser = CancellableKeyParser(
        spawn: (_) {
          starts++;
          throw StateError('unreachable');
        },
      );
      final cancelled = WorkCancellation()..cancel();
      await expectLater(
        parser.parse(vector(), cancellation: cancelled),
        throwsA(isA<WorkCancelled>()),
      );
      await expectLater(
        parser.parse(Uint8List(1024 * 1024 + 1)),
        throwsA(code(FailureCode.unsupportedKey)),
      );
      await expectLater(
        parser.parse(vector(), timeout: Duration.zero),
        throwsA(code(FailureCode.timeout)),
      );
      await expectLater(
        parser.parse(vector(), passphrase: String.fromCharCode(0xd800)),
        throwsA(code(FailureCode.invalidArgument)),
      );
      await parser.stopAdmission();
      await expectLater(
        parser.parse(vector()),
        throwsA(code(FailureCode.shuttingDown)),
      );
      expect(starts, 0);
      await parser.dispose();
    },
  );

  test('shutdown cancels active jobs and waits for confirmed exits', () async {
    final worker = FakeWorker();
    final parser = CancellableKeyParser(spawn: (_) async => worker);
    final failure = expectLater(
      parser.parse(vector()),
      throwsA(isA<WorkCancelled>()),
    );
    await turn();
    var disposed = false;
    final disposal = parser.dispose().then((_) {
      disposed = true;
    });
    await failure;
    await turn();
    expect(disposed, isFalse);
    worker.exited.complete();
    await disposal;
    expect(parser.activeWorkers, 0);
  });
}
