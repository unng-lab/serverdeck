part of 'operational_auth_client.dart';

String _requestId() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

extension _OperationalGrantClient on OperationalClientSession {
  Future<McpOpenResult> _openGrant(
    McpCredentialFiles files,
    String grantId,
  ) async {
    if (_closed) throw StateError('UNAUTHORIZED');
    if (role != OperationalRole.mcp) throw StateError('FORBIDDEN');
    if (_grantAttempted) {
      await close();
      throw StateError('UNAUTHORIZED');
    }
    _grantAttempted = true;
    final watch = Stopwatch()..start();
    Duration remaining() {
      if (_closed) throw StateError('UNAUTHORIZED');
      final value = rpcDeadline - watch.elapsed;
      if (value <= Duration.zero) throw StateError('TIMEOUT');
      return value;
    }

    Future<void> verify() async {
      remaining();
      await revalidate().timeout(remaining());
      remaining();
    }

    Future<McpOpenResult> work() async {
      McpLoadedCredential? loaded;
      try {
        requireUuid(grantId);
        await verify();
        loaded = await files.readForBridge(grantId);
        remaining();
        await verify();
        final clientNonce = base64Url
            .encode(List<int>.generate(32, (_) => Random.secure().nextInt(256)))
            .replaceAll('=', '');
        final transcript = McpOpenTranscript(
          hello: hello,
          workspaceId: loaded.binding.workspaceId,
          sessionId: id,
          clientNonce: clientNonce,
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
        await verify();
        final requestId = _requestId();
        final io = OperationalHandshakeIo(peer);
        await io.write({
          'v': 1,
          'id': requestId,
          'sessionId': id,
          'method': 'mcp.open',
          'params': McpOpenRequest(
            grantId: grantId,
            clientNonce: clientNonce,
            proof: base64Url.encode(proof).replaceAll('=', ''),
          ).toJson(),
        }, remaining);
        final response = StrictCodec().decode(
          await io.read(remaining),
          maxBytes: maxHandshakeBytes,
        );
        validateResponseEnvelope(response);
        if (response['id'] != requestId ||
            response['generation'] != hello.generation)
          throw StateError('UNAUTHORIZED');
        final error = response['error'];
        if (error is Map<String, Object?>) {
          final code = error['code'];
          throw StateError(
            const {
                  'UNAUTHORIZED',
                  'FORBIDDEN',
                  'STORAGE_BLOCKED',
                  'RESOURCE_LIMIT',
                  'TIMEOUT',
                  'INCOMPATIBLE',
                }.contains(code)
                ? code as String
                : 'UNAUTHORIZED',
          );
        }
        final result = McpOpenResult.fromJson(response['result']);
        final serverBytes = transcript.serverBytes(result);
        late final bool valid;
        try {
          valid = await loaded.key.verify(
            serverBytes,
            base64Url.decode('${result.proof}='),
          );
        } finally {
          serverBytes.fillRange(0, serverBytes.length, 0);
        }
        if (!valid ||
            !DateTime.now().isBefore(DateTime.parse(result.expiresAt)))
          throw StateError('UNAUTHORIZED');
        await verify();
        if (!DateTime.now().isBefore(DateTime.parse(result.expiresAt)))
          throw StateError('UNAUTHORIZED');
        remaining();
        return result;
      } finally {
        loaded?.key.close();
      }
    }

    try {
      final budget = remaining();
      final result = await work().timeout(budget);
      remaining();
      return _grant = result;
    } on TimeoutException {
      await close();
      throw StateError('TIMEOUT');
    } on FormatException {
      await close();
      throw StateError('UNAUTHORIZED');
    } catch (_) {
      await close();
      rethrow;
    }
  }
}
