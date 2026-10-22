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
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_locald/storage/trusted_snapshot.dart';
import 'package:serverdeck_locald/storage/workspace.dart';
import 'package:serverdeck_locald/storage/workspace_migration.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mcp_credentials.dart';
import 'package:serverdeck_windows/mcp_credential_files.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';

import '../../../serverdeck_windows/test/support/native_fixture_job.dart';
import '../automation/snapshot_test.dart' as g;
import 'trusted_schema_child.dart' as raw show capture;
import 'trusted_snapshot_child.dart' show seedAutomation;
import 'mcp_runtime_actor.dart' show check, ownRoot;
import 'mcp_runtime_actor.dart' as runtime show refusal;

Future<void> refusal(
  Future<Object?> Function() action, [
  String code = 'STORAGE_BLOCKED',
]) => runtime.refusal(action, code);

Future<void> main(List<String> args) async {
  try {
    final root = p.normalize(p.absolute(args[0])), mode = args[1];
    ownRoot(root);
    containCurrentFixtureTree();
    final sid = currentUserSid(),
        custody = KeyCustody(DpapiProtection(), currentUserSid());
    final data = g.foundation().toJson()..['ownerSid'] = sid;
    final workspace = data['workspaceId'] as String,
        keyId = data['receiptKeyId'] as String;
    final key = await custody.createReceiptKey(workspace, keyId);
    final digest = (await Sha256().hash(utf8.encode(root))).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final lease = await MutexLease.acquire(
      'Global\\ServerDeckNext.v1.$digest',
      sid,
    );
    Isar? db;
    Future<UpgradeSnapshot> preflight() =>
        WorkspaceMigration.preflightTrustedSource(
          localAppData: root,
          appRoot: root,
          lease: lease,
          custody: custody,
          receiptKey: key,
        );
    try {
      if (mode.startsWith('role-')) {
        await refusal(preflight, 'UNAUTHORIZED');
        check(
          !Workspace.hasOpenReservation &&
              !Directory(p.join(root, 'ServerDeckNext')).existsSync(),
        );
      } else {
        await initializeTrustedNativeRuntime(root);
        var active = root;
        for (final segment in [
          'ServerDeckNext',
          'v1',
          'workspaces',
          'default',
        ]) {
          active = p.join(active, segment);
          createProtectedDirectory(root, active, sid);
        }
        final manifest = {
          ...await custody.createWorkspaceManifest(key),
          'format': 2,
          'schema': 2,
        };
        if (mode == 'manifest3') {
          manifest['format'] = 3;
          manifest['schema'] = 3;
        }
        if (mode == 'manifest-foreign') manifest['workspaceId'] = keyId;
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
          mode == 'wrapper' ? [1, 2, 3] : key.wrapper,
        );
        final profile =
            (data['profiles'] as Map).values.single as Map<String, Object?>;
        final credential = g.id(91),
            server = profile['id'] as String,
            time = profile['updatedAt'] as String;
        profile['credentialRef'] = credential;
        final blob = await custody.wrapCredential(
          workspace,
          server,
          credential,
          {
            'action': 'replace',
            'kind': 'password',
            'password': 'synthetic-preflight-private',
          },
        );
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
        if (mode == 'empty') {
          data
            ..clear()
            ..addAll(
              WorkspaceState.empty(
                workspaceId: workspace,
                receiptKeyId: keyId,
                ownerSid: sid,
              ).toJson(),
            );
        }
        final state = WorkspaceState.fromJson(
          data,
          workspaceId: workspace,
          receiptKeyId: keyId,
          ownerSid: sid,
        );
        final records = WorkspaceRecords.fromOperationalState(state);
        if (mode == 'marker3')
          records.workspace.payload = records.workspace.payload.replaceFirst(
            '"schemaVersion":2',
            '"schemaVersion":3',
          );
        final graph = await g.graph();
        if (mode == 'empty')
          for (final rows in graph.values) {
            rows.clear();
          }
        if (mode == 'occupied') {
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
        final files = McpCredentialFiles(
          localAppData: root,
          workspaceId: workspace,
          ownerSid: sid,
          custody: McpCredentialCustody(DpapiProtection()),
        );
        for (final grant in graph['grants']!) {
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
        }
        for (final name in ['workspace.isar', 'workspace.isar-lck']) {
          await createProtectedEmptyFile(root, p.join(active, name), sid);
        }
        db = await Isar.open(
          mode == 'native1'
              ? workspaceSchemas
              : mode == 'native3'
              ? trustedWorkspaceSchemas
              : automationWorkspaceSchemas,
          directory: active,
          name: 'workspace',
          maxSizeMiB: 64,
          relaxedDurability: false,
          inspector: false,
        );
        final seed = db;
        await seed.writeTxn(() async {
          await seed.storedWorkspaces.put(records.workspace);
          await seed.storedSettings.put(records.settings);
          await seed.storedProfiles.putAll(records.profiles);
          await seed.storedCredentials.putAll(records.credentials);
          await seed.storedReceipts.putAll(records.receipts);
          if (mode != 'native1') await seedAutomation(seed, g.rows(graph));
        });
        final before = mode == 'native1' ? null : await raw.capture(seed);
        check(await seed.close());
        db = null;
        final frozen = File(p.join(active, 'workspace.isar')).readAsBytesSync();
        final manifestBefore = File(p.join(active, 'workspace.manifest.json'))
            .readAsBytesSync();
        final wrapperBefore = File(p.join(active, 'receipt-key.dpapi'))
            .readAsBytesSync();
        final suffix = switch (mode) {
          'stage-creating' => '.creating',
          'stage-1-2' => '.upgrading-1-2',
          'stage-2-3' || 'empty-stage' => '.upgrading-2-3',
          _ => null,
        };
        if (suffix != null)
          createProtectedDirectory(root, '$active$suffix', sid);
        if (mode == 'stage-2-3')
          await writeNewProtectedFile(
            root,
            '$active$suffix/migration.json',
            sid,
            utf8.encode('{}'),
          );
        if (mode == 'missing-lock')
          File(p.join(active, 'workspace.isar-lck')).deleteSync();
        if (mode == 'acl-db')
          check(
            (await Process.run('icacls.exe', [
                  p.join(active, 'workspace.isar'),
                  '/grant',
                  '*S-1-1-0:R',
                ])).exitCode ==
                0,
          );
        if (mode == 'closed-key') key.close();
        if (mode == 'closed-lease') await lease.close();
        if (mode == 'probe-disabled')
          await refusal(() async {
            MigrationProbe.install((_) async {});
            return null;
          }, 'MIGRATION_PROBE_UNAVAILABLE');
        if (mode.startsWith('close-')) {
          MigrationProbe.install(
            (_) async {},
            closeNative: (_) async {
              check(Isar.getInstance('workspace')!.isOpen && lease.isHeld);
              if (mode == 'close-throw')
                throw StateError('OWNED_CLOSE_WITHHELD');
              return false;
            },
          );
          await refusal(preflight);
          check(
            WorkspaceMigration.hasOpenReservation &&
                Workspace.hasOpenReservation &&
                lease.isHeld,
          );
          check(Isar.getInstance('workspace')!.isOpen);
          check(
            !File(p.join(active, 'mcp-credentials', g.grantId, 'current.json'))
                .existsSync(),
          );
          await refusal(preflight);
          await refusal(
            () => StateStore.openTrustedOperational(
              localAppData: root,
              appRoot: root,
              lease: lease,
              custody: custody,
              receiptKey: key,
            ),
          );
          stdout.writeln('PASS:$mode');
          await stdout.flush();
          // The component retains the actual native handle/reservation/lease.
          // Exit this owned fault process; OS cleanup is not a successful close.
          exit(0);
        }
        if ({
          'good',
          'empty',
          'empty-stage',
          'probe-disabled',
          'concurrent',
        }.contains(mode)) {
          void validate(UpgradeSnapshot result) {
            check(
              result.rows.length == 15 &&
                  result.foundation.workspaceId == workspace,
            );
            final captured = {
              for (final e in result.rows.entries)
                e.key: [
                  for (final row in e.value)
                    {
                      'nativeId': row.nativeId,
                      'entityId': row.entityId,
                      'payloadBase64': base64Encode(utf8.encode(row.payload)),
                    },
                ],
            };
            check(
              base64Encode(StrictCodec().canonical(captured)) ==
                  base64Encode(StrictCodec().canonical(jsonDecode(before!))),
            );
          }

          if (mode == 'concurrent') {
            final first = preflight();
            check(WorkspaceMigration.hasOpenReservation);
            await refusal(preflight);
            await refusal(
              () => StateStore.openTrustedOperational(
                localAppData: root,
                appRoot: root,
                lease: lease,
                custody: custody,
                receiptKey: key,
              ),
            );
            await refusal(
              () => Workspace.open(
                localAppData: root,
                appRoot: root,
                lease: lease,
                custody: custody,
              ),
            );
            validate(await first);
          } else {
            validate(await preflight());
          }
          check(
            !Workspace.hasOpenReservation &&
                Isar.getInstance('workspace') == null &&
                lease.isHeld,
          );
          await custody.createWorkspaceManifest(key);
          validate(
            await preflight(),
          ); // actual reopen, no lease/key ownership transfer
        } else {
          await refusal(
            preflight,
            mode == 'occupied'
                ? 'HOST_BUSY'
                : {'manifest3', 'native1', 'native3', 'marker3'}.contains(mode)
                ? 'INCOMPATIBLE'
                : 'STORAGE_BLOCKED',
          );
          check(
            !Workspace.hasOpenReservation &&
                Isar.getInstance('workspace') == null,
          );
          if (!{
            'occupied',
            'marker3',
            'bad-credential',
            'bad-client',
          }.contains(mode)) {
            check(
              base64Encode(
                    File(p.join(active, 'workspace.isar')).readAsBytesSync(),
                  ) ==
                  base64Encode(frozen),
            );
          }
        }
        check(
          base64Encode(
                File(p.join(active, 'workspace.manifest.json'))
                    .readAsBytesSync(),
              ) ==
              base64Encode(manifestBefore),
        );
        check(
          base64Encode(
                File(p.join(active, 'receipt-key.dpapi')).readAsBytesSync(),
              ) ==
              base64Encode(wrapperBefore),
        );
        check(
          !File(p.join(active, 'mcp-credentials', g.grantId, 'current.json'))
              .existsSync(),
        );
        if (suffix == null)
          check(!Directory('$active.upgrading-2-3').existsSync());
        if (!{
          'missing-lock',
          'acl-db',
          'closed-key',
          'closed-lease',
          'native1',
        }.contains(mode)) {
          db = await Isar.open(
            mode == 'native3'
                ? trustedWorkspaceSchemas
                : automationWorkspaceSchemas,
            directory: active,
            name: 'workspace',
            maxSizeMiB: 64,
            relaxedDurability: false,
            inspector: false,
          );
          check(await raw.capture(db) == before);
        }
      }
    } finally {
      if (db != null) check(await db.close());
      key.close();
      await lease.close();
    }
    stdout.writeln('PASS:$mode');
  } catch (error, stack) {
    stderr.writeln(error);
    stderr.writeln(stack);
    exitCode = 1;
  }
}
