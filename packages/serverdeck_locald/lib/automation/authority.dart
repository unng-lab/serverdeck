import 'dart:async';

import 'package:serverdeck_protocol/automation/authority_owner.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../api/operational_auth.dart';
import '../storage/state_store.dart';
import 'authority_commands.dart';

DateTime _now() => DateTime.fromMillisecondsSinceEpoch(
  DateTime.now().toUtc().millisecondsSinceEpoch,
  isUtc: true,
);

/// Actual native actors and the same durable approval/delegation backend.
/// Owner-only decisions are never inferred from supplied origin or JSON roles.
final class TrustedAutomationAuthorityService {
  TrustedAutomationAuthorityService({
    required this.store,
    required this.sessions,
    required this.authority,
  }) {
    if (!sessions.hasNativePublicationGate) throw StateError('NOT_READY');
    store.trustedOperational;
  }
  final StateStore store;
  final TrustedSessions sessions;
  final TrustedMcpAuthority authority;
  final _operations = <AutomationAuthorityOperation>{};
  bool _closed = false, _nativeFailure = false;
  Future<void>? _closing;

  AutomationAuthorityOperation startOwner(
    TrustedSessionRequest request,
    String method,
    Map<String, Object?> arguments,
  ) {
    if (!request.belongsTo(sessions) ||
        request.role != OperationalRole.owner ||
        request.method != method ||
        !request.initialAdmissionProved)
      throw StateError('FORBIDDEN');
    if (!automationAuthorityOwnerMethods.contains(method))
      throw StateError('UNSUPPORTED');
    request.rpcRemaining;
    return _start(method, arguments, owner: request);
  }

  AutomationAuthorityOperation startMcp(
    TrustedMcpContext context,
    Map<String, Object?> arguments,
  ) {
    if (!context.belongsTo(sessions, authority)) throw StateError('FORBIDDEN');
    context.authorize(scope: McpScope.apply);
    return _start('approvals.request', arguments, mcp: context);
  }

  AutomationAuthorityOperation _start(
    String method,
    Map<String, Object?> arguments, {
    TrustedSessionRequest? owner,
    TrustedMcpContext? mcp,
  }) {
    if (_closed) throw StateError('NOT_READY');
    if (_nativeFailure) throw StateError('SERVICE_UNAVAILABLE');
    if (_operations.length >= 32) throw StateError('RESOURCE_LIMIT');
    final input = StrictCodec().decode(
      encodeMcpMessage(arguments, maxBytes: 256 * 1024),
      maxBytes: 256 * 1024,
    );
    final mutation = automationAuthorityMutations[method];
    final command = mutation == null
        ? null
        : AutomationAuthorityCommand.parse(mutation, input);
    if (mutation == null) {
      if (method.endsWith('.get')) {
        final field = method.startsWith('delegations.')
            ? 'delegationId'
            : 'approvalId';
        requireFields(input, {field});
        requireUuid(input[field]);
      } else {
        requireFields(input, {}, {'offset', 'limit', 'serverId'});
        if (input.containsKey('serverId')) requireUuid(input['serverId']);
        final offset = input['offset'] ?? 0, limit = input['limit'] ?? 25;
        if (offset is! int ||
            offset < 0 ||
            offset > 1000 ||
            limit is! int ||
            limit < 1 ||
            limit > 50)
          throw const FormatException('VALIDATION');
        input['offset'] = offset;
        input['limit'] = limit;
      }
    }
    final operation = AutomationAuthorityOperation._(
      this,
      method,
      input,
      command,
      owner,
      mcp,
    );
    _operations.add(operation);
    operation._run().ignore();
    return operation;
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    final pending = _operations.toList();
    for (final operation in pending) operation.stop('SERVICE_UNAVAILABLE');
    return _closing = Future.wait(pending.map((value) => value.done)).then((_) {
      if (_nativeFailure) throw StateError('SERVICE_UNAVAILABLE');
    });
  }
}

