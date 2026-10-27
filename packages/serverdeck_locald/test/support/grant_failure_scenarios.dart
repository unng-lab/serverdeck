import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/mcp/grants.dart';
import 'package:serverdeck_locald/storage/automation_records.dart';
import 'package:serverdeck_locald/storage/grant_write_probe.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_windows/mcp_credential_files.dart';
import 'package:serverdeck_windows/paths.dart';

import '../automation/snapshot_test.dart' as g;
import 'grant_transaction_scenarios.dart';
import 'operational_open_scenarios.dart' show refusal;
import 'operational_snapshot_child.dart' show check, sameJson;

final grantFaultModes = {
  for (final point in GrantWriteBoundary.values) 'grant-fault-${point.name}',
  'grant-corrupt-afterCommit',
  'grant-probe-disabled',
};
final grantKillModes = {
  for (final point in GrantWriteBoundary.values) 'grant-kill-${point.name}',
};

Future<StateStore> verifyNativeGrantFault(
  StateStore initial,
  Future<StateStore> Function() reopen,
  McpCredentialFiles files,
  String mode,
) async {
  var store = initial;
  final input = grantCreate(800, 801);
  OwnerGrantService service() =>
      OwnerGrantService(store, clock: () => DateTime.utc(2026, 10, 21, 12));
  if (mode == 'grant-probe-disabled') {
    check(!grantWriteProbesEnabled);
    try {
      GrantWriteProbe.install((_) async {});
      throw StateError('PROBE_INSTALLED');
    } on StateError catch (e) {
      check(e.message == 'GRANT_PROBE_UNAVAILABLE');
    }
    await refusal(
      () => GrantWriteProbe.hit(GrantWriteBoundary.beforeStage),
      'GRANT_PROBE_UNAVAILABLE',
    );
    await service().submitOwner('grant.create', input);
    return store;
  }
  check(grantWriteProbesEnabled);
  final kill = mode.startsWith('grant-kill-'),
      corrupt = mode == 'grant-corrupt-afterCommit';
  final name = corrupt
      ? 'afterCommit'
      : mode.substring(kill ? 'grant-kill-'.length : 'grant-fault-'.length);
  final point = GrantWriteBoundary.values.singleWhere((p) => p.name == name);
  var fired = false;
  String? blob;
  List<int>? ciphertext;
  final before = store.operational;
  GrantWriteProbe.install((boundary) async {
    if (boundary != point || fired) return;
    fired = true;
    final native = Isar.getInstance('workspace')!;
    final grant = await native.storedMcpGrants.getByEntityId(g.id(801));
    final receipt = await native.storedAutomationReceipts.getByEntityId(
      g.id(800),
    );
    check(
      (grant != null) ==
          (point.index >= GrantWriteBoundary.afterGrantWrite.index),
    );
    check(
      (receipt != null) ==
          (point.index >= GrantWriteBoundary.afterReceiptWrite.index),
    );
    if (point.index >= GrantWriteBoundary.beforeTransaction.index) {
      check(!store.isAutomationReady);
      await refusal(() async => store.operational);
    }
    if (kill) {
      stdout.writeln('GRANT_CRASH_BOUNDARY:${point.name}');
      await stdout.flush();
      await Completer<void>().future;
      return;
    }
    if (corrupt) {
      final metadata = jsonDecode(grant!.payload) as Map;
      blob = p.join(
        files.directory,
        'mcp-credentials',
        g.id(801),
        '${metadata['secretRef']}.dpapi',
      );
      ciphertext = await readProtectedFile(
        files.localAppData,
        blob!,
        files.ownerSid,
        maxBytes: 16384,
      );
      await replaceProtectedFile(files.localAppData, blob!, files.ownerSid, [
        1,
        2,
        3,
      ]);
      return;
    }
    throw StateError('PRIVATE_SYNTHETIC_BOUNDARY_FAILURE');
  });
  try {
    await refusal(() => service().submitOwner('grant.create', input));
    check(fired && !store.isAutomationReady);
    await refusal(() async => store.operational);
    await refusal(
      () => service().submitOwner('grant.create', grantCreate(802, 803)),
    );
    final committed = point.index >= GrantWriteBoundary.afterCommit.index;
    final native = Isar.getInstance('workspace')!;
    check(
      (await native.storedMcpGrants.getByEntityId(g.id(801)) != null) ==
          committed,
    );
    check(
      (await native.storedAutomationReceipts.getByEntityId(g.id(800)) !=
              null) ==
          committed,
    );
    await store.close();
    if (ciphertext != null) {
      // Explicit fixture repair, never product fallback. The corrupt referenced
      // blob must first make an actual fresh opener refuse without repairing it.
      await refusal(reopen);
      await replaceProtectedFile(
        files.localAppData,
        blob!,
        files.ownerSid,
        ciphertext!,
      );
    }
    store = await reopen();
    check(store.operational.automation.grants.length == (committed ? 1 : 0));
    final beforeReplay = credentialFiles(files);
    sameJson(
      {'grantId': g.id(801), 'revision': 1},
      await service().submitOwner('grant.create', input),
      'fault-recovery-replay',
    );
    if (committed)
      check(credentialFiles(files) == beforeReplay);
    else
      check(credentialFiles(files) == beforeReplay + 2);
    baselineRetained(before, store.operational);
    check(
      store.isAutomationReady &&
          store.operational.automation.receipts.length == 1,
    );
    stdout.writeln(
      'ACTUAL_NATIVE_GRANT_BOUNDARY_ROLLBACK_BLOCK_RECOVERY_PROVED',
    );
    return store;
  } catch (_) {
    if (!identical(store, initial)) await store.close();
    rethrow;
  }
}
