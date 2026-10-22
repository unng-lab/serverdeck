part of 'operational_auth_client.dart';

enum OperationalRpcFailureOrigin { local, remote, transport }

final class OperationalRpcException implements Exception {
  const OperationalRpcException._(this.code, this.origin, [this.field]);
  final ErrorCode code;
  final OperationalRpcFailureOrigin origin;
  final String? field;
  bool get terminal => origin == OperationalRpcFailureOrigin.transport;
  RetryAdvice get retry => LocalError(code).retry;
  @override
  String toString() =>
      'OperationalRpcException(${code.wireName},${origin.name})';
}

final class _RpcPending {
  _RpcPending(this.until) {
    result.future.ignore();
  }
  final Duration until;
  final result = Completer<Map<String, Object?>>();
  Timer? timer;
}

/// Exactly one ordinary RPC owner of a real native-bootstrap session.
/// There are no raw transport callbacks or automatic connection/effect retries.
final class OperationalApiClient {
  factory OperationalApiClient(OperationalClientSession session) {
    if (session._closed ||
        session._ordinaryClaimed ||
        session._grantAttempted && session._grant == null) {
      throw const OperationalRpcException._(
        ErrorCode.serviceUnavailable,
        OperationalRpcFailureOrigin.local,
      );
    }
    session._ordinaryClaimed = true;
    return OperationalApiClient._(session);
  }
  OperationalApiClient._(this._session) {
    _done.future.ignore();
    _readLoop().ignore();
  }
  final OperationalClientSession _session;
  final _watch = Stopwatch()..start();
  final _pending = <String, _RpcPending>{};
  final _done = Completer<void>();
  Future<void> _writeTail = Future.value();
  bool _closing = false;
  bool get isClosed => _closing || _session._closed;
  int get pendingRequests => _pending.length;
  Future<void> get done => _done.future;

  Duration _remaining(Duration until) {
    if (isClosed) throw StateError('SERVICE_UNAVAILABLE');
    final remaining = until - _watch.elapsed;
    if (remaining <= Duration.zero) throw StateError('TIMEOUT');
    return remaining;
  }

  Future<Map<String, Object?>> call(
    String method,
    Map<String, Object?> params, {
    String? requestId,
  }) {
    final until = _watch.elapsed + rpcDeadline;
    if (isClosed) {
      return Future.error(
        const OperationalRpcException._(
          ErrorCode.serviceUnavailable,
          OperationalRpcFailureOrigin.transport,
        ),
      );
    }
    if (requestId != null) {
      try {
        requireUuid(requestId);
      } catch (_) {
        return Future.error(
          const OperationalRpcException._(
            ErrorCode.validation,
            OperationalRpcFailureOrigin.local,
          ),
        );
      }
      if (_pending.containsKey(requestId)) {
        return Future.error(
          const OperationalRpcException._(
            ErrorCode.idempotencyConflict,
            OperationalRpcFailureOrigin.local,
          ),
        );
      }
    }
    if (_pending.length >= maxPendingPerSession) {
      return Future.error(
        const OperationalRpcException._(
          ErrorCode.resourceLimit,
          OperationalRpcFailureOrigin.local,
        ),
      );
    }
    String id;
    if (requestId != null) {
      id = requestId;
    } else {
      do {
        id = _requestId();
      } while (_pending.containsKey(id));
    }
    late final List<int> bytes;
    try {
      if (method.isEmpty || method.runes.length > 256)
        throw const FormatException();
      bytes = frameBytes(
        encodeMcpMessage({
          'v': 1,
          'id': id,
          'sessionId': _session.id,
          'method': method,
          'params': params,
        }, maxBytes: maxRequestBytes),
        maxBytes: maxRequestBytes,
      );
      _remaining(until);
    } catch (error) {
      if (error is StateError && error.message == 'TIMEOUT') {
        _terminate(ErrorCode.timeout).ignore();
        return Future.error(
          const OperationalRpcException._(
            ErrorCode.timeout,
            OperationalRpcFailureOrigin.transport,
          ),
        );
      }
      return Future.error(
        const OperationalRpcException._(
          ErrorCode.validation,
          OperationalRpcFailureOrigin.local,
        ),
      );
    }
    final pending = _RpcPending(until);
    _pending[id] = pending;
    pending.timer = Timer(until - _watch.elapsed, () {
      if (identical(_pending[id], pending))
        _terminate(ErrorCode.timeout).ignore();
    });
    final write = _writeTail.then((_) async {
      if (isClosed || !identical(_pending[id], pending)) return;
      try {
        await _session.peer.write(bytes, deadline: _remaining(until));
        _remaining(until);
      } catch (error) {
        _terminate(_transportCode(error)).ignore();
      }
    });
    write.ignore();
    _writeTail = write;
    return pending.result.future;
  }

