import 'dart:async';
import 'dart:math';

import 'package:serverdeck_protocol/mcp/catalog.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';

import '../api/operational_auth.dart';

/// All implementations are shared with the trusted owner service. This interface
/// cannot create an authenticated context, select an origin or export a key.
abstract interface class McpToolServices {
  McpServiceOperation start(
    OperationalMcpContext context,
    McpToolDefinition tool,
    Map<String, Object?> arguments,
  );
}

final class McpServiceOperation {
  const McpServiceOperation(this.result, this.cancelInterest);
  final Future<McpToolResult> result;
  final Future<void> Function() cancelInterest;
}

final class _Operation {
  _Operation(this.id, this.context, this.started);
  final String id;
  final OperationalMcpContext context;
  final Duration started;
  McpServiceOperation? service;
  McpInvokeReply? result;
  Duration? expires;
  Future<String?>? cleanupAcknowledged;
  bool exposed = false, retired = false, timedOut = false;
  bool resultSettled = false, cleanupSettled = true;
  bool finishing = false;
}

String _operationId() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// One same-isolate router for one native registry/workspace generation.
/// Unfinished work keeps its quota after response interest is retired.
final class McpRouter {
  McpRouter({
    required this.sessions,
    required this.authority,
    required this.services,
    Duration Function()? elapsed,
  }) {
    _clock = elapsed ?? () => _watch.elapsed;
    _removeDetach = sessions.onSessionDetached(_detach);
    try {
      _removeGrant = authority.onGrantPublished(
        (id, _) => _invalidateGrant(id),
      );
    } catch (_) {
      _removeDetach();
      rethrow;
    }
  }
  static const workspaceLimit = 32, sessionLimit = 16;
  static const operationLifetime = Duration(seconds: 30);
  static const completionLifetime = Duration(seconds: 60);
  final OperationalSessions sessions;
  final OperationalMcpAuthority authority;
  final McpToolServices services;
  final _watch = Stopwatch()..start();
  late final Duration Function() _clock;
  late final void Function() _removeDetach, _removeGrant;
  final _records = <String, _Operation>{};
  final _charged = <_Operation>{};
  Timer? _timer;
  bool _closed = false, _sweeping = false;
  int get retainedOperations => _records.length;
  int get chargedOperations => _charged.length;

  void _ready() {
    if (_closed) throw StateError('NOT_READY');
  }

