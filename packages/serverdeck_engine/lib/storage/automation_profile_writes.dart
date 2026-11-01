part of 'state_store.dart';

extension AutomationProfileWrites on StateStore {
  /// Explicit schema3 catalog write; native actor/gate admission stays separate.
  Future<Map<String, Object?>> mutateAutomationProfile(
    AutomationProfileCommand command, {
    required String? originGrantId,
    required int? expectedGrantRevision,
    required DateTime Function() clock,
  }) => _mutateAutomationProfile(
    command,
    originGrantId,
    expectedGrantRevision,
    clock,
  );

  Future<Map<String, Object?>> _mutateAutomationProfile(
    AutomationProfileCommand command,
    String? originGrantId,
    int? expectedGrantRevision,
    DateTime Function() clock,
  ) {
    try {
      if (_closing) throw StateError('NOT_READY');
      _ensure();
      if (originGrantId != null) {
        requireUuid(originGrantId);
        if (expectedGrantRevision == null ||
            expectedGrantRevision < 1 ||
            expectedGrantRevision > 2147483647) {
          throw const FormatException('VALIDATION');
        }
      } else if (expectedGrantRevision != null) {
        throw const FormatException('VALIDATION');
      }
      final mac = base64.decode(
        _custody.receiptDigestSync(
          _receiptKey,
          command.canonicalRequest(originGrantId),
        ),
      );
      final digest = mac.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final existing = _pendingAutomation[command.requestId];
      if (existing != null) {
        if (existing.originGrantId != originGrantId)
          throw StateError('FORBIDDEN');
        if (existing.digest != digest) throw StateError('IDEMPOTENCY_CONFLICT');
        return existing.result.future;
      }
      if (_pendingAutomation.length + _pendingFoundation >= 32)
        throw StateError('RESOURCE_LIMIT');
      final pending = _AutomationPending(digest, originGrantId: originGrantId);
      pending.result.future.ignore();
      _pendingAutomation[command.requestId] = pending;
      final run = _tail.then(
        (_) => _writeAutomationProfile(
          command,
          originGrantId,
          expectedGrantRevision,
          digest,
          clock,
        ),
      );
      _tail = run.then<void>(
        (result) {
          _pendingAutomation.remove(command.requestId);
          pending.result.complete(result);
        },
        onError: (Object error, StackTrace stack) {
          _pendingAutomation.remove(command.requestId);
          final code = _profileWriteError(error);
          if (code == 'STORAGE_BLOCKED') _blocked = true;
          pending.result.completeError(StateError(code), stack);
        },
      );
      return pending.result.future;
    } on FormatException {
      return Future.error(StateError('VALIDATION'));
    } catch (error) {
      final code = _profileWriteError(error);
      if (code == 'STORAGE_BLOCKED') _blocked = true;
      return Future.error(StateError(code));
    }
  }

  String _profileWriteError(Object error) =>
      error is StateError &&
          {
            'NOT_READY',
            'FORBIDDEN',
            'REVISION_CONFLICT',
            'IDEMPOTENCY_CONFLICT',
            'RESOURCE_LIMIT',
            'STORAGE_BLOCKED',
            'VALIDATION',
          }.contains(error.message)
      ? error.message
      : 'STORAGE_BLOCKED';

  void _profileInitiator(String? origin, int? revision, DateTime at) {
    _grantLive();
    if (origin == null) return;
    final grant = _automationView().automation.grants[origin];
    if (grant == null ||
        grant.revision != revision ||
        !grant.isCurrentAt(at) ||
        !grant.policy.allowsScope(McpScope.author))
      throw StateError('FORBIDDEN');
  }

