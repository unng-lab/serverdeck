part of 'state_store.dart';

extension TrustedAuthorityWrites on StateStore {
  void _authorityInitiator(String? origin, int? revision, DateTime at) {
    _grantLive(_AutomationFormat.trusted);
    if (origin == null) return;
    final grant = _automationView(_AutomationFormat.trusted)
        .automation
        .grants[origin];
    if (grant == null ||
        grant.revision != revision ||
        !grant.isCurrentAt(at) ||
        !grant.policy.allowsScope(McpScope.apply))
      throw StateError('FORBIDDEN');
  }

  void _authorityObjectGrant(String? grantId, String server, DateTime at) {
    if (grantId == null) return;
    final grant = _automationView(_AutomationFormat.trusted)
        .automation
        .grants[grantId];
    if (grant == null ||
        !grant.isCurrentAt(at) ||
        !grant.policy.allowsScope(McpScope.apply) ||
        !grant.policy.allowsServer(server))
      throw StateError('FORBIDDEN');
  }

  Future<Map<String, Object?>> mutateTrustedAuthority(
    AutomationAuthorityCommand command, {
    required String? originGrantId,
    required int? expectedGrantRevision,
    required DateTime Function() clock,
  }) {
    _ensure();
    trustedOperational;
    if (_closing) throw StateError('NOT_READY');
    if (command.ownerOnly && originGrantId != null)
      throw StateError('FORBIDDEN');
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
      (_) => _writeAuthority(
        command,
        originGrantId,
        expectedGrantRevision,
        digest,
        clock,
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
                  'NOT_FOUND',
                  'VALIDATION',
                  'REVISION_CONFLICT',
                  'IDEMPOTENCY_CONFLICT',
                  'RESOURCE_LIMIT',
                  'PLAN_EXPIRED',
                  'PLAN_STALE',
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

  Future<Map<String, Object?>> _writeAuthority(
    AutomationAuthorityCommand command,
    String? origin,
    int? grantRevision,
    String digest,
    DateTime Function() clock,
  ) async {
    final at = _grantInstant(clock, _AutomationFormat.trusted);
    _authorityInitiator(origin, grantRevision, at);
    final previous = _automationView(_AutomationFormat.trusted),
        graph = previous.automation;
    final input = command.toJson();
    final oldReceipt = graph.receipts[command.requestId];
    if (oldReceipt != null) {
      if (oldReceipt.originGrantId != origin) throw StateError('FORBIDDEN');
      if (oldReceipt.operation != command.operation ||
          oldReceipt.canonicalDigest != digest)
        throw StateError('IDEMPOTENCY_CONFLICT');
      if (command.operation.startsWith('approval.')) {
        final approval = graph.approvals[oldReceipt.result['approvalId']];
        if (approval == null) throw StateError('STORAGE_BLOCKED');
        _authorityObjectGrant(
          approval.grantId,
          graph.plans[approval.planId]!.serverId,
          at,
        );
      }
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
      final rows = candidate[group]!;
      final index = rows.indexWhere((row) => row.entityId == key);
      final row = AutomationSnapshotRow(
        index < 0 ? _nextGrantNativeId(rows) : rows[index].nativeId,
        key,
        utf8.decode(StrictCodec().canonical(value)),
      );
      if (index < 0)
        rows.add(row);
      else
        rows[index] = row;
    }

    String unique(Set<String> ids) {
      for (var attempt = 0; attempt < 8; attempt++) {
        final id = _grantSecretRef();
        if (!ids.contains(id)) return id;
      }
      throw StateError('RESOURCE_LIMIT');
    }

    String? objectGrant;
    String? policyServer;
    Map<String, Object?> result;
    switch (command.operation) {
      case 'delegation.create':
        if (graph.delegations.length >= 1000)
          throw StateError('RESOURCE_LIMIT');
        final grant = graph.grants[input['grantId']];
        if (grant == null) throw StateError('FORBIDDEN');
        if (!grant.isCurrentAt(at) ||
            !grant.policy.allowsScope(McpScope.apply) ||
            !grant.policy.serverIds.containsAll(
              (input['serverIds'] as List).cast<String>(),
            ) ||
            at
                .add(Duration(seconds: input['lifetimeSeconds'] as int))
                .isAfter(grant.expiresAt))
          throw StateError('FORBIDDEN');
        objectGrant = grant.id;
        for (final raw in input['profileRevisions'] as List) {
          final key = AutomationRevisionKey.fromJson(
            raw as Map<String, Object?>,
          );
          final revision = graph.revisions['${key.profileId}:${key.revision}'];
          if (revision == null || revision.key != key)
            throw StateError('REVISION_CONFLICT');
          if (graph.profiles[key.profileId]!.archived)
            throw StateError('VALIDATION');
          final definitions =
              revision.body.toJson()['parameters'] as Map<String, Object?>;
          final predicates = input['predicates'] as Map<String, Object?>;
          if (definitions.length != predicates.length ||
              !definitions.keys.every(predicates.containsKey))
            throw StateError('VALIDATION');
          for (final entry in definitions.entries) {
            final definition = entry.value as Map<String, Object?>;
            final constraint = ParameterConstraint.fromJson(
              predicates[entry.key] as Map<String, Object?>,
            );
            final bool valid;
            if (constraint is IntegerConstraint) {
              valid =
                  definition['type'] == 'integer' &&
                  constraint.minimum >= (definition['minimum'] as int) &&
                  constraint.maximum <= (definition['maximum'] as int);
            } else if (constraint is EnumConstraint) {
              valid = constraint.values.every(
                (value) => switch (definition['type']) {
                  'boolean' => value is bool,
                  'integer' =>
                    value is int &&
                        value >= (definition['minimum'] as int) &&
                        value <= (definition['maximum'] as int),
                  'enum' =>
                    value is String &&
                        (definition['values'] as List).contains(value),
                  'string' =>
                    value is String &&
                        value.runes.length <= (definition['maxLength'] as int),
                  _ => false,
                },
              );
            } else {
              valid = false;
            }
            if (!valid) throw StateError('VALIDATION');
          }
          if (at.isBefore(revision.createdAt)) throw StateError('VALIDATION');
        }
        final delegation = DelegationRecord.fromJson({
          'workspaceId': _state.workspaceId,
          'id': unique(graph.delegations.keys.toSet()),
          'grantId': grant.id,
          'revision': 1,
          'serverIds': input['serverIds'],
          'profileRevisions': input['profileRevisions'],
          'predicates': input['predicates'],
          'expiresAt': DelegationRecord.expiryFor(
            at,
            grant: grant,
            lifetime: Duration(seconds: input['lifetimeSeconds'] as int),
          ).toIso8601String(),
          'revokedAt': null,
        });
        try {
          delegation.validateForGrant(grant, issuedAt: at);
        } on FormatException {
          throw StateError('FORBIDDEN');
        }
        if (delegation.serverIds.any(
          (server) => !_state.profiles.containsKey(server),
        ))
          throw StateError('VALIDATION');
        put('delegations', delegation.id, delegation.toJson());
        result = {'delegationId': delegation.id, 'revision': 1};
      case 'delegation.revoke':
        final delegation = graph.delegations[input['delegationId']];
        if (delegation == null) throw StateError('NOT_FOUND');
        objectGrant = delegation.grantId;
        if (delegation.revision != input['expectedRevision'] ||
            delegation.revokedAt != null)
          throw StateError('REVISION_CONFLICT');
        final issued = graph.receipts.values
            .where(
              (row) =>
                  row.operation == 'delegation.create' &&
                  row.result['delegationId'] == delegation.id,
            )
            .single
            .createdAt;
        if (at.isBefore(issued)) throw StateError('VALIDATION');
        final value = DelegationRecord.fromJson({
          ...delegation.toJson(),
          'revision': 2,
          'revokedAt': at.toIso8601String(),
        });
        put('delegations', value.id, value.toJson());
        result = {'delegationId': value.id, 'revision': 2};
      case 'approval.request':
        final plan = graph.plans[input['planId']];
        if (plan == null ||
            origin != null && plan.toJson()['originGrantId'] != origin)
          throw StateError('FORBIDDEN');
        if (plan.status != 'runnable') throw StateError('PLAN_STALE');
        if (!at.isBefore(plan.expiresAt)) throw StateError('PLAN_EXPIRED');
        if (at.isBefore(plan.createdAt)) throw StateError('VALIDATION');
        policyServer = plan.serverId;
        objectGrant = plan.toJson()['originGrantId'] as String?;
        _authorityObjectGrant(objectGrant, plan.serverId, at);
        final server = _state.profiles[plan.serverId];
        if (server == null ||
            server.revision != plan.serverRevision ||
            server.connectionRevision != plan.connectionRevision ||
            server.credentialRevision != plan.accessRevision ||
            server.trustRevision != plan.trustRevision)
          throw StateError('PLAN_STALE');
        if (graph.approvals.length >= 100) throw StateError('RESOURCE_LIMIT');
        final approval = AutomationApprovalRecord.fromJson({
          'workspaceId': _state.workspaceId,
          'id': unique(graph.approvals.keys.toSet()),
          'planId': plan.id,
          'planDigest': plan.toJson()['digest'],
          'grantId': objectGrant,
          'createdAt': at.toIso8601String(),
          'expiresAt': plan.expiresAt.toIso8601String(),
          'state': 'pending',
          'jobId': null,
        });
        put('approvals', approval.id, approval.toJson());
        result = {
          'approvalId': approval.id,
          'planId': plan.id,
          'planDigest': approval.planDigest,
        };
      case 'approval.decide':
        final approval = graph.approvals[input['approvalId']];
        if (approval == null) throw StateError('NOT_FOUND');
        final plan = graph.plans[approval.planId]!;
        objectGrant = approval.grantId;
        policyServer = plan.serverId;
        if (input['planDigest'] != approval.planDigest)
          throw StateError('REVISION_CONFLICT');
        _authorityObjectGrant(objectGrant, plan.serverId, at);
        if (!at.isBefore(approval.expiresAt) || !at.isBefore(plan.expiresAt))
          throw StateError('PLAN_EXPIRED');
        if (at.isBefore(approval.createdAt)) throw StateError('VALIDATION');
        final decision = input['decision'] as String;
        final same = decision == 'approved'
            ? const {'approved', 'consumed'}.contains(approval.state)
            : approval.state == 'denied';
        if (approval.state != 'pending' && !same)
          throw StateError('REVISION_CONFLICT');
        if (approval.state == 'pending') {
          final next = AutomationApprovalRecord.fromJson({
            ...approval.toJson(),
            'state': decision,
          });
          approval.validateTransitionTo(next);
          put('approvals', next.id, next.toJson());
        }
        result = {
          'approvalId': approval.id,
          'planId': approval.planId,
          'planDigest': approval.planDigest,
          'decision': decision,
        };
      default:
        throw StateError('VALIDATION');
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
      _authorityInitiator(origin, grantRevision, now);
      if (policyServer != null)
        _authorityObjectGrant(objectGrant, policyServer, now);
      if (command.operation.startsWith('approval.')) {
        final plan = command.operation == 'approval.request'
            ? graph.plans[input['planId']]!
            : graph.plans[graph.approvals[input['approvalId']]!.planId]!;
        if (!now.isBefore(plan.expiresAt)) throw StateError('PLAN_EXPIRED');
      }
      if (command.operation == 'delegation.create') {
        final grant = graph.grants[objectGrant]!;
        if (!grant.isCurrentAt(now) ||
            !grant.policy.allowsScope(McpScope.apply))
          throw StateError('FORBIDDEN');
      }
    });
    return receipt.result;
  }
}
