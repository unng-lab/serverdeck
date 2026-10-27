part of 'state_store.dart';

extension TrustedFoundationWrites on StateStore {
  /// Internal schema3 primitive. The shared service owns authorization, receipt
  /// HMAC/replay, trust transition/challenge rules and its native target lease
  /// BEFORE queue admission. This entry never enables schema2 services on3.
  Future<void> commitTrustedFoundation(HostTrustState next) {
    try {
      _ensure();
      trustedOperational;
      if (_pendingFoundation + _pendingAutomation.length >= 32)
        throw StateError('RESOURCE_LIMIT');
      _pendingFoundation++;
      final result = _tail.then((_) => _commitTrustedFoundation(next));
      _tail = result.then<void>(
        (_) {
          _pendingFoundation--;
        },
        onError: (Object _, StackTrace __) {
          _pendingFoundation--;
        },
      );
      return result;
    } catch (error, stack) {
      return Future.error(error, stack);
    }
  }

  Future<void> _commitTrustedFoundation(HostTrustState next) async {
    _ensure();
    final retained = trustedOperational,
        current = retained.foundation.foundation;
    final state = next.foundation, codec = StrictCodec();
    if (state.storeRevision != nextRevision(current.storeRevision))
      throw StateError('REVISION_CONFLICT');
    if (state.workspaceId != current.workspaceId ||
        state.receiptKeyId != current.receiptKeyId ||
        state.ownerSid != current.ownerSid ||
        state.receipts.length != current.receipts.length + 1)
      throw StateError('STORAGE_BLOCKED');
    for (final entry in current.receipts.entries) {
      if (!_equal(
        codec.canonical(entry.value.toJson()),
        codec.canonical(state.receipts[entry.key]?.toJson()),
      ))
        throw StateError('STORAGE_BLOCKED');
    }
    for (final id in state.receipts.keys) {
      if (!current.receipts.containsKey(id) &&
          retained.automation.receipts.containsKey(id))
        throw StateError('IDEMPOTENCY_CONFLICT');
    }
    _guardFoundationIdentities(current, state, retained.automation);
    final records = WorkspaceRecords.fromTrustedState(state);
    final expected = <String, List<MigrationRow>>{...retained.rows};
    // Preserve exact raw bytes for semantically unchanged rows, including
    // whitespace/escape spellings in historical receipts and protected blobs.
    List<MigrationRow> plan(String name, List<MigrationRow> proposed) {
      final before = retained.rows[name]!;
      final byId = {for (final row in before) row.entityId: row};
      var maximum = before.fold<int>(0, (n, row) => max(n, row.nativeId));
      final result = <MigrationRow>[];
      for (final row in proposed) {
        final old = byId[row.entityId];
        if (old != null &&
            _equal(
              codec.canonical(
                codec.decode(utf8.encode(old.payload), maxBytes: 512 * 1024),
              ),
              codec.canonical(
                codec.decode(utf8.encode(row.payload), maxBytes: 512 * 1024),
              ),
            )) {
          result.add(old);
        } else {
          if (old == null && maximum >= 9223372036854775807)
            throw StateError('RESOURCE_LIMIT');
          result.add(
            MigrationRow(
              old?.nativeId ?? ++maximum,
              row.payload,
              entityId: row.entityId,
            ),
          );
        }
      }
      result.sort((a, b) => a.nativeId.compareTo(b.nativeId));
      return expected[name] = result;
    }

    plan('StoredWorkspace', [MigrationRow(1, records.workspace.payload)]);
    plan('StoredSettings', [MigrationRow(1, records.settings.payload)]);
    plan('StoredProfile', [
      for (final row in records.profiles)
        MigrationRow(0, row.payload, entityId: row.entityId),
    ]);
    plan('StoredCredential', [
      for (final row in records.credentials)
        MigrationRow(0, row.payload, entityId: row.entityId),
    ]);
    plan('StoredReceipt', [
      for (final row in records.receipts)
        MigrationRow(0, row.payload, entityId: row.entityId),
    ]);
    plan('StoredHostTrust', [
      for (final entry in next.trust.entries)
        MigrationRow(
          0,
          utf8.decode(codec.encode(entry.value.toJson(), maxBytes: 4096)),
          entityId: entry.key,
        ),
    ]);
    var payloadBytes = 0;
    for (final rows in expected.values) {
      for (final row in rows) {
        payloadBytes += utf8.encode(row.payload).length;
        if (payloadBytes > 64 * 1024 * 1024) throw StateError('RESOURCE_LIMIT');
      }
    }
    // Validate proposed cross-references and credentials before any native write.
    await validateWorkspaceCredentials(state, _custody);
    const groups = {
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
    await AutomationSnapshot.loadTrusted(
      foundation: next,
      collections: {
        for (final entry in groups.entries)
          entry.key: [
            for (final row in retained.rows[entry.value]!)
              AutomationSnapshotRow(row.nativeId, row.entityId!, row.payload),
          ],
      },
    );
    _ensure();
    var started = false;
    try {
      await _isar.writeTxn(() async {
        started = true;
        Future<void> apply<T>(
          IsarCollection<T> collection,
          T Function(MigrationRow) convert,
        ) async {
          final after = expected[collection.name]!;
          final byId = {for (final row in after) row.nativeId: row};
          final before = retained.rows[collection.name]!;
          for (final row in before) {
            if (!byId.containsKey(row.nativeId) &&
                !await collection.delete(row.nativeId))
              throw StateError('STORAGE_BLOCKED');
          }
          final old = {for (final row in before) row.nativeId: row};
          for (final row in after) {
            if (old[row.nativeId]?.payload != row.payload &&
                await collection.put(convert(row)) != row.nativeId)
              throw StateError('STORAGE_BLOCKED');
          }
        }

        await apply(
          _isar.storedWorkspaces,
          (r) => StoredWorkspace()
            ..id = r.nativeId
            ..payload = r.payload,
        );
        await apply(
          _isar.storedSettings,
          (r) => StoredSettings()
            ..id = r.nativeId
            ..payload = r.payload,
        );
        await apply(
          _isar.storedProfiles,
          (r) => StoredProfile()
            ..id = r.nativeId
            ..entityId = r.entityId!
            ..payload = r.payload,
        );
        await apply(
          _isar.storedCredentials,
          (r) => StoredCredential()
            ..id = r.nativeId
            ..entityId = r.entityId!
            ..payload = r.payload,
        );
        await apply(
          _isar.storedReceipts,
          (r) => StoredReceipt()
            ..id = r.nativeId
            ..entityId = r.entityId!
            ..payload = r.payload,
        );
        await apply(
          _isar.storedHostTrusts,
          (r) => StoredHostTrust()
            ..id = r.nativeId
            ..entityId = r.entityId!
            ..payload = r.payload,
        );
      });
      final fresh = await _verifyTrustedFoundation(expected);
      _trustedOperational = fresh;
      _state = fresh.foundation.foundation;
    } catch (error) {
      if (started && isNativeCapacityFailure(error)) {
        try {
          await _verifyTrustedFoundation(retained.rows);
        } catch (_) {
          _blocked = true;
          throw StateError('STORAGE_BLOCKED');
        }
        throw StateError('RESOURCE_LIMIT');
      }
      _blocked = true;
      throw StateError('STORAGE_BLOCKED');
    }
  }

  Future<TrustedOperationalSnapshot> _verifyTrustedFoundation(
    Map<String, List<MigrationRow>> expected,
  ) async {
    final fresh = await readTrustedOperationalSnapshot(
      _isar,
      _receiptKey,
      _custody,
      localAppData: _operationalRoot!,
      lease: _lease,
    );
    _ensure();
    if (fresh.rows.length != expected.length)
      throw StateError('STORAGE_BLOCKED');
    for (final entry in expected.entries) {
      final actual = fresh.rows[entry.key];
      if (actual == null || actual.length != entry.value.length)
        throw StateError('STORAGE_BLOCKED');
      for (var i = 0; i < actual.length; i++) {
        final a = actual[i], e = entry.value[i];
        if (a.nativeId != e.nativeId ||
            a.entityId != e.entityId ||
            a.payload != e.payload)
          throw StateError('STORAGE_BLOCKED');
      }
    }
    return fresh;
  }
}
