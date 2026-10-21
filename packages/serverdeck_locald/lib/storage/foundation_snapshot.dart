import 'dart:convert';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/automation/models.dart'
    show ClientGrantRecord;
import 'package:serverdeck_windows/mcp_credentials.dart';
import 'package:serverdeck_windows/mcp_credential_files.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/security.dart';

import '../automation/snapshot.dart';

import 'automation_records.dart';
import 'credential_validation.dart';
import 'key_custody.dart';
import 'migration_rows.dart';
import 'models.dart';
import 'records.dart';

final class FoundationSnapshot {
  const FoundationSnapshot(this.state, this.rows);

  /// Existing logical foundation state, always using its schema1 model. The
  /// physical target marker is checked before this temporary compatibility view.
  final WorkspaceState state;
  final MigrationRows rows;
}

/// Complete foundation row/reference/DPAPI gate, without opening/closing Isar.
/// Schema2 mode is only the freshly migrated, empty automation state. It cannot
/// silently load an operational schema2 workspace and discard automation data.
/// Migration callers must use a protected copy; normal schema1 open may use its
/// owned active instance. File custody/sole-writer/native preflight are caller gates.
Future<FoundationSnapshot> readFoundationSnapshot(
  Isar isar,
  ReceiptKeyMaterial key,
  KeyCustody custody, {
  int expectedSchema = 1,
}) async {
  if (expectedSchema != 1 && expectedSchema != 2)
    throw StateError('INCOMPATIBLE');
  // Also proves material is live, even when no server credential exists.
  await custody.createWorkspaceManifest(key);
  if (expectedSchema == 2) {
    for (final collection in [
      isar.storedMcpGrants,
      isar.storedDelegations,
      isar.storedAutomationProfiles,
      isar.storedAutomationRevisions,
      isar.storedAutomationPlans,
      isar.storedAutomationApprovals,
      isar.storedAutomationJobs,
      isar.storedDesiredStates,
      isar.storedAutomationReceipts,
      isar.storedAutomationEvents,
    ]) {
      if (await collection.count() != 0) throw StateError('STORAGE_BLOCKED');
    }
  }
  return _readFoundationRows(isar, key, custody, expectedSchema);
}

