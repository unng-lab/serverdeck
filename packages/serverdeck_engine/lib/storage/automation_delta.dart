part of 'state_store.dart';

/// Fixed schema3 collections only. No caller path/schema/query or delete API.
extension _TrustedAutomationDelta on StateStore {
  WorkspaceCollection _automationCollection(String group) => switch (group) {
    'delegations' => WorkspaceCollection.delegations,
    'approvals' => WorkspaceCollection.approvals,
    'jobs' => WorkspaceCollection.jobs,
    'events' => WorkspaceCollection.events,
    'desired' => WorkspaceCollection.desired,
    'receipts' => WorkspaceCollection.automationReceipts,
    _ => throw StateError('STORAGE_BLOCKED'),
  };

  AutomationSnapshotRow? _snapshotRow(StoredRow? row) => row == null
      ? null
      : AutomationSnapshotRow(row.nativeId, row.entityId!, row.payload);

  Future<AutomationSnapshotRow?> _automationRow(
    WorkspaceWriteTransaction tx,
    String group,
    int id,
  ) async => _snapshotRow(await tx.get(_automationCollection(group), id));

  Future<AutomationSnapshotRow?> _automationKey(
    WorkspaceWriteTransaction tx,
    String group,
    String key,
  ) async =>
      _snapshotRow(await tx.getByEntityId(_automationCollection(group), key));

  Future<void> _putAutomationRow(
    WorkspaceWriteTransaction tx,
    String group,
    AutomationSnapshotRow row,
  ) async {
    final result = await tx.put(
      _automationCollection(group),
      StoredRow(row.nativeId, row.payload, entityId: row.entityId),
    );
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
      await _writeStorage((tx) async {
        entered = true;
        policy();
        for (final group in changed.entries) {
          for (final row in group.value) {
            final old = previous.rows[group.key]!
                .where((value) => value.nativeId == row.nativeId)
                .firstOrNull;
            final actual = await _automationRow(tx, group.key, row.nativeId);
            final byKey = await _automationKey(tx, group.key, row.entityId);
            if (old == null
                ? actual != null || byKey != null
                : actual == null ||
                      byKey == null ||
                      actual.payload != old.payload ||
                      actual.entityId != old.entityId ||
                      byKey.nativeId != old.nativeId)
              throw StateError('STORAGE_BLOCKED');
            await _putAutomationRow(tx, group.key, row);
          }
        }
        // Native reads/puts may have waited after the entry check. Revalidate
        // the exact live policy before allowing this transaction to finish;
        // failure here must roll back every row, including dispatch intent.
        policy();
        _grantLive();
      });
      committed = true;
      final loaded = await _reloadGrants();
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
          (_storage.isCapacityFailure(error) || policyCode != null)) {
        try {
          final restored = await _reloadGrants();
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
