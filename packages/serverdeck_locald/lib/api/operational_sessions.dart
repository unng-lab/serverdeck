part of 'operational_auth.dart';

const _mcpMethods = {
  'readiness.get',
  'session.ping',
  'session.close',
  'mcp.open',
  'mcp.invoke',
  'mcp.close',
};

/// Same owner-isolate registry for all operational owner/MCP channels. Public
/// methods cannot create a session or change its verified role.
final class OperationalSessions {
  OperationalSessions({
    required this.generation,
    Duration Function()? elapsed,
    void Function(String)? onDetached,
    void Function(String)? onExpiredChannel,
    void Function()? onChanged,
  }) : _onDetached = onDetached,
       _onExpiredChannel = onExpiredChannel,
       _onChanged = onChanged {
    requireUuid(generation);
    _clock = elapsed ?? () => _watch.elapsed;
  }
  final String generation;
  final _watch = Stopwatch()..start();
  late final Duration Function() _clock;
  final void Function(String)? _onDetached, _onExpiredChannel;
  final void Function()? _onChanged;
  final _sessions = <String, _OperationalSession>{};
  final _detachListeners = <void Function(String)>{};

  void Function() onSessionDetached(void Function(String) listener) {
    if (_stopping) throw StateError('NOT_READY');
    _detachListeners.add(listener);
    return () => _detachListeners.remove(listener);
  }

  bool _stopping = false;
  Duration? _emptyAt;
  int get count => _sessions.length;
  int get mcpCount =>
      _sessions.values.where((s) => s.role == OperationalRole.mcp).length;
  Duration? get emptyAt => _emptyAt;
  Duration? get nextExpiry => _sessions.isEmpty
      ? null
      : _sessions.values.map((s) => s.expires).reduce((a, b) => a < b ? a : b);

  void _register(
    String channel,
    String id,
    OperationalHello hello,
    OperationalPipePeer peer,
  ) {
    if (_stopping) throw StateError('NOT_READY');
    expire();
    if (_stopping) throw StateError('NOT_READY');
    if (hello.generation != generation ||
        hello.buildId != peer.buildId ||
        hello.clientRole != _clientRole(peer) ||
        _sessions.containsKey(channel) ||
        _sessions.values.any((s) => s.id == id))
      throw StateError('UNAUTHORIZED');
    if (count >= maxSessions ||
        hello.clientRole == OperationalRole.mcp && mcpCount >= 4) {
      throw StateError('RESOURCE_LIMIT');
    }
    final session = _OperationalSession(
      id,
      hello,
      peer,
      _clock() + sessionLease,
    );
    _sessions[channel] = session;
    _emptyAt = null;
    _onChanged?.call();
    if (!_current(channel, session)) throw StateError('UNAUTHORIZED');
  }

  bool _current(String channel, _OperationalSession session) =>
      !_stopping &&
      identical(_sessions[channel], session) &&
      _clock() < session.expires;

  /// Reserve bounded interest synchronously before awaiting a native proof.
  /// The method gate runs before any method-specific payload/object lookup.
  Future<OperationalSessionRequest> begin(
    String channel,
    String id,
    String method,
  ) async {
    expire();
    final session = _sessions[channel];
    if (session == null || session.id != id || !_current(channel, session))
      throw StateError('UNAUTHORIZED');
    if (session.role == OperationalRole.mcp && !_mcpMethods.contains(method) ||
        session.role == OperationalRole.owner && method.startsWith('mcp.'))
      throw StateError('FORBIDDEN');
    if (method == 'mcp.invoke' && session.grant == null)
      throw StateError('FORBIDDEN');
    if (session.pending >= maxPendingPerSession)
      throw StateError('RESOURCE_LIMIT');
    session.pending++;
    final request = OperationalSessionRequest._(this, channel, session, method);
    try {
      await request.revalidate();
      session.expires = _clock() + sessionLease;
      _onChanged?.call();
      request._live();
      return request;
    } catch (_) {
      request.complete();
      rethrow;
    }
  }

  void disconnect(String channel) {
    _remove(channel, _clock());
  }

  void _remove(String channel, Duration at) {
    final session = _sessions.remove(channel);
    if (session == null) return;
    session.detached.complete();
    if (_sessions.isEmpty) _emptyAt = at;
    var listenerFailed = false;
    for (final listener in _detachListeners.toList()) {
      try {
        listener(session.id);
      } catch (_) {
        listenerFailed = true;
      }
    }
    try {
      _onDetached?.call(session.id);
    } catch (_) {
      listenerFailed = true;
    }
    try {
      _onChanged?.call();
    } catch (_) {
      listenerFailed = true;
    }
    if (listenerFailed) throw StateError('UNAUTHORIZED');
  }

  void expire() {
    final now = _clock();
    final due = _sessions.entries.where((e) => now >= e.value.expires).toList()
      ..sort((a, b) => a.value.expires.compareTo(b.value.expires));
    for (final entry in due) {
      if (!identical(_sessions[entry.key], entry.value)) continue;
      _remove(entry.key, entry.value.expires);
      _onExpiredChannel?.call(entry.key);
    }
  }

