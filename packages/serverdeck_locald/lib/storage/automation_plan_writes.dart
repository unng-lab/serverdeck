part of 'state_store.dart';

extension TrustedPlanWrites on StateStore {
  String _planRequestDigest(PlanCreateCommand command, String? origin) => base64
      .decode(
        _custody.receiptDigestSync(
          _receiptKey,
          command.canonicalRequest(origin),
        ),
      )
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  void _planInitiator(
    String? origin,
    int? grantRevision,
    String server,
    DateTime at,
  ) {
    _grantLive(_AutomationFormat.trusted);
    if (origin == null) return;
    final grant = _automationView(_AutomationFormat.trusted)
        .automation
        .grants[origin];
    if (grant == null ||
        grant.revision != grantRevision ||
        !grant.isCurrentAt(at) ||
        !grant.policy.allowsScope(McpScope.plan) ||
        !grant.policy.allowsServer(server))
      throw StateError('FORBIDDEN');
  }

  /// Receipt replay verifies the actual retained native graph before ACK.
  Future<Map<String, Object?>?> replayTrustedPlan(
    PlanCreateCommand command, {
    required String? originGrantId,
    required int? expectedGrantRevision,
    required DateTime at,
  }) => _queueTrustedMetadata(
    () =>
        _verifiedPlanReplay(command, originGrantId, expectedGrantRevision, at),
  );

  Map<String, Object?>? _findPlanReceipt(
    PlanCreateCommand command,
    String? originGrantId,
    int? expectedGrantRevision,
    DateTime at,
  ) {
    _planInitiator(originGrantId, expectedGrantRevision, command.serverId, at);
    final receipt = _automationView(_AutomationFormat.trusted)
        .automation
        .receipts[command.requestId];
    if (receipt == null) {
      if (_state.receipts.containsKey(command.requestId))
        throw StateError('IDEMPOTENCY_CONFLICT');
      return null;
    }
    if (receipt.originGrantId != originGrantId) throw StateError('FORBIDDEN');
    if (receipt.operation != 'plan.create' ||
        receipt.canonicalDigest != _planRequestDigest(command, originGrantId))
      throw StateError('IDEMPOTENCY_CONFLICT');
    return receipt.result;
  }

  Future<Map<String, Object?>?> _verifiedPlanReplay(
    PlanCreateCommand command,
    String? origin,
    int? revision,
    DateTime at,
  ) async {
    final receipt = _findPlanReceipt(command, origin, revision, at);
    if (receipt == null) return null;
    final previous = _automationView(_AutomationFormat.trusted);
    _authorityUnavailable = true;
    try {
      final loaded = await _reloadGrants(_AutomationFormat.trusted);
      if (!_sameGrantSnapshot(previous, loaded))
        throw StateError('STORAGE_BLOCKED');
      _publishAutomation(loaded);
      _authorityUnavailable = false;
      return receipt;
    } catch (_) {
      _blocked = true;
      throw StateError('STORAGE_BLOCKED');
    }
  }

