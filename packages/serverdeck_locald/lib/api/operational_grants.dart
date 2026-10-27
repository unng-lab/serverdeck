part of 'operational_auth.dart';

/// One per workspace/service generation. Not a wire-accessible signing service.
final class OperationalMcpAuthority extends _McpAuthority {
  OperationalMcpAuthority(super.store, {super.clock});
  @override
  ClientGrantRecord _read(String id) =>
      _store.currentMcpGrant(id, at: _clock());
  @override
  Future<McpGrantKey> _openKey(String id, Duration deadline) =>
      _store.openMcpGrantKey(id, clock: _clock, publicationDeadline: deadline);
}

/// Format3 authority. Only trusted native requests can bind this authority.
final class TrustedMcpAuthority extends _McpAuthority {
  TrustedMcpAuthority(super.store, {super.clock});

  /// Stop authority synchronously and await all already charged open work,
  /// including late key disposal after a caller timeout or disconnect.
  /// The runtime still owns the registry, native peers and store teardown.
  Future<void> closeAndDrain() => _closeAndDrain();
  @override
  ClientGrantRecord _read(String id) =>
      _store.currentTrustedMcpGrant(id, at: _clock());
  @override
  Future<McpGrantKey> _openKey(String id, Duration deadline) => _store
      .openTrustedMcpGrantKey(id, clock: _clock, publicationDeadline: deadline);
}

sealed class _McpAuthority {
  _McpAuthority(StateStore store, {DateTime Function()? clock})
    : _store = store,
      _clock = clock ?? DateTime.now;
  ClientGrantRecord _read(String id);
  Future<McpGrantKey> _openKey(String id, Duration deadline);
  final StateStore _store;
  final DateTime Function() _clock;
  final _interests = <Completer<void>>{};
  bool _closed = false;
  int _working = 0;
  Completer<void>? _draining;
  int get pendingOpens => _working;
  bool belongsTo(StateStore store) => identical(_store, store) && !_closed;

  bool _publicationPause(Object error) =>
      !_closed &&
      error is StateError &&
      error.message == 'STORAGE_BLOCKED' &&
      _store.hasPendingMcpAuthorityPublication;

  // Only synchronous, side-effect-free authority checks enter this retry loop.
  Future<T> _stable<T>(T Function() read, Duration deadline) async {
    final watch = Stopwatch()..start();
    while (true) {
      if (_closed) throw StateError('UNAUTHORIZED');
      final remaining = deadline - watch.elapsed;
      if (remaining <= Duration.zero) throw StateError('TIMEOUT');
      try {
        return read();
      } catch (error) {
        if (!_publicationPause(error)) rethrow;
        final closed = Completer<void>();
        _interests.add(closed);
        try {
          await Future.any<void>([
            _store.waitForMcpAuthority(deadline: remaining),
            closed.future.then((_) => throw StateError('UNAUTHORIZED')),
          ]);
        } finally {
          _interests.remove(closed);
        }
      }
    }
  }

  void Function() onGrantPublished(void Function(String, int) listener) =>
      _store.onMcpGrantPublished(listener);

  ClientGrantRecord _current(String id) {
    if (_closed) throw StateError('UNAUTHORIZED');
    return _read(id);
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

  Future<void> _closeAndDrain() {
    final previous = _draining;
    if (previous != null) return previous.future;
    final done = _draining = Completer<void>();
    close();
    if (_working == 0) done.complete();
    return done.future;
  }
}

extension _GrantOpen<P> on _GrantSessionRequest<P> {
  Duration _openRemaining() {
    _live();
    if (_registry.targetChangesBlocked) throw StateError('UNAUTHORIZED');
    final remaining = _began + rpcDeadline - _registry._clock();
    if (remaining <= Duration.zero) throw StateError('TIMEOUT');
    return remaining;
  }

  Future<void> _openVerify() async {
    try {
      final budget = _openRemaining();
      await _session.binding
          .revalidate(
            remaining: _openRemaining,
            scopes: [_session.nativeScope, nativeScope],
          )
          .timeout(budget);
      _openRemaining();
    } on NativeControlLocalFailure catch (error) {
      error.rethrowCause();
    } on TimeoutException {
      throw StateError('TIMEOUT');
    }
  }

  Future<(ClientGrantRecord, McpOpenResult)> _openWork(
    _McpAuthority authority,
    McpOpenRequest input,
  ) async {
    McpGrantKey? owned;
    try {
      _openRemaining();
      await authority._stable(
        () => authority._current(input.grantId),
        _openRemaining(),
      );
      await _openVerify();
      owned = await authority._openKey(input.grantId, _openRemaining());
      _openRemaining();
      await authority._stable(
        () => authority._exact(owned!.grant),
        _openRemaining(),
      );
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
      await authority._stable(
        () => authority._exact(owned!.grant),
        _openRemaining(),
      );
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
      await authority._stable(
        () => authority._exact(owned!.grant),
        _openRemaining(),
      );
      await _openVerify();
      await authority._stable(
        () => authority._exact(owned!.grant),
        _openRemaining(),
      );
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
      if (authority._working == 0) authority._draining?.complete();
    }
  }
}
