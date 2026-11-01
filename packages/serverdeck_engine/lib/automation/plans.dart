import 'dart:async';
import 'dart:math';

import 'package:cryptography/dart.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/mcp/catalog.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../hosting/sessions.dart';
import '../remote/connections.dart';
import '../remote/direct_ssh.dart';
import '../remote/direct_ssh_observations.dart';
import '../remote/direct_ssh_packages.dart';

import 'package:serverdeck_protocol/direct_ssh_runtime.dart';

import 'package:serverdeck_engine/storage/state_store.dart';

import 'package:serverdeck_engine/automation/compiler.dart';

import 'package:serverdeck_engine/automation/plan_commands.dart';

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
String _id() {
  final random = Random.secure(), bytes = List<int>.filled(16, 0);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = random.nextInt(256);
  }
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return hex.substring(0, 8) +
      '-' +
      hex.substring(8, 12) +
      '-' +
      hex.substring(12, 16) +
      '-' +
      hex.substring(16, 20) +
      '-' +
      hex.substring(20);
}

/// Actual captured preflight facts only. Cache presence is not authorization,
/// current observations, remote ownership, or permission to dispatch a job.
final class DirectPlanPreflight {
  DirectPlanPreflight._(
    this.target,
    this.identity,
    this.packages,
    List<ManagedResourceObservationRecord> observations,
    this.capsuleDigest,
    this.expires,
  ) : observations = List.unmodifiable(observations);
  final DirectObservationTarget target;
  final DirectSshIdentity identity;
  final DirectPackageSnapshot packages;
  final List<ManagedResourceObservationRecord> observations;
  final String capsuleDigest;
  final Duration expires;
}

/// Local compiler/preflight over the existing store/native actors/SSH registry.
/// Neither a parsed plan nor cached facts authorize execution.
final class TrustedPlanService {
  TrustedPlanService(this.connections) {
    _retired = connections.onRetired((server) {
      _epochs[server] = (_epochs[server] ?? 0) + 1;
      _cache.removeWhere((_, value) => value.target.serverId == server);
    });
  }
  final TrustedConnectionService connections;
  StateStore get store => connections.store;
  final _clock = Stopwatch()..start();
  final _cache = <String, DirectPlanPreflight>{};
  final _reservations = <PlanOperation>{};
  final _epochs = <String, int>{};
  late final void Function() _retired;
  void _sweep() =>
      _cache.removeWhere((_, value) => _clock.elapsed >= value.expires);
  void _reserve(PlanOperation work) {
    _sweep();
    if (_cache.length + _reservations.length >= 16 ||
        _cache.values.fold<int>(
                  0,
                  (sum, value) => sum + value.packages.byteLength + 256 * 1024,
                ) +
                (_reservations.length + 1) * 8 * 1024 * 1024 >
            64 * 1024 * 1024) {
      throw StateError('RESOURCE_LIMIT');
    }
    _reservations.add(work);
  }

  DirectPlanPreflight preflightFor(AutomationPlanRecord plan) {
    if (_closed || _nativeFailure) throw StateError('SERVICE_UNAVAILABLE');
    _sweep();
    final facts = _cache[plan.id];
    final snapshot = store.snapshot;
    if (facts == null ||
        snapshot.automation.plans[plan.id]?.toJson()['digest'] !=
            plan.toJson()['digest'] ||
        plan.preflight?.isDirectSsh != true ||
        facts.capsuleDigest != plan.preflight!.digest ||
        !plan.isWithinLifetimeAt(_now()) ||
        !facts.target.matches(snapshot.foundation.foundation))
      throw StateError('PLAN_STALE');
    return facts;
  }

  final _operations = <PlanOperation>{};
  bool _closed = false, _nativeFailure = false;
  Future<void>? _closing;