  /// Same protected queue/native readback as profile writes. A structural plan
  /// is never execution authority; admission must independently recompile it.
  Future<Map<String, Object?>> persistTrustedPlan(
    PlanCreateCommand command,
    AutomationPlanRecord plan, {
    required String? originGrantId,
    required int? expectedGrantRevision,
    required DateTime Function() clock,
  }) {
    _ensure();
    trustedOperational;
    if (_closing) throw StateError('NOT_READY');
    final digest = _planRequestDigest(command, originGrantId);
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
      (_) => _persistPlan(
        command,
        plan,
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
                  'NOT_READY',
                  'FORBIDDEN',
                  'VALIDATION',
                  'PLAN_STALE',
                  'PLAN_EXPIRED',
                  'REVISION_CONFLICT',
                  'IDEMPOTENCY_CONFLICT',
                  'RESOURCE_LIMIT',
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

  Future<Map<String, Object?>> _persistPlan(
    PlanCreateCommand command,
    AutomationPlanRecord plan,
    String? origin,
    int? grantRevision,
    String digest,
    DateTime Function() clock,
  ) async {
    final at = _grantInstant(clock, _AutomationFormat.trusted);
    final replay = await _verifiedPlanReplay(
      command,
      origin,
      grantRevision,
      at,
    );
    if (replay != null) return replay;
    final previous = _automationView(_AutomationFormat.trusted),
        graph = previous.automation;
    final metadata = graph.profiles[command.profileId];
    final revision =
        graph.revisions['${command.profileId}:${command.revision}'];
    if (metadata == null || metadata.archived || revision == null)
      throw StateError('FORBIDDEN');
    final document = plan.toJson();
    if (document['requestId'] != command.requestId ||
        document['originGrantId'] != origin ||
        plan.workspaceId != _state.workspaceId ||
        plan.serverId != command.serverId ||
        plan.key != revision.key ||
        StrictCodec().canonical(document['exactParams']).toString() !=
            StrictCodec()
                .canonical(revision.body.resolveParameters(command.parameters))
                .toString())
      throw StateError('VALIDATION');
    if (at.isBefore(plan.createdAt) || !at.isBefore(plan.expiresAt))
      throw StateError('PLAN_EXPIRED');
    final server = _state.profiles[plan.serverId];
    if (server == null ||
        server.revision != plan.serverRevision ||
        server.connectionRevision != plan.connectionRevision ||
        server.credentialRevision != plan.accessRevision ||
        server.trustRevision != plan.trustRevision)
      throw StateError('PLAN_STALE');
    if (graph.plans.length >= 1000 ||
        graph.receipts.length >= 10000 ||
        graph.plans.containsKey(plan.id))
      throw StateError('RESOURCE_LIMIT');
    await AutomationPlanRecord.fromTrustedJson(document, revision: revision);
    final receipt = AutomationMutationReceiptRecord.fromJson({
      'workspaceId': _state.workspaceId,
      'requestId': command.requestId,
      'originGrantId': origin,
      'objectGrantId': origin,
      'canonicalDigest': digest,
      'operation': 'plan.create',
      'result': {'planId': plan.id, 'planDigest': document['digest']},
      'createdAt': at.toIso8601String(),
    });
    AutomationSnapshotRow row(int id, String key, Map<String, Object?> value) =>
        AutomationSnapshotRow(
          id,
          key,
          utf8.decode(StrictCodec().canonical(value)),
        );
    final planRow = row(
      _nextGrantNativeId(previous.rows['plans']!),
      plan.id,
      document,
    );
    final receiptRow = row(
      _nextGrantNativeId(previous.rows['receipts']!),
      command.requestId,
      receipt.toJson(),
    );
    final candidate = {
      for (final group in previous.rows.entries)
        group.key: List<AutomationSnapshotRow>.of(group.value),
    };
    candidate['plans']!.add(planRow);
    candidate['receipts']!.add(receiptRow);
    var bytes = previous.foundationPayloadBytes;
    for (final rows in candidate.values) {
      for (final value in rows) {
        bytes += utf8.encode(value.payload).length;
        if (bytes > 64 << 20) throw StateError('RESOURCE_LIMIT');
      }
    }
    await previous.validate(candidate);
    var entered = false, committed = false;
    try {
      _authorityUnavailable = true;
      await _isar.writeTxn(() async {
        entered = true;
        _planInitiator(
          origin,
          grantRevision,
          plan.serverId,
          _grantInstant(clock, _AutomationFormat.trusted),
        );
        if (await _isar.storedAutomationPlans.getByEntityId(plan.id) != null ||
            await _isar.storedAutomationPlans.get(planRow.nativeId) != null ||
            await _isar.storedAutomationReceipts.getByEntityId(
                  command.requestId,
                ) !=
                null ||
            await _isar.storedAutomationReceipts.get(receiptRow.nativeId) !=
                null)
          throw StateError('STORAGE_BLOCKED');
        if (await _isar.storedAutomationPlans.put(
                  StoredAutomationPlan()
                    ..id = planRow.nativeId
                    ..entityId = planRow.entityId
                    ..payload = planRow.payload,
                ) <
                1 ||
            await _isar.storedAutomationReceipts.put(
                  StoredAutomationReceipt()
                    ..id = receiptRow.nativeId
                    ..entityId = receiptRow.entityId
                    ..payload = receiptRow.payload,
                ) <
                1)
          throw StateError('STORAGE_BLOCKED');
        _grantLive(_AutomationFormat.trusted);
      });
      committed = true;
      final loaded = await _reloadGrants(_AutomationFormat.trusted);
      if (!previous.sameFoundation(loaded)) throw StateError('STORAGE_BLOCKED');
      for (final group in candidate.entries) {
        final actual = {
          for (final value in loaded.rows[group.key]!) value.nativeId: value,
        };
        if (actual.length != group.value.length)
          throw StateError('STORAGE_BLOCKED');
        for (final expected in group.value) {
          final value = actual[expected.nativeId];
          if (value == null ||
              value.entityId != expected.entityId ||
              value.payload != expected.payload)
            throw StateError('STORAGE_BLOCKED');
        }
      }
      _publishAutomation(loaded);
      _authorityUnavailable = false;
      return receipt.result;
    } catch (error) {
      final denied = error is StateError && error.message == 'FORBIDDEN';
      if (entered && !committed && (isNativeCapacityFailure(error) || denied)) {
        final restored = await _reloadGrants(_AutomationFormat.trusted);
        if (!_sameGrantSnapshot(previous, restored)) {
          _blocked = true;
          throw StateError('STORAGE_BLOCKED');
        }
        _publishAutomation(restored);
        _authorityUnavailable = false;
        throw StateError(denied ? 'FORBIDDEN' : 'RESOURCE_LIMIT');
      }
      _blocked = true;
      throw StateError('STORAGE_BLOCKED');
    }
  }
}
