part of 'state_store.dart';

extension OperationalFoundationWrites on StateStore {
  /// Trusted foundation transaction primitive. The shared owner service must
  /// acquire its native publication/target lease BEFORE joining this queue.
  /// This never authorizes a session or enables operational product startup.
  Future<void> commitOperationalFoundation(WorkspaceState next) {
    try {
      _ensure();
      operational;
      if (_pendingAutomation.length + _pendingFoundation >= 32)
        throw StateError('RESOURCE_LIMIT');
      _pendingFoundation++;
      final result = _tail.then(
        (_) => _commit(next, operationalFoundation: true),
      );
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

  void _guardFoundationIdentities(
    WorkspaceState current,
    WorkspaceState next,
    AutomationSnapshot automation,
  ) {
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
      if (!_equal(
            codec.canonical(identity(previous)),
            codec.canonical(identity(replacement)),
          ) ||
          !_equal(
            codec.canonical(
              current.credentials[previous.credentialRef]?.toJson(),
            ),
            codec.canonical(
              next.credentials[replacement.credentialRef]?.toJson(),
            ),
          ))
        throw StateError('HOST_BUSY');
    }
  }

  Future<OperationalSnapshot> _verifyOperationalFoundation(
    WorkspaceState expected,
    OperationalSnapshot retained,
  ) async {
    final fresh = await readOperationalSnapshot(
      _isar,
      _receiptKey,
      _custody,
      localAppData: _operationalRoot!,
      lease: _lease,
    );
    _ensure();
    final codec = StrictCodec();
    if (!_equal(
      codec.canonical(expected.toJson()),
      codec.canonical(fresh.foundation.state.toJson()),
    ))
      throw StateError('STORAGE_BLOCKED');
    for (final collection in retained.rows.keys) {
      final before = retained.rows[collection]!;
      final after = {
        for (final row in fresh.rows[collection]!) row.entityId: row,
      };
      if (before.length != after.length) throw StateError('STORAGE_BLOCKED');
      for (final row in before) {
        final actual = after[row.entityId];
        if (actual == null ||
            row.nativeId != actual.nativeId ||
            row.payload != actual.payload)
          throw StateError('STORAGE_BLOCKED');
      }
    }
    return fresh;
  }
}