  static ErrorCode _transportCode(Object error) => error is StateError
      ? switch (error.message) {
          'TIMEOUT' => ErrorCode.timeout,
          'UNAUTHORIZED' => ErrorCode.unauthorized,
          _ => ErrorCode.serviceUnavailable,
        }
      : ErrorCode.serviceUnavailable;

  Future<void> _readLoop() async {
    try {
      while (!isClosed) {
        final frame = await _frame();
        final response = StrictCodec().decode(
          frame,
          maxBytes: maxResponseBytes,
        );
        validateResponseEnvelope(response);
        final id = response['id'] as String;
        final pending = _pending[id];
        if (response['generation'] != _session.hello.generation ||
            pending == null) {
          throw const FormatException('INVALID_FRAME');
        }
        final error = response['error'] as Map<String, Object?>?;
        final result = error == null
            ? _freeze(response['result']) as Map<String, Object?>
            : null;
        _remaining(pending.until);
        if (!identical(_pending[id], pending))
          throw const FormatException('INVALID_FRAME');
        _pending.remove(id);
        pending.timer?.cancel();
        if (error == null) {
          pending.result.complete(result!);
        } else {
          pending.result.completeError(
            OperationalRpcException._(
              ErrorCode.values.singleWhere(
                (code) => code.wireName == error['code'],
              ),
              OperationalRpcFailureOrigin.remote,
              error['field'] as String?,
            ),
          );
        }
      }
    } on FormatException {
      _terminate(ErrorCode.unauthorized).ignore();
    } catch (error) {
      _terminate(_transportCode(error)).ignore();
    }
  }

  static Object? _freeze(Object? value) => switch (value) {
    Map<String, Object?>() => Map<String, Object?>.unmodifiable(
      value.map((key, child) => MapEntry(key, _freeze(child))),
    ),
    List() => List<Object?>.unmodifiable(value.map(_freeze)),
    _ => value,
  };

  Future<Uint8List> _frame() async {
    final idleUntil = _watch.elapsed + sessionLease;
    Duration? partialUntil;
    Future<Uint8List> fill(int count) async {
      final result = Uint8List(count);
      var offset = 0;
      while (offset < count) {
        final until = partialUntil == null || idleUntil < partialUntil!
            ? idleUntil
            : partialUntil!;
        final bytes = await _session.peer.read(
          count: (count - offset).clamp(1, 65536),
          deadline: _remaining(until),
        );
        _remaining(until);
        if (bytes.isEmpty) throw StateError('SERVICE_UNAVAILABLE');
        if (bytes.length > count - offset)
          throw const FormatException('INVALID_FRAME');
        partialUntil ??= _watch.elapsed + rpcDeadline;
        result.setRange(offset, offset + bytes.length, bytes);
        offset += bytes.length;
      }
      return result;
    }

    final header = ByteData.sublistView(await fill(4));
    final size = header.getUint32(0, Endian.little);
    if (size == 0 || size > maxResponseBytes)
      throw const FormatException('INVALID_FRAME');
    return fill(size);
  }

  Future<void> close() => _terminate(ErrorCode.serviceUnavailable);
  Future<void> _terminate(ErrorCode code) {
    if (_closing) return done;
    _closing = true;
    _session._retire();
    final calls = _pending.values.toList();
    _pending.clear();
    for (final pending in calls) {
      pending.timer?.cancel();
      pending.result.completeError(
        OperationalRpcException._(code, OperationalRpcFailureOrigin.transport),
      );
    }
    _finishClose().ignore();
    return done;
  }

  Future<void> _finishClose() async {
    try {
      await _session.close();
      _done.complete();
    } catch (_) {
      _done.completeError(
        const OperationalRpcException._(
          ErrorCode.serviceUnavailable,
          OperationalRpcFailureOrigin.transport,
        ),
      );
    } finally {
      _watch.stop();
    }
  }
}
