import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:pointycastle/digests/sha256.dart';

import '../domain/models.dart';
import '../console/console_port.dart';
import '../journals/journal_models.dart';
import '../journals/journal_port.dart';
import '../journals/journal_protocol.dart';
import '../profiles/key_envelope.dart';
import '../runtime/owned_work.dart';
import '../monitoring/linux_metrics.dart';
import '../monitoring/monitoring_models.dart';
import 'host_signature.dart';
import 'private_signer.dart';

const strictSshAlgorithms = SSHAlgorithms(
  kex: [
    SSHKexType.x25519Rfc,
    SSHKexType.x25519,
    SSHKexType.nistp521,
    SSHKexType.nistp384,
    SSHKexType.nistp256,
    SSHKexType.dhGexSha256,
    SSHKexType.dh14Sha256,
  ],
  hostkey: [
    SSHHostkeyType.ed25519,
    SSHHostkeyType.rsaSha512,
    SSHHostkeyType.rsaSha256,
  ],
  cipher: [
    SSHCipherType.aes256gcm,
    SSHCipherType.aes128gcm,
    SSHCipherType.chacha20poly1305,
    SSHCipherType.aes256ctr,
    SSHCipherType.aes128ctr,
  ],
  mac: [
    SSHMacType.hmacSha256Etm,
    SSHMacType.hmacSha512Etm,
    SSHMacType.hmacSha256,
    SSHMacType.hmacSha512,
  ],
);

final class HostObservation {
  HostObservation._(this.keyType, this.fingerprint, Uint8List blob)
    : blob = Uint8List.fromList(blob).asUnmodifiableView();

  /// Data projection only: caller already verified the KEX signature. This
  /// constructor grants no actor/nonce authority and is never decoded from JSON.
  factory HostObservation.fromVerifiedBlob(String negotiated, Uint8List blob) {
    if (blob.isEmpty || blob.length > 16384)
      throw const OperationFailure(FailureCode.unsupportedServer);
    final fingerprint =
        'SHA256:${base64.encode(SHA256Digest().process(blob)).replaceAll('=', '')}';
    return _observation(
      negotiated,
      Uint8List.fromList(utf8.encode(fingerprint)),
      blob,
    );
  }
  final String keyType, fingerprint;
  final Uint8List blob;
}

HostObservation _observation(
  String negotiated,
  Uint8List fingerprint,
  Uint8List blob,
) {
  final type = SSHHostKey.getType(blob);
  if (!['ssh-ed25519', 'ssh-rsa'].contains(type) ||
      (type == 'ssh-ed25519'
          ? negotiated != type
          : !['rsa-sha2-256', 'rsa-sha2-512'].contains(negotiated))) {
    throw const OperationFailure(FailureCode.unsupportedServer);
  }
  final expected =
      'SHA256:${base64.encode(SHA256Digest().process(blob)).replaceAll('=', '')}';
  if (utf8.decode(fingerprint) != expected)
    throw const OperationFailure(FailureCode.unsupportedServer);
  return HostObservation._(type, expected, blob);
}

sealed class AttemptCredential {
  AttemptCredential(Uint8List bytes) : bytes = Uint8List.fromList(bytes);
  final Uint8List bytes;
  void dispose() => bytes.fillRange(0, bytes.length, 0);
}

final class PasswordCredential extends AttemptCredential {
  PasswordCredential(super.bytes) {
    if (bytes.isEmpty || bytes.length > 65536) {
      dispose();
      throw const OperationFailure(
        FailureCode.invalidArgument,
        field: OperationField.authentication,
      );
    }
    try {
      utf8.decode(bytes);
    } catch (_) {
      dispose();
      throw const OperationFailure(
        FailureCode.invalidArgument,
        field: OperationField.authentication,
      );
    }
  }
}

final class PrivateKeyCredential extends AttemptCredential {
  PrivateKeyCredential(
    super.bytes, {
    required this.revision,
    required this.inspection,
    required this.publicHint,
  }) {
    if (bytes.isEmpty || bytes.length > 1024 * 1024 || revision < 1) {
      dispose();
      throw const OperationFailure(FailureCode.unsupportedKey);
    }
  }
  final int revision;
  final KeyInspection inspection;
  final PublicKeyHint publicHint;
}

