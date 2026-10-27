import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/executor_jobs.dart';
import 'package:serverdeck_protocol/mcp/catalog.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../api/operational_auth.dart';
import '../remote/executor.dart';
import '../storage/state_store.dart';
import 'compiler.dart';
import 'job_commands.dart';
import 'job_session.dart';

const jobTools = {
  'serverdeck_apply',
  'serverdeck_jobs_list',
  'serverdeck_jobs_get',
  'serverdeck_jobs_events',
  'serverdeck_jobs_cancel',
  'serverdeck_jobs_reconcile',
};
const _terminal = {'succeeded', 'failed', 'cancelled'};
DateTime _now() => DateTime.fromMillisecondsSinceEpoch(
  DateTime.now().toUtc().millisecondsSinceEpoch,
  isUtc: true,
);
bool _same(Object? a, Object? b) =>
    StrictCodec().canonical(a).toString() ==
    StrictCodec().canonical(b).toString();

/// Concrete six-tool domain over the same native store and enrolled root service.
/// A durable driver is independent of the request's response interest, but never
/// independent of current native/session/grant/target/selected step authority.
final class TrustedJobService {
  TrustedJobService(this.executors);
  final RemoteExecutorService executors;
  StateStore get store => executors.connections.store;
  TrustedSessions get sessions => executors.connections.sessions;
  final _operations = <JobOperation>{};
  final _drivers = <String, _JobDriver>{};
  final _cursors = <String, _JobCursor>{};
  final _clock = Stopwatch()..start();
  bool _closed = false, _nativeFailure = false;
  Future<void>? _closing;

  /// Local-only generation recovery; never reconnect or restore step authority.
  Future<void> recover() => sessions.runAuthorityMutation(() async {
    final pending = store.trustedOperational.automation.jobs.values
        .where(
          (job) => !_terminal.contains(job.state) && job.state != 'unknown',
        )
        .toList();
    for (final job in pending) {
      final queued = job.state == 'queued';
      await store.publishTrustedJobProgress(
        jobId: job.id,
        expectedSequence: job.nextSequence,
        state: queued ? 'cancelled' : 'unknown',
        clock: _now,
        outcome: AutomationJobOutcome.fromJson({
          'effects': queued ? 'none' : 'uncertain',
          'checks': [],
          'safeCode': queued ? 'CANCELLED' : 'UNKNOWN_OUTCOME',
        }),
      );
    }
  });

  Future<T> _stable<T>(FutureOr<T> Function() read) async {
    final watch = Stopwatch()..start();
    while (true) {
      try {
        return await read();
      } on StateError catch (error) {
        if (error.message != 'STORAGE_BLOCKED' ||
            !store.hasPendingMcpAuthorityPublication)
          rethrow;
        final left = const Duration(seconds: 5) - watch.elapsed;
        if (left <= Duration.zero) throw StateError('TIMEOUT');
        await store.waitForMcpAuthority(deadline: left);
      }
    }
  }

  JobOperation startMcp(
    TrustedMcpContext context,
    String tool,
    Map<String, Object?> arguments,
  ) {
    if (_closed) throw StateError('NOT_READY');
    if (_nativeFailure) throw StateError('SERVICE_UNAVAILABLE');
    if (!context.belongsTo(sessions, executors.connections.authority))
      throw StateError('FORBIDDEN');
    if (!jobTools.contains(tool)) throw StateError('UNSUPPORTED');
    context.authorize(scope: _scope(tool));
    if (_operations.length >= 32) throw StateError('RESOURCE_LIMIT');
    final input = StrictCodec().decode(
      encodeMcpMessage(arguments, maxBytes: 256 * 1024),
      maxBytes: 256 * 1024,
    );
    validateMcpArguments(mcpTool(tool)!, input);
    final operation = JobOperation._(this, _JobActor.mcp(context), tool, input);
    _operations.add(operation);
    operation._run().ignore();
    return operation;
  }

