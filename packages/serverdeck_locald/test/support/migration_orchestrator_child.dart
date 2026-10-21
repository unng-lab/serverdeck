import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/dart.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/bootstrap/native_runtime.dart';
import 'package:serverdeck_locald/profiles/mutation_coordinator.dart';
import 'package:serverdeck_locald/storage/automation_records.dart';
import 'package:serverdeck_locald/storage/foundation_snapshot.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/migration_probe.dart';
import 'package:serverdeck_locald/storage/native_schema.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_locald/storage/workspace.dart';
import 'package:serverdeck_locald/storage/workspace_migration.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/process.dart';
import 'package:serverdeck_windows/security.dart';

void check(bool value) {
  if (!value) throw StateError('ORCHESTRATOR_FIXTURE_FAILED');
}

final class FaultProtection implements UserProtection {
  FaultProtection(this.mode);
  final String mode;
  final UserProtection actual = DpapiProtection();
  bool refused = false;
  @override
  Future<List<int>> protect(List<int> value, List<int> entropy) =>
      actual.protect(value, entropy);
  @override
  Future<List<int>> unprotect(List<int> value, List<int> entropy) {
    final context = utf8.decode(entropy);
    if ((mode == 'fault-dpapi-key' && context.endsWith('\nreceipt')) ||
        (mode == 'fault-dpapi-credential' &&
            context.endsWith('\ncredential'))) {
      refused = true;
      throw StateError('PROTECTION_UNAVAILABLE');
    }
    return actual.unprotect(value, entropy);
  }
}

Future<void> blocked(Future<Object?> operation) async {
  try {
    await operation;
  } on StateError catch (error) {
    check(error.message == 'STORAGE_BLOCKED');
    return;
  }
  throw StateError('CONCURRENT_OWNER_ACCEPTED');
}

