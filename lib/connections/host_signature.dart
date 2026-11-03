import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../runtime/capability.dart';
import '../runtime/owned_work.dart';

final class HostSignatureRequest {
  HostSignatureRequest(
    this.type,
    Uint8List key,
    Uint8List signature,
    Uint8List hash,
  ) : key = Uint8List.fromList(key),
      signature = Uint8List.fromList(signature),
      hash = Uint8List.fromList(hash);
  final SSHHostkeyType type;
  final Uint8List key, signature, hash;
  void dispose() {
    for (final bytes in [key, signature, hash]) {
      bytes.fillRange(0, bytes.length, 0);
    }
  }
}

abstract interface class HostSignatureWorker implements OwnedWorker<bool> {}

typedef SpawnHostSignatureWorker = Future<HostSignatureWorker> Function(
  HostSignatureRequest request,
);

/// Four independent signature reservations, separate from private-key parsing.
final class HostSignatureVerifier implements RuntimeCapability {
  HostSignatureVerifier({
    SpawnHostSignatureWorker? spawn,
    ScheduleOwnedDeadline? schedule,
  }) : _pool = OwnedWorkerPool<HostSignatureRequest, bool>(
         id: 'ssh-host-signatures',
         spawn: spawn ?? spawnHostSignatureWorker,
         disposeRequest: (r) => r.dispose(),
         disposeLateResult: (_) {},
         schedule: schedule,
       );
  final OwnedWorkerPool<HostSignatureRequest, bool> _pool;
  int get activeWorkers => _pool.activeWorkers;
  @override
  String get id => _pool.id;
  Future<bool> verify(
    SSHHostkeyType type,
    Uint8List key,
    Uint8List signature,
    Uint8List hash, {
    WorkCancellation? cancellation,
    Duration timeout = OwnedWorkerPool.maxDuration,
  }) {
    if (_pool.isStopped)
      return Future.error(
        SSHSignatureVerificationError(SSHSignatureFailure.stopping),
      );
    if (cancellation?.isCancelled ?? false)
      return Future.error(
        SSHSignatureVerificationError(SSHSignatureFailure.cancelled),
      );
    if (!const [
          SSHHostkeyType.ed25519,
          SSHHostkeyType.rsaSha256,
          SSHHostkeyType.rsaSha512,
        ].contains(type) ||
        !SSHTransport.isHostSignatureEncodingValid(
          negotiatedType: type,
          keyBytes: key,
          signatureBytes: signature,
          exchangeHash: hash,
        ))
      return Future.value(false);
    return _pool
        .run(
          HostSignatureRequest(type, key, signature, hash),
          cancellation: cancellation,
          timeout: timeout,
        )
        .then(
          (value) => value,
          onError: (Object error, StackTrace stack) {
            final mapped = error is WorkCancelled
                ? SSHSignatureFailure.cancelled
                : error is WorkFailure
                ? switch (error.kind) {
                    WorkFailureKind.stopped => SSHSignatureFailure.stopping,
                    WorkFailureKind.capacity => SSHSignatureFailure.exhausted,
                    WorkFailureKind.timeout => SSHSignatureFailure.timeout,
                  }
                : null;
            if (mapped == null)
              return false; // Drop worker errors and all untrusted text.
            Error.throwWithStackTrace(
              SSHSignatureVerificationError(mapped),
              stack,
            );
          },
        );
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

Future<HostSignatureWorker> spawnHostSignatureWorker(
  HostSignatureRequest request,
) async {
  final port = ReceivePort();
  final worker = _SignatureWorker(port);
  worker.listen();
  try {
    worker.isolate = await Isolate.spawn(
      _verifyEntry,
      (
        port.sendPort,
        request.type,
        request.key,
        request.signature,
        request.hash,
      ),
      onExit: port.sendPort,
      onError: port.sendPort,
      errorsAreFatal: true,
      debugName: 'ServerDeck-host-signature',
    );
    return worker;
  } catch (_) {
    worker.abortSpawn();
    rethrow;
  }
}

void _verifyEntry(
  (SendPort, SSHHostkeyType, Uint8List, Uint8List, Uint8List) request,
) {
  try {
    request.$1.send(
      SSHTransport.verifyHostSignature(
        negotiatedType: request.$2,
        keyBytes: request.$3,
        signatureBytes: request.$4,
        exchangeHash: request.$5,
      ),
    );
  } catch (_) {
    request.$1.send(false);
  } finally {
    for (final bytes in [request.$3, request.$4, request.$5]) {
      bytes.fillRange(0, bytes.length, 0);
    }
  }
}

final class _SignatureWorker implements HostSignatureWorker {
  _SignatureWorker(this.port);
  final ReceivePort port;
  final _result = Completer<bool>(), _exit = Completer<void>();
  Isolate? isolate;
  bool _received = false;
  @override
  Future<bool> get result => _result.future;
  void listen() {
    port.listen((Object? message) {
      if (message == null) {
        if (!_result.isCompleted) _result.complete(false);
        if (!_exit.isCompleted) _exit.complete();
        port.close();
      } else if (!_result.isCompleted) {
        _received = true;
        _result.complete(message is bool ? message : false);
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
