part of 'operational_auth.dart';

/// Native-backed operation context, independent of one RPC's response interest.
/// No public constructor, role override, key, serialization or owner fallback.
final class OperationalMcpContext {
  OperationalMcpContext._(this._registry, this._channel, this._session);
  final OperationalSessions _registry;
  final String _channel;
  final _OperationalSession _session;

  String get sessionId => _session.id;
  String get grantId => _session.grant!.id;
  String get workspaceId => _session.grant!.workspaceId;
  int get revision => _session.grant!.revision;
  bool belongsTo(
    OperationalSessions sessions,
    OperationalMcpAuthority authority,
  ) =>
      identical(_registry, sessions) &&
      identical(_session.authority, authority);

  ClientGrantRecord _current() {
    if (!_registry._current(_channel, _session))
      throw StateError('UNAUTHORIZED');
    try {
      return _session.authority!._exact(_session.grant!);
    } catch (_) {
      if (identical(_registry._sessions[_channel], _session))
        _registry.disconnect(_channel);
      rethrow;
    }
  }

  GrantScopePolicy get policy => _current().policy;

  /// The router schedules idle expiry too; these durations never grant access.
  Duration get untilExpiry {
    // A publication/replay may temporarily gate store reads. Timer scheduling
    // uses the already-bound lifetime; publication hooks retire changed grants.
    // Only authorize/revalidate may establish authority for actual work/output.
    if (!_registry._current(_channel, _session) ||
        _session.authority!._closed ||
        !_session.grant!.isCurrentAt(_session.authority!._clock())) {
      if (identical(_registry._sessions[_channel], _session))
        _registry.disconnect(_channel);
      throw StateError('UNAUTHORIZED');
    }
    final wall = _session.grant!.expiresAt.difference(
      _session.authority!._clock(),
    );
    final lease = _session.expires - _registry._clock();
    return wall < lease ? wall : lease;
  }

  void authorize({McpScope? scope, String? serverId}) {
    final grant = _current();
    if (scope != null && !grant.policy.allowsScope(scope) ||
        serverId != null && !grant.policy.allowsServer(serverId))
      throw StateError('FORBIDDEN');
  }

  Future<void> revalidate({Duration deadline = rpcDeadline}) async {
    _current();
    if (deadline <= Duration.zero) throw StateError('TIMEOUT');
    try {
      await _session.peer.revalidate().timeout(deadline);
    } on TimeoutException {
      throw StateError('TIMEOUT');
    } catch (error) {
      if (error is StateError && error.message == 'RESOURCE_LIMIT') rethrow;
      if (identical(_registry._sessions[_channel], _session))
        _registry.disconnect(_channel);
      throw StateError('UNAUTHORIZED');
    }
    _current();
  }
}
