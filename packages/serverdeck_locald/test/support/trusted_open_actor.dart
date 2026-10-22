import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/bootstrap/native_runtime.dart';
import 'package:serverdeck_locald/storage/automation_records.dart';
import 'package:serverdeck_locald/storage/host_trust_records.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/models.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';

import '../../../serverdeck_windows/test/support/native_fixture_job.dart';
import 'mcp_runtime_actor.dart' show check, ownRoot;
import 'mcp_runtime_actor.dart' as runtime show refusal;
import 'trusted_schema_child.dart' as raw show capture;

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
    const workspace = '10000000-0000-4000-8000-000000000001',
        keyId = '10000000-0000-4000-8000-000000000002';
    final key = await custody.createReceiptKey(workspace, keyId);
    final digest = (await Sha256().hash(utf8.encode(root))).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final lease = await MutexLease.acquire(
      'Global\\ServerDeckNext.v1.$digest',
      sid,
    );
    StateStore? store;
    Isar? seed;
    Future<StateStore> open() => StateStore.openTrustedOperational(
      localAppData: root,
      appRoot: root,
      lease: lease,
      custody: custody,
      receiptKey: key,
    );
    try {
      if (mode.startsWith('role-')) {
        await refusal(open, 'UNAUTHORIZED');
        check(
          !StateStore.hasOpenReservation &&
              Isar.getInstance('workspace') == null,
        );
        check(!Directory(p.join(root, 'ServerDeckNext')).existsSync());
      } else {
        await initializeTrustedNativeRuntime(root);
        var directory = root;
        for (final segment in [
          'ServerDeckNext',
          'v1',
          'workspaces',
          'default',
        ]) {
          directory = p.join(directory, segment);
          createProtectedDirectory(root, directory, sid);
        }
        final document = await custody.createTrustedWorkspaceManifest(key);
        if (mode == 'manifest2') {
          document['format'] = 2;
          document['schema'] = 2;
        }
        if (mode == 'manifest-foreign') document['workspaceId'] = keyId;
        await writeNewProtectedFile(
          root,
          p.join(directory, 'workspace.manifest.json'),
          sid,
          utf8.encode(jsonEncode(document)),
        );
        await writeNewProtectedFile(
          root,
          p.join(directory, 'receipt-key.dpapi'),
          sid,
          mode == 'wrapper' ? [1, 2, 3] : key.wrapper,
        );
        final state = WorkspaceState.fromTrustedJson(
          {
            ...WorkspaceState.empty(
              workspaceId: workspace,
              receiptKeyId: keyId,
              ownerSid: sid,
            ).toJson(),
            'schemaVersion': 3,
          },
          workspaceId: workspace,
          receiptKeyId: keyId,
          ownerSid: sid,
        );
        final records = WorkspaceRecords.fromTrustedState(state);
        if (mode == 'marker2')
          records.workspace.payload = records.workspace.payload.replaceFirst(
            '"schemaVersion":3',
            '"schemaVersion":2',
          );
        for (final name in ['workspace.isar', 'workspace.isar-lck']) {
          await createProtectedEmptyFile(root, p.join(directory, name), sid);
        }
        seed = await Isar.open(
          mode == 'registry2'
              ? automationWorkspaceSchemas
              : trustedWorkspaceSchemas,
          directory: directory,
          name: 'workspace',
          maxSizeMiB: 64,
          relaxedDurability: false,
          inspector: false,
        );
        final db = seed;
        Future<String> capture(Isar source) async =>
            '${await raw.capture(source)}\n${jsonEncode([
              for (final row in await source.storedHostTrusts.where().findAll()) [row.id, row.entityId, row.payload],
            ])}';
        await db.writeTxn(() async {
          await db.storedWorkspaces.put(records.workspace);
          await db.storedSettings.put(records.settings);
          if (mode == 'bad-trust')
            await db.storedHostTrusts.put(
              StoredHostTrust()
                ..entityId = keyId
                ..payload = '{}',
            );
        });
        final retainedRows = mode == 'registry2' ? null : await capture(db);
        check(await db.close());
        seed = null;
        for (final name in ['workspace.isar', 'workspace.isar-lck']) {
          requireOwnerOnlyFileAcl(p.join(directory, name), sid);
        }
        final before = File(p.join(directory, 'workspace.isar'))
            .readAsBytesSync();
        final suffix = switch (mode) {
          'stage-creating' => '.creating',
          'stage-1-2' => '.upgrading-1-2',
          'stage-2-3' => '.upgrading-2-3',
          _ => null,
        };
        if (suffix != null)
          createProtectedDirectory(root, '$directory$suffix', sid);
        if (mode == 'missing-lock')
          File(p.join(directory, 'workspace.isar-lck')).deleteSync();
        if (mode == 'closed-key') key.close();
        if (mode == 'closed-lease') await lease.close();
        if (mode == 'good' || mode == 'concurrent') {
          if (mode == 'concurrent') {
            final first = open();
            await refusal(open);
            store = await first;
          } else {
            store = await open();
          }
          check(
            StateStore.hasOpenReservation &&
                store.isTrustedSnapshotLoaded &&
                !store.isAutomationReady,
          );
          check(
            store.trustedOperational.rows.length == 16 &&
                store.state.schemaVersion == 3,
          );
          final retained = store.trustedOperational.preservationDigest();
          await refusal(() async => store!.operational);
          await refusal(() => store!.commit(state));
          await refusal(
            () => StateStore.openMcpOperational(
              localAppData: root,
              appRoot: root,
              lease: lease,
              custody: custody,
              receiptKey: key,
            ),
          );
          await store.close();
          check(!StateStore.hasOpenReservation && lease.isHeld);
          await custody.createTrustedWorkspaceManifest(key);
          await refusal(() async => store!.trustedOperational);
          store = await open();
          check(store.trustedOperational.preservationDigest() == retained);
          await store.close();
          store = null;
        } else {
          await refusal(
            open,
            {'manifest2', 'registry2', 'marker2'}.contains(mode)
                ? 'INCOMPATIBLE'
                : 'STORAGE_BLOCKED',
          );
          check(
            !StateStore.hasOpenReservation &&
                Isar.getInstance('workspace') == null,
          );
          // Closed native validation failures may touch native housekeeping;
          // every pre-native refusal must preserve the entire database bytes.
          if (!{'marker2', 'bad-trust'}.contains(mode)) {
            final after = File(p.join(directory, 'workspace.isar'))
                .readAsBytesSync();
            check(base64Encode(before) == base64Encode(after));
          }
          if (mode == 'bad-trust' || mode == 'marker2') {
            seed = await Isar.open(
              trustedWorkspaceSchemas,
              directory: directory,
              name: 'workspace',
              maxSizeMiB: 64,
              relaxedDurability: false,
              inspector: false,
            );
            final repair = seed;
            check(await capture(repair) == retainedRows);
            await repair.writeTxn(() async {
              if (mode == 'bad-trust') {
                check(await repair.storedHostTrusts.count() == 1);
                await repair.storedHostTrusts.clear();
              } else {
                final row = (await repair.storedWorkspaces.get(1))!;
                row.payload = row.payload.replaceFirst(
                  '"schemaVersion":2',
                  '"schemaVersion":3',
                );
                await repair.storedWorkspaces.put(row);
              }
            });
            check(await repair.close());
            seed = null;
            store = await open();
            check(store.isTrustedSnapshotLoaded);
            await store.close();
            store = null;
          }
        }
      }
    } finally {
      if (store != null) await store.close();
      if (seed != null) check(await seed.close());
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
