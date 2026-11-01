part of 'state_store.dart';

/// Driver-only durable intent. The driver must hold the actual authority/native
/// publication gate, obtain fresh native/session/baseline proof, and keep that
/// gate through this commit and first SSH dispatch. This store method neither
/// obtains native permission nor sends any remote bytes.
extension DirectSshDispatchWrites on StateStore {
  Future<AutomationJobRecord> authorizeDirectSshStep({
    required String jobId,
    required int expectedSequence,
    required String stepId,
    required String bootIdHash,
    required int observedUptimeMs,
    // Monotonic elapsed since BEFORE the uptime probe, including round trip.
    required Duration Function() elapsedSinceProbe,
    required String? originGrantId,
    required int? expectedGrantRevision,
    required DateTime Function() clock,
    required void Function() revalidate,
  }) => _queueMetadata(() async {
    final previous = _automationView(), graph = previous.automation;
    final job = graph.jobs[requireUuid(jobId)];
    if (job == null) throw StateError('FORBIDDEN');
    if (job.nextSequence != expectedSequence)
      throw StateError('REVISION_CONFLICT');
    final plan = graph.plans[job.immutablePlanId]!;
    if (plan.preflight?.isDirectSsh != true)
      throw StateError('RUNTIME_INCOMPATIBLE');
    // A legacy host UUID cannot safely be mapped to the direct identity.
    if (graph.jobs.values.any(
      (row) =>
          !_terminalJobStates.contains(row.state) &&
          graph.plans[row.immutablePlanId]!.preflight?.isDirectSsh != true,
    )) {
      throw StateError('HOST_BUSY');
    }
    if (plan.preflight!.toJson()['bootIdHash'] != bootIdHash)
      throw StateError('PLAN_STALE');
    if (observedUptimeMs < 0 || observedUptimeMs > 9223372036854770807)
      throw StateError('VALIDATION');
    final effects = (plan.toJson()['effects'] as List)
        .cast<Map<String, Object?>>();
    final previousDispatch = job.sshDispatch;
    final previousIndex = previousDispatch == null
        ? -1
        : effects.indexWhere((row) => row['id'] == previousDispatch.stepId);
    if (previousDispatch != null && previousDispatch.state != 'completed')
      throw StateError('REVISION_CONFLICT');
    final index = previousIndex + 1;
    if (index >= effects.length || effects[index]['id'] != stepId)
      throw StateError('VALIDATION');
    if (job.nextSequence >= 9223372036854775807 || graph.events.length >= 10000)
      throw StateError('RESOURCE_LIMIT');
    var at = _grantInstant(clock);
    if (at.isBefore(job.updatedAt)) at = job.updatedAt;
    void authority(DateTime now) {
      revalidate();
      _validateJobStep(
        job.id,
        originGrantId: originGrantId,
        expectedGrantRevision: expectedGrantRevision,
        at: now,
      );
    }

    authority(at);
    final grant = graph.grants[job.grantId];
    final authorityExpiry = job.authority.kind == 'approval'
        ? graph.approvals[job.authority.id]!.expiresAt
        : graph.delegations[job.authority.id]!.expiresAt;
    var budget = 5000;
    void bound(DateTime expiry) {
      budget = min(budget, expiry.difference(at).inMilliseconds);
    }

    if (grant != null) bound(grant.expiresAt);
    if (job.authority.kind == 'delegation') bound(authorityExpiry);
    final sampledElapsed = elapsedSinceProbe();
    if (sampledElapsed.isNegative) throw StateError('VALIDATION');
    final elapsed = sampledElapsed.inMilliseconds;
    final remaining = budget - elapsed;
    if (remaining <= 0) throw StateError('TIMEOUT');
    final dispatch = DirectSshDispatch.fromJson({
      'format': 1,
      'stepId': stepId,
      'stepDigest': directBindingDigest(effects[index]),
      'token': _grantSecretRef(),
      'bootIdHash': bootIdHash,
      'issuedUptimeMs': observedUptimeMs,
      'expiresUptimeMs': observedUptimeMs + remaining,
      'authorityBindingDigest': directAuthorityBinding(
        plan: plan,
        authority: job.authority,
        grantId: job.grantId,
        grantRevision: grant?.revision,
        grantExpiresAt: grant?.expiresAt,
        authorityExpiresAt: authorityExpiry,
      ),
      'targetBindingDigest': directTargetBinding(plan),
      'authorizedAt': at.toIso8601String(),
      'grantRevision': grant?.revision,
      'grantExpiresAt': grant?.expiresAt.toIso8601String(),
      'state': 'authorized',
    });
    final next = AutomationJobRecord.fromJson({
      ...job.toJson(),
      'sshDispatch': dispatch.toJson(),
      'state': 'running',
      'nextSequence': job.nextSequence + 1,
      'updatedAt': at.toIso8601String(),
    });
    job.validateTransitionTo(next);
    final event = AutomationJobEventRecord.fromJson({
      'workspaceId': job.workspaceId,
      'jobId': job.id,
      'sequence': job.nextSequence,
      'timestamp': at.toIso8601String(),
      'kind': 'step',
      'stepId': stepId,
      'state': null,
      'safeCode': null,
      'checkResult': null,
      'droppedCount': 0,
    });
    final candidate = {
      for (final entry in previous.rows.entries)
        entry.key: List<AutomationSnapshotRow>.of(entry.value),
    };
    final jobs = candidate['jobs']!,
        position = jobs.indexWhere((row) => row.entityId == job.id);
    jobs[position] = AutomationSnapshotRow(
      jobs[position].nativeId,
      job.id,
      utf8.decode(StrictCodec().canonical(next.toJson())),
    );
    candidate['events']!.add(
      AutomationSnapshotRow(
        _nextGrantNativeId(candidate['events']!),
        '${job.id}:${event.sequence}',
        utf8.decode(StrictCodec().canonical(event.toJson())),
      ),
    );
    await _commitTrustedDelta(previous, candidate, () {
      authority(_grantInstant(clock));
      final currentElapsed = elapsedSinceProbe();
      if (currentElapsed < sampledElapsed ||
          currentElapsed.inMilliseconds >= remaining)
        throw StateError('FORBIDDEN');
    });
    return next;
  });
}