/// Implement through DomainCommandGate: execute actualWrite synchronously inside
/// CommandContext.linearize with CURRENT actor and connection/credential/endpoint
/// fences. No network Future may be awaited inside that effect. The callback is
/// called exactly once, before this Future completes; any late call is fenced.
typedef AdmitSshWrite = Future<void> Function(void Function() actualWrite);

/// One already-dialed owned socket. No shell, channel, exec or raw-client API.
/// Root owns the shared crypto pools, trust/prompt effects and attempt budget.
abstract interface class SshConnection {
  Future<void> get authenticated;
  Future<OperationFailure?> get ended;
  bool get isClosed;
  Future<void> ping();
  Future<void> close();
}

/// Optional typed capability; callers cannot supply command text or expose it via MCP.
abstract interface class MonitoringSshConnection {
  Future<LinuxSample> collectMonitoring(
    WorkCancellation cancellation, {
    Duration timeout = const Duration(seconds: 5),
  });
}

final class StrictSshTransport
    implements
        SshConnection,
        MonitoringSshConnection,
        JournalSshConnection,
        ConsoleSshConnection {
  StrictSshTransport({
    required SSHSocket socket,
    required String username,
    required AttemptCredential credential,
    required HostSignatureVerifier verifier,
    required PrivateSigner signer,
    required AdmitSshWrite admitWrite,
    required void Function() checkAuthentication,
    required Future<bool> Function(HostObservation) verifyHost,
    required Future<void> Function(HostObservation) changedHost,
    required Future<String?> Function() requestPassphrase,
    required Duration Function() remainingBudget,
    required WorkCancellation cancellation,
  }) : _credential = credential,
       _checkAuthentication = checkAuthentication {
    _socket = _AdmittedSocket(socket, admitWrite, _fail);
    try {
      SSHIdentity? identity;
      if (credential is PrivateKeyCredential) {
        _identity = OwnedPrivateIdentity(
          file: credential.bytes,
          credentialRevision: credential.revision,
          expected: credential.inspection,
          publicHint: credential.publicHint,
          signer: signer,
          checkAdmission: (_) => _checkAuth(),
          serverAlgorithms: () => _client.serverSigAlgs,
          requestPassphrase: requestPassphrase,
          remainingBudget: remainingBudget,
          cancellation: _cancelWork,
        );
        identity = _TrackedIdentity(_identity!, () {
          _checkAuth();
          _prepared = true;
        });
      }
      _client = SSHClient(
        _socket,
        username: username,
        algorithms: strictSshAlgorithms,
        identities: identity == null ? null : [identity],
        onPasswordRequest: identity != null
            ? null
            : () {
                _checkAuth();
                if (_prepared)
                  throw const OperationFailure(FailureCode.authFailed);
                final password = utf8.decode(_credential.bytes);
                _prepared = true;
                _credential.dispose();
                return password;
              },
        onVerifyHostSignature: (type, key, signature, hash) async {
          final valid = await verifier.verify(
            type,
            key,
            signature,
            hash,
            cancellation: _cancelWork,
            timeout: remainingBudget(),
          );
          if (_stopped) return false;
          return valid;
        },
        onVerifyHostKey: (type, fingerprint, blob) async {
          if (_stopped) return false;
          final observation = _observation(type, fingerprint, blob);
          final accepted = await verifyHost(observation);
          if (_stopped) return false;
          _accepted = accepted;
          if (!accepted)
            _failure ??= const OperationFailure(FailureCode.trustRequired);
          return accepted;
        },
        onHostKeyChanged: (type, fingerprint, blob) {
          if (_stopped) return Future<void>.value();
          _changed = true;
          // Invoke the owner now, before library done callbacks can invalidate
          // its generation. Await persistence before publishing our ended event.
          return _changedWork = Future.sync(
            () => changedHost(_observation(type, fingerprint, blob)),
          );
        },
        onAuthenticated: () {
          if (!_prepared || !_accepted)
            _fail(const OperationFailure(FailureCode.unsupportedServer));
        },
        keepAliveInterval: null,
        handshakeTimeout: null,
        authTimeout: null,
      );
      _client.done
          .then(
            (_) => _onEnded(null),
            onError: (Object error, StackTrace _) => _onEnded(error),
          )
          .ignore();
      _client.authenticated
          .then(
            (_) async {
              try {
                await _socket.flush();
                _checkAuth();
                if (!_prepared)
                  throw const OperationFailure(FailureCode.unsupportedServer);
                _identity?.dispose();
                _credential.dispose();
                if (!_authenticated.isCompleted) _authenticated.complete();
              } catch (error) {
                _fail(error);
              }
            },
            onError: (Object error, StackTrace _) {
              _fail(error);
            },
          )
          .ignore();
      _unlisten = cancellation.listen(() {
        unawaited(close().catchError((Object _) {}));
      });
    } catch (_) {
      _identity?.dispose();
      _credential.dispose();
      // The root still owns the known socket if construction fails.
      rethrow;
    }
    _authenticated.future.ignore();
  }
  final AttemptCredential _credential;
  final void Function() _checkAuthentication;
  late final _AdmittedSocket _socket;
  late final SSHClient _client;
  OwnedPrivateIdentity? _identity;
  final _cancelWork = WorkCancellation();
  final _authenticated = Completer<void>();
  final _ended = Completer<OperationFailure?>();
  Future<void>? _changedWork;
  void Function()? _unlisten;
  bool _accepted = false,
      _prepared = false,
      _stopped = false,
      _changed = false,
      _pinging = false;
  OperationFailure? _failure;
  Future<void> get authenticated => _authenticated.future;
  Future<OperationFailure?> get ended => _ended.future;
  bool get isClosed => _stopped || _client.isClosed;

  @override
  ConsoleOpening openConsole({
    String? path,
    required void Function(Uint8List) onData,
    required void Function() guard,
  }) {
    _checkAuth();
    guard();
    try {
      final operation = _client.startOwnedPty(
        SSHOwnedPtyOptions(
          path: path,
          onData: onData,
          send: (payload, checkAction, committed, wait) => _sendConsolePacket(
            payload,
            () {
              guard();
              checkAction();
            },
            committed,
            wait,
          ),
        ),
      );
      return _ConsoleOpening(operation);
    } catch (error) {
      throw _consoleOpenFailure(error);
    }
  }

  Future<void> _sendConsolePacket(
    Uint8List payload,
    void Function() guard,
    void Function() committed,
    SSHOwnedPacketWait wait,
  ) async {
    while (true) {
      await _waitConsoleReady(guard, wait, rekey: true);
      var sent = false;
      await _admitConsolePacket(wait, guard, () {
        _checkAuth();
        if (wait.remaining() <= Duration.zero) {
          throw const OperationFailure(FailureCode.timeout);
        }
        if (_socket.hasPendingWrites || _client.ownedPacketBlocked) return;
        guard();
        sent = _socket.runImmediate(payload.length + 256, () {
          final accepted = _client.trySendOwnedPacket(payload);
          if (accepted) committed();
          return accepted;
        });
      });
      if (sent) {
        await _waitConsoleReady(guard, wait, rekey: false);
        return;
      }
    }
  }

  int _consoleAdmissions = 0;
  int get consoleAdmissionCount => _consoleAdmissions;
  int get consolePacketWaiterCount =>
      _socket._drainListeners.length + _client.ownedPacketWaiterCount;

  Future<void> _admitConsolePacket(
    SSHOwnedPacketWait wait,
    void Function() guard,
    void Function() write,
  ) async {
    if (_consoleAdmissions >= 64)
      throw const OperationFailure(FailureCode.resourceExhausted);
    _consoleAdmissions++;
    var active = true;
    final result = Completer<void>();
    void checkCancelled() {
      try {
        guard();
      } catch (error, stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      }
    }

    final off = wait.listenCancelled(checkCancelled);
    final remaining = wait.remaining();
    final timer = Timer(
      remaining > Duration.zero ? remaining : Duration.zero,
      () {
        if (!result.isCompleted)
          result.completeError(const OperationFailure(FailureCode.timeout));
      },
    );
    unawaited(
      Future<void>.sync(
        () => _socket.admit(() {
          if (!active) throw const WorkCancelled();
          guard();
          if (wait.remaining() <= Duration.zero)
            throw const OperationFailure(FailureCode.timeout);
          write();
        }),
      ).then(
        (_) {
          _consoleAdmissions--;
          if (!result.isCompleted) result.complete();
        },
        onError: (Object error, StackTrace stack) {
          _consoleAdmissions--;
          if (!result.isCompleted) result.completeError(error, stack);
        },
      ),
    );
    try {
      checkCancelled();
      await result.future;
    } finally {
      active = false;
      off();
      timer.cancel();
    }
    // A queued gate callback may finish later. Its bounded reservation remains
    // until then, and its inactive latch forbids encryption or a socket write.
  }

  Future<void> _waitConsoleReady(
    void Function() guard,
    SSHOwnedPacketWait wait, {
    required bool rekey,
  }) async {
    final result = Completer<void>();
    void check() {
      if (result.isCompleted) return;
      try {
        _checkAuth();
        guard();
        if (wait.remaining() <= Duration.zero)
          throw const OperationFailure(FailureCode.timeout);
        if (_socket._stopped)
          throw _socket._failure ??
              const OperationFailure(FailureCode.networkError);
        if (!_socket.hasPendingWrites &&
            (!rekey || !_client.ownedPacketBlocked))
          result.complete();
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    }

    final offDrain = _socket.listenDrained(check);
    final offKex = _client.listenOwnedPacketReady(check);
    final offCancel = wait.listenCancelled(check);
    final remaining = wait.remaining();
    final timer = Timer(
      remaining > Duration.zero ? remaining : Duration.zero,
      () {
        if (!result.isCompleted)
          result.completeError(const OperationFailure(FailureCode.timeout));
      },
    );
    try {
      check();
      await result.future;
    } finally {
      offDrain();
      offKex();
      offCancel();
      timer.cancel();
    }
  }

  @override
  Future<LinuxSample> collectMonitoring(
    WorkCancellation cancellation, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      cancellation.check();
      _checkAuth();
      final operation = _client.startBoundedExec(
        linuxMonitoringCommand,
        timeout: timeout,
      );
      final unlisten = cancellation.listen(operation.cancel);
      try {
        final result = await operation.result;
        cancellation.check();
        _checkAuth();
        final reason = switch (result.failure) {
          SSHBoundedExecFailure.cancelled => MonitoringReason.paused,
          SSHBoundedExecFailure.timeout => MonitoringReason.timeout,
          SSHBoundedExecFailure.outputLimit => MonitoringReason.outputLimit,
          SSHBoundedExecFailure.cleanupPending =>
            MonitoringReason.cleanupPending,
          SSHBoundedExecFailure.unavailable =>
            MonitoringReason.sourceUnavailable,
          SSHBoundedExecFailure.invalidResponse =>
            MonitoringReason.invalidResponse,
          null => null,
        };
        if (reason != null) return LinuxSample.failed(reason);
        return parseLinuxMetrics(result.stdout, exitCode: result.exitCode);
      } finally {
        unlisten();
      }
    } on WorkCancelled {
      return const LinuxSample.failed(MonitoringReason.paused);
    } on OperationFailure {
      return const LinuxSample.failed(MonitoringReason.disconnected);
    } catch (_) {
      return const LinuxSample.failed(MonitoringReason.invalidResponse);
    }
  }

  @override
  Future<JournalReply> collectJournal(
    JournalRequest request,
    WorkCancellation cancellation, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      cancellation.check();
      _checkAuth();
      final operation = _client.startBoundedExec(
        journalCommand(request),
        timeout: timeout,
        captureStatus: true,
      );
      final unlisten = cancellation.listen(operation.cancel);
      try {
        final result = await operation.result;
        cancellation.check();
        _checkAuth();
        final failure = switch (result.failure) {
          SSHBoundedExecFailure.cancelled => JournalStatus.paused,
          SSHBoundedExecFailure.timeout => JournalStatus.timeout,
          SSHBoundedExecFailure.outputLimit => JournalStatus.outputLimit,
          SSHBoundedExecFailure.cleanupPending => JournalStatus.waiting,
          SSHBoundedExecFailure.unavailable => JournalStatus.unavailable,
          SSHBoundedExecFailure.invalidResponse =>
            JournalStatus.invalidResponse,
          null => null,
        };
        if (failure != null) return JournalReply(failure: failure);
        return parseJournalReply(
          request,
          result.stdout,
          result.stderr,
          result.exitCode,
        );
      } finally {
        unlisten();
      }
    } on WorkCancelled {
      return JournalReply(failure: JournalStatus.paused);
    } on OperationFailure {
      return JournalReply(failure: JournalStatus.disconnected);
    } catch (_) {
      return JournalReply(failure: JournalStatus.invalidResponse);
    }
  }

  void _checkAuth() {
    if (_stopped || _client.isClosed)
      throw _failure ?? const OperationFailure(FailureCode.conflict);
    if (!_accepted) throw const OperationFailure(FailureCode.trustRequired);
    _checkAuthentication();
  }

  void _fail(Object error) {
    if (_changed) {
      // Destroy also aborts queued flush/auth futures. Keep cleaning up, but
      // only _onEnded may choose the result after warning persistence settles.
      unawaited(close().catchError((Object _) {}));
      return;
    }
    _failure ??= sshFailure(error, changed: _changed);
    if (!_authenticated.isCompleted) _authenticated.completeError(_failure!);
    unawaited(close().catchError((Object _) {}));
  }

  Future<void> _onEnded(Object? error) async {
    try {
      await _changedWork;
    } catch (failure) {
      _failure ??= sshFailure(failure);
    }
    _failure ??= error == null ? null : sshFailure(error, changed: _changed);
    if (!_authenticated.isCompleted)
      _authenticated.completeError(
        _failure ?? const OperationFailure(FailureCode.networkError),
      );
    _stop();
    if (!_ended.isCompleted) _ended.complete(_failure);
  }

  void _stop() {
    if (_stopped) return;
    _stopped = true;
    _socket.stopWrites();
    _cancelWork.cancel();
    _identity?.dispose();
    _credential.dispose();
    _unlisten?.call();
    _unlisten = null;
  }

  Future<void> ping() async {
    if (_stopped)
      throw _failure ?? const OperationFailure(FailureCode.networkError);
    if (_pinging)
      throw const OperationFailure(
        FailureCode.resourceExhausted,
        retryable: true,
      );
    _pinging = true;
    try {
      await _client.ping();
      await _socket.flush();
    } catch (error) {
      if (_changed) {
        // The vendor aborts ping as soon as it detects the changed host. That
        // subordinate error must not preempt the pending warning transaction.
        throw await _ended.future ?? sshFailure(error, changed: true);
      }
      final failure = _failure ?? sshFailure(error);
      _fail(failure);
      throw failure;
    } finally {
      _pinging = false;
    }
  }

  Future<void> close() async {
    _stop();
    try {
      await _client.close();
      // Library done/closeWithError can precede physical socket completion.
      await _socket.close();
      await _socket.drainWrites();
    } catch (_) {
      throw const OperationFailure(
        FailureCode.cleanupRequired,
        retryable: true,
        reason: FailureReason.connectionCleanup,
      );
    }
  }
}

