part of 'in_process_gateway.dart';

/// One root-bound UI channel. send copies data synchronously before returning;
/// transport loss never proves worker/native cleanup. No role/owner DTO enters
/// this interface. The trusted mailbox routes its private VM binding out of band.
abstract interface class GatewayChannel {
  Stream<Object?> get messages;
  void send(Map<String, Object?> frame);
  void dispose();
}

/// Concrete Dart-port transport, constructed only from trusted spawn/attach
/// endpoints. No named OS endpoint, global port lookup or reconnect exists.
final class DartGatewayChannel implements GatewayChannel {
  DartGatewayChannel({
    required SendPort mailbox,
    required Capability binding,
    required ReceivePort replies,
  }) : _mailbox = mailbox,
       _binding = binding,
       _replies = replies {
    _subscription = replies.listen(_messages.add);
  }
  final SendPort _mailbox;
  final Capability _binding;
  final ReceivePort _replies;
  final _messages = StreamController<Object?>(sync: true);
  late final StreamSubscription<Object?> _subscription;
  bool _disposed = false;
  bool get isDisposed => _disposed;
  @override
  Stream<Object?> get messages => _messages.stream;
  @override
  void send(Map<String, Object?> frame) {
    if (_disposed) throw EngineCallFailure('SERVICE_UNAVAILABLE');
    _mailbox.send([_binding, frame]);
  }

  /// Called by root's authoritative onExit/onError, not an observation timeout.
  void workerLost() {
    if (_disposed) return;
    _messages.addError(EngineCallFailure('SERVICE_UNAVAILABLE'));
    dispose();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _replies.close();
    _subscription.cancel().ignore();
    _messages.close().ignore();
  }
}

typedef GatewaySchedule = void Function() Function(Duration, void Function());
void Function() _scheduleGateway(Duration duration, void Function() action) {
  final timer = Timer(duration, action);
  return timer.cancel;
}

final class _ProxyWork {
  _ProxyWork(this.id, this.method);
  final String id, method;
  late final int expiresAt;
  final reply = Completer<Map<String, Object?>>();
  void Function()? cancelTimer;
  bool posted = false, received = false;
}

/// UI-side interest only. Tokens stay charged after logical timeout until the
/// exact worker's settlement frame; loss permanently retires this proxy.
final class WorkerGatewayProxy implements EngineGateway {
  WorkerGatewayProxy({
    required this.generation,
    required GatewayChannel channel,
    int Function()? nowMicros,
    GatewaySchedule? schedule,
  }) : _channel = channel,
       _now = nowMicros ?? (() => Timeline.now),
       _schedule = schedule ?? _scheduleGateway {
    requireUuid(generation);
    _subscription = channel.messages.listen(
      _receive,
      onError: (Object _, StackTrace __) => _fail(),
      onDone: () {
        if (!_physicallyClosed) _fail();
      },
    );
    if (_failed) _subscription?.cancel().ignore();
  }
  @override
  final String generation;
  final GatewayChannel _channel;
  final int Function() _now;
  final GatewaySchedule _schedule;
  final _pending = <int, _ProxyWork>{};
  final _retired = Completer<void>();
  @override
  Future<void> get retired => _retired.future;
  StreamSubscription<Object?>? _subscription;
  int _next = 0;
  bool _closed = false, _failed = false, _physicallyClosed = false;
  Completer<void>? _closing;
  @override
  bool get isClosed => _closed;
  int get pendingRequests => _pending.length;

