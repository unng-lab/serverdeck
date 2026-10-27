import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/mcp/grants.dart';
import 'package:serverdeck_locald/storage/automation_records.dart';
import 'package:serverdeck_locald/storage/foundation_snapshot.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/native_failure.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_windows/mcp_credential_files.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';

import '../automation/snapshot_test.dart' as g;
import 'grant_transaction_scenarios.dart';
import 'operational_snapshot_child.dart' show check, sameJson;

/// Real replacements and settings maintenance with a retained native reader fill
/// the unchanged 64MiB map. No fake capacity code or reduced production quota.
Future<void> verifyActualGrantMapCapacity(
  StateStore store,
  McpCredentialFiles files, {
  required ReceiptKeyMaterial key,
  required KeyCustody custody,
  required MutexLease lease,
}) async {
  final service = OwnerGrantService(
    store,
    clock: () => DateTime.utc(2026, 10, 21, 12),
  );
  await service.submitOwner('grant.create', grantCreate(900, 901));
  final native = Isar.getInstance('workspace')!;
  final pinned = Completer<void>(), release = Completer<void>();
  final reader = native.txn(() async {
    check(await native.storedMcpGrants.getByEntityId(g.id(901)) != null);
    pinned.complete();
    await release.future;
  });
  await pinned.future;
  Future<void> fillRetainedPages() async {
    final original = (await native.storedSettings.get(1))!.payload;
    final parsed = jsonDecode(original) as Map;
    final alternate = jsonEncode({
      ...parsed,
      'reduceMotion': !(parsed['reduceMotion'] as bool),
    });
    var full = false;
    for (var n = 0; n < 20000; n++) {
      try {
        // Owned fixture maintenance restores the exact row in every commit.
        // Only the real pinned reader prevents native page reclamation.
        await native.writeTxn(() async {
          await native.storedSettings.put(
            StoredSettings()..payload = alternate,
          );
          await native.storedSettings.put(StoredSettings()..payload = original);
        });
      } catch (error) {
        if (!isNativeCapacityFailure(error)) rethrow;
        full = true;
        break;
      }
    }
    check(full && (await native.storedSettings.get(1))!.payload == original);
    final fresh = await readOperationalSnapshot(
      native,
      key,
      custody,
      localAppData: files.localAppData,
      lease: lease,
    );
    baselineRetained(store.operational, fresh);
    for (final group in store.operational.rows.entries) {
      check(fresh.rows[group.key]!.length == group.value.length);
    }
    stdout.writeln('ACTUAL_GRANT_NATIVE_MAINTENANCE_MAP_FULL_PROVED');
  }

  Map<String, Object?>? failed;
  var committed = 0;
  final retired = <String>{};
  Future<void> maintainSelectedRetiredBlobs() async {
    // Explicit owner fixture maintenance, never runtime automatic GC. Dry-run
    // all protected inventory and fully revalidate committed native authority
    // while no mutation is pending. Keep all rows, receipts and current files.
    check(store.isAutomationReady && lease.isHeld);
    await files.validateInventory();
    final fresh = await readOperationalSnapshot(
      native,
      key,
      custody,
      localAppData: files.localAppData,
      lease: lease,
    );
    baselineRetained(store.operational, fresh);
    final referenced = fresh.automation.grants.values
        .map((grant) => grant.secretRef)
        .toSet();
    final root = p.normalize(p.absolute(files.localAppData));
    check(p.isWithin(p.normalize(p.absolute(Directory.systemTemp.path)), root));
    check(p.basename(root).startsWith('serverdeck-operational-snapshot-'));
    final folder = p.join(files.directory, 'mcp-credentials', g.id(901));
    final selected = <String>[];
    for (final ref in retired) {
      check(!referenced.contains(ref));
      final target = p.normalize(p.absolute(p.join(folder, '$ref.dpapi')));
      check(p.isWithin(root, target) && p.equals(p.dirname(target), folder));
      requireSafePath(root, target);
      requireOwnerOnlyFileAcl(target, key.ownerSid);
      check(
        FileSystemEntity.typeSync(target, followLinks: false) ==
            FileSystemEntityType.file,
      );
      selected.add(target);
    }
    // The selected set is complete before any deletion, and contains only
    // successful previous revisions recorded by this owned fixture.
    for (final target in selected) {
      check(lease.isHeld && store.isAutomationReady);
      File(target).deleteSync();
    }
    retired.clear();
    await files.validateInventory();
  }

  try {
    for (var i = 0; i < 128; i++) {
      // Exercise real successful key/receipt replacements first, then fill with
      // native maintenance rather than thousands of quadratic full-graph loads.
      if (i == 8) await fillRetainedPages();
      final before = store.operational;
      final request = {
        ...grantCreate(20000 + i, 901),
        'expectedRevision': before.automation.grants[g.id(901)]!.revision,
      };
      final count = credentialFiles(files);
      try {
        await service.submitOwner('grant.replace', request);
        committed++;
        retired.add(before.automation.grants[g.id(901)]!.secretRef);
        if (committed % 16 == 0) await maintainSelectedRetiredBlobs();
        if (committed % 100 == 0) {
          stdout.writeln('GRANT_NATIVE_CAPACITY_COMMITS=$committed');
          await stdout.flush();
        }
      } on StateError catch (e) {
        check(e.message == 'RESOURCE_LIMIT');
        // A staged orphan and unchanged rows distinguish the actual native
        // transaction-capacity branch from pre-stage file/logical admission.
        check(credentialFiles(files) == count + 1 && store.isAutomationReady);
        baselineRetained(before, store.operational);
        check(
          !store.operational.automation.receipts.containsKey(g.id(20000 + i)),
        );
        final lookup = await files.readLookupForRecovery(g.id(901));
        check(
          lookup!.binding.secretRef ==
              before.automation.grants[g.id(901)]!.secretRef,
        );
        failed = request;
        break;
      }
    }
    check(failed != null && committed >= 8);
  } finally {
    release.complete();
    await reader;
  }
  // Native page reclamation is now possible. Retry consumes the same original
  // request exactly once, choosing a fresh blob and retaining the failed orphan.
  final expectedRevision = (failed!['expectedRevision'] as int) + 1;
  sameJson(
    {'grantId': g.id(901), 'revision': expectedRevision},
    await service.submitOwner('grant.replace', failed),
    'native-capacity-retry',
  );
  final after = credentialFiles(files);
  await service.submitOwner('grant.replace', failed);
  check(credentialFiles(files) == after && store.isAutomationReady);
  stdout.writeln('ACTUAL_GRANT_NATIVE_MAP_FULL_ROLLBACK_RECLAIM_REPLAY_PROVED');
}
