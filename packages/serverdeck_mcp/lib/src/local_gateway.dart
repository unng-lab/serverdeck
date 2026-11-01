import 'dart:async';
import 'dart:convert';

import 'package:serverdeck_protocol/errors.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_engine/mcp/client.dart';
import 'package:serverdeck_engine/platform/ports.dart';

import 'server.dart';

ErrorCode _publicCode(ErrorCode code) =>
    code == ErrorCode.unauthorized ? ErrorCode.forbidden : code;

ErrorCode _domainCode(String code) => _publicCode(
  ErrorCode.values.where((value) => value.wireName == code).firstOrNull ??
      ErrorCode.internal,
);

final class _RpcFailure implements Exception {
  _RpcFailure(
    this.code, {
    this.terminal = false,
    this.origin,
    this.domainCode,
    RetryAdvice? retry,
  }) : retry = retry ?? LocalError(code).retry;
  final ErrorCode code;
  final RetryAdvice retry;
  final bool terminal;
  final McpClientFailureOrigin? origin;
  final String? domainCode;
  Map<String, Object?> result() => McpToolResult.failure(
    domainCode ?? _publicCode(code).wireName,
    retry: switch (retry) {
      RetryAdvice.none => 'none',
      RetryAdvice.reload => 'reload',
      RetryAdvice.reconnect => 'reconnect',
      RetryAdvice.retrySameRequest => 'retry-same-request',
      RetryAdvice.manualRecovery => 'manual-recovery',
    },
  ).toJson();
}

final class _RpcWork {
  final settled = Completer<void>();
}