  @override
  Future<Map<String, Object?>> call(
    String method,
    Map<String, Object?> params, {
    required String requestId,
  }) {
    if (_closed) return Future.error(EngineCallFailure('SERVICE_UNAVAILABLE'));
    if (_pending.length >= 16)
      return Future.error(EngineCallFailure('RESOURCE_LIMIT'));
    if (_next == 0x7fffffffffffffff) {
      _fail();
      return Future.error(EngineCallFailure('SERVICE_UNAVAILABLE'));
    }
    final sequence = ++_next, work = _ProxyWork(requestId, method);
    work.reply.future.ignore();
    _pending[sequence] = work;
    List<int>? bytes;
    try {
      final deadline = _now() + rpcDeadline.inMicroseconds;
      work.expiresAt = deadline;
      work.cancelTimer = _schedule(rpcDeadline, () {
        if (!work.reply.isCompleted)
          work.reply.completeError(EngineCallFailure('TIMEOUT'));
      });
      final captured = _captureGatewayInput(method, params, requestId);
      bytes = encodeMcpMessage(captured, maxBytes: maxRequestBytes);
      if (_closed) throw EngineCallFailure('SERVICE_UNAVAILABLE');
      if (_now() >= deadline) throw EngineCallFailure('TIMEOUT');
      work.posted = true;
      _channel.send({
        'kind': 'call',
        'generation': generation,
        'sequence': sequence,
        'id': requestId,
        'method': method,
        'expiresAt': deadline,
        'body': bytes,
      });
    } catch (error) {
      if (work.posted)
        _fail(); // Delivery is uncertain; no replay/free token.
      else {
        _pending.remove(sequence);
        work.cancelTimer?.call();
        if (!work.reply.isCompleted)
          work.reply.completeError(InProcessGateway._safe(error));
      }
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
    }
    return work.reply.future;
  }

  void _receive(Object? input) {
    if (_failed || _physicallyClosed) {
      discardWorkerFrame(input);
      return;
    }
    try {
      if (input is! Map<String, Object?> || input['generation'] != generation) {
        throw const FormatException('INVALID_WORKER_FRAME');
      }
      if (input['kind'] == 'closed') {
        requireFields(input, {'kind', 'generation', 'ok'});
        if (_closing == null || input['ok'] != true)
          throw const FormatException('INVALID_WORKER_CLOSE');
        _physicallyClosed = true;
        _closed = true;
        if (!_retired.isCompleted) _retired.complete();
        for (final work in _pending.values) {
          work.cancelTimer?.call();
          if (!work.reply.isCompleted)
            work.reply.completeError(EngineCallFailure('SERVICE_UNAVAILABLE'));
        }
        _pending.clear();
        _subscription?.cancel().ignore();
        try {
          _channel.dispose();
          _closing!.complete();
        } catch (_) {
          _failed = true;
          _closing!.completeError(EngineCallFailure('SERVICE_UNAVAILABLE'));
        }
        return;
      }
      final sequence = input['sequence'];
      if (sequence is! int || sequence < 1)
        throw const FormatException('INVALID_SEQUENCE');
      final work = _pending[sequence];
      if (work == null || !work.posted || input['id'] != work.id)
        throw const FormatException('INVALID_CORRELATION');
      if (input['kind'] == 'settled') {
        requireFields(input, {'kind', 'generation', 'sequence', 'id', 'ok'});
        if (!work.received || input['ok'] != true)
          throw const FormatException('UNCONFIRMED_SETTLEMENT');
        work.cancelTimer?.call();
        _pending.remove(sequence);
        return;
      }
      if (work.received) throw const FormatException('DUPLICATE_REPLY');
      if (input['kind'] == 'result') {
        requireFields(input, {'kind', 'generation', 'sequence', 'id', 'body'});
        final body = input['body'];
        if (body is! List<int>) throw const FormatException('INVALID_BODY');
        late Map<String, Object?> value;
        try {
          value = StrictCodec().decode(body, maxBytes: maxResponseBytes);
        } finally {
          body.fillRange(0, body.length, 0);
        }
        requireFields(value, {'v', 'id', 'generation', 'result'});
        if (value['v'] is! int ||
            value['v'] != 1 ||
            value['id'] != work.id ||
            value['generation'] != generation ||
            value['result'] is! Map<String, Object?>) {
          throw const FormatException('INVALID_RESULT');
        }
        work.received = true;
        if (!work.reply.isCompleted) {
          if (_now() >= work.expiresAt)
            work.reply.completeError(EngineCallFailure('TIMEOUT'));
          else
            work.reply.complete(
              _freezeGateway(value['result']) as Map<String, Object?>,
            );
        }
        if (work.method == 'session.close') close().ignore();
      } else if (input['kind'] == 'error') {
        requireFields(input, {
          'kind',
          'generation',
          'sequence',
          'id',
          'error',
          'retired',
        });
        if (input['error'] is! Map<String, Object?> ||
            input['retired'] is! bool)
          throw const FormatException('INVALID_ERROR');
        final error = TrustedLocalError.fromJson(
          input['error'] as Map<String, Object?>,
        );
        work.received = true;
        if (!work.reply.isCompleted)
          work.reply.completeError(
            _now() >= work.expiresAt
                ? EngineCallFailure('TIMEOUT')
                : EngineCallFailure(error.code, field: error.field),
          );
        if (input['retired'] == true) close().ignore();
      } else {
        throw const FormatException('INVALID_KIND');
      }
    } catch (_) {
      _fail();
    } finally {
      discardWorkerFrame(input);
    }
  }

