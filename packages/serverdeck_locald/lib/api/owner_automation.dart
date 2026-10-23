import 'dart:async';

import 'package:serverdeck_protocol/automation/owner_operations.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/mcp/catalog.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../automation/plans.dart';
import '../automation/jobs.dart';
import 'operational_auth.dart';
import 'owner_api.dart';

/// Owner-only async projection of the actual shared automation services.
final class AutomationOwnerApi implements TrustedOwnerApi {
  AutomationOwnerApi({required this.plans, required this.jobs}) {
    if (!identical(plans.executors, jobs.executors))
      throw StateError('NOT_READY');
    _unsubscribe = sessions.onSessionDetached((session) {
      for (final op in _operations.values.toList())
        if (op.session == session) _retire(op);
      _sweep();
    });
  }
  final TrustedPlanService plans;
  final TrustedJobService jobs;
  TrustedSessions get sessions => plans.executors.connections.sessions;
  final _operations = <String, _OwnerAutomation>{};
  final _inline = <_OwnerAutomationWork>{};
  final _clock = Stopwatch()..start();
  late final void Function() _unsubscribe;
  bool _closed = false, _failed = false;
  Future<void>? _closing;
  @override
  bool supports(String method) => ownerAutomationMethods.contains(method);
  void _owner(TrustedSessionRequest request, String method) {
    if (_closed) throw StateError('SERVICE_UNAVAILABLE');
    if (!request.belongsTo(sessions) ||
        request.role != OperationalRole.owner ||
        request.method != method)
      throw StateError('FORBIDDEN');
  }

  void _retire(_OwnerAutomation op) {
    op.retired = true;
    op.result = null;
    op.work?.cancelInterest().ignore();
    if (op.work == null) op.done = true;
  }

  void _sweep() {
    for (final op in _operations.values.toList()) {
      if (!op.retired && op.expires != null && op.expires! <= _clock.elapsed)
        _retire(op);
      if (op.done && op.reservations.isEmpty && op.retired)
        _operations.remove(op.id);
    }
  }

