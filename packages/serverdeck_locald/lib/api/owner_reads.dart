import 'dart:async';

import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/host_trust.dart' show TrustedLocalError;
import 'package:serverdeck_protocol/mcp/operations.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../remote/reads.dart';
import 'operational_auth.dart';
import 'owner_api.dart';

/// Owner UI uses the same read implementation with native owner authority.
final class RemoteReadOwnerApi implements TrustedOwnerApi {
  RemoteReadOwnerApi(this.service) {
    _unsubscribe = service.connections.sessions.onSessionDetached(_detach);
    _unsubscribeTarget = service.connections.onRetired(_target);
  }
  final RemoteReadService service;
  final _operations = <String, _OwnerRead>{};
  final _clock = Stopwatch()..start();
  final _codec = StrictCodec();
  late final void Function() _unsubscribe, _unsubscribeTarget;
  bool _closed = false;
  Future<void>? _closing;
  static const methods = {
    'servers.state',
    'servers.logs',
    'servers.configuration',
    'servers.executorInspect',
    'servers.recipes',
    'servers.readStatus',
    'servers.readCancel',
  };
  @override
  bool supports(String method) => methods.contains(method);
  void _owner(
    TrustedSessionRequest request,
    String method, {
    bool admitted = false,
  }) {
    if (_closed) throw StateError('SERVICE_UNAVAILABLE');
    if (!request.belongsTo(service.connections.sessions) ||
        request.role != OperationalRole.owner ||
        request.method != method ||
        admitted && !request.initialAdmissionProved)
      throw StateError('FORBIDDEN');
  }

  void _sweep() => _operations.removeWhere(
    (_, op) =>
        op.done &&
        op.reservations.isEmpty &&
        (op.retired || op.expires != null && _clock.elapsed >= op.expires!),
  );
  void _detach(String session) {
    for (final op in _operations.values.toList())
      if (op.session == session) _retire(op);
    _sweep();
  }

  void _target(String profile) {
    for (final op in _operations.values.toList())
      if (op.args['serverId'] == profile) _retire(op);
    _sweep();
  }

  void _retire(_OwnerRead op) {
    op.retired = true;
    op.result = null;
    op.work?.cancelInterest().ignore();
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
    requireUuid(requestId);
    final input = _codec.decode(
      _codec.encode(params, maxBytes: 8192),
      maxBytes: 8192,
    );
    if (method == 'servers.readStatus' || method == 'servers.readCancel') {
      requireFields(input, {'operationId'});
      requireUuid(input['operationId']);
      return TrustedOwnerInvocation(request, () async {
        _owner(request, method, admitted: true);
        await request.revalidate().timeout(request.rpcRemaining);
        request.rpcRemaining;
        _owner(request, method, admitted: true);
        _sweep();
        final id = input['operationId'] as String, op = _operations[id];
        final cancel = method == 'servers.readCancel';
        if (op == null ||
            op.retired ||
            !identical(op.principal, request.connectionInterest)) {
          if (cancel) return {'operationId': id, 'cancelled': false};
          throw StateError('NOT_FOUND');
        }
        if (cancel) {
          final pending = op.result == null && op.code == null;
          if (pending) {
            op.code = 'CANCELLED';
            op.expires = _clock.elapsed + const Duration(seconds: 60);
            op.work?.cancelInterest().ignore();
          }
          return {'operationId': id, 'cancelled': pending};
        }
        if (op.result != null)
          return {
            'operationId': id,
            'state': 'succeeded',
            'kind': op.kind,
            'result': op.result,
          };
        if (op.code != null)
          return {'operationId': id, 'state': 'failed', 'code': op.code};
        return {'operationId': id, 'state': 'running'};
      });
    }
    final allowed = method == 'servers.logs'
        ? {'unit', 'since', 'until', 'priority', 'text', 'limit', 'cursor'}
        : method == 'servers.configuration'
        ? {'resourceId', 'refresh'}
        : method == 'servers.executorInspect' || method == 'servers.recipes'
        ? <String>{}
        : {'refresh'};
    requireFields(input, {
      'profileId',
      if (method == 'servers.configuration') 'resourceId',
    }, allowed..remove('resourceId'));
    requireUuid(input['profileId']);
    final args = <String, Object?>{...input}..remove('profileId');
    args['serverId'] = input['profileId'];
    final kind = method.substring('servers.'.length),
        tool = method == 'servers.executorInspect'
            ? 'owner_executor_inspect'
            : 'serverdeck_${kind == 'logs'
                  ? 'logs_read'
                  : kind == 'state'
                  ? 'state_get'
                  : kind == 'recipes'
                  ? 'recipes_list'
                  : 'configuration_get'}';
    _sweep();
    var op = _operations[requestId];
    if (op != null) {
      if (!identical(op.principal, request.connectionInterest) || op.retired)
        throw StateError('NOT_FOUND');
      if (op.kind != kind ||
          _codec.canonical(op.args).toString() !=
              _codec.canonical(args).toString())
        throw StateError('IDEMPOTENCY_CONFLICT');
    } else {
      if (_operations.length >= 16) throw StateError('RESOURCE_LIMIT');
      op = _OwnerRead(
        requestId,
        request.sessionId,
        request.connectionInterest,
        kind,
        args,
      );
      _operations[requestId] = op;
    }
    final operation = op;
    final reservation = Object();
    operation.reservations.add(reservation);
    return TrustedOwnerInvocation(
      request,
      () async {
        _owner(request, method, admitted: true);
        if (!operation.reservations.contains(reservation) || operation.retired)
          throw StateError('NOT_FOUND');
        if (operation.code == 'CANCELLED') {
          if (operation.work == null) operation.done = true;
          return {'operationId': operation.id, 'state': 'running'};
        }
        if (operation.work == null) {
          final work = operation.work = service.startOwner(
            request.ownerReadContext(),
            tool,
            operation.args,
          );
          work.result
              .then<void>(
                (value) {
                  if (!operation.retired && operation.code == null)
                    operation.result = value;
                },
                onError: (Object error, StackTrace _) {
                  if (!operation.retired && operation.code == null)
                    operation.code =
                        error is StateError &&
                            (mcpDomainCodes.contains(error.message) ||
                                TrustedLocalError.codes.contains(error.message))
                        ? error.message
                        : 'INTERNAL';
                },
              )
              .whenComplete(
                () => operation.expires =
                    _clock.elapsed + const Duration(seconds: 60),
              )
              .ignore();
          work.done.then<void>((_) {
            operation.done = true;
            _sweep();
          }).ignore();
        }
        return {'operationId': operation.id, 'state': 'running'};
      },
      onClose: () {
        operation.reservations.remove(reservation);
        if (operation.work == null && operation.code != null)
          operation.done = true;
        if (operation.work == null &&
            operation.code == null &&
            operation.reservations.isEmpty)
          _operations.remove(operation.id);
        _sweep();
      },
    );
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    _unsubscribe();
    _unsubscribeTarget();
    for (final op in _operations.values) _retire(op);
    return _closing = Future.wait([
      for (final op in _operations.values)
        if (op.work != null) op.work!.done,
    ]).then<void>((_) => _operations.clear());
  }
}

final class _OwnerRead {
  _OwnerRead(this.id, this.session, this.principal, this.kind, this.args);
  final String id, session, kind;
  final Object principal;
  final Map<String, Object?> args;
  final reservations = <Object>{};
  RemoteReadWork? work;
  Map<String, Object?>? result;
  String? code;
  Duration? expires;
  bool retired = false, done = false;
}