  PlanOperation startOwner(
    TrustedOwnerAutomationContext context,
    String tool,
    Map<String, Object?> arguments,
  ) {
    if (!context.belongsTo(connections.sessions) ||
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
    if (!context.belongsTo(connections.sessions, connections.authority))
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
    _retired();
    _cache.clear();
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
  final _directs = <ConnectionDirectWork>{};
  DirectObservationTarget? _target;
  int? _epoch;
  DirectPlanPreflight? _facts;
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
    final target = _target;
    if (target != null &&
        (!target.matches(service.store.snapshot.foundation.foundation) ||
            _epoch != (service._epochs[target.serverId] ?? 0)))
      throw StateError('PLAN_STALE');
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
    for (final direct in _directs.toList()) direct.cancelInterest().ignore();
  }

  Future<void> cancelInterest() {
    stop('CANCELLED');
    return done;
  }

  Map<String, Object?> _get(String id) {
    final plan = service.store.snapshot.automation.plans[requireUuid(id)];
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
        final replay = await service.connections.sessions.runAuthorityMutation(
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
          final receipt = await service.connections.sessions
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
          if (_facts case final facts?) service._cache[plan.id] = facts;
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
        await Future.wait([
          for (final direct in _directs.toList()) direct.cancelInterest(),
        ]);
      } catch (_) {
        service._nativeFailure = true;
      }
      service._reservations.remove(this);
      await owner?.settled;
      await Future.wait(_native.toList());
      service._operations.remove(this);
      _done.complete();
    }
  }

  Future<DirectSshOutput> _read(DirectSshCommand command) async {
    final target = _target!;
    void current() => _check(target.serverId);
    current();
    final work = owner != null
        ? service.connections.executeDirectAutomationOwner(
            owner!,
            target.serverId,
            command,
            beforeDispatch: current,
          )
        : service.connections.executeDirectMcp(
            context!,
            target.serverId,
            command,
            beforeDispatch: current,
          );
    _directs.add(work);
    try {
      final value = await work.result;
      await work.done;
      current();
      return value.output;
    } finally {
      work.done.then<void>((_) => _directs.remove(work)).ignore();
    }
  }

