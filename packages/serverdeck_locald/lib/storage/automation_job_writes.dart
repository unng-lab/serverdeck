part of 'state_store.dart';

const _terminalJobStates = {'succeeded', 'failed', 'cancelled'};

/// Native durable admission/state only. Before admission the shared job service
/// must independently recompile and revalidate qualified root/current facts.
/// These records cannot send a root request or authorize an execution step.
extension TrustedJobWrites on StateStore {
  Future<Map<String, Object?>?> replayTrustedJob(
    JobMutationCommand command, {
    required String? originGrantId,
    required int? expectedGrantRevision,
    required DateTime at,
  }) => _queueTrustedMetadata(() async {
    final previous = _automationView(_AutomationFormat.trusted),
        graph = previous.automation;
    final input = command.toJson();
    final job = graph.jobs[input['jobId']];
    final plan = command.operation == 'job.apply'
        ? graph.plans[input['planId']]
        : job == null
        ? null
        : graph.plans[job.immutablePlanId];
    if (plan == null ||
        originGrantId != null &&
            plan.toJson()['originGrantId'] != originGrantId)
      throw StateError('FORBIDDEN');
    _jobMutationAuthority(
      command.operation,
      originGrantId,
      expectedGrantRevision,
      plan.toJson()['originGrantId'] as String?,
      plan.serverId,
      at,
    );
    final receipt = graph.receipts[command.requestId];
    if (receipt == null) {
      if (_state.receipts.containsKey(command.requestId))
        throw StateError('IDEMPOTENCY_CONFLICT');
      return null;
    }
    if (receipt.originGrantId != originGrantId) throw StateError('FORBIDDEN');
    final digest = base64
        .decode(
          _custody.receiptDigestSync(
            _receiptKey,
            command.canonicalRequest(originGrantId),
          ),
        )
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    if (receipt.operation != command.operation ||
        receipt.canonicalDigest != digest)
      throw StateError('IDEMPOTENCY_CONFLICT');
    _authorityUnavailable = true;
    try {
      final loaded = await _reloadGrants(_AutomationFormat.trusted);
      if (!_sameGrantSnapshot(previous, loaded))
        throw StateError('STORAGE_BLOCKED');
      _publishAutomation(loaded);
      _authorityUnavailable = false;
      return receipt.result;
    } catch (_) {
      _blocked = true;
      throw StateError('STORAGE_BLOCKED');
    }
  });
  void _jobActor(
    String? origin,
    int? revision,
    String server,
    McpScope scope,
    DateTime at,
  ) {
    _grantLive(_AutomationFormat.trusted);
    if (origin == null) return;
    final grant = _automationView(_AutomationFormat.trusted)
        .automation
        .grants[origin];
    if (grant == null ||
        grant.revision != revision ||
        !grant.isCurrentAt(at) ||
        !grant.policy.allowsScope(scope) ||
        !grant.policy.allowsServer(server))
      throw StateError('FORBIDDEN');
  }

  void _jobObjectGrant(
    String? grantId,
    String server,
    McpScope scope,
    DateTime at,
  ) {
    if (grantId == null) return;
    final grant = _automationView(_AutomationFormat.trusted)
        .automation
        .grants[grantId];
    if (grant == null ||
        !grant.isCurrentAt(at) ||
        !grant.policy.allowsScope(scope) ||
        !grant.policy.allowsServer(server))
      throw StateError('FORBIDDEN');
  }

  void _jobMutationAuthority(
    String operation,
    String? origin,
    int? revision,
    String? objectGrant,
    String server,
    DateTime at,
  ) {
    final scope = operation == 'job.reconcile' ? McpScope.read : McpScope.apply;
    _jobActor(origin, revision, server, scope, at);
    // A trusted owner may stop/observe an already accepted job even after its
    // original client loses authority. This never authorizes apply or a step;
    // neither the job's grant nor its receipt object identity is rewritten.
    if (origin != null || operation == 'job.apply') {
      _jobObjectGrant(objectGrant, server, scope, at);
    }
  }

  void _jobTarget(AutomationPlanRecord plan) {
    final server = _state.profiles[plan.serverId];
    if (server == null ||
        server.revision != plan.serverRevision ||
        server.connectionRevision != plan.connectionRevision ||
        server.credentialRevision != plan.accessRevision ||
        server.trustRevision != plan.trustRevision)
      throw StateError('PLAN_STALE');
  }