Future<FoundationSnapshot> _readFoundationRows(
  Isar isar,
  ReceiptKeyMaterial key,
  KeyCustody custody,
  int expectedSchema,
) async {
  await custody.createWorkspaceManifest(key);
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
  Map<String, Object?> document(String value, int bound) {
    try {
      return StrictCodec().decode(utf8.encode(value), maxBytes: bound);
    } on FormatException {
      throw StateError('STORAGE_BLOCKED');
    }
  }

  final metadata = document(workspace.payload, 4096);
  if (metadata.keys.toSet().difference({
        'schemaVersion',
        'workspaceId',
        'receiptKeyId',
        'ownerSid',
        'storeRevision',
      }).isNotEmpty ||
      metadata.length != 5)
    throw StateError('STORAGE_BLOCKED');
  if (metadata['schemaVersion'] is! int ||
      metadata['schemaVersion'] != expectedSchema)
    throw StateError('INCOMPATIBLE');
  final profiles = await isar.storedProfiles.where().findAll();
  final credentials = await isar.storedCredentials.where().findAll();
  final receipts = await isar.storedReceipts.where().findAll();
  final rows = MigrationRows.capture(
    schema: expectedSchema,
    workspace: MigrationRow(workspace.id, workspace.payload),
    settings: MigrationRow(settings.id, settings.payload),
    profiles: [
      for (final row in profiles)
        MigrationRow(row.id, row.payload, entityId: row.entityId),
    ],
    credentials: [
      for (final row in credentials)
        MigrationRow(row.id, row.payload, entityId: row.entityId),
    ],
    receipts: [
      for (final row in receipts)
        MigrationRow(row.id, row.payload, entityId: row.entityId),
    ],
  );
  Map<String, Object?> entities(List<(int, String, String)> input, int bound) =>
      {for (final row in input) row.$2: document(row.$3, bound)};
  final state = WorkspaceState.fromJson(
    {
      ...metadata,
      'schemaVersion': 1,
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
  await validateWorkspaceCredentials(state, custody);
  return FoundationSnapshot(state, rows);
}

final class OperationalSnapshot {
  OperationalSnapshot._(
    this.foundation,
    this.automation,
    Map<String, List<AutomationSnapshotRow>> rows,
  ) : rows = Map.unmodifiable({
        for (final entry in rows.entries)
          entry.key: List<AutomationSnapshotRow>.unmodifiable(entry.value),
      });
  final FoundationSnapshot foundation;
  final AutomationSnapshot automation;

  /// Exact internal storage rows, retained without DTO reserialization.
  final Map<String, List<AutomationSnapshotRow>> rows;
}

/// Complete existing-open composition only. Caller owns native preflight/open,
/// manifest/key/file custody and the sole-writer reservation throughout this
/// call. This neither opens/closes Isar nor changes physical schema/DB rows.
Future<OperationalSnapshot> readOperationalSnapshot(
  Isar isar,
  ReceiptKeyMaterial key,
  KeyCustody custody, {
  required String localAppData,
  required MutexLease lease,
}) async {
  void owner() {
    if (!lease.isHeld ||
        custody.ownerSid != currentUserSid() ||
        key.ownerSid != custody.ownerSid)
      throw StateError('STORAGE_BLOCKED');
  }

  Future<void> live() async {
    owner();
    await custody.createWorkspaceManifest(key);
    owner();
  }

  try {
    await live();
    final files = McpCredentialFiles(
      localAppData: localAppData,
      workspaceId: key.workspaceId,
      ownerSid: key.ownerSid,
      custody: McpCredentialCustody(custody.protection),
    );
    if (isar.name != 'workspace' ||
        isar.directory == null ||
        !p.equals(p.normalize(p.absolute(isar.directory!)), files.directory)) {
      throw StateError('STORAGE_BLOCKED');
    }
    final foundation = await _readFoundationRows(isar, key, custody, 2);
    await live();
    final knownServers = foundation.state.profiles.keys.toSet();
    for (final receipt in foundation.state.receipts.values) {
      if (receipt.operation == 'profiles.delete' && receipt.result.deleted) {
        if (receipt.result.entityId == null ||
            receipt.result.entityId != receipt.toJson()['profileId'])
          throw StateError('STORAGE_BLOCKED');
        knownServers.add(receipt.result.entityId!);
      }
    }
    Future<List<AutomationSnapshotRow>> take<T>(
      IsarCollection<T> collection,
      int cap,
      AutomationSnapshotRow Function(T) convert,
    ) async {
      if (await collection.count() > cap) throw StateError('STORAGE_BLOCKED');
      owner();
      final rows = await collection.where().limit(cap + 1).findAll();
      if (rows.length > cap) throw StateError('STORAGE_BLOCKED');
      owner();
      return [for (final row in rows) convert(row)];
    }

    final collections = {
      'grants': await take(
        isar.storedMcpGrants,
        32,
        (r) => AutomationSnapshotRow(r.id, r.entityId, r.payload),
      ),
      'delegations': await take(
        isar.storedDelegations,
        1000,
        (r) => AutomationSnapshotRow(r.id, r.entityId, r.payload),
      ),
      'profiles': await take(
        isar.storedAutomationProfiles,
        250,
        (r) => AutomationSnapshotRow(r.id, r.entityId, r.payload),
      ),
      'revisions': await take(
        isar.storedAutomationRevisions,
        5000,
        (r) => AutomationSnapshotRow(r.id, r.entityId, r.payload),
      ),
      'plans': await take(
        isar.storedAutomationPlans,
        1000,
        (r) => AutomationSnapshotRow(r.id, r.entityId, r.payload),
      ),
      'approvals': await take(
        isar.storedAutomationApprovals,
        100,
        (r) => AutomationSnapshotRow(r.id, r.entityId, r.payload),
      ),
      'jobs': await take(
        isar.storedAutomationJobs,
        1250,
        (r) => AutomationSnapshotRow(r.id, r.entityId, r.payload),
      ),
      'desired': await take(
        isar.storedDesiredStates,
        knownServers.length * 5,
        (r) => AutomationSnapshotRow(r.id, r.entityId, r.payload),
      ),
      'events': await take(
        isar.storedAutomationEvents,
        10000,
        (r) => AutomationSnapshotRow(r.id, r.entityId, r.payload),
      ),
      'receipts': await take(
        isar.storedAutomationReceipts,
        10000,
        (r) => AutomationSnapshotRow(r.id, r.entityId, r.payload),
      ),
    };
    final graph = await AutomationSnapshot.load(
      foundation: foundation.state,
      collections: collections,
    );
    await live();
    await files.validateInventory();
    McpCredentialBinding binding(ClientGrantRecord grant) =>
        McpCredentialBinding(
          workspaceId: grant.workspaceId,
          grantId: grant.id,
          secretRef: grant.secretRef,
          ownerSid: key.ownerSid,
          issuedAt: grant.issuedAt.toIso8601String(),
        );
    for (final grant in graph.grants.values) {
      final clientKey = await files.openReferenced(binding(grant));
      try {
        await live();
      } finally {
        clientKey.close();
      }
    }
    for (final grant in graph.grants.values) {
      await files.readLookupForRecovery(grant.id);
      await live();
    }
    for (final grant in graph.grants.values) {
      await live();
      await files.publish(binding(grant), revoked: grant.revokedAt != null);
    }
    await live();
    return OperationalSnapshot._(foundation, graph, collections);
  } catch (error) {
    if (error is StateError && error.message == 'INCOMPATIBLE') rethrow;
    throw StateError('STORAGE_BLOCKED');
  }
}