  JobOperation startOwner(
    TrustedOwnerAutomationContext context,
    String tool,
    Map<String, Object?> arguments,
  ) {
    final method = switch (tool) {
      'serverdeck_apply' => 'jobs.apply',
      'serverdeck_jobs_list' => 'jobs.list',
      'serverdeck_jobs_get' => 'jobs.get',
      'serverdeck_jobs_events' => 'jobs.events',
      'serverdeck_jobs_cancel' => 'jobs.cancel',
      'serverdeck_jobs_reconcile' => 'jobs.reconcile',
      _ => throw StateError('UNSUPPORTED'),
    };
    if (!context.belongsTo(sessions) || context.method != method)
      throw StateError('FORBIDDEN');
    context.remaining;
    if (_closed) throw StateError('NOT_READY');
    if (_nativeFailure) throw StateError('SERVICE_UNAVAILABLE');
    if (_operations.length >= 32) throw StateError('RESOURCE_LIMIT');
    final input = StrictCodec().decode(
      encodeMcpMessage(arguments, maxBytes: 256 * 1024),
      maxBytes: 256 * 1024,
    );
    validateMcpArguments(mcpTool(tool)!, input);
    final operation = JobOperation._(
      this,
      _JobActor.owner(context),
      tool,
      input,
    );
    _operations.add(operation);
    operation._run().ignore();
    return operation;
  }

  static McpScope _scope(String tool) =>
      const {'serverdeck_apply', 'serverdeck_jobs_cancel'}.contains(tool)
      ? McpScope.apply
      : McpScope.read;

  Future<void> _proof(
    _JobActor context,
    McpScope scope,
    String? server,
    Duration budget,
    _NativeWork native,
  ) async {
    if (_closed) throw StateError('SERVICE_UNAVAILABLE');
    if (_nativeFailure) throw StateError('SERVICE_UNAVAILABLE');
    final watch = Stopwatch()..start();
    if (budget > const Duration(seconds: 5))
      budget = const Duration(seconds: 5);
    if (context.owner != null && store.hasPendingMcpAuthorityPublication) {
      await store.waitForMcpAuthority(deadline: budget);
      budget -= watch.elapsed;
      if (budget <= Duration.zero) throw StateError('TIMEOUT');
      watch.reset();
    }
    await context.authorizeWhenStable(
      scope: scope,
      serverId: server,
      deadline: budget,
    );
    final left = budget - watch.elapsed;
    if (left <= Duration.zero) throw StateError('TIMEOUT');
    await context.revalidate(
      deadline: left,
      observeNativeCompletion: native.observe,
    );
    context.authorize(scope: scope, serverId: server);
  }

  AutomationJobRecord _job(_JobActor context, String id, McpScope scope) {
    context.authorize(scope: scope);
    final graph = store.trustedOperational.automation,
        job = graph.jobs[requireUuid(id)];
    if (job == null ||
        context.grantId != null && job.grantId != context.grantId)
      throw StateError('FORBIDDEN');
    context.authorize(
      scope: scope,
      serverId: graph.plans[job.immutablePlanId]!.serverId,
    );
    return job;
  }

  AutomationPlanRecord _plan(_JobActor context, String id) {
    context.authorize(scope: McpScope.apply);
    final plan = store.trustedOperational.automation.plans[requireUuid(id)];
    if (plan == null ||
        context.grantId != null &&
            plan.toJson()['originGrantId'] != context.grantId)
      throw StateError('FORBIDDEN');
    context.authorize(scope: McpScope.apply, serverId: plan.serverId);
    return plan;
  }

  bool _drive(
    String jobId,
    _JobActor context,
    String mode, {
    RemoteExecutorOperation? opening,
    RemoteExecutorSession? session,
  }) {
    if (_drivers.containsKey(jobId)) return false;
    final driver = _JobDriver(this, context, jobId, mode, opening, session);
    _drivers[jobId] = driver;
    driver.run().ignore();
    return true;
  }

