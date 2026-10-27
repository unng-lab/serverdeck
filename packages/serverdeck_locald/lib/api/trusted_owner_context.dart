part of 'operational_auth.dart';

/// Actual admitted owner connection identity; not a transport or trust grant.
/// The original RPC must still be live when this context is first issued.
final class TrustedOwnerConnectionContext extends _TrustedOwnerAsyncContext {
  TrustedOwnerConnectionContext._(
    TrustedSessions registry,
    String channel,
    _Session<TrustedPipePeer> session,
    Duration began,
  ) : super(registry, channel, session, began, const Duration(seconds: 15));
}

/// Admitted owner read identity with one original 30-second operation budget.
final class TrustedOwnerReadContext extends _TrustedOwnerAsyncContext {
  TrustedOwnerReadContext._(
    TrustedSessions registry,
    String channel,
    _Session<TrustedPipePeer> session,
    Duration began,
  ) : super(registry, channel, session, began, const Duration(seconds: 30));
}

/// A fixed admitted owner automation method, independent of its RPC interest.
/// It cannot be minted by MCP, a parsed role, or an owner read operation.
final class TrustedOwnerAutomationContext extends _TrustedOwnerAsyncContext {
  TrustedOwnerAutomationContext._(
    TrustedSessions registry,
    String channel,
    _Session<TrustedPipePeer> session,
    Duration began,
    this.method,
  ) : super(
        registry,
        channel,
        session,
        began,
        const {'jobs.apply', 'jobs.cancel'}.contains(method)
            ? const Duration(hours: 2)
            : const Duration(seconds: 30),
      );
  final String method;

  static const methods = {
    'plans.create',
    'plans.get',
    'jobs.apply',
    'jobs.list',
    'jobs.get',
    'jobs.events',
    'jobs.cancel',
    'jobs.reconcile',
  };
  Set<String> get _executorMethods => switch (method) {
    'plans.create' => {'hello', 'observe', 'preflight', 'preflight_get'},
    'jobs.apply' => {
      'hello',
      'observe',
      'preflight_get',
      'submit',
      'status',
      'authorize_step',
      'cancel',
    },
    'jobs.cancel' => {'hello', 'status', 'cancel'},
    'jobs.reconcile' => {'hello', 'status', 'reconcile'},
    _ => {},
  };
  void authorizeExecutorMethod(String method) {
    remaining;
    if (!_executorMethods.contains(method)) throw StateError('FORBIDDEN');
  }

  void authorizeExecutorScope(McpScope scope) {
    remaining;
    if (_executorMethods.isEmpty ||
        scope == McpScope.author ||
        scope == McpScope.logs ||
        scope == McpScope.apply &&
            !const {'jobs.apply', 'jobs.cancel'}.contains(method) ||
        scope == McpScope.plan &&
            !const {'plans.create', 'jobs.apply'}.contains(method))
      throw StateError('FORBIDDEN');
  }
}

sealed class _TrustedOwnerAsyncContext {
  _TrustedOwnerAsyncContext(
    this._registry,
    this._channel,
    this._session,
    this._began,
    this._budget,
  );
  final TrustedSessions _registry;
  final String _channel;
  final _Session<TrustedPipePeer> _session;
  final Duration _began;
  final Duration _budget;
  final _proofs = <Future<void>>{};
  String get sessionId => _session.id;
  String get generation => _registry.generation;
  Object get connectionInterest => _session.connectionInterest;
  Future<void> get detached => _session.detached.future;
  bool belongsTo(TrustedSessions registry) => identical(registry, _registry);

  /// Session comparison only. Every consumer still owns fresh authorization.
  bool matches(TrustedSessionRequest request) =>
      identical(request._registry, _registry) &&
      identical(request._session, _session) &&
      !request._completed &&
      request._initialAdmissionProved &&
      _session.role == OperationalRole.owner &&
      _registry._current(_channel, _session);

  Duration get remaining {
    if (!_registry._current(_channel, _session))
      throw StateError('UNAUTHORIZED');
    final left = _began + _budget - _registry._clock();
    if (left <= Duration.zero) throw StateError('TIMEOUT');
    return left;
  }

  /// Stop issuing proofs before awaiting physical cleanup, also after timeout.
  Future<void> get settled => Future.wait<void>(_proofs.toList());

