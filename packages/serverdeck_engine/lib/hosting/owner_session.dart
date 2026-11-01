part of 'sessions.dart';

/// Local-only binding issued after HostAuthority validates its opaque capability.
/// Strings from a request cannot recreate this object or enter owner admission.
final class OwnerSession {
  OwnerSession._(this._registry, this._capability, this._channel, this._record);
  final EngineSessions _registry;
  final OwnerCapability _capability;
  final String _channel;
  final _Session<_SessionPeer> _record;
  bool get isCurrent =>
      !_capability.isRevoked && _registry._current(_channel, _record);
  String get generation => _registry.generation;

  /// Bookkeeping clock only; reading it never admits an operation.
  Duration get clockElapsed => _registry._clock();
  SessionRequest reserve(String method, {Duration? expiresAt}) {
    if (!isCurrent) throw StateError('UNAUTHORIZED');
    final request =
        _registry._reserve(_channel, _record.id, method) as SessionRequest;
    try {
      if (expiresAt != null) {
        if (expiresAt > request._began + rpcDeadline)
          throw StateError('VALIDATION');
        request._expiresAt = expiresAt;
        request.rpcBudgetRemaining;
      }
      return request;
    } catch (_) {
      request.complete();
      rethrow;
    }
  }

  Future<void> admit(SessionRequest request) {
    if (!isCurrent ||
        !identical(request._session, _record) ||
        !request.belongsTo(_registry))
      return Future.error(StateError('UNAUTHORIZED'));
    return _registry.completeAdmission(request);
  }

  void close() {
    if (identical(_registry._sessions[_channel], _record))
      _registry.disconnect(_channel);
  }
}
