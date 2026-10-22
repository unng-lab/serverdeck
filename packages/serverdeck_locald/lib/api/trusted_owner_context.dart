part of 'operational_auth.dart';

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

  Future<void> revalidate() async {
    final left = remaining;
    final budget = left < rpcDeadline ? left : rpcDeadline;
    try {
      final actual = _session.binding.revalidate();
      final tracked = actual.then<void>(
        (_) {},
        onError: (Object _, StackTrace __) {},
      );
      _proofs.add(tracked);
      tracked.then<void>((_) => _proofs.remove(tracked)).ignore();
      await actual.timeout(budget);
    } on TimeoutException {
      throw StateError('TIMEOUT');
    } catch (error) {
      if (error is StateError && error.message == 'RESOURCE_LIMIT') rethrow;
      if (identical(_registry._sessions[_channel], _session))
        _registry.disconnect(_channel);
      throw StateError('UNAUTHORIZED');
    }
    remaining;
  }
}