  void _fail() {
    if (!_retired.isCompleted) _retired.complete();
    if (_failed || _physicallyClosed) return;
    _failed = true;
    _closed = true;
    for (final work in _pending.values) {
      work.cancelTimer?.call();
      if (!work.reply.isCompleted)
        work.reply.completeError(EngineCallFailure('SERVICE_UNAVAILABLE'));
    }
    final closing = _closing ??= Completer<void>();
    closing.future.ignore();
    if (!closing.isCompleted)
      closing.completeError(EngineCallFailure('SERVICE_UNAVAILABLE'));
    // Tokens remain unconfirmed. A root cannot infer store/lease release here.
    _subscription?.cancel().ignore();
    // Withdraw this binding even if its reply path is corrupt/lost. Delivery is
    // best effort only; it is never converted into a successful close proof.
    try {
      _channel.send({'kind': 'close', 'generation': generation});
    } catch (_) {
      /* no retry after uncertain delivery */
    }
    try {
      _channel.dispose();
    } catch (_) {
      /* permanent loss */
    }
  }

  @override
  Future<void> close() {
    if (_closing != null) return _closing!.future;
    final done = _closing = Completer<void>();
    done.future.ignore();
    _closed = true;
    if (!_retired.isCompleted) _retired.complete();
    for (final work in _pending.values) {
      if (!work.reply.isCompleted)
        work.reply.completeError(EngineCallFailure('SERVICE_UNAVAILABLE'));
    }
    try {
      _channel.send({'kind': 'close', 'generation': generation});
    } catch (_) {
      _fail();
    }
    return done.future;
  }
}

Object? _freezeGateway(Object? value) => switch (value) {
  Map<String, Object?>() => Map<String, Object?>.unmodifiable(
    value.map((k, v) => MapEntry(k, _freezeGateway(v))),
  ),
  List() => List<Object?>.unmodifiable(value.map(_freezeGateway)),
  _ => value,
};

/// Wipes an owned frame rejected by the trusted root before binding dispatch.
void discardWorkerFrame(Object? input) {
  try {
    if (input is Map<String, Object?> && input['body'] is List<int>) {
      final body = input['body'] as List<int>;
      body.fillRange(0, body.length, 0);
    }
  } catch (_) {
    /* A malformed immutable payload cannot authorize anything. */
  }
}

/// Worker-side adapter after the trusted mailbox has verified its VM binding.
/// It cannot attach a window, select a role, create a Host or open storage.
final class GatewayWorkerBinding {
  GatewayWorkerBinding({
    required InProcessGateway gateway,
    required void Function(Map<String, Object?>) send,
    required Future<void> Function() detach,
  }) : _gateway = gateway,
       _send = send,
       _detach = detach;
  final InProcessGateway _gateway;
  final void Function(Map<String, Object?>) _send;
  final Future<void> Function() _detach;
  final _calls = <Future<void>>{};
  Future<void>? _closing;
  int _lastSequence = 0;
  bool _closed = false, _failed = false;
  String get generation => _gateway.generation;