  Map<String, Object?> _list(_JobActor context, Map<String, Object?> input) {
    final limit = input['limit'] as int? ?? 50,
        server = input['serverId'] as String?;
    if (server != null)
      context.authorize(scope: McpScope.read, serverId: server);
    _cursors.removeWhere((_, row) => row.expires <= _clock.elapsed);
    final filter = jsonEncode({'serverId': server, 'limit': limit});
    final token = input['cursor'];
    _JobCursor? cursor;
    if (token != null) {
      cursor = _cursors[token];
      if (cursor == null ||
          cursor.session != context.sessionId ||
          cursor.grant != context.cursorGrant ||
          cursor.revision != context.cursorRevision ||
          cursor.filter != filter)
        throw StateError('CURSOR_EXPIRED');
    }
    final graph = store.trustedOperational.automation;
    final ids =
        cursor?.ids ??
        ([
          for (final job in graph.jobs.values)
            if ((context.grantId == null || job.grantId == context.grantId) &&
                context.allowsServer(
                  graph.plans[job.immutablePlanId]!.serverId,
                ) &&
                (server == null ||
                    graph.plans[job.immutablePlanId]!.serverId == server))
              job.id,
        ]..sort());
    final offset = cursor?.offset ?? 0, end = min(offset + limit, ids.length);
    final rows = [
      for (final id in ids.sublist(offset, end))
        {
          'job': _job(context, id, McpScope.read).toJson(),
          'serverId': graph.plans[graph.jobs[id]!.immutablePlanId]!.serverId,
        },
    ];
    String? next;
    if (end < ids.length) {
      if (_cursors.length >= 64) throw StateError('RESOURCE_LIMIT');
      for (var i = 0; i < 8; i++) {
        final value = base64Url
            .encode(List.generate(32, (_) => Random.secure().nextInt(256)))
            .replaceAll('=', '');
        if (_cursors.containsKey(value)) continue;
        next = value;
        _cursors[value] = _JobCursor(
          context.sessionId,
          context.cursorGrant,
          context.cursorRevision,
          filter,
          List.unmodifiable(ids),
          end,
          cursor?.expires ?? _clock.elapsed + const Duration(minutes: 5),
        );
        break;
      }
      if (next == null) throw StateError('RESOURCE_LIMIT');
    }
    return {'items': rows, if (next != null) 'nextCursor': next};
  }

  Map<String, Object?> _events(
    AutomationJobRecord job,
    Map<String, Object?> input,
  ) {
    final after = input['after'] as int? ?? 0,
        limit = input['limit'] as int? ?? 50;
    if (after >= job.nextSequence)
      return {
        'events': <Object?>[],
        'nextSequence': job.nextSequence,
        'dropped': 0,
        'hasMore': false,
      };
    final all =
        store.trustedOperational.automation.events.values
            .where((event) => event.jobId == job.id && event.sequence > after)
            .toList()
          ..sort((a, b) => a.sequence.compareTo(b.sequence));
    final rows = all.take(limit).toList(), more = all.length > rows.length;
    final next = more
        ? rows.last.sequence + 1
        : max(after + 1, job.nextSequence);
    return {
      'events': rows.map((row) => row.toJson()).toList(),
      'nextSequence': next,
      'dropped': max(0, next - 1 - after - rows.length),
      'hasMore': more,
    };
  }

  Future<void> _validatePlan(
    AutomationPlanRecord plan,
    RemoteExecutorSession session,
  ) async {
    _sessionMatches(plan, session, use: JobSessionUse.admission);
    if (plan.status != 'runnable' || !plan.isWithinLifetimeAt(_now()))
      throw StateError('PLAN_EXPIRED');
    final release = executors.release;
    if (release == null) throw StateError('EXECUTOR_UNAVAILABLE');
    release.revalidate();
    final doc = plan.toJson(), capsule = plan.preflight!;
    final facts = capsule.toJson();
    if (facts['runtimeVersion'] != release.descriptor.runtimeVersion ||
        facts['runtimeLockDigest'] != release.descriptor.lockDigest ||
        facts['compilerDigest'] != release.descriptor.compilerDigest)
      throw StateError('RUNTIME_INCOMPATIBLE');
    final graph = await _stable(() => store.trustedOperational.automation);
    final revision =
        graph.revisions['${plan.key.profileId}:${plan.key.revision}'];
    if (revision == null || revision.key != plan.key)
      throw StateError('PLAN_STALE');
    final compiled = compileAutomation(
      body: revision.body,
      parameters: doc['exactParams'] as Map<String, Object?>,
      baselineFingerprints: plan.baseObservations,
      qualifiedRecipes: {
        for (final recipe in capsule.recipes) recipe.digest: recipe,
      },
    ).toJson();
    if (!_same(compiled['effects'], doc['effects']) ||
        !_same(compiled['checks'], doc['checks']) ||
        !_same(compiled['desired'], doc['desired']))
      throw StateError('RUNTIME_INCOMPATIBLE');
    final cached = await session.request('preflight_get', {
      'operationId': capsule.operationId,
    });
    if (cached['operationId'] != capsule.operationId ||
        cached['state'] != 'succeeded')
      throw StateError('PLAN_STALE');
    final result = cached['result'];
    if (result is! Map<String, Object?>)
      throw StateError('RUNTIME_INCOMPATIBLE');
    requireFields(result, {
      'planFacts',
      'digest',
      'effects',
      'checks',
      'reasons',
      'observations',
    });
    if (result['digest'] != capsule.digest ||
        !_same(result['planFacts'], capsule.toJson()) ||
        !_same(result['effects'], compiled['effects']) ||
        !_same(result['checks'], compiled['checks']) ||
        !_same(result['reasons'], []))
      throw StateError('RUNTIME_INCOMPATIBLE');
    final observations = <ManagedResourceObservationRecord>[];
    for (final resource in plan.baseObservations.keys)
      observations.add(await session.observe(resource));
    try {
      await plan.validateCurrentObservations(observations, now: _now());
    } on FormatException {
      throw StateError('PLAN_STALE');
    }
  }

