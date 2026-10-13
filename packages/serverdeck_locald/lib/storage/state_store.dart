import 'dart:convert';
import 'dart:typed_data';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';

import '../bootstrap/native_runtime.dart';
import 'credential_validation.dart';
import 'key_custody.dart';
import 'models.dart';
import 'native_failure.dart';
import 'native_close.dart';
import 'native_schema.dart';
import 'records.dart';

/// Owned existing-workspace repository. Creation/promotion belongs to workspace.
class StateStore {
  static bool _reserved = false;
  static bool get hasOpenReservation => _reserved;
  StateStore._(
    this._isar,
    this._lease,
    this._custody,
    this._receiptKey,
    this._state,
  );
  final Isar _isar;
  final MutexLease _lease;
  final KeyCustody _custody;
  final ReceiptKeyMaterial _receiptKey;
  WorkspaceState _state;
  Future<void> _tail = Future.value();
  Future<void>? _closeOperation;
  bool _blocked = false, _closing = false, _closed = false;

  static Future<StateStore> open({
    required String localAppData,
    required String directory,
    required String appRoot,
    required MutexLease lease,
    required KeyCustody custody,
    required ReceiptKeyMaterial receiptKey,
  }) async {
    if (_reserved || !lease.isHeld || custody.ownerSid != currentUserSid()) {
      throw StateError('STORAGE_BLOCKED');
    }
    // Isar registers only after its async native open: reserve synchronously.
    _reserved = true;
    Isar? isar;
    var transferred = false, safeToRelease = true;
    try {
      await initializeNativeRuntime(appRoot);
      requireSafePath(localAppData, directory);
      requireOwnerOnlyFileAcl(directory, custody.ownerSid);
      final codec = StrictCodec();
      final manifest = await readProtectedFile(
        localAppData,
        p.join(directory, 'workspace.manifest.json'),
        custody.ownerSid,
        maxBytes: 4096,
      );
      await custody.verifyWorkspaceManifest(
        codec.decode(manifest, maxBytes: 4096),
        receiptKey,
      );
      final keyBytes = await readProtectedFile(
        localAppData,
        p.join(directory, 'receipt-key.dpapi'),
        custody.ownerSid,
        maxBytes: 16384,
      );
      if (!_equal(keyBytes, receiptKey.wrapper))
        throw StateError('STORAGE_BLOCKED');
      final snapshot = await readProtectedFile(
        localAppData,
        p.join(directory, 'workspace.isar'),
        custody.ownerSid,
        maxBytes: 64 * 1024 * 1024,
      );
      validateNativeSnapshot(Uint8List.fromList(snapshot));
      requireSafePath(localAppData, p.join(directory, 'workspace.isar-lck'));
      requireOwnerOnlyFileAcl(
        p.join(directory, 'workspace.isar-lck'),
        custody.ownerSid,
      );
      if (!lease.isHeld || Isar.getInstance('workspace') != null)
        throw StateError('STORAGE_BLOCKED');
      isar = await Isar.open(
        workspaceSchemas,
        directory: directory,
        name: 'workspace',
        maxSizeMiB: 64,
        relaxedDurability: false,
        inspector: false,
      );
      final state = await _load(isar, receiptKey);
      await validateWorkspaceCredentials(state, custody);
      if (!lease.isHeld) throw StateError('STORAGE_BLOCKED');
      transferred = true;
      return StateStore._(isar, lease, custody, receiptKey, state);
    } catch (error) {
      if (isar != null) {
        safeToRelease = await confirmNativeClose(isar.close);
      }
      if (error is StateError &&
          (error.message == 'INCOMPATIBLE' ||
              error.message == 'PREREQUISITE_UNAVAILABLE'))
        rethrow;
      throw StateError('STORAGE_BLOCKED');
    } finally {
      if (!transferred && safeToRelease) _reserved = false;
    }
  }

  WorkspaceState get state {
    _ensure();
    return _state;
  }

  void _ensure() {
    if (_blocked || _closed || _closing || !_lease.isHeld)
      throw StateError('STORAGE_BLOCKED');
  }

  static Future<WorkspaceState> _load(Isar isar, ReceiptKeyMaterial key) async {
    if (await isar.storedWorkspaces.count() != 1 ||
        await isar.storedSettings.count() != 1 ||
        await isar.storedProfiles.count() > 250 ||
        await isar.storedCredentials.count() > 250 ||
        await isar.storedReceipts.count() > 10000)
      throw StateError('STORAGE_BLOCKED');
    final workspace = await isar.storedWorkspaces.get(1),
        settings = await isar.storedSettings.get(1);
    if (workspace == null || settings == null)
      throw StateError('STORAGE_BLOCKED');
    Map<String, Object?> document(String value, int bound) =>
        StrictCodec().decode(utf8.encode(value), maxBytes: bound);
    final metadata = document(workspace.payload, 4096);
    if (metadata.keys.toSet().difference({
          'schemaVersion',
          'workspaceId',
          'receiptKeyId',
          'ownerSid',
          'storeRevision',
        }).isNotEmpty ||
        metadata.length != 5) {
      throw StateError('STORAGE_BLOCKED');
    }
    Map<String, Object?> entities(List<(int, String, String)> rows, int bound) {
      final values = <String, Object?>{};
      for (final row in rows) {
        if (row.$1 < 1 || values.containsKey(row.$2))
          throw StateError('STORAGE_BLOCKED');
        final value = document(row.$3, bound);
        if (row.$2 != value['id'] && row.$2 != value['requestId'])
          throw StateError('STORAGE_BLOCKED');
        values[row.$2] = value;
      }
      return values;
    }

    final profiles = await isar.storedProfiles.where().findAll();
    final credentials = await isar.storedCredentials.where().findAll();
    final receipts = await isar.storedReceipts.where().findAll();
    return WorkspaceState.fromJson(
      {
        ...metadata,
        'settings': document(settings.payload, 4096),
        'profiles': entities([
          for (final row in profiles) (row.id, row.entityId, row.payload),
        ], 16 * 1024),
        'credentials': entities([
          for (final row in credentials) (row.id, row.entityId, row.payload),
        ], 512 * 1024),
        'receipts': entities([
          for (final row in receipts) (row.id, row.entityId, row.payload),
        ], 4096),
      },
      workspaceId: key.workspaceId,
      receiptKeyId: key.receiptKeyId,
      ownerSid: key.ownerSid,
    );
  }

