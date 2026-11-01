part of 'client.dart';

final class _Pending {
  _Pending(this.until, this.method) {
    result.future.ignore();
    writeSettled.future.ignore();
  }
  final Duration until;
  final String method;
  final result = Completer<Map<String, Object?>>();
  final writeSettled = Completer<void>();
  Timer? timer;
  bool issued = false;
}

Object? _freeze(Object? value) => switch (value) {
  Map<String, Object?>() => Map<String, Object?>.unmodifiable(
    value.map((key, child) => MapEntry(key, _freeze(child))),
  ),
  List() => List<Object?>.unmodifiable(value.map(_freeze)),
  _ => value,
};

/// Capture a response under its ORIGINAL deadline, including recursive CPU
/// work. The caller still owns the pending slot and checks current connection
/// ownership before delivery; this helper never publishes or grants authority.
Map<String, Object?> captureMcpResult(
  Map<String, Object?> result, {
  required EngineClock clock,
  required Duration deadline,
}) {
  final captured = _freeze(result) as Map<String, Object?>;
  if (clock.elapsed >= deadline) throw StateError('TIMEOUT');
  return captured;
}

extension McpClientRpc on McpClient {
  /// One reader/writer incarnation, no raw role, owner methods, reconnect or
  /// effect retries. Pre-grant permits liveness/readiness only.
  Future<Map<String, Object?>> call(
    String method,
    Map<String, Object?> params,
  ) {
    if (_closed || !_authenticated)
      return Future.error(
        const McpClientException(
          'SERVICE_UNAVAILABLE',
          McpClientFailureOrigin.transport,
        ),
      );
    if (_grantBusy)
      return Future.error(
        const McpClientException(
          'SERVICE_UNAVAILABLE',
          McpClientFailureOrigin.local,
        ),
      );
    if (!const {
          'readiness.get',
          'session.ping',
          'session.close',
          'mcp.close',
          'mcp.invoke',
        }.contains(method) ||
        method == 'mcp.invoke' && _grant == null) {
      return Future.error(
        const McpClientException('FORBIDDEN', McpClientFailureOrigin.local),
      );
    }
    return _call(method, params);
  }
}

extension _Rpc on McpClient {
  Future<Map<String, Object?>> _call(
    String method,
    Map<String, Object?> params, {
    Duration? until,
  }) {
    until ??= _clock.elapsed + rpcDeadline;
    if (_closed || !_authenticated)
      return Future.error(
        const McpClientException(
          'SERVICE_UNAVAILABLE',
          McpClientFailureOrigin.transport,
        ),
      );
    try {
      _check();
    } catch (e) {
      _terminate(_safe(e)).ignore();
      return Future.error(
        McpClientException(_safe(e), McpClientFailureOrigin.transport),
      );
    }
    if (_pending.length >= maxPendingPerSession)
      return Future.error(
        const McpClientException(
          'RESOURCE_LIMIT',
          McpClientFailureOrigin.local,
        ),
      );
    String id;
    do {
      id = _id();
    } while (_pending.containsKey(id));
    final pending = _Pending(until, method);
    _pending[id] =
        pending; // Charge before encoding/caller collection callouts.
    List<int>? bytes;
    try {
      if (method == 'mcp.invoke') {
        McpInvokeInput.fromJson(params);
      } else if (method != 'mcp.open') {
        requireFields(params, {});
      }
      bytes = Uint8List.fromList(
        frameBytes(
          encodeMcpMessage({
            'v': 1,
            'id': id,
            'sessionId': _session!,
            'method': method,
            'params': params,
          }, maxBytes: maxRequestBytes),
          maxBytes: maxRequestBytes,
        ),
      );
      final remaining = _remaining(until);
      pending.timer = Timer(remaining, () {
        if (identical(_pending[id], pending)) _terminate('TIMEOUT').ignore();
      });
    } catch (e) {
      bytes?.fillRange(0, bytes.length, 0);
      if (identical(_pending[id], pending)) {
        _pending.remove(id);
        pending.result.completeError(
          McpClientException(
            e is StateError && e.message == 'TIMEOUT'
                ? 'TIMEOUT'
                : 'VALIDATION',
            McpClientFailureOrigin.local,
          ),
        );
      }
      return pending.result.future;
    }
    final captured = bytes;
    final previous = _writeTail;
    final write = _owned(() async {
      try {
        await previous;
        if (_closed || !identical(_pending[id], pending)) return;
        await _proof(pending.until);
        pending.issued = true;
        await _owned(
          () => _peer.write(captured, deadline: _remaining(pending.until)),
        );
        _remaining(pending.until);
      } catch (e) {
        _terminate(_safe(e)).ignore();
      } finally {
        captured.fillRange(0, captured.length, 0);
        pending.writeSettled.complete();
      }
    });
    _writeTail = write;
    write.ignore();
    return pending.result.future;
  }

