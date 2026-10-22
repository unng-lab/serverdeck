part of 'operational_auth.dart';

extension _FailedOpen<P> on _GrantSessionRequest<P> {
  void _recordOpenFailure(Object? reason) {
    if (!_firstOpen || _session.grant != null || _openFailureCode != null)
      return;
    final code = switch (reason) {
      'STORAGE_BLOCKED' => ErrorCode.storageBlocked,
      'RESOURCE_LIMIT' => ErrorCode.resourceLimit,
      'TIMEOUT' => ErrorCode.timeout,
      'INCOMPATIBLE' => ErrorCode.incompatible,
      _ => ErrorCode.unauthorized,
    };
    _openFailureCode = code;
  }
}

/// The sole post-detach publication: a fixed initial-open failure, never a tool
/// result or arbitrary bytes. Only the admitted request can mint this permit.
final class OperationalOpenFailure extends _OpenFailure<OperationalPipePeer> {
  OperationalOpenFailure._(OperationalSessionRequest request, ErrorCode code)
    : super._(request, code);
  @override
  Map<String, Object?> get _error => LocalError(_code).toJson();
  @override
  Future<void> _write(List<int> bytes, Duration deadline) =>
      _request._session.peer.write(bytes, deadline: deadline);
}

final class TrustedOpenFailure extends _OpenFailure<TrustedPipePeer> {
  TrustedOpenFailure._(TrustedSessionRequest request, ErrorCode code)
    : super._(request, code);
  @override
  Map<String, Object?> get _error => TrustedLocalError(_code.wireName).toJson();
  @override
  Future<void> _write(List<int> bytes, Duration deadline) =>
      _request._session.peer.write(bytes, deadline: deadline);
}

sealed class _OpenFailure<P> {
  _OpenFailure._(this._request, this._code);
  final _GrantSessionRequest<P> _request;
  Map<String, Object?> get _error;
  Future<void> _write(List<int> bytes, Duration deadline);
  final ErrorCode _code;
  bool _used = false;

  Duration _remaining() {
    final request = _request, registry = request._registry;
    final session = request._session;
    if (request._completed ||
        !request._firstOpen ||
        request.method != 'mcp.open' ||
        !session.openAttempted ||
        session.grant != null ||
        !session.detached.isCompleted ||
        registry._stopping ||
        registry._sessions.containsKey(request.channel) ||
        registry._clock() >= session.expires) {
      throw StateError('UNAUTHORIZED');
    }
    final value = request._began + rpcDeadline - registry._clock();
    if (value <= Duration.zero) throw StateError('TIMEOUT');
    return value;
  }

  Future<void> write(
    String requestId, {
    Duration deadline = rpcDeadline,
  }) async {
    if (_used) throw StateError('UNAUTHORIZED');
    _used = true;
    requireUuid(requestId);
    final watch = Stopwatch()..start();
    Duration remaining() {
      final original = _remaining(), outer = deadline - watch.elapsed;
      if (outer <= Duration.zero) throw StateError('TIMEOUT');
      return outer < original ? outer : original;
    }

    final peer = _request._session.binding;
    try {
      final bytes = frameBytes(
        StrictCodec().encode({
          'v': 1,
          'id': requestId,
          'generation': _request._registry.generation,
          'error': _error,
        }),
      );
      final verificationBudget = remaining();
      await peer.revalidate().timeout(verificationBudget);
      // Synchronous guard after the await, immediately before issuing I/O.
      await _write(bytes, remaining());
      remaining();
    } on TimeoutException {
      throw StateError('TIMEOUT');
    } finally {
      watch.stop();
    }
  }
}
