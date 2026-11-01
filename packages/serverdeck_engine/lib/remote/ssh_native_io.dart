part of 'ssh_transport.dart';

final class _NativeSshIoFactory implements SshIoFactory {
  const _NativeSshIoFactory();
  @override
  SshIoAttempt start(
    SshEndpoint endpoint,
    SshCredential? credential, {
    required Duration deadline,
    required bool Function(SshHostPin) verifyHostPin,
  }) => _NativeSshIoAttempt(endpoint, credential, deadline, verifyHostPin);
}

/// Owns every late provider phase even after its result was cancelled/timed out.
final class _NativeSshIoAttempt implements SshIoAttempt {
  _NativeSshIoAttempt(
    this.endpoint,
    this.credential,
    this.budget,
    this.verify,
  ) {
    _consume(result);
    _settled.future.ignore();
    _timer = Timer(budget, () => _stop(SshTransportCode.TIMEOUT));
    _run()
        .then<void>((_) {}, onError: (Object _, StackTrace __) => _failedRun())
        .ignore();
  }
  final SshEndpoint endpoint;
  SshCredential? credential;
  final Duration budget;
  final bool Function(SshHostPin) verify;
  final _clock = Stopwatch()..start();
  final _result = Completer<SshIoClient>(), _settled = Completer<void>();
  late final Timer _timer;
  SSHSocket? _socket;
  SSHClient? _client;
  _KeyWorker? _worker;
  bool _stopped = false, _verified = false;
  @override
  Future<SshIoClient> get result => _result.future;
  @override
  Future<void> get settled => _settled.future;
  Duration get _remaining => budget - _clock.elapsed;
  bool _live() {
    if (!_stopped && _remaining <= Duration.zero)
      _stop(SshTransportCode.TIMEOUT);
    return !_stopped;
  }

  @override
  void cancel() => _stop(SshTransportCode.CANCELLED);
  void _stop(SshTransportCode code) {
    if (_stopped) return;
    _stopped = true;
    _timer.cancel();
    if (!_result.isCompleted)
      _result.completeError(SshTransportFailure(code), StackTrace.empty);
    _worker?.cancel();
    _socket?.destroy();
    final client = _client;
    if (client != null) _consume(client.close());
  }

  void _failedRun() {
    // A cleanup implementation can fail synchronously before the ordinary
    // finally reached every resource. Preserve ownership and report failure,
    // never strand provider settled behind an ignored run Future.
    _stopped = true;
    _timer.cancel();
    credential = null;
    try {
      _worker?.cancel();
    } catch (_) {}
    try {
      _socket?.destroy();
    } catch (_) {}
    final client = _client;
    if (client != null) _consume(Future<void>.sync(client.close));
    const failure = SshTransportFailure(SshTransportCode.SERVICE_UNAVAILABLE);
    if (!_result.isCompleted) _result.completeError(failure);
    if (!_settled.isCompleted) _settled.completeError(failure);
  }

  Future<void> _run() async {
    Future<void>? clientDone, socketDone;
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
            _verified = verify(SshHostPin.fromCallback(algorithm, bytes));
            return _verified;
          } catch (_) {
            _stop(SshTransportCode.TRUST_CHANGED);
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
      if (!_verified) {
        _stop(SshTransportCode.TRUST_CHANGED);
        return;
      }
      _timer.cancel();
      _result.complete(_NativeSshIoClient(client));
      await clientDone;
    } catch (error) {
      if (_live())
        _stop(
          error is SshTransportFailure
              ? error.code
              : error is SSHAuthFailError
              ? SshTransportCode.AUTHENTICATION_FAILED
              : SshTransportCode.CONNECTION_FAILED,
        );
    } finally {
      password = null;
      credential = null;
      _worker?.cancel();
      if (_client == null && _socket != null) await _consume(_socket!.close());
      _socket?.destroy();
      final client = _client;
      if (client != null) await _consume(client.close());
      if (clientDone != null) await clientDone;
      if (socketDone != null) await socketDone;
      if (_worker != null) await _worker!.settled;
      _client = null;
      _socket = null;
      _worker = null;
      if (!_result.isCompleted) _stop(SshTransportCode.CONNECTION_FAILED);
      _timer.cancel();
      _settled.complete();
    }
  }
}

final class _NativeSshIoClient implements SshIoClient {
  _NativeSshIoClient(this.client);
  final SSHClient client;
  @override
  Future<void> get done => _consume(client.done);
  @override
  Future<void> close() => _consume(client.close());
  @override
  Future<SshIoSession> execute(SshIoCommand command) async =>
      _NativeSshIoSession(await client.execute(command._command));
}

final class _NativeSshIoSession implements SshIoSession {
  _NativeSshIoSession(this.session);
  final SSHSession session;
  @override
  Stream<Uint8List> get stdout => session.stdout;
  @override
  Stream<Uint8List> get stderr => session.stderr;
  @override
  StreamSink<Uint8List> get stdin => session.stdin;
  @override
  Future<void> get done => session.done;
  @override
  int? get exitCode => session.exitCode;
  @override
  void close() => session.close();
}
