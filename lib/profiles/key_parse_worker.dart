import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../domain/models.dart';
import '../runtime/capability.dart';
import '../runtime/owned_work.dart';
import 'credential_parser.dart';
import 'key_envelope.dart';

typedef CredentialCancelled = WorkCancelled;
typedef CredentialCancellation = WorkCancellation;

final class KeyParseRequest {
  KeyParseRequest(Uint8List bytes, this.passphrase)
    : bytes = Uint8List.fromList(bytes);
  final Uint8List bytes;
  String? passphrase;
  void dispose() {
    bytes.fillRange(0, bytes.length, 0);
    passphrase = null;
  }
}

abstract interface class KeyParseWorker
    implements OwnedWorker<ParsedPrivateKey> {}

typedef SpawnKeyWorker = Future<KeyParseWorker> Function(
  KeyParseRequest request,
);
typedef ScheduleKeyDeadline = ScheduleOwnedDeadline;

abstract interface class KeyInspector {
  Future<KeyInspection> inspect(
    Uint8List bytes, {
    String? passphrase,
    CredentialCancellation? cancellation,
    Duration timeout = const Duration(seconds: 30),
  });
}

/// Bounded owner for CPU-bound parsing; no external processes or network.
final class CancellableKeyParser implements KeyInspector, RuntimeCapability {
  CancellableKeyParser({SpawnKeyWorker? spawn, ScheduleKeyDeadline? schedule})
    : _pool = OwnedWorkerPool<KeyParseRequest, ParsedPrivateKey>(
        id: 'credential-parser',
        spawn: spawn ?? spawnKeyParseWorker,
        disposeRequest: (request) => request.dispose(),
        disposeLateResult: (result) => result.dispose(),
        schedule: schedule,
      );
  final OwnedWorkerPool<KeyParseRequest, ParsedPrivateKey> _pool;
  static const maxWorkers = OwnedWorkerPool.maxWorkers;
  static const maxDuration = OwnedWorkerPool.maxDuration;
  int get activeWorkers => _pool.activeWorkers;
  @override
  String get id => _pool.id;

  Future<ParsedPrivateKey> parse(
    Uint8List bytes, {
    String? passphrase,
    CredentialCancellation? cancellation,
    Duration timeout = maxDuration,
  }) {
    if (_pool.isStopped)
      return Future.error(const OperationFailure(FailureCode.shuttingDown));
    if (cancellation?.isCancelled ?? false)
      return Future.error(const CredentialCancelled());
    if (bytes.isEmpty || bytes.length > 1024 * 1024) {
      return Future.error(
        const OperationFailure(
          FailureCode.unsupportedKey,
          field: OperationField.authentication,
        ),
      );
    }
    if (timeout <= Duration.zero)
      return Future.error(const OperationFailure(FailureCode.timeout));
    if (_pool.activeWorkers >= maxWorkers)
      return Future.error(
        const OperationFailure(FailureCode.resourceExhausted, retryable: true),
      );
    if (passphrase != null && !isKeyPassphraseBounded(passphrase)) {
      return Future.error(
        const OperationFailure(
          FailureCode.invalidArgument,
          field: OperationField.passphrase,
        ),
      );
    }
    return _pool
        .run(
          KeyParseRequest(bytes, passphrase),
          cancellation: cancellation,
          timeout: timeout,
        )
        .then(
          (value) => value,
          onError: (Object error, StackTrace stack) {
            final mapped = error is WorkFailure
                ? switch (error.kind) {
                    WorkFailureKind.stopped => const OperationFailure(
                      FailureCode.shuttingDown,
                    ),
                    WorkFailureKind.capacity => const OperationFailure(
                      FailureCode.resourceExhausted,
                      retryable: true,
                    ),
                    WorkFailureKind.timeout => const OperationFailure(
                      FailureCode.timeout,
                      retryable: true,
                    ),
                  }
                : error is WorkCancelled
                ? error
                : error is OperationFailure
                ? error
                : const OperationFailure(FailureCode.unsupportedKey);
            Error.throwWithStackTrace(mapped, stack);
          },
        );
  }

  @override
  Future<KeyInspection> inspect(
    Uint8List bytes, {
    String? passphrase,
    CredentialCancellation? cancellation,
    Duration timeout = maxDuration,
  }) async {
    final parsed = await parse(
      bytes,
      passphrase: passphrase,
      cancellation: cancellation,
      timeout: timeout,
    );
    try {
      return parsed.inspection;
    } finally {
      parsed.dispose();
    }
  }

  @override
  Future<void> stopAdmission() => _pool.stopAdmission();
  @override
  Future<void> cancelPending() => _pool.cancelPending();
  @override
  Future<void> closeSessions() => _pool.closeSessions();
  @override
  Future<void> drain() => _pool.drain();
  @override
  Future<void> dispose() => _pool.dispose();
}

/// Adapter unit: all messages stay inside the Dart process. Error text is dropped.
Future<KeyParseWorker> spawnKeyParseWorker(KeyParseRequest request) async {
  final port = ReceivePort();
  final worker = _IsolateKeyWorker(port);
  worker.listen();
  try {
    worker.isolate = await Isolate.spawn(
      _parseEntry,
      (port.sendPort, request.bytes, request.passphrase),
      onExit: port.sendPort,
      onError: port.sendPort,
      errorsAreFatal: true,
      debugName: 'ServerDeck-key-parser',
    );
    return worker;
  } catch (_) {
    worker.abortSpawn();
    rethrow;
  }
}

void _parseEntry((SendPort, Uint8List, String?) request) {
  ParsedPrivateKey? parsed;
  try {
    parsed = parseOpenSshKey(request.$2, passphrase: request.$3);
    // send copies the graph; clear the sender's owned key before natural exit.
    request.$1.send(parsed);
  } on OperationFailure catch (error) {
    request.$1.send(error);
  } catch (_) {
    request.$1.send(const OperationFailure(FailureCode.unsupportedKey));
  } finally {
    parsed?.dispose();
    request.$2.fillRange(0, request.$2.length, 0);
  }
}

final class _IsolateKeyWorker implements KeyParseWorker {
  _IsolateKeyWorker(this.port) {
    _result.future.ignore();
  }
  final ReceivePort port;
  final _result = Completer<ParsedPrivateKey>(), _exit = Completer<void>();
  Isolate? isolate;
  bool _received = false;
  @override
  Future<ParsedPrivateKey> get result => _result.future;
  void listen() {
    port.listen((Object? message) {
      if (message == null) {
        if (!_result.isCompleted)
          _result.completeError(
            const OperationFailure(FailureCode.unsupportedKey),
          );
        if (!_exit.isCompleted) _exit.complete();
        port.close();
      } else if (message is ParsedPrivateKey) {
        _received = true;
        if (!_result.isCompleted)
          _result.complete(message);
        else
          message.dispose();
      } else if (!_result.isCompleted) {
        _received = true;
        _result.completeError(
          message is OperationFailure
              ? message
              : const OperationFailure(FailureCode.unsupportedKey),
        );
      }
    });
  }

  void abortSpawn() {
    port.close();
    if (!_exit.isCompleted) _exit.complete();
  }

  @override
  Future<void> stop() async {
    if (!_received && !_exit.isCompleted)
      isolate?.kill(priority: Isolate.immediate);
    await _exit.future;
  }
}
