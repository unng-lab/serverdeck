part of 'sessions.dart';

const _mcpMethods = {
  'readiness.get',
  'session.ping',
  'session.close',
  'mcp.open',
  'mcp.invoke',
  'mcp.close',
};

/// Worker-internal pause identity, never a credential or a wire value. Only the
/// same registry can consume its current pause after Host resume revalidation.
final class SessionAdmissionPause {
  SessionAdmissionPause._(this._registry, this._epoch);
  final EngineSessions _registry;
  final int _epoch;
}

/// Same-registry sessions backed only by the target native identity proof.
/// Public methods cannot mint a verified role or register a session.
final class EngineSessions extends _Sessions<_SessionPeer> {
  static final _hosts = Expando<EngineSessions>();
  factory EngineSessions.withAuthority({
    required HostAuthority authority,
    required bool Function() admissionBlocked,
    Duration Function()? elapsed,
    void Function(String)? onDetached,
    void Function(String)? onExpiredChannel,
    void Function()? onChanged,
  }) {
    final gate = authority.publicationGate;
    if (_hosts[authority] != null) throw StateError('NOT_READY');
    final registry = EngineSessions._(
      authority,
      admissionBlocked: admissionBlocked,
      elapsed: elapsed,
      onDetached: onDetached,
      onExpiredChannel: onExpiredChannel,
      onChanged: onChanged,
    );
    registry._targets = TargetChanges(
      gate: gate,
      isStopping: () => registry._stopping,
      retireMcp: registry._retireMcp,
      onFailure: registry.stop,
    );
    _hosts[authority] = registry;
    return registry;
  }
  EngineSessions._(
    this._host, {
    required this.admissionBlocked,
    super.elapsed,
    super.onDetached,
    super.onExpiredChannel,
    super.onChanged,
  }) : super(generation: _host.generation);
  final HostAuthority _host;
  @override
  final bool Function() admissionBlocked;
  final _owners = Map<OwnerCapability, OwnerSession>.identity();
  final _opening = Map<OwnerCapability, Future<OwnerSession>>.identity();
  SessionAdmissionPause? _pause;
  int _admissionRetirements = 0;

  /// Synchronously fences external admission and retires all observation
  /// interests. Physical request/proof ownership is retained by normal drains;
  /// this is not a cancellation of an accepted mutation or remote job.
  SessionAdmissionPause pauseAdmission() {
    if (_stopping) throw StateError('SERVICE_UNAVAILABLE');
    _admissionPaused = true;
    _pause = SessionAdmissionPause._(this, ++_admissionEpoch);
    _admissionRetirements++;
    try {
      var failed = false;
      for (final channel in _sessions.keys.toList()) {
        try {
          disconnect(channel);
        } catch (_) {
          failed = true;
        }
      }
      for (final request in _requests.toList()) request.complete();
      if (failed) {
        // A failed retirement cannot later be treated as a successful suspend.
        stop();
        throw StateError('SERVICE_UNAVAILABLE');
      }
      // Nested pauses advance the epoch. Return the current fence so the outer
      // caller can resume once all synchronous retirement frames have unwound.
      return _pause!;
    } finally {
      _admissionRetirements--;
    }
  }

  /// Host must first finish its same-incarnation physical suspend and recheck
  /// vault/runtime/lease/capabilities/revisions. This method proves no such work
  /// by itself and cannot revive records, pending proofs or prior MCP channels.
  void resumeAdmission(SessionAdmissionPause pause) {
    if (_stopping) throw StateError('SERVICE_UNAVAILABLE');
    if (_admissionRetirements != 0 ||
        !identical(pause._registry, this) ||
        !identical(_pause, pause) ||
        pause._epoch != _admissionEpoch) {
      throw StateError('NOT_READY');
    }
    _pause = null;
    _admissionPaused = false;
  }

  /// Quiescence of retired admissions, not permanent registry closure. Native
  /// proof chains remain charged until all their late phases have settled.
  Future<void> drainRetiredAdmissions() async {
    if (!_admissionPaused && !_stopping) throw StateError('NOT_READY');
    while (_requests.isNotEmpty ||
        _peerProofs.isNotEmpty ||
        _opening.isNotEmpty) {
      await Future.wait<void>([
        for (final request in _requests.toList()) request.settled,
        ..._peerProofs.toList(),
        for (final opening in _opening.values.toList())
          opening.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
      ]);
    }
  }

