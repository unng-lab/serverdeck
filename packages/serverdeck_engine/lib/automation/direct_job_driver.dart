part of 'jobs.dart';

Map<String, Object?> _directPlanTarget(AutomationPlanRecord plan) => {
  'workspaceId': plan.workspaceId,
  'serverId': plan.serverId,
  'targetRevision': plan.serverRevision,
  'connectionRevision': plan.connectionRevision,
  'accessRevision': plan.accessRevision,
  'trustRevision': plan.trustRevision,
};
void _noLegacyWrites(TrustedJobService service) {
  final graph = service.store.snapshot.automation;
  if (graph.jobs.values.any(
    (job) =>
        !_terminal.contains(job.state) &&
        graph.plans[job.immutablePlanId]!.preflight?.isDirectSsh != true,
  ))
    throw StateError('UNKNOWN_OUTCOME');
}

ConnectionDirectWork _openJobDirect(
  TrustedJobService service,
  _JobActor actor,
  String server,
  DirectSshCommand command,
  void Function() current,
) => actor.mcp != null
    ? service.executors.connections.executeDirectMcp(
        actor.mcp!,
        server,
        command,
        beforeDispatch: current,
      )
    : service.executors.connections.executeDirectAutomationOwner(
        actor.owner!,
        server,
        command,
        beforeDispatch: current,
      );

Future<DirectSshOutput> _ownedDirect(
  ConnectionDirectWork work,
  Set<ConnectionDirectWork> owned,
  void Function() current, {
  Duration? budget,
}) async {
  owned.add(work);
  try {
    Future<ConnectionDirectValue> result = work.result;
    if (budget != null)
      result = result.timeout(
        budget,
        onTimeout: () {
          work.cancelInterest().ignore();
          throw StateError('TIMEOUT');
        },
      );
    final value = await result;
    await work.done;
    current();
    return value.output;
  } finally {
    work.done.then<void>((_) => owned.remove(work)).ignore();
  }
}

final class _DirectFacts {
  _DirectFacts(
    this.identity,
    this.packages,
    this.observations,
    this.uptimeWatch,
  );
  final DirectSshIdentity identity;
  final DirectPackageSnapshot packages;
  final List<ManagedResourceObservationRecord> observations;
  final Stopwatch uptimeWatch;
}

Future<_DirectFacts> _collectDirect(
  TrustedJobService service,
  _JobActor actor,
  AutomationPlanRecord plan,
  Set<ConnectionDirectWork> owned,
  void Function() current, {
  Duration Function()? remaining,
}) async {
  final target = DirectObservationTarget.capture(
    service.store.snapshot.foundation.foundation,
    plan.serverId,
  );
  if (!_same(target.toJson(), _directPlanTarget(plan)))
    throw StateError('PLAN_STALE');
  Future<DirectSshOutput> read(DirectSshCommand command) {
    current();
    final work = _openJobDirect(
      service,
      actor,
      plan.serverId,
      command,
      current,
    );
    return _ownedDirect(work, owned, current, budget: remaining?.call());
  }

  final first = DirectSshIdentity.capture(
    (await read(DirectSshCommand.inspect())).textRows(DirectSshIdentity.fields),
  );
  if (first.hostId != plan.hostId ||
      first.bootIdHash != plan.preflight!.toJson()['bootIdHash'])
    throw StateError('PLAN_STALE');
  final packages = DirectPackageSnapshot.capture(
    await read(DirectSshCommand.packages()),
  );
  if (packages.digest != plan.preflight!.toJson()['packageSnapshotDigest'])
    throw StateError('PLAN_STALE');
  final observations = <ManagedResourceObservationRecord>[];
  for (final resource in plan.baseObservations.keys) {
    final at = _now();
    observations.add(
      target.parse(
        resource,
        first,
        await read(DirectSshCommand.observation(resource)),
        at,
      ),
    );
  }
  final after = DirectPackageSnapshot.capture(
    await read(DirectSshCommand.packages()),
  );
  if (after.digest != packages.digest) throw StateError('PLAN_STALE');
  final uptimeWatch = Stopwatch()..start();
  final identity = DirectSshIdentity.capture(
    (await read(DirectSshCommand.inspect())).textRows(DirectSshIdentity.fields),
  );
  if (identity.hostId != first.hostId ||
      identity.bootIdHash != first.bootIdHash ||
      identity.uptimeMs < first.uptimeMs)
    throw StateError('PLAN_STALE');
  try {
    await plan.validateCurrentObservations(observations, now: _now());
  } on FormatException {
    throw StateError('PLAN_STALE');
  }
  current();
  return _DirectFacts(identity, packages, observations, uptimeWatch);
}

