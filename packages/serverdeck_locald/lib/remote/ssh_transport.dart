import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:serverdeck_protocol/profile_validation.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/executor.dart';

export 'package:serverdeck_protocol/host_trust.dart'
    show SshHostPin, SshTransportCode, SshTransportFailure;

part 'ssh_reads.dart';
part 'ssh_executor.dart';

Never _invalid() =>
    throw const SshTransportFailure(SshTransportCode.VALIDATION_ERROR);

final class SshEndpoint {
  factory SshEndpoint(String host, int port, String username) {
    if (!RegExp(r'^[A-Za-z0-9.:-]{1,253}$').hasMatch(host) ||
        port < 1 ||
        port > 65535 ||
        !RegExp(r'^[A-Za-z_][A-Za-z0-9_.-]{0,63}$').hasMatch(username)) {
      _invalid();
    }
    return SshEndpoint._(host, port, username);
  }
  const SshEndpoint._(this.host, this.port, this.username);
  final String host;
  final int port;
  final String username;
  @override
  String toString() => 'SshEndpoint';
}

/// Ephemeral trusted-locald input. It is never a wire capability or a log DTO.
final class SshCredential {
  factory SshCredential.password(String password) {
    try {
      normalizeCredential({
        'action': 'replace',
        'kind': 'password',
        'password': password,
      });
      return SshCredential._(password, null, null);
    } catch (_) {
      _invalid();
    }
  }
  factory SshCredential.privateKey(String pem, {String? passphrase}) {
    try {
      normalizeCredential({
        'action': 'replace',
        'kind': 'privateKey',
        'privateKey': pem,
        'passphrase': passphrase,
      });
      return SshCredential._(null, pem, passphrase);
    } catch (_) {
      _invalid();
    }
  }
  const SshCredential._(this._password, this._pem, this._passphrase);
  final String? _password;
  final String? _pem;
  final String? _passphrase;
  @override
  String toString() => 'SshCredential';
}

final class SshAttempt<T> {
  SshAttempt._(this.result, this.settled, this._cancel) {
    _consume(result);
  }
  final Future<T> result;
  final Future<void> settled;
  final void Function() _cancel;
  void cancel() => _cancel();
}

final class SshLease {
  SshLease._(this._operation);
  final _SshOperation _operation;
  Future<void> get done => _operation.settled;
  SshAttempt<SshReadOutput> read(
    SshReadRequest request, {
    Duration deadline = const Duration(seconds: 30),
  }) {
    if (_operation._stopped || _operation._client == null)
      throw const SshTransportFailure(SshTransportCode.SERVICE_UNAVAILABLE);
    if (_operation._reads.length + _operation._executors.length >= 4)
      throw const SshTransportFailure(SshTransportCode.RESOURCE_LIMIT);
    if (deadline <= Duration.zero)
      throw const SshTransportFailure(SshTransportCode.TIMEOUT);
    final work = _SshReadOperation(
      _operation,
      request,
      deadline < const Duration(seconds: 30)
          ? deadline
          : const Duration(seconds: 30),
    );
    _operation._reads.add(work);
    work.run().ignore();
    return SshAttempt._(
      work.result,
      work.done,
      () => work.stop(SshTransportCode.CANCELLED),
    );
  }

  Future<void> close() {
    _operation.stop(SshTransportCode.CANCELLED);
    return done;
  }

  /// Fixed privileged helper only. This transport method grants no admission;
  /// the shared service owns current policy/target checks for every root call.
  SshAttempt<SshExecutorChannel> openExecutor() {
    if (_operation._stopped || _operation._client == null)
      throw const SshTransportFailure(SshTransportCode.SERVICE_UNAVAILABLE);
    if (_operation._reads.length + _operation._executors.length >= 4)
      throw const SshTransportFailure(SshTransportCode.RESOURCE_LIMIT);
    final work = _SshExecutorOperation(_operation);
    _operation._executors.add(work);
    work.run().ignore();
    return SshAttempt._(
      work.ready,
      work.done,
      () => work.stop(SshTransportCode.CANCELLED),
    );
  }

  @override
  String toString() => 'SshLease';
}