  Future<AutomationPlanRecord> _create(PlanCreateCommand command) async {
    _check(command.serverId);
    final snapshot = service.store.snapshot;
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
                'config_file' => 1,
                _ => 1,
              },
        ) >
        32;
    AutomationPreflightCapsule? capsule;
    Map<String, Object?>? program;
    String? blocked;
    String? remoteBlockedField;
    try {
      if (snapshot.automation.jobs.values.any(
        (job) =>
            !const {'succeeded', 'failed', 'cancelled'}.contains(job.state) &&
            snapshot
                    .automation
                    .plans[job.immutablePlanId]!
                    .preflight
                    ?.isDirectSsh !=
                true,
      )) {
        remoteBlockedField = 'runtime';
        throw StateError('UNKNOWN_OUTCOME');
      }
      if (stepLimitExceeded) throw StateError('RESOURCE_LIMIT');
      _target = DirectObservationTarget.capture(foundation, server.id);
      _epoch = service._epochs[server.id] ?? 0;
      // DB writes require durable direct provenance; existing root-owned files
      // and public observations cannot adopt a database. Catalog/qualification
      // collection is integrated separately; no remote preflight fallback.
      if (desired.any(
        (row) =>
            row['kind'] == 'install_recipe' ||
            row['resourceId'] != 'system.motd',
      )) {
        remoteBlockedField =
            desired.any((row) => row['kind'] == 'install_recipe')
            ? 'recipe'
            : 'qualification';
        throw DirectSshFailure('QUALIFICATION_REQUIRED');
      }
      remoteBlockedField = 'runtime';
      service._reserve(this);
      final started = service._clock.elapsed;
      final identity = DirectSshIdentity.capture(
        (await _read(DirectSshCommand.inspect()))
            .textRows(DirectSshIdentity.fields),
      );
      remoteBlockedField = 'packages';
      final packages = DirectPackageSnapshot.capture(
        await _read(DirectSshCommand.packages()),
      );
      remoteBlockedField = 'observation';
      final observations = <ManagedResourceObservationRecord>[];
      final observed = <String, String>{};
      for (final resource
          in desired.map((row) => row['resourceId'] as String).toSet()) {
        final at = _now();
        final observation = _target!.parse(
          resource,
          identity,
          await _read(DirectSshCommand.observation(resource)),
          at,
        );
        if (!observation.isFreshAt(_now()))
          throw StateError(
            observation.status == 'known' ? 'PLAN_STALE' : 'UNSUPPORTED',
          );
        observations.add(observation);
        observed[resource] = await observation.fingerprint();
        _check(server.id);
      }
      remoteBlockedField = 'packages';
      final after = DirectPackageSnapshot.capture(
        await _read(DirectSshCommand.packages()),
      );
      if (after.digest != packages.digest) throw StateError('PLAN_STALE');
      final finalIdentity = DirectSshIdentity.capture(
        (await _read(DirectSshCommand.inspect()))
            .textRows(DirectSshIdentity.fields),
      );
      if (finalIdentity.hostId != identity.hostId ||
          finalIdentity.bootIdHash != identity.bootIdHash ||
          finalIdentity.uptimeMs < identity.uptimeMs)
        throw StateError('PLAN_STALE');
      remoteBlockedField = 'observation';
      if (observations.any((row) => !row.isFreshAt(_now())))
        throw StateError('PLAN_STALE');
      final compiled = compileAutomation(
        body: revision.body,
        parameters: params,
        baselineFingerprints: observed,
        qualifiedRecipes: {},
        directSsh: true,
      ).toJson();
      final parsed = await AutomationPreflightCapsule.fromJson({
        'format': 2,
        'operationId': _id(),
        'hostId': identity.hostId,
        'environment': DirectSshRuntime.environment,
        'profileDigest': revision.key.bodyDigest,
        'inputDigest': _hash(params),
        'runtimeVersion': DirectSshRuntime.version,
        'runtimeLockDigest': DirectSshRuntime.prerequisiteDigest,
        'compilerDigest': DirectSshRuntime.compilerDigest,
        'registryDigest': DirectSshRuntime.registryDigest,
        'bootIdHash': identity.bootIdHash,
        'packageSnapshotDigest': packages.digest,
        'expectedPackageSnapshotDigest': packages.digest,
        'netbirdSnapshotDigest': packages.netbirdDigest,
        'aptIndexDigests': <String>[],
        'recipes': <Object?>[],
        'baseObservations': [
          for (final entry in observed.entries)
            {'resourceId': entry.key, 'fingerprint': entry.value},
        ],
      });
      _check(server.id);
      _facts = DirectPlanPreflight._(
        _target!,
        identity,
        packages,
        observations,
        parsed.digest,
        started + const Duration(minutes: 5),
      );
      capsule = parsed;
      program = compiled;
    } catch (error) {
      await _proof(command.serverId);
      final code = error is DirectSshFailure
          ? switch (error.code) {
              'QUALIFICATION_REQUIRED' ||
              'PREREQUISITE_UNAVAILABLE' => 'RUNTIME_INCOMPATIBLE',
              'RESOURCE_LIMIT' ||
              'TIMEOUT' ||
              'TRUST_CHANGED' ||
              'PLAN_STALE' ||
              'FORBIDDEN' => error.code,
              _ => 'UNSUPPORTED',
            }
          : error is StateError
          ? error.message
          : error is FormatException
          ? 'RUNTIME_INCOMPATIBLE'
          : 'UNSUPPORTED';
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
        'UNKNOWN_OUTCOME' => code,
        _ => throw error,
      };
      capsule = null;
      program = null;
      _facts = null;
    }
    _check(command.serverId);
    final created = _now();
    final document = <String, Object?>{
      'workspaceId': foundation.workspaceId,
      'id': _id(),
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
