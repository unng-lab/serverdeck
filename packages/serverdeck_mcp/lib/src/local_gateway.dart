import 'dart:async';
import 'dart:convert';

import 'package:serverdeck_protocol/errors.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';
import 'package:serverdeck_windows/pipe_worker.dart';

import 'server.dart';

ErrorCode _publicCode(ErrorCode code) =>
    code == ErrorCode.unauthorized ? ErrorCode.forbidden : code;

final class _RpcFailure implements Exception {
  _RpcFailure(
    this.code, {
    this.terminal = false,
    this.origin,
    RetryAdvice? retry,
  }) : retry = retry ?? LocalError(code).retry;
  final ErrorCode code;
  final RetryAdvice retry;
  final bool terminal;
  final OperationalRpcFailureOrigin? origin;
  Map<String, Object?> result() => McpToolResult.failure(
    _publicCode(code).wireName,
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
  LocalMcpGateway.unconfigured()
    : _client = null,
      _gate = null,
      _expires = null;
  LocalMcpGateway._(this._client, this._gate, this._expires) {
    _client!.done
        .then<void>(
          (_) {
            close().ignore();
          },
          onError: (Object _) {
            close().ignore();
          },
        )
        .ignore();
    _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_closed || _heartbeatBusy || _client.pendingRequests >= 16) return;
      _heartbeatBusy = true;
      _ping(_now + const Duration(seconds: 5))
          .catchError((Object error) {
            if (error is! _RpcFailure ||
                error.code != ErrorCode.resourceLimit ||
                error.origin != OperationalRpcFailureOrigin.local ||
                error.terminal)
              close().ignore();
          })
          .whenComplete(() {
            _heartbeatBusy = false;
          })
          .ignore();
    });
  }

  /// Admission denial leaves the caller-owned bootstrap session untouched.
  static Future<LocalMcpGateway> connect(
    OperationalClientSession session,
  ) async {
    final grant = session.grant;
    if (session.role != OperationalRole.mcp || grant == null)
      throw const McpGatewayFailure(ErrorCode.forbidden);
    late final OperationalApiClient client;
    try {
      client = OperationalApiClient(session);
    } on OperationalRpcException catch (error) {
      throw McpGatewayFailure(_publicCode(error.code));
    }
    final creating = session.peer.publicationGate(session.hello.generation);
    creating.ignore();
    try {
      final gate = await creating.timeout(const Duration(seconds: 5));
      if (client.isClosed) {
        await gate.close();
        throw const McpGatewayFailure(ErrorCode.serviceUnavailable);
      }
      return LocalMcpGateway._(client, gate, DateTime.parse(grant.expiresAt));
    } catch (error) {
      // A timed-out factory still owns any later-created gate and native work.
      creating.then<void>((gate) => gate.close()).ignore();
      try {
        await client.close();
      } catch (_) {
        /* Remains terminal. */
      }
      throw McpGatewayFailure(
        error is TimeoutException
            ? ErrorCode.timeout
            : ErrorCode.serviceUnavailable,
      );
    }
  }

  final OperationalApiClient? _client;
  final OperationalPublicationGate? _gate;
  final DateTime? _expires;
  final _watch = Stopwatch()..start();
  final _operations = <_Operation>{};
  final _calls = <_RpcWork>{};
  Timer? _heartbeat;
  bool _heartbeatBusy = false, _closed = false;
  Future<void>? _closeFuture;
  Duration get _now => _watch.elapsed;

  McpInvocation _immediate(Map<String, Object?> value) {
    final complete = Future<void>.value();
    return McpInvocation(
      Future.value(value),
      () => complete,
      beforePublish: () => complete,
      validatePublication: () {},
      afterPublish: () => complete,
    );
  }

  @override
  McpInvocation start(String method, Map<String, Object?> params) {
    if (_closed) throw const McpGatewayFailure(ErrorCode.serviceUnavailable);
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
    if (_client == null) {
      return _immediate(
        method == 'tools/list'
            ? {'tools': <Object?>[]}
            : McpToolResult.failure('FORBIDDEN').toJson(),
      );
    }
    if (_operations.length >= 16) {
      if (method == 'tools/list')
        throw const McpGatewayFailure(ErrorCode.resourceLimit);
      return _immediate(McpToolResult.failure('RESOURCE_LIMIT').toJson());
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
      if (_closed || _client!.isClosed)
        throw _RpcFailure(ErrorCode.serviceUnavailable, terminal: true);
      if (!cancel && operation?._retired == true)
        throw const McpGatewayFailure(ErrorCode.forbidden);
    }

    live();
    final stage = _now + const Duration(seconds: 5);
    until = until < stage ? until : stage;
    while (_client!.pendingRequests >= 16 || _calls.length >= 16) {
      live();
      if (_calls.isEmpty)
        throw _RpcFailure(
          ErrorCode.resourceLimit,
          origin: OperationalRpcFailureOrigin.local,
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
    } on OperationalRpcException catch (error) {
      if (error.terminal) close().ignore();
      throw _RpcFailure(
        error.code,
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
    _heartbeat?.cancel();
    for (final operation in _operations.toList()) {
      operation.retire();
    }
    // Start native cleanup before awaiting publication interests. A publication
    // lease is released only by afterPublish after actual guard/flush settlement.
    final native = _client?.close() ?? Future<void>.value();
    final gate = _gate?.close() ?? Future<void>.value();
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
  _Operation(this.gateway, this.method, this.input)
    : until = gateway._now + const Duration(seconds: 35) {
    result.future.ignore();
    done.future.ignore();
  }
  final LocalMcpGateway gateway;
  final String method;
  final Map<String, Object?> input;
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
  OperationalPublicationLease? _lease;
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
    if (gateway._closed || gateway._client!.isClosed)
      throw _RpcFailure(ErrorCode.serviceUnavailable, terminal: true);
    if (_retired) throw const McpGatewayFailure(ErrorCode.forbidden);
    gateway._remaining(until);
  }

  Future<void> run() async {
    try {
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
      else
        result.complete(error.result());
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
    if (_fixed) return; // Only locally synthesized, fixed, data-free failures.
    _guardStarted = true;
    validatePublication();
    final budget = gateway._now + const Duration(seconds: 5);
    try {
      _lease = await gateway._gate!.acquire(
        deadline: gateway._remaining(budget),
      );
      validatePublication();
      await gateway._ping(budget, operation: this);
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
    if (_fixed) return;
    if (gateway._closed || gateway._client!.isClosed)
      throw const McpGatewayFailure(ErrorCode.serviceUnavailable);
    if (_retired || !DateTime.now().toUtc().isBefore(gateway._expires!))
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
        if (gateway._closed) await gateway._gate?.close();
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
