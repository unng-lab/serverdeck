part of 'client.dart';

extension _Bootstrap on McpClient {
  String _mac(Uint8List bytes) {
    final key = SecretKeyData(
      List<int>.of(_token),
      overwriteWhenDestroyed: true,
    );
    try {
      _remaining(_bootstrapUntil);
      return base64Url
          .encode(
            DartHmac.sha256()
                .calculateMacSync(bytes, secretKeyData: key, nonce: const [])
                .bytes,
          )
          .replaceAll('=', '');
    } finally {
      key.destroy();
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<void> _authenticate() async {
    try {
      await _proof(_bootstrapUntil);
      final bytes = await _handshakeFrame(_bootstrapUntil);
      late final OperationalHello hello;
      try {
        final value = StrictCodec().decode(bytes, maxBytes: maxHandshakeBytes);
        final shape = value['hello'];
        if (shape is Map<String, Object?> &&
            shape['apiMajor'] is int &&
            shape['apiMinor'] is int &&
            (shape['apiMajor'] != 1 || shape['apiMinor'] != 1))
          throw StateError('INCOMPATIBLE');
        hello = OperationalHello.fromJson(value);
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
      if (hello.generation != generation || hello.buildId != _build)
        throw StateError('INCOMPATIBLE');
      if (hello.clientRole != OperationalRole.mcp)
        throw StateError('UNAUTHORIZED');
      await _proof(_bootstrapUntil);
      final nonce = _nonce();
      final transcript = OperationalBootstrapTranscript(
        hello: hello,
        clientNonce: nonce,
        requestedCapabilities: const ['mcp'],
      );
      await _handshakeWrite(
        OperationalAuthenticate(
          clientNonce: nonce,
          clientBuildId: _build,
          requestedCapabilities: const ['mcp'],
          proof: _mac(transcript.clientBytes()),
        ).toJson(),
        _bootstrapUntil,
      );
      final responseBytes = await _handshakeFrame(_bootstrapUntil);
      late final OperationalAuthenticated response;
      try {
        response = OperationalAuthenticated.decode(responseBytes);
      } finally {
        responseBytes.fillRange(0, responseBytes.length, 0);
      }
      if (response.clientRole != OperationalRole.mcp ||
          response.capabilities.length != 1 ||
          response.capabilities.single != 'mcp')
        throw StateError('UNAUTHORIZED');
      final expected = base64Url.decode(
        '${_mac(transcript.serverBytes(response))}=',
      );
      final actual = base64Url.decode('${response.proof}=');
      try {
        var difference = expected.length ^ actual.length;
        for (var i = 0; i < expected.length; i++) {
          difference |= expected[i] ^ (i < actual.length ? actual[i] : 0);
        }
        if (difference != 0) throw StateError('UNAUTHORIZED');
      } finally {
        expected.fillRange(0, expected.length, 0);
        actual.fillRange(0, actual.length, 0);
      }
      await _proof(_bootstrapUntil);
      _remaining(_bootstrapUntil);
      _hello = hello;
      _session = response.sessionId;
      _authenticated = true;
    } finally {
      _token.fillRange(0, _token.length, 0);
    }
  }
}

extension McpClientBootstrap on McpClient {
  /// Single-use bootstrap, with one original budget of at most5s. A logical
  /// timeout rejects immediately; close/done still own late native work.
  Future<void> authenticate() {
    if (_authentication != null || _closed)
      return Future.error(StateError('SERVICE_UNAVAILABLE'));
    final done = Completer<void>();
    _authentication = done.future;
    done.future.ignore();
    final actual = _owned(_authenticate);
    Duration remaining;
    try {
      remaining = _remaining(_bootstrapUntil);
    } catch (e) {
      close().ignore();
      done.completeError(StateError(_safe(e)));
      return done.future;
    }
    actual
        .timeout(remaining)
        .then<void>(
          (_) {
            if (_closed) {
              done.completeError(StateError('SERVICE_UNAVAILABLE'));
              return;
            }
            _owned(_readLoop).ignore();
            done.complete();
          },
          onError: (Object e, StackTrace _) {
            close().ignore();
            done.completeError(
              StateError(e is FormatException ? 'UNAUTHORIZED' : _safe(e)),
            );
          },
        );
    return done.future;
  }
}
