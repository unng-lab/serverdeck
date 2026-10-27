import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/storage/automation_records.dart';
import 'package:serverdeck_locald/storage/host_trust_records.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/models.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_locald/storage/trusted_snapshot.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mcp_credentials.dart';
import 'package:serverdeck_windows/mcp_credential_files.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';

import '../automation/snapshot_test.dart' as g;
import 'trusted_snapshot_child.dart' show seedAutomation;
import 'trusted_schema_child.dart' as raw show capture;

void check(bool value) {
  if (!value) throw StateError('UPGRADE_CAPTURE_FAILED');
}

Future<void> refusal(
  Future<Object?> Function() body, [
  String code = 'STORAGE_BLOCKED',
]) async {
  try {
    await body();
  } on StateError catch (e) {
    check(e.message == code);
    return;
  }
  throw StateError('EXPECTED_CAPTURE_REFUSAL');
}

Future<void> main(List<String> args) async {
  final root = p.normalize(p.absolute(args[0])), mode = args[2];
  check(
    p.isWithin(p.normalize(p.absolute(Directory.systemTemp.path)), root) &&
        p.basename(root).startsWith('serverdeck-upgrade-capture-'),
  );
  final sid = currentUserSid(),
      custody = KeyCustody(DpapiProtection(), currentUserSid());
  final data = g.foundation().toJson()..['ownerSid'] = sid;
  final workspace = data['workspaceId'] as String,
      keyId = data['receiptKeyId'] as String,
      profile = (data['profiles'] as Map).values.single as Map<String, Object?>,
      server = profile['id'] as String,
      credential = g.id(91),
      time = profile['updatedAt'] as String;
  profile['credentialRef'] = credential;
  final blob = await custody.wrapCredential(workspace, server, credential, {
    'action': 'replace',
    'kind': 'password',
    'password': 'unpublished-upgrade-fixture',
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
  final state = WorkspaceState.fromJson(
    data,
    workspaceId: workspace,
    receiptKeyId: keyId,
    ownerSid: sid,
  );
  final key = await custody.createReceiptKey(workspace, keyId);
  final digest = (await Sha256().hash(utf8.encode(root))).bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  final lease = await MutexLease.acquire(
    'Global\\ServerDeckNext.v1.$digest',
    sid,
  );
  Isar? db;
  try {
    var active = root;
    for (final segment in ['ServerDeckNext', 'v1', 'workspaces', 'default']) {
      active = p.join(active, segment);
      createProtectedDirectory(root, active, sid);
    }
    final stage = '$active.upgrading-2-3';
    final files = McpCredentialFiles(
      localAppData: root,
      workspaceId: workspace,
      ownerSid: sid,
      custody: McpCredentialCustody(DpapiProtection()),
    );
    final graph = await g.graph();
    final jobState = mode == 'occupied'
        ? 'unknown'
        : mode.startsWith('job-')
        ? mode.substring(4)
        : null;
    final busy =
        jobState != null && !{'failed', 'cancelled'}.contains(jobState);
    if (jobState != null) {
      graph['jobs']!.single['state'] = jobState;
      graph['jobs']!.single['cancelRequested'] = jobState == 'cancel-requested';
      graph['jobs']!.single['outcome'] =
          {'failed', 'cancelled', 'unknown'}.contains(jobState)
          ? {
              'effects': jobState == 'unknown' ? 'uncertain' : 'none',
              'checks': <Object?>[],
              'safeCode': jobState == 'unknown'
                  ? 'UNKNOWN_OUTCOME'
                  : jobState == 'cancelled'
                  ? 'CANCELLED'
                  : 'DISCONNECTED',
            }
          : null;
      graph['desired']!.clear();
      graph['events']!.clear();
      graph['jobs']!.single['nextSequence'] = 1;
    }
    final grant = graph['grants']!.single;
    final binding = McpCredentialBinding(
      workspaceId: workspace,
      grantId: grant['id'] as String,
      secretRef: grant['secretRef'] as String,
      ownerSid: sid,
      issuedAt: grant['issuedAt'] as String,
    );
    await files.stage(binding);
    if (mode == 'bad-client')
      await replaceProtectedFile(
        root,
        p.join(
          active,
          'mcp-credentials',
          binding.grantId,
          '${binding.secretRef}.dpapi',
        ),
        sid,
        [1, 2, 3],
      );
    final lookup = p.join(
      active,
      'mcp-credentials',
      binding.grantId,
      'current.json',
    );
    if (mode == 'lookup-existing') await files.publish(binding, revoked: false);
    if (mode == 'bad-lookup') {
      await files.publish(binding, revoked: false);
      await replaceProtectedFile(root, lookup, sid, utf8.encode('{}'));
    }
    final lookupBefore = File(lookup).existsSync()
        ? File(lookup).readAsBytesSync()
        : null;
    void noPublication() => check(
      lookupBefore == null
          ? !File(lookup).existsSync()
          : base64Encode(File(lookup).readAsBytesSync()) ==
                base64Encode(lookupBefore),
    );
    await Isar.initializeIsarCore(
      libraries: {Abi.windowsX64: args[1]},
      download: false,
    );
    for (final name in ['workspace.isar', 'workspace.isar-lck']) {
      await createProtectedEmptyFile(root, p.join(active, name), sid);
    }
    db = await Isar.open(
      automationWorkspaceSchemas,
      directory: active,
      name: 'workspace',
      maxSizeMiB: 64,
      relaxedDurability: false,
      inspector: false,
    );
    final records = WorkspaceRecords.fromOperationalState(state), source = db;
    records.settings.payload = ' \n${records.settings.payload} ';
    records.profiles.single.payload = records.profiles.single.payload
        .replaceFirst('"Synthetic"', r'"\u0053ynthetic"');
    await source.writeTxn(() async {
      await source.storedWorkspaces.put(records.workspace);
      await source.storedSettings.put(records.settings);
      for (final row in records.profiles) {
        row.id = 7;
      }
      for (final row in records.credentials) {
        row.id = 11;
      }
      for (var i = 0; i < records.receipts.length; i++) {
        records.receipts[i].id = 15 + i;
      }
      await source.storedProfiles.putAll(records.profiles);
      await source.storedCredentials.putAll(records.credentials);
      await source.storedReceipts.putAll(records.receipts);
      await seedAutomation(source, g.rows(graph));
    });
    final before = await raw.capture(source);
    if (mode == 'empty-stage') createProtectedDirectory(root, stage, sid);
    if (mode == 'stage') {
      createProtectedDirectory(root, stage, sid);
      await writeNewProtectedFile(
        root,
        p.join(stage, 'migration.json'),
        sid,
        utf8.encode('{}'),
      );
    }
    if (busy ||
        {
          'bad-credential',
          'bad-client',
          'bad-lookup',
          'occupied',
          'stage',
          'wrong-path',
        }.contains(mode)) {
      await refusal(
        () => readSchema2UpgradePreflight(
          source,
          key,
          custody,
          localAppData: mode == 'wrong-path' ? p.join(root, 'foreign') : root,
          lease: lease,
        ),
        busy ? 'HOST_BUSY' : 'STORAGE_BLOCKED',
      );
      check(await raw.capture(source) == before);
      noPublication();
      if (busy) {
        check(!Directory(stage).existsSync());
        check(await source.close());
        db = null;
        final frozen = File(p.join(active, 'workspace.isar')).readAsBytesSync();
        createProtectedDirectory(root, stage, sid);
        await copyProtectedFile(
          root,
          p.join(active, 'workspace.isar'),
          p.join(stage, 'workspace.isar'),
          sid,
        );
        await createProtectedEmptyFile(
          root,
          p.join(stage, 'workspace.isar-lck'),
          sid,
        );
        db = await Isar.open(
          automationWorkspaceSchemas,
          directory: stage,
          name: 'workspace',
          maxSizeMiB: 64,
          relaxedDurability: false,
          inspector: false,
        );
        await refusal(
          () => readSchema2UpgradeSource(
            db!,
            key,
            custody,
            localAppData: root,
            lease: lease,
          ),
        );
        check(await raw.capture(db) == before);
        check(await db.close());
        db = null;
        db = await Isar.open(
          trustedWorkspaceSchemas,
          directory: stage,
          name: 'workspace',
          maxSizeMiB: 64,
          relaxedDurability: false,
          inspector: false,
        );
        final target = db;
        await target.writeTxn(() async {
          final row = (await target.storedWorkspaces.get(1))!;
          row.payload = row.payload.replaceFirst(
            '"schemaVersion":2',
            '"schemaVersion":3',
          );
          await target.storedWorkspaces.put(row);
        });
        await refusal(
          () => readSchema3UpgradeTarget(
            target,
            key,
            custody,
            localAppData: root,
            lease: lease,
          ),
        );
        check(
          base64Encode(
                File(p.join(active, 'workspace.isar')).readAsBytesSync(),
              ) ==
              base64Encode(frozen),
        );
        noPublication();
      }
    } else {
      final preflight = await readSchema2UpgradePreflight(
        source,
        key,
        custody,
        localAppData: root,
        lease: lease,
      );
      check(
        preflight.rows.length == 15 &&
            (jobState != null ||
                preflight.rows.values.every((r) => r.isNotEmpty)),
      );
      try {
        preflight.rows.clear();
        throw StateError('MUTABLE_CAPTURE');
      } on UnsupportedError {
        /* exact immutable capture */
      }
      await refusal(
        () => readSchema2UpgradeSource(
          source,
          key,
          custody,
          localAppData: root,
          lease: lease,
        ),
      );
      noPublication();
      final preserved = preflight.preservationDigest();
      check(await source.close());
      db = null;
      createProtectedDirectory(root, stage, sid);
      await copyProtectedFile(
        root,
        p.join(active, 'workspace.isar'),
        p.join(stage, 'workspace.isar'),
        sid,
      );
      await createProtectedEmptyFile(
        root,
        p.join(stage, 'workspace.isar-lck'),
        sid,
      );
      db = await Isar.open(
        automationWorkspaceSchemas,
        directory: stage,
        name: 'workspace',
        maxSizeMiB: 64,
        relaxedDurability: false,
        inspector: false,
      );
      await refusal(
        () => readSchema2UpgradePreflight(
          db!,
          key,
          custody,
          localAppData: root,
          lease: lease,
        ),
      );
      final copy = await readSchema2UpgradeSource(
        db,
        key,
        custody,
        localAppData: root,
        lease: lease,
      );
      check(copy.preservationDigest() == preserved);
      noPublication();
      check(await raw.capture(db) == before);
      check(await db.close());
      db = null;
      db = await Isar.open(
        trustedWorkspaceSchemas,
        directory: stage,
        name: 'workspace',
        maxSizeMiB: 64,
        relaxedDurability: false,
        inspector: false,
      );
      final target = db;
      await target.writeTxn(() async {
        final row = (await target.storedWorkspaces.get(1))!;
        row.payload = row.payload.replaceFirst(
          '"schemaVersion":2',
          '"schemaVersion":3',
        );
        await target.storedWorkspaces.put(row);
        if (mode == 'nonempty-trust')
          await target.storedHostTrusts.put(
            StoredHostTrust()
              ..entityId = server
              ..payload = '{}',
          );
      });
      if (mode == 'nonempty-trust') {
        await refusal(
          () => readSchema3UpgradeTarget(
            target,
            key,
            custody,
            localAppData: root,
            lease: lease,
          ),
        );
      } else {
        final upgraded = await readSchema3UpgradeTarget(
          target,
          key,
          custody,
          localAppData: root,
          lease: lease,
        );
        check(
          upgraded.rows.length == 16 &&
              upgraded.rows['StoredHostTrust']!.isEmpty,
        );
        check(upgraded.preservationDigest() == preserved);
        noPublication();
        await refusal(
          () => readSchema2UpgradeSource(
            target,
            key,
            custody,
            localAppData: root,
            lease: lease,
          ),
          'INCOMPATIBLE',
        );
      }
    }
    noPublication();
    stdout.writeln('PASS:$mode');
  } finally {
    if (db != null) check(await db.close());
    key.close();
    await lease.close();
  }
}