final class _TrackedIdentity extends SSHIdentity {
  _TrackedIdentity(this.delegate, this.signed);
  final OwnedPrivateIdentity delegate;
  final void Function() signed;
  @override
  String get type => delegate.type;
  @override
  SSHHostKey toPublicKey() => delegate.toPublicKey();
  @override
  Future<SSHSignature> sign(Uint8List data) async {
    final result = await delegate.sign(data);
    signed();
    return result;
  }
}

OperationFailure sshFailure(
  Object error, {
  bool changed = false,
  int depth = 0,
}) {
  if (depth > 4) return const OperationFailure(FailureCode.networkError);
  if (error is OperationFailure) return error;
  if (error is SSHInternalError)
    return sshFailure(error.error, changed: changed, depth: depth + 1);
  if (error is SSHAuthAbortError && error.reason != null)
    return sshFailure(error.reason!, changed: changed, depth: depth + 1);
  if (error is WorkCancelled)
    return const OperationFailure(FailureCode.conflict);
  if (error is SSHSignatureVerificationError)
    return switch (error.reason) {
      SSHSignatureFailure.cancelled => const OperationFailure(
        FailureCode.conflict,
      ),
      SSHSignatureFailure.stopping => const OperationFailure(
        FailureCode.shuttingDown,
      ),
      SSHSignatureFailure.exhausted => const OperationFailure(
        FailureCode.resourceExhausted,
        retryable: true,
      ),
      SSHSignatureFailure.timeout => const OperationFailure(
        FailureCode.timeout,
        retryable: true,
      ),
    };
  if (error is SSHResourceLimitError)
    return const OperationFailure(
      FailureCode.resourceExhausted,
      retryable: true,
    );
  if (error is SSHAuthFailError)
    return const OperationFailure(FailureCode.authFailed);
  if (changed && error is SSHHostkeyError)
    return const OperationFailure(FailureCode.hostKeyChanged);
  if (error is SSHHostkeyError ||
      error is SSHUnsupportedAuthError ||
      error is SSHHandshakeError ||
      error is SSHPacketError)
    return const OperationFailure(FailureCode.unsupportedServer);
  return const OperationFailure(FailureCode.networkError, retryable: true);
}