  /// Serial durable primitive; upstream coordinator owns CAS/idempotency/grants.
  Future<void> commit(WorkspaceState next) {
    _ensure();
    final result = _tail.then((_) => _commit(next));
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _commit(WorkspaceState next) async {
    _ensure();
    final current = _state;
    if (next.workspaceId != current.workspaceId ||
        next.receiptKeyId != current.receiptKeyId ||
        next.ownerSid != current.ownerSid ||
        next.storeRevision != nextRevision(current.storeRevision) ||
        next.receipts.length != current.receipts.length + 1)
      throw StateError('STORAGE_BLOCKED');
    final codec = StrictCodec();
    for (final entry in current.receipts.entries) {
      final retained = next.receipts[entry.key];
      if (retained == null ||
          !_equal(
            codec.canonical(entry.value.toJson()),
            codec.canonical(retained.toJson()),
          )) {
        throw StateError('STORAGE_BLOCKED');
      }
    }
    final rows = WorkspaceRecords.fromState(next);
    var transactionStarted = false;
    try {
      await validateWorkspaceCredentials(next, _custody);
      final oldProfiles = {
        for (final row in await _isar.storedProfiles.where().findAll())
          row.entityId: row,
      };
      final oldCredentials = {
        for (final row in await _isar.storedCredentials.where().findAll())
          row.entityId: row,
      };
      final oldReceipts = {
        for (final row in await _isar.storedReceipts.where().findAll())
          row.entityId: row,
      };
      _ensure();
      await _isar.writeTxn(() async {
        transactionStarted = true;
        for (final row in oldProfiles.values) {
          if (!next.profiles.containsKey(row.entityId))
            await _isar.storedProfiles.delete(row.id);
        }
        for (final row in oldCredentials.values) {
          if (!next.credentials.containsKey(row.entityId))
            await _isar.storedCredentials.delete(row.id);
        }
        for (final row in rows.profiles) {
          final old = oldProfiles[row.entityId];
          if (old != null) row.id = old.id;
          if (old?.payload != row.payload &&
              await _isar.storedProfiles.put(row) < 1)
            throw StateError('RESOURCE_LIMIT');
        }
        for (final row in rows.credentials) {
          final old = oldCredentials[row.entityId];
          if (old != null) row.id = old.id;
          if (old?.payload != row.payload &&
              await _isar.storedCredentials.put(row) < 1)
            throw StateError('RESOURCE_LIMIT');
        }
        for (final row in rows.receipts) {
          if (!oldReceipts.containsKey(row.entityId) &&
              await _isar.storedReceipts.put(row) < 1)
            throw StateError('RESOURCE_LIMIT');
        }
        if (!_equal(
          codec.canonical(next.settings.toJson()),
          codec.canonical(current.settings.toJson()),
        ))
          await _isar.storedSettings.put(rows.settings);
        await _isar.storedWorkspaces.put(rows.workspace);
      });
      _state = next;
    } catch (error) {
      if (transactionStarted &&
          (isNativeCapacityFailure(error) ||
              (error is StateError && error.message == 'RESOURCE_LIMIT'))) {
        try {
          _ensure();
          final persisted = await _load(_isar, _receiptKey);
          await validateWorkspaceCredentials(persisted, _custody);
          if (!_equal(
            codec.canonical(persisted.toJson()),
            codec.canonical(current.toJson()),
          ))
            throw StateError('STORAGE_BLOCKED');
        } catch (_) {
          _blocked = true;
          throw StateError('STORAGE_BLOCKED');
        }
        // Native writeTxn has completed its abort; every persisted record was
        // reread and verified against the unchanged ready model.
        throw StateError('RESOURCE_LIMIT');
      }
      _blocked = true;
      throw StateError('STORAGE_BLOCKED');
    }
  }

  Future<void> close() => _closeOperation ??= _close();

  Future<void> _close() async {
    _closing = true;
    await _tail;
    try {
      if (!await _isar.close()) throw StateError('STORAGE_BLOCKED');
      _reserved = false;
    } catch (_) {
      throw StateError('STORAGE_BLOCKED');
    } finally {
      _closed = true;
    }
  }
}

bool _equal(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