  void _sessionMatches(
    AutomationPlanRecord plan,
    RemoteExecutorSession session, {
    JobSessionUse use = JobSessionUse.effect,
  }) {
    // The actual session proves current owner-confirmed trust/enrollment and
    // rechecks its current target before each request. Stop/reconciliation use
    // the historical attempt on that same host; they cannot submit/authorize.
    // Requiring old counters here would make legitimate recovery impossible.
    validateJobSession(
      plan: plan,
      target: session.target,
      hostId: session.enrollment.hostId,
      registryDigest: session.enrollment.registryDigest,
      bootIdHash: session.hello['bootIdHash'],
      use: use,
    );
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    _cursors.clear();
    for (final operation in _operations.toList())
      operation.stop('SERVICE_UNAVAILABLE');
    for (final driver in _drivers.values.toList()) driver.stop();
    return _closing = () async {
      await Future.wait([
        for (final operation in _operations.toList()) operation.done,
      ]);
      // An already admitted mutation can transfer its driver during close.
      final remaining = _drivers.values.toList();
      for (final driver in remaining) driver.stop();
      await Future.wait([for (final driver in remaining) driver.done]);
      if (_nativeFailure) throw StateError('SERVICE_UNAVAILABLE');
    }();
  }
}

final class _NativeWork {
  _NativeWork(this.service);
  final TrustedJobService service;
  final work = <Future<void>>{};
  void observe(Future<void> actual) {
    final tracked = actual.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {
        service._nativeFailure = true;
      },
    );
    work.add(tracked);
    tracked.then<void>((_) => work.remove(tracked)).ignore();
  }

  Future<void> get done => Future.wait(work.toList());
}

final class JobOperation {
  JobOperation._(this.service, this.context, this.tool, this.input)
    : native = _NativeWork(service) {
    _result.future.ignore();
  }
  final TrustedJobService service;
  final _JobActor context;
  final String tool;
  final Map<String, Object?> input;
  final _NativeWork native;
  final _watch = Stopwatch()..start();
  final _result = Completer<Map<String, Object?>>(), _done = Completer<void>();
  RemoteExecutorOperation? _opening;
  bool _stopped = false, _mutating = false, _transferred = false;
  Future<Map<String, Object?>> get result => _result.future;
  Future<void> get done => _done.future;
  Duration get remaining {
    final left = const Duration(seconds: 30) - _watch.elapsed;
    if (left <= Duration.zero) throw StateError('TIMEOUT');
    return left;
  }

  void _check() {
    if (_stopped || service._closed) throw StateError('CANCELLED');
    remaining;
    context.authorize(scope: TrustedJobService._scope(tool));
  }

  Future<void> _proof([String? server]) async {
    _check();
    await service._proof(
      context,
      TrustedJobService._scope(tool),
      server,
      remaining,
      native,
    );
    _check();
  }

