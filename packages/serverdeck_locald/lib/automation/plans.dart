import 'dart:async';

import 'package:cryptography/dart.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/mcp/catalog.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../api/operational_auth.dart';
import '../remote/executor.dart';
import '../storage/state_store.dart';
import 'compiler.dart';
import 'plan_commands.dart';

const planTools = {'serverdeck_plan_create', 'serverdeck_plans_get'};
DateTime _now() => DateTime.fromMillisecondsSinceEpoch(
  DateTime.now().toUtc().millisecondsSinceEpoch,
  isUtc: true,
);
String _hash(Object? value) => const DartSha256()
    .hashSync(StrictCodec().canonical(value))
    .bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();
bool _equal(Object? a, Object? b) =>
    StrictCodec().canonical(a).toString() ==
    StrictCodec().canonical(b).toString();

/// Concrete plan service over the same catalog/store/native actors/root facade.
/// Neither a parsed plan nor a matching remote digest authorizes execution.
final class TrustedPlanService {
  TrustedPlanService(this.executors);
  final RemoteExecutorService executors;
  StateStore get store => executors.connections.store;
  final _operations = <PlanOperation>{};
  bool _closed = false, _nativeFailure = false;
  Future<void>? _closing;

  PlanOperation startOwner(
    TrustedOwnerAutomationContext context,
    String tool,
    Map<String, Object?> arguments,
  ) {
    if (!context.belongsTo(executors.connections.sessions) ||
        context.method !=
            (tool == 'serverdeck_plan_create' ? 'plans.create' : 'plans.get'))
      throw StateError('FORBIDDEN');
    context.remaining;
    if (_closed) throw StateError('NOT_READY');
    if (_nativeFailure) throw StateError('SERVICE_UNAVAILABLE');
    if (!planTools.contains(tool)) throw StateError('UNSUPPORTED');
    if (_operations.length >= 32) throw StateError('RESOURCE_LIMIT');
    final input = StrictCodec().decode(
      encodeMcpMessage(arguments, maxBytes: 256 * 1024),
      maxBytes: 256 * 1024,
    );
    validateMcpArguments(mcpTool(tool)!, input);
    final operation = PlanOperation._(this, null, tool, input, owner: context);
    _operations.add(operation);
    operation._run().ignore();
    return operation;
  }

  PlanOperation startMcp(
    TrustedMcpContext context,
    String tool,
    Map<String, Object?> arguments,
  ) {
    if (_closed) throw StateError('NOT_READY');
    if (_nativeFailure) throw StateError('SERVICE_UNAVAILABLE');
    if (!context.belongsTo(
      executors.connections.sessions,
      executors.connections.authority,
    ))
      throw StateError('FORBIDDEN');
    context.authorize(scope: McpScope.plan);
    if (!planTools.contains(tool)) throw StateError('UNSUPPORTED');
    if (_operations.length >= 32) throw StateError('RESOURCE_LIMIT');
    final input = StrictCodec().decode(
      encodeMcpMessage(arguments, maxBytes: 256 * 1024),
      maxBytes: 256 * 1024,
    );
    validateMcpArguments(mcpTool(tool)!, input);
    if (tool == 'serverdeck_plan_create')
      context.authorize(
        scope: McpScope.plan,
        serverId: requireUuid(input['serverId']),
      );
    final operation = PlanOperation._(this, context, tool, input);
    _operations.add(operation);
    operation._run().ignore();
    return operation;
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    for (final operation in _operations.toList())
      operation.stop('SERVICE_UNAVAILABLE');
    return _closing =
        Future.wait([
          for (final operation in _operations.toList()) operation.done,
        ]).then<void>((_) {
          if (_nativeFailure) throw StateError('SERVICE_UNAVAILABLE');
        });
  }
}

final class PlanOperation {
  PlanOperation._(
    this.service,
    this.context,
    this.tool,
    this.input, {
    this.owner,
  }) {
    _result.future.ignore();
  }
  final TrustedPlanService service;
  final TrustedMcpContext? context;
  final TrustedOwnerAutomationContext? owner;
  final String tool;
  final Map<String, Object?> input;
  final _watch = Stopwatch()..start();
  final _result = Completer<Map<String, Object?>>(), _done = Completer<void>();
  final _native = <Future<void>>{};
  RemoteExecutorOperation? _opening;
  bool _stopped = false;
  Future<Map<String, Object?>> get result => _result.future;
  Future<void> get done => _done.future;
  Duration get remaining {
    owner?.remaining;
    final value = const Duration(seconds: 30) - _watch.elapsed;
    if (value <= Duration.zero) throw StateError('TIMEOUT');
    return value;
  }