  Future<OwnerSession> openOwner(OwnerCapability capability) {
    try {
      _requireAdmission();
    } catch (error, stack) {
      return Future.error(error, stack);
    }
    try {
      expire();
    } catch (_) {
      return Future.error(StateError('UNAUTHORIZED'));
    }
    try {
      _requireAdmission();
    } catch (error, stack) {
      return Future.error(error, stack);
    }
    final epoch = _admissionEpoch;
    final previous = _owners[capability];
    if (previous != null && previous.isCurrent) {
      return _host.validateOwner(capability).then((_) {
        _requireAdmission(epoch);
        if (!previous.isCurrent) throw StateError('UNAUTHORIZED');
        return previous;
      });
    }
    final pending = _opening[capability];
    if (pending != null) return pending;
    if (count + _opening.length >= maxSessions)
      return Future.error(StateError('RESOURCE_LIMIT'));
    final work = _openOwner(capability);
    _opening[capability] = work;
    work
        .then<void>(
          (_) {
            _opening.remove(capability);
          },
          onError: (Object _, StackTrace __) {
            _opening.remove(capability);
          },
        )
        .ignore();
    return work;
  }

  Future<OwnerSession> _openOwner(OwnerCapability capability) async {
    final epoch = _admissionEpoch;
    final channel = 'owner:${_randomNonce()}', id = _randomNonce();
    final peer = _OwnerPeer(_host, capability);
    try {
      await _host.validateOwner(capability);
      _requireAdmission(epoch);
      final hello = OperationalHello(
        generation: generation,
        serverNonce: _randomNonce(),
        buildId: _host.runtime.buildId,
        clientRole: OperationalRole.owner,
      );
      _register(channel, id, hello, peer, peer, admissionEpoch: epoch);
      final owner = OwnerSession._(
        this,
        capability,
        channel,
        _sessions[channel]!,
      );
      _owners[capability] = owner;
      return owner;
    } catch (error) {
      if (identical(_sessions[channel]?.peer, peer)) {
        try {
          disconnect(channel);
        } catch (_) {
          /* Removed before callbacks. */
        }
      }
      if (error is StateError &&
          const {
            'UNAUTHORIZED',
            'TIMEOUT',
            'RESOURCE_LIMIT',
            'SERVICE_UNAVAILABLE',
            'NOT_READY',
            'INCOMPATIBLE',
          }.contains(error.message))
        rethrow;
      throw StateError('UNAUTHORIZED');
    }
  }

  @override
  SessionRequest _makeRequest(
    String channel,
    _Session<_SessionPeer> session,
    String method,
  ) => SessionRequest._(this, channel, session, method);
  Future<SessionRequest> begin(String channel, String id, String method) async {
    final request = reserve(channel, id, method);
    await completeAdmission(request);
    return request;
  }

  SessionRequest reserve(String channel, String id, String method) =>
      _reserveMcp(channel, id, method);
  SessionRequest _reserveMcp(String channel, String id, String method) {
    if (_sessions[channel]?.role != OperationalRole.mcp)
      throw StateError('UNAUTHORIZED');
    return _reserve(channel, id, method) as SessionRequest;
  }

  Future<ReconciledTargetChangeLease> beginReconciledTargetChange({
    Duration deadline = rpcDeadline,
  }) {
    if (_stopping) return Future.error(StateError('SERVICE_UNAVAILABLE'));
    final targets = _targets;
    if (targets == null) return Future.error(StateError('NOT_READY'));
    return targets.beginReconciled(deadline);
  }
}