  void stop(String code) {
    if (_stopped) return;
    _stopped = true;
    if (!_result.isCompleted) _result.completeError(StateError(code));
    if (!_mutating && !_transferred) _opening?.close().ignore();
  }

  Future<void> cancelInterest() {
    stop('CANCELLED');
    return done;
  }

  Future<void> _run() async {
    final timer = Timer(const Duration(seconds: 30), () => stop('TIMEOUT'));
    try {
      await _proof();
      Map<String, Object?> output;
      if (tool == 'serverdeck_jobs_list') {
        output = await service._stable(() => service._list(context, input));
      } else if (tool == 'serverdeck_jobs_get' ||
          tool == 'serverdeck_jobs_events') {
        output = await service._stable(() {
          final job = service._job(
            context,
            input['jobId'] as String,
            McpScope.read,
          );
          return tool == 'serverdeck_jobs_events'
              ? service._events(job, input)
              : {
                  'job': job.toJson(),
                  'plan': service
                      .store
                      .trustedOperational
                      .automation
                      .plans[job.immutablePlanId]!
                      .toJson(),
                };
        });
      } else {
        final operation = switch (tool) {
          'serverdeck_apply' => 'job.apply',
          'serverdeck_jobs_cancel' => 'job.cancel',
          _ => 'job.reconcile',
        };
        final command = JobMutationCommand.parse(operation, input);
        final plan = await service._stable(
          () => tool == 'serverdeck_apply'
              ? service._plan(context, input['planId'] as String)
              : service.store.trustedOperational.automation.plans[service
                    ._job(
                      context,
                      input['jobId'] as String,
                      TrustedJobService._scope(tool),
                    )
                    .immutablePlanId]!,
        );
        await _proof(plan.serverId);
        final replay = await service.sessions.runAuthorityMutation(
          () async {
            await _proof(plan.serverId);
            return service.store.replayTrustedJob(
              command,
              originGrantId: context.grantId,
              expectedGrantRevision: context.revision,
              at: _now(),
            );
          },
          deadline: const Duration(seconds: 5),
          observeNativeCompletion: native.observe,
        );
        if (replay != null) {
          output = replay;
          final old = await service._stable(
            () => service
                .store
                .trustedOperational
                .automation
                .jobs[replay['jobId']]!,
          );
          if (operation == 'job.cancel' && !_terminal.contains(old.state))
            service._drive(old.id, context, 'cancel');
          if (operation == 'job.reconcile' && old.state == 'reconciling')
            service._drive(old.id, context, 'reconcile');
        } else {
          if (await service._stable(
                () =>
                    service.store.trustedOperational.automation.receipts.length,
              ) >=
              10000)
            throw StateError('RESOURCE_LIMIT');
          RemoteExecutorSession? session;
          final prior = await service._stable(
            () => service.store.trustedOperational.automation.jobs.values
                .where((job) => job.immutablePlanId == plan.id)
                .firstOrNull,
          );
          if (tool == 'serverdeck_apply' && prior == null) {
            if (plan.status != 'runnable') throw StateError('PLAN_STALE');
            if (!plan.isWithinLifetimeAt(_now()))
              throw StateError('PLAN_EXPIRED');
            if (service._drivers.length >= 48)
              throw StateError('RESOURCE_LIMIT');
            final opening = _opening = context.open(
              service.executors,
              plan.serverId,
              scope: McpScope.apply,
            );
            session = await opening.result;
            try {
              await service._validatePlan(plan, session);
            } on FormatException {
              throw StateError('RUNTIME_INCOMPATIBLE');
            } on StateError catch (error) {
              if (error.message == 'NOT_FOUND') throw StateError('PLAN_STALE');
              rethrow;
            }
            await _proof(plan.serverId);
          }
          _mutating = true;
          output = await service.sessions.runAuthorityMutation(
            () async {
              await _proof(plan.serverId);
              return service.store.mutateTrustedJob(
                command,
                originGrantId: context.grantId,
                expectedGrantRevision: context.revision,
                clock: _now,
                verifiedPlanDigest: session == null
                    ? null
                    : plan.toJson()['digest'] as String,
              );
            },
            deadline: const Duration(seconds: 5),
            observeNativeCompletion: native.observe,
          );
          // The accepted mutation owns its continuation even if caller interest
          // timed out while its native transaction was physically completing.
          final jobId = output['jobId'] as String;
          final job = await service._stable(
            () => service.store.trustedOperational.automation.jobs[jobId]!,
          );
          if (session != null &&
              job.requestId == command.requestId &&
              job.state == 'queued') {
            _transferred = service._drive(
              jobId,
              context,
              'apply',
              opening: _opening,
              session: session,
            );
          } else if (operation == 'job.cancel' &&
              !_terminal.contains(job.state)) {
            service._drive(jobId, context, 'cancel');
          } else if (operation == 'job.reconcile' &&
              job.state == 'reconciling') {
            service._drive(jobId, context, 'reconcile');
          }
        }
      }
      await _proof();
      if (!_result.isCompleted) _result.complete(output);
    } catch (error) {
      if (!_result.isCompleted) _result.completeError(error);
    } finally {
      timer.cancel();
      try {
        if (!_transferred) await _opening?.close();
      } catch (_) {
        service._nativeFailure = true;
      }
      await native.done;
      await context.owner?.settled;
      service._operations.remove(this);
      _done.complete();
    }
  }
}

