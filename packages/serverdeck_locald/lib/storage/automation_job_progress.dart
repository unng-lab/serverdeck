part of 'state_store.dart';

/// Driver-only metadata publication. It does not establish remote success;
/// the shared driver validates actual enrolled root responses before calling.
extension TrustedJobProgress on StateStore {
  Future<AutomationJobRecord> publishTrustedJobProgress({
    required String jobId,
    required int expectedSequence,
    required String state,
    required AutomationJobOutcome? outcome,
    required DateTime Function() clock,
    String? progressStepId,
  }) => _queueTrustedMetadata(() async {
    final previous = _automationView(_AutomationFormat.trusted),
        graph = previous.automation;
    final job = graph.jobs[requireUuid(jobId)];
    if (job == null) throw StateError('FORBIDDEN');
    if (job.nextSequence != expectedSequence)
      throw StateError('REVISION_CONFLICT');
    if (progressStepId == null &&
        job.state == state &&
        StrictCodec().canonical(job.outcome?.toJson()).toString() ==
            StrictCodec().canonical(outcome?.toJson()).toString())
      return job;
    if (job.nextSequence >= 9223372036854775807)
      throw StateError('RESOURCE_LIMIT');
    var at = _grantInstant(clock, _AutomationFormat.trusted);
    if (at.isBefore(job.updatedAt)) at = job.updatedAt;
    if (progressStepId != null &&
        !(graph.plans[job.immutablePlanId]!.toJson()['effects'] as List).any(
          (raw) => (raw as Map)['id'] == progressStepId,
        ))
      throw StateError('VALIDATION');
    final next = AutomationJobRecord.fromJson({
      ...job.toJson(),
      'state': state,
      'outcome': outcome?.toJson(),
      'nextSequence': job.nextSequence + 1,
      'updatedAt': at.toIso8601String(),
      if (state == 'cancel-requested') 'cancelRequested': true,
    });
    job.validateTransitionTo(next);
    final candidate = {
      for (final entry in previous.rows.entries)
        entry.key: List<AutomationSnapshotRow>.of(entry.value),
    };
    void put(String group, String key, Map<String, Object?> value) {
      final rows = candidate[group]!,
          index = rows.indexWhere((row) => row.entityId == key);
      final row = AutomationSnapshotRow(
        index < 0 ? _nextGrantNativeId(rows) : rows[index].nativeId,
        key,
        utf8.decode(StrictCodec().canonical(value)),
      );
      if (index < 0) {
        rows.add(row);
      } else {
        rows[index] = row;
      }
    }

    put('jobs', next.id, next.toJson());
    if (graph.events.length < 10000) {
      final event = AutomationJobEventRecord.fromJson({
        'workspaceId': _state.workspaceId,
        'jobId': job.id,
        'sequence': job.nextSequence,
        'timestamp': at.toIso8601String(),
        'kind': progressStepId == null ? 'state' : 'step',
        'stepId': progressStepId,
        'state': progressStepId == null ? state : null,
        'safeCode': outcome?.safeCode,
        'checkResult': null,
        'droppedCount': 0,
      });
      put('events', '${job.id}:${event.sequence}', event.toJson());
    }
    // Even at the event quota the durable state/outcome must advance. A missing
    // event is an explicit sequence gap exposed by jobs_events.dropped; never
    // hide an uncertain or terminal state behind a progress allocation failure.
    if (state == 'succeeded') {
      final plan = graph.plans[job.immutablePlanId]!, doc = plan.toJson();
      final checks = (doc['checks'] as List).cast<Map<String, Object?>>();
      final results = outcome!.checks;
      if (results.length != checks.length ||
          checks.any(
            (check) => !results.any(
              (result) =>
                  result.checkId == check['id'] &&
                  result.stepId == check['effectId'] &&
                  result.result == 'passed',
            ),
          ))
        throw StateError('VALIDATION');
      final resources = <String>{
        for (final raw in doc['effects'] as List)
          if ((raw as Map<String, Object?>)['resourceId'] case final String id)
            id,
        for (final recipe in plan.preflight!.recipes) ...recipe.ownedResources,
      };
      for (final resource in resources) {
        final prior = graph.desired.values
            .where(
              (row) =>
                  row.serverId == plan.serverId && row.resourceId == resource,
            )
            .firstOrNull;
        final revision = (prior?.desiredRevision ?? 0) + 1;
        if (revision > 2147483647) throw StateError('RESOURCE_LIMIT');
        String freshId() {
          final used = candidate['desired']!.map((row) => row.entityId).toSet();
          for (var i = 0; i < 8; i++) {
            final id = _grantSecretRef();
            if (!used.contains(id)) return id;
          }
          throw StateError('RESOURCE_LIMIT');
        }

        final desired = AutomationDesiredStateRecord.fromJson({
          'workspaceId': _state.workspaceId,
          'id': prior?.id ?? freshId(),
          'serverId': plan.serverId,
          'resourceId': resource,
          'desiredRevision': revision,
          'bodyDigest': job.profileKey.bodyDigest,
          'inputDigest': doc['inputDigest'],
          'lastJobId': job.id,
          'observedRevision': revision,
        });
        put('desired', desired.id, desired.toJson());
      }
    }
    await _commitTrustedDelta(
      previous,
      candidate,
      () => _grantLive(_AutomationFormat.trusted),
    );
    return next;
  });
}
