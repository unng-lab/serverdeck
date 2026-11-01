import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/automation/models.dart'
    show ClientGrantRecord;
import 'package:serverdeck_protocol/validation.dart';

import '../automation/snapshot.dart';
import '../credentials/mcp_credential_files.dart';
import '../credentials/mcp_credentials.dart';
import '../platform/ports.dart';
import 'host_trust_models.dart';
import 'key_custody.dart';
import 'models.dart';
import 'workspace_rows.dart';

Never _blocked() => throw StateError('STORAGE_BLOCKED');

/// Fully validated retained metadata. This snapshot is not
/// live authority, native open permission or a verified runtime proof.
final class WorkspaceSnapshot {
  WorkspaceSnapshot._(
    this.foundation,
    this.automation,
    Map<String, List<StoredRow>> rows,
  ) : rows = Map.unmodifiable({
        for (final entry in rows.entries)
          entry.key: List<StoredRow>.unmodifiable(entry.value),
      });
  final HostTrustState foundation;
  final AutomationSnapshot automation;
  final Map<String, List<StoredRow>> rows;
}

/// Existing schema3 composition only. Caller owns verified native open,
/// registry/manifest/DB/lock custody and the sole-writer queue throughout. This
/// does not open/close Isar, migrate a marker, acquire/release a lease or enable
/// services. Complete graph/key validation precedes pointer publication.
/// Reconciles MCP lookup files after validation; this is not the read-only
/// semantic startup preflight and cannot grant permission to open a database.
Future<WorkspaceSnapshot> readWorkspaceSnapshot(
  WorkspaceRowSource source,
  ReceiptKeyMaterial key,
  KeyCustody custody, {
  required String localAppData,
  required WorkspaceLease lease,
  required ProtectedFiles protectedFiles,
}) async {
  return _readWorkspace(
    source,
    key,
    custody,
    localAppData: localAppData,
    lease: lease,
    protectedFiles: protectedFiles,
    initial: false,
    recoverLookups: true,
  );
}

/// Read-only validation of the one fixed protected fresh schema3 creation stage.
/// Only the default empty graph is accepted; it cannot import grants or jobs.
Future<WorkspaceSnapshot> readInitialWorkspace(
  WorkspaceRowSource source,
  ReceiptKeyMaterial key,
  KeyCustody custody, {
  required String localAppData,
  required WorkspaceLease lease,
  required ProtectedFiles protectedFiles,
}) async {
  return _readWorkspace(
    source,
    key,
    custody,
    localAppData: localAppData,
    lease: lease,
    protectedFiles: protectedFiles,
    initial: true,
    recoverLookups: false,
  );
}

/// Full graph/custody/artifact validation with no lookup publication or writes.
/// This accepts a detached native-byte source before any writable DB open.
Future<WorkspaceSnapshot> inspectWorkspaceSnapshot(
  WorkspaceRowSource source,
  ReceiptKeyMaterial key,
  KeyCustody custody, {
  required String localAppData,
  required WorkspaceLease lease,
  required ProtectedFiles protectedFiles,
}) => _readWorkspace(
  source,
  key,
  custody,
  localAppData: localAppData,
  lease: lease,
  protectedFiles: protectedFiles,
  initial: false,
  recoverLookups: false,
);