  Future<McpInvokeReply> invoke(
    OperationalSessionRequest request,
    Object? params,
  ) async {
    _ready();
    request.requireMcpInvocationBinding(sessions, authority);
    // Snapshot original input before the first router await; do not canonicalize
    // decomposed Unicode or turn invalid float arguments into integers.
    final input = McpInvokeInput.fromJson(params);
    final context = await request.mcpContextWhenStable();
    if (!context.belongsTo(sessions, authority)) throw StateError('FORBIDDEN');
    await context.revalidate(deadline: request.rpcBudgetRemaining);
    request.rpcBudgetRemaining;
    sweep();
    _ready();
    await context.authorizeWhenStable(deadline: request.rpcBudgetRemaining);
    switch (input.kind) {
      case McpInvokeKind.catalog:
        final policy = await context.policyWhenStable(
          deadline: request.rpcBudgetRemaining,
        );
        final reply = McpInvokeReply.catalog(mcpToolsFor(policy));
        await _publication(request, context);
        return reply;
      case McpInvokeKind.request:
        final tool = mcpTool(input.name!);
        if (tool == null) {
          await _publication(request, context);
          return McpInvokeReply.invalidParams();
        }
        for (final scope in tool.requiredScopes)
          await context.authorizeWhenStable(
            scope: scope,
            deadline: request.rpcBudgetRemaining,
          );
        try {
          validateMcpArguments(tool, input.arguments!);
        } on FormatException {
          await _publication(request, context);
          return McpInvokeReply.invalidParams();
        }
        if (input.arguments!['serverId'] case final String serverId) {
          await context.authorizeWhenStable(
            serverId: serverId,
            deadline: request.rpcBudgetRemaining,
          );
        }
        if (_charged.length >= workspaceLimit ||
            _charged
                    .where((op) => op.context.sessionId == context.sessionId)
                    .length >=
                sessionLimit)
          throw StateError('RESOURCE_LIMIT');
        final op = _Operation(_operationId(), context, _clock());
        _charged.add(op);
        _records[op.id] = op;
        try {
          op.service = services.start(context, tool, input.arguments!);
          if (op.retired) _cleanup(op);
          unawaited(
            op.service!.result.then<void>(
              (result) => _finish(op, result),
              onError: (Object _, StackTrace __) =>
                  _finish(op, McpToolResult.failure('INTERNAL')),
            ),
          );
        } catch (_) {
          unawaited(_finish(op, McpToolResult.failure('INTERNAL')));
        }
        _wakeSoon();
        // Already-resolved results settle before this event turn. Slower work
        // exposes its handle immediately instead of occupying a local RPC.
        try {
          await Future<void>.delayed(Duration.zero);
          await _publication(request, context);
        } catch (_) {
          _retire(op);
          rethrow;
        }
        if (op.retired) throw StateError('FORBIDDEN');
        final result = op.result;
        if (result != null) {
          _removeRecord(op);
          _release(op);
          return result;
        }
        op.exposed = true;
        return McpInvokeReply.pending(op.id);
      case McpInvokeKind.poll:
        final op = await _owned(
          context,
          input.operationId!,
          request.rpcBudgetRemaining,
        );
        if (op.retired) throw StateError('FORBIDDEN');
        await _publication(request, context);
        if (!identical(_records[op.id], op) || op.retired)
          throw StateError('FORBIDDEN');
        return op.result ?? McpInvokeReply.pending(op.id);
      case McpInvokeKind.cancel:
        final op = await _owned(
          context,
          input.operationId!,
          request.rpcBudgetRemaining,
        );
        _retire(op, retainHandle: true);
        final acknowledged = op.cleanupAcknowledged;
        if (acknowledged != null) {
          String? failure;
          try {
            failure = await acknowledged.timeout(request.rpcBudgetRemaining);
          } on TimeoutException {
            throw StateError('TIMEOUT');
          }
          if (failure != null) throw StateError(failure);
        }
        await _publication(request, context);
        return McpInvokeReply.cancelled();
    }
  }

  Future<void> _publication(
    OperationalSessionRequest request,
    OperationalMcpContext context,
  ) async {
    while (true) {
      await context.revalidate(deadline: request.rpcBudgetRemaining);
      try {
        request.rpcRemaining;
        _ready();
        context.authorize();
        return;
      } catch (error) {
        if (!request.isAuthorityPublicationPause(error)) rethrow;
      }
    }
  }

  Future<_Operation> _owned(
    OperationalMcpContext context,
    String id,
    Duration deadline,
  ) async {
    await context.authorizeWhenStable(deadline: deadline);
    final op = _records[id];
    if (op == null ||
        op.context.sessionId != context.sessionId ||
        op.context.grantId != context.grantId ||
        op.context.revision != context.revision)
      throw StateError('FORBIDDEN');
    return op;
  }

  Future<void> _finish(_Operation op, McpToolResult result) async {
    if (op.resultSettled || op.finishing) return;
    op.finishing = true;
    if (!_closed && !op.retired && !op.timedOut) {
      try {
        await op.context.authorizeWhenStable(
          deadline: op.started + operationLifetime - _clock(),
        );
      } catch (error) {
        if (error is StateError &&
            error.message == 'TIMEOUT' &&
            !_closed &&
            !op.retired) {
          _timeout(op);
        } else {
          _retire(op);
        }
      }
      if (!op.retired && !op.timedOut) {
        if (_clock() >= op.started + operationLifetime) {
          _timeout(op);
        } else {
          try {
            op.result = McpInvokeReply.done(result);
          } catch (_) {
            op.result = McpInvokeReply.done(McpToolResult.failure('INTERNAL'));
          }
          if (_clock() >= op.started + operationLifetime) {
            _timeout(op);
          } else {
            op.expires = _clock() + completionLifetime;
          }
        }
      }
    }
    op.resultSettled = true;
    op.finishing = false;
    _release(op);
    _wakeSoon();
  }

