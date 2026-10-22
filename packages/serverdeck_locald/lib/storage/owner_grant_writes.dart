part of 'state_store.dart';

final class _AutomationPending {
  _AutomationPending(this.digest, {this.originGrantId});
  final String digest;
  final String? originGrantId;
  final result = Completer<Map<String, Object?>>();
}

extension _OwnerGrantWrites on StateStore {
  void _grantLive() {
    // Already accepted work drains during close; intake rejects new work.
    if (_blocked ||
        _closed ||
        !_lease.isHeld ||
        _custody.ownerSid != currentUserSid() ||
        _operational == null)
      throw StateError('STORAGE_BLOCKED');
    _custody.receiptDigestSync(_receiptKey, {
      'purpose': 'grant-write-liveness',
    });
  }

  DateTime _grantInstant(DateTime Function() clock) {
    var at = DateTime.fromMillisecondsSinceEpoch(
      clock().millisecondsSinceEpoch,
      isUtc: true,
    );
    void floor(DateTime time) {
      if (time.isAfter(at)) at = time;
    }

    for (final receipt in _state.receipts.values) {
      floor(DateTime.parse(receipt.committedAt));
    }
    for (final receipt in _operational!.automation.receipts.values) {
      floor(receipt.createdAt);
    }
    for (final grant in _operational!.automation.grants.values) {
      floor(grant.issuedAt);
      if (grant.revokedAt != null) floor(grant.revokedAt!);
    }
    // The strict DTO uses the same canonical supported timestamp interval.
    ClientGrantRecord.expiryFor(at, lifetime: const Duration(seconds: 300));
    return at;
  }

  int _nextGrantNativeId(List<AutomationSnapshotRow> rows) {
    var maximum = 0;
    for (final row in rows) {
      if (row.nativeId > maximum) maximum = row.nativeId;
    }
    if (maximum >= 9223372036854775807) throw StateError('RESOURCE_LIMIT');
    return maximum + 1;
  }

  String _grantSecretRef() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 0x40;
    bytes[8] = (bytes[8] & 63) | 0x80;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  McpCredentialFiles _grantFiles() => McpCredentialFiles(
    localAppData: _operationalRoot!,
    workspaceId: _state.workspaceId,
    ownerSid: _state.ownerSid,
    custody: McpCredentialCustody(_custody.protection),
  );

  McpCredentialBinding _grantBinding(ClientGrantRecord grant) =>
      McpCredentialBinding(
        workspaceId: grant.workspaceId,
        grantId: grant.id,
        secretRef: grant.secretRef,
        ownerSid: _state.ownerSid,
        issuedAt: grant.issuedAt.toIso8601String(),
      );

  bool _sameGrantSnapshot(OperationalSnapshot left, OperationalSnapshot right) {
    if (left.foundation.rows.digest() != right.foundation.rows.digest() ||
        left.rows.length != right.rows.length)
      return false;
    for (final group in left.rows.entries) {
      final retained = {
        for (final row in right.rows[group.key]!) row.nativeId: row,
      };
      if (group.value.length != retained.length) return false;
      for (final row in group.value) {
        final actual = retained[row.nativeId];
        if (actual == null ||
            actual.entityId != row.entityId ||
            actual.payload != row.payload)
          return false;
      }
    }
    return true;
  }

  Future<OperationalSnapshot> _reloadGrants() async {
    _grantLive();
    final current = await readOperationalSnapshot(
      _isar,
      _receiptKey,
      _custody,
      localAppData: _operationalRoot!,
      lease: _lease,
    );
    _grantLive();
    return current;
  }

