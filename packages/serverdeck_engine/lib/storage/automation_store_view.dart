part of 'state_store.dart';

const _automationGroups = {
  'grants': 'StoredMcpGrant',
  'delegations': 'StoredDelegation',
  'profiles': 'StoredAutomationProfile',
  'revisions': 'StoredAutomationRevision',
  'plans': 'StoredAutomationPlan',
  'approvals': 'StoredAutomationApproval',
  'jobs': 'StoredAutomationJob',
  'desired': 'StoredDesiredState',
  'events': 'StoredAutomationEvent',
  'receipts': 'StoredAutomationReceipt',
};
const _foundationGroups = {
  'StoredWorkspace',
  'StoredSettings',
  'StoredProfile',
  'StoredCredential',
  'StoredReceipt',
  'StoredHostTrust',
};

final class _AutomationView {
  _AutomationView(this.snapshot);
  final WorkspaceSnapshot snapshot;
  AutomationSnapshot get automation => snapshot.automation;
  late final Map<String, List<AutomationSnapshotRow>> rows = Map.unmodifiable({
    for (final group in _automationGroups.entries)
      group.key: List<AutomationSnapshotRow>.unmodifiable([
        for (final row in snapshot.rows[group.value]!)
          AutomationSnapshotRow(row.nativeId, row.entityId!, row.payload),
      ]),
  });
  int get foundationPayloadBytes => _foundationGroups.fold(
    0,
    (n, name) =>
        n +
        snapshot.rows[name]!.fold(
          0,
          (n, row) => n + utf8.encode(row.payload).length,
        ),
  );
  bool sameFoundation(_AutomationView other) {
    for (final name in _foundationGroups) {
      final left = snapshot.rows[name]!, right = other.snapshot.rows[name]!;
      if (left.length != right.length) return false;
      for (var i = 0; i < left.length; i++) {
        if (left[i].nativeId != right[i].nativeId ||
            left[i].entityId != right[i].entityId ||
            left[i].payload != right[i].payload)
          return false;
      }
    }
    return true;
  }

  Future<AutomationSnapshot> validate(
    Map<String, List<AutomationSnapshotRow>> candidate,
  ) => AutomationSnapshot.load(
    foundation: snapshot.foundation,
    collections: candidate,
  );
}

extension _AutomationStoreViews on StateStore {
  _AutomationView _automationView() => _AutomationView(_snapshot);
  void _publishAutomation(_AutomationView value) {
    _snapshot = value.snapshot;
  }

  Future<_AutomationView> _reloadGrants() async {
    await _runtimeLive();
    final current = _AutomationView(
      await readWorkspaceSnapshot(
        _storage,
        _receiptKey,
        _custody,
        localAppData: _localAppData,
        lease: _lease,
        protectedFiles: _files,
      ),
    );
    await _runtimeLive();
    return current;
  }
}