final class _JobDriver {
  _JobDriver(
    this.service,
    this.context,
    this.jobId,
    this.mode,
    this.opening,
    this.session,
  ) : native = _NativeWork(service);
  final TrustedJobService service;
  final _JobActor context;
  final String jobId, mode;
  late AutomationJobRecord identity;
  late AutomationPlanRecord _capturedPlan;
  RemoteExecutorOperation? opening;
  RemoteExecutorSession? session;
  final _NativeWork native;
  final _done = Completer<void>(), _stop = Completer<void>();
  bool stopped = false, submitted = false, cancelSent = false;
  Future<void> get done => _done.future;
  void stop() {
    stopped = true;
    if (!_stop.isCompleted) _stop.complete();
    opening?.close().ignore();
  }

  AutomationJobRecord get job =>
      service.store.trustedOperational.automation.jobs[jobId]!;
  AutomationPlanRecord get plan => _capturedPlan;
  Future<void> proof() async {
    if (stopped) throw StateError('CANCELLED');
    final target = await service._stable(() => plan);
    await service._proof(
      context,
      mode == 'reconcile' ? McpScope.read : McpScope.apply,
      target.serverId,
      const Duration(seconds: 5),
      native,
    );
    if (stopped) throw StateError('CANCELLED');
  }

  Future<AutomationJobRecord> publish(
    String state,
    AutomationJobOutcome? outcome, {
    String? step,
  }) async {
    while (true) {
      final previous = await service._stable(() => job);
      if (_terminal.contains(previous.state)) return previous;
      if (previous.state == 'unknown' && state == 'unknown') return previous;
      final nextState = previous.cancelRequested && state == 'running'
          ? 'cancel-requested'
          : state;
      try {
        return await service._stable(
          () => service.store.publishTrustedJobProgress(
            jobId: jobId,
            expectedSequence: previous.nextSequence,
            state: nextState,
            outcome: outcome,
            clock: _now,
            progressStepId: step,
          ),
        );
      } on StateError catch (error) {
        if (error.message != 'REVISION_CONFLICT') rethrow;
      }
    }
  }

  Future<void> gate(Future<void> Function() effect) =>
      service.sessions.runAuthorityMutation(
        () async {
          await proof();
          await effect();
        },
        deadline: const Duration(seconds: 5),
        observeNativeCompletion: native.observe,
      );

