import 'dart:typed_data';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;

import 'automation_records.dart';
import 'host_trust_records.dart';
import 'isar_rows.dart';
import 'native_close.dart';
import 'native_failure.dart';
import 'native_schema.dart';
import 'records.dart';
import 'workspace_rows.dart';
import 'workspace_storage.dart';

/// Production provider for the existing pinned schema3 workspace only.
final class IsarWorkspaceStorageProvider implements WorkspaceStorageProvider {
  const IsarWorkspaceStorageProvider();

  @override
  bool get hasOpenInstance => Isar.getInstance('workspace') != null;

  @override
  WorkspaceRowSource preflightRows(
    Uint8List bytes, {
    required String directory,
  }) => NativeWorkspaceRows.fromSnapshot(bytes, directory: directory);

  @override
  WorkspaceStorageOpen createOpenAttempt({required String directory}) {
    if (!p.isAbsolute(directory) ||
        p.normalize(directory) != directory ||
        directory.contains('\u0000') ||
        directory.length > 32767) {
      throw StateError('STORAGE_BLOCKED');
    }
    return _IsarOpen(directory);
  }
}

final class _IsarOpen implements WorkspaceStorageOpen {
  _IsarOpen(this.directory);
  final String directory;
  bool _owningOpenAttempted = false;
  Isar? _returned;
  _IsarStorage? _storage;
  Future<WorkspaceStorage>? _opening;
  Future<bool>? _cleanup;

  @override
  Future<WorkspaceStorage> open() {
    if (_cleanup != null) return Future.error(StateError('STORAGE_BLOCKED'));
    return _opening ??= _open();
  }

  Future<WorkspaceStorage> _open() async {
    // This check precedes any ownership by this attempt; do not close its result.
    if (Isar.getInstance('workspace') != null) {
      throw StateError('STORAGE_BLOCKED');
    }
    _owningOpenAttempted = true;
    final isar = await Isar.open(
      workspaceSchemas,
      directory: directory,
      name: 'workspace',
      maxSizeMiB: 64,
      relaxedDurability: false,
      inspector: false,
    );
    _returned = isar;
    return _storage = _IsarStorage(isar);
  }

  @override
  Future<bool> cleanupAfterFailedOpen() => _cleanup ??= _closeAttempt();

  Future<bool> _closeAttempt() async {
    final opening = _opening;
    if (opening != null) {
      try {
        await opening;
      } catch (_) {
        // Even throwing native open may have acquired a handle.
      }
    }
    if (!_owningOpenAttempted) return true;
    final storage = _storage;
    if (storage != null) return confirmNativeClose(storage.close);
    final registered = Isar.getInstance('workspace');
    final candidate =
        _returned ??
        (registered != null &&
                registered.directory != null &&
                p.equals(p.normalize(registered.directory!), directory)
            ? registered
            : null);
    return candidate == null ? false : confirmNativeClose(candidate.close);
  }
}

final class _IsarStorage extends TransactionalWorkspaceStorage {
  _IsarStorage(this.isar)
    : rows = IsarRowSource(isar),
      collections = _collections(isar);
  final Isar isar;
  final IsarRowSource rows;
  final Map<WorkspaceCollection, _Access> collections;

  @override
  String get name => rows.name;
  @override
  String get directory => rows.directory;
  @override
  bool isCapacityFailure(Object error) => isNativeCapacityFailure(error);
  @override
  Future<T> backendRead<T>(Future<T> Function() read) => isar.txn(read);
  @override
  Future<T> backendWrite<T>(Future<T> Function() write) => isar.writeTxn(write);
  @override
  Future<int> backendCount(WorkspaceCollection collection) =>
      rows.count(collection.persistedName);
  @override
  Future<List<StoredRow>> backendRows(
    WorkspaceCollection collection,
    int limit,
  ) => rows.read(collection.persistedName, limit: limit);
  @override
  Future<StoredRow?> backendGet(WorkspaceCollection collection, int id) =>
      _rowCall(() => collections[collection]!.get(id));
  @override
  Future<StoredRow?> backendGetByEntityId(
    WorkspaceCollection collection,
    String entityId,
  ) => _rowCall(() => collections[collection]!.getByEntityId(entityId));
  @override
  Future<int> backendPut(WorkspaceCollection collection, StoredRow row) =>
      _rowCall(() => collections[collection]!.put(row));
  @override
  Future<bool> backendDelete(WorkspaceCollection collection, int id) =>
      _rowCall(() => collections[collection]!.delete(id));
  @override
  Future<bool> backendClose() => isar.close();

