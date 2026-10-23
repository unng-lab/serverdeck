part of 'state_store.dart';

/// Fixed native collections only. No caller path/schema/SQL or delete API.
extension _TrustedAutomationDelta on StateStore {
  Future<AutomationSnapshotRow?> _nativeAutomationRow(
    String group,
    int id,
  ) async {
    AutomationSnapshotRow? row(dynamic value) => value == null
        ? null
        : AutomationSnapshotRow(
            value.id as int,
            value.entityId as String,
            value.payload as String,
          );
    return row(await switch (group) {
      'delegations' => _isar.storedDelegations.get(id),
      'approvals' => _isar.storedAutomationApprovals.get(id),
      'jobs' => _isar.storedAutomationJobs.get(id),
      'events' => _isar.storedAutomationEvents.get(id),
      'desired' => _isar.storedDesiredStates.get(id),
      'receipts' => _isar.storedAutomationReceipts.get(id),
      _ => throw StateError('STORAGE_BLOCKED'),
    });
  }

  Future<AutomationSnapshotRow?> _nativeAutomationKey(
    String group,
    String key,
  ) async {
    AutomationSnapshotRow? row(dynamic value) => value == null
        ? null
        : AutomationSnapshotRow(
            value.id as int,
            value.entityId as String,
            value.payload as String,
          );
    return row(await switch (group) {
      'delegations' => _isar.storedDelegations.getByEntityId(key),
      'approvals' => _isar.storedAutomationApprovals.getByEntityId(key),
      'jobs' => _isar.storedAutomationJobs.getByEntityId(key),
      'events' => _isar.storedAutomationEvents.getByEntityId(key),
      'desired' => _isar.storedDesiredStates.getByEntityId(key),
      'receipts' => _isar.storedAutomationReceipts.getByEntityId(key),
      _ => throw StateError('STORAGE_BLOCKED'),
    });
  }

  Future<void> _putNativeAutomation(
    String group,
    AutomationSnapshotRow row,
  ) async {
    final result = await switch (group) {
      'delegations' => _isar.storedDelegations.put(
        StoredDelegation()
          ..id = row.nativeId
          ..entityId = row.entityId
          ..payload = row.payload,
      ),
      'approvals' => _isar.storedAutomationApprovals.put(
        StoredAutomationApproval()
          ..id = row.nativeId
          ..entityId = row.entityId
          ..payload = row.payload,
      ),
      'jobs' => _isar.storedAutomationJobs.put(
        StoredAutomationJob()
          ..id = row.nativeId
          ..entityId = row.entityId
          ..payload = row.payload,
      ),
      'events' => _isar.storedAutomationEvents.put(
        StoredAutomationEvent()
          ..id = row.nativeId
          ..entityId = row.entityId
          ..payload = row.payload,
      ),
      'desired' => _isar.storedDesiredStates.put(
        StoredDesiredState()
          ..id = row.nativeId
          ..entityId = row.entityId
          ..payload = row.payload,
      ),
      'receipts' => _isar.storedAutomationReceipts.put(
        StoredAutomationReceipt()
          ..id = row.nativeId
          ..entityId = row.entityId
          ..payload = row.payload,
      ),
      _ => throw StateError('STORAGE_BLOCKED'),
    };
    if (result != row.nativeId) throw StateError('STORAGE_BLOCKED');
  }

  Future<void> _commitTrustedDelta(
    _AutomationView previous,
    Map<String, List<AutomationSnapshotRow>> candidate,
    void Function() policy,
  ) async {
    var bytes = previous.foundationPayloadBytes;
    final changed = <String, List<AutomationSnapshotRow>>{};
    for (final group in candidate.entries) {
      final old = {
        for (final row in previous.rows[group.key]!) row.nativeId: row,
      };
      if (old.keys.any((id) => !group.value.any((row) => row.nativeId == id)))
        throw StateError('STORAGE_BLOCKED');
      for (final row in group.value) {
        bytes += utf8.encode(row.payload).length;
        if (bytes > 64 << 20) throw StateError('RESOURCE_LIMIT');
        final was = old[row.nativeId];
        if (was == null ||
            was.entityId != row.entityId ||
            was.payload != row.payload)
          (changed[group.key] ??= []).add(row);
      }
    }
    await previous.validate(candidate);
    policy();
    var entered = false, committed = false;
    try {
      _authorityUnavailable = true;
      await _isar.writeTxn(() async {
        entered = true;
        policy();
        for (final group in changed.entries) {
          for (final row in group.value) {
            final old = previous.rows[group.key]!
                .where((value) => value.nativeId == row.nativeId)
                .firstOrNull;
            final actual = await _nativeAutomationRow(group.key, row.nativeId);
            final byKey = await _nativeAutomationKey(group.key, row.entityId);
            if (old == null
                ? actual != null || byKey != null
                : actual == null ||
                      byKey == null ||
                      actual.payload != old.payload ||
                      actual.entityId != old.entityId ||
                      byKey.nativeId != old.nativeId)
              throw StateError('STORAGE_BLOCKED');
            await _putNativeAutomation(group.key, row);
          }
        }
        _grantLive(_AutomationFormat.trusted);
      });
      committed = true;
      final loaded = await _reloadGrants(_AutomationFormat.trusted);
      if (!previous.sameFoundation(loaded)) throw StateError('STORAGE_BLOCKED');
      for (final group in candidate.entries) {
        final actual = {
          for (final row in loaded.rows[group.key]!) row.nativeId: row,
        };
        if (actual.length != group.value.length)
          throw StateError('STORAGE_BLOCKED');
        for (final row in group.value) {
          final value = actual[row.nativeId];
          if (value == null ||
              value.entityId != row.entityId ||
              value.payload != row.payload)
            throw StateError('STORAGE_BLOCKED');
        }
      }
      _publishAutomation(loaded);
      _authorityUnavailable = false;
    } catch (error) {
      final policyCode =
          error is StateError &&
              const {
                'FORBIDDEN',
                'PLAN_EXPIRED',
                'PLAN_STALE',
              }.contains(error.message)
          ? error.message
          : null;
      if (entered &&
          !committed &&
          (isNativeCapacityFailure(error) || policyCode != null)) {
        try {
          final restored = await _reloadGrants(_AutomationFormat.trusted);
          if (!_sameGrantSnapshot(previous, restored))
            throw StateError('STORAGE_BLOCKED');
          _publishAutomation(restored);
          _authorityUnavailable = false;
        } catch (_) {
          _blocked = true;
          throw StateError('STORAGE_BLOCKED');
        }
        throw StateError(policyCode ?? 'RESOURCE_LIMIT');
      }
      _blocked = true;
      throw StateError('STORAGE_BLOCKED');
    }
  }
}