sealed class _Sessions<P> {
  bool Function() get admissionBlocked;
  _SessionRequest<P> _makeRequest(
    String channel,
    _Session<P> session,
    String method,
  );
  _Sessions({
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
  final _sessions = <String, _Session<P>>{};
  final _detachListeners = <void Function(String)>{};
  final _requests = <_SessionRequest<P>>{};
  final _peerProofs = <Future<void>>{};
  void _ownPeerProof(Future<void> physical) {
    if (_stopping) throw StateError('SERVICE_UNAVAILABLE');
    if (_peerProofs.length >= 256) throw StateError('RESOURCE_LIMIT');
    _peerProofs.add(physical);
    physical
        .then<void>(
          (_) {
            _peerProofs.remove(physical);
          },
          onError: (Object _, StackTrace __) {
            _peerProofs.remove(physical);
          },
        )
        .ignore();
  }

  TargetChanges? _targets;
  Future<void>? _closeFuture;

  int get targetChangeInterests => _targets?.interests ?? 0;
  bool get hasPublicationGate =>
      !_stopping && _targets != null && !_targets!.gate.isClosed;

  bool get targetChangesBlocked =>
      _stopping ||
      ((_targets?.interests ?? 0) != 0) ||
      (_targets?.gate.isClosed ?? false);

  /// The synchronous call reserves the open fence before any native await.
  /// Each mutation owns its own gate lease; overlapping mutations serialize.
  Future<TargetChangeLease> beginTargetChange({
    Duration deadline = rpcDeadline,
  }) {
    if (_stopping) return Future.error(StateError('SERVICE_UNAVAILABLE'));
    final targets = _targets;
    if (targets == null) return Future.error(StateError('NOT_READY'));
    return targets.begin(deadline);
  }

  /// Trusted authority services enter before joining the store's write queue.
  /// The effect remains owned through actual completion after a reply timeout.
  Future<T> runAuthorityMutation<T>(
    Future<T> Function() effect, {
    Duration deadline = rpcDeadline,
    void Function(Future<void>)? observeNativeCompletion,
  }) {
    if (_stopping) return Future.error(StateError('SERVICE_UNAVAILABLE'));
    final targets = _targets;
    if (targets == null) return Future.error(StateError('NOT_READY'));
    return targets.runAuthority(
      effect,
      deadline,
      observeNativeCompletion: observeNativeCompletion,
    );
  }

  Future<void> close() {
    if (_closeFuture != null) return _closeFuture!;
    final done = Completer<void>();
    _closeFuture = done.future;
    done.future.ignore();
    var failed = false;
    try {
      stop();
    } catch (_) {
      failed = true;
    }
    Future<void>(() async {
      try {
        await Future.wait<void>([
          if (_targets != null) _targets!.close(),
          for (final request in _requests.toList()) request.settled,
          ..._peerProofs.toList(),
        ]);
      } catch (_) {
        failed = true;
      }
      if (failed) throw StateError('SERVICE_UNAVAILABLE');
    }).then<void>(
      (_) => done.complete(),
      onError: (Object _) =>
          done.completeError(StateError('SERVICE_UNAVAILABLE')),
    );
    return done.future;
  }

  void Function() onSessionDetached(void Function(String) listener) {
    if (_stopping) throw StateError('NOT_READY');
    _detachListeners.add(listener);
    return () => _detachListeners.remove(listener);
  }

  bool _stopping = false;
  bool _admissionPaused = false;
  int _admissionEpoch = 0;
  void _requireAdmission([int? epoch]) {
    if (_stopping) throw StateError('SERVICE_UNAVAILABLE');
    if (_admissionPaused ||
        admissionBlocked() ||
        epoch != null && epoch != _admissionEpoch) {
      throw StateError('NOT_READY');
    }
  }

  int get count => _sessions.length;
  int get mcpCount =>
      _sessions.values.where((s) => s.role == OperationalRole.mcp).length;
  Duration? get nextExpiry => _sessions.isEmpty
      ? null
      : _sessions.values.map((s) => s.expires).reduce((a, b) => a < b ? a : b);

  void _register(
    String channel,
    String id,
    OperationalHello hello,
    P peer,
    _SessionPeer binding, {
    required int admissionEpoch,
  }) {
    _requireAdmission(admissionEpoch);
    expire();
    _requireAdmission(admissionEpoch);
    if (hello.generation != generation ||
        hello.buildId != binding.buildId ||
        hello.clientRole != _sessionRole(binding) ||
        _sessions.containsKey(channel) ||
        _sessions.values.any((s) => s.id == id))
      throw StateError('UNAUTHORIZED');
    if (count >= maxSessions ||
        hello.clientRole == OperationalRole.mcp && mcpCount >= 4) {
      throw StateError('RESOURCE_LIMIT');
    }
    final session = _Session<P>(
      id,
      hello,
      peer,
      binding,
      _clock() + sessionLease,
    );
    _sessions[channel] = session;
    _onChanged?.call();
    if (!_current(channel, session)) throw StateError('UNAUTHORIZED');
  }

  bool _current(String channel, _Session<P> session) =>
      !_stopping &&
      !_admissionPaused &&
      !admissionBlocked() &&
      identical(_sessions[channel], session) &&
      _clock() < session.expires &&
      session.binding.isCurrent;

  _SessionRequest<P> _reserve(String channel, String id, String method) {
    _requireAdmission();
    expire();
    final session = _sessions[channel];
    if (session == null || session.id != id || !_current(channel, session))
      throw StateError('UNAUTHORIZED');
    if (session.role == OperationalRole.mcp && !_mcpMethods.contains(method) ||
        session.role == OperationalRole.owner && method.startsWith('mcp.'))
      throw StateError('FORBIDDEN');
    if (method == 'mcp.invoke' && session.grant == null)
      throw StateError('FORBIDDEN');
    if (session.pending >= maxPendingPerSession || _requests.length >= 256)
      throw StateError('RESOURCE_LIMIT');
    session.pending++;
    final request = _makeRequest(channel, session, method);
    _requests.add(request);
    return request;
  }

  Future<void> completeAdmission(_SessionRequest<P> request) {
    if (!request.belongsTo(this)) return Future.error(StateError('FORBIDDEN'));
    try {
      request._identityLive();
      return request._initialAdmission ??= _completeAdmission(request);
    } catch (error, stack) {
      return Future.error(error, stack);
    }
  }

  Future<void> _completeAdmission(_SessionRequest<P> request) async {
    try {
      try {
        final budget = request.rpcBudgetRemaining;
        await request.revalidate().timeout(budget);
      } on TimeoutException {
        throw StateError('TIMEOUT');
      }
      void admitted() {
        request._live();
        request._session.expires = _clock() + sessionLease;
        request._initialAdmissionProved = true;
      }

      final authority = request._session.authority;
      if (authority == null) {
        admitted();
      } else {
        await authority._stable(admitted, request.rpcBudgetRemaining);
      }
      _onChanged?.call();
    } catch (_) {
      request.complete();
      rethrow;
    }
  }

  void _retireMcp(Set<String>? affected) {
    var failed = false;
    for (final entry in _sessions.entries.toList()) {
      final session = entry.value;
      if (session.role != OperationalRole.mcp) continue;
      if (affected != null &&
          session.grant != null &&
          !affected.any(session.grant!.policy.allowsServer))
        continue;
      try {
        disconnect(entry.key);
      } catch (_) {
        failed = true;
      }
    }
    if (failed) throw StateError('UNAUTHORIZED');
  }

  void disconnect(String channel) {
    _remove(channel, _clock());
  }

  void _remove(String channel, Duration at) {
    final session = _sessions.remove(channel);
    if (session == null) return;
    session.detached.complete();
    if (this is EngineSessions) {
      (this as EngineSessions)._owners.removeWhere(
        (_, owner) => identical(owner._record, session),
      );
    }
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
    _targets?.stop();
    var failed = false;
    try {
      for (final channel in _sessions.keys.toList()) {
        try {
          disconnect(channel);
        } catch (_) {
          failed = true;
        }
      }
    } finally {
      for (final request in _requests.toList()) request.complete();
      _watch.stop();
    }
    if (failed) throw StateError('UNAUTHORIZED');
  }
}

final class _Session<P> {
  _Session(this.id, this.hello, this.peer, this.binding, this.expires);
  final String id;
  final OperationalHello hello;
  final P peer;
  final _SessionPeer binding;
  OperationalRole get role => hello.clientRole;
  Duration expires;
  int pending = 0;
  bool openAttempted = false;
  final detached = Completer<void>();
  final connectionInterest = Object();
  _McpAuthority? authority;
  ClientGrantRecord? grant;
}

sealed class _SessionRequest<P> {
  _SessionRequest._(this._registry, this.channel, this._session, this.method)
    : _began = _registry._clock();
  final _Sessions<P> _registry;
  final _Session<P> _session;
  final String channel, method;
  final Duration _began;
  Duration? _expiresAt;
  bool belongsTo(_Sessions<P> registry) => identical(_registry, registry);
  bool _completed = false;
  bool _initialAdmissionProved = false;
  Future<void>? _initialAdmission;
  final _proofs = <Future<void>>{};
  void _observe(Future<void> actual) {
    final tracked = actual.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _proofs.add(tracked);
    tracked.then<void>((_) => _proofs.remove(tracked));
  }

  Future<void> get settled async {
    while (_proofs.isNotEmpty) await Future.wait<void>(_proofs.toList());
  }

  // Proof ownership only. It is also used by the narrowly-scoped detached-open
  // permit, whose separate guards deliberately do not require a live record.
  Future<void> _proveBinding(
    Duration budget, {
    void Function(Future<void>)? observer,
  }) async {
    final actual = _session.binding.revalidate(
      observeNativeCompletion: (physical) {
        _observe(physical);
        observer?.call(physical);
      },
    );
    _observe(actual);
    actual.ignore();
    await actual.timeout(budget);
  }

  bool get initialAdmissionProved {
    _identityLive();
    return _initialAdmissionProved;
  }

  Duration get rpcRemaining {
    _live();
    return rpcBudgetRemaining;
  }

  /// Bookkeeping only. Never authorizes an effect or an output frame.
  Duration get rpcBudgetRemaining {
    _identityLive();
    final value = (_expiresAt ?? _began + rpcDeadline) - _registry._clock();
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

  void _identityLive() {
    if (_completed || !_registry._current(channel, _session))
      throw StateError('UNAUTHORIZED');
  }

  void _live() {
    _identityLive();
    final grant = _session.grant;
    if (grant != null) {
      try {
        _session.authority!._exact(grant);
      } catch (error) {
        if (_session.authority!._publicationPause(error)) rethrow;
        _detach();
        rethrow;
      }
    }
  }

  void _detach() {
    if (identical(_registry._sessions[channel], _session))
      _registry.disconnect(channel);
  }

  Future<void> _stableLive() async {
    _identityLive();
    final authority = _session.authority;
    if (authority == null) {
      _live();
      return;
    }
    await authority._stable(_live, rpcBudgetRemaining);
  }

  bool isAuthorityPublicationPause(Object error) =>
      _session.authority?._publicationPause(error) ?? false;

  Future<void> revalidate({
    void Function(Future<void>)? observeNativeCompletion,
  }) async {
    while (true) {
      await _stableLive();
      try {
        final budget = rpcBudgetRemaining;
        await _proveBinding(budget, observer: observeNativeCompletion);
      } on TimeoutException {
        throw StateError('TIMEOUT');
      } catch (error) {
        if (error is StateError && error.message == 'RESOURCE_LIMIT') rethrow;
        // Never remove a different session that subsequently reused a channel ID.
        if (identical(_registry._sessions[channel], _session))
          _registry.disconnect(channel);
        throw StateError('UNAUTHORIZED');
      }
      rpcBudgetRemaining;
      try {
        _live();
        return;
      } catch (error) {
        if (!isAuthorityPublicationPause(error)) rethrow;
      }
    }
  }

  void complete() {
    if (_completed) return;
    _completed = true;
    settled.then<void>((_) {
      _session.pending--;
      _registry._requests.remove(this);
    }).ignore();
  }
}

final class SessionRequest extends _GrantSessionRequest<_SessionPeer> {
  SessionRequest._(
    EngineSessions registry,
    String channel,
    _Session<_SessionPeer> session,
    String method,
  ) : super._(registry, channel, session, method);
  Object get connectionInterest {
    _live();
    return _session.connectionInterest;
  }

  TrustedOwnerConnectionContext? _ownerConnection;
  TrustedOwnerAutomationContext? _ownerAutomation;
  Future<String> verifiedOwnerBundleRoot() async {
    _live();
    if (_session.role != OperationalRole.owner || !_initialAdmissionProved)
      throw StateError('FORBIDDEN');
    final peer = _session.peer;
    if (peer is! _OwnerPeer) throw StateError('FORBIDDEN');
    await _proveBinding(rpcRemaining);
    final root = peer.host.runtime.appRoot;
    rpcRemaining;
    return root;
  }

  TrustedOwnerAutomationContext ownerAutomationContext() {
    _live();
    if (_session.role != OperationalRole.owner ||
        !TrustedOwnerAutomationContext.methods.contains(method) ||
        !_initialAdmissionProved)
      throw StateError('FORBIDDEN');
    rpcRemaining;
    return _ownerAutomation ??= TrustedOwnerAutomationContext._(
      _registry as EngineSessions,
      channel,
      _session,
      _began,
      method,
    );
  }

  TrustedOwnerReadContext? _ownerRead;
  TrustedOwnerReadContext ownerReadContext() {
    _live();
    if (_session.role != OperationalRole.owner ||
        !const {
          'servers.state',
          'servers.logs',
          'servers.configuration',
          'servers.executorInspect',
          'servers.recipes',
        }.contains(method) ||
        !_initialAdmissionProved)
      throw StateError('FORBIDDEN');
    rpcRemaining;
    return _ownerRead ??= TrustedOwnerReadContext._(
      _registry as EngineSessions,
      channel,
      _session,
      _began,
    );
  }

  TrustedOwnerConnectionContext ownerConnectionContext() {
    _live();
    if (_session.role != OperationalRole.owner ||
        method != 'servers.connect' ||
        !_initialAdmissionProved)
      throw StateError('FORBIDDEN');
    rpcRemaining;
    return _ownerConnection ??= TrustedOwnerConnectionContext._(
      _registry as EngineSessions,
      channel,
      _session,
      _began,
    );
  }

  TrustedOwnerProbeContext? _ownerProbe;
  TrustedOwnerProbeContext ownerProbeContext() {
    _live();
    if (_session.role != OperationalRole.owner ||
        method != 'servers.trust.probe' ||
        !_initialAdmissionProved)
      throw StateError('FORBIDDEN');
    return _ownerProbe ??= TrustedOwnerProbeContext._(
      _registry as EngineSessions,
      channel,
      _session,
      _began,
    );
  }

  TrustedOpenFailure? _failure;
  TrustedOpenFailure? get openFailure => _openFailureCode == null
      ? null
      : _failure ??= TrustedOpenFailure._(this, _openFailureCode!);
  @override
  TrustedMcpContext _makeContext() =>
      TrustedMcpContext._(_registry as EngineSessions, channel, _session);
  TrustedMcpContext mcpContext() => _context() as TrustedMcpContext;
  Future<TrustedMcpContext> mcpContextWhenStable() async =>
      await _contextWhenStable() as TrustedMcpContext;
  void requireMcpInvocationBinding(
    EngineSessions registry,
    TrustedMcpAuthority authority,
  ) => _requireInvocationBinding(registry, authority);
  Future<McpOpenResult> openGrant(
    TrustedMcpAuthority authority,
    Object? params,
  ) => _openGrant(authority, params);
}

sealed class _GrantSessionRequest<P> extends _SessionRequest<P> {
  _GrantSessionRequest._(
    _Sessions<P> registry,
    String channel,
    _Session<P> session,
    String method,
  ) : super._(registry, channel, session, method);
  bool _firstOpen = false;
  ErrorCode? _openFailureCode;
  _McpContext<P> _makeContext();

  Future<_McpContext<P>> _contextWhenStable() async {
    _identityLive();
    final authority = _session.authority;
    if (authority == null) throw StateError('FORBIDDEN');
    return authority._stable(_context, rpcBudgetRemaining);
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

  _McpContext<P> _context() {
    _live();
    if (method != 'mcp.invoke') throw StateError('FORBIDDEN');
    authorizeMcp();
    return _makeContext();
  }

  /// Native binding gate before payload parsing; this supplies no permission.
  void _requireInvocationBinding(
    _Sessions<P> registry,
    _McpAuthority authority,
  ) {
    _identityLive();
    if (!belongsTo(registry) ||
        method != 'mcp.invoke' ||
        _session.role != OperationalRole.mcp ||
        _session.grant == null ||
        !identical(_session.authority, authority)) {
      throw StateError('FORBIDDEN');
    }
  }

  Future<McpOpenResult> _openGrant(
    _McpAuthority authority,
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
    Completer<void>? finalPhase;
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
      finalPhase = Completer<void>();
      _drainOpen(authority, work, finalPhase.future).ignore();
      final result = await Future.any<(ClientGrantRecord, McpOpenResult)>([
        work,
        _session.detached.future.then((_) => throw StateError('UNAUTHORIZED')),
        interest.future.then((_) => throw StateError('UNAUTHORIZED')),
      ]).timeout(budget);
      await _openVerify();
      await authority._stable(
        () => authority._exact(result.$1),
        _openRemaining(),
      );
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
      finalPhase?.complete();
      authority._interests.remove(interest);
    }
  }
}