  void handle(Object? input) {
    if (_closed) {
      discardWorkerFrame(input);
      return;
    }
    try {
      if (input is! Map<String, Object?> || input['generation'] != generation)
        throw const FormatException('INVALID_GENERATION');
      if (input['kind'] == 'close') {
        requireFields(input, {'kind', 'generation'});
        close().ignore();
        return;
      }
      requireFields(input, {
        'kind',
        'generation',
        'sequence',
        'id',
        'method',
        'expiresAt',
        'body',
      });
      final sequence = input['sequence'],
          id = input['id'],
          method = input['method'];
      final expiresAt = input['expiresAt'], body = input['body'];
      if (input['kind'] != 'call' ||
          sequence is! int ||
          sequence <= _lastSequence ||
          sequence > 0x7fffffffffffffff ||
          id is! String ||
          method is! String ||
          expiresAt is! int ||
          expiresAt < 0 ||
          expiresAt > 0x7fffffffffffffff ||
          body is! List<int>) {
        throw const FormatException('INVALID_CALL');
      }
      _lastSequence = sequence;
      late Map<String, Object?> params;
      try {
        params = StrictCodec().decode(body, maxBytes: maxRequestBytes);
      } finally {
        body.fillRange(0, body.length, 0);
      }
      if (_calls.length >= 16) {
        _postError(sequence, id, EngineCallFailure('RESOURCE_LIMIT'));
        _send({
          'kind': 'settled',
          'generation': generation,
          'sequence': sequence,
          'id': id,
          'ok': true,
        });
        return;
      }
      final physical = Completer<void>();
      physical.future.ignore();
      _calls.add(physical.future);
      physical.future.then<void>(
        (_) => _calls.remove(physical.future),
        onError: (Object _, StackTrace __) {
          _failed = true;
          _calls.remove(physical.future);
        },
      );
      final invocation = _gateway.beginCall(
        method,
        params,
        requestId: id,
        expiresAt: Duration(microseconds: expiresAt),
      );
      _serve(
        invocation,
        sequence,
        id,
        method,
        Duration(microseconds: expiresAt),
      ).then<void>(
        physical.complete,
        onError: (Object _, StackTrace __) {
          _failed = true;
          physical.completeError(EngineCallFailure('SERVICE_UNAVAILABLE'));
          close().ignore();
        },
      );
    } catch (_) {
      _failed = true;
      close().ignore();
    } finally {
      discardWorkerFrame(input);
    }
  }

  void _postError(int sequence, String id, EngineCallFailure error) =>
      _send(_errorFrame(sequence, id, error));
  Map<String, Object?> _errorFrame(
    int sequence,
    String id,
    EngineCallFailure error,
  ) => {
    'kind': 'error',
    'generation': generation,
    'sequence': sequence,
    'id': id,
    'error': error.toJson(),
    'retired': _closed || _gateway.isClosed,
  };
  Future<void> _serve(
    EngineInvocation invocation,
    int sequence,
    String id,
    String method,
    Duration expiresAt,
  ) async {
    var delivered = true;
    List<int>? bytes;
    late Map<String, Object?> frame;
    try {
      final result = await invocation.result;
      bytes = encodeMcpMessage({
        'v': 1,
        'id': id,
        'generation': generation,
        'result': result,
      }, maxBytes: maxResponseBytes);
      if (_gateway._owner.clockElapsed >= expiresAt)
        throw EngineCallFailure('TIMEOUT');
      if (method != 'session.close') {
        if (_closed || _gateway.isClosed)
          throw EngineCallFailure('SERVICE_UNAVAILABLE');
        if (method != 'readiness.get' && method != 'session.ping')
          _gateway._domainReady();
      }
      frame = {
        'kind': 'result',
        'generation': generation,
        'sequence': sequence,
        'id': id,
        'body': bytes,
      };
    } catch (error) {
      frame = _errorFrame(sequence, id, InProcessGateway._safe(error));
    }
    // One send attempt only. A throw after posting cannot become a second reply.
    try {
      _send(frame);
    } catch (_) {
      delivered = false;
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
    }
    var settled = true;
    try {
      await invocation.settled;
    } catch (_) {
      settled = false;
    }
    if (delivered) {
      try {
        _send({
          'kind': 'settled',
          'generation': generation,
          'sequence': sequence,
          'id': id,
          'ok': settled,
        });
      } catch (_) {
        delivered = false;
      }
    }
    if (!delivered || !settled) throw EngineCallFailure('SERVICE_UNAVAILABLE');
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    final done = Completer<void>();
    _closing = done.future;
    done.future.ignore();
    _closed = true;
    // Start detach before waiting responses; it closes session intake now.
    final detach = Future<void>.sync(_detach);
    () async {
      var failed = _failed;
      try {
        await Future.wait<void>([detach, ..._calls.toList()]);
      } catch (_) {
        failed = true;
      }
      failed = failed || _failed;
      try {
        _send({'kind': 'closed', 'generation': generation, 'ok': !failed});
      } catch (_) {
        failed = true;
      }
      if (failed) throw EngineCallFailure('SERVICE_UNAVAILABLE');
    }().then<void>(
      done.complete,
      onError: (Object _, StackTrace __) =>
          done.completeError(EngineCallFailure('SERVICE_UNAVAILABLE')),
    );
    return done.future;
  }
}