Future<void> main(List<String> args) async {
  final root = p.normalize(p.absolute(args[0])),
      bundle = args[1],
      mode = args[2];
  check(
    p.isWithin(p.normalize(p.absolute(Directory.systemTemp.path)), root) &&
        p.basename(root).startsWith('serverdeck-migration-fixture-'),
  );
  final sid = currentUserSid(), local = p.join(root, 'local');
  final hash = const DartSha256()
      .hashSync(utf8.encode('orchestrator-$root'))
      .bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  final lease = await MutexLease.acquire(
    'Global\\ServerDeckNext.v1.$hash',
    sid,
  );
  check(lease.isHeld);
  final protection = FaultProtection(mode);
  final custody = KeyCustody(protection, sid);
  final active = p.join(local, 'ServerDeckNext', 'v1', 'workspaces', 'default');
  final stage = '$active.upgrading-1-2';
  final evidence = File(p.join(root, 'baseline.json'));
  Workspace? workspace;
  ReceiptKeyMaterial? key;
  Isar? isar;
  try {
    if (mode.startsWith('fault-')) {
      var faultEnabled = mode == 'fault-space-initial', faultReached = false;
      final closeFailure =
          mode == 'fault-close-false' || mode == 'fault-close-throw';
      MigrationProbe.install(
        (boundary) async {
          if ((mode == 'fault-space-journal' &&
                  boundary == MigrationBoundary.journalFlushed) ||
              (mode == 'fault-space-published' &&
                  boundary == MigrationBoundary.databasePublished))
            faultEnabled = true;
          if (mode == 'fault-boundary-${boundary.name}') {
            faultReached = true;
            throw StateError('INJECTED_OPERATION_FAILURE');
          }
        },
        minimumFreeBytes: (requested) {
          if (!faultEnabled) return requested;
          faultReached = true;
          return 0x7fffffffffffffff;
        },
        closeNative: (actualClose) async {
          if (!closeFailure) return actualClose();
          faultReached = true;
          if (mode == 'fault-close-throw')
            throw StateError('INJECTED_NATIVE_CLOSE_FAILURE');
          return false;
        },
      );
      await blocked(
        WorkspaceMigration.run(
          localAppData: local,
          appRoot: bundle,
          lease: lease,
          custody: custody,
        ),
      );
      check(faultReached || protection.refused);
      if (closeFailure) {
        check(
          Workspace.hasOpenReservation &&
              lease.isHeld &&
              Isar.getInstance('workspace') != null,
        );
        await blocked(
          WorkspaceMigration.run(
            localAppData: local,
            appRoot: bundle,
            lease: lease,
            custody: custody,
          ),
        );
        await blocked(
          Workspace.open(
            localAppData: local,
            appRoot: bundle,
            lease: lease,
            custody: custody,
          ),
        );
        final baseline = jsonDecode(evidence.readAsStringSync()) as Map;
        final state = baseline['state'] as Map;
        key = await custody.openReceiptKey(
          await readProtectedFile(
            local,
            p.join(active, 'receipt-key.dpapi'),
            sid,
            maxBytes: 16384,
          ),
          state['workspaceId'] as String,
          state['receiptKeyId'] as String,
        );
        await blocked(
          StateStore.open(
            localAppData: local,
            directory: active,
            appRoot: bundle,
            lease: lease,
            custody: custody,
            receiptKey: key,
          ),
        );
        final contender = await MutexLease.acquire(
          'Global\\ServerDeckNext.v1.$hash',
          sid,
        );
        check(!contender.isHeld);
        await contender.close();
        stdout.writeln('FAULT_RETAINED');
        await stdout.flush();
        await Completer<void>().future;
      }
      check(!Workspace.hasOpenReservation && lease.isHeld);
      stdout.writeln('FAULT_REFUSED');
      return;
    }
    if (mode == 'prepare' ||
        mode == 'prepare-raw' ||
        mode == 'prepare-partial-native' ||
        mode == 'prepare-future-marker') {
      createProtectedDirectory(root, local, sid);
      workspace = await Workspace.open(
        localAppData: local,
        appRoot: bundle,
        lease: lease,
        custody: custody,
      );
      final coordinator = MutationCoordinator(
        workspace.store,
        custody,
        workspace.receiptKey,
      );
      try {
        await coordinator.submit(
          '20000000-0000-4000-8000-000000000001',
          ApiMethod.profilesCreate,
          {
            'profileId': '20000000-0000-4000-8000-000000000002',
            'name': 'Native migration fixture',
            'address': 'example.invalid',
            'sshUser': 'synthetic',
            'credential': {
              'action': 'replace',
              'kind': 'password',
              'password': 'owned-fixture-only',
            },
          },
          requester: 'owned-migration-fixture',
        );
      } finally {
        await coordinator.close();
      }
      final state = workspace.store.state.toJson();
      final native = Isar.getInstance('workspace')!;
      if (mode == 'prepare-raw') {
        // Valid old rows need not use canonical JSON bytes. Rewriting even
        // whitespace is forbidden by the migration preservation contract.
        await native.writeTxn(() async {
          final settings = (await native.storedSettings.get(1))!;
          settings.payload = ' \n${settings.payload}\t ';
          await native.storedSettings.put(settings);
          final profile =
              (await native.storedProfiles.where().findAll()).single;
          profile.payload = ' \n${profile.payload}\t ';
          await native.storedProfiles.put(profile);
          final credential =
              (await native.storedCredentials.where().findAll()).single;
          credential.payload = ' \n${credential.payload}\t ';
          await native.storedCredentials.put(credential);
          final receipt =
              (await native.storedReceipts.where().findAll()).single;
          receipt.payload = ' \n${receipt.payload}\t ';
          await native.storedReceipts.put(receipt);
        });
      }
      final rowsDigest = (await readFoundationSnapshot(
        native,
        workspace.receiptKey,
        custody,
      )).rows.digest();
      await workspace.close();
      workspace = null;
      if (mode == 'prepare-partial-native' || mode == 'prepare-future-marker') {
        isar = await Isar.open(
          mode == 'prepare-partial-native'
              ? [...workspaceSchemas, StoredMcpGrantSchema]
              : workspaceSchemas,
          directory: active,
          name: 'workspace',
          maxSizeMiB: 64,
          relaxedDurability: false,
          inspector: false,
        );
        if (mode == 'prepare-future-marker') {
          final native = isar;
          await native.writeTxn(() async {
            final row = (await native.storedWorkspaces.get(1))!;
            final metadata = StrictCodec().decode(utf8.encode(row.payload))
              ..['schemaVersion'] = 3;
            row.payload = utf8.decode(StrictCodec().canonical(metadata));
            await native.storedWorkspaces.put(row);
          });
        }
        check(await isar.close());
        isar = null;
      }
      evidence.writeAsStringSync(
        jsonEncode({
          'state': state,
          'rowsDigest': rowsDigest,
          for (final name in [
            'workspace.isar',
            'workspace.manifest.json',
            'receipt-key.dpapi',
          ])
            name: fileSha256(p.join(active, name)),
        }),
        flush: true,
      );
      stdout.writeln('PREPARED');
      return;
    }
    if (mode == 'migrate' || mode == 'kill' || mode == 'refuse') {
      if (mode == 'kill') {
        var occurrences = 0;
        final split = args[3].split(':');
        final selected = MigrationBoundary.values.byName(split[0]);
        final occurrence = split.length == 2 ? int.parse(split[1]) : 1;
        MigrationProbe.install((boundary) async {
          if (boundary == selected && ++occurrences == occurrence) {
            stdout.writeln('BOUNDARY:${args[3]}');
            await stdout.flush();
            await Completer<void>().future;
          }
        });
      }
      if (mode == 'refuse') {
        try {
          await WorkspaceMigration.run(
            localAppData: local,
            appRoot: bundle,
            lease: lease,
            custody: custody,
          );
        } on StateError catch (error) {
          check(
            error.message == 'STORAGE_BLOCKED' ||
                error.message == 'INCOMPATIBLE',
          );
          stdout.writeln('REFUSED');
          return;
        }
        throw StateError('INVALID_MIGRATION_ACCEPTED');
      }
      await WorkspaceMigration.run(
        localAppData: local,
        appRoot: bundle,
        lease: lease,
        custody: custody,
      );
      check(!Workspace.hasOpenReservation);
      stdout.writeln('MIGRATED');
      return;
    }
    if (mode == 'verify') {
      check(!Directory(stage).existsSync());
      final before = jsonDecode(evidence.readAsStringSync()) as Map;
      check(
        fileSha256(p.join(active, 'receipt-key.dpapi')) ==
            before['receipt-key.dpapi'],
      );
      final manifest = StrictCodec().decode(
        await readProtectedFile(
          local,
          p.join(active, 'workspace.manifest.json'),
          sid,
          maxBytes: 4096,
        ),
      );
      check(manifest['schema'] == 2 && manifest['format'] == 2);
      final old = Map<String, Object?>.from(before['state'] as Map);
      check(
        manifest['workspaceId'] == old['workspaceId'] &&
            manifest['receiptKeyId'] == old['receiptKeyId'],
      );
      key = await custody.openReceiptKey(
        await readProtectedFile(
          local,
          p.join(active, 'receipt-key.dpapi'),
          sid,
          maxBytes: 16384,
        ),
        old['workspaceId'] as String,
        old['receiptKeyId'] as String,
      );
      await initializeNativeRuntime(bundle);
      check(
        inspectNativeWorkspaceSchema(
              await File(p.join(active, 'workspace.isar')).readAsBytes(),
            ) ==
            2,
      );
      final copy = p.join(root, 'verification');
      createProtectedDirectory(root, copy, sid);
      final activeHash = fileSha256(p.join(active, 'workspace.isar'));
      await copyProtectedFile(
        root,
        p.join(active, 'workspace.isar'),
        p.join(copy, 'workspace.isar'),
        sid,
      );
      await createProtectedEmptyFile(
        root,
        p.join(copy, 'workspace.isar-lck'),
        sid,
      );
      isar = await Isar.open(
        automationWorkspaceSchemas,
        directory: copy,
        name: 'workspace',
        maxSizeMiB: 64,
        relaxedDurability: false,
        inspector: false,
      );
      final actual = await readFoundationSnapshot(
        isar,
        key,
        custody,
        expectedSchema: 2,
      );
      check(actual.rows.digest() == before['rowsDigest']);
      check(
        base64.encode(StrictCodec().canonical(actual.state.toJson())) ==
            base64.encode(StrictCodec().canonical(old)),
      );
      check(await isar.close());
      isar = null;
      check(fileSha256(p.join(active, 'workspace.isar')) == activeHash);
      stdout.writeln('EXACT_STATE_CREDENTIAL_RECEIPT_PRESERVATION_VERIFIED');
      return;
    }
    throw StateError('UNKNOWN_FIXTURE_MODE');
  } finally {
    if (isar != null) check(await isar.close());
    if (workspace != null) await workspace.close();
    key?.close();
    if (!Workspace.hasOpenReservation) await lease.close();
  }
}