/// One shared instance per locald. No wire caller can create a private pool.
final class SshTransportPool {
  final _operations = <_SshOperation>{};
  final _reservations = <SshTransportReservation>{};
  bool _closed = false;
  Future<void>? _closing;
  int get activeTransports => _operations.length + _reservations.length;

  /// Charges the shared physical budget while trusted custody work is pending.
  SshTransportReservation reserve() {
    if (_closed)
      throw const SshTransportFailure(SshTransportCode.SERVICE_UNAVAILABLE);
    if (activeTransports >= 2)
      throw const SshTransportFailure(SshTransportCode.RESOURCE_LIMIT);
    final reservation = SshTransportReservation._(this);
    _reservations.add(reservation);
    return reservation;
  }

  SshAttempt<SshLease> connect(
    SshEndpoint endpoint,
    SshHostPin pin,
    SshCredential credential, {
    Duration deadline = const Duration(seconds: 15),
  }) {
    final operation = _admit(endpoint, pin, credential, deadline: deadline);
    return SshAttempt._(
      operation.result.then((value) => value as SshLease),
      operation.settled,
      () => operation.stop(SshTransportCode.CANCELLED),
    );
  }

  SshAttempt<SshHostPin> probe(SshEndpoint endpoint) {
    final operation = _admit(endpoint, null, null);
    return SshAttempt._(
      operation.result.then((value) => value as SshHostPin),
      operation.settled,
      () => operation.stop(SshTransportCode.CANCELLED),
    );
  }

  _SshOperation _admit(
    SshEndpoint endpoint,
    SshHostPin? pin,
    SshCredential? credential, {
    Duration deadline = const Duration(seconds: 15),
    SshTransportReservation? reservation,
  }) {
    if (_closed) {
      throw const SshTransportFailure(SshTransportCode.SERVICE_UNAVAILABLE);
    }
    if (reservation == null && activeTransports >= 2) {
      throw const SshTransportFailure(SshTransportCode.RESOURCE_LIMIT);
    }
    if (deadline <= Duration.zero)
      throw const SshTransportFailure(SshTransportCode.TIMEOUT);
    if (reservation != null &&
        (!identical(reservation._pool, this) ||
            !_reservations.contains(reservation)))
      throw const SshTransportFailure(SshTransportCode.SERVICE_UNAVAILABLE);
    final budget = deadline < const Duration(seconds: 15)
        ? deadline
        : const Duration(seconds: 15);
    final operation = _SshOperation(this, endpoint, pin, credential, budget);
    reservation?.close();
    _operations.add(operation);
    unawaited(operation.run());
    return operation;
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    final pending = _operations.toList();
    for (final operation in pending) {
      operation.stop(SshTransportCode.SERVICE_UNAVAILABLE);
    }
    await Future.wait([
      ...pending.map((operation) => operation.settled),
      for (final reservation in _reservations.toList()) reservation.done,
    ]);
  }
}

/// Opaque locald-only slot, not authentication or a wire capability.
final class SshTransportReservation {
  SshTransportReservation._(this._pool);
  final SshTransportPool _pool;
  final _done = Completer<void>();
  Future<void> get done => _done.future;
  SshAttempt<SshLease> connect(
    SshEndpoint endpoint,
    SshHostPin pin,
    SshCredential credential, {
    required Duration deadline,
  }) {
    final operation = _pool._admit(
      endpoint,
      pin,
      credential,
      deadline: deadline,
      reservation: this,
    );
    return SshAttempt._(
      operation.result.then((value) => value as SshLease),
      operation.settled,
      () => operation.stop(SshTransportCode.CANCELLED),
    );
  }

  void close() {
    if (_pool._reservations.remove(this) && !_done.isCompleted)
      _done.complete();
  }
}

const _algorithms = SSHAlgorithms(
  mac: [
    SSHMacType.hmacSha256Etm,
    SSHMacType.hmacSha512Etm,
    SSHMacType.hmacSha256,
    SSHMacType.hmacSha512,
  ],
);

Future<void> _consume(Future<dynamic> future) =>
    future.then<void>((_) {}, onError: (Object _, StackTrace _) {});

