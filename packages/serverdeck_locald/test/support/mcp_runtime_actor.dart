import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/bootstrap/native_runtime.dart';
import 'package:serverdeck_locald/credentials/provider.dart';
import 'package:serverdeck_locald/profiles/service.dart';
import 'package:serverdeck_locald/profiles/validation.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_locald/storage/automation_records.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/models.dart';
import 'package:serverdeck_locald/storage/migration_rows.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/process.dart';
import 'package:serverdeck_windows/security.dart';

import '../../../serverdeck_windows/test/support/native_fixture_job.dart';

void check(bool value) {
  if (!value) throw StateError('RUNTIME_FIXTURE_FAILED');
}

void ownRoot(String root) => check(
  p.isWithin(p.normalize(p.absolute(Directory.systemTemp.path)), root) &&
      p.basename(root).startsWith('serverdeck-mcp-bundle-'),
);
Future<void> refusal(Future<Object?> Function() call, String code) async {
  try {
    await call();
  } on StateError catch (error) {
    check(error.message == code);
    return;
  }
  throw StateError('EXPECTED_$code');
}

void manifest(String root, void Function(Map<String, dynamic>) change) {
  final path = p.join(root, 'foundation.manifest.json');
  final document =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  change(document);
  File(path).writeAsStringSync(jsonEncode(document));
}

void legacy(String root) => manifest(root, (d) {
  d['format'] = 1;
  for (final key in ['product', 'apiMajor', 'apiMinor', 'workspaceSchema'])
    d.remove(key);
  (d['sha256'] as Map).remove('mcp.exe');
});