final class _AdmittedSocket implements SSHSocket {
  _AdmittedSocket(this.raw, this.admit, this.failure) {
    _sink = _AdmittedSink(this);
  }
  final SSHSocket raw;
  final AdmitSshWrite admit;
  final void Function(Object) failure;
  late final _AdmittedSink _sink;
  Future<void> _tail = Future<void>.value();
  Future<void>? _closing;
  bool _stopped = false, _closed = false;
  int _bytes = 0, _count = 0;
  OperationFailure? _failure;
  bool _immediate = false;
  int _immediateMax = 0, _immediateAdds = 0;
  bool get hasPendingWrites => _count != 0;
  final _drainListeners = <void Function()>{};
  bool _drainSignalScheduled = false;
  void Function() listenDrained(void Function() callback) {
    _drainListeners.add(callback);
    return () => _drainListeners.remove(callback);
  }

  void _signalDrained() {
    if (_drainSignalScheduled) return;
    _drainSignalScheduled = true;
    scheduleMicrotask(() {
      _drainSignalScheduled = false;
      for (final listener in List.of(_drainListeners)) {
        if (_drainListeners.contains(listener)) listener();
      }
    });
  }

  /// Called only inside canonical connection admission. No await or user hook.
  bool runImmediate(int maximumBytes, bool Function() serialize) {
    if (_stopped || _immediate || _count != 0 || maximumBytes > maxBytes) {
      throw const OperationFailure(FailureCode.conflict);
    }
    _count++;
    _bytes += maximumBytes;
    _immediate = true;
    _immediateMax = maximumBytes;
    _immediateAdds = 0;
    var reserved = true;
    void release() {
      if (!reserved) return;
      reserved = false;
      _count--;
      _bytes -= maximumBytes;
      _signalDrained();
    }

    try {
      final sent = serialize();
      if (!sent) {
        release();
        return false;
      }
      if (_immediateAdds != 1) throw StateError('Invalid owned packet framing');
      _tail = _tail.then((_) async {
        try {
          await raw.flush();
        } catch (error) {
          _stopped = true;
          _failure ??= sshFailure(error);
          failure(_failure!);
        } finally {
          release();
        }
      });
      return true;
    } catch (error) {
      release();
      _stopped = true;
      _failure ??= sshFailure(error);
      failure(_failure!);
      rethrow;
    } finally {
      _immediate = false;
    }
  }

