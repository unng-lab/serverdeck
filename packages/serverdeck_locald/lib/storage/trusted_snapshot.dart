import 'dart:convert';
import 'dart:io';

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
import 'package:serverdeck_windows/paths.dart';
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
  String preservationDigest() => _preservationDigest(rows);
}

/// Validated migration metadata, never open permission or service authority.
/// Source2 foundation uses the existing schema1 compatibility model; raw rows
/// retain the actual schema2 marker. Target3 retains its explicit schema3 model.
final class UpgradeSnapshot {
  UpgradeSnapshot._(
    this.foundation,
    this.automation,
    Map<String, List<MigrationRow>> rows,
  ) : rows = Map.unmodifiable({
        for (final e in rows.entries)
          e.key: List<MigrationRow>.unmodifiable(e.value),
      });
  final WorkspaceState foundation;
  final AutomationSnapshot automation;
  final Map<String, List<MigrationRow>> rows;
  String preservationDigest() => _preservationDigest(rows);
}

String _preservationDigest(Map<String, List<MigrationRow>> rows) {
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

enum _CaptureKind { trusted, preflight, source, target }

/// Existing-open source2 capture before stage/hash bindings. The caller owns
/// verified format3 runtime, exact schema2 native open/file identity, global
/// reservation and lease, and confirms close before HOST_BUSY or hash freeze.
/// This entry performs no lookup publication, native open/close or DB writes.
Future<UpgradeSnapshot> readSchema2UpgradePreflight(
  Isar isar,
  ReceiptKeyMaterial key,
  KeyCustody custody, {
  required String localAppData,
  required MutexLease lease,
}) async => (await _readCapture(
  isar,
  key,
  custody,
  localAppData: localAppData,
  lease: lease,
  kind: _CaptureKind.preflight,
)).upgrade;

/// Existing-open protected source2 copy only. The migration controller owns
/// journal/hash/manifest/native registry binding and confirmed physical close.
Future<UpgradeSnapshot> readSchema2UpgradeSource(
  Isar isar,
  ReceiptKeyMaterial key,
  KeyCustody custody, {
  required String localAppData,
  required MutexLease lease,
}) async => (await _readCapture(
  isar,
  key,
  custody,
  localAppData: localAppData,
  lease: lease,
  kind: _CaptureKind.source,
)).upgrade;

/// Existing-open protected target3 copy only, requiring empty trust and terminal
/// jobs. Neither missing credential lookup nor a stale one is repaired here.
Future<UpgradeSnapshot> readSchema3UpgradeTarget(
  Isar isar,
  ReceiptKeyMaterial key,
  KeyCustody custody, {
  required String localAppData,
  required MutexLease lease,
}) async => (await _readCapture(
  isar,
  key,
  custody,
  localAppData: localAppData,
  lease: lease,
  kind: _CaptureKind.target,
)).upgrade;

final class _Capture {
  const _Capture(this.upgrade, this.trust);
  final UpgradeSnapshot upgrade;
  final HostTrustState? trust;
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
  final result = await _readCapture(
    isar,
    key,
    custody,
    localAppData: localAppData,
    lease: lease,
    kind: _CaptureKind.trusted,
  );
  return TrustedOperationalSnapshot._(
    result.trust!,
    result.upgrade.automation,
    result.upgrade.rows,
  );
}

Future<_Capture> _readCapture(
  Isar isar,
  ReceiptKeyMaterial key,
  KeyCustody custody, {
  required String localAppData,
  required MutexLease lease,
  required _CaptureKind kind,
}) async {
  final schema3 = kind == _CaptureKind.trusted || kind == _CaptureKind.target;
  final migration = kind != _CaptureKind.trusted;
  final staged = kind == _CaptureKind.source || kind == _CaptureKind.target;
  void owner() {
    if (!lease.isHeld ||
        custody.ownerSid != currentUserSid() ||
        key.ownerSid != custody.ownerSid)
      _blocked();
  }

  Future<void> live() async {
    owner();
    if (schema3) {
      await custody.createTrustedWorkspaceManifest(key);
    } else {
      await custody.createWorkspaceManifest(key);
    }
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
    final expected = staged
        ? '${files.directory}.upgrading-2-3'
        : files.directory;
    if (isar.name != 'workspace' ||
        isar.directory == null ||
        !p.equals(p.normalize(p.absolute(isar.directory!)), expected))
      _blocked();
    if (migration) {
      var path = p.normalize(p.absolute(localAppData));
      for (final name in [
        'ServerDeckNext',
        'v1',
        'workspaces',
        staged ? 'default.upgrading-2-3' : 'default',
      ]) {
        path = p.join(path, name);
        requireSafePath(localAppData, path);
        if (FileSystemEntity.typeSync(path, followLinks: false) !=
            FileSystemEntityType.directory)
          _blocked();
        requireOwnerOnlyFileAcl(path, key.ownerSid);
      }
      for (final name in ['workspace.isar', 'workspace.isar-lck']) {
        final path = p.join(expected, name);
        requireSafePath(localAppData, path);
        if (FileSystemEntity.typeSync(path, followLinks: false) !=
            FileSystemEntityType.file)
          _blocked();
        requireOwnerOnlyFileAcl(path, key.ownerSid);
      }
      if (kind == _CaptureKind.preflight) {
        for (final suffix in [
          '.creating',
          '.upgrading-1-2',
          '.upgrading-2-3',
        ]) {
          final stage = '${files.directory}$suffix';
          requireSafePath(localAppData, stage);
          final type = FileSystemEntity.typeSync(stage, followLinks: false);
          if (type == FileSystemEntityType.notFound) continue;
          if (suffix != '.upgrading-2-3' ||
              type != FileSystemEntityType.directory)
            _blocked();
          requireOwnerOnlyFileAcl(stage, key.ownerSid);
          if (!await Directory(stage).list(followLinks: false).isEmpty)
            _blocked();
        }
      }
    }
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

    late WorkspaceState state;
    HostTrustState? foundation;
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
      if (metadata['schemaVersion'] is! int ||
          metadata['schemaVersion'] != (schema3 ? 3 : 2))
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
      final foundationDocument = {
        ...metadata,
        'settings': settings,
        'profiles': profiles,
        'credentials': credentials,
        'receipts': receipts,
      };
      state = schema3
          ? WorkspaceState.fromTrustedJson(
              foundationDocument,
              workspaceId: key.workspaceId,
              receiptKeyId: key.receiptKeyId,
              ownerSid: key.ownerSid,
            )
          : WorkspaceState.fromJson(
              {...foundationDocument, 'schemaVersion': 1},
              workspaceId: key.workspaceId,
              receiptKeyId: key.receiptKeyId,
              ownerSid: key.ownerSid,
            );
      if (schema3) {
        final trust = await take(
          isar.storedHostTrusts,
          250,
          4096,
          (r) => MigrationRow(r.id, r.payload, entityId: r.entityId),
        );
        if (kind == _CaptureKind.target && trust.isNotEmpty) _blocked();
        foundation = HostTrustState.fromRecords(state, {
          for (final entry in trust.entries)
            entry.key: HostTrustRecord.fromJson(entry.value),
        });
      }
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
    final automation = schema3
        ? await AutomationSnapshot.loadTrusted(
            foundation: foundation!,
            collections: groups,
          )
        : await AutomationSnapshot.load(foundation: state, collections: groups);
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
    if (migration &&
        automation.jobs.values.any(
          (job) => !{'succeeded', 'failed', 'cancelled'}.contains(job.state),
        )) {
      throw StateError(
        kind == _CaptureKind.preflight ? 'HOST_BUSY' : 'STORAGE_BLOCKED',
      );
    }
    if (!migration) {
      for (final grant in automation.grants.values) {
        await live();
        await files.publish(binding(grant), revoked: grant.revokedAt != null);
      }
    }
    await live();
    return _Capture(UpgradeSnapshot._(state, automation, raw), foundation);
  } catch (error) {
    if (error is StateError && error.message == 'INCOMPATIBLE') rethrow;
    if (kind == _CaptureKind.preflight &&
        error is StateError &&
        error.message == 'HOST_BUSY')
      rethrow;
    _blocked();
  }
}