  AutomationAuthorityRef _jobAuthority(AutomationPlanRecord plan, DateTime at) {
    final graph = _automationView(_AutomationFormat.trusted).automation;
    final doc = plan.toJson(), origin = doc['originGrantId'] as String?;
    final grant = graph.grants[origin];
    if (grant != null) {
      final matches =
          graph.delegations.values
              .where(
                (row) => row.matches(
                  grant: grant,
                  serverId: plan.serverId,
                  profile: plan.key,
                  parameters: doc['exactParams'] as Map<String, Object?>,
                  at: at,
                ),
              )
              .toList()
            ..sort((a, b) => a.id.compareTo(b.id));
      if (matches.isNotEmpty)
        return AutomationAuthorityRef.fromJson({
          'kind': 'delegation',
          'id': matches.first.id,
          'revision': matches.first.revision,
        });
    }
    final approvals =
        graph.approvals.values
            .where(
              (row) =>
                  row.planId == plan.id &&
                  row.planDigest == doc['digest'] &&
                  row.grantId == origin &&
                  row.state == 'approved' &&
                  !at.isBefore(row.createdAt) &&
                  at.isBefore(row.expiresAt),
            )
            .toList()
          ..sort((a, b) {
            final order = a.createdAt.compareTo(b.createdAt);
            return order == 0 ? a.id.compareTo(b.id) : order;
          });
    if (approvals.isEmpty) throw StateError('APPROVAL_REQUIRED');
    return AutomationAuthorityRef.fromJson({
      'kind': 'approval',
      'id': approvals.first.id,
      'revision': 1,
    });
  }

  /// Fresh authority for one not-yet-authorized effect, never an approval token.
  /// The service must hold its actual native publication gate through the root
  /// CAS authorize_step and revalidate native/session/target before dispatch.
  void validateTrustedJobStep(
    String jobId, {
    required String? originGrantId,
    required int? expectedGrantRevision,
    required DateTime at,
  }) {
    final graph = trustedOperational.automation;
    final job = graph.jobs[requireUuid(jobId)];
    if (job == null || originGrantId != null && job.grantId != originGrantId)
      throw StateError('FORBIDDEN');
    final plan = graph.plans[job.immutablePlanId]!;
    _jobActor(
      originGrantId,
      expectedGrantRevision,
      plan.serverId,
      McpScope.apply,
      at,
    );
    _jobObjectGrant(job.grantId, plan.serverId, McpScope.apply, at);
    _jobTarget(plan);
    if (!const {'queued', 'running'}.contains(job.state) || job.cancelRequested)
      throw StateError('CANCELLED');
    if (job.authority.kind == 'delegation') {
      final delegation = graph.delegations[job.authority.id],
          grant = graph.grants[job.grantId];
      if (delegation == null ||
          grant == null ||
          delegation.revision != job.authority.revision ||
          !delegation.matches(
            grant: grant,
            serverId: plan.serverId,
            profile: plan.key,
            parameters: plan.toJson()['exactParams'] as Map<String, Object?>,
            at: at,
          ))
        throw StateError('FORBIDDEN');
    } else {
      final approval = graph.approvals[job.authority.id];
      // Consent was consumed at admission. Its original plan TTL does not kill
      // a running atomic effect; current actor/target checks still apply.
      if (approval == null ||
          approval.state != 'consumed' ||
          approval.jobId != job.id ||
          approval.planDigest != job.planDigest ||
          approval.grantId != job.grantId)
        throw StateError('FORBIDDEN');
    }
  }

  Future<Map<String, Object?>> mutateTrustedJob(
    JobMutationCommand command, {
    required String? originGrantId,
    required int? expectedGrantRevision,
    required DateTime Function() clock,
    String? verifiedPlanDigest,
  }) {
    _ensure();
    trustedOperational;
    if (_closing) throw StateError('NOT_READY');
    final digest = base64
        .decode(
          _custody.receiptDigestSync(
            _receiptKey,
            command.canonicalRequest(originGrantId),
          ),
        )
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final pending = _pendingAutomation[command.requestId];
    if (pending != null) {
      if (pending.originGrantId != originGrantId) throw StateError('FORBIDDEN');
      if (pending.digest != digest) throw StateError('IDEMPOTENCY_CONFLICT');
      return pending.result.future;
    }
    if (_pendingAutomation.length + _pendingFoundation >= 32)
      throw StateError('RESOURCE_LIMIT');
    final work = _AutomationPending(digest, originGrantId: originGrantId);
    work.result.future.ignore();
    _pendingAutomation[command.requestId] = work;
    final run = _tail.then(
      (_) => _writeJob(
        command,
        originGrantId,
        expectedGrantRevision,
        digest,
        clock,
        verifiedPlanDigest,
      ),
    );
    _tail = run.then<void>(
      (value) {
        _pendingAutomation.remove(command.requestId);
        work.result.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        _pendingAutomation.remove(command.requestId);
        final code =
            error is StateError &&
                const {
                  'FORBIDDEN',
                  'NOT_READY',
                  'VALIDATION',
                  'REVISION_CONFLICT',
                  'IDEMPOTENCY_CONFLICT',
                  'RESOURCE_LIMIT',
                  'PLAN_EXPIRED',
                  'PLAN_STALE',
                  'APPROVAL_REQUIRED',
                  'HOST_BUSY',
                  'STORAGE_BLOCKED',
                }.contains(error.message)
            ? error.message
            : 'STORAGE_BLOCKED';
        if (code == 'STORAGE_BLOCKED') _blocked = true;
        work.result.completeError(StateError(code), stack);
      },
    );
    return work.result.future;
  }