  static const maxBytes = 1024 * 1024, maxPackets = 64;
  @override
  Stream<Uint8List> get stream => raw.stream;
  @override
  StreamSink<List<int>> get sink => _sink;
  @override
  Future<void> get done => raw.done;
  void stopWrites() {
    _stopped = true;
    _signalDrained();
  }

  void add(List<int> bytes) {
    if (_immediate) {
      if (_stopped || ++_immediateAdds != 1 || bytes.length > _immediateMax) {
        throw StateError('Owned packet exceeded pre-encryption reservation');
      }
      raw.sink.add(Uint8List.fromList(bytes).asUnmodifiableView());
      return;
    }
    if (_stopped) return;
    if (_count >= maxPackets || bytes.length > maxBytes - _bytes) {
      final error = const OperationFailure(
        FailureCode.resourceExhausted,
        retryable: true,
      );
      _stopped = true;
      _failure ??= error;
      failure(error);
      return;
    }
    final packet = Uint8List.fromList(bytes);
    _count++;
    _bytes += packet.length;
    _tail = _tail.then((_) async {
      var active = true, called = false;
      try {
        if (_stopped) return;
        await admit(() {
          if (!active || called || _stopped)
            throw const OperationFailure(FailureCode.conflict);
          called = true;
          // IOSink may retain this list after add returns. Transfer a separate
          // immutable copy; never mutate the sink-owned bytes, even after flush.
          raw.sink.add(Uint8List.fromList(packet).asUnmodifiableView());
        });
        if (!called) throw const OperationFailure(FailureCode.conflict);
        // Outside the gate: retain byte/packet reservation through backpressure.
        await raw.flush();
      } catch (error) {
        _stopped = true;
        _failure ??= sshFailure(error);
        failure(_failure!);
      } finally {
        active = false;
        _count--;
        _bytes -= packet.length;
        _signalDrained();
        packet.fillRange(0, packet.length, 0);
      }
    });
  }