  Future<void> run() async {
    final timer = Timer(
      mode == 'reconcile'
          ? const Duration(seconds: 30)
          : const Duration(hours: 2),
      stop,
    );
    try {
      if (service._closed) throw StateError('SERVICE_UNAVAILABLE');
      await service._stable(() {
        identity = job;
        _capturedPlan = service
            .store
            .trustedOperational
            .automation
            .plans[identity.immutablePlanId]!;
      });
      await proof();
      if (_terminal.contains((await service._stable(() => job)).state)) return;
      if (session == null) {
        opening = context.open(
          service.executors,
          plan.serverId,
          scope: mode == 'reconcile' ? McpScope.read : McpScope.apply,
        );
        session = await opening!.result;
      }
      service._sessionMatches(
        plan,
        session!,
        use: mode == 'apply' ? JobSessionUse.effect : JobSessionUse.control,
      );
      if (mode == 'apply') {
        await gate(() async {
          await service._stable(
            () => service.store.validateTrustedJobStep(
              jobId,
              originGrantId: context.grantId,
              expectedGrantRevision: context.revision,
              at: _now(),
            ),
          );
          if ((await service._stable(() => job)).state != 'queued')
            throw StateError('REVISION_CONFLICT');
          await publish('running', null);
        });
        await gate(() async {
          await service._stable(
            () => service.store.validateTrustedJobStep(
              jobId,
              originGrantId: context.grantId,
              expectedGrantRevision: context.revision,
              at: _now(),
            ),
          );
          final revision = await service._stable(
            () => service
                .store
                .trustedOperational
                .automation
                .revisions['${plan.key.profileId}:${plan.key.revision}']!,
          );
          final doc = plan.toJson();
          submitted = true;
          final response = await session!.request('submit', {
            'jobId': jobId,
            'attemptId': identity.hostAttemptId,
            'planDigest': identity.planDigest,
            'profileId': plan.key.profileId,
            'profileRevision': plan.key.revision,
            'profileBody': revision.body.toJson(),
            'profileDigest': plan.key.bodyDigest,
            'parameters': doc['exactParams'],
            'preflightDigest': doc['preflightDigest'],
            'expectedHostId': plan.hostId,
            'controllerId': plan.workspaceId,
            'workspaceId': plan.workspaceId,
          });
          requireFields(response, {'attemptId', 'state', 'sequence'});
          if (response['attemptId'] != identity.hostAttemptId ||
              response['sequence'] is! int ||
              !const {'queued', 'succeeded'}.contains(response['state']))
            throw StateError('RUNTIME_INCOMPATIBLE');
        });
      } else if (mode == 'reconcile') {
        // This root method only observes/journals outcomes, never runs Ansible.
        final value = await session!.request('reconcile', {
          'attemptId': identity.hostAttemptId,
        });
        requireFields(value, {
          'attemptId',
          'state',
          'childrenStopped',
          'sequence',
        });
        if (value['attemptId'] != identity.hostAttemptId ||
            value['childrenStopped'] is! bool ||
            value['sequence'] is! int)
          throw StateError('RUNTIME_INCOMPATIBLE');
      }
      var previousSequence = 0, previousEpoch = 0, previousStep = 0;
      while (true) {
        await proof();
        if ((await service._stable(() => job)).cancelRequested &&
            mode != 'reconcile' &&
            !cancelSent) {
          await gate(() async {
            final value = await session!.request('cancel', {
              'attemptId': identity.hostAttemptId,
              'requestId': identity.id,
            });
            requireFields(value, {'attemptId', 'state'});
            if (value['attemptId'] != identity.hostAttemptId)
              throw StateError('RUNTIME_INCOMPATIBLE');
            cancelSent = true;
          });
        }
        final raw = await session!.request('status', {
          'attemptId': identity.hostAttemptId,
          'afterSequence': previousSequence,
          'limit': 100,
        });
        final status = ExecutorJobStatus.capture(
          raw,
          plan: plan,
          attemptId: identity.hostAttemptId,
        );
        if (status.sequence < previousSequence ||
            status.authorizationEpoch < previousEpoch ||
            status.stepIndex < previousStep)
          throw StateError('RUNTIME_INCOMPATIBLE');
        previousSequence = status.sequence;
        previousEpoch = status.authorizationEpoch;
        previousStep = status.stepIndex;
        await proof();
        if (status.terminal) {
          await publish(status.localState, status.outcome(executorDomainCode));
          return;
        }
        if (mode == 'reconcile') {
          // A still running child has no proven terminal result. Recovery does
          // not wait indefinitely or authorize the next waiting root effect.
          await publish(
            'unknown',
            AutomationJobOutcome.fromJson({
              'effects': 'uncertain',
              'checks': [],
              'safeCode': 'UNKNOWN_OUTCOME',
            }),
          );
          return;
        }
        final challenge = status.challenge;
        if (challenge != null &&
            !(await service._stable(() => job)).cancelRequested &&
            mode == 'apply') {
          await gate(() async {
            await service._stable(
              () => service.store.validateTrustedJobStep(
                jobId,
                originGrantId: context.grantId,
                expectedGrantRevision: context.revision,
                at: _now(),
              ),
            );
            final response = await session!.request('authorize_step', {
              'attemptId': identity.hostAttemptId,
              ...challenge,
              'authorizationEpoch': status.authorizationEpoch + 1,
            });
            requireFields(response, {'attemptId', 'state'});
            if (response['attemptId'] != identity.hostAttemptId ||
                response['state'] != 'running')
              throw StateError('RUNTIME_INCOMPATIBLE');
            await publish('running', null, step: challenge['stepId'] as String);
          });
        }
        await Future.any([
          Future<void>.delayed(const Duration(seconds: 1)),
          _stop.future,
        ]);
      }
    } catch (_) {
      try {
        final current = await service._stable(() => job);
        if (!_terminal.contains(current.state)) {
          if (mode == 'apply' &&
              !submitted &&
              const {
                'queued',
                'running',
                'cancel-requested',
              }.contains(current.state)) {
            await publish(
              'cancelled',
              AutomationJobOutcome.fromJson({
                'effects': 'none',
                'checks': [],
                'safeCode': 'CANCELLED',
              }),
            );
          } else {
            if (current.state == 'queued') await publish('running', null);
            await publish(
              'unknown',
              AutomationJobOutcome.fromJson({
                'effects': 'uncertain',
                'checks': [],
                'safeCode': 'UNKNOWN_OUTCOME',
              }),
            );
          }
        }
      } catch (_) {
        service._nativeFailure = true;
      }
    } finally {
      timer.cancel();
      try {
        await opening?.close();
      } catch (_) {
        service._nativeFailure = true;
      }
      await native.done;
      await context.owner?.settled;
      if (identical(service._drivers[jobId], this))
        service._drivers.remove(jobId);
      _done.complete();
    }
  }
}

