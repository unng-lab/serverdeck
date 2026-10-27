import 'dart:convert';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_locald/storage/workspace.dart';
import 'package:serverdeck_locald/storage/workspace_migration.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mcp_credential_files.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/process.dart';
import 'package:serverdeck_windows/security.dart';

import 'operational_snapshot_child.dart' show check, sameJson, graphDocument;
import 'operational_open_lock.dart';
import 'grant_transaction_scenarios.dart';
import 'grant_failure_scenarios.dart';
import 'grant_capacity_scenarios.dart';
import 'grant_key_loss_scenarios.dart';
import 'grant_publication_scenarios.dart';
import 'foundation_transaction_scenarios.dart';
import 'profile_catalog_storage_scenarios.dart';

Future<void> refusal(
  Future<Object?> Function() action, [
  String code = 'STORAGE_BLOCKED',
]) async {
  try {
    await action();
  } on StateError catch (e) {
    check(e.message == code);
    return;
  }
  throw StateError('EXPECTED_OWNED_OPEN_REFUSAL');
}

// Actual native instance is closed during the grant DPAPI check, then custody
// fails: cleanup receives false. This proves retained reservation on an
// unconfirmed close, not a leaked native handle or a DPAPI outage simulation.
final class ClosedGrantFailure implements UserProtection {
  final actual = DpapiProtection();
  bool triggered = false;
  @override
  Future<List<int>> protect(List<int> bytes, List<int> entropy) =>
      actual.protect(bytes, entropy);
  @override
  Future<List<int>> unprotect(List<int> bytes, List<int> entropy) async {
    if (utf8.decode(entropy).contains('serverdeck-next-mcp-client-v1')) {
      check(await Isar.getInstance('workspace')!.close());
      triggered = true;
      throw StateError('PROTECTION_UNAVAILABLE');
    }
    return actual.unprotect(bytes, entropy);
  }
}