/// Standard MCP adapter over one claimed, protected native MCP session.
/// No raw transport, authority, credential or method-provider injection.
final class LocalMcpGateway implements McpGateway {
  LocalMcpGateway.attach(
    McpClient client,
    PublicationGate gate, {
    EngineClock? clock,
  }) : _client = client,
       _gate = gate,
       _clock = clock ?? SystemEngineClock(),
       _expires = client.grant == null
           ? null
           : DateTime.parse(client.grant!.expiresAt) {
    if (client.isClosed ||
        gate.isClosed ||
        gate.generation != client.generation) {
      throw const McpGatewayFailure(ErrorCode.serviceUnavailable);
    }
    client.retired.then<void>((_) => close().ignore()).ignore();
    _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
      if (isClosed || _heartbeatBusy || _client.pendingRequests >= 16) return;
      _heartbeatBusy = true;
      _ping(_now + const Duration(seconds: 5))
          .catchError((Object error) {
            if (error is! _RpcFailure ||
                error.code != ErrorCode.resourceLimit ||
                error.origin != McpClientFailureOrigin.local ||
                error.terminal)
              close().ignore();
          })
          .whenComplete(() {
            _heartbeatBusy = false;
          })
          .ignore();
    });
  }

  final McpClient _client;
  final PublicationGate _gate;
  final DateTime? _expires;
  final EngineClock _clock;
  final _operations = <_Operation>{};
  final _calls = <_RpcWork>{};
  Timer? _heartbeat;
  bool _heartbeatBusy = false, _closed = false;
  Future<void>? _closeFuture;
  final _retired = Completer<void>();
  @override
  bool get isClosed => _closed || _client.isClosed;
  @override
  Future<void> get retired => _retired.future;

  @override
  McpInvocation protect(Map<String, Object?> value) => _fixedInvocation(value);
  McpInvocation _fixedInvocation(Map<String, Object?> value) {
    if (isClosed) throw const McpGatewayFailure(ErrorCode.serviceUnavailable);
    // At most16 tool interests plus the one active builtin writer guard.
    if (_operations.length >= 17)
      throw const McpGatewayFailure(ErrorCode.resourceLimit);
    final operation = _Operation(this, 'fixed', const {}, value);
    return _launch(operation);
  }

  McpInvocation _launch(_Operation operation) {
    _operations.add(operation);
    operation.run().ignore();
    return McpInvocation(
      operation.result.future,
      operation.cancelInterest,
      beforePublish: operation.beforePublish,
      validatePublication: operation.validatePublication,
      afterPublish: operation.afterPublish,
    );
  }

  Duration get _now => _clock.elapsed;

  @override
  McpInvocation start(String method, Map<String, Object?> params) {
    if (isClosed) throw const McpGatewayFailure(ErrorCode.serviceUnavailable);
    if (method != 'tools/list' && method != 'tools/call')
      throw const McpProtocolException(-32601);
    late final Map<String, Object?> snapshot;
    try {
      snapshot = jsonDecode(
        utf8.decode(encodeMcpMessage(params, maxBytes: mcpMaxRequestBytes)),
      ) as Map<String, Object?>;
    } catch (_) {
      throw const McpProtocolException(-32602);
    }
    final fields = method == 'tools/list'
        ? const {'_meta'}
        : const {'name', 'arguments', '_meta'};
    if (snapshot.keys.any((key) => !fields.contains(key)) ||
        (snapshot.containsKey('_meta') &&
            snapshot['_meta'] is! Map<String, Object?>) ||
        (method == 'tools/call' &&
            (snapshot['name'] is! String ||
                (snapshot['name'] as String).runes.isEmpty ||
                (snapshot['name'] as String).runes.length > 256 ||
                snapshot.containsKey('arguments') &&
                    snapshot['arguments'] is! Map<String, Object?>)))
      throw const McpProtocolException(-32602);
    if (_operations.length >= 16) {
      if (method == 'tools/list')
        throw const McpGatewayFailure(ErrorCode.resourceLimit);
      return _fixedInvocation(McpToolResult.failure('RESOURCE_LIMIT').toJson());
    }
    if (_expires == null) {
      return _fixedInvocation(
        method == 'tools/list'
            ? {'tools': <Object?>[]}
            : McpToolResult.failure('FORBIDDEN').toJson(),
      );
    }
    final operation = _Operation(
      this,
      method,
      method == 'tools/list'
          ? {'catalog': <String, Object?>{}}
          : {
              'request': {
                'name': snapshot['name'],
                'arguments': snapshot['arguments'] ?? <String, Object?>{},
              },
            },
    );
    return _launch(operation);
  }

  Duration _remaining(Duration until) {
    final left = until - _now;
    if (left <= Duration.zero) throw _RpcFailure(ErrorCode.timeout);
    return left;
  }

  Future<Map<String, Object?>> _rpc(
    String method,
    Map<String, Object?> params,
    Duration until, {
    _Operation? operation,
    bool cancel = false,
  }) async {
    void live() {
      if (_closed || _client.isClosed)
        throw _RpcFailure(ErrorCode.serviceUnavailable, terminal: true);
      if (!cancel && operation?._retired == true)
        throw const McpGatewayFailure(ErrorCode.forbidden);
    }

    live();
    final stage = _now + const Duration(seconds: 5);
    until = until < stage ? until : stage;
    while (_client.pendingRequests >= 16 || _calls.length >= 16) {
      live();
      if (_calls.isEmpty)
        throw _RpcFailure(
          ErrorCode.resourceLimit,
          origin: McpClientFailureOrigin.local,
        );
      try {
        await Future.any<void>([
          for (final work in _calls) work.settled.future,
          if (!cancel && operation != null) operation._wake.future,
        ]).timeout(_remaining(until));
      } on TimeoutException {
        throw _RpcFailure(ErrorCode.timeout);
      }
    }
    live();
    _remaining(until);
    final work = _RpcWork();
    _calls.add(work);
    operation?._rpcCount++;
    final actual = Future<Map<String, Object?>>.sync(
      () => _client.call(method, params),
    );
    actual.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      _calls.remove(work);
      if (operation != null) {
        operation._rpcCount--;
        operation.maybeFinished();
      }
      work.settled.complete();
    }).ignore();
    try {
      // SDK admission snapshots/encodes synchronously. Recheck the original
      // outer stage budget before its queued writer can issue native I/O.
      return await actual.timeout(_remaining(until));
    } on _RpcFailure {
      close().ignore();
      throw _RpcFailure(ErrorCode.timeout, terminal: true);
    } on McpClientException catch (error) {
      if (error.terminal) close().ignore();
      throw _RpcFailure(
        _domainCode(error.code),
        domainCode:
            mcpDomainCodes.contains(error.code) && error.code != 'UNAUTHORIZED'
            ? error.code
            : null,
        terminal: error.terminal,
        origin: error.origin,
        retry: error.retry,
      );
    } on TimeoutException {
      close().ignore();
      throw _RpcFailure(ErrorCode.timeout, terminal: true);
    }
  }

  Future<void> _ping(Duration until, {_Operation? operation}) async {
    final reply = await _rpc('session.ping', {}, until, operation: operation);
    if (reply.length != 1 ||
        reply['leaseSeconds'] is! int ||
        reply['leaseSeconds'] != 60) {
      close().ignore();
      throw const McpGatewayFailure(ErrorCode.internal);
    }
  }

  @override
  Future<void> close() {
    if (_closeFuture != null) return _closeFuture!;
    final done = Completer<void>();
    _closeFuture = done.future;
    done.future.ignore();
    _closed = true;
    _retired.complete();
    _heartbeat?.cancel();
    for (final operation in _operations.toList()) {
      operation.retire();
    }
    // Start native cleanup before awaiting publication interests. A publication
    // lease is released only by afterPublish after actual guard/flush settlement.
    final native = _client.close();
    final gate = _gate.close();
    Future.wait<void>([
      native,
      gate,
      for (final operation in _operations.toList()) operation.done.future,
      for (final work in _calls.toList()) work.settled.future,
    ]).then<void>(
      (_) {
        done.complete();
      },
      onError: (Object _) {
        done.completeError(
          const McpGatewayFailure(ErrorCode.serviceUnavailable),
        );
      },
    );
    return done.future;
  }
}

