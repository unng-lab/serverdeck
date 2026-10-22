import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/automation/models.dart'
    show ClientGrantRecord;
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_windows/mcp_credential_files.dart';
import 'package:serverdeck_windows/mcp_credentials.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/security.dart';

import '../automation/snapshot.dart';
import 'automation_records.dart';
import 'host_trust_models.dart';
import 'host_trust_records.dart';
import 'key_custody.dart';
import 'migration_rows.dart';
import 'models.dart';
import 'records.dart';

Never _blocked() => throw StateError('STORAGE_BLOCKED');

/// Fully validated retained metadata. Neither this snapshot nor its digest is
/// live authority, native open permission or a verified format3 runtime proof.
final class TrustedOperationalSnapshot {
  TrustedOperationalSnapshot._(
    this.foundation,
    this.automation,
    Map<String, List<MigrationRow>> rows,
  ) : rows = Map.unmodifiable({
        for (final entry in rows.entries)
          entry.key: List<MigrationRow>.unmodifiable(entry.value),
      });
  final HostTrustState foundation;
  final AutomationSnapshot automation;
  final Map<String, List<MigrationRow>> rows;

  /// The exact schema2→3 preservation input. Trust rows are checked separately
  /// (migration requires empty); only the workspace schema marker is omitted.
  String preservationDigest() {
    final sink = const DartSha256().newHashSink(), codec = StrictCodec();
    void text(String value) => sink.add(utf8.encode(value));
    text('{"collections":{');
    final names =
        rows.keys
            .where(
              (name) => name != 'StoredWorkspace' && name != 'StoredHostTrust',
            )
            .toList()
          ..sort();
    for (var i = 0; i < names.length; i++) {
      if (i > 0) text(',');
      sink.add(codec.canonical(names[i]));
      text(':[');
      final values = rows[names[i]]!;
      for (var n = 0; n < values.length; n++) {
        if (n > 0) text(',');
        final row = values[n];
        sink.add(
          codec.canonical({
            'nativeId': row.nativeId,
            'entityId': row.entityId,
            'payloadBase64': base64.encode(utf8.encode(row.payload)),
          }),
        );
      }
      text(']');
    }
    final workspace = rows['StoredWorkspace']!.single;
    final metadata = StrictCodec().decode(
      utf8.encode(workspace.payload),
      maxBytes: 4096,
    )..remove('schemaVersion');
    text('},"workspace":');
    sink.add(
      codec.canonical({'nativeId': workspace.nativeId, 'payload': metadata}),
    );
    text('}');
    sink.close();
    return sink
        .hashSync()
        .bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}

/// Existing schema3 composition only. Caller owns verified format3 native open,
/// registry/manifest/DB/lock custody and the sole-writer queue throughout. This
/// does not open/close Isar, migrate a marker, acquire/release a lease or enable
/// services. Complete graph/DPAPI/key validation precedes pointer publication.
Future<TrustedOperationalSnapshot> readTrustedOperationalSnapshot(
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
      _blocked();
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
        !p.equals(p.normalize(p.absolute(isar.directory!)), files.directory))
      _blocked();
    final raw = <String, List<MigrationRow>>{};
    var totalBytes = 0;
    Map<String, Object?> document(MigrationRow row, int bound) {
      if (row.nativeId < 1 || row.nativeId > 9223372036854775807) _blocked();
      StrictCodec().canonical(row.payload);
      final bytes = utf8.encode(row.payload);
      totalBytes += bytes.length;
      if (bytes.length > bound || totalBytes > 64 * 1024 * 1024) _blocked();
      return StrictCodec().decode(bytes, maxBytes: bound);
    }

    Future<Map<String, Map<String, Object?>>> take<T>(
      IsarCollection<T> collection,
      int cap,
      int bound,
      MigrationRow Function(T) convert, {
      bool singleton = false,
    }) async {
      owner();
      if (await collection.count() > cap) _blocked();
      owner();
      final native = await collection.where().limit(cap + 1).findAll();
      owner();
      if (native.length > cap || (singleton && native.length != 1)) _blocked();
      final rows = <MigrationRow>[], ids = <int>{};
      final docs = <String, Map<String, Object?>>{};
      for (final value in native) {
        final row = convert(value);
        if (!ids.add(row.nativeId) ||
            (singleton && (row.nativeId != 1 || row.entityId != null)))
          _blocked();
        final name = singleton ? 'singleton' : row.entityId;
        if (name == null || docs.containsKey(name)) _blocked();
        docs[name] = document(row, bound);
        rows.add(row);
      }
      rows.sort((a, b) => a.nativeId.compareTo(b.nativeId));
      raw[collection.name] = rows;
      return docs;
    }

