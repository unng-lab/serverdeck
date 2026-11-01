part of 'client.dart';

extension McpClientGrant on McpClient {
  /// Exactly one protected grant attempt. No raw key/permission DTO can create
  /// client grant authority; a current server proof is still mandatory.
  Future<void> openGrant(McpCredentialFiles files, String grantId) {
    if (_closed ||
        !_authenticated ||
        _grantOpening != null ||
        _pending.isNotEmpty) {
      return Future.error(StateError('SERVICE_UNAVAILABLE'));
    }
    final done = Completer<void>();
    _grantOpening = done.future;
    done.future.ignore();
    _grantBusy = true;
    final until = _clock.elapsed + rpcDeadline;
    final actual = _owned(() async {
      McpLoadedCredential? loaded;
      try {
        requireUuid(grantId);
        if (files.ownerSid != _owner || files.workspaceId != workspaceId)
          throw StateError('STORAGE_BLOCKED');
        await _proof(until);
        loaded = await files.readForBridge(grantId);
        _remaining(until);
        await _proof(until);
        final nonce = _nonce();
        final transcript = McpOpenTranscript(
          hello: _hello!,
          workspaceId: workspaceId,
          sessionId: _session!,
          clientNonce: nonce,
          grantId: grantId,
          secretRef: loaded.binding.secretRef,
        );
        final clientBytes = transcript.clientBytes();
        late final List<int> proof;
        try {
          proof = await loaded.key.mac(clientBytes);
        } finally {
          clientBytes.fillRange(0, clientBytes.length, 0);
        }
        await _proof(until);
        final response = await _call(
          'mcp.open',
          McpOpenRequest(
            grantId: grantId,
            clientNonce: nonce,
            proof: base64Url.encode(proof).replaceAll('=', ''),
          ).toJson(),
          until: until,
        );
        final result = McpOpenResult.fromJson(response);
        final serverBytes = transcript.serverBytes(result);
        final expected = base64Url.decode('${result.proof}=');
        late final bool valid;
        try {
          valid = await loaded.key.verify(serverBytes, expected);
        } finally {
          serverBytes.fillRange(0, serverBytes.length, 0);
          expected.fillRange(0, expected.length, 0);
        }
        if (!valid || !_clock.utcNow.isBefore(DateTime.parse(result.expiresAt)))
          throw StateError('UNAUTHORIZED');
        await _proof(until);
        if (!_clock.utcNow.isBefore(DateTime.parse(result.expiresAt)))
          throw StateError('UNAUTHORIZED');
        _remaining(until);
        _grant = result;
      } finally {
        loaded?.key.close();
        _grantBusy = false;
      }
    });
    Duration remaining;
    try {
      remaining = _remaining(until);
    } catch (e) {
      close().ignore();
      done.completeError(StateError(_safe(e)));
      return done.future;
    }
    actual
        .timeout(remaining)
        .then<void>(
          done.complete,
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
