part of 'state_store.dart';

extension TrustedFoundationWrites on StateStore {
  void _guardFoundationIdentities(
    HostTrustState currentFoundation,
    HostTrustState nextFoundation,
    AutomationSnapshot automation,
  ) {
    final current = currentFoundation.foundation,
        next = nextFoundation.foundation;
    final deleted = {
      for (final receipt in current.receipts.values)
        if (receipt.operation == 'profiles.delete' && receipt.result.deleted)
          receipt.result.entityId,
    };
    for (final id in next.profiles.keys) {
      if (!current.profiles.containsKey(id) && deleted.contains(id))
        throw StateError('ALREADY_EXISTS');
    }
    final codec = StrictCodec();
    for (final job in automation.jobs.values) {
      if (const {'succeeded', 'failed', 'cancelled'}.contains(job.state))
        continue;
      final id = automation.plans[job.immutablePlanId]!.serverId;
      final previous = current.profiles[id], replacement = next.profiles[id];
      if (previous == null || replacement == null)
        throw StateError('HOST_BUSY');
      Map<String, Object?> identity(ProfileRecord profile) => profile.toJson()
        ..remove('name')
        ..remove('tags')
        ..remove('revision')
        ..remove('updatedAt');
      final credentialsMatch = _equal(
        codec.canonical(current.credentials[previous.credentialRef]?.toJson()),
        codec.canonical(next.credentials[replacement.credentialRef]?.toJson()),
      );
      var identitiesMatch = _equal(
        codec.canonical(identity(previous)),
        codec.canonical(identity(replacement)),
      );
      if (!identitiesMatch &&
          credentialsMatch &&
          automation.plans[job.immutablePlanId]!.preflight?.isDirectSsh ==
              true) {
        final before = currentFoundation.trust[id],
            after = nextFoundation.trust[id];
        final added = next.receipts.values
            .where(
              (receipt) => !current.receipts.containsKey(receipt.requestId),
            )
            .toList();
        if (before != null && after != null && added.length == 1) {
          final receipt = added.single;
          final operation = receipt.operation;
          final expectedStatus = operation == 'servers.trust.revoke'
              ? 'revoked'
              : operation == 'servers.trust.confirm'
              ? 'trusted'
              : null;
          Map<String, Object?> trustIdentity(Map<String, Object?> row) =>
              {...row}
                ..remove('revision')
                ..remove('status')
                ..remove('updatedAt');
          final oldIdentity = identity(previous)..remove('trustRevision');
          final newIdentity = identity(replacement)..remove('trustRevision');
          identitiesMatch =
              expectedStatus != null &&
              receipt.toJson()['profileId'] == id &&
              receipt.result.entityId == id &&
              !receipt.result.deleted &&
              receipt.result.entityRevision == replacement.revision &&
              receipt.result.storeRevision == next.storeRevision &&
              replacement.revision == nextRevision(previous.revision) &&
              replacement.trustRevision ==
                  nextRevision(previous.trustRevision) &&
              after.toJson()['status'] == expectedStatus &&
              _equal(
                codec.canonical(oldIdentity),
                codec.canonical(newIdentity),
              ) &&
              _equal(
                codec.canonical(trustIdentity(before.toJson())),
                codec.canonical(trustIdentity(after.toJson())),
              );
        }
      }
      if (!identitiesMatch || !credentialsMatch) throw StateError('HOST_BUSY');
    }
  }

  /// Internal schema3 primitive. The shared service owns authorization, receipt
  /// HMAC/replay, trust transition/challenge rules and its native target lease
  /// BEFORE queue admission. Admission does not come from a store method.
  Future<void> commitFoundation(HostTrustState next) {
    try {
      _ensure();
      snapshot;
      if (_pendingFoundation + _pendingAutomation.length >= 32)
        throw StateError('RESOURCE_LIMIT');
      _pendingFoundation++;
      final result = _tail.then((_) => _commitFoundation(next));
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

  Future<void> _commitFoundation(HostTrustState next) async {
    _ensure();
    final retained = snapshot, current = retained.foundation.foundation;
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
    _guardFoundationIdentities(retained.foundation, next, retained.automation);
    final records = WorkspaceRecords.fromState(state);
    final expected = <String, List<StoredRow>>{...retained.rows};
    List<StoredRow> plan(String name, List<StoredRow> proposed) =>
        expected[name] = retainRowIdentities(retained.rows[name]!, proposed);

    plan('StoredWorkspace', [StoredRow(1, records.workspace.payload)]);
    plan('StoredSettings', [StoredRow(1, records.settings.payload)]);
    plan('StoredProfile', [
      for (final row in records.profiles)
        StoredRow(0, row.payload, entityId: row.entityId),
    ]);
    plan('StoredCredential', [
      for (final row in records.credentials)
        StoredRow(0, row.payload, entityId: row.entityId),
    ]);
    plan('StoredReceipt', [
      for (final row in records.receipts)
        StoredRow(0, row.payload, entityId: row.entityId),
    ]);
    plan('StoredHostTrust', [
      for (final entry in next.trust.entries)
        StoredRow(
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
    await AutomationSnapshot.load(
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
      await _writeStorage((tx) async {
        started = true;
        Future<void> apply(WorkspaceCollection collection) async {
          final after = expected[collection.persistedName]!;
          final byId = {for (final row in after) row.nativeId: row};
          final before = retained.rows[collection.persistedName]!;
          for (final row in before) {
            if (!byId.containsKey(row.nativeId) &&
                !await tx.delete(collection, row.nativeId)) {
              throw StateError('STORAGE_BLOCKED');
            }
          }
          final old = {for (final row in before) row.nativeId: row};
          for (final row in after) {
            if (old[row.nativeId]?.payload != row.payload &&
                await tx.put(collection, row) != row.nativeId) {
              throw StateError('STORAGE_BLOCKED');
            }
          }
        }

        for (final collection in const [
          WorkspaceCollection.workspace,
          WorkspaceCollection.settings,
          WorkspaceCollection.profiles,
          WorkspaceCollection.credentials,
          WorkspaceCollection.receipts,
          WorkspaceCollection.hostTrust,
        ]) {
          await apply(collection);
        }
      });
      final fresh = await _verifyFoundation(expected);
      _snapshot = fresh;
      _state = fresh.foundation.foundation;
    } catch (error) {
      if (started && _storage.isCapacityFailure(error)) {
        try {
          await _verifyFoundation(retained.rows);
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

  Future<WorkspaceSnapshot> _verifyFoundation(
    Map<String, List<StoredRow>> expected,
  ) async {
    await _runtimeLive();
    final fresh = await readWorkspaceSnapshot(
      _storage,
      _receiptKey,
      _custody,
      localAppData: _localAppData,
      lease: _lease,
      protectedFiles: _files,
    );
    await _runtimeLive();
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
