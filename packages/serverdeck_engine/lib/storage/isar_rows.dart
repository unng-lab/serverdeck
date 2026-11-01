import 'package:isar_community/isar.dart';

import 'automation_records.dart';
import 'host_trust_records.dart';
import 'records.dart';
import 'workspace_rows.dart';

/// Borrows the engine's existing native handle; ownership remains with store.
final class IsarRowSource implements WorkspaceRowSource {
  IsarRowSource(this._isar)
    : _readers = {
        'StoredWorkspace': _CollectionRows(
          _isar.storedWorkspaces,
          (r) => StoredRow(r.id, r.payload),
        ),
        'StoredSettings': _CollectionRows(
          _isar.storedSettings,
          (r) => StoredRow(r.id, r.payload),
        ),
        'StoredProfile': _CollectionRows(
          _isar.storedProfiles,
          (r) => StoredRow(r.id, r.payload, entityId: r.entityId),
        ),
        'StoredCredential': _CollectionRows(
          _isar.storedCredentials,
          (r) => StoredRow(r.id, r.payload, entityId: r.entityId),
        ),
        'StoredReceipt': _CollectionRows(
          _isar.storedReceipts,
          (r) => StoredRow(r.id, r.payload, entityId: r.entityId),
        ),
        'StoredHostTrust': _CollectionRows(
          _isar.storedHostTrusts,
          (r) => StoredRow(r.id, r.payload, entityId: r.entityId),
        ),
        'StoredMcpGrant': _CollectionRows(
          _isar.storedMcpGrants,
          (r) => StoredRow(r.id, r.payload, entityId: r.entityId),
        ),
        'StoredDelegation': _CollectionRows(
          _isar.storedDelegations,
          (r) => StoredRow(r.id, r.payload, entityId: r.entityId),
        ),
        'StoredAutomationProfile': _CollectionRows(
          _isar.storedAutomationProfiles,
          (r) => StoredRow(r.id, r.payload, entityId: r.entityId),
        ),
        'StoredAutomationRevision': _CollectionRows(
          _isar.storedAutomationRevisions,
          (r) => StoredRow(r.id, r.payload, entityId: r.entityId),
        ),
        'StoredAutomationPlan': _CollectionRows(
          _isar.storedAutomationPlans,
          (r) => StoredRow(r.id, r.payload, entityId: r.entityId),
        ),
        'StoredAutomationApproval': _CollectionRows(
          _isar.storedAutomationApprovals,
          (r) => StoredRow(r.id, r.payload, entityId: r.entityId),
        ),
        'StoredAutomationJob': _CollectionRows(
          _isar.storedAutomationJobs,
          (r) => StoredRow(r.id, r.payload, entityId: r.entityId),
        ),
        'StoredDesiredState': _CollectionRows(
          _isar.storedDesiredStates,
          (r) => StoredRow(r.id, r.payload, entityId: r.entityId),
        ),
        'StoredAutomationEvent': _CollectionRows(
          _isar.storedAutomationEvents,
          (r) => StoredRow(r.id, r.payload, entityId: r.entityId),
        ),
        'StoredAutomationReceipt': _CollectionRows(
          _isar.storedAutomationReceipts,
          (r) => StoredRow(r.id, r.payload, entityId: r.entityId),
        ),
      };
  final Isar _isar;
  final Map<String, _Rows> _readers;
  @override
  String get name => _isar.name;
  @override
  String get directory =>
      _isar.directory ?? (throw StateError('STORAGE_BLOCKED'));
  @override
  Future<T> readTransaction<T>(Future<T> Function() read) => _isar.txn(read);
  _Rows _reader(String name) =>
      _readers[name] ?? (throw StateError('STORAGE_BLOCKED'));
  @override
  Future<int> count(String collection) => _reader(collection).count();
  @override
  Future<List<StoredRow>> read(String collection, {required int limit}) {
    // desired cap: (250 live profiles + 10000 deleted-profile receipts) * 5,
    // plus one sentinel row. Other families are at most10001.
    if (limit < 1 || limit > 51251) throw StateError('STORAGE_BLOCKED');
    return _reader(collection).read(limit);
  }
}

abstract interface class _Rows {
  Future<int> count();
  Future<List<StoredRow>> read(int limit);
}

final class _CollectionRows<T> implements _Rows {
  _CollectionRows(this.collection, this.convert);
  final IsarCollection<T> collection;
  final StoredRow Function(T) convert;
  @override
  Future<int> count() => collection.count();
  @override
  Future<List<StoredRow>> read(int limit) async => List.unmodifiable([
    for (final value in await collection.where().limit(limit).findAll())
      convert(value),
  ]);
}
