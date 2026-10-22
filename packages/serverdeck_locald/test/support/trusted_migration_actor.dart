import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/bootstrap/native_runtime.dart';
import 'package:serverdeck_locald/storage/automation_records.dart';
import 'package:serverdeck_locald/storage/host_trust_records.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/migration_probe.dart';
import 'package:serverdeck_locald/storage/models.dart';
import 'package:serverdeck_locald/storage/native_schema.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_locald/storage/trusted_snapshot.dart';
import 'package:serverdeck_locald/storage/workspace_migration.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mcp_credential_files.dart';
import 'package:serverdeck_windows/mcp_credentials.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/process.dart';
import 'package:serverdeck_windows/security.dart';

import '../../../serverdeck_windows/test/support/native_fixture_job.dart';
import '../automation/snapshot_test.dart' as g;
import 'trusted_snapshot_child.dart' show seedAutomation;
import 'trusted_schema_child.dart' as raw show retained;
import 'trusted_graph_write_fixture.dart';
import 'trusted_migration_capacity_fixture.dart';
import 'trusted_automation_write_fixture.dart';
import 'trusted_coordinator_scenarios.dart';
import 'mcp_runtime_actor.dart' show check, ownRoot;

final class FaultProtection implements UserProtection {
  FaultProtection(this.denyCredential);
  final bool denyCredential;
  final actual = DpapiProtection();
  @override
  Future<List<int>> protect(List<int> bytes, List<int> entropy) =>
      actual.protect(bytes, entropy);
  @override
  Future<List<int>> unprotect(List<int> bytes, List<int> entropy) {
    if (denyCredential && utf8.decode(entropy).endsWith('\ncredential'))
      throw StateError('OWNED_DPAPI_DENIED');
    return actual.unprotect(bytes, entropy);
  }
}