  void _cleanup(_Operation op) {
    if (op.cleanupAcknowledged != null || op.service == null) return;
    op.cleanupSettled = false;
    final actual = Future<void>.sync(op.service!.cancelInterest)
        .then<String?>(
          (_) => null,
          onError: (Object _, StackTrace __) => 'INTERNAL',
        )
        .whenComplete(() {
          op.cleanupSettled = true;
          _release(op);
        });
    // One shared bounded acknowledgement; repeated cancel does not attach an
    // unbounded set of timeout listeners to a permanently unresolved cleanup.
    op.cleanupAcknowledged = actual.timeout(
      const Duration(seconds: 5),
      onTimeout: () => 'TIMEOUT',
    );
  }

  void _retire(_Operation op, {bool retainHandle = false}) {
    if (!op.retired) {
      op.retired = true;
      op.result = null;
      op.expires = _clock() + completionLifetime;
      _cleanup(op);
    }
    if (!retainHandle) _removeRecord(op);
    _release(op);
    _wakeSoon();
  }

  void _removeRecord(_Operation op) {
    if (identical(_records[op.id], op)) _records.remove(op.id);
  }

  void _timeout(_Operation op) {
    op.timedOut = true;
    op.result = McpInvokeReply.done(McpToolResult.failure('TIMEOUT'));
    op.expires = op.started + operationLifetime + completionLifetime;
    _cleanup(op);
  }

  void _release(_Operation op) {
    if (!identical(_records[op.id], op) &&
        op.resultSettled &&
        op.cleanupSettled) {
      op.result = null;
      _charged.remove(op);
    }
  }

  void _detach(String sessionId) {
    for (final op in _charged.toList()) {
      if (op.context.sessionId == sessionId) _retire(op);
    }
  }

  void _invalidateGrant(String grantId) {
    // Never consult unrelated grants inside the store's publication gate.
    for (final op in _charged.toList()) {
      if (op.context.grantId == grantId) _retire(op);
    }
  }

  void _wakeSoon() {
    if (_closed || _sweeping) return;
    _timer?.cancel();
    _timer = Timer(Duration.zero, sweep);
  }

  /// Also callable by the owner lifecycle when using its monotonic test clock.
  void sweep() {
    if (_closed || _sweeping) return;
    _sweeping = true;
    _timer?.cancel();
    _timer = null;
    Duration? next;
    final now = _clock();
    void due(Duration value) {
      if (next == null || value < next!) next = value;
    }

    try {
      for (final op in _charged.toList()) {
        if (!op.retired) {
          try {
            due(op.context.untilExpiry);
          } catch (_) {
            _retire(op);
            continue;
          }
        }
        if (!op.retired && !op.resultSettled && !op.timedOut) {
          final remaining = op.started + operationLifetime - now;
          if (remaining <= Duration.zero) {
            _timeout(op);
          } else {
            due(remaining);
          }
        }
        if (op.expires case final Duration expires) {
          final remaining = expires - now;
          if (remaining <= Duration.zero) {
            op.result = null;
            _removeRecord(op);
            if (!op.resultSettled) _retire(op);
            _release(op);
          } else if (identical(_records[op.id], op)) {
            due(remaining);
          }
        }
      }
    } finally {
      _sweeping = false;
      if (!_closed && next != null) {
        _timer = Timer(next! <= Duration.zero ? Duration.zero : next!, sweep);
      }
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _removeDetach();
    _removeGrant();
    _timer?.cancel();
    for (final op in _charged.toList()) _retire(op);
    _watch.stop();
  }
}
