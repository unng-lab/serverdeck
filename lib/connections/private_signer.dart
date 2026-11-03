import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/src/hostkey/hostkey_ed25519.dart';
import 'package:dartssh2/src/hostkey/hostkey_rsa.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/asymmetric/api.dart' as rsa;
import 'package:pointycastle/digests/sha512.dart';
import 'package:pointycastle/signers/rsa_signer.dart';

import '../domain/models.dart';
import '../profiles/credential_parser.dart';
import '../profiles/key_envelope.dart';
import '../runtime/capability.dart';
import '../runtime/owned_work.dart';

enum PrivateSignatureScheme {
  ed25519('ssh-ed25519'),
  rsa256('rsa-sha2-256'),
  rsa512('rsa-sha2-512');

  const PrivateSignatureScheme(this.wire);
  final String wire;
}

PrivateSignatureScheme selectPrivateSignatureScheme(
  PublicKeyHint hint,
  List<String>? serverAlgorithms,
) {
  if (hint.inspection.keyType == 'ssh-ed25519') {
    if (serverAlgorithms == null || serverAlgorithms.contains('ssh-ed25519'))
      return PrivateSignatureScheme.ed25519;
  } else {
    if (serverAlgorithms?.contains('rsa-sha2-512') ?? false)
      return PrivateSignatureScheme.rsa512;
    if (serverAlgorithms == null || serverAlgorithms.contains('rsa-sha2-256'))
      return PrivateSignatureScheme.rsa256;
  }
  throw const OperationFailure(FailureCode.unsupportedServer);
}

const _unsupported = OperationFailure(
  FailureCode.unsupportedKey,
  field: OperationField.authentication,
);
const maxSignChallengeBytes = 2 * 1024 * 1024;

final class PrivateSignRequest {
  PrivateSignRequest(
    Uint8List file,
    this.scheme,
    Uint8List challenge,
    this.passphrase,
  ) : file = Uint8List.fromList(file),
      challenge = Uint8List.fromList(challenge);
  final Uint8List file, challenge;
  final PrivateSignatureScheme scheme;
  String? passphrase;
  void dispose() {
    file.fillRange(0, file.length, 0);
    challenge.fillRange(0, challenge.length, 0);
    passphrase = null;
  }
}

abstract interface class PrivateSignWorker implements OwnedWorker<Uint8List> {}

typedef SpawnPrivateSignWorker = Future<PrivateSignWorker> Function(
  PrivateSignRequest request,
);

/// Separate four-slot owner: only encoded signatures cross back from its workers.
final class PrivateSigner implements RuntimeCapability {
  PrivateSigner({
    SpawnPrivateSignWorker? spawn,
    ScheduleOwnedDeadline? schedule,
  }) : _pool = OwnedWorkerPool<PrivateSignRequest, Uint8List>(
         id: 'ssh-private-signatures',
         spawn: spawn ?? spawnPrivateSignWorker,
         disposeRequest: (r) => r.dispose(),
         disposeLateResult: (r) => r.fillRange(0, r.length, 0),
         schedule: schedule,
       );
  final OwnedWorkerPool<PrivateSignRequest, Uint8List> _pool;
  int get activeWorkers => _pool.activeWorkers;
  @override
  String get id => _pool.id;