Future<WorkspaceSnapshot> _readWorkspace(
  WorkspaceRowSource source,
  ReceiptKeyMaterial key,
  KeyCustody custody, {
  required String localAppData,
  required WorkspaceLease lease,
  required ProtectedFiles protectedFiles,
  required bool initial,
  required bool recoverLookups,
}) async {
  void owner() {
    if (protectedFiles.root != localAppData ||
        !lease.isHeld ||
        lease.workspaceSlot != 'default' ||
        lease.ownerIdentity != custody.ownerSid ||
        protectedFiles.ownerIdentity != custody.ownerSid ||
        key.ownerSid != custody.ownerSid)
      _blocked();
    protectedFiles.requirePath(localAppData);
  }

  Future<void> live() async {
    owner();
    await custody.createWorkspaceManifest(key);
    owner();
  }

  try {
    await live();
    final files = McpCredentialFiles(
      protectedFiles: protectedFiles,
      localAppData: localAppData,
      workspaceId: key.workspaceId,
      ownerSid: key.ownerSid,
      custody: McpCredentialCustody(custody.protection),
    );
    final expected = initial ? '${files.directory}.creating' : files.directory;
    if (source.name != 'workspace' ||
        !p.equals(p.normalize(p.absolute(source.directory)), expected))
      _blocked();
    var path = p.normalize(p.absolute(localAppData));
    for (final name in [
      'ServerDeckNext',
      'v1',
      'workspaces',
      initial ? 'default.creating' : 'default',
    ]) {
      path = p.join(path, name);
      protectedFiles.requirePath(path);
      if (protectedFiles.kind(path) != ProtectedPathKind.directory) _blocked();
      protectedFiles.requireOwnerOnly(path);
    }
    for (final name in ['workspace.isar', 'workspace.isar-lck']) {
      final path = p.join(expected, name);
      protectedFiles.requirePath(path);
      if (protectedFiles.kind(path) != ProtectedPathKind.file) _blocked();
      protectedFiles.requireOwnerOnly(path);
    }
    final raw = <String, List<StoredRow>>{};
    var totalBytes = 0;
    Map<String, Object?> document(StoredRow row, int bound) {
      if (row.nativeId < 1 || row.nativeId > 9223372036854775807) _blocked();
      StrictCodec().canonical(row.payload);
      final bytes = utf8.encode(row.payload);
      totalBytes += bytes.length;
      if (bytes.length > bound || totalBytes > 64 * 1024 * 1024) _blocked();
      return StrictCodec().decode(bytes, maxBytes: bound);
    }

    Future<Map<String, Map<String, Object?>>> take(
      String collection,
      int cap,
      int bound, {
      bool singleton = false,
    }) async {
      owner();
      final count = await source.count(collection);
      if (count < 0 || count > cap) _blocked();
      owner();
      final native = await source.read(collection, limit: cap + 1);
      owner();
      if (native.length != count ||
          native.length > cap ||
          (singleton && native.length != 1))
        _blocked();
      final rows = <StoredRow>[], ids = <int>{};
      final docs = <String, Map<String, Object?>>{};
      for (final value in native) {
        final row = value;
        if (!ids.add(row.nativeId) ||
            (singleton && (row.nativeId != 1 || row.entityId != null)))
          _blocked();
        final name = singleton ? 'singleton' : row.entityId;
        if (name == null || docs.containsKey(name)) _blocked();
        docs[name] = document(row, bound);
        rows.add(row);
      }
      rows.sort((a, b) => a.nativeId.compareTo(b.nativeId));
      raw[collection] = rows;
      return docs;
    }

    late WorkspaceState state;
    late HostTrustState foundation;
    final groups = <String, List<AutomationSnapshotRow>>{};
    // One source read transaction captures a coherent16-collection view.
    await source.readTransaction(() async {
      final metadata = (await take(
        'StoredWorkspace',
        1,
        4096,
        singleton: true,
      ))['singleton']!;
      requireFields(metadata, {
        'schemaVersion',
        'workspaceId',
        'receiptKeyId',
        'ownerSid',
        'storeRevision',
      });
      if (metadata['schemaVersion'] is! int || metadata['schemaVersion'] != 3)
        throw StateError('INCOMPATIBLE');
      final settings = (await take(
        'StoredSettings',
        1,
        4096,
        singleton: true,
      ))['singleton']!;
      final profiles = await take('StoredProfile', 250, 16 * 1024);
      final credentials = await take('StoredCredential', 250, 512 * 1024);
      final receipts = await take('StoredReceipt', 10000, 4096);
      final foundationDocument = {
        ...metadata,
        'settings': settings,
        'profiles': profiles,
        'credentials': credentials,
        'receipts': receipts,
      };
      state = WorkspaceState.fromJson(
        foundationDocument,
        workspaceId: key.workspaceId,
        receiptKeyId: key.receiptKeyId,
        ownerSid: key.ownerSid,
      );
      final trust = await take('StoredHostTrust', 250, 4096);
      foundation = HostTrustState.fromRecords(state, {
        for (final entry in trust.entries)
          entry.key: HostTrustRecord.fromJson(entry.value),
      });
      final knownServers = state.profiles.keys.toSet();
      for (final receipt in state.receipts.values) {
        if (receipt.operation == 'profiles.delete' && receipt.result.deleted)
          knownServers.add(receipt.result.entityId!);
      }
      Future<void> group(
        String name,
        String collection,
        int cap, {
        int bound = 256 * 1024,
      }) async {
        await take(collection, cap, bound);
        groups[name] = [
          for (final row in raw[collection]!)
            AutomationSnapshotRow(row.nativeId, row.entityId!, row.payload),
        ];
      }

      await group('grants', 'StoredMcpGrant', 32);
      await group('delegations', 'StoredDelegation', 1000);
      await group('profiles', 'StoredAutomationProfile', 250);
      await group('revisions', 'StoredAutomationRevision', 5000);
      await group('plans', 'StoredAutomationPlan', 1000);
      await group('approvals', 'StoredAutomationApproval', 100);
      await group('jobs', 'StoredAutomationJob', 1250);
      await group('desired', 'StoredDesiredState', knownServers.length * 5);
      await group('events', 'StoredAutomationEvent', 10000, bound: 4096);
      await group('receipts', 'StoredAutomationReceipt', 10000, bound: 8192);
    });
    await live();
    if (initial &&
        (!state.isInitialEmpty ||
            raw.entries.any(
              (entry) =>
                  !{'StoredWorkspace', 'StoredSettings'}.contains(entry.key) &&
                  entry.value.isNotEmpty,
            )))
      _blocked();
    for (final credential in state.credentials.values) {
      await live();
      final secret = await custody.openCredential(
        credential.protectedBlob,
        key.workspaceId,
        credential.profileId,
        credential.id,
      );
      try {
        if (secret['kind'] != credential.kind.name) _blocked();
        await live();
      } finally {
        secret.clear();
      }
    }
    await live();
    final automation = await AutomationSnapshot.load(
      foundation: foundation,
      collections: groups,
    );
    await live();
    await _mcpArtifacts(
      automation,
      files,
      key,
      live,
      initial: initial,
      publish: recoverLookups,
    );
    return WorkspaceSnapshot._(foundation, automation, raw);
  } catch (error) {
    if (error is StateError && error.message == 'INCOMPATIBLE') rethrow;
    _blocked();
  }
}