Future<String> digest(Map<String, Object?> rows) async {
  final workspace = (rows['StoredWorkspace'] as List).single as Map;
  final metadata = jsonDecode(
    utf8.decode(base64Decode(workspace['payloadBase64'] as String)),
  ) as Map<String, Object?>;
  metadata.remove('schemaVersion');
  final bytes = StrictCodec().canonical({
    'workspace': {'nativeId': workspace['nativeId'], 'payload': metadata},
    'collections': {
      for (final e in rows.entries)
        if (e.key != 'StoredWorkspace') e.key: e.value,
    },
  });
  return (await Sha256().hash(bytes)).bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

Future<void> main(List<String> args) async {
  try {
    final root = p.normalize(p.absolute(args[0])), mode = args[1];
    ownRoot(root);
    containCurrentFixtureTree();
    final sid = currentUserSid(),
        custody = KeyCustody(
          FaultProtection(mode == 'fault-dpapi'),
          currentUserSid(),
        );
    final lock = (await Sha256().hash(utf8.encode(root))).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final lease = await MutexLease.acquire(
      'Global\\ServerDeckNext.v1.$lock',
      sid,
    );
    final active = p.join(
          root,
          'ServerDeckNext',
          'v1',
          'workspaces',
          'default',
        ),
        stage = '$active.upgrading-2-3';
    Isar? db;
    ReceiptKeyMaterial? key;
    Future<void> run() => WorkspaceMigration.runTrusted(
      localAppData: root,
      appRoot: root,
      lease: lease,
      custody: custody,
    );
    try {
      if (mode.startsWith('role-') || mode == 'format2') {
        try {
          await run();
          throw StateError('EXPECTED_MODE_REFUSAL');
        } on StateError catch (e) {
          check(
            e.message == (mode == 'format2' ? 'INCOMPATIBLE' : 'UNAUTHORIZED'),
          );
        }
        check(
          !WorkspaceMigration.hasOpenReservation &&
              !Directory(active).existsSync(),
        );
        stdout.writeln('PASS:$mode');
        return;
      }
      await initializeTrustedNativeRuntime(root);
      if (mode.startsWith('prepare')) {
        final schema = mode == 'prepare1' ? 1 : 2;
        var dir = root;
        for (final name in ['ServerDeckNext', 'v1', 'workspaces', 'default']) {
          dir = p.join(dir, name);
          createProtectedDirectory(root, dir, sid);
        }
        final data = g.foundation().toJson()..['ownerSid'] = sid;
        final wid = data['workspaceId'] as String,
            kid = data['receiptKeyId'] as String;
        key = await custody.createReceiptKey(wid, kid);
        final profile =
            (data['profiles'] as Map).values.single as Map<String, Object?>;
        final server = profile['id'] as String,
            cred = g.id(91),
            time = profile['updatedAt'];
        profile['credentialRef'] = cred;
        data['credentials'] = {
          cred: {
            'id': cred,
            'revision': '1',
            'profileId': server,
            'kind': 'password',
            'protectedBlob': await custody.wrapCredential(wid, server, cred, {
              'action': 'replace',
              'kind': 'password',
              'password': 'private-disposable-upgrade',
            }),
            'createdAt': time,
            'updatedAt': time,
          },
        };
        final state = WorkspaceState.fromJson(
          data,
          workspaceId: wid,
          receiptKeyId: kid,
          ownerSid: sid,
        );
        final manifest = {
          ...await custody.createWorkspaceManifest(key),
          if (schema == 2) 'format': 2,
          'schema': schema,
        };
        await writeNewProtectedFile(
          root,
          p.join(active, 'workspace.manifest.json'),
          sid,
          utf8.encode(jsonEncode(manifest)),
        );
        await writeNewProtectedFile(
          root,
          p.join(active, 'receipt-key.dpapi'),
          sid,
          key.wrapper,
        );
        final graph = await g.graph();
        if (mode == 'prepare-busy') {
          graph['jobs']!.single
            ..['state'] = 'unknown'
            ..['nextSequence'] = 1
            ..['outcome'] = {
              'effects': 'uncertain',
              'checks': <Object?>[],
              'safeCode': 'UNKNOWN_OUTCOME',
            };
          graph['desired']!.clear();
          graph['events']!.clear();
        }
        if (schema == 2) {
          final files = McpCredentialFiles(
            localAppData: root,
            workspaceId: wid,
            ownerSid: sid,
            custody: McpCredentialCustody(DpapiProtection()),
          );
          for (final grant in graph['grants']!)
            await files.stage(
              McpCredentialBinding(
                workspaceId: wid,
                grantId: grant['id'] as String,
                secretRef: grant['secretRef'] as String,
                ownerSid: sid,
                issuedAt: grant['issuedAt'] as String,
              ),
            );
        }
        for (final name in ['workspace.isar', 'workspace.isar-lck'])
          await createProtectedEmptyFile(root, p.join(active, name), sid);
        db = await Isar.open(
          schema == 1 ? workspaceSchemas : automationWorkspaceSchemas,
          directory: active,
          name: 'workspace',
          maxSizeMiB: 64,
          relaxedDurability: false,
          inspector: false,
        );
        final records = schema == 1
                ? WorkspaceRecords.fromState(state)
                : WorkspaceRecords.fromOperationalState(state),
            seed = db;
        records.settings.payload = ' \n${records.settings.payload} ';
        records.profiles.single.payload = records.profiles.single.payload
            .replaceFirst('"Synthetic"', r'"\u0053ynthetic"');
        await seed.writeTxn(() async {
          await seed.storedWorkspaces.put(records.workspace);
          await seed.storedSettings.put(records.settings);
          for (final row in records.profiles) {
            row.id = 7;
          }
          for (final row in records.credentials) {
            row.id = 11;
          }
          for (var i = 0; i < records.receipts.length; i++) {
            records.receipts[i].id = 15 + i;
          }
          await seed.storedProfiles.putAll(records.profiles);
          await seed.storedCredentials.putAll(records.credentials);
          await seed.storedReceipts.putAll(records.receipts);
          if (schema == 2) await seedAutomation(seed, g.rows(graph));
        });
        final rows = <String, Object?>{
          for (final s in automationWorkspaceSchemas) s.name: <Object?>[],
        };
        final cols = schema == 1
            ? <IsarCollection<dynamic>>[
                seed.storedWorkspaces,
                seed.storedSettings,
                seed.storedProfiles,
                seed.storedCredentials,
                seed.storedReceipts,
              ]
            : raw.retained(seed);
        for (final col in cols) {
          final values = await col.where().findAll();
          values.sort(
            (dynamic a, dynamic b) => (a.id as int).compareTo(b.id as int),
          );
          rows[col.name] = [
            for (final dynamic row in values)
              {
                'nativeId': row.id,
                'entityId': col.schema.indexes.isEmpty ? null : row.entityId,
                'payloadBase64': base64Encode(
                  utf8.encode(row.payload as String),
                ),
              },
          ];
        }
        check(await seed.close());
        db = null;
        File(p.join(root, 'fixture-expected.json')).writeAsStringSync(
          jsonEncode({
            'rowsDigest': await digest(rows),
            'keyHash': fileSha256(p.join(active, 'receipt-key.dpapi')),
            'workspaceId': wid,
            'receiptKeyId': kid,
          }),
        );
      } else {
        final capacity = mode == 'capacity'
            ? TrustedMigrationCapacityFixture(active, lease)
            : null;
        capacity?.install();
        var reservationSources = 0;
        if (mode == 'reservation')
          MigrationProbe.install((boundary) async {
            check(WorkspaceMigration.hasOpenReservation && lease.isHeld);
            if (boundary == MigrationBoundary.sourceValidated)
              reservationSources++;
            try {
              await run();
              throw StateError('SECOND_WRITER_ADMITTED');
            } on StateError catch (e) {
              check(e.message == 'STORAGE_BLOCKED');
            }
          });
        if (mode.startsWith('fault-')) {
          var published = false, closes = 0;
          MigrationProbe.install(
            (boundary) async {
              if (boundary == MigrationBoundary.databasePublished)
                published = true;
            },
            minimumFreeBytes: (required) =>
                mode == 'fault-space-initial' ||
                    mode == 'fault-space-published' && published
                ? 1 << 60
                : required,
            closeNative: (actual) async {
              closes++;
              if (mode == 'fault-close-false' ||
                  mode == 'fault-close-throw' ||
                  mode == 'fault-close-target' && closes == 3) {
                check(Isar.getInstance('workspace')!.isOpen && lease.isHeld);
                if (mode == 'fault-close-throw')
                  throw StateError('OWNED_CLOSE_WITHHELD');
                return false;
              }
              return actual();
            },
          );
        }
        if (mode == 'kill') {
          var count = 0;
          final parts = args[2].split(':');
          final occurrence = parts.length == 2 ? int.parse(parts[1]) : 1;
          MigrationProbe.install((boundary) async {
            if (boundary == MigrationBoundary.sourceValidated)
              File(p.join(root, 'fixture-baseline.json')).writeAsStringSync(
                jsonEncode({
                  for (final name in [
                    'workspace.isar',
                    'workspace.manifest.json',
                    'receipt-key.dpapi',
                  ])
                    name: fileSha256(p.join(active, name)),
                }),
              );
            if (boundary.name == parts[0] && ++count == occurrence) {
              stdout.writeln('BOUNDARY:${args[2]}');
              await stdout.flush();
              await Completer<void>().future;
            }
          });
        }
        if (mode == 'capacity') {
          try {
            await run();
            throw StateError('EXPECTED_MIGRATION_CAPACITY_REFUSAL');
          } on StateError catch (error) {
            check(error.message == 'STORAGE_BLOCKED');
          }
          capacity!.verify();
        } else if (mode.startsWith('fault-') || mode == 'blocked') {
          Future<void> reject() async {
            try {
              await run();
              throw StateError('EXPECTED_BLOCKED');
            } on StateError catch (e) {
              check(e.message == 'STORAGE_BLOCKED');
            }
          }

          await reject();
          if (mode.startsWith('fault-close-')) {
            check(
              WorkspaceMigration.hasOpenReservation &&
                  Isar.getInstance('workspace')!.isOpen &&
                  lease.isHeld,
            );
            await reject();
            stdout.writeln('PASS:$mode');
            await stdout.flush();
            exit(0);
          }
          check(
            !WorkspaceMigration.hasOpenReservation &&
                Isar.getInstance('workspace') == null &&
                lease.isHeld,
          );
          await reject();
          check(
            !WorkspaceMigration.hasOpenReservation &&
                Isar.getInstance('workspace') == null,
          );
        } else if (mode == 'busy') {
          try {
            await run();
            throw StateError('EXPECTED_HOST_BUSY');
          } on StateError catch (e) {
            check(e.message == 'HOST_BUSY');
          }
          check(
            !WorkspaceMigration.hasOpenReservation &&
                Isar.getInstance('workspace') == null &&
                lease.isHeld,
          );
          check(!Directory(stage).existsSync());
        } else {
          final lookup = p.join(
            active,
            'mcp-credentials',
            g.grantId,
            'current.json',
          );
          final before = File(lookup).existsSync()
              ? File(lookup).readAsBytesSync()
              : null;
          await run();
          if (mode == 'reservation') check(reservationSources == 2);
          check(
            before == null
                ? !File(lookup).existsSync()
                : base64Encode(File(lookup).readAsBytesSync()) ==
                      base64Encode(before),
          );
          check(
            !Directory(stage).existsSync() &&
                !Directory('$active.upgrading-1-2').existsSync(),
          );
          if (mode == 'verify') {
            final expected = jsonDecode(
              File(p.join(root, 'fixture-expected.json')).readAsStringSync(),
            ) as Map;
            check(
              fileSha256(p.join(active, 'receipt-key.dpapi')) ==
                  expected['keyHash'],
            );
            final manifest = StrictCodec().decode(
              File(p.join(active, 'workspace.manifest.json')).readAsBytesSync(),
            );
            check(manifest['format'] == 3 && manifest['schema'] == 3);
            check(
              inspectTrustedNativeWorkspaceSchema(
                    File(p.join(active, 'workspace.isar')).readAsBytesSync(),
                  ) ==
                  3,
            );
            key = await custody.openReceiptKey(
              File(p.join(active, 'receipt-key.dpapi')).readAsBytesSync(),
              expected['workspaceId'] as String,
              expected['receiptKeyId'] as String,
            );
            db = await Isar.open(
              trustedWorkspaceSchemas,
              directory: active,
              name: 'workspace',
              maxSizeMiB: 64,
              relaxedDurability: false,
              inspector: false,
            );
            final result = await readTrustedOperationalSnapshot(
              db,
              key,
              custody,
              localAppData: root,
              lease: lease,
            );
            check(
              result.preservationDigest() == expected['rowsDigest'] &&
                  result.foundation.trust.isEmpty,
            );
          }
          if (mode == 'writer-graph' ||
              mode.startsWith('writer-busy-') ||
              mode.startsWith('writer-automation') ||
              mode.startsWith('writer-coordinator-')) {
            final expected = jsonDecode(
              File(p.join(root, 'fixture-expected.json')).readAsStringSync(),
            ) as Map;
            key = await custody.openReceiptKey(
              File(p.join(active, 'receipt-key.dpapi')).readAsBytesSync(),
              expected['workspaceId'] as String,
              expected['receiptKeyId'] as String,
            );
            if (mode.startsWith('writer-coordinator-')) {
              await exerciseTrustedCoordinator(
                root,
                custody,
                key,
                lease,
                mode.substring('writer-'.length),
              );
            } else if (mode.startsWith('writer-automation')) {
              await exerciseTrustedAutomationWrite(
                root,
                custody,
                key,
                lease,
                mode,
              );
            } else {
              await exerciseTrustedGraphWrite(
                root,
                custody,
                key,
                lease,
                busyState: mode.startsWith('writer-busy-')
                    ? mode.substring('writer-busy-'.length)
                    : null,
              );
            }
          }
        }
      }
    } finally {
      if (db != null) check(await db.close());
      key?.close();
      await lease.close();
    }
    stdout.writeln('PASS:$mode');
  } catch (error, stack) {
    stderr.writeln(error);
    stderr.writeln(stack);
    exitCode = 1;
  }
}