  Future<void> _readLoop() async {
    try {
      while (!_closed) {
        final bytes = await _frame();
        late final Map<String, Object?> response;
        try {
          response = StrictCodec().decode(bytes, maxBytes: maxResponseBytes);
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
        validateTrustedResponseEnvelope(response);
        final id = response['id'] as String;
        final pending = _pending[id];
        if (response['generation'] != generation ||
            pending == null ||
            !pending.issued)
          throw StateError('UNAUTHORIZED');
        await pending.writeSettled.future.timeout(_remaining(pending.until));
        await _proof(pending.until);
        final error = response['error'] as Map<String, Object?>?;
        final result = response['result'] as Map<String, Object?>?;
        if (error == null) {
          switch (pending.method) {
            case 'readiness.get':
              final value = TrustedReadiness.fromJson(result);
              if (value.generation != generation ||
                  value.state == ReadinessState.ready &&
                      value.workspaceId != workspaceId)
                throw StateError('INCOMPATIBLE');
            case 'session.ping':
              requireFields(result!, {'leaseSeconds'});
              if (result['leaseSeconds'] is! int ||
                  result['leaseSeconds'] != 60)
                throw StateError('UNAUTHORIZED');
            case 'session.close' || 'mcp.close':
              requireFields(result!, {'closed'});
              if (result['closed'] != true) throw StateError('UNAUTHORIZED');
            case 'mcp.invoke':
              McpInvokeReply.fromJson(result);
          }
        }
        final captured = error == null
            ? captureMcpResult(result!, clock: _clock, deadline: pending.until)
            : null;
        _remaining(pending.until);
        if (!identical(_pending[id], pending)) throw StateError('UNAUTHORIZED');
        _pending.remove(id);
        pending.timer?.cancel();
        if (error == null) {
          pending.result.complete(captured!);
        } else {
          pending.result.completeError(
            McpClientException(
              error['code'] as String,
              McpClientFailureOrigin.remote,
            ),
          );
        }
      }
    } on FormatException {
      _terminate('UNAUTHORIZED').ignore();
    } catch (e) {
      _terminate(_safe(e)).ignore();
    }
  }

  Future<Uint8List> _frame() async {
    final idleUntil = _clock.elapsed + sessionLease;
    Duration? partialUntil;
    Duration remaining() {
      final until = partialUntil == null || idleUntil < partialUntil!
          ? idleUntil
          : partialUntil!;
      return _remaining(until);
    }

    Future<Uint8List> fill(int count) async {
      final output = Uint8List(count);
      var offset = 0;
      try {
        while (offset < count) {
          final bytes = await _owned(
            () => _peer.read(
              count: (count - offset).clamp(1, 65536),
              deadline: remaining(),
            ),
          );
          try {
            remaining();
            if (bytes.isEmpty || bytes.length > count - offset)
              throw StateError('SERVICE_UNAVAILABLE');
            partialUntil ??= _clock.elapsed + rpcDeadline;
            output.setRange(offset, offset + bytes.length, bytes);
            offset += bytes.length;
          } finally {
            bytes.fillRange(0, bytes.length, 0);
          }
        }
        return output;
      } catch (_) {
        output.fillRange(0, output.length, 0);
        rethrow;
      }
    }

    final header = await fill(4);
    final size = ByteData.sublistView(header).getUint32(0, Endian.little);
    header.fillRange(0, header.length, 0);
    if (size < 1 || size > maxResponseBytes) throw StateError('UNAUTHORIZED');
    return fill(size);
  }
}
