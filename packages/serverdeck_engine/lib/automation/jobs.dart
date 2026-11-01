import 'job_progress.dart';
import 'job_controls.dart';
import 'job_observations.dart';
import '../platform/ports.dart' show EngineClock, SystemEngineClock;

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

import '../hosting/sessions.dart';
import '../remote/executor.dart';
import '../remote/connections.dart';
import '../remote/direct_ssh.dart';
import '../remote/direct_ssh_observations.dart';
import '../remote/direct_ssh_packages.dart';
import 'plans.dart';

import 'package:serverdeck_engine/storage/state_store.dart';

import 'package:serverdeck_engine/automation/job_commands.dart';

import 'package:serverdeck_engine/automation/job_session.dart';

part 'direct_job_driver.dart';

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
  TrustedJobService(this.executors, {required this.plans, EngineClock? clock}) {
    _controlClock = clock ?? SystemEngineClock();
    _controls = JobControlContinuations<_ControlIntent>(
      clock: _controlClock,
      wake: _wakeControls,
    );
    _observations = LocalJobObservations(
      generation: sessions.generation,
      workspaceId: store.snapshot.foundation.foundation.workspaceId,
      clock: _controlClock,
    );
    _detachObserver = executors.connections.onRetired((server) {
      _observations.detachServer(server);
      _retireControls(server);
    });
    _invalidateObserver = executors.onEnrollmentChanged((server) {
      _observations.invalidateServer(server);
      _retireControls(server);
    });
    _detachSessionObserver = sessions.onSessionDetached((id) {
      for (final driver in _drivers.values.toList()) {
        if (driver.context.sessionId == id) driver.stop();
      }
    });
  }
  late final LocalJobObservations _observations;
  late final EngineClock _controlClock;
  late final JobControlContinuations<_ControlIntent> _controls;
  Future<void>? _controlPumping;
  bool _controlWake = false;

  void _retireControls(String server) {
    _controls.retireServer(server);
    for (final ticket in _controls.pending) {
      if (ticket.value.server == server) ticket.value.retired = true;
    }
    for (final driver in _drivers.values) {
      if (driver.control?.value.server == server) {
        driver.control!.value.retired = true;
        driver.stop();
      }
    }
    _wakeControls();
  }

  void _pruneControls() => _controls.prune({
    for (final job in store.snapshot.automation.jobs.values)
      if (!_terminal.contains(job.state)) job.id,
  });
  bool _controlCurrent(JobControlTicket<_ControlIntent> ticket) {
    if (!_controls.current(ticket) ||
        ticket.value.retired ||
        _nativeFailure ||
        _closed ||
        _paused)
      return false;
    final intent = ticket.value;
    if (!_same(intent.target, _currentObservationTarget(intent.server)))
      return false;
    try {
      final job = _job(
        intent.actor,
        ticket.jobId,
        ticket.kind == JobControlKind.cancel ? McpScope.apply : McpScope.read,
      );
      return job.hostAttemptId == ticket.attemptId &&
          !_terminal.contains(job.state);
    } catch (_) {
      return false;
    }
  }

  Future<void> _uncertainControl(String id) async {
    while (true) {
      final job = await _stable(() => store.snapshot.automation.jobs[id]);
      if (job == null ||
          job.state != 'reconciling' ||
          const {'cancel', 'reconcile'}.contains(_drivers[id]?.mode))
        return;
      try {
        await _stable(
          () => store.publishTrustedJobProgress(
            jobId: id,
            expectedSequence: job.nextSequence,
            state: 'unknown',
            clock: _now,
            outcome: AutomationJobOutcome.fromJson({
              'effects': 'uncertain',
              'checks': [],
              'safeCode': 'UNKNOWN_OUTCOME',
            }),
          ),
        );
        return;
      } on StateError catch (error) {
        if (error.message != 'REVISION_CONFLICT') rethrow;
      }
    }
  }

  void _wakeControls() {
    if (_controls.sealed ||
        _closed ||
        _paused ||
        _nativeFailure ||
        _controls.entryCount == 0)
      return;
    _controlWake = true;
    if (_controlPumping != null) return;
    final done = Completer<void>();
    _controlPumping = done.future;
    done.future.ignore();
    () async {
      try {
        while (_controlWake && !_controls.sealed && !_nativeFailure) {
          _controlWake = false;
          final lease = _controls.reserve(
            valid: () => !_controls.sealed,
            pump: true,
          );
          final native = _NativeWork(this);
          final actors = <_JobActor>{};
          final ready = <_JobDriver>[];
          try {
            await lease.entered;
            await _stable(_pruneControls);
            _controls.expire(lease);
            for (final id in _controls.jobs) {
              if (_controls.sealed) break;
              if (_drivers.containsKey(id)) {
                if (!_controls.hasReconcile(id)) await _uncertainControl(id);
                continue;
              }
              final ticket = _controls.take(lease, id);
              if (ticket == null) {
                await _uncertainControl(id);
                continue;
              }
              final intent = ticket.value;
              actors.add(intent.actor);
              try {
                if (!_controlCurrent(ticket)) throw StateError('CANCELLED');
                await sessions.runAuthorityMutation(
                  () async {
                    await _proof(
                      intent.actor,
                      ticket.kind == JobControlKind.cancel
                          ? McpScope.apply
                          : McpScope.read,
                      intent.server,
                      ticket.deadline - _controlClock.elapsed,
                      native,
                    );
                    if (!_controlCurrent(ticket)) throw StateError('CANCELLED');
                    final replay = await store.replayTrustedJob(
                      intent.command,
                      originGrantId: intent.actor.grantId,
                      expectedGrantRevision: intent.actor.revision,
                      at: _now(),
                    );
                    if (replay?['jobId'] != id) throw StateError('FORBIDDEN');
                    if (ticket.kind == JobControlKind.reconcile) {
                      while (true) {
                        if (!_controlCurrent(ticket))
                          throw StateError('CANCELLED');
                        final job = await _stable(
                          () => store.snapshot.automation.jobs[id]!,
                        );
                        if (job.state != 'unknown') break;
                        try {
                          await store.publishTrustedJobProgress(
                            jobId: id,
                            expectedSequence: job.nextSequence,
                            state: 'reconciling',
                            outcome: null,
                            clock: _now,
                          );
                          break;
                        } on StateError catch (error) {
                          if (error.message != 'REVISION_CONFLICT') rethrow;
                        }
                      }
                    }
                  },
                  deadline: _controlBudget(ticket),
                  observeNativeCompletion: native.observe,
                );
                await native.done;
                await intent.actor.owner?.settled;
                if (!_controlCurrent(ticket)) throw StateError('CANCELLED');
                if (_drive(
                  id,
                  intent.actor,
                  ticket.kind.name,
                  control: ticket,
                  start: false,
                ))
                  ready.add(_drivers[id]!);
              } catch (_) {
                await native.done;
                await intent.actor.owner?.settled;
                if (!_controls.hasReconcile(id)) await _uncertainControl(id);
                if (_controls.pending.any((pending) => pending.jobId == id))
                  _controlWake = true;
              }
            }
          } finally {
            await native.done;
            for (final actor in actors) await actor.owner?.settled;
            lease.release();
            for (final driver in ready) driver.run().ignore();
          }
        }
        done.complete();
      } catch (_) {
        if (_controls.sealed) {
          done.complete();
        } else {
          _nativeFailure = true;
          done.completeError(StateError('SERVICE_UNAVAILABLE'));
        }
      } finally {
        _controlPumping = null;
        if (_controlWake && !_controls.sealed && !_nativeFailure)
          _wakeControls();
      }
    }().ignore();
  }

  Duration _controlBudget(JobControlTicket<_ControlIntent> ticket) {
    final left = ticket.deadline - _controlClock.elapsed;
    if (left <= Duration.zero) throw StateError('TIMEOUT');
    return left < const Duration(seconds: 5)
        ? left
        : const Duration(seconds: 5);
  }

  Future<void> _registerControl(
    JobControlAdmission lease,
    JobMutationCommand command,
    _JobActor actor,
    AutomationJobRecord job,
    Duration deadline,
    Map<String, Object?>? target,
  ) async {
    if (_terminal.contains(job.state)) {
      _pruneControls();
      return;
    }
    final plan = store.snapshot.automation.plans[job.immutablePlanId]!;
    final accepted = _controls.register(
      lease,
      jobId: job.id,
      attemptId: job.hostAttemptId,
      kind: command.operation == 'job.cancel'
          ? JobControlKind.cancel
          : JobControlKind.reconcile,
      value: _ControlIntent(actor, command, plan.serverId, target),
      deadline: deadline,
    );
    if (!accepted) await _uncertainControl(job.id);
  }

  late final void Function() _detachObserver,
      _invalidateObserver,
      _detachSessionObserver;

  Map<String, Object?>? _currentObservationTarget(String serverId) {
    final foundation = store.snapshot.foundation.foundation;
    final server = foundation.profiles[serverId];
    if (server == null) return null;
    return {
      'workspaceId': foundation.workspaceId,
      'serverId': server.id,
      'targetRevision': server.revision,
      'connectionRevision': server.connectionRevision,
      'accessRevision': server.credentialRevision,
      'trustRevision': server.trustRevision,
    };
  }

  Map<String, Object?> _observation(AutomationJobRecord job) {
    final graph = store.snapshot.automation;
    _observations.prune(graph.jobs.keys.toSet());
    return _observations
        .snapshot(
          jobId: job.id,
          attemptId: job.hostAttemptId,
          currentTarget: _currentObservationTarget(
            graph.plans[job.immutablePlanId]!.serverId,
          ),
        )
        .toJson();
  }

  JobObserverBinding _beginObservation(
    AutomationJobRecord job,
    RemoteExecutorSession session,
  ) {
    _observations.prune(store.snapshot.automation.jobs.keys.toSet());
    return _observations.begin(
      JobObserverIdentity(
        jobId: job.id,
        attemptId: job.hostAttemptId,
        hostId: session.enrollment.hostId,
        registryDigest: session.enrollment.registryDigest,
        target: session.target,
      ),
    );
  }

  final RemoteExecutorService executors;
  final TrustedPlanService plans;
  StateStore get store => executors.connections.store;
  EngineSessions get sessions => executors.connections.sessions;
  final _operations = <JobOperation>{};
  final _drivers = <String, _JobDriver>{};
  final _cursors = <String, _JobCursor>{};
  final _clock = Stopwatch()..start();
  bool _closed = false,
      _nativeFailure = false,
      _paused = false,
      _pauseDrained = false;
  Future<void>? _closing, _pausing;

  /// Local-only generation recovery; never reconnect or restore step authority.
  Future<void> recover() => sessions.runAuthorityMutation(() async {
    final pending = store.snapshot.automation.jobs.values
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
        sshDispatchState:
            !queued &&
                job.sshDispatch != null &&
                job.sshDispatch!.state != 'completed'
            ? 'unknown'
            : null,
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
    if (_closed || _paused) throw StateError('NOT_READY');
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
    if (_closed || _paused) throw StateError('NOT_READY');
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
    if (_closed || _paused) throw StateError('SERVICE_UNAVAILABLE');
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
    final graph = store.snapshot.automation, job = graph.jobs[requireUuid(id)];
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
    final plan = store.snapshot.automation.plans[requireUuid(id)];
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
    JobControlTicket<_ControlIntent>? control,
    bool start = true,
  }) {
    if (_drivers.containsKey(jobId)) return false;
    final driver = _JobDriver(
      this,
      context,
      jobId,
      mode,
      opening,
      session,
      control,
    );
    _drivers[jobId] = driver;
    if (start) driver.run().ignore();
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
    final graph = store.snapshot.automation;
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
          'observation': _observation(graph.jobs[id]!),
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
        store.snapshot.automation.events.values
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

  Future<void> suspend() {
    if (_closed) return Future.error(StateError('SERVICE_UNAVAILABLE'));
    if (_pausing != null) return _pausing!;
    _paused = true;
    _controls.seal();
    final done = Completer<void>();
    _pausing = done.future;
    done.future.ignore();
    Future<void>.sync(_drainJobs).then<void>(
      (_) {
        _pauseDrained = true;
        done.complete();
      },
      onError: (Object _, StackTrace __) =>
          done.completeError(StateError('SERVICE_UNAVAILABLE')),
    );
    return done.future;
  }

  void resume() {
    if (_closed || _nativeFailure || !_paused || !_pauseDrained)
      throw StateError('SERVICE_UNAVAILABLE');
    _controls.resume();
    _paused = _pauseDrained = false;
    _pausing = null;
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    _controls.seal();
    _detachObserver();
    _invalidateObserver();
    _detachSessionObserver();
    _observations.close();
    return _closing = _drainJobs();
  }

  Future<void> _drainJobs() {
    _cursors.clear();
    for (final operation in _operations.toList())
      operation.stop('SERVICE_UNAVAILABLE');
    for (final driver in _drivers.values.toList()) driver.stop();
    return () async {
      await Future.wait([
        for (final operation in _operations.toList()) operation.done,
      ]);
      await _controlPumping;
      // An already admitted mutation can transfer its driver during close.
      final remaining = _drivers.values.toList();
      for (final driver in remaining) driver.stop();
      await Future.wait([for (final driver in remaining) driver.done]);
      for (final id in _controls.jobs) await _uncertainControl(id);
      if (!_controls.idle) throw StateError('SERVICE_UNAVAILABLE');
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
    : native = _NativeWork(service),
      _controlDeadline =
          service._controlClock.elapsed + const Duration(seconds: 30) {
    _result.future.ignore();
  }
  final TrustedJobService service;
  final _JobActor context;
  final String tool;
  final Map<String, Object?> input;
  final _NativeWork native;
  final Duration _controlDeadline;
  JobControlAdmission? _controlAdmission;
  final _watch = Stopwatch()..start();
  final _result = Completer<Map<String, Object?>>(), _done = Completer<void>();
  RemoteExecutorOperation? _opening;
  final _directs = <ConnectionDirectWork>{};
  bool _stopped = false, _mutating = false, _transferred = false;
  Future<Map<String, Object?>> get result => _result.future;
  Future<void> get done => _done.future;
  Duration get remaining {
    final left = _controlAdmission == null
        ? const Duration(seconds: 30) - _watch.elapsed
        : _controlDeadline - service._controlClock.elapsed;
    if (left <= Duration.zero) throw StateError('TIMEOUT');
    return left;
  }

  void _check() {
    if (_stopped || service._closed || service._paused)
      throw StateError('CANCELLED');
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
    _controlAdmission?.cancel();
    if (!_result.isCompleted) _result.completeError(StateError(code));
    if (!_mutating && !_transferred) _opening?.close().ignore();
    if (!_mutating && !_transferred)
      for (final work in _directs.toList()) work.cancelInterest().ignore();
  }

  Future<void> cancelInterest() {
    stop('CANCELLED');
    return done;
  }

  Future<void> _run() async {
    final timer = Timer(const Duration(seconds: 30), () => stop('TIMEOUT'));
    try {
      if (tool == 'serverdeck_jobs_cancel' ||
          tool == 'serverdeck_jobs_reconcile') {
        final lease = _controlAdmission = service._controls.reserve(
          deadline: _controlDeadline,
          valid: () => !_stopped,
        );
        await lease.entered;
      }
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
                  'observation': service._observation(job),
                  'plan': service
                      .store
                      .snapshot
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
              : service.store.snapshot.automation.plans[service
                    ._job(
                      context,
                      input['jobId'] as String,
                      TrustedJobService._scope(tool),
                    )
                    .immutablePlanId]!,
        );
        // Retained legacy attempts are history, never a helper fallback.
        if (plan.preflight?.isDirectSsh != true)
          throw StateError('UNKNOWN_OUTCOME');
        final controlTarget = service._currentObservationTarget(plan.serverId);
        if (_controlAdmission case final JobControlAdmission lease) {
          service._pruneControls();
          final current =
              service.store.snapshot.automation.jobs[input['jobId']]!;
          if (!_terminal.contains(current.state)) {
            service._controls.reserveJob(
              lease,
              current.id,
              current.hostAttemptId,
              serverId: plan.serverId,
            );
          }
        }
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
            () => service.store.snapshot.automation.jobs[replay['jobId']]!,
          );
          if (_controlAdmission case final JobControlAdmission lease) {
            await service._stable(
              () => service._registerControl(
                lease,
                command,
                context,
                old,
                _controlDeadline,
                controlTarget,
              ),
            );
          }
        } else {
          if (await service._stable(
                () => service.store.snapshot.automation.receipts.length,
              ) >=
              10000)
            throw StateError('RESOURCE_LIMIT');
          var verifiedDirect = false;
          final prior = await service._stable(
            () => service.store.snapshot.automation.jobs.values
                .where((job) => job.immutablePlanId == plan.id)
                .firstOrNull,
          );
          if (tool == 'serverdeck_apply' && prior == null) {
            if (plan.status != 'runnable') throw StateError('PLAN_STALE');
            if (!plan.isWithinLifetimeAt(_now()))
              throw StateError('PLAN_EXPIRED');
            if (service._drivers.length >= 48)
              throw StateError('RESOURCE_LIMIT');
            await _validateDirect(plan);
            verifiedDirect = true;
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
                verifiedPlanDigest: !verifiedDirect
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
            () => service.store.snapshot.automation.jobs[jobId]!,
          );
          if (verifiedDirect &&
              job.requestId == command.requestId &&
              job.state == 'queued') {
            _transferred = service._drive(
              jobId,
              context,
              'apply',
              opening: _opening,
            );
          } else if (_controlAdmission case final JobControlAdmission lease) {
            await service._stable(
              () => service._registerControl(
                lease,
                command,
                context,
                job,
                _controlDeadline,
                controlTarget,
              ),
            );
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
        await Future.wait([
          for (final work in _directs.toList()) work.cancelInterest(),
        ]);
      } catch (_) {
        service._nativeFailure = true;
      }
      await native.done;
      await context.owner?.settled;
      _controlAdmission?.release();
      // A native commit may settle after the logical authority wrapper failed.
      // Even without a returned ACK/ticket, conservatively settle its phase.
      if (_controlAdmission != null) service._wakeControls();
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
    this.control,
  ) : native = _NativeWork(service);
  final TrustedJobService service;
  final _JobActor context;
  final String jobId, mode;
  final JobControlTicket<_ControlIntent>? control;
  late AutomationJobRecord identity;
  late AutomationPlanRecord _capturedPlan;
  RemoteExecutorOperation? opening;
  RemoteExecutorSession? session;
  final _directs = <ConnectionDirectWork>{};
  JobObserverBinding? observer;
  final _NativeWork native;
  final _done = Completer<void>(), _stop = Completer<void>();
  bool stopped = false, submitted = false, cancelSent = false;
  int? _ownedReconciliationSequence;
  Future<void> get done => _done.future;
  void stop() {
    if (observer case final JobObserverBinding current)
      service._observations.detach(current);
    stopped = true;
    if (!_stop.isCompleted) _stop.complete();
    opening?.close().ignore();
    for (final work in _directs.toList()) work.cancelInterest().ignore();
  }

  AutomationJobRecord get job => service.store.snapshot.automation.jobs[jobId]!;
  AutomationPlanRecord get plan => _capturedPlan;
  Future<void> proof() async {
    if (stopped || control != null && !service._controlCurrent(control!))
      throw StateError('CANCELLED');
    final target = await service._stable(() => plan);
    await service._proof(
      context,
      mode == 'reconcile' ? McpScope.read : McpScope.apply,
      target.serverId,
      control == null
          ? const Duration(seconds: 5)
          : service._controlBudget(control!),
      native,
    );
    if (stopped || control != null && !service._controlCurrent(control!))
      throw StateError('CANCELLED');
  }

  Future<AutomationJobRecord> publish(
    String state,
    AutomationJobOutcome? outcome, {
    String? step,
    String? dispatchState,
  }) => publishJobProgress(
    mode: mode,
    state: state,
    ownedReconciliationSequence: _ownedReconciliationSequence,
    readCurrent: () => service._stable(() => job),
    compareAndSwap: (previous, nextState) => service._stable(
      () => service.store.publishTrustedJobProgress(
        jobId: jobId,
        expectedSequence: previous.nextSequence,
        state: nextState,
        outcome: outcome,
        clock: _now,
        progressStepId: step,
        sshDispatchState: dispatchState,
      ),
    ),
  );

  Future<void> gate(Future<void> Function() effect) =>
      service.sessions.runAuthorityMutation(
        () async {
          await proof();
          await effect();
        },
        deadline: control == null
            ? const Duration(seconds: 5)
            : service._controlBudget(control!),
        observeNativeCompletion: native.observe,
      );

  Future<Map<String, Object?>> request(
    String method,
    Map<String, Object?> args,
  ) async {
    await proof();
    final call = session!.request(method, args);
    if (control == null) return call;
    try {
      return await call.timeout(service._controlBudget(control!));
    } on TimeoutException {
      stop();
      throw StateError('TIMEOUT');
    }
  }

  Future<void> run() async {
    final timer = Timer(
      control != null
          ? (control!.deadline - service._controlClock.elapsed > Duration.zero
                ? control!.deadline - service._controlClock.elapsed
                : Duration.zero)
          : const Duration(hours: 2),
      stop,
    );
    try {
      if (service._closed || service._paused)
        throw StateError('SERVICE_UNAVAILABLE');
      await service._stable(() {
        identity = job;
        _capturedPlan =
            service.store.snapshot.automation.plans[identity.immutablePlanId]!;
      });
      await proof();
      if (_terminal.contains((await service._stable(() => job)).state)) return;
      if (plan.preflight?.isDirectSsh == true) {
        await this._runDirect();
        return;
      }
      if (session == null) {
        opening = context.open(
          service.executors,
          plan.serverId,
          scope: mode == 'reconcile' ? McpScope.read : McpScope.apply,
          beforeDispatch: control == null
              ? null
              : () {
                  if (stopped || !service._controlCurrent(control!))
                    throw StateError('CANCELLED');
                  service._controlBudget(control!);
                },
        );
        session = await opening!.result;
      }
      service._sessionMatches(
        plan,
        session!,
        use: mode == 'apply' ? JobSessionUse.effect : JobSessionUse.control,
      );
      observer = service._beginObservation(identity, session!);
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
                .snapshot
                .automation
                .revisions['${plan.key.profileId}:${plan.key.revision}']!,
          );
          final doc = plan.toJson();
          submitted = true;
          final response = await request('submit', {
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
          if (!service._observations.advanceFloor(
            observer!,
            response['sequence'] as int,
          ))
            throw StateError('RUNTIME_INCOMPATIBLE');
        });
      } else if (mode == 'reconcile') {
        // This root method only observes/journals outcomes, never runs Ansible.
        final value = await request('reconcile', {
          'attemptId': identity.hostAttemptId,
        });
        final receipt = ExecutorReconcileResult.capture(
          value,
          attemptId: identity.hostAttemptId,
        );
        await proof();
        if (!service._observations.advanceFloor(observer!, receipt.sequence))
          throw StateError('RUNTIME_INCOMPATIBLE');
        if (!receipt.childrenStopped) {
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
      }
      var previousSequence = 0, previousEpoch = 0, previousStep = 0;
      while (true) {
        await proof();
        if ((await service._stable(() => job)).cancelRequested &&
            mode != 'reconcile' &&
            !cancelSent) {
          await gate(() async {
            final binding = service._controls.stopBinding(
              jobId,
              identity.hostAttemptId,
            );
            final value = await request('cancel', {
              'attemptId': identity.hostAttemptId,
              'requestId': identity.id,
            });
            requireFields(value, {'attemptId', 'state'});
            if (value['attemptId'] != identity.hostAttemptId ||
                !executorJobStates.contains(value['state']))
              throw StateError('RUNTIME_INCOMPATIBLE');
            cancelSent = true;
            service._controls.acknowledgeStop(
              jobId,
              identity.hostAttemptId,
              binding: binding,
            );
          });
        }
        final raw = await request('status', {
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
        if (!service._observations.observe(
          observer!,
          JobObservationProgress.fromStatus(status),
          currentTarget: service._currentObservationTarget(plan.serverId),
        ))
          throw StateError('RUNTIME_INCOMPATIBLE');
        if (status.terminal) {
          await publish(status.localState, status.outcome(executorDomainCode));
          return;
        }
        if (mode == 'reconcile' || mode == 'cancel') {
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
            final response = await request('authorize_step', {
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
              dispatchState:
                  current.sshDispatch != null &&
                      current.sshDispatch!.state != 'completed'
                  ? 'unknown'
                  : null,
            );
          }
        }
      } catch (_) {
        service._nativeFailure = true;
      }
    } finally {
      timer.cancel();
      if (observer case final JobObserverBinding current)
        service._observations.detach(current);
      try {
        await opening?.close();
        await Future.wait([
          for (final work in _directs.toList()) work.cancelInterest(),
        ]);
      } catch (_) {
        service._nativeFailure = true;
      }
      await native.done;
      await context.owner?.settled;
      if (identical(service._drivers[jobId], this))
        service._drivers.remove(jobId);
      _done.complete();
      if (!service._nativeFailure) service._wakeControls();
    }
  }
}

final class _ControlIntent {
  _ControlIntent(this.actor, this.command, this.server, this.target);
  final _JobActor actor;
  final JobMutationCommand command;
  final String server;
  final Map<String, Object?>? target;
  bool retired = false;
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
        await owner!.revalidate().timeout(deadline);
      } on TimeoutException {
        throw StateError('TIMEOUT');
      }
    }
  }

  RemoteExecutorOperation open(
    RemoteExecutorService executors,
    String server, {
    required McpScope scope,
    void Function()? beforeDispatch,
  }) => mcp != null
      ? executors.startMcp(
          mcp!,
          server,
          scope: scope,
          beforeDispatch: beforeDispatch,
        )
      : executors.startAutomationOwner(
          owner!,
          server,
          scope: scope,
          beforeDispatch: beforeDispatch,
        );
}