final class _SshOperation {
  _SshOperation(
    this.pool,
    this.endpoint,
    this.pin,
    this.credential,
    this._budget,
  ) {
    _timer = Timer(_budget, () {
      stop(SshTransportCode.TIMEOUT);
    });
    _consume(result);
  }
  final SshTransportPool pool;
  final SshEndpoint endpoint;
  final SshHostPin? pin;
  SshCredential? credential;
  final _reads = <_SshReadOperation>{};
  final _executors = <_SshExecutorOperation>{};
  final Duration _budget;
  final _clock = Stopwatch()..start();
  final _result = Completer<Object>();
  final _settled = Completer<void>();
  late final Timer _timer;
  SSHSocket? _socket;
  SSHClient? _client;
  _KeyWorker? _worker;
  bool _stopped = false;
  bool _mismatch = false;
  bool _verified = false;
  SshHostPin? _observed;
  Future<Object> get result => _result.future;
  Future<void> get settled => _settled.future;
  Duration get _remaining => _budget - _clock.elapsed;

  void stop(SshTransportCode code) {
    if (_stopped) return;
    _stopped = true;
    _timer.cancel();
    for (final read in _reads.toList()) read.stop(code);
    for (final executor in _executors.toList()) executor.stop(code);
    if (!_result.isCompleted) {
      _result.completeError(SshTransportFailure(code), StackTrace.empty);
    }
    _worker?.cancel();
    _socket?.destroy();
    final client = _client;
    if (client != null) unawaited(_consume(client.close()));
  }

  bool _live() {
    if (!_stopped && _remaining <= Duration.zero) {
      stop(SshTransportCode.TIMEOUT);
    }
    return !_stopped;
  }

  Future<void> run() async {
    Future<void>? clientDone;
    Future<void>? socketDone;
    String? password;
    try {
      List<SSHKeyPair>? keys;
      if (credential?._pem != null) {
        final worker = _worker = _KeyWorker(
          credential!._pem!,
          credential!._passphrase,
        );
        keys = await worker.result;
        await worker.settled;
      }
      password = credential?._password;
      credential = null;
      if (!_live()) return;
      final socket = _socket = await SSHSocket.connect(
        endpoint.host,
        endpoint.port,
        timeout: _remaining,
      );
      socketDone = _consume(socket.done);
      if (!_live()) return;
      var passwordUsed = false;
      final client = _client = SSHClient(
        socket,
        username: endpoint.username,
        algorithms: _algorithms,
        identities: keys,
        onVerifyHostKey: (algorithm, bytes) {
          if (!_live()) return false;
          try {
            final observed = SshHostPin.fromCallback(algorithm, bytes);
            _observed = observed;
            if (pin == null) return false;
            _verified = observed == pin;
            _mismatch = !_verified;
            return _verified;
          } catch (_) {
            _mismatch = true;
            return false;
          }
        },
        onPasswordRequest: password == null
            ? null
            : () {
                if (!_live() || !_verified || passwordUsed) return null;
                passwordUsed = true;
                return password;
              },
        keepAliveInterval: null,
        handshakeTimeout: _remaining,
        authTimeout: _remaining,
      );
      keys = null;
      clientDone = _consume(client.done);
      await client.authenticated;
      password = null;
      if (!_live()) return;
      if (!_verified || pin == null) {
        stop(SshTransportCode.TRUST_CHANGED);
        return;
      }
      _timer.cancel();
      _result.complete(SshLease._(this));
      await clientDone;
    } catch (error) {
      if (!_live()) return;
      if (_mismatch) {
        stop(SshTransportCode.TRUST_CHANGED);
      } else if (pin != null || _observed == null) {
        stop(
          error is SshTransportFailure
              ? error.code
              : error is SSHAuthFailError
              ? SshTransportCode.AUTHENTICATION_FAILED
              : SshTransportCode.CONNECTION_FAILED,
        );
      }
      // A probe deliberately rejects host verification. Publish only after drain.
    } finally {
      password = null;
      credential = null;
      for (final read in _reads.toList())
        read.stop(SshTransportCode.CONNECTION_FAILED);
      for (final executor in _executors.toList())
        executor.stop(SshTransportCode.CONNECTION_FAILED);
      _worker?.cancel();
      // A late TCP success may never have been handed to SSHClient. Its native
      // IOSink still needs close: destroy alone does not complete sink.done on
      // Linux when no writer has ever attached to the sink.
      if (_client == null && _socket != null) {
        await _consume(_socket!.close());
      }
      _socket?.destroy();
      final client = _client;
      if (client != null) await _consume(client.close());
      if (clientDone != null) await clientDone;
      if (socketDone != null) await socketDone;
      final worker = _worker;
      if (worker != null) await worker.settled;
      _client = null;
      _socket = null;
      _worker = null;
      if (!_result.isCompleted) {
        if (_live() && pin == null && _observed != null) {
          _result.complete(_observed!);
        } else {
          stop(SshTransportCode.CONNECTION_FAILED);
        }
      }
      _timer.cancel();
      await Future.wait([for (final read in _reads.toList()) read.done]);
      await Future.wait([
        for (final executor in _executors.toList()) executor.done,
      ]);
      pool._operations.remove(this);
      _settled.complete();
    }
  }
}