final class _Operation {
  _Operation(this.gateway, this.method, this.input, [this.fixed])
    : until = gateway._now + const Duration(seconds: 35) {
    result.future.ignore();
    done.future.ignore();
  }
  final LocalMcpGateway gateway;
  final String method;
  final Map<String, Object?> input;
  final Map<String, Object?>? fixed;
  final Duration until;
  final result = Completer<Map<String, Object?>>();
  final done = Completer<void>(), _ack = Completer<void>();
  final _wake = Completer<void>();
  Timer? _poll;
  String? _handle;
  int _rpcCount = 0;
  bool _produced = false,
      _retired = false,
      _fixed = false,
      _needsPublication = false,
      _guardStarted = false,
      _published = false,
      _cancelDone = false;
  PublicationLease? _lease;
  Future<void>? _cancelFuture, _guardFuture, _releaseFuture;

  McpInvokeReply parse(Map<String, Object?> value) {
    try {
      return McpInvokeReply.fromJson(value);
    } catch (_) {
      return invalid();
    }
  }

  Never invalid() {
    gateway.close().ignore();
    throw const McpGatewayFailure(ErrorCode.internal);
  }

  void live() {
    if (gateway._closed || gateway._client.isClosed)
      throw _RpcFailure(ErrorCode.serviceUnavailable, terminal: true);
    if (_retired) throw const McpGatewayFailure(ErrorCode.forbidden);
    gateway._remaining(until);
  }

  Future<void> run() async {
    try {
      if (fixed != null) {
        _ack.complete();
        live();
        _needsPublication = true;
        result.complete(fixed!);
        return;
      }
      late final McpInvokeReply initial;
      try {
        initial = parse(
          await gateway._rpc('mcp.invoke', input, until, operation: this),
        );
        if (initial.kind == McpInvokeReplyKind.pending)
          _handle = initial.toJson()['operationId'] as String;
      } finally {
        _ack.complete();
      }
      live();
      Map<String, Object?> output;
      if (method == 'tools/list') {
        if (initial.kind != McpInvokeReplyKind.catalog) invalid();
        output = initial.toJson();
      } else {
        var reply = initial;
        if (reply.kind == McpInvokeReplyKind.invalidParams)
          throw const McpProtocolException(-32602);
        while (reply.kind == McpInvokeReplyKind.pending) {
          if (reply.toJson()['operationId'] != _handle) invalid();
          final delay = Completer<void>();
          final remaining = gateway._remaining(until);
          _poll = Timer(
            remaining < const Duration(milliseconds: 250)
                ? remaining
                : const Duration(milliseconds: 250),
            delay.complete,
          );
          await Future.any<void>([delay.future, _wake.future]);
          _poll?.cancel();
          _poll = null;
          live();
          reply = parse(
            await gateway._rpc(
              'mcp.invoke',
              {
                'poll': {'operationId': _handle},
              },
              until,
              operation: this,
            ),
          );
        }
        if (reply.kind != McpInvokeReplyKind.done) invalid();
        output = McpToolResult.fromJson(reply.toJson()['result']).toJson();
      }
      live();
      _needsPublication = true;
      result.complete(output);
    } on _RpcFailure catch (error) {
      _fixed = true;
      if (method == 'tools/list')
        result.completeError(McpGatewayFailure(_publicCode(error.code)));
      else {
        _needsPublication = true;
        result.complete(error.result());
      }
      if (_handle != null) cancelInterest().ignore();
    } on McpProtocolException catch (error) {
      result.completeError(error);
    } on McpGatewayFailure catch (error) {
      result.completeError(error);
    } catch (_) {
      gateway.close().ignore();
      result.completeError(const McpGatewayFailure(ErrorCode.internal));
    } finally {
      _produced = true;
      maybeFinished();
    }
  }