  @override
  TrustedOwnerInvocation prepare(
    TrustedSessionRequest request,
    String method,
    Map<String, Object?> params, {
    required String requestId,
  }) {
    _owner(request, method);
    if (!supports(method)) throw StateError('UNSUPPORTED');
    final input = StrictCodec().decode(
      encodeMcpMessage(params, maxBytes: 256 * 1024),
      maxBytes: 256 * 1024,
    );
    if (method == 'automation.status' || method == 'automation.cancel') {
      requireFields(input, {'operationId'});
      final id = requireUuid(input['operationId']);
      return TrustedOwnerInvocation(request, () async {
        _owner(request, method);
        await request.revalidate();
        _owner(request, method);
        request.rpcRemaining;
        _sweep();
        final op = _operations[id];
        if (op == null ||
            op.retired ||
            !identical(op.principal, request.connectionInterest))
          throw StateError('NOT_FOUND');
        if (method == 'automation.cancel') {
          final pending = op.result == null;
          if (pending) {
            op.cancelled = true;
            op.result = McpToolResult.failure('CANCELLED').toJson();
            op.expires = _clock.elapsed + const Duration(seconds: 60);
            op.work?.cancelInterest().ignore();
          }
          return {'operationId': id, 'cancelled': pending};
        }
        return op.result == null
            ? {'operationId': id, 'state': 'running'}
            : {
                'operationId': id,
                'state': 'done',
                'kind': op.method,
                'result': op.result,
              };
      });
    }
    final tool = switch (method) {
      'plans.create' => 'serverdeck_plan_create',
      'plans.get' => 'serverdeck_plans_get',
      'jobs.apply' => 'serverdeck_apply',
      'jobs.list' => 'serverdeck_jobs_list',
      'jobs.get' => 'serverdeck_jobs_get',
      'jobs.events' => 'serverdeck_jobs_events',
      'jobs.cancel' => 'serverdeck_jobs_cancel',
      'jobs.reconcile' => 'serverdeck_jobs_reconcile',
      _ => throw StateError('UNSUPPORTED'),
    };
    validateMcpArguments(mcpTool(tool)!, input);
    if (ownerAutomationInlineMethods.contains(method)) {
      _OwnerAutomationWork? work;
      return TrustedOwnerInvocation(
        request,
        () async {
          _owner(request, method);
          if (_inline.length >= 16) throw StateError('RESOURCE_LIMIT');
          final actor = request.ownerAutomationContext();
          final current = work = method.startsWith('plans.')
              ? _OwnerAutomationWork.plan(plans.startOwner(actor, tool, input))
              : _OwnerAutomationWork.job(jobs.startOwner(actor, tool, input));
          _inline.add(current);
          current.done
              .then<void>(
                (_) => _inline.remove(current),
                onError: (Object _, StackTrace __) {
                  _failed = true;
                  _inline.remove(current);
                },
              )
              .ignore();
          Map<String, Object?> result;
          try {
            final value = await current.result.timeout(request.rpcRemaining);
            result = McpToolResult.success(value).toJson();
            StrictCodec().encode(result, maxBytes: 2 * 1024 * 1024 - 4096);
          } on TimeoutException {
            throw StateError('TIMEOUT');
          } catch (error) {
            result = McpToolResult.failure(
              error is StateError && mcpDomainCodes.contains(error.message)
                  ? error.message
                  : error is FormatException
                  ? 'VALIDATION'
                  : 'INTERNAL',
            ).toJson();
          }
          request.rpcRemaining;
          return {
            'operationId': requestId,
            'state': 'done',
            'kind': method,
            'result': result,
          };
        },
        onClose: () {
          work?.cancelInterest().ignore();
        },
      );
    }
    _sweep();
    var op = _operations[requestId];
    if (op != null) {
      if (op.retired || !identical(op.principal, request.connectionInterest))
        throw StateError('NOT_FOUND');
      if (op.method != method ||
          StrictCodec().canonical(op.input).toString() !=
              StrictCodec().canonical(input).toString())
        throw StateError('IDEMPOTENCY_CONFLICT');
    } else {
      if (_operations.length >= 16) throw StateError('RESOURCE_LIMIT');
      op = _OwnerAutomation(
        requestId,
        request.sessionId,
        request.connectionInterest,
        method,
        input,
      );
      _operations[requestId] = op;
    }
    final operation = op, reservation = Object();
    operation.reservations.add(reservation);
    return TrustedOwnerInvocation(
      request,
      () async {
        _owner(request, method);
        if (operation.retired || !operation.reservations.contains(reservation))
          throw StateError('NOT_FOUND');
        if (operation.cancelled) {
          if (operation.work == null) operation.done = true;
          return {'operationId': operation.id, 'state': 'running'};
        }
        if (operation.work == null) {
          final actor = request.ownerAutomationContext();
          final work = operation.work = method.startsWith('plans.')
              ? _OwnerAutomationWork.plan(
                  plans.startOwner(actor, tool, operation.input),
                )
              : _OwnerAutomationWork.job(
                  jobs.startOwner(actor, tool, operation.input),
                );
          work.result
              .then<void>(
                (value) {
                  if (!operation.retired && !operation.cancelled) {
                    try {
                      final result = McpToolResult.success(value).toJson();
                      StrictCodec().encode(
                        result,
                        maxBytes: 2 * 1024 * 1024 - 4096,
                      );
                      operation.result = result;
                    } catch (_) {
                      operation.result = McpToolResult.failure('RESOURCE_LIMIT')
                          .toJson();
                    }
                  }
                },
                onError: (Object error, StackTrace _) {
                  if (!operation.retired && !operation.cancelled)
                    operation.result = McpToolResult.failure(
                      error is StateError &&
                              mcpDomainCodes.contains(error.message)
                          ? error.message
                          : error is FormatException
                          ? 'VALIDATION'
                          : 'INTERNAL',
                    ).toJson();
                },
              )
              .whenComplete(() {
                operation.expires ??=
                    _clock.elapsed + const Duration(seconds: 60);
              })
              .ignore();
          work.done
              .then<void>(
                (_) {
                  operation.done = true;
                  _sweep();
                },
                onError: (Object _, StackTrace __) {
                  _failed = true;
                  operation.done = true;
                  _retire(operation);
                  _sweep();
                },
              )
              .ignore();
        }
        return {'operationId': operation.id, 'state': 'running'};
      },
      onClose: () {
        operation.reservations.remove(reservation);
        if (operation.work == null && operation.reservations.isEmpty) {
          operation.done = true;
          if (!operation.cancelled) operation.retired = true;
        }
        _sweep();
      },
    );
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    _unsubscribe();
    final pending = _operations.values.toList();
    for (final op in pending) _retire(op);
    return _closing =
        Future.wait([
          for (final work in _inline.toList()) work.cancelInterest(),
          for (final op in pending)
            if (op.work != null) op.work!.done,
        ]).then<void>((_) {
          _operations.clear();
          if (_failed) throw StateError('SERVICE_UNAVAILABLE');
        });
  }
}

final class _OwnerAutomation {
  _OwnerAutomation(
    this.id,
    this.session,
    this.principal,
    this.method,
    this.input,
  );
  final String id, session, method;
  final Object principal;
  final Map<String, Object?> input;
  final reservations = <Object>{};
  _OwnerAutomationWork? work;
  Map<String, Object?>? result;
  Duration? expires;
  bool retired = false, cancelled = false, done = false;
}

final class _OwnerAutomationWork {
  _OwnerAutomationWork.plan(PlanOperation work)
    : result = work.result,
      done = work.done,
      cancelInterest = work.cancelInterest;
  _OwnerAutomationWork.job(JobOperation work)
    : result = work.result,
      done = work.done,
      cancelInterest = work.cancelInterest;
  final Future<Map<String, Object?>> result;
  final Future<void> done;
  final Future<void> Function() cancelInterest;
}