  Future<void> revalidate({Duration deadline = rpcDeadline}) async {
    final left = remaining;
    var budget = left < deadline ? left : deadline;
    if (budget > rpcDeadline) budget = rpcDeadline;
    final watch = Stopwatch()..start();
    Duration proofRemaining() {
      final operation = remaining, attempt = budget - watch.elapsed;
      if (attempt <= Duration.zero) throw StateError('TIMEOUT');
      return operation < attempt ? operation : attempt;
    }

    try {
      final ticket = _session.binding.beginRevalidation(
        remaining: proofRemaining,
        scopes: [_session.nativeScope],
      );
      final tracked = ticket.settled.then<void>(
        (_) {},
        onError: (Object _, StackTrace __) {},
      );
      _proofs.add(tracked);
      tracked.then<void>((_) => _proofs.remove(tracked)).ignore();
      await ticket.result;
    } on TimeoutException {
      throw StateError('TIMEOUT');
    } on NativeControlLocalFailure catch (error) {
      error.rethrowCause();
    } catch (error) {
      if (error is StateError && error.message == 'RESOURCE_LIMIT') rethrow;
      if (identical(_registry._sessions[_channel], _session))
        _registry.disconnect(_channel);
      throw StateError('UNAUTHORIZED');
    } finally {
      watch.stop();
    }
    remaining;
  }
}

/// Native identity captured from an admitted format3 owner probe only.
/// It retains no RPC interest, credential or authority to confirm a key.
final class TrustedOwnerProbeContext {
  TrustedOwnerProbeContext._(
    this._registry,
    this._channel,
    this._session,
    this._began,
  );
  final TrustedSessions _registry;
  final String _channel;
  final _Session<TrustedPipePeer> _session;
  final Duration _began;
  final _proofs = <Future<void>>{};
  String get sessionId => _session.id;
  String get generation => _registry.generation;
  Future<void> get detached => _session.detached.future;
  bool belongsTo(TrustedSessions registry) => identical(registry, _registry);

  /// Identity comparison for a later challenge consumer, not authorization.
  /// A challenge may outlive the 30-second probe budget. The consumer still
  /// owns its own fresh native proof, RPC budget, target gate and TTL checks.
  bool matches(TrustedSessionRequest request) =>
      identical(request._registry, _registry) &&
      identical(request._session, _session) &&
      !request._completed &&
      request._initialAdmissionProved &&
      _session.role == OperationalRole.owner &&
      _registry._current(_channel, _session);

  void _current() {
    if (!_registry._current(_channel, _session))
      throw StateError('UNAUTHORIZED');
  }

  /// One service budget, starting at the original synchronous RPC admission.
  /// Completion of that RPC neither invalidates nor renews this budget.
  Duration get remaining {
    _current();
    final left = _began + const Duration(seconds: 30) - _registry._clock();
    if (left <= Duration.zero) throw StateError('TIMEOUT');
    return left;
  }

  /// The probe service must stop issuing proofs and await this physical drain
  /// before retiring its admission slot, including after timeout or detach.
  Future<void> get settled => Future.wait<void>(_proofs.toList());

  Future<void> revalidate({Duration deadline = rpcDeadline}) async {
    final left = remaining;
    var budget = left < deadline ? left : deadline;
    if (budget > rpcDeadline) budget = rpcDeadline;
    final watch = Stopwatch()..start();
    Duration proofRemaining() {
      final operation = remaining, attempt = budget - watch.elapsed;
      if (attempt <= Duration.zero) throw StateError('TIMEOUT');
      return operation < attempt ? operation : attempt;
    }

    try {
      final ticket = _session.binding.beginRevalidation(
        remaining: proofRemaining,
        scopes: [_session.nativeScope],
      );
      final tracked = ticket.settled.then<void>(
        (_) {},
        onError: (Object _, StackTrace __) {},
      );
      _proofs.add(tracked);
      tracked.then<void>((_) => _proofs.remove(tracked)).ignore();
      await ticket.result;
    } on TimeoutException {
      throw StateError('TIMEOUT');
    } on NativeControlLocalFailure catch (error) {
      error.rethrowCause();
    } catch (error) {
      if (error is StateError && error.message == 'RESOURCE_LIMIT') rethrow;
      if (identical(_registry._sessions[_channel], _session))
        _registry.disconnect(_channel);
      throw StateError('UNAUTHORIZED');
    } finally {
      watch.stop();
    }
    remaining;
  }
}