Future<void> existingStore(String root, {bool withTarget = false}) async {
  final sid = currentUserSid();
  final custody = KeyCustody(DpapiProtection(), sid);
  const workspaceId = '12345678-1234-4234-8234-123456789abc';
  const keyId = '12345678-1234-4234-8234-123456789abd';
  final key = await custody.createReceiptKey(workspaceId, keyId);
  final namespace = (await Sha256().hash(
    utf8.encode('mcp-runtime-fixture-$root'),
  )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final lease = await MutexLease.acquire(
    'Global\\ServerDeckNext.v1.$namespace',
    sid,
  );
  StateStore? store;
  Isar? seed;
  try {
    check(lease.isHeld);
    final local = p.join(root, 'private');
    createProtectedDirectory(root, local, sid);
    var directory = local;
    for (final part in ['ServerDeckNext', 'v1', 'workspaces', 'default']) {
      directory = p.join(directory, part);
      createProtectedDirectory(local, directory, sid);
    }
    var state = WorkspaceState.empty(
      workspaceId: workspaceId,
      receiptKeyId: keyId,
      ownerSid: sid,
    );
    if (withTarget) {
      const targetId = '32345678-1234-4234-8234-123456789abc';
      const requestId = '42345678-1234-4234-8234-123456789abc';
      const at = '2020-01-01T00:00:00.000Z';
      final input = validateMutationInput(ApiMethod.profilesCreate, {
        'profileId': targetId,
        'name': 'Synthetic target',
        'address': '127.0.0.1',
        'port': 22,
        'sshUser': 'fixture',
        'tags': <String>[],
      });
      final prepared = await ProfileService(CredentialProvider(custody))
          .prepare(state, ApiMethod.profilesCreate, input, at);
      (prepared.value['receipts'] as Map)[requestId] = {
        'requestId': requestId,
        'inputDigest': custody.receiptDigestSync(key, {
          'operation': 'profiles.create',
          'params': input,
        }),
        'operation': 'profiles.create',
        'profileId': targetId,
        'result': prepared.result.toJson(),
        'committedAt': at,
      };
      state = WorkspaceState.fromJson(
        prepared.value,
        workspaceId: workspaceId,
        receiptKeyId: keyId,
        ownerSid: sid,
      );
    }
    final records = WorkspaceRecords.fromState(state);
    records.workspace.payload = jsonEncode({
      ...(jsonDecode(records.workspace.payload) as Map<String, dynamic>),
      'schemaVersion': 2,
    });
    for (final name in ['workspace.isar', 'workspace.isar-lck']) {
      await createProtectedEmptyFile(local, p.join(directory, name), sid);
    }
    seed = await Isar.open(
      automationWorkspaceSchemas,
      directory: directory,
      name: 'workspace',
      maxSizeMiB: 64,
      relaxedDurability: false,
      inspector: false,
    );
    final db = seed;
    await db.writeTxn(() async {
      await db.storedWorkspaces.put(records.workspace);
      await db.storedSettings.put(records.settings);
      final ids = await db.storedProfiles.putAll(records.profiles);
      for (var i = 0; i < ids.length; i++) records.profiles[i].id = ids[i];
      final receipts = await db.storedReceipts.putAll(records.receipts);
      for (var i = 0; i < receipts.length; i++)
        records.receipts[i].id = receipts[i];
    });
    check(await seed.close());
    seed = null;
    await writeNewProtectedFile(
      local,
      p.join(directory, 'receipt-key.dpapi'),
      sid,
      key.wrapper,
    );
    await writeNewProtectedFile(
      local,
      p.join(directory, 'workspace.manifest.json'),
      sid,
      utf8.encode(
        jsonEncode({
          ...await custody.createWorkspaceManifest(key),
          'format': 2,
          'schema': 2,
        }),
      ),
    );
    final before = MigrationRows.capture(
      schema: 2,
      workspace: MigrationRow(records.workspace.id, records.workspace.payload),
      settings: MigrationRow(records.settings.id, records.settings.payload),
      profiles: [
        for (final row in records.profiles)
          MigrationRow(row.id, row.payload, entityId: row.entityId),
      ],
      credentials: [],
      receipts: [
        for (final row in records.receipts)
          MigrationRow(row.id, row.payload, entityId: row.entityId),
      ],
    ).digest();
    for (var n = 0; n < 2; n++) {
      store = await StateStore.openMcpOperational(
        localAppData: local,
        appRoot: root,
        lease: lease,
        custody: custody,
        receiptKey: key,
      );
      check(
        store.isAutomationReady && store.operational.automation.grants.isEmpty,
      );
      check(
        store.state.workspaceId == workspaceId &&
            store.state.storeRevision == state.storeRevision &&
            store.state.profiles.length == (withTarget ? 1 : 0),
      );
      check(store.operational.foundation.rows.digest() == before);
      await store.close();
      store = null;
      check(!StateStore.hasOpenReservation);
    }
  } finally {
    await store?.close();
    await seed?.close();
    key.close();
    await lease.close();
  }
}

Future<void> refusedStore(
  String root,
  String code, {
  bool legacyEntry = false,
}) async {
  final sid = currentUserSid();
  final custody = KeyCustody(DpapiProtection(), sid);
  final key = await custody.createReceiptKey(
    '12345678-1234-4234-8234-123456789abc',
    '12345678-1234-4234-8234-123456789abd',
  );
  final namespace = (await Sha256().hash(
    utf8.encode('mcp-refusal-fixture-$root'),
  )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final lease = await MutexLease.acquire(
    'Global\\ServerDeckNext.v1.$namespace',
    sid,
  );
  try {
    check(lease.isHeld);
    await refusal(
      () => legacyEntry
          ? StateStore.openOperational(
              localAppData: p.join(root, 'private'),
              appRoot: root,
              lease: lease,
              custody: custody,
              receiptKey: key,
            )
          : StateStore.openMcpOperational(
              localAppData: p.join(root, 'private'),
              appRoot: root,
              lease: lease,
              custody: custody,
              receiptKey: key,
            ),
      code,
    );
    check(
      !StateStore.hasOpenReservation &&
          !Directory(p.join(root, 'private')).existsSync(),
    );
  } finally {
    key.close();
    await lease.close();
  }
}

Future<void> main(List<String> args) async {
  try {
    final root = p.normalize(p.absolute(args[0])), mode = args[1];
    ownRoot(root);
    containCurrentFixtureTree();
    switch (mode) {
      case 'good':
        final bundles = await Future.wait([
          initializeMcpNativeRuntime(root),
          initializeMcpNativeRuntime(root),
        ]);
        check(bundles.every((bundle) => bundle.manifest.workspaceSchema == 2));
        await initializeMcpNativeRuntime(root);
        await existingStore(root);
      case 'role':
        await refusal(() => initializeMcpNativeRuntime(root), 'UNAUTHORIZED');
        await refusedStore(root, 'UNAUTHORIZED');
      case 'legacy-refusal':
        await refusal(() => initializeNativeRuntime(root), 'INCOMPATIBLE');
        await refusedStore(root, 'INCOMPATIBLE', legacyEntry: true);
      case 'format-refusal':
        legacy(root);
        await refusal(() => initializeMcpNativeRuntime(root), 'INCOMPATIBLE');
        await initializeNativeRuntime(root);
        await refusedStore(root, 'INCOMPATIBLE');
      case 'build-conflict':
        await initializeMcpNativeRuntime(root);
        manifest(root, (d) {
          d['configuration'] = 'Release';
          d['buildId'] = (d['buildId'] as String).replaceFirst(
            'Debug',
            'Release',
          );
        });
        await refusal(() => initializeMcpNativeRuntime(root), 'INCOMPATIBLE');
      case 'mode-conflict':
        await initializeMcpNativeRuntime(root);
        legacy(root);
        await refusal(() => initializeNativeRuntime(root), 'INCOMPATIBLE');
      case 'test-selection':
        manifest(root, (d) => d['testOnly'] = true);
        await refusal(() => initializeMcpNativeRuntime(root), 'INCOMPATIBLE');
        check(
          (await initializeMcpNativeRuntime(
            root,
            testOnly: true,
          )).manifest.testOnly,
        );
        manifest(root, (d) => d['testOnly'] = false);
        await refusal(() => initializeMcpNativeRuntime(root), 'INCOMPATIBLE');
      case 'load-failure':
        final dll = File(p.join(root, 'libisar.dll'));
        final original = dll.readAsBytesSync();
        dll.writeAsBytesSync([1, 2, 3]);
        manifest(
          root,
          (d) => (d['sha256'] as Map)['libisar.dll'] = fileSha256(dll.path),
        );
        await refusal(
          () => initializeMcpNativeRuntime(root),
          'PREREQUISITE_UNAVAILABLE',
        );
        await refusedStore(root, 'PREREQUISITE_UNAVAILABLE');
        await refusal(
          () => initializeMcpNativeRuntime(root),
          'PREREQUISITE_UNAVAILABLE',
        );
        dll.writeAsBytesSync(original);
        manifest(
          root,
          (d) => (d['sha256'] as Map)['libisar.dll'] = fileSha256(dll.path),
        );
        await refusal(() => initializeMcpNativeRuntime(root), 'INCOMPATIBLE');
      default:
        throw StateError('UNKNOWN_MODE');
    }
    check(!Directory(p.join(root, 'private')).existsSync() || mode == 'good');
    stdout.writeln('PASS:$mode');
  } catch (error, trace) {
    stderr.writeln(error);
    stderr.writeln(trace);
    exitCode = 1;
  }
}