  Future<SSHSignature> sign(
    Uint8List file,
    PrivateSignatureScheme scheme,
    Uint8List challenge, {
    String? passphrase,
    WorkCancellation? cancellation,
    Duration timeout = OwnedWorkerPool.maxDuration,
  }) async {
    if (_pool.isStopped) throw const OperationFailure(FailureCode.shuttingDown);
    cancellation?.check();
    if (timeout <= Duration.zero)
      throw const OperationFailure(FailureCode.timeout);
    if (file.isEmpty ||
        file.length > 1024 * 1024 ||
        challenge.length > maxSignChallengeBytes)
      throw _unsupported;
    if (passphrase != null && !isKeyPassphraseBounded(passphrase)) {
      throw const OperationFailure(
        FailureCode.invalidArgument,
        field: OperationField.passphrase,
      );
    }
    Uint8List? encoded;
    try {
      encoded = await _pool.run(
        PrivateSignRequest(file, scheme, challenge, passphrase),
        cancellation: cancellation,
        timeout: timeout,
      );
      // Both decoders hold views: give the returned signature its own public bytes.
      final bytes = Uint8List.fromList(encoded);
      final SSHSignature signature;
      if (scheme == PrivateSignatureScheme.ed25519) {
        final ed = SSHEd25519Signature.decode(bytes);
        if (ed.signature.length != 64) throw _unsupported;
        signature = ed;
      } else {
        final rs = SSHRsaSignature.decode(bytes);
        if (rs.type != scheme.wire || rs.signature.isEmpty) throw _unsupported;
        signature = rs;
      }
      if (!sameKeyBytes(signature.encode(), encoded)) throw _unsupported;
      cancellation?.check();
      return signature;
    } on WorkCancelled {
      rethrow;
    } on WorkFailure catch (e) {
      throw switch (e.kind) {
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
      };
    } on OperationFailure catch (e) {
      if (e.code == FailureCode.passphraseRequired ||
          e.code == FailureCode.passphraseInvalid ||
          e.code == FailureCode.unsupportedKey)
        rethrow;
      throw _unsupported;
    } catch (_) {
      throw _unsupported;
    } finally {
      encoded?.fillRange(0, encoded.length, 0);
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

Future<PrivateSignWorker> spawnPrivateSignWorker(
  PrivateSignRequest request,
) async {
  final port = ReceivePort(), worker = _PrivateWorker();
  worker.listen(port);
  try {
    worker.isolate = await Isolate.spawn(
      _signEntry,
      (
        port.sendPort,
        request.file,
        request.scheme,
        request.challenge,
        request.passphrase,
      ),
      onExit: port.sendPort,
      onError: port.sendPort,
      errorsAreFatal: true,
      debugName: 'ServerDeck-private-signature',
    );
    return worker;
  } catch (_) {
    worker.abortSpawn(port);
    rethrow;
  }
}

void _signEntry(
  (SendPort, Uint8List, PrivateSignatureScheme, Uint8List, String?) request,
) {
  ParsedPrivateKey? parsed;
  Uint8List? encoded;
  try {
    parsed = parseOpenSshKey(request.$2, passphrase: request.$5);
    final key = parsed.key;
    final SSHSignature signature;
    if (request.$3 == PrivateSignatureScheme.ed25519 &&
        key is OpenSSHEd25519KeyPair) {
      signature = key.sign(request.$4);
    } else if (key is OpenSSHRsaKeyPair &&
        request.$3 != PrivateSignatureScheme.ed25519) {
      if (request.$3 == PrivateSignatureScheme.rsa256) {
        signature = key.sign(request.$4);
      } else {
        final signer = RSASigner(SHA512Digest(), '0609608648016503040203');
        signer.init(
          true,
          PrivateKeyParameter<rsa.RSAPrivateKey>(
            rsa.RSAPrivateKey(key.n, key.d, key.p, key.q),
          ),
        );
        signature = SSHRsaSignature(
          request.$3.wire,
          signer.generateSignature(request.$4).bytes,
        );
      }
    } else {
      throw _unsupported;
    }
    encoded = signature.encode();
    request.$1.send(encoded);
  } on OperationFailure catch (e) {
    request.$1.send(e);
  } catch (_) {
    request.$1.send(_unsupported);
  } finally {
    parsed?.dispose();
    for (final bytes in [request.$2, request.$4, encoded]) {
      bytes?.fillRange(0, bytes.length, 0);
    }
  }
}

final class _PrivateWorker implements PrivateSignWorker {
  final _result = Completer<Uint8List>(), _exit = Completer<void>();
  Isolate? isolate;
  bool _received = false;
  @override
  Future<Uint8List> get result => _result.future;
  void listen(ReceivePort port) {
    _result.future.ignore();
    port.listen((Object? message) {
      if (message == null) {
        if (!_result.isCompleted) _result.completeError(_unsupported);
        if (!_exit.isCompleted) _exit.complete();
        port.close();
      } else if (!_result.isCompleted) {
        _received = true;
        if (message is Uint8List) {
          _result.complete(message);
        } else {
          _result.completeError(
            message is OperationFailure ? message : _unsupported,
          );
        }
      } else if (message is Uint8List) {
        message.fillRange(0, message.length, 0);
      }
    });
  }

  void abortSpawn(ReceivePort port) {
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

/// One credential revision and one frozen algorithm per authentication attempt.
/// The owner must check verified/accepted host, current authority and all fences
/// in checkAdmission, and implement the bounded prompt in requestPassphrase.
final class OwnedPrivateIdentity extends SSHIdentity {
  OwnedPrivateIdentity({
    required Uint8List file,
    required this.credentialRevision,
    required KeyInspection expected,
    required this.signer,
    required this.checkAdmission,
    required this.serverAlgorithms,
    required this.requestPassphrase,
    required this.remainingBudget,
    WorkCancellation? cancellation,
  }) : hint = readPublicKeyHint(file),
       _file = Uint8List.fromList(file) {
    if (credentialRevision < 1 ||
        hint.inspection.keyType != expected.keyType ||
        hint.inspection.bits != expected.bits ||
        hint.inspection.encrypted != expected.encrypted) {
      dispose();
      throw _unsupported;
    }
    _unlisten = cancellation?.listen(dispose);
  }
  final int credentialRevision;
  final PublicKeyHint hint;
  final PrivateSigner signer;
  final void Function(int credentialRevision) checkAdmission;
  final List<String>? Function() serverAlgorithms;
  final Future<String?> Function() requestPassphrase;
  final Duration Function() remainingBudget;
  final Uint8List _file;
  final _cancellation = WorkCancellation();
  void Function()? _unlisten;
  PrivateSignatureScheme? _scheme;
  bool _used = false;
  void _check() {
    _cancellation.check();
    checkAdmission(credentialRevision);
  }

  @override
  String get type {
    _check();
    return (_scheme ??= selectPrivateSignatureScheme(
      hint,
      serverAlgorithms(),
    )).wire;
  }

  @override
  SSHHostKey toPublicKey() {
    type;
    return hint.toPublicKey();
  }

  Future<String?> _prompt() async {
    final result = Completer<String?>();
    final unlisten = _cancellation.listen(() {
      if (!result.isCompleted) result.completeError(const WorkCancelled());
    });
    if (!result.isCompleted) {
      unawaited(
        Future.sync(requestPassphrase).then(
          (value) {
            if (!result.isCompleted) result.complete(value);
          },
          onError: (Object error, StackTrace stack) {
            if (!result.isCompleted) result.completeError(error, stack);
          },
        ),
      );
    }
    try {
      return await result.future;
    } finally {
      unlisten();
    }
  }

  @override
  Future<SSHSignature> sign(Uint8List data) async {
    Uint8List? challenge;
    String? passphrase;
    var success = false;
    try {
      _check();
      if (_used) throw const OperationFailure(FailureCode.authFailed);
      _used = true;
      if (data.length > maxSignChallengeBytes) throw _unsupported;
      type; // Freeze before awaiting any prompt.
      challenge = Uint8List.fromList(data);
      if (hint.inspection.encrypted) passphrase = await _prompt();
      _check();
      final result = await signer.sign(
        _file,
        _scheme!,
        challenge,
        passphrase: passphrase,
        cancellation: _cancellation,
        timeout: remainingBudget(),
      );
      _check();
      success = true;
      return result;
    } finally {
      passphrase = null;
      challenge?.fillRange(0, challenge.length, 0);
      _file.fillRange(0, _file.length, 0);
      // SSHClient reads type again after awaiting sign; keep its frozen public
      // identity usable until the owner ends authentication or cancels it.
      if (!success) dispose();
    }
  }

  void dispose() {
    _unlisten?.call();
    _unlisten = null;
    _cancellation.cancel();
    _file.fillRange(0, _file.length, 0);
  }
}