extension _DirectJobAdmission on JobOperation {
  Future<void> _validateDirect(AutomationPlanRecord plan) async {
    _noLegacyWrites(service);
    service.plans.preflightFor(plan);
    final captured = DirectObservationTarget.capture(
      service.store.snapshot.foundation.foundation,
      plan.serverId,
    );
    void current() {
      _check();
      context.authorize(scope: McpScope.apply, serverId: plan.serverId);
      if (!captured.matches(service.store.snapshot.foundation.foundation))
        throw StateError('PLAN_STALE');
    }

    try {
      await _collectDirect(
        service,
        context,
        plan,
        _directs,
        current,
        remaining: () => remaining,
      );
    } on DirectSshFailure catch (error) {
      throw StateError(error.code == 'TIMEOUT' ? 'TIMEOUT' : 'PLAN_STALE');
    }
    service.plans.preflightFor(plan);
  }
}

extension _DirectJobExecution on _JobDriver {
  Future<void> _runDirect() async {
    final target = DirectObservationTarget.capture(
      service.store.snapshot.foundation.foundation,
      plan.serverId,
    );
    final attempt = DirectSshAttempt.fromRecords(identity, plan);
    void current() {
      if (stopped ||
          service._closed ||
          service._paused ||
          service._nativeFailure ||
          control != null && !service._controlCurrent(control!))
        throw StateError('CANCELLED');
      context.authorize(
        scope: mode == 'reconcile' ? McpScope.read : McpScope.apply,
        serverId: plan.serverId,
      );
      if (!target.matches(service.store.snapshot.foundation.foundation))
        throw StateError('TRUST_CHANGED');
      if (control != null) service._controlBudget(control!);
    }

    Future<DirectSshOutput> read(DirectSshCommand command) async {
      current();
      return _ownedDirect(
        _openJobDirect(service, context, plan.serverId, command, current),
        _directs,
        current,
        budget: control == null ? null : service._controlBudget(control!),
      );
    }

    final actualIdentity = DirectSshIdentity.capture(
      (await read(DirectSshCommand.inspect()))
          .textRows(DirectSshIdentity.fields),
    );
    if (actualIdentity.hostId != plan.hostId) throw StateError('TRUST_CHANGED');
    observer = service._observations.begin(
      JobObserverIdentity(
        jobId: jobId,
        attemptId: identity.hostAttemptId,
        hostId: actualIdentity.hostId,
        registryDigest: plan.registryDigest!,
        target: target.toJson(),
      ),
    );
    void sample(int phase, String state, List<Map<String, Object?>> checks) {
      current();
      if (!service._observations.observe(
        observer!,
        JobObservationProgress.capture({
          'attemptId': identity.hostAttemptId,
          'state': state,
          'sequence': phase,
          'stepIndex': phase >= 4 ? 1 : 0,
          'authorizationEpoch': phase >= 2 ? 1 : 0,
          'failureCode': state == 'failed' ? 'POSTCHECK_FAILED' : null,
          'checks': [
            for (final check in checks)
              {
                'checkId': check['checkId'],
                'passed': check['result'] == 'passed',
              },
          ],
        }),
        currentTarget: service._currentObservationTarget(plan.serverId),
      ))
        throw StateError('TRUST_CHANGED');
    }

    Future<DirectSshOutput> send(
      Future<DirectSshCommand> Function(Duration Function()) prepare, {
      bool selected = false,
    }) async {
      ConnectionDirectWork? work;
      var gateLive = true;
      final watch = Stopwatch()..start();
      Duration left() {
        final remaining = const Duration(seconds: 5) - watch.elapsed;
        if (remaining <= Duration.zero) throw StateError('TIMEOUT');
        return remaining;
      }

      try {
        await gate(() async {
          watch.reset();
          current();
          final command = await prepare(left);
          void fenced() {
            if (!gateLive) throw StateError('FORBIDDEN');
            left();
            current();
            if (selected)
              service.store.validateTrustedJobStep(
                jobId,
                originGrantId: context.grantId,
                expectedGrantRevision: context.revision,
                at: _now(),
              );
          }

          fenced();
          work = _openJobDirect(
            service,
            context,
            plan.serverId,
            command,
            fenced,
          );
          _directs.add(work!);
          try {
            await work!.dispatched.timeout(left());
          } on TimeoutException {
            work!.cancelInterest().ignore();
            throw StateError('TIMEOUT');
          }
        });
      } finally {
        gateLive = false;
      }
      return _ownedDirect(work!, _directs, current);
    }

    Future<void> terminal(
      String state,
      AutomationJobOutcome outcome, {
      String? dispatchState,
    }) async {
      // Only claim cancel's own reconciliation phase after remote proof, and
      // hold the actual native gate through both local publications. A newer
      // accepted reconcile can otherwise reuse an existing reconciling state.
      await gate(() async {
        current();
        final before = await service._stable(() => job);
        if (mode == 'cancel' && before.state == 'unknown') {
          final phase = await publish('reconciling', null);
          if (phase.state == 'reconciling' &&
              phase.nextSequence == before.nextSequence + 1)
            _ownedReconciliationSequence = phase.nextSequence;
        }
        await publish(state, outcome, dispatchState: dispatchState);
      });
    }

    if (mode == 'apply') {
      _noLegacyWrites(service);
      if (!_same(target.toJson(), _directPlanTarget(plan)))
        throw StateError('PLAN_STALE');
      await send((_) async {
        service.store.validateTrustedJobStep(
          jobId,
          originGrantId: context.grantId,
          expectedGrantRevision: context.revision,
          at: _now(),
        );
        await publish('running', null);
        submitted = true;
        return DirectSshCommand.reserveAttempt(attempt);
      }, selected: true).then((output) {
        final reserved = DirectAttemptSnapshot.fromOutput(attempt, output);
        if (reserved.owner == null ||
            reserved.admission == null ||
            reserved.terminal != null)
          throw StateError('UNKNOWN_OUTCOME');
      });
      sample(1, 'queued', []);
      await send((left) async {
        final facts = await _collectDirect(
          service,
          context,
          plan,
          _directs,
          current,
          remaining: left,
        );
        final before = await service._stable(() => job);
        final effects = (plan.toJson()['effects'] as List)
            .cast<Map<String, Object?>>();
        final authorized = await service.store.authorizeDirectSshStep(
          jobId: jobId,
          expectedSequence: before.nextSequence,
          stepId: effects.first['id'] as String,
          bootIdHash: facts.identity.bootIdHash,
          observedUptimeMs: facts.identity.uptimeMs,
          elapsedSinceProbe: () => facts.uptimeWatch.elapsed,
          originGrantId: context.grantId,
          expectedGrantRevision: context.revision,
          clock: _now,
          revalidate: () {
            if (stopped ||
                service._closed ||
                service._paused ||
                control != null && !service._controlCurrent(control!))
              throw StateError('FORBIDDEN');
            context.owner?.remaining;
            if (context.mcp != null &&
                context.mcp!.untilExpiry <= Duration.zero)
              throw StateError('FORBIDDEN');
            left();
          },
        );
        final step = await DirectSshStep.capture(
          authorized,
          plan,
          facts.observations.single,
        );
        current();
        left();
        return DirectSshCommand.launchStep(step);
      }, selected: true).then((output) {
        final disposition = output.textRows(const {
          'disposition',
        })['disposition'];
        if (!const {'launched', 'existing', 'stopped'}.contains(disposition))
          throw StateError('UNKNOWN_OUTCOME');
      });
      await publish('running', null, dispatchState: 'sent');
    }
    while (true) {
      await proof();
      current();
      if (job.cancelRequested && mode != 'reconcile' && !cancelSent) {
        try {
          final binding = service._controls.stopBinding(
            jobId,
            identity.hostAttemptId,
          );
          final output = await send(
            (_) async => DirectSshCommand.stopAttempt(attempt),
          );
          DirectAttemptSnapshot.fromOutput(attempt, output);
          cancelSent = true;
          service._controls.acknowledgeStop(
            jobId,
            identity.hostAttemptId,
            binding: binding,
          );
        } on DirectSshFailure catch (error) {
          if (error.code != 'HOST_BUSY') rethrow;
        }
      }
      final attemptStatus = DirectAttemptSnapshot.fromOutput(
        attempt,
        await read(DirectSshCommand.attemptStatus(attempt)),
      );
      final currentJob = await service._stable(() => job);
      if (currentJob.sshDispatch == null) {
        final cancellation = DirectUndispatchedCancellation.capture(
          currentJob,
          plan,
          attemptStatus,
        );
        final output = await send(
          (_) async => DirectSshCommand.cancelUndispatched(cancellation),
        );
        final finalStatus = DirectAttemptSnapshot.fromOutput(attempt, output);
        if (finalStatus.owner != null ||
            finalStatus.terminal == null ||
            finalStatus.plan?.fields['terminal'] != 'cancelled' ||
            base64.encode(finalStatus.terminal!.encode()) !=
                base64.encode(cancellation.terminal.encode()))
          throw StateError('UNKNOWN_OUTCOME');
        await proof();
        current();
        await terminal('cancelled', cancellation.outcome);
        return;
      }
      final reference = await DirectSshStep.reference(currentJob, plan);
      final released =
          attemptStatus.terminal != null &&
          attemptStatus.owner == null &&
          attemptStatus.plan?.fields['terminal'] ==
              attemptStatus.terminal!.fields['state'];
      final receipt = await DirectStepSnapshot.capture(
        currentJob,
        plan,
        await read(
          DirectSshCommand.stepStatus(reference, historyOnly: released),
        ),
      );
      sample(
        receipt.records['result'] != null
            ? 4
            : receipt.records['start'] != null
            ? 3
            : 2,
        'running',
        receipt.checks,
      );
      if (released || receipt.hasCompleteReceipt) {
        ManagedResourceObservationRecord? observation;
        if (!released && receipt.state != 'stopped') {
          final at = _now();
          final fresh = DirectSshIdentity.capture(
            (await read(DirectSshCommand.inspect()))
                .textRows(DirectSshIdentity.fields),
          );
          if (fresh.hostId != plan.hostId ||
              fresh.bootIdHash != reference.dispatch.bootIdHash)
            throw StateError('PLAN_STALE');
          observation = target.parse(
            reference.resourceId,
            fresh,
            await read(DirectSshCommand.observation(reference.resourceId)),
            at,
          );
        }
        final finalization = DirectFinalization.capture(
          attemptStatus,
          receipt,
          observation,
          at: _now(),
        );
        final output = await send(
          (_) async => DirectSshCommand.finalizeAttempt(finalization),
        );
        final finalStatus = DirectAttemptSnapshot.fromOutput(attempt, output);
        if (finalStatus.owner != null ||
            finalStatus.terminal == null ||
            finalStatus.plan?.fields['terminal'] !=
                finalization.terminal.fields['state'] ||
            base64.encode(finalStatus.terminal!.encode()) !=
                base64.encode(finalization.terminal.encode()))
          throw StateError('UNKNOWN_OUTCOME');
        await proof();
        current();
        // The receipt sample remains phase4 until this driver detaches. A
        // pending newer reconcile may own local terminal publication, so an
        // older cancel must not install a terminal observation ahead of it.
        await terminal(
          finalization.terminal.fields['state']!,
          finalization.outcome,
          dispatchState: 'completed',
        );
        return;
      }
      if (mode != 'apply') throw StateError('UNKNOWN_OUTCOME');
      await Future.any([
        Future<void>.delayed(const Duration(seconds: 1)),
        _stop.future,
      ]);
    }
  }
}