final class _JobCursor {
  const _JobCursor(
    this.session,
    this.grant,
    this.revision,
    this.filter,
    this.ids,
    this.offset,
    this.expires,
  );
  final String session, grant, filter;
  final int revision, offset;
  final List<String> ids;
  final Duration expires;
}

/// Trusted native actor union, never created from a role/grant field in JSON.
final class _JobActor {
  const _JobActor.mcp(TrustedMcpContext value) : mcp = value, owner = null;
  const _JobActor.owner(TrustedOwnerAutomationContext value)
    : owner = value,
      mcp = null;
  final TrustedMcpContext? mcp;
  final TrustedOwnerAutomationContext? owner;
  String? get grantId => mcp?.grantId;
  int? get revision => mcp?.revision;
  String get cursorGrant => grantId ?? 'owner';
  int get cursorRevision => revision ?? 0;
  String get sessionId => mcp?.sessionId ?? owner!.sessionId;
  bool allowsServer(String server) => mcp?.policy.allowsServer(server) ?? true;
  void authorize({McpScope? scope, String? serverId}) {
    owner?.remaining;
    mcp?.authorize(scope: scope, serverId: serverId);
  }

  Future<void> authorizeWhenStable({
    McpScope? scope,
    String? serverId,
    required Duration deadline,
  }) {
    if (mcp != null)
      return mcp!.authorizeWhenStable(
        scope: scope,
        serverId: serverId,
        deadline: deadline,
      );
    authorize(scope: scope, serverId: serverId);
    return Future.value();
  }

  Future<void> revalidate({
    required Duration deadline,
    void Function(Future<void>)? observeNativeCompletion,
  }) async {
    if (mcp != null) {
      await mcp!.revalidate(
        deadline: deadline,
        observeNativeCompletion: observeNativeCompletion,
      );
    } else {
      try {
        await owner!.revalidate(deadline: deadline);
      } on TimeoutException {
        throw StateError('TIMEOUT');
      }
    }
  }

  RemoteExecutorOperation open(
    RemoteExecutorService executors,
    String server, {
    required McpScope scope,
  }) => mcp != null
      ? executors.startMcp(mcp!, server, scope: scope)
      : executors.startAutomationOwner(owner!, server, scope: scope);
}