  Future<void> drainWrites() => _tail;
  @override
  Future<void> flush() async {
    await _tail;
    if (_failure != null) throw _failure!;
    if (_stopped) throw const OperationFailure(FailureCode.conflict);
  }

  @override
  Future<void> close() {
    stopWrites();
    if (_closed) return Future<void>.value();
    return _closing ??= _close();
  }

  Future<void> _close() async {
    try {
      await raw.close();
      final done =
          raw.done; // A throwing getter does not confirm physical close.
      try {
        await done;
      } catch (_) {
        /* done confirms closure even with a transport error. */
      }
      _closed = true;
    } finally {
      _closing = null;
    }
  }

  @override
  void destroy() {
    stopWrites();
    raw.destroy();
  }
}

final class _AdmittedSink implements StreamSink<List<int>> {
  _AdmittedSink(this.owner);
  final _AdmittedSocket owner;
  @override
  void add(List<int> bytes) => owner.add(bytes);
  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    owner.stopWrites();
    owner.failure(error);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final bytes in stream) {
      owner.add(bytes);
    }
  }

  @override
  Future<void> close() => owner.close();
  @override
  Future<void> get done => owner.done;
}

final class _ConsoleOpening implements ConsoleOpening {
  const _ConsoleOpening(this.operation);
  final SSHOwnedPtyOperation operation;
  @override
  Future<ConsoleChannel> get opened => operation.opened.then(
    _ConsoleChannel.new,
    onError: (Object error, StackTrace stack) =>
        throw _consoleOpenFailure(error),
  );
  @override
  void cancel() => operation.cancel();
}

