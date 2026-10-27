import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/automation/snapshot.dart';
import 'package:serverdeck_locald/storage/automation_records.dart';
import 'package:serverdeck_locald/storage/foundation_snapshot.dart';
import 'package:serverdeck_locald/storage/host_trust_records.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/models.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_locald/storage/trusted_snapshot.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mcp_credentials.dart';
import 'package:serverdeck_windows/mcp_credential_files.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';

import '../automation/snapshot_test.dart' as g;
import 'trusted_schema_child.dart' as raw;

void check(bool value) {
  if (!value) throw StateError('TRUSTED_SNAPSHOT_FIXTURE_FAILED');
}

Future<void> seedAutomation(
  Isar db,
  Map<String, List<AutomationSnapshotRow>> rows,
) async {
  Future<void> put<T>(
    IsarCollection<T> col,
    String name,
    T Function(AutomationSnapshotRow) make,
  ) async {
    await col.putAll([for (final row in rows[name]!) make(row)]);
  }

  await put(
    db.storedMcpGrants,
    'grants',
    (r) => StoredMcpGrant()
      ..id = r.nativeId + 100
      ..entityId = r.entityId
      ..payload = r.payload,
  );
  await put(
    db.storedDelegations,
    'delegations',
    (r) => StoredDelegation()
      ..id = r.nativeId + 100
      ..entityId = r.entityId
      ..payload = r.payload,
  );
  await put(
    db.storedAutomationProfiles,
    'profiles',
    (r) => StoredAutomationProfile()
      ..id = r.nativeId + 100
      ..entityId = r.entityId
      ..payload = r.payload,
  );
  await put(
    db.storedAutomationRevisions,
    'revisions',
    (r) => StoredAutomationRevision()
      ..id = r.nativeId + 100
      ..entityId = r.entityId
      ..payload = r.payload,
  );
  await put(
    db.storedAutomationPlans,
    'plans',
    (r) => StoredAutomationPlan()
      ..id = r.nativeId + 100
      ..entityId = r.entityId
      ..payload = r.payload,
  );
  await put(
    db.storedAutomationApprovals,
    'approvals',
    (r) => StoredAutomationApproval()
      ..id = r.nativeId + 100
      ..entityId = r.entityId
      ..payload = r.payload,
  );
  await put(
    db.storedAutomationJobs,
    'jobs',
    (r) => StoredAutomationJob()
      ..id = r.nativeId + 100
      ..entityId = r.entityId
      ..payload = r.payload,
  );
  await put(
    db.storedDesiredStates,
    'desired',
    (r) => StoredDesiredState()
      ..id = r.nativeId + 100
      ..entityId = r.entityId
      ..payload = r.payload,
  );
  await put(
    db.storedAutomationEvents,
    'events',
    (r) => StoredAutomationEvent()
      ..id = r.nativeId + 100
      ..entityId = r.entityId
      ..payload = r.payload,
  );
  await put(
    db.storedAutomationReceipts,
    'receipts',
    (r) => StoredAutomationReceipt()
      ..id = r.nativeId + 100
      ..entityId = r.entityId
      ..payload = r.payload,
  );
}