    late HostTrustState foundation;
    final groups = <String, List<AutomationSnapshotRow>>{};
    // One real native read transaction captures a coherent16-collection view.
    await isar.txn(() async {
      final metadata = (await take(
        isar.storedWorkspaces,
        1,
        4096,
        (r) => MigrationRow(r.id, r.payload),
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
        isar.storedSettings,
        1,
        4096,
        (r) => MigrationRow(r.id, r.payload),
        singleton: true,
      ))['singleton']!;
      final profiles = await take(
        isar.storedProfiles,
        250,
        16 * 1024,
        (r) => MigrationRow(r.id, r.payload, entityId: r.entityId),
      );
      final credentials = await take(
        isar.storedCredentials,
        250,
        512 * 1024,
        (r) => MigrationRow(r.id, r.payload, entityId: r.entityId),
      );
      final receipts = await take(
        isar.storedReceipts,
        10000,
        4096,
        (r) => MigrationRow(r.id, r.payload, entityId: r.entityId),
      );
      final state = WorkspaceState.fromTrustedJson(
        {
          ...metadata,
          'settings': settings,
          'profiles': profiles,
          'credentials': credentials,
          'receipts': receipts,
        },
        workspaceId: key.workspaceId,
        receiptKeyId: key.receiptKeyId,
        ownerSid: key.ownerSid,
      );
      final trust = await take(
        isar.storedHostTrusts,
        250,
        4096,
        (r) => MigrationRow(r.id, r.payload, entityId: r.entityId),
      );
      foundation = HostTrustState.fromRecords(state, {
        for (final entry in trust.entries)
          entry.key: HostTrustRecord.fromJson(entry.value),
      });
      final knownServers = state.profiles.keys.toSet();
      for (final receipt in state.receipts.values) {
        if (receipt.operation == 'profiles.delete' && receipt.result.deleted)
          knownServers.add(receipt.result.entityId!);
      }
      Future<void> group<T>(
        String name,
        IsarCollection<T> collection,
        int cap,
        MigrationRow Function(T) convert, {
        int bound = 256 * 1024,
      }) async {
        await take(collection, cap, bound, convert);
        groups[name] = [
          for (final row in raw[collection.name]!)
            AutomationSnapshotRow(row.nativeId, row.entityId!, row.payload),
        ];
      }

      await group(
        'grants',
        isar.storedMcpGrants,
        32,
        (r) => MigrationRow(r.id, r.payload, entityId: r.entityId),
      );
      await group(
        'delegations',
        isar.storedDelegations,
        1000,
        (r) => MigrationRow(r.id, r.payload, entityId: r.entityId),
      );
      await group(
        'profiles',
        isar.storedAutomationProfiles,
        250,
        (r) => MigrationRow(r.id, r.payload, entityId: r.entityId),
      );
      await group(
        'revisions',
        isar.storedAutomationRevisions,
        5000,
        (r) => MigrationRow(r.id, r.payload, entityId: r.entityId),
      );
      await group(
        'plans',
        isar.storedAutomationPlans,
        1000,
        (r) => MigrationRow(r.id, r.payload, entityId: r.entityId),
      );
      await group(
        'approvals',
        isar.storedAutomationApprovals,
        100,
        (r) => MigrationRow(r.id, r.payload, entityId: r.entityId),
      );
      await group(
        'jobs',
        isar.storedAutomationJobs,
        1250,
        (r) => MigrationRow(r.id, r.payload, entityId: r.entityId),
      );
      await group(
        'desired',
        isar.storedDesiredStates,
        knownServers.length * 5,
        (r) => MigrationRow(r.id, r.payload, entityId: r.entityId),
      );
      await group(
        'events',
        isar.storedAutomationEvents,
        10000,
        (r) => MigrationRow(r.id, r.payload, entityId: r.entityId),
        bound: 4096,
      );
      await group(
        'receipts',
        isar.storedAutomationReceipts,
        10000,
        (r) => MigrationRow(r.id, r.payload, entityId: r.entityId),
        bound: 8192,
      );
    });
    await live();
    for (final credential in foundation.foundation.credentials.values) {
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
    final automation = await AutomationSnapshot.loadTrusted(
      foundation: foundation,
      collections: groups,
    );
    await live();
    await files.validateInventory();
    await live();
    McpCredentialBinding binding(ClientGrantRecord grant) =>
        McpCredentialBinding(
          workspaceId: grant.workspaceId,
          grantId: grant.id,
          secretRef: grant.secretRef,
          ownerSid: key.ownerSid,
          issuedAt: grant.issuedAt.toIso8601String(),
        );
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
    for (final grant in automation.grants.values) {
      await live();
      await files.publish(binding(grant), revoked: grant.revokedAt != null);
    }
    await live();
    return TrustedOperationalSnapshot._(foundation, automation, raw);
  } catch (error) {
    if (error is StateError && error.message == 'INCOMPATIBLE') rethrow;
    _blocked();
  }
}
