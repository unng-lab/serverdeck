part of 'state_store.dart';

/// Selected by fixed store entry points, never a public/wire schema option.
enum _AutomationFormat { operational, trusted }

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
  _AutomationView.operational(OperationalSnapshot value)
    : operational = value,
      trusted = null;
  _AutomationView.trusted(TrustedOperationalSnapshot value)
    : trusted = value,
      operational = null;
  final OperationalSnapshot? operational;
  final TrustedOperationalSnapshot? trusted;
  AutomationSnapshot get automation =>
      operational?.automation ?? trusted!.automation;
  late final Map<String, List<AutomationSnapshotRow>> rows =
      operational?.rows ??
      Map.unmodifiable({
        for (final group in _automationGroups.entries)
          group.key: List<AutomationSnapshotRow>.unmodifiable([
            for (final r in trusted!.rows[group.value]!)
              AutomationSnapshotRow(r.nativeId, r.entityId!, r.payload),
          ]),
      });

  // Preserve the schema2 admission rule; schema3 accounts for all16 payloads.
  int get foundationPayloadBytes => trusted == null
      ? 0
      : _foundationGroups.fold(
          0,
          (n, name) =>
              n +
              trusted!.rows[name]!.fold(
                0,
                (n, r) => n + utf8.encode(r.payload).length,
              ),
        );

  bool sameFoundation(_AutomationView other) {
    if (operational != null)
      return other.operational != null &&
          operational!.foundation.rows.digest() ==
              other.operational!.foundation.rows.digest();
    if (other.trusted == null) return false;
    for (final name in _foundationGroups) {
      final left = trusted!.rows[name]!, right = other.trusted!.rows[name]!;
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
  ) => trusted != null
      ? AutomationSnapshot.loadTrusted(
          foundation: trusted!.foundation,
          collections: candidate,
        )
      : AutomationSnapshot.load(
          foundation: operational!.foundation.state,
          collections: candidate,
        );
}

extension _AutomationStoreViews on StateStore {
  bool _hasAutomation(_AutomationFormat format) => switch (format) {
    _AutomationFormat.operational => _operational != null,
    _AutomationFormat.trusted => _trustedOperational != null,
  };
  _AutomationView _automationView(_AutomationFormat format) => switch (format) {
    _AutomationFormat.operational when _operational != null =>
      _AutomationView.operational(_operational!),
    _AutomationFormat.trusted when _trustedOperational != null =>
      _AutomationView.trusted(_trustedOperational!),
    _ => throw StateError('STORAGE_BLOCKED'),
  };
  void _publishAutomation(_AutomationView value) {
    if (value.trusted != null &&
        _trustedOperational != null &&
        _operational == null) {
      _trustedOperational = value.trusted;
    } else if (value.operational != null &&
        _operational != null &&
        _trustedOperational == null) {
      _operational = value.operational;
    } else {
      throw StateError('STORAGE_BLOCKED');
    }
  }

  Future<_AutomationView> _reloadGrants(_AutomationFormat format) async {
    _grantLive(format);
    final current = switch (format) {
      _AutomationFormat.operational => _AutomationView.operational(
        await readOperationalSnapshot(
          _isar,
          _receiptKey,
          _custody,
          localAppData: _operationalRoot!,
          lease: _lease,
        ),
      ),
      _AutomationFormat.trusted => _AutomationView.trusted(
        await readTrustedOperationalSnapshot(
          _isar,
          _receiptKey,
          _custody,
          localAppData: _operationalRoot!,
          lease: _lease,
        ),
      ),
    };
    _grantLive(format);
    return current;
  }
}