  Future<T> _rowCall<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on IsarError catch (error) {
      if (isNativeCapacityFailure(error)) rethrow;
      throw StateError('STORAGE_BLOCKED');
    }
  }
}

abstract interface class _Access {
  Future<StoredRow?> get(int id);
  Future<StoredRow?> getByEntityId(String entityId);
  Future<int> put(StoredRow row);
  Future<bool> delete(int id);
}

final class _CollectionAccess<T> implements _Access {
  _CollectionAccess(this.collection, this.encode, this.decode, {this.byEntity});
  final IsarCollection<T> collection;
  final T Function(StoredRow) encode;
  final StoredRow Function(T) decode;
  final Future<T?> Function(String)? byEntity;
  @override
  Future<StoredRow?> get(int id) async {
    final value = await collection.get(id);
    return value == null ? null : decode(value);
  }

  @override
  Future<StoredRow?> getByEntityId(String entityId) async {
    final lookup = byEntity;
    if (lookup == null) throw StateError('STORAGE_BLOCKED');
    final value = await lookup(entityId);
    return value == null ? null : decode(value);
  }

  @override
  Future<int> put(StoredRow row) => collection.put(encode(row));
  @override
  Future<bool> delete(int id) => collection.delete(id);
}

Map<WorkspaceCollection, _Access> _collections(Isar isar) => {
  WorkspaceCollection.workspace: _CollectionAccess<StoredWorkspace>(
    isar.storedWorkspaces,
    (row) => StoredWorkspace()
      ..id = row.nativeId
      ..payload = row.payload,
    (row) => StoredRow(row.id, row.payload),
  ),
  WorkspaceCollection.settings: _CollectionAccess<StoredSettings>(
    isar.storedSettings,
    (row) => StoredSettings()
      ..id = row.nativeId
      ..payload = row.payload,
    (row) => StoredRow(row.id, row.payload),
  ),
  WorkspaceCollection.profiles: _CollectionAccess<StoredProfile>(
    isar.storedProfiles,
    (row) => StoredProfile()
      ..id = row.nativeId
      ..entityId = row.entityId!
      ..payload = row.payload,
    (row) => StoredRow(row.id, row.payload, entityId: row.entityId),
    byEntity: isar.storedProfiles.getByEntityId,
  ),
  WorkspaceCollection.credentials: _CollectionAccess<StoredCredential>(
    isar.storedCredentials,
    (row) => StoredCredential()
      ..id = row.nativeId
      ..entityId = row.entityId!
      ..payload = row.payload,
    (row) => StoredRow(row.id, row.payload, entityId: row.entityId),
    byEntity: isar.storedCredentials.getByEntityId,
  ),
  WorkspaceCollection.receipts: _CollectionAccess<StoredReceipt>(
    isar.storedReceipts,
    (row) => StoredReceipt()
      ..id = row.nativeId
      ..entityId = row.entityId!
      ..payload = row.payload,
    (row) => StoredRow(row.id, row.payload, entityId: row.entityId),
    byEntity: isar.storedReceipts.getByEntityId,
  ),
  WorkspaceCollection.hostTrust: _CollectionAccess<StoredHostTrust>(
    isar.storedHostTrusts,
    (row) => StoredHostTrust()
      ..id = row.nativeId
      ..entityId = row.entityId!
      ..payload = row.payload,
    (row) => StoredRow(row.id, row.payload, entityId: row.entityId),
    byEntity: isar.storedHostTrusts.getByEntityId,
  ),
  WorkspaceCollection.grants: _CollectionAccess<StoredMcpGrant>(
    isar.storedMcpGrants,
    (row) => StoredMcpGrant()
      ..id = row.nativeId
      ..entityId = row.entityId!
      ..payload = row.payload,
    (row) => StoredRow(row.id, row.payload, entityId: row.entityId),
    byEntity: isar.storedMcpGrants.getByEntityId,
  ),
  WorkspaceCollection.delegations: _CollectionAccess<StoredDelegation>(
    isar.storedDelegations,
    (row) => StoredDelegation()
      ..id = row.nativeId
      ..entityId = row.entityId!
      ..payload = row.payload,
    (row) => StoredRow(row.id, row.payload, entityId: row.entityId),
    byEntity: isar.storedDelegations.getByEntityId,
  ),
  WorkspaceCollection.automationProfiles:
      _CollectionAccess<StoredAutomationProfile>(
        isar.storedAutomationProfiles,
        (row) => StoredAutomationProfile()
          ..id = row.nativeId
          ..entityId = row.entityId!
          ..payload = row.payload,
        (row) => StoredRow(row.id, row.payload, entityId: row.entityId),
        byEntity: isar.storedAutomationProfiles.getByEntityId,
      ),
  WorkspaceCollection.revisions: _CollectionAccess<StoredAutomationRevision>(
    isar.storedAutomationRevisions,
    (row) => StoredAutomationRevision()
      ..id = row.nativeId
      ..entityId = row.entityId!
      ..payload = row.payload,
    (row) => StoredRow(row.id, row.payload, entityId: row.entityId),
    byEntity: isar.storedAutomationRevisions.getByEntityId,
  ),
  WorkspaceCollection.plans: _CollectionAccess<StoredAutomationPlan>(
    isar.storedAutomationPlans,
    (row) => StoredAutomationPlan()
      ..id = row.nativeId
      ..entityId = row.entityId!
      ..payload = row.payload,
    (row) => StoredRow(row.id, row.payload, entityId: row.entityId),
    byEntity: isar.storedAutomationPlans.getByEntityId,
  ),
  WorkspaceCollection.approvals: _CollectionAccess<StoredAutomationApproval>(
    isar.storedAutomationApprovals,
    (row) => StoredAutomationApproval()
      ..id = row.nativeId
      ..entityId = row.entityId!
      ..payload = row.payload,
    (row) => StoredRow(row.id, row.payload, entityId: row.entityId),
    byEntity: isar.storedAutomationApprovals.getByEntityId,
  ),
  WorkspaceCollection.jobs: _CollectionAccess<StoredAutomationJob>(
    isar.storedAutomationJobs,
    (row) => StoredAutomationJob()
      ..id = row.nativeId
      ..entityId = row.entityId!
      ..payload = row.payload,
    (row) => StoredRow(row.id, row.payload, entityId: row.entityId),
    byEntity: isar.storedAutomationJobs.getByEntityId,
  ),
  WorkspaceCollection.desired: _CollectionAccess<StoredDesiredState>(
    isar.storedDesiredStates,
    (row) => StoredDesiredState()
      ..id = row.nativeId
      ..entityId = row.entityId!
      ..payload = row.payload,
    (row) => StoredRow(row.id, row.payload, entityId: row.entityId),
    byEntity: isar.storedDesiredStates.getByEntityId,
  ),
  WorkspaceCollection.events: _CollectionAccess<StoredAutomationEvent>(
    isar.storedAutomationEvents,
    (row) => StoredAutomationEvent()
      ..id = row.nativeId
      ..entityId = row.entityId!
      ..payload = row.payload,
    (row) => StoredRow(row.id, row.payload, entityId: row.entityId),
    byEntity: isar.storedAutomationEvents.getByEntityId,
  ),
  WorkspaceCollection.automationReceipts:
      _CollectionAccess<StoredAutomationReceipt>(
        isar.storedAutomationReceipts,
        (row) => StoredAutomationReceipt()
          ..id = row.nativeId
          ..entityId = row.entityId!
          ..payload = row.payload,
        (row) => StoredRow(row.id, row.payload, entityId: row.entityId),
        byEntity: isar.storedAutomationReceipts.getByEntityId,
      ),
};
