part of 'operational_auth.dart';

/// One per workspace/service generation. Not a wire-accessible signing service.
final class OperationalMcpAuthority {
  OperationalMcpAuthority(this._store, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final StateStore _store;
  final DateTime Function() _clock;
  final _interests = <Completer<void>>{};
  bool _closed = false;
  int _working = 0;
  int get pendingOpens => _working;

  void Function() onGrantPublished(void Function(String, int) listener) =>
      _store.onMcpGrantPublished(listener);

  ClientGrantRecord _current(String id) {
    if (_closed) throw StateError('UNAUTHORIZED');
    return _store.currentMcpGrant(id, at: _clock());
  }

  ClientGrantRecord _exact(ClientGrantRecord binding) {
    final current = _current(binding.id);
    if (current.workspaceId != binding.workspaceId ||
        current.revision != binding.revision ||
        current.secretRef != binding.secretRef)
      throw StateError('UNAUTHORIZED');
    return current;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final interest in _interests) interest.complete();
    _interests.clear();
  }
}

extension _OperationalGrantOpen on OperationalSessionRequest {
  Duration _openRemaining() {
    _live();
    final remaining = _began + rpcDeadline - _registry._clock();
    if (remaining <= Duration.zero) throw StateError('TIMEOUT');
    return remaining;
  }

  Future<void> _openVerify() async {
    try {
      await _session.peer.revalidate().timeout(_openRemaining());
      _openRemaining();
    } on TimeoutException {
      throw StateError('TIMEOUT');
    }
  }

  Future<(ClientGrantRecord, McpOpenResult)> _openWork(
    OperationalMcpAuthority authority,
    McpOpenRequest input,
  ) async {
    McpGrantKey? owned;
    try {
      _openRemaining();
      authority._current(input.grantId);
      await _openVerify();
      owned = await authority._store.openMcpGrantKey(
        input.grantId,
        clock: authority._clock,
      );
      _openRemaining();
      authority._exact(owned.grant);
      await _openVerify();
      final transcript = McpOpenTranscript(
        hello: _session.hello,
        workspaceId: owned.grant.workspaceId,
        sessionId: _session.id,
        clientNonce: input.clientNonce,
        grantId: input.grantId,
        secretRef: owned.grant.secretRef,
      );
      final clientBytes = transcript.clientBytes();
      late final bool valid;
      try {
        valid = await owned.key.verify(
          clientBytes,
          base64Url.decode('${input.proof}='),
        );
      } finally {
        clientBytes.fillRange(0, clientBytes.length, 0);
      }
      _openRemaining();
      authority._exact(owned.grant);
      if (!valid) throw StateError('UNAUTHORIZED');
      final unsigned = McpOpenResult(
        workspaceId: owned.grant.workspaceId,
        grantId: owned.grant.id,
        revision: owned.grant.revision,
        expiresAt: owned.grant.expiresAt.toIso8601String(),
        proof: input.proof,
      );
      final serverBytes = transcript.serverBytes(unsigned);
      late final List<int> mac;
      try {
        mac = await owned.key.mac(serverBytes);
      } finally {
        serverBytes.fillRange(0, serverBytes.length, 0);
      }
      _openRemaining();
      authority._exact(owned.grant);
      await _openVerify();
      authority._exact(owned.grant);
      return (
        owned.grant,
        McpOpenResult(
          workspaceId: unsigned.workspaceId,
          grantId: unsigned.grantId,
          revision: unsigned.revision,
          expiresAt: unsigned.expiresAt,
          proof: base64Url.encode(mac).replaceAll('=', ''),
        ),
      );
    } finally {
      owned?.close();
      authority._working--;
    }
  }
}