/// Owns spawn, logical parse deadline and actual worker exit independently.
final class _KeyWorker {
  _KeyWorker(String pem, String? passphrase) {
    _events.listen((message) {
      if (message == null) {
        _exited = true;
        _finish();
      } else if (message is List && message.length == 1) {
        final value = message.single;
        if (value is List<SSHKeyPair> && value.isNotEmpty && !_cancelled) {
          _keys = value;
        }
      }
    });
    _timer = Timer(const Duration(seconds: 5), cancel);
    _consume(result);
    unawaited(_spawn(pem, passphrase));
  }
  final _events = ReceivePort();
  final _clock = Stopwatch()..start();
  final _result = Completer<List<SSHKeyPair>>();
  final _settled = Completer<void>();
  late final Timer _timer;
  Isolate? _isolate;
  List<SSHKeyPair>? _keys;
  bool _spawned = false;
  bool _exited = false;
  bool _cancelled = false;
  Future<List<SSHKeyPair>> get result => _result.future;
  Future<void> get settled => _settled.future;

  Future<void> _spawn(String pem, String? passphrase) async {
    try {
      _isolate = await Isolate.spawn(
        _parseKey,
        (_events.sendPort, pem, passphrase),
        onExit: _events.sendPort,
        onError: _events.sendPort,
        errorsAreFatal: true,
        debugName: 'serverdeck-ssh-key',
      );
      if (_cancelled) _isolate!.kill(priority: Isolate.immediate);
    } catch (_) {
      _exited = true;
    } finally {
      _spawned = true;
      _finish();
    }
  }

  void cancel() {
    if (_settled.isCompleted || _cancelled) return;
    _cancelled = true;
    _keys = null;
    _isolate?.kill(priority: Isolate.immediate);
    if (!_result.isCompleted) {
      _result.completeError(
        const SshTransportFailure(SshTransportCode.VALIDATION_ERROR),
        StackTrace.empty,
      );
    }
  }

  void _finish() {
    if (!_spawned || !_exited || _settled.isCompleted) return;
    if (_clock.elapsed >= const Duration(seconds: 5)) cancel();
    _timer.cancel();
    _clock.stop();
    _events.close();
    _isolate = null;
    if (!_result.isCompleted) {
      final keys = _keys;
      if (!_cancelled && keys != null) {
        _result.complete(keys);
      } else {
        _result.completeError(
          const SshTransportFailure(SshTransportCode.VALIDATION_ERROR),
          StackTrace.empty,
        );
      }
    }
    _keys = null;
    _settled.complete();
  }
}

void _parseKey((SendPort, String, String?) input) {
  List<SSHKeyPair>? keys;
  try {
    final pem = SSHPem.decode(input.$2);
    if (pem.type == 'OPENSSH PRIVATE KEY') {
      final container = OpenSSHKeyPairs.decode(pem.content);
      if (!container.isEncrypted) {
        if (container.kdfName != 'none') throw const FormatException();
      } else {
        final kdf = container.kdfOptions;
        if (container.kdfName != 'bcrypt' ||
            kdf is! OpenSSHBcryptKdfOptions ||
            kdf.rounds < 1 ||
            kdf.rounds > 64 ||
            kdf.salt.length < 16 ||
            kdf.salt.length > 64) {
          throw const FormatException();
        }
      }
    }
    keys = SSHKeyPair.fromPem(input.$2, input.$3);
  } catch (_) {
    // Never transfer library exceptions, which may embed PEM/KDF contents.
  }
  Isolate.exit(input.$1, [keys]);
}