Future<void> verifyOwnedOperationalOpen({
  required String root,
  required String bundle,
  required String mode,
  required McpCredentialFiles files,
  required ReceiptKeyMaterial key,
  required MutexLease lease,
  required KeyCustody custody,
  required Map<String, Object?> expected,
  required Future<void> Function(Isar) unchanged,
}) async {
  final directory = files.directory, sid = custody.ownerSid;
  final manifest = {
    ...await custody.createWorkspaceManifest(key),
    'format': 2,
    'schema': 2,
  };
  if (mode == 'manifest-malformed') manifest['unexpected'] = true;
  if (mode == 'manifest-foreign')
    manifest['workspaceId'] = '10000000-0000-4000-8000-000000000099';
  if (mode == 'manifest-schema1') {
    manifest.remove('format');
    manifest['schema'] = 1;
  }
  await writeNewProtectedFile(
    root,
    p.join(directory, 'workspace.manifest.json'),
    sid,
    utf8.encode(jsonEncode(manifest)),
  );
  await writeNewProtectedFile(
    root,
    p.join(directory, 'receipt-key.dpapi'),
    sid,
    mode == 'wrapper' ? [1, 2, 3] : key.wrapper,
  );
  if (mode == 'creating' || mode == 'upgrading') {
    createProtectedDirectory(
      root,
      '$directory${mode == 'creating' ? '.creating' : '.upgrading-1-2'}',
      sid,
    );
  }
  if (mode.startsWith('acl-')) {
    final target = switch (mode.substring(4)) {
      'product' => p.join(root, 'ServerDeckNext'),
      'version' => p.join(root, 'ServerDeckNext', 'v1'),
      'parent' => p.dirname(directory),
      'active' => directory,
      'database' => p.join(directory, 'workspace.isar'),
      _ => p.join(directory, 'workspace.isar-lck'),
    };
    final result = await Process.run('icacls.exe', [
      target,
      '/grant',
      '*S-1-1-0:(F)',
    ]);
    check(result.exitCode == 0);
  }
  String? restoreFrom, restoreTo;
  if (mode == 'junction' || mode == 'link-database' || mode == 'link-lock') {
    restoreTo = mode == 'junction'
        ? p.join(root, 'ServerDeckNext')
        : p.join(
            directory,
            mode == 'link-database' ? 'workspace.isar' : 'workspace.isar-lck',
          );
    restoreFrom = p.join(root, 'retained-target');
    check(
      p.isWithin(root, p.absolute(restoreTo)) &&
          p.isWithin(root, p.absolute(restoreFrom)),
    );
    if (mode == 'junction') {
      Directory(restoreTo).renameSync(restoreFrom);
      final result = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          'New-Item -ItemType Junction -Path \$env:SERVERDECK_TEST_JUNCTION -Target \$env:SERVERDECK_TEST_TARGET -ErrorAction Stop | Out-Null',
        ],
        environment: {
          'SERVERDECK_TEST_JUNCTION': restoreTo,
          'SERVERDECK_TEST_TARGET': restoreFrom,
        },
      );
      check(result.exitCode == 0);
    } else {
      File(restoreTo).renameSync(restoreFrom);
      Link(restoreTo).createSync(restoreFrom);
    }
  }
  final sourcePath = mode == 'junction'
      ? p.join(restoreFrom!, 'v1', 'workspaces', 'default', 'workspace.isar')
      : mode == 'link-database'
      ? restoreFrom!
      : p.join(directory, 'workspace.isar');
  final originalHash = fileSha256(sourcePath);
  if (mode == 'bundle')
    File(p.join(bundle, 'locald.exe')).writeAsBytesSync([9]);
  final fault = ClosedGrantFailure();
  final lockFault = lockedOpener(sid, p.join(directory, 'workspace.isar'));
  final loadCustody = mode == 'close-false'
      ? KeyCustody(fault, sid)
      : mode == 'open-throw'
      ? lockFault
      : custody;
  if (mode == 'closed-key') key.close();
  if (mode == 'closed-lease') await lease.close();
  Future<StateStore> open() => StateStore.openOperational(
    localAppData: root,
    appRoot: bundle,
    lease: lease,
    custody: loadCustody,
    receiptKey: key,
  );
  StateStore? store;
  Future<void> refuseLegacyBeforeIo({required bool pending}) async {
    check(
      StateStore.hasOpenReservation && Isar.getInstance('workspace') == null,
    );
    final other = p.join(root, 'competing-local-app-data');
    check(p.isWithin(root, other) && !Directory(other).existsSync());
    Directory(other).createSync();
    await refusal(
      () => Workspace.open(
        localAppData: other,
        // During a pending open, fail the old entry immediately at verification
        // instead of deliberately racing two native opens. With a retained
        // reservation/no native instance use the real bundle and assert no files.
        appRoot: pending ? p.join(root, 'must-not-probe-bundle') : bundle,
        lease: lease,
        custody: custody,
      ),
    );
    check(Directory(other).listSync(followLinks: false).isEmpty);
    check(StateStore.hasOpenReservation && lease.isHeld);
  }

  try {
    const positive = {
      'good',
      'empty',
      'stale',
      'revoked',
      'reservation',
      'reservation-race',
      'grant-basic',
    };
    if (!positive.contains(mode) &&
        !foundationWriteModes.contains(mode) &&
        !profileCatalogModes.contains(mode) &&
        !grantBoundaryModes.contains(mode) &&
        !grantFaultModes.contains(mode) &&
        !grantKillModes.contains(mode) &&
        !grantKeyLossModes.contains(mode) &&
        !grantPublicationModes.contains(mode) &&
        mode != 'grant-capacity') {
      final incompatible = {
        'manifest-schema1',
        'wrong-schema',
        'native-schema1',
        'bundle',
      }.contains(mode);
      await refusal(open, incompatible ? 'INCOMPATIBLE' : 'STORAGE_BLOCKED');
      final retained = {'close-false', 'open-throw'}.contains(mode);
      check(StateStore.hasOpenReservation == retained);
      check(Workspace.hasOpenReservation == retained);
      check(Isar.getInstance('workspace') == null);
      if (mode == 'open-throw') {
        check(lockFault.triggered && lease.isHeld);
        await lockFault.closeFixture();
      }
      if (mode == 'close-false') check(fault.triggered && lease.isHeld);
      if (retained) await refuseLegacyBeforeIo(pending: false);
      if (!{
        'wrong-schema',
        'bad-graph',
        'bad-native-id',
        'second-corrupt',
        'second-lookup',
        'close-false',
      }.contains(mode)) {
        check(fileSha256(sourcePath) == originalHash);
      }
      check(
        !File(
          p.join(
            directory,
            'mcp-credentials',
            '10000000-0000-4000-8000-000000000007',
            'current.json',
          ),
        ).existsSync(),
      );
      stdout.writeln('OWNED_OPERATIONAL_REFUSAL_PROVED');
      return;
    }
    if (mode == 'reservation-race') {
      final opening = open();
      try {
        await refuseLegacyBeforeIo(pending: true);
      } finally {
        store = await opening;
      }
    } else {
      store = await open();
    }
    check(StateStore.hasOpenReservation && lease.isHeld);
    final before = store.operational.foundation.rows.digest();
    sameJson(expected, graphDocument(store.operational), 'owned-snapshot');
    await unchanged(Isar.getInstance('workspace')!);
    await refusal(() => store!.commit(store.state));
    check(store.operational.foundation.rows.digest() == before);
    await unchanged(Isar.getInstance('workspace')!);
    if (mode == 'reservation') {
      final native = Isar.getInstance('workspace');
      await refusal(open);
      await refusal(
        () => StateStore.open(
          localAppData: root,
          directory: directory,
          appRoot: bundle,
          lease: lease,
          custody: custody,
          receiptKey: key,
        ),
      );
      await refusal(
        () => WorkspaceMigration.run(
          localAppData: root,
          appRoot: bundle,
          lease: lease,
          custody: custody,
        ),
      );
      await refusal(
        () => Workspace.open(
          localAppData: root,
          appRoot: bundle,
          lease: lease,
          custody: custody,
        ),
      );
      check(identical(native, Isar.getInstance('workspace')) && native!.isOpen);
    }
    await store.close();
    await refusal(() async => store!.operational);
    store = null;
    check(!Workspace.hasOpenReservation && lease.isHeld);
    await custody.createWorkspaceManifest(key);
    store = await open();
    check(store.operational.foundation.rows.digest() == before);
    sameJson(expected, graphDocument(store.operational), 'owned-reopened');
    await unchanged(Isar.getInstance('workspace')!);
    final grant = store.operational.automation.grants.values.firstOrNull;
    if (grant != null) {
      final lookup = await files.readLookupForRecovery(grant.id);
      check(
        lookup != null &&
            lookup.binding.secretRef == grant.secretRef &&
            lookup.revoked == (mode == 'revoked'),
      );
      if (mode == 'revoked')
        await refusal(() => files.readForBridge(grant.id), 'FORBIDDEN');
    }
    if (mode == 'grant-basic')
      store = await verifyNativeGrantTransactions(store, open, files);
    if (grantBoundaryModes.contains(mode))
      await verifyNativeGrantBoundaries(store, mode, files);
    if (grantFaultModes.contains(mode) || grantKillModes.contains(mode))
      store = await verifyNativeGrantFault(store, open, files, mode);
    if (grantPublicationModes.contains(mode))
      store = await verifyNativeGrantPublication(store, open, files, mode);
    if (mode == 'grant-capacity')
      await verifyActualGrantMapCapacity(
        store,
        files,
        key: key,
        custody: custody,
        lease: lease,
      );
    if (grantKeyLossModes.contains(mode))
      await verifyNativeGrantKeyLoss(
        store: store,
        mode: mode,
        root: root,
        bundle: bundle,
        key: key,
        custody: custody,
        lease: lease,
        files: files,
      );
    if (foundationWriteModes.contains(mode))
      store = await verifyFoundationTransactions(
        store,
        open,
        custody,
        key,
        mode,
      );
    if (profileCatalogModes.contains(mode))
      store = await verifyProfileCatalogStorage(store, open, mode, files);
    stdout.writeln('OWNED_OPERATIONAL_REOPEN_RESERVATION_PROVED');
  } finally {
    if (mode == 'open-throw') await lockFault.closeFixture();
    if (store != null) await store.close();
    if (restoreFrom != null && restoreTo != null) {
      check(
        p.isWithin(root, p.absolute(restoreTo)) &&
            p.isWithin(root, p.absolute(restoreFrom)),
      );
      Link(restoreTo).deleteSync();
      if (mode == 'junction') {
        Directory(restoreFrom).renameSync(restoreTo);
      } else {
        File(restoreFrom).renameSync(restoreTo);
      }
    }
  }
}