  Future<Map<String, Object?>> _writeAutomationProfile(
    AutomationProfileCommand command,
    String? origin,
    int? grantRevision,
    String digest,
    DateTime Function() clock,
  ) async {
    _grantLive();
    final previous = _automationView(), graph = previous.automation;
    var at = _grantInstant(clock);
    for (final revision in graph.revisions.values) {
      if (revision.createdAt.isAfter(at)) at = revision.createdAt;
    }
    _profileInitiator(origin, grantRevision, at);
    final receipt = graph.receipts[command.requestId];
    if (receipt != null) {
      if (receipt.originGrantId != origin) throw StateError('FORBIDDEN');
      if (receipt.operation != command.operation ||
          receipt.canonicalDigest != digest) {
        throw StateError('IDEMPOTENCY_CONFLICT');
      }
      // Replay still validates actual retained/native storage, never rewrites it.
      _authorityUnavailable = true;
      try {
        final loaded = await _reloadGrants();
        if (!_sameGrantSnapshot(previous, loaded))
          throw StateError('STORAGE_BLOCKED');
        _publishAutomation(loaded);
        _authorityUnavailable = false;
        return Map.unmodifiable(receipt.result);
      } catch (_) {
        _blocked = true;
        throw StateError('STORAGE_BLOCKED');
      }
    }
    if (_state.receipts.containsKey(command.requestId))
      throw StateError('IDEMPOTENCY_CONFLICT');
    final create = command.operation == 'profile.create',
        archive = command.operation == 'profile.archive';
    final old = create ? null : graph.profiles[command.profileId];
    if (!create && old == null) throw StateError('FORBIDDEN');
    if (!create && old!.headRevision != command.expectedRevision)
      throw StateError('REVISION_CONFLICT');
    if (graph.receipts.length >= 10000 ||
        create && graph.profiles.length >= 250 ||
        !create &&
            !archive &&
            (old!.headRevision >= 20 || old.headRevision >= 2147483647)) {
      throw StateError('RESOURCE_LIMIT');
    }
    var id = old?.id;
    for (var attempt = 0; id == null && attempt < 8; attempt++) {
      final next = _grantSecretRef();
      if (!graph.profiles.containsKey(next)) id = next;
    }
    if (id == null) throw StateError('RESOURCE_LIMIT');
    final revision = create
        ? 1
        : archive
        ? old!.headRevision
        : old!.headRevision + 1;
    final metadata = AutomationProfileRecord.fromJson({
      'workspaceId': _state.workspaceId,
      'id': id,
      'name': command.name ?? old!.name,
      'description': command.description ?? old!.description,
      'headRevision': revision,
      'archived': archive || (old?.archived ?? false),
    });
    final bodyDigest = archive ? null : await command.body!.digest();
    final version = archive
        ? null
        : await AutomationRevisionRecord.fromJson({
            'workspaceId': _state.workspaceId,
            'profileId': id,
            'revision': revision,
            'parentRevision': create ? null : old!.headRevision,
            'bodyFormat': 1,
            'body': command.body!.toJson(),
            'digest': bodyDigest,
            'authorGrantId': origin,
            'createdAt': at.toIso8601String(),
          });
    final nextReceipt = AutomationMutationReceiptRecord.fromJson({
      'workspaceId': _state.workspaceId,
      'requestId': command.requestId,
      'originGrantId': origin,
      'objectGrantId': null,
      'canonicalDigest': digest,
      'operation': command.operation,
      'result': archive
          ? {'profileId': id, 'revision': revision, 'archived': true}
          : {'profileId': id, 'revision': revision, 'digest': bodyDigest},
      'createdAt': at.toIso8601String(),
    });
    AutomationSnapshotRow row(
      int nativeId,
      String key,
      Map<String, Object?> payload,
    ) => AutomationSnapshotRow(
      nativeId,
      key,
      utf8.decode(StrictCodec().canonical(payload)),
    );
    final oldRow = create
        ? null
        : previous.rows['profiles']!.singleWhere((r) => r.entityId == id);
    final metadataRow = row(
      oldRow?.nativeId ?? _nextGrantNativeId(previous.rows['profiles']!),
      id,
      metadata.toJson(),
    );
    final versionRow = version == null
        ? null
        : row(
            _nextGrantNativeId(previous.rows['revisions']!),
            '$id:$revision',
            version.toJson(),
          );
    final receiptRow = row(
      _nextGrantNativeId(previous.rows['receipts']!),
      command.requestId,
      nextReceipt.toJson(),
    );
    final candidate = {
      for (final entry in previous.rows.entries)
        entry.key: List<AutomationSnapshotRow>.of(entry.value),
    };
    if (oldRow == null) {
      candidate['profiles']!.add(metadataRow);
    } else {
      candidate['profiles']![candidate['profiles']!.indexOf(oldRow)] =
          metadataRow;
    }
    if (versionRow != null) candidate['revisions']!.add(versionRow);
    candidate['receipts']!.add(receiptRow);
    var bytes = previous.foundationPayloadBytes;
    for (final rows in candidate.values) {
      for (final value in rows) {
        bytes += utf8.encode(value.payload).length;
        if (bytes > 64 << 20) throw StateError('RESOURCE_LIMIT');
      }
    }
    try {
      await previous.validate(candidate);
      _profileInitiator(origin, grantRevision, _grantInstant(clock));
    } catch (error) {
      if (error is StateError && error.message == 'FORBIDDEN') rethrow;
      _blocked = true;
      throw StateError('STORAGE_BLOCKED');
    }
    var entered = false, committed = false;
    try {
      _authorityUnavailable = true;
      _grantLive();
      await _writeStorage((tx) async {
        entered = true;
        _profileInitiator(origin, grantRevision, _grantInstant(clock));
        final actual = await tx.getByEntityId(
          WorkspaceCollection.automationProfiles,
          id!,
        );
        if ((oldRow == null
                ? actual != null
                : actual == null ||
                      actual.nativeId != oldRow.nativeId ||
                      actual.payload != oldRow.payload) ||
            oldRow == null &&
                await tx.get(
                      WorkspaceCollection.automationProfiles,
                      metadataRow.nativeId,
                    ) !=
                    null ||
            await tx.getByEntityId(
                  WorkspaceCollection.automationReceipts,
                  command.requestId,
                ) !=
                null ||
            await tx.get(
                  WorkspaceCollection.automationReceipts,
                  receiptRow.nativeId,
                ) !=
                null ||
            versionRow != null &&
                (await tx.getByEntityId(
                          WorkspaceCollection.revisions,
                          versionRow.entityId,
                        ) !=
                        null ||
                    await tx.get(
                          WorkspaceCollection.revisions,
                          versionRow.nativeId,
                        ) !=
                        null)) {
          throw StateError('STORAGE_BLOCKED');
        }
        if (await tx.put(
              WorkspaceCollection.automationProfiles,
              StoredRow(
                metadataRow.nativeId,
                metadataRow.payload,
                entityId: metadataRow.entityId,
              ),
            ) !=
            metadataRow.nativeId) {
          throw StateError('STORAGE_BLOCKED');
        }
        if (versionRow != null &&
            await tx.put(
                  WorkspaceCollection.revisions,
                  StoredRow(
                    versionRow.nativeId,
                    versionRow.payload,
                    entityId: versionRow.entityId,
                  ),
                ) !=
                versionRow.nativeId) {
          throw StateError('STORAGE_BLOCKED');
        }
        if (await tx.put(
              WorkspaceCollection.automationReceipts,
              StoredRow(
                receiptRow.nativeId,
                receiptRow.payload,
                entityId: receiptRow.entityId,
              ),
            ) !=
            receiptRow.nativeId) {
          throw StateError('STORAGE_BLOCKED');
        }
        _grantLive();
      });
      committed = true;
      final loaded = await _reloadGrants();
      for (final group in candidate.entries) {
        final actual = {
          for (final value in loaded.rows[group.key]!) value.nativeId: value,
        };
        if (actual.length != group.value.length)
          throw StateError('STORAGE_BLOCKED');
        for (final value in group.value) {
          final current = actual[value.nativeId];
          if (current == null ||
              current.entityId != value.entityId ||
              current.payload != value.payload) {
            throw StateError('STORAGE_BLOCKED');
          }
        }
      }
      if (!previous.sameFoundation(loaded)) throw StateError('STORAGE_BLOCKED');
      _grantLive();
      _publishAutomation(loaded);
      _authorityUnavailable = false;
      return Map.unmodifiable(nextReceipt.result);
    } catch (error) {
      final policyDenied = error is StateError && error.message == 'FORBIDDEN';
      if (entered &&
          !committed &&
          (_storage.isCapacityFailure(error) || policyDenied)) {
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
        throw StateError(policyDenied ? 'FORBIDDEN' : 'RESOURCE_LIMIT');
      }
      _blocked = true;
      throw StateError('STORAGE_BLOCKED');
    }
  }
}