  Future<Map<String, Object?>> _writeOwnerGrant(
    OwnerGrantCommand command,
    String digest,
    DateTime Function() clock,
  ) async {
    _grantLive();
    final previous = _operational!, graph = previous.automation;
    final receipt = graph.receipts[command.requestId];
    if (receipt != null) {
      if (receipt.originGrantId != null) throw StateError('FORBIDDEN');
      if (receipt.operation != command.operation ||
          receipt.canonicalDigest != digest)
        throw StateError('IDEMPOTENCY_CONFLICT');
      _authorityUnavailable = true;
      try {
        final loaded = await _reloadGrants();
        if (!_sameGrantSnapshot(previous, loaded))
          throw StateError('STORAGE_BLOCKED');
        _operational = loaded;
        _authorityUnavailable = false;
        return Map.unmodifiable(receipt.result);
      } catch (_) {
        _blocked = true;
        throw StateError('STORAGE_BLOCKED');
      }
    }
    if (_state.receipts.containsKey(command.requestId))
      throw StateError('IDEMPOTENCY_CONFLICT');
    if (graph.receipts.length >= 10000) throw StateError('RESOURCE_LIMIT');
    final old = graph.grants[command.grantId];
    final create = command.operation == 'grant.create',
        revoke = command.operation == 'grant.revoke';
    if (create && old != null) throw StateError('REVISION_CONFLICT');
    if (!create && old == null) throw StateError('FORBIDDEN');
    if (!create &&
        (old!.revokedAt != null || old.revision != command.expectedRevision))
      throw StateError('REVISION_CONFLICT');
    if (create && graph.grants.length >= 32 ||
        old != null && old.revision >= 2147483647)
      throw StateError('RESOURCE_LIMIT');
    if (!revoke &&
        !(_state.profiles.keys.toSet().containsAll(command.policy!.serverIds)))
      throw StateError('FORBIDDEN');
    final oldRow = create
        ? null
        : previous.rows['grants']!.singleWhere(
            (r) => r.entityId == command.grantId,
          );
    final grantId =
        oldRow?.nativeId ?? _nextGrantNativeId(previous.rows['grants']!);
    final receiptId = _nextGrantNativeId(previous.rows['receipts']!);
    late final DateTime at;
    try {
      at = _grantInstant(clock);
    } catch (_) {
      _blocked = true;
      throw StateError('STORAGE_BLOCKED');
    }
    late final ClientGrantRecord next;
    try {
      final json = revoke
          ? {
              ...old!.toJson(),
              'revision': old.revision + 1,
              'revokedAt': at.toIso8601String(),
            }
          : {
              'id': command.grantId,
              'workspaceId': _state.workspaceId,
              'label': command.label,
              'revision': create ? 1 : old!.revision + 1,
              ...command.policy!.toJson(),
              'createdAt': create
                  ? at.toIso8601String()
                  : old!.createdAt.toIso8601String(),
              'issuedAt': at.toIso8601String(),
              'expiresAt': ClientGrantRecord.expiryFor(
                at,
                lifetime: Duration(seconds: command.lifetimeSeconds!),
              ).toIso8601String(),
              'revokedAt': null,
              'secretRef': _grantSecretRef(),
            };
      next = ClientGrantRecord.fromJson(json);
      if (!create) {
        if (revoke) {
          old!.validateRevocation(next, at: at);
        } else {
          old!.validateReplacement(next, at: at);
        }
      }
    } catch (_) {
      _blocked = true;
      throw StateError('STORAGE_BLOCKED');
    }
    final nextReceipt = AutomationMutationReceiptRecord.fromJson({
      'workspaceId': _state.workspaceId,
      'requestId': command.requestId,
      'originGrantId': null,
      'objectGrantId': null,
      'canonicalDigest': digest,
      'operation': command.operation,
      'result': {'grantId': next.id, 'revision': next.revision},
      'createdAt': at.toIso8601String(),
    });
    final grantRow = AutomationSnapshotRow(
      grantId,
      next.id,
      utf8.decode(StrictCodec().canonical(next.toJson())),
    );
    final receiptRow = AutomationSnapshotRow(
      receiptId,
      command.requestId,
      utf8.decode(StrictCodec().canonical(nextReceipt.toJson())),
    );
    final candidate = {
      for (final entry in previous.rows.entries)
        entry.key: List<AutomationSnapshotRow>.of(entry.value),
    };
    if (oldRow == null) {
      candidate['grants']!.add(grantRow);
    } else {
      candidate['grants']![candidate['grants']!.indexOf(oldRow)] = grantRow;
    }
    candidate['receipts']!.add(receiptRow);
    var bytes = 0;
    for (final rows in candidate.values) {
      for (final row in rows) {
        bytes += utf8.encode(row.payload).length;
        if (bytes > 64 << 20) throw StateError('RESOURCE_LIMIT');
      }
    }
    try {
      await AutomationSnapshot.load(foundation: _state, collections: candidate);
      _grantLive();
    } catch (_) {
      _blocked = true;
      throw StateError('STORAGE_BLOCKED');
    }
    var entered = false, committed = false;
    try {
      if (grantWriteProbesEnabled)
        await GrantWriteProbe.hit(GrantWriteBoundary.beforeStage);
      _grantLive();
      if (!revoke) {
        await _grantFiles().stage(_grantBinding(next));
        _grantLive();
      }
      if (grantWriteProbesEnabled)
        await GrantWriteProbe.hit(GrantWriteBoundary.afterStage);
      _grantLive();
      _authorityUnavailable = true;
      if (grantWriteProbesEnabled)
        await GrantWriteProbe.hit(GrantWriteBoundary.beforeTransaction);
      _grantLive();
      await _isar.writeTxn(() async {
        entered = true;
        _grantLive();
        final actual = await _isar.storedMcpGrants.getByEntityId(next.id);
        final consumed = await _isar.storedAutomationReceipts.getByEntityId(
          command.requestId,
        );
        if (consumed != null ||
            (oldRow == null &&
                await _isar.storedMcpGrants.get(grantRow.nativeId) != null) ||
            (oldRow == null
                ? actual != null
                : actual == null ||
                      actual.id != oldRow.nativeId ||
                      actual.entityId != oldRow.entityId ||
                      actual.payload != oldRow.payload) ||
            await _isar.storedAutomationReceipts.get(receiptId) != null)
          throw StateError('STORAGE_BLOCKED');
        _grantLive();
        if (await _isar.storedMcpGrants.put(
              StoredMcpGrant()
                ..id = grantRow.nativeId
                ..entityId = grantRow.entityId
                ..payload = grantRow.payload,
            ) <
            1)
          throw StateError('STORAGE_BLOCKED');
        if (grantWriteProbesEnabled)
          await GrantWriteProbe.hit(GrantWriteBoundary.afterGrantWrite);
        if (await _isar.storedAutomationReceipts.put(
              StoredAutomationReceipt()
                ..id = receiptRow.nativeId
                ..entityId = receiptRow.entityId
                ..payload = receiptRow.payload,
            ) <
            1)
          throw StateError('STORAGE_BLOCKED');
        if (grantWriteProbesEnabled)
          await GrantWriteProbe.hit(GrantWriteBoundary.afterReceiptWrite);
        _grantLive();
      });
      committed = true;
      if (grantWriteProbesEnabled)
        await GrantWriteProbe.hit(GrantWriteBoundary.afterCommit);
      _grantLive();
      if (grantWriteProbesEnabled)
        await GrantWriteProbe.hit(GrantWriteBoundary.beforePublication);
      final loaded = await _reloadGrants();
      if (grantWriteProbesEnabled)
        await GrantWriteProbe.hit(GrantWriteBoundary.afterPublication);
      // Check exact expected raw delta, including every unaffected collection.
      for (final group in candidate.entries) {
        final actual = {
          for (final row in loaded.rows[group.key]!) row.nativeId: row,
        };
        if (actual.length != group.value.length)
          throw StateError('STORAGE_BLOCKED');
        for (final row in group.value) {
          final current = actual[row.nativeId];
          if (current == null ||
              current.entityId != row.entityId ||
              current.payload != row.payload)
            throw StateError('STORAGE_BLOCKED');
        }
      }
      if (loaded.foundation.rows.digest() != previous.foundation.rows.digest())
        throw StateError('STORAGE_BLOCKED');
      if (grantWriteProbesEnabled)
        await GrantWriteProbe.hit(GrantWriteBoundary.beforeAcknowledgement);
      _grantLive();
      _operational = loaded;
      // Listeners synchronously retire interests before authority reopens or an
      // acknowledgement escapes. A throw takes the existing blocked path while
      // retaining the committed receipt; it cannot undo the durable mutation.
      var listenerFailed = false;
      for (final listener in _grantPublished.toList()) {
        try {
          listener(next.id, next.revision);
        } catch (_) {
          listenerFailed = true;
        }
      }
      if (listenerFailed) throw StateError('STORAGE_BLOCKED');
      _authorityUnavailable = false;
      return Map.unmodifiable(nextReceipt.result);
    } catch (error) {
      if (!entered && error is StateError && error.message == 'RESOURCE_LIMIT')
        rethrow;
      if (entered && !committed && isNativeCapacityFailure(error)) {
        try {
          final restored = await _reloadGrants();
          if (!_sameGrantSnapshot(previous, restored))
            throw StateError('STORAGE_BLOCKED');
          _operational = restored;
          _authorityUnavailable = false;
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
}