  Duration get _proofBudget {
    final value = remaining;
    return value < const Duration(seconds: 5)
        ? value
        : const Duration(seconds: 5);
  }

  void _check([String? server]) {
    if (_stopped || service._closed) throw StateError('CANCELLED');
    if (service._nativeFailure) throw StateError('SERVICE_UNAVAILABLE');
    remaining;
    context?.authorize(scope: McpScope.plan, serverId: server);
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

  Future<void> _proof([String? server]) async {
    if (_stopped || service._closed) throw StateError('CANCELLED');
    final budget = _proofBudget, watch = Stopwatch()..start();
    Duration left() {
      final value = budget - watch.elapsed, overall = remaining;
      if (value <= Duration.zero) throw StateError('TIMEOUT');
      return value < overall ? value : overall;
    }

    if (owner != null) {
      if (service.store.hasPendingMcpAuthorityPublication)
        await service.store.waitForMcpAuthority(deadline: left());
      try {
        await owner!.revalidate().timeout(left());
      } on TimeoutException {
        throw StateError('TIMEOUT');
      }
      _check(server);
      return;
    }
    await context!.authorizeWhenStable(
      scope: McpScope.plan,
      serverId: server,
      deadline: left(),
    );
    await context!.revalidate(
      deadline: left(),
      observeNativeCompletion: _observe,
    );
    _check(server);
  }

  void stop(String code) {
    if (_stopped) return;
    _stopped = true;
    if (!_result.isCompleted) _result.completeError(StateError(code));
    _opening?.close().ignore();
  }

  Future<void> cancelInterest() {
    stop('CANCELLED');
    return done;
  }

  Map<String, Object?> _get(String id) {
    final plan =
        service.store.trustedOperational.automation.plans[requireUuid(id)];
    if (plan == null ||
        context != null && plan.toJson()['originGrantId'] != context!.grantId)
      throw StateError('FORBIDDEN');
    _check(plan.serverId);
    return plan.toJson();
  }

  Future<Map<String, Object?>> _getStable(String id) async {
    while (true) {
      await _proof();
      try {
        return _get(id);
      } catch (error) {
        if (error is! StateError ||
            error.message != 'STORAGE_BLOCKED' ||
            !service.store.hasPendingMcpAuthorityPublication)
          rethrow;
        await service.store.waitForMcpAuthority(deadline: _proofBudget);
      }
    }
  }

  Future<void> _run() async {
    final timer = Timer(const Duration(seconds: 30), () => stop('TIMEOUT'));
    try {
      await _proof();
      Map<String, Object?> output;
      if (tool == 'serverdeck_plans_get') {
        final plan = await _getStable(requireUuid(input['planId']));
        output = {
          'plan': plan,
          'expired': !_now().isBefore(
            DateTime.parse(plan['expiresAt'] as String),
          ),
        };
      } else {
        final command = PlanCreateCommand.fromJson(input);
        await _proof(command.serverId);
        final replay = await service.executors.connections.sessions
            .runAuthorityMutation(
              () async {
                await _proof(command.serverId);
                return service.store.replayTrustedPlan(
                  command,
                  originGrantId: context?.grantId,
                  expectedGrantRevision: context?.revision,
                  at: _now(),
                );
              },
              deadline: _proofBudget,
              observeNativeCompletion: _observe,
            );
        if (replay != null) {
          output = Map<String, Object?>.of(replay);
        } else {
          final plan = await _create(command);
          await _proof(command.serverId);
          final receipt = await service.executors.connections.sessions
              .runAuthorityMutation(
                () async {
                  await _proof(command.serverId);
                  _check(command.serverId);
                  return service.store.persistTrustedPlan(
                    command,
                    plan,
                    originGrantId: context?.grantId,
                    expectedGrantRevision: context?.revision,
                    clock: _now,
                  );
                },
                deadline: _proofBudget,
                observeNativeCompletion: _observe,
              );
          await _proof(command.serverId);
          output = Map<String, Object?>.of(receipt);
        }
      }
      await _proof();
      _check();
      if (!_result.isCompleted) _result.complete(output);
    } catch (error) {
      if (!_result.isCompleted) _result.completeError(error);
    } finally {
      timer.cancel();
      try {
        await _opening?.close();
      } catch (_) {
        service._nativeFailure = true;
      }
      await owner?.settled;
      await Future.wait(_native.toList());
      service._operations.remove(this);
      _done.complete();
    }
  }

  Future<AutomationPlanRecord> _create(PlanCreateCommand command) async {
    _check(command.serverId);
    final snapshot = service.store.trustedOperational;
    final foundation = snapshot.foundation.foundation;
    final server = foundation.profiles[command.serverId];
    final profile = snapshot.automation.profiles[command.profileId];
    final revision = snapshot
        .automation
        .revisions['${command.profileId}:${command.revision}'];
    if (server == null ||
        profile == null ||
        profile.archived ||
        revision == null)
      throw StateError('FORBIDDEN');
    final params = revision.body.resolveParameters(command.parameters);
    final desired = revision.body.resolveSteps(params);
    final stepLimitExceeded =
        desired.fold<int>(
          0,
          (count, step) =>
              count +
              switch (step['kind']) {
                'service' => step.containsKey('enabled') ? 2 : 1,
                'config_file' => step['resourceId'] == 'system.motd' ? 1 : 2,
                _ => 1,
              },
        ) >
        32;
    AutomationPreflightCapsule? capsule;
    Map<String, Object?>? program;
    String? blocked;
    String? remoteBlockedField;
    try {
      if (stepLimitExceeded) throw StateError('RESOURCE_LIMIT');
      final opening = _opening = owner != null
          ? service.executors.startAutomationOwner(
              owner!,
              server.id,
              scope: McpScope.plan,
            )
          : service.executors.startMcp(
              context!,
              server.id,
              scope: McpScope.plan,
            );
      final session = await opening.result;
      _check(server.id);
      if (session.target['targetRevision'] != server.revision)
        throw StateError('PLAN_STALE');
      final operation = executorRequestId();
      final first = await session.request('preflight', {
        'operationId': operation,
        'profileBody': revision.body.toJson(),
        'profileDigest': revision.key.bodyDigest,
        'parameters': params,
        'expectedHostId': session.enrollment.hostId,
        'target': session.target,
      });
      if (first['operationId'] != operation ||
          !const {'running', 'completed'}.contains(first['state']))
        throw StateError('RUNTIME_INCOMPATIBLE');
      Map<String, Object?>? facts;
      while (facts == null) {
        _check(server.id);
        final value = await session.request('preflight_get', {
          'operationId': operation,
        });
        if (value['operationId'] != operation)
          throw StateError('RUNTIME_INCOMPATIBLE');
        if (value['state'] == 'failed') {
          if (value.containsKey('field')) {
            if (!const {
              'executor',
              'runtime',
              'trust',
              'recipe',
              'packages',
              'paths',
              'qualification',
              'memory',
              'step_limit',
              'observation',
            }.contains(value['field']))
              throw StateError('RUNTIME_INCOMPATIBLE');
            remoteBlockedField = value['field'] as String;
          }
          throw StateError(executorDomainCode('${value['code']}'));
        }
        if (value['state'] == 'succeeded') {
          facts = _object(value['result']);
          break;
        }
        if (value['state'] != 'running')
          throw StateError('RUNTIME_INCOMPATIBLE');
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      requireFields(facts, {
        'planFacts',
        'digest',
        'effects',
        'checks',
        'reasons',
        'observations',
      });
      final parsed = await AutomationPreflightCapsule.fromJson(
        _object(facts['planFacts']),
      );
      _check(server.id);
      final release = service.executors.release?.descriptor;
      final doc = parsed.toJson();
      if (parsed.digest != facts['digest'] ||
          parsed.operationId != operation ||
          parsed.profileDigest != revision.key.bodyDigest ||
          parsed.inputDigest != _hash(params) ||
          parsed.hostId != session.enrollment.hostId ||
          parsed.registryDigest != session.enrollment.registryDigest ||
          doc['runtimeVersion'] != release?.runtimeVersion ||
          doc['runtimeLockDigest'] != release?.lockDigest ||
          doc['compilerDigest'] != release?.compilerDigest ||
          doc['bootIdHash'] != session.hello['bootIdHash'])
        throw StateError('RUNTIME_INCOMPATIBLE');
      final rows = facts['observations'];
      if (rows is! List || rows.length > 5)
        throw StateError('RUNTIME_INCOMPATIBLE');
      final observed = <String, String>{};
      for (final raw in rows) {
        final observation = ManagedResourceObservationRecord.fromTrustedJson(
          _object(raw),
        );
        if (observed.containsKey(observation.resourceId) ||
            observation.serverId != server.id ||
            observation.workspaceId != foundation.workspaceId ||
            observation.targetRevision != server.revision ||
            observation.connectionRevision != server.connectionRevision ||
            observation.accessRevision != server.credentialRevision ||
            observation.trustRevision != server.trustRevision ||
            observation.hostId != parsed.hostId ||
            observation.resourceRegistryDigest != parsed.registryDigest ||
            !observation.isFreshAt(_now()))
          throw StateError('PLAN_STALE');
        observed[observation.resourceId] = await observation.fingerprint();
        _check(server.id);
      }
      if (!_equal(observed, parsed.baseObservations) ||
          !_equal(facts['reasons'], []))
        throw StateError('RUNTIME_INCOMPATIBLE');
      final compiled = compileAutomation(
        body: revision.body,
        parameters: params,
        baselineFingerprints: observed,
        qualifiedRecipes: {
          for (final recipe in parsed.recipes) recipe.digest: recipe,
        },
      ).toJson();
      if (!_equal(compiled['effects'], facts['effects']) ||
          !_equal(compiled['checks'], facts['checks']) ||
          !_equal(compiled['desired'], desired))
        throw StateError('RUNTIME_INCOMPATIBLE');
      capsule = parsed;
      program = compiled;
    } catch (error) {
      await _proof(command.serverId);
      final code = error is StateError
          ? error.message
          : error is FormatException
          ? 'RUNTIME_INCOMPATIBLE'
          : 'EXECUTOR_UNAVAILABLE';
      blocked = switch (code) {
        'NOT_READY' => 'EXECUTOR_UNAVAILABLE',
        'TRUST_REQUIRED' ||
        'TRUST_CHANGED' ||
        'EXECUTOR_UNAVAILABLE' ||
        'RUNTIME_INCOMPATIBLE' ||
        'PLAN_STALE' ||
        'TIMEOUT' ||
        'RESOURCE_LIMIT' ||
        'UNSUPPORTED' => code,
        _ => throw error,
      };
      capsule = null;
      program = null;
    }
    _check(command.serverId);
    final created = _now();
    final document = <String, Object?>{
      'workspaceId': foundation.workspaceId,
      'id': executorRequestId(),
      'requestId': command.requestId,
      'profileId': revision.key.profileId,
      'profileRevision': revision.key.revision,
      'profileDigest': revision.key.bodyDigest,
      'serverId': server.id,
      'serverRevision': server.revision,
      'connectionRevision': server.connectionRevision,
      'accessRevision': server.credentialRevision,
      'trustRevision': server.trustRevision,
      'hostId': capsule?.hostId,
      'registryDigest': capsule?.registryDigest,
      'exactParams': params,
      'inputDigest': _hash(params),
      'desired': desired,
      'baseObservations': capsule?.toJson()['baseObservations'] ?? [],
      'effects': program?['effects'] ?? [],
      'checks': program?['checks'] ?? [],
      'preflight': capsule?.toJson(),
      'preflightDigest': capsule?.digest,
      'status': blocked == null ? 'runnable' : 'blocked',
      'reasons': blocked == null
          ? []
          : [
              {
                'code': blocked,
                'field':
                    remoteBlockedField ??
                    switch (blocked) {
                      'TRUST_REQUIRED' || 'TRUST_CHANGED' => 'trust',
                      'PLAN_STALE' => 'observation',
                      'RESOURCE_LIMIT' =>
                        stepLimitExceeded ? 'step_limit' : 'executor',
                      'RUNTIME_INCOMPATIBLE' => 'runtime',
                      _ => 'executor',
                    },
                'stepId': null,
              },
            ],
      'createdAt': created.toIso8601String(),
      'expiresAt': created.add(const Duration(minutes: 5)).toIso8601String(),
      'originGrantId': context?.grantId,
    };
    document['digest'] = _hash(document);
    return AutomationPlanRecord.fromTrustedJson(document, revision: revision);
  }
}

Map<String, Object?> _object(Object? value) => value is Map<String, Object?>
    ? value
    : throw const FormatException('VALIDATION');