  void stop() {
    if (_stopping) return;
    _stopping = true;
    for (final channel in _sessions.keys.toList()) disconnect(channel);
    _watch.stop();
  }
}

final class _OperationalSession {
  _OperationalSession(this.id, this.hello, this.peer, this.expires);
  final String id;
  final OperationalHello hello;
  final OperationalPipePeer peer;
  OperationalRole get role => hello.clientRole;
  Duration expires;
  int pending = 0;
  bool openAttempted = false;
  final detached = Completer<void>();
  OperationalMcpAuthority? authority;
  ClientGrantRecord? grant;
}

final class OperationalSessionRequest {
  OperationalSessionRequest._(
    this._registry,
    this.channel,
    this._session,
    this.method,
  ) : _began = _registry._clock();
  final OperationalSessions _registry;
  final _OperationalSession _session;
  final String channel, method;
  final Duration _began;
  bool _completed = false;
  bool _firstOpen = false;
  OperationalOpenFailure? _openFailure;
  OperationalOpenFailure? get openFailure => _openFailure;
  Duration get rpcRemaining {
    _live();
    final value = _began + rpcDeadline - _registry._clock();
    if (value <= Duration.zero) throw StateError('TIMEOUT');
    return value;
  }

  OperationalRole get role {
    _live();
    return _session.role;
  }

  String get sessionId {
    _live();
    return _session.id;
  }

  OperationalHello get hello {
    _live();
    return _session.hello;
  }

  void _live() {
    if (_completed || !_registry._current(channel, _session))
      throw StateError('UNAUTHORIZED');
    final grant = _session.grant;
    if (grant != null) {
      try {
        _session.authority!._exact(grant);
      } catch (_) {
        _detach();
        rethrow;
      }
    }
  }

  void _detach() {
    if (identical(_registry._sessions[channel], _session))
      _registry.disconnect(channel);
  }

  /// Consult live policy before object lookup and again before publishing results.
  ClientGrantRecord authorizeMcp({McpScope? scope, String? serverId}) {
    _live();
    if (_session.role != OperationalRole.mcp || _session.grant == null)
      throw StateError('FORBIDDEN');
    final grant = _session.authority!._exact(_session.grant!);
    if (scope != null && !grant.policy.allowsScope(scope) ||
        serverId != null && !grant.policy.allowsServer(serverId))
      throw StateError('FORBIDDEN');
    return grant;
  }

  OperationalMcpContext mcpContext() {
    _live();
    if (method != 'mcp.invoke') throw StateError('FORBIDDEN');
    authorizeMcp();
    return OperationalMcpContext._(_registry, channel, _session);
  }

  Future<McpOpenResult> openGrant(
    OperationalMcpAuthority authority,
    Object? params,
  ) async {
    _live();
    if (_session.role != OperationalRole.mcp || method != 'mcp.open')
      throw StateError('FORBIDDEN');
    if (_session.openAttempted) {
      _detach();
      throw StateError('UNAUTHORIZED');
    }
    _firstOpen = true;
    _session.openAttempted = true;
    final interest = Completer<void>();
    try {
      _openRemaining();
      final input = McpOpenRequest.fromJson(params);
      if (authority._closed) throw StateError('UNAUTHORIZED');
      if (authority._working >= 4) throw StateError('RESOURCE_LIMIT');
      final budget = _openRemaining();
      authority._interests.add(interest);
      authority._working++;
      // The work retains its slot through actual completion, even after the
      // caller's timeout/disconnect wins this race. _openWork owns late keys.
      final work = _openWork(authority, input);
      final result = await Future.any<(ClientGrantRecord, McpOpenResult)>([
        work,
        _session.detached.future.then((_) => throw StateError('UNAUTHORIZED')),
        interest.future.then((_) => throw StateError('UNAUTHORIZED')),
      ]).timeout(budget);
      await _openVerify();
      authority._exact(result.$1);
      _openRemaining();
      _session.authority = authority;
      _session.grant = result.$1;
      return result.$2;
    } on TimeoutException {
      _recordOpenFailure('TIMEOUT');
      _detach();
      throw StateError('TIMEOUT');
    } on FormatException {
      _recordOpenFailure('UNAUTHORIZED');
      _detach();
      throw StateError('UNAUTHORIZED');
    } catch (error) {
      _recordOpenFailure(error is StateError ? error.message : null);
      _detach();
      rethrow;
    } finally {
      authority._interests.remove(interest);
    }
  }

  Future<void> revalidate() async {
    _live();
    try {
      await _session.peer.revalidate().timeout(rpcDeadline);
    } catch (error) {
      if (error is StateError && error.message == 'RESOURCE_LIMIT') rethrow;
      // Never remove a different session that subsequently reused a channel ID.
      if (identical(_registry._sessions[channel], _session))
        _registry.disconnect(channel);
      throw StateError('UNAUTHORIZED');
    }
    _live();
  }

  void complete() {
    if (_completed) return;
    _completed = true;
    _session.pending--;
  }
}