/// Reconcile only after the reopened native rows match the validated preflight.
/// The host still owns the single writer queue and publication/target authority.
Future<void> recoverWorkspaceLookups(
  WorkspaceSnapshot snapshot, {
  required ProtectedFiles files,
  required WorkspaceLease lease,
  required ReceiptKeyMaterial key,
  required KeyCustody custody,
}) async {
  final root = files.root;
  void owner() {
    if (!lease.isHeld ||
        lease.workspaceSlot != 'default' ||
        files.root != root ||
        lease.ownerIdentity != key.ownerSid ||
        files.ownerIdentity != key.ownerSid ||
        custody.ownerSid != key.ownerSid ||
        snapshot.foundation.foundation.ownerSid != key.ownerSid ||
        snapshot.foundation.foundation.workspaceId != key.workspaceId ||
        snapshot.foundation.foundation.receiptKeyId != key.receiptKeyId)
      _blocked();
    files.requirePath(root);
  }

  Future<void> live() async {
    owner();
    await custody.createWorkspaceManifest(key);
    owner();
  }

  try {
    await live();
    final artifacts = McpCredentialFiles(
      protectedFiles: files,
      localAppData: root,
      workspaceId: key.workspaceId,
      ownerSid: key.ownerSid,
      custody: McpCredentialCustody(custody.protection),
    );
    await _mcpArtifacts(
      snapshot.automation,
      artifacts,
      key,
      live,
      initial: false,
      publish: true,
    );
  } catch (_) {
    _blocked();
  }
}

Future<void> _mcpArtifacts(
  AutomationSnapshot automation,
  McpCredentialFiles files,
  ReceiptKeyMaterial key,
  Future<void> Function() live, {
  required bool initial,
  required bool publish,
}) async {
  if (!initial) await files.validateInventory();
  await live();
  McpCredentialBinding binding(ClientGrantRecord grant) => McpCredentialBinding(
    workspaceId: grant.workspaceId,
    grantId: grant.id,
    secretRef: grant.secretRef,
    ownerSid: key.ownerSid,
    issuedAt: grant.issuedAt.toIso8601String(),
  );
  // Every retained grant is validated before the first pointer can be published.
  for (final grant in automation.grants.values) {
    final clientKey = await files.openReferenced(binding(grant));
    try {
      await live();
    } finally {
      clientKey.close();
    }
  }
  for (final grant in automation.grants.values) {
    await files.readLookupForRecovery(grant.id);
    await live();
  }
  if (publish) {
    for (final grant in automation.grants.values) {
      await live();
      await files.publish(binding(grant), revoked: grant.revokedAt != null);
    }
  }
  await live();
}

/// Exact native IDs, business IDs and original payload bytes; never normalize
/// persisted bytes when comparing preflight with the subsequently reopened DB.
void requireSameWorkspaceRows(
  WorkspaceSnapshot expected,
  WorkspaceSnapshot actual,
) {
  if (expected.rows.length != actual.rows.length) _blocked();
  for (final entry in expected.rows.entries) {
    final rows = actual.rows[entry.key];
    if (rows == null || rows.length != entry.value.length) _blocked();
    for (var i = 0; i < rows.length; i++) {
      final before = entry.value[i], after = rows[i];
      if (before.nativeId != after.nativeId ||
          before.entityId != after.entityId ||
          before.payload != after.payload)
        _blocked();
    }
  }
}