  Future<Map<String, Object?>> _writeJob(
    JobMutationCommand command,
    String? origin,
    int? revision,
    String digest,
    DateTime Function() clock,
    String? verifiedDigest,
  ) async {
    var at = _grantInstant(clock, _AutomationFormat.trusted);
    final previous = _automationView(_AutomationFormat.trusted),
        graph = previous.automation,
        input = command.toJson(),
        applying = command.operation == 'job.apply';
    final existing = applying ? null : graph.jobs[input['jobId']];
    final plan = applying
        ? graph.plans[input['planId']]
        : existing == null
        ? null
        : graph.plans[existing.immutablePlanId];
    if (plan == null ||
        origin != null && plan.toJson()['originGrantId'] != origin)
      throw StateError('FORBIDDEN');
    if (existing != null && existing.updatedAt.isAfter(at))
      at = existing.updatedAt;
    final objectGrant = plan.toJson()['originGrantId'] as String?;
    _jobMutationAuthority(
      command.operation,
      origin,
      revision,
      objectGrant,
      plan.serverId,
      at,
    );
    final oldReceipt = graph.receipts[command.requestId];
    if (oldReceipt != null) {
      if (oldReceipt.originGrantId != origin) throw StateError('FORBIDDEN');
      if (oldReceipt.operation != command.operation ||
          oldReceipt.canonicalDigest != digest)
        throw StateError('IDEMPOTENCY_CONFLICT');
      _authorityUnavailable = true;
      try {
        final loaded = await _reloadGrants(_AutomationFormat.trusted);
        if (!_sameGrantSnapshot(previous, loaded))
          throw StateError('STORAGE_BLOCKED');
        _publishAutomation(loaded);
        _authorityUnavailable = false;
        return oldReceipt.result;
      } catch (_) {
        _blocked = true;
        throw StateError('STORAGE_BLOCKED');
      }
    }
    if (_state.receipts.containsKey(command.requestId))
      throw StateError('IDEMPOTENCY_CONFLICT');
    if (graph.receipts.length >= 10000) throw StateError('RESOURCE_LIMIT');
    final candidate = {
      for (final group in previous.rows.entries)
        group.key: List<AutomationSnapshotRow>.of(group.value),
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

    String unique(Set<String> used) {
      for (var i = 0; i < 8; i++) {
        final id = _grantSecretRef();
        if (!used.contains(id)) return id;
      }
      throw StateError('RESOURCE_LIMIT');
    }

    void event(AutomationJobRecord job, String state) {
      if (graph.events.length >= 10000) return;
      final record = AutomationJobEventRecord.fromJson({
        'workspaceId': _state.workspaceId,
        'jobId': job.id,
        'sequence': job.nextSequence - 1,
        'timestamp': at.toIso8601String(),
        'kind': 'state',
        'stepId': null,
        'state': state,
        'checkResult': null,
        'safeCode': job.outcome?.safeCode,
        'droppedCount': 0,
      });
      put('events', '${job.id}:${record.sequence}', record.toJson());
    }

    Map<String, Object?> result;
    AutomationAuthorityRef? selected;
    var newAdmission = false;
    if (applying) {
      final prior = graph.jobs.values
          .where((job) => job.immutablePlanId == plan.id)
          .firstOrNull;
      if (prior != null) {
        // An acknowledgement alias preserves the canonical original creation.
        result = {
          'jobId': prior.id,
          'planId': plan.id,
          'planDigest': prior.planDigest,
          'authorityRef': prior.authority.toJson(),
        };
      } else {
        if (graph.events.length >= 10000) throw StateError('RESOURCE_LIMIT');
        if (plan.status != 'runnable' ||
            verifiedDigest != plan.toJson()['digest'])
          throw StateError('PLAN_STALE');
        if (!plan.isWithinLifetimeAt(at)) throw StateError('PLAN_EXPIRED');
        _jobTarget(plan);
        final profile = graph.profiles[plan.key.profileId];
        if (profile == null || profile.archived) throw StateError('PLAN_STALE');
        final resources = <String>{
          for (final raw in plan.toJson()['effects'] as List)
            if ((raw as Map)['resourceId'] case final String id) id,
          for (final recipe in plan.preflight!.recipes)
            ...recipe.ownedResources,
        };
        if (graph.desired.values.any(
          (row) =>
              row.serverId == plan.serverId &&
              resources.contains(row.resourceId) &&
              row.desiredRevision >= 2147483647,
        ))
          throw StateError('RESOURCE_LIMIT');
        final active = graph.jobs.values.where(
          (job) => !_terminalJobStates.contains(job.state),
        );
        if (active.length >= 250 || graph.jobs.length >= 1250)
          throw StateError('RESOURCE_LIMIT');
        if (active.any((job) {
          final target = graph.plans[job.immutablePlanId]!;
          return target.serverId == plan.serverId ||
              target.hostId == plan.hostId;
        }))
          throw StateError('HOST_BUSY');
        selected = _jobAuthority(plan, at);
        final job = AutomationJobRecord.fromJson({
          'workspaceId': _state.workspaceId,
          'id': unique(graph.jobs.keys.toSet()),
          'requestId': command.requestId,
          'immutablePlanId': plan.id,
          'planDigest': plan.toJson()['digest'],
          'profileId': plan.key.profileId,
          'profileRevision': plan.key.revision,
          'profileDigest': plan.key.bodyDigest,
          'grantId': objectGrant,
          'authorityRef': selected.toJson(),
          'hostAttemptId': unique(
            graph.jobs.values.map((row) => row.hostAttemptId).toSet(),
          ),
          'state': 'queued',
          'nextSequence': 2,
          'cancelRequested': false,
          'createdAt': at.toIso8601String(),
          'updatedAt': at.toIso8601String(),
          'outcome': null,
        });
        if (selected.kind == 'approval') {
          final approval = graph.approvals[selected.id]!;
          final consumed = AutomationApprovalRecord.fromJson({
            ...approval.toJson(),
            'state': 'consumed',
            'jobId': job.id,
          });
          approval.validateTransitionTo(consumed);
          put('approvals', consumed.id, consumed.toJson());
        }
        put('jobs', job.id, job.toJson());
        event(job, 'queued');
        newAdmission = true;
        result = {
          'jobId': job.id,
          'planId': plan.id,
          'planDigest': job.planDigest,
          'authorityRef': job.authority.toJson(),
        };
      }
    } else {
      final job = existing!;
      if (command.operation == 'job.cancel' &&
          !_terminalJobStates.contains(job.state) &&
          !job.cancelRequested) {
        final state = job.state == 'queued'
            ? 'cancelled'
            : job.state == 'running'
            ? 'cancel-requested'
            : job.state;
        final updated = AutomationJobRecord.fromJson({
          ...job.toJson(),
          'state': state,
          'cancelRequested': true,
          'nextSequence': job.nextSequence + 1,
          'updatedAt': at.toIso8601String(),
          if (state == 'cancelled')
            'outcome': {
              'effects': 'none',
              'checks': [],
              'safeCode': 'CANCELLED',
            },
        });
        job.validateTransitionTo(updated);
        put('jobs', job.id, updated.toJson());
        event(updated, state);
      } else if (command.operation == 'job.reconcile' &&
          job.state == 'unknown') {
        final updated = AutomationJobRecord.fromJson({
          ...job.toJson(),
          'state': 'reconciling',
          'outcome': null,
          'nextSequence': job.nextSequence + 1,
          'updatedAt': at.toIso8601String(),
        });
        job.validateTransitionTo(updated);
        put('jobs', job.id, updated.toJson());
        event(updated, 'reconciling');
      } else if (command.operation == 'job.reconcile' &&
          !{..._terminalJobStates, 'reconciling'}.contains(job.state)) {
        throw StateError('REVISION_CONFLICT');
      }
      result = {'jobId': job.id};
    }
    final receipt = AutomationMutationReceiptRecord.fromJson({
      'workspaceId': _state.workspaceId,
      'requestId': command.requestId,
      'originGrantId': origin,
      'objectGrantId': objectGrant,
      'canonicalDigest': digest,
      'operation': command.operation,
      'result': result,
      'createdAt': at.toIso8601String(),
    });
    put('receipts', command.requestId, receipt.toJson());
    await _commitTrustedDelta(previous, candidate, () {
      final now = _grantInstant(clock, _AutomationFormat.trusted);
      _jobMutationAuthority(
        command.operation,
        origin,
        revision,
        objectGrant,
        plan.serverId,
        now,
      );
      if (newAdmission) {
        if (!plan.isWithinLifetimeAt(now)) throw StateError('PLAN_EXPIRED');
        _jobTarget(plan);
        final AutomationAuthorityRef current;
        try {
          current = _jobAuthority(plan, now);
        } on StateError catch (error) {
          if (error.message == 'APPROVAL_REQUIRED')
            throw StateError('FORBIDDEN');
          rethrow;
        }
        if (!current.sameAs(selected!)) throw StateError('FORBIDDEN');
      }
    });
    return receipt.result;
  }
}