  void retire() {
    _retired = true;
    _poll?.cancel();
    _poll = null;
    if (!_wake.isCompleted) _wake.complete();
    maybeFinished();
  }

  Future<void> cancelInterest() {
    if (_cancelFuture != null) return _cancelFuture!;
    final completion = Completer<void>();
    _cancelFuture = completion.future;
    completion.future.ignore();
    retire();
    final budget = gateway._now + const Duration(seconds: 5);
    Future<void>(() async {
      try {
        await _ack.future.timeout(gateway._remaining(budget));
        if (!gateway._closed && _handle != null) {
          final reply = parse(
            await gateway._rpc(
              'mcp.invoke',
              {
                'cancel': {'operationId': _handle},
              },
              budget,
              operation: this,
              cancel: true,
            ),
          );
          if (reply.kind != McpInvokeReplyKind.cancelled) invalid();
        }
      } catch (_) {
        gateway.close().ignore();
        throw const McpGatewayFailure(ErrorCode.serviceUnavailable);
      } finally {
        _cancelDone = true;
        maybeFinished();
      }
    }).then(completion.complete, onError: completion.completeError);
    return completion.future;
  }

  Future<void> beforePublish() => _guardFuture ??= _guard();
  Future<void> _guard() async {
    _guardStarted = true;
    validatePublication();
    final budget = gateway._now + const Duration(seconds: 5);
    try {
      _lease = await gateway._gate.acquire(
        deadline: gateway._remaining(budget),
      );
      validatePublication();
      if (fixed != null || _fixed) {
        await gateway._client.verifyLive(deadline: gateway._remaining(budget));
      } else {
        await gateway._ping(budget, operation: this);
      }
    } on _RpcFailure catch (error) {
      throw McpGatewayFailure(_publicCode(error.code));
    } on McpGatewayFailure {
      rethrow;
    } catch (error) {
      gateway.close().ignore();
      throw McpGatewayFailure(
        error is StateError && error.message == 'TIMEOUT'
            ? ErrorCode.timeout
            : ErrorCode.serviceUnavailable,
      );
    }
  }

  void validatePublication() {
    if (gateway._closed || gateway._client.isClosed)
      throw const McpGatewayFailure(ErrorCode.serviceUnavailable);
    if (!_fixed &&
        (_retired ||
            fixed == null &&
                gateway._expires != null &&
                !gateway._clock.utcNow.isBefore(gateway._expires!)))
      throw const McpGatewayFailure(ErrorCode.forbidden);
  }

  Future<void> afterPublish() {
    if (_releaseFuture != null) return _releaseFuture!;
    final completion = Completer<void>();
    _releaseFuture = completion.future;
    completion.future.ignore();
    Future<void>(() async {
      try {
        await _lease?.close();
        if (gateway._closed) await gateway._gate.close();
      } catch (_) {
        gateway.close().ignore();
        throw const McpGatewayFailure(ErrorCode.serviceUnavailable);
      } finally {
        _published = true;
        maybeFinished();
      }
    }).then(completion.complete, onError: completion.completeError);
    return completion.future;
  }

  void maybeFinished() {
    if (done.isCompleted ||
        !_produced ||
        _rpcCount != 0 ||
        (_cancelFuture != null && !_cancelDone) ||
        (_needsPublication && !_published && !(_retired && !_guardStarted)))
      return;
    gateway._operations.remove(this);
    done.complete();
  }
}
