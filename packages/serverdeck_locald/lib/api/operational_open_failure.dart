part of 'operational_auth.dart';

extension _FailedOpen on OperationalSessionRequest {
  void _recordOpenFailure(Object? reason) {
    if (!_firstOpen || _session.grant != null || _openFailure != null) return;
    final code = switch (reason) {
      'STORAGE_BLOCKED' => ErrorCode.storageBlocked,
      'RESOURCE_LIMIT' => ErrorCode.resourceLimit,
      'TIMEOUT' => ErrorCode.timeout,
      'INCOMPATIBLE' => ErrorCode.incompatible,
      _ => ErrorCode.unauthorized,
    };
    _openFailure = OperationalOpenFailure._(this, code);
  }
}

/// The sole post-detach publication: a fixed initial-open failure, never a tool
/// result or arbitrary bytes. Only the admitted request can mint this permit.
final class OperationalOpenFailure {
  OperationalOpenFailure._(this._request, this._code);
  final OperationalSessionRequest _request;
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

    final peer = _request._session.peer;
    try {
      final bytes = frameBytes(
        StrictCodec().encode({
          'v': 1,
          'id': requestId,
          'generation': _request._registry.generation,
          'error': LocalError(_code).toJson(),
        }),
      );
      final verificationBudget = remaining();
      await peer.revalidate().timeout(verificationBudget);
      // Synchronous guard after the await, immediately before issuing I/O.
      await peer.write(bytes, deadline: remaining());
      remaining();
    } on TimeoutException {
      throw StateError('TIMEOUT');
    } finally {
      watch.stop();
    }
  }
}