Future<void> main(List<String> args) async {
  final root = p.normalize(p.absolute(args[0])), mode = args[2];
  check(
    p.isWithin(p.normalize(p.absolute(Directory.systemTemp.path)), root) &&
        p.basename(root).startsWith('serverdeck-trusted-snapshot-'),
  );
  final sid = currentUserSid(),
      custody = KeyCustody(DpapiProtection(), currentUserSid());
  final data = g.foundation().toJson()
    ..['ownerSid'] = sid
    ..['schemaVersion'] = 3
    ..['storeRevision'] = '3';
  final workspace = data['workspaceId'] as String,
      keyId = data['receiptKeyId'] as String;
  final server = (data['profiles'] as Map).keys.single as String,
      credential = g.id(91);
  final profile = (data['profiles'] as Map)[server] as Map<String, Object?>;
  profile['revision'] = '3';
  profile['trustRevision'] = '3';
  profile['credentialRef'] = credential;
  final time = profile['updatedAt'] as String;
  final blob = await custody.wrapCredential(workspace, server, credential, {
    'action': 'replace',
    'kind': 'password',
    'password': 'synthetic-unpublished-password',
  });
  data['credentials'] = {
    credential: {
      'id': credential,
      'revision': '1',
      'profileId': server,
      'kind': 'password',
      'protectedBlob': mode == 'bad-credential'
          ? base64Encode([1, 2, 3])
          : blob,
      'createdAt': time,
      'updatedAt': time,
    },
  };
  final receipts = data['receipts'] as Map<String, Object?>;
  receipts[g.id(43)] = {
    ...(receipts[g.id(42)] as Map<String, Object?>),
    'requestId': g.id(43),
    'operation': 'servers.trust.confirm',
    'result': {
      'entityId': server,
      'entityRevision': '3',
      'storeRevision': '3',
      'deleted': false,
    },
  };
  if (mode == 'migrated') {
    receipts.remove(g.id(43));
    data['storeRevision'] = '2';
    profile['revision'] = '2';
    profile['trustRevision'] = '2';
  }
  if (mode == 'empty') {
    data
      ..clear()
      ..addAll(
        WorkspaceState.empty(
          workspaceId: workspace,
          receiptKeyId: keyId,
          ownerSid: sid,
        ).toJson(),
      )
      ..['schemaVersion'] = 3;
  }
  final state = WorkspaceState.fromTrustedJson(
    data,
    workspaceId: workspace,
    receiptKeyId: keyId,
    ownerSid: sid,
  );
  final key = await custody.createReceiptKey(workspace, keyId);
  final leaseDigest = (await Sha256().hash(utf8.encode(root))).bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  final lease = await MutexLease.acquire(
    'Global\\ServerDeckNext.v1.$leaseDigest',
    sid,
  );
  Isar? db;
  ReceiptKeyMaterial? wrongKey;
  try {
    var path = root;
    for (final name in ['ServerDeckNext', 'v1', 'workspaces', 'default']) {
      path = p.join(path, name);
      createProtectedDirectory(root, path, sid);
    }
    final files = McpCredentialFiles(
      localAppData: root,
      workspaceId: workspace,
      ownerSid: sid,
      custody: McpCredentialCustody(DpapiProtection()),
    );
    final graph = await g.graph();
    if (mode == 'empty') {
      for (final rows in graph.values) {
        rows.clear();
      }
    }
    // Second grant proves all wrappers/lookups precede first publication.
    if (graph['grants']!.isNotEmpty) {
      graph['grants']!.add({
        ...graph['grants']!.first,
        'id': g.id(80),
        'secretRef': g.id(81),
      });
      graph['receipts']!.add({
        ...graph['receipts']!.first,
        'requestId': g.id(90),
        'result': {'grantId': g.id(80), 'revision': 1},
      });
    }
    McpCredentialBinding binding(Map<String, Object?> grant) =>
        McpCredentialBinding(
          workspaceId: workspace,
          grantId: grant['id'] as String,
          secretRef: grant['secretRef'] as String,
          ownerSid: sid,
          issuedAt: grant['issuedAt'] as String,
        );
    for (final grant in graph['grants']!) {
      if (mode == 'missing-key' && grant['id'] == g.id(80)) continue;
      await files.stage(binding(grant));
    }
    if (mode == 'bad-key')
      await replaceProtectedFile(
        root,
        p.join(
          files.directory,
          'mcp-credentials',
          g.id(80),
          '${g.id(81)}.dpapi',
        ),
        sid,
        [1, 2, 3],
      );
    if (mode == 'bad-lookup') {
      await files.publish(binding(graph['grants']!.last), revoked: false);
      await replaceProtectedFile(
        root,
        p.join(files.directory, 'mcp-credentials', g.id(80), 'current.json'),
        sid,
        utf8.encode('{}'),
      );
    }
    if (mode == 'bad-graph') graph['jobs']!.single['grantId'] = g.id(99);
    await Isar.initializeIsarCore(
      libraries: {Abi.windowsX64: args[1]},
      download: false,
    );
    db = await Isar.open(
      trustedWorkspaceSchemas,
      directory: files.directory,
      name: mode == 'wrong-name' ? 'foreign' : 'workspace',
      maxSizeMiB: 64,
      relaxedDurability: false,
      inspector: false,
    );
    final records = WorkspaceRecords.fromTrustedState(state), native = db;
    if (mode == 'wrong-schema')
      records.workspace.payload = records.workspace.payload.replaceFirst(
        '"schemaVersion":3',
        '"schemaVersion":2',
      );
    if (mode == 'extra-metadata') {
      final metadata =
          jsonDecode(records.workspace.payload) as Map<String, Object?>;
      metadata['profiles'] = <String, Object?>{};
      records.workspace.payload = jsonEncode(metadata);
    }
    final trust = {
      'workspaceId': mode == 'foreign-trust' ? g.id(99) : workspace,
      'profileId': server,
      'revision': mode == 'bad-epoch' ? '2' : '3',
      'connectionRevision': '2',
      'status': 'trusted',
      'key': {
        'format': 'ssh-ed25519',
        'fingerprint':
            'SHA256:${base64Encode(List.filled(32, 0)).replaceAll('=', '')}',
      },
      'createdAt': time,
      'updatedAt': time,
    };
    await native.writeTxn(() async {
      await native.storedWorkspaces.put(records.workspace);
      await native.storedSettings.put(records.settings);
      for (final dynamic row in records.profiles) {
        row.id = 7;
      }
      for (final dynamic row in records.credentials) {
        row.id = 11;
      }
      for (var i = 0; i < records.receipts.length; i++) {
        records.receipts[i].id = 13 + i;
      }
      await native.storedProfiles.putAll(records.profiles);
      await native.storedCredentials.putAll(records.credentials);
      await native.storedReceipts.putAll(records.receipts);
      if (!{'missing-trust', 'migrated', 'empty'}.contains(mode))
        await native.storedHostTrusts.put(
          StoredHostTrust()
            ..id = mode == 'bad-trust-native-id' ? 0 : 23
            ..entityId = mode == 'orphan-trust' ? g.id(99) : server
            ..payload = jsonEncode(trust),
        );
      await seedAutomation(native, g.rows(graph));
    });
    if (mode == 'closed-lease') await lease.close();
    if (mode == 'closed-key') key.close();
    if (mode == 'wrong-key')
      wrongKey = await custody.createReceiptKey(workspace, g.id(99));
    Future<String> capture() async =>
        '${await raw.capture(native)}\n${jsonEncode([
          for (final row in await native.storedHostTrusts.where().findAll()) [row.id, row.entityId, row.payload],
        ])}';
    final before = await capture();
    const positive = {'good', 'empty', 'migrated'};
    try {
      final result = await readTrustedOperationalSnapshot(
        native,
        wrongKey ?? key,
        mode == 'wrong-owner'
            ? KeyCustody(DpapiProtection(), '$sid-1')
            : custody,
        localAppData: mode == 'wrong-directory'
            ? p.join(root, 'foreign')
            : root,
        lease: lease,
      );
      check(positive.contains(mode));
      check(result.rows.length == 16);
      if (mode != 'empty')
        check(
          result.rows.entries
              .where((e) => e.key != 'StoredHostTrust')
              .every((e) => e.value.isNotEmpty),
        );
      check(
        result.foundation.foundation.schemaVersion == 3 &&
            (mode == 'good'
                ? result.foundation.trust[server]!.revision == '3'
                : result.foundation.trust.isEmpty),
      );
      check(
        result.automation.jobs.length == (mode == 'empty' ? 0 : 1) &&
            result.automation.grants.length == (mode == 'empty' ? 0 : 2),
      );
      // Historical plan remains at trust2; current confirmation is trust3.
      if (mode != 'empty') {
        check(result.automation.plans.values.single.trustRevision == '2');
        check(result.rows['StoredCredential']!.single.nativeId == 11);
      }
      if (mode == 'good')
        check(result.rows['StoredHostTrust']!.single.nativeId == 23);
      check(
        result.rows.values
            .expand((r) => r)
            .every(
              (r) => !r.payload.contains('synthetic-unpublished-password'),
            ),
      );
      final digest = result.preservationDigest();
      final expected = {
        'workspace': {
          'nativeId': 1,
          'payload':
              (jsonDecode(records.workspace.payload) as Map<String, Object?>)
                ..remove('schemaVersion'),
        },
        'collections': {
          for (final entry in result.rows.entries)
            if (!{'StoredWorkspace', 'StoredHostTrust'}.contains(entry.key))
              entry.key: [
                for (final r in entry.value)
                  {
                    'nativeId': r.nativeId,
                    'entityId': r.entityId,
                    'payloadBase64': base64Encode(utf8.encode(r.payload)),
                  },
              ],
        },
      };
      final expectedDigest = (await Sha256().hash(
        StrictCodec().canonical(expected),
      )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      check(digest == expectedDigest);
      try {
        result.rows.clear();
        throw StateError('MUTABLE_ROWS');
      } on UnsupportedError {
        /* immutable */
      }
      try {
        await readOperationalSnapshot(
          native,
          key,
          custody,
          localAppData: root,
          lease: lease,
        );
        throw StateError('LEGACY_ACCEPTED_SCHEMA3');
      } on StateError catch (e) {
        check(e.message == 'INCOMPATIBLE');
      }
      check(await capture() == before);
      check(await native.close());
      db = null;
      db = await Isar.open(
        trustedWorkspaceSchemas,
        directory: files.directory,
        name: 'workspace',
        maxSizeMiB: 64,
        relaxedDurability: false,
        inspector: false,
      );
      final reopened = await readTrustedOperationalSnapshot(
        db,
        key,
        custody,
        localAppData: root,
        lease: lease,
      );
      check(reopened.preservationDigest() == digest);
      check(
        jsonEncode(
              reopened.rows.map(
                (k, v) => MapEntry(k, [
                  for (final r in v) [r.nativeId, r.entityId, r.payload],
                ]),
              ),
            ) ==
            jsonEncode(
              result.rows.map(
                (k, v) => MapEntry(k, [
                  for (final r in v) [r.nativeId, r.entityId, r.payload],
                ]),
              ),
            ),
      );
      stdout.writeln(
        'ACTUAL_SCHEMA3_FULL_GRAPH_DPAPI_ALL16_REOPEN_RAW_PRESERVATION_PROVED',
      );
    } on StateError catch (e) {
      if (positive.contains(mode)) rethrow;
      check(
        e.message ==
            (mode == 'wrong-schema' ? 'INCOMPATIBLE' : 'STORAGE_BLOCKED'),
      );
      check(await capture() == before);
      check(
        !File(
          p.join(files.directory, 'mcp-credentials', g.grantId, 'current.json'),
        ).existsSync(),
      );
      stdout.writeln('ACTUAL_SCHEMA3_REFUSAL_BEFORE_FIRST_PUBLICATION_PROVED');
    }
  } finally {
    if (db != null) check(await db.close());
    wrongKey?.close();
    key.close();
    await lease.close();
  }
}