final class AutomationAuthorityOperation {
  AutomationAuthorityOperation._(
    this.service,
    this.method,
    this.input,
    this.command,
    this.owner,
    this.mcp,
  ) {
    _result.future.ignore();
  }
  final TrustedAutomationAuthorityService service;
  final String method;
  final Map<String, Object?> input;
  final AutomationAuthorityCommand? command;
  final TrustedSessionRequest? owner;
  final TrustedMcpContext? mcp;
  final _watch = Stopwatch()..start();
  final _result = Completer<Map<String, Object?>>(), _done = Completer<void>();
  final _native = <Future<void>>{};
  bool _stopped = false;
  Future<Map<String, Object?>> get result => _result.future;
  Future<void> get done => _done.future;
  Duration get remaining {
    final left =
        owner?.rpcRemaining ?? const Duration(seconds: 30) - _watch.elapsed;
    if (left <= Duration.zero) throw StateError('TIMEOUT');
    return left;
  }

  Duration get _proofBudget {
    final left = remaining;
    return left < const Duration(seconds: 5)
        ? left
        : const Duration(seconds: 5);
  }

  void _check() {
    if (_stopped || service._closed) throw StateError('CANCELLED');
    if (service._nativeFailure) throw StateError('SERVICE_UNAVAILABLE');
    remaining;
    mcp?.authorize(scope: McpScope.apply);
  }

  void _observe(Future<void> actual) {
    final tracked = actual.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {
        service._nativeFailure = true;
      },
    );
    _native.add(tracked);
    tracked.then<void>((_) => _native.remove(tracked)).ignore();
  }

  Future<void> _proof() async {
    _check();
    if (owner != null) {
      await owner!.revalidate(observeNativeCompletion: _observe);
    } else {
      final watch = Stopwatch()..start(), budget = _proofBudget;
      await mcp!.authorizeWhenStable(scope: McpScope.apply, deadline: budget);
      final left = budget - watch.elapsed;
      if (left <= Duration.zero) throw StateError('TIMEOUT');
      await mcp!.revalidate(deadline: left, observeNativeCompletion: _observe);
    }
    _check();
  }

  void stop(String code) {
    if (_stopped) return;
    _stopped = true;
    if (!_result.isCompleted) _result.completeError(StateError(code));
  }

  Future<void> cancelInterest() {
    stop('CANCELLED');
    return done;
  }

  Map<String, Object?> _read() {
    _check();
    final graph = service.store.trustedOperational.automation;
    final delegations = method.startsWith('delegations.');
    final server = input['serverId'] as String?;
    final values = delegations
        ? {
            for (final row in graph.delegations.values)
              if (server == null || row.serverIds.contains(server))
                row.id: row.toJson(),
          }
        : {
            for (final row in graph.approvals.values)
              if (server == null || graph.plans[row.planId]!.serverId == server)
                row.id: row.toJson(),
          };
    if (method.endsWith('.get')) {
      final row = values[input[delegations ? 'delegationId' : 'approvalId']];
      if (row == null) throw StateError('NOT_FOUND');
      return {delegations ? 'delegation' : 'approval': row};
    }
    final keys = values.keys.toList()..sort();
    final offset = input['offset'] as int, limit = input['limit'] as int;
    final selected = keys.skip(offset).take(limit).toList();
    final next = offset + selected.length;
    return {
      'items': [for (final key in selected) values[key]],
      'nextOffset': next < keys.length ? next : null,
    };
  }

  Future<void> _run() async {
    Timer? timer;
    try {
      timer = Timer(remaining, () => stop('TIMEOUT'));
      await _proof();
      Map<String, Object?> output;
      if (command == null) {
        output = _read();
      } else {
        output = await service.sessions.runAuthorityMutation(
          () async {
            await _proof();
            return service.store.mutateTrustedAuthority(
              command!,
              originGrantId: mcp?.grantId,
              expectedGrantRevision: mcp?.revision,
              // Accepted store writes retain their receipt after caller timeout.
              // Current grant checks execute inside the native transaction.
              clock: _now,
            );
          },
          deadline: _proofBudget,
          observeNativeCompletion: _observe,
        );
      }
      await _proof();
      _check();
      final captured = captureAutomationAuthorityOwnerResult(method, output);
      if (!_result.isCompleted) _result.complete(captured);
    } catch (error) {
      if (!_result.isCompleted) _result.completeError(error);
    } finally {
      timer?.cancel();
      await Future.wait(_native.toList());
      service._operations.remove(this);
      _done.complete();
    }
  }
}
