part of 'operational_auth.dart';

/// Native-backed operation context, independent of one RPC's response interest.
/// No public constructor, role override, key, serialization or owner fallback.
final class OperationalMcpContext extends _McpContext<OperationalPipePeer> {
  OperationalMcpContext._(
    OperationalSessions registry,
    String channel,
    _Session<OperationalPipePeer> session,
  ) : super._(registry, channel, session);
  bool belongsTo(
    OperationalSessions sessions,
    OperationalMcpAuthority authority,
  ) => _belongsTo(sessions, authority);
}

final class TrustedMcpContext extends _McpContext<TrustedPipePeer> {
  TrustedMcpContext._(
    TrustedSessions registry,
    String channel,
    _Session<TrustedPipePeer> session,
  ) : super._(registry, channel, session);
  Object get connectionInterest => _session.connectionInterest;
  Future<void> get detached => _session.detached.future;
  bool belongsTo(TrustedSessions sessions, TrustedMcpAuthority authority) =>
      _belongsTo(sessions, authority);
}

sealed class _McpContext<P> {
  _McpContext._(this._registry, this._channel, this._session);
  final _Sessions<P> _registry;
  final String _channel;
  final _Session<P> _session;
  String get sessionId => _session.id;
  String get grantId => _session.grant!.id;
  String get workspaceId => _session.grant!.workspaceId;
  int get revision => _session.grant!.revision;
  bool _belongsTo(_Sessions<P> sessions, _McpAuthority authority) =>
      identical(_registry, sessions) &&
      identical(_session.authority, authority);

  ClientGrantRecord _current() {
    if (!_registry._current(_channel, _session))
      throw StateError('UNAUTHORIZED');
    try {
      return _session.authority!._exact(_session.grant!);
    } catch (error) {
      if (_session.authority!._publicationPause(error)) rethrow;
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

  Future<void> authorizeWhenStable({
    McpScope? scope,
    String? serverId,
    Duration deadline = rpcDeadline,
  }) => _session.authority!._stable(
    () => authorize(scope: scope, serverId: serverId),
    deadline,
  );

  Future<GrantScopePolicy> policyWhenStable({
    Duration deadline = rpcDeadline,
  }) => _session.authority!._stable(() => policy, deadline);

  Future<void> revalidate({
    Duration deadline = rpcDeadline,
    void Function(Future<void>)? observeNativeCompletion,
  }) async {
    final watch = Stopwatch()..start();
    Duration remaining() {
      final left = deadline - watch.elapsed;
      if (left <= Duration.zero) throw StateError('TIMEOUT');
      return left;
    }

    while (true) {
      await _session.authority!._stable(_current, remaining());
      try {
        final budget = remaining();
        final actual = _session.binding.revalidate(
          observeNativeCompletion: observeNativeCompletion,
        );
        actual.ignore();
        await actual.timeout(budget);
      } on TimeoutException {
        throw StateError('TIMEOUT');
      } catch (error) {
        if (error is StateError && error.message == 'RESOURCE_LIMIT') rethrow;
        if (identical(_registry._sessions[_channel], _session))
          _registry.disconnect(_channel);
        throw StateError('UNAUTHORIZED');
      }
      remaining();
      try {
        _current();
        return;
      } catch (error) {
        if (!_session.authority!._publicationPause(error)) rethrow;
      }
    }
  }
}