ConsoleOpenFailure _consoleOpenFailure(Object error) =>
    ConsoleOpenFailure(switch (error) {
      SSHOwnedPtyError(reason: 'ptyDenied') => ConsoleOpenFailureCode.ptyDenied,
      SSHOwnedPtyError(reason: 'shellDenied') =>
        ConsoleOpenFailureCode.shellDenied,
      SSHOwnedPtyError(reason: 'cleanupPending') =>
        ConsoleOpenFailureCode.cleanupRequired,
      SSHOwnedPtyError(reason: 'timeout') ||
      TimeoutException() => ConsoleOpenFailureCode.timeout,
      SSHOwnedPtyError(reason: 'invalidPacketSize') =>
        ConsoleOpenFailureCode.unsupportedServer,
      SSHOwnedPtyError(reason: 'cancelled') ||
      WorkCancelled() => ConsoleOpenFailureCode.cancelled,
      _ => ConsoleOpenFailureCode.networkError,
    });

final class _ConsoleChannel implements ConsoleChannel {
  const _ConsoleChannel(this.session);
  final SSHOwnedPtySession session;
  @override
  Future<void> get done => session.streamsDone;
  @override
  int? get exitCode => session.exitCode;
  @override
  String? get failure => session.failure;
  @override
  void abort() => session.abort();
  @override
  Future<ConsoleWriteOutcome> write(
    Uint8List bytes, {
    required void Function() guard,
    required WorkCancellation cancellation,
  }) async {
    final token = SSHOwnedPtyCancellation();
    final off = cancellation.listen(token.cancel);
    try {
      final result = await session.sendGuardedData(
        bytes,
        guard: guard,
        cancellation: token,
      );
      return ConsoleWriteOutcome(result.acceptedBytes, result.status.name);
    } finally {
      off();
    }
  }

  @override
  Future<void> resize(int columns, int rows, void Function() guard) =>
      session.resizeGuarded(columns, rows, guard);
}
