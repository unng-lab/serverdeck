import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/mcp/grants.dart';
import 'package:serverdeck_locald/storage/automation_records.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_windows/mcp_credential_file_probe.dart';
import 'package:serverdeck_windows/mcp_credential_files.dart';
import 'package:serverdeck_windows/paths.dart';

import '../automation/snapshot_test.dart' as g;
import 'grant_transaction_scenarios.dart';
import 'operational_open_scenarios.dart' show refusal;
import 'operational_snapshot_child.dart' show check, sameJson;

const publicationOperations = ['create', 'replace', 'revoke'];
final grantPublicationFaultModes = {
  for (final op in publicationOperations)
    for (final point in McpLookupWriteBoundary.values)
      'grant-pointer-throw-$op-${point.name}',
  'grant-pointer-disabled',
  'grant-pointer-corrupt-readback',
};
final grantPublicationKillModes = {
  for (final op in publicationOperations)
    for (final point in McpLookupWriteBoundary.values)
      'grant-pointer-kill-$op-${point.name}',
};
final grantPublicationModes = {
  ...grantPublicationFaultModes,
  ...grantPublicationKillModes,
};

Map<String, Object?> publicationRequest(String operation) =>
    operation == 'create'
    ? grantCreate(800, 801)
    : operation == 'replace'
    ? {...grantCreate(802, 801), 'expectedRevision': 1}
    : {'requestId': g.id(802), 'grantId': g.id(801), 'expectedRevision': 1};

Future<StateStore> verifyPublicationRecovery(
  StateStore initial,
  Future<StateStore> Function() reopen,
  McpCredentialFiles files,
  String operation,
) async {
  var store = initial;
  final revision = operation == 'create' ? 1 : 2;
  final request = publicationRequest(operation);
  try {
    check(store.isAutomationReady);
    final before = store.operational;
    check(before.automation.grants.length == 1);
    check(before.automation.receipts.length == revision);
    final grant = before.automation.grants[g.id(801)]!;
    check(grant.revision == revision);
    check((grant.revokedAt != null) == (operation == 'revoke'));
    check(before.foundation.state.storeRevision == '0');
    final count = credentialFiles(files);
    final expected = {'grantId': g.id(801), 'revision': revision};
    OwnerGrantService service() => OwnerGrantService(store);
    sameJson(
      expected,
      await service().submitOwner('grant.$operation', request),
      'inner-publication-replay',
    );
    // A historical create receipt must never restore an old key or revoked
    // authority after replacement/revoke, even across another actual reopening.
    sameJson(
      {'grantId': g.id(801), 'revision': 1},
      await service().submitOwner('grant.create', grantCreate(800, 801)),
      'old-create-after-publication',
    );
    check(credentialFiles(files) == count);
    baselineRetained(before, store.operational);
    final pointer = await files.readLookupForRecovery(grant.id);
    check(
      pointer != null &&
          pointer.binding.secretRef == grant.secretRef &&
          pointer.revoked == (operation == 'revoke'),
    );
    if (operation == 'revoke') {
      await refusal(() => files.readForBridge(grant.id), 'FORBIDDEN');
    } else {
      final loaded = await files.readForBridge(grant.id);
      check(loaded.binding.secretRef == grant.secretRef);
      loaded.key.close();
    }
    await store.close();
    store = await reopen();
    baselineRetained(before, store.operational);
    sameJson(
      expected,
      await service().submitOwner('grant.$operation', request),
      'inner-publication-second-open',
    );
    check(credentialFiles(files) == count);
    stdout.writeln('ACTUAL_GRANT_POINTER_RECOVERY_REPLAY_PROVED');
    return store;
  } catch (_) {
    if (!identical(store, initial)) await store.close();
    rethrow;
  }
}

Future<StateStore> verifyNativeGrantPublication(
  StateStore initial,
  Future<StateStore> Function() reopen,
  McpCredentialFiles files,
  String mode,
) async {
  var store = initial;
  OwnerGrantService service() =>
      OwnerGrantService(store, clock: () => DateTime.utc(2026, 10, 21, 12));
  if (mode == 'grant-pointer-disabled') {
    check(!mcpCredentialFileProbesEnabled);
    await refusal(
      () async => McpCredentialFileProbe.installBoundary((_) async {}),
      'MCP_FILE_PROBE_UNAVAILABLE',
    );
    await refusal(
      () => McpCredentialFileProbe.hit(McpLookupWriteBoundary.afterPending),
      'MCP_FILE_PROBE_UNAVAILABLE',
    );
    await service().submitOwner('grant.create', grantCreate(800, 801));
    return store;
  }
  check(mcpCredentialFileProbesEnabled);
  final corrupt = mode == 'grant-pointer-corrupt-readback';
  final parts = mode.split('-'),
      operation = corrupt ? 'create' : parts[3],
      name = corrupt ? 'afterRename' : parts[4];
  final kill = parts[2] == 'kill';
  final point = McpLookupWriteBoundary.values.singleWhere(
    (p) => p.name == name,
  );
  if (operation != 'create')
    await service().submitOwner('grant.create', grantCreate(800, 801));
  final before = store.operational;
  final oldGrant = before.automation.grants[g.id(801)];
  final oldPointer = oldGrant == null
      ? null
      : await files.readLookupForRecovery(g.id(801));
  var fired = false;
  List<int>? validLookup;
  final lookupPath = p.join(
    files.directory,
    'mcp-credentials',
    g.id(801),
    'current.json',
  );
  McpCredentialFileProbe.installBoundary((boundary) async {
    if (boundary != point || fired) return;
    fired = true;
    check(!store.isAutomationReady);
    await refusal(() async => store.operational);
    final native = Isar.getInstance('workspace')!;
    final row = await native.storedMcpGrants.getByEntityId(g.id(801));
    final receipt = await native.storedAutomationReceipts.getByEntityId(
      g.id(operation == 'create' ? 800 : 802),
    );
    check(row != null && receipt != null);
    final grant = jsonDecode(row!.payload) as Map;
    check(grant['revision'] == (operation == 'create' ? 1 : 2));
    check((grant['revokedAt'] != null) == (operation == 'revoke'));
    if (operation == 'replace')
      check(grant['secretRef'] != oldGrant!.secretRef);
    if (operation == 'revoke') {
      sameJson(
        {...oldGrant!.toJson(), 'revision': 2, 'revokedAt': grant['revokedAt']},
        grant,
        'revoke-preserves-binding',
      );
    }
    final pointer = await files.readLookupForRecovery(g.id(801));
    if (point == McpLookupWriteBoundary.afterPending) {
      check((pointer == null) == (oldPointer == null));
      if (pointer != null)
        check(
          pointer.binding.secretRef == oldPointer!.binding.secretRef &&
              !pointer.revoked,
        );
    } else {
      check(
        pointer != null &&
            pointer.binding.secretRef == grant['secretRef'] &&
            pointer.revoked == (operation == 'revoke'),
      );
    }
    final folder = Directory(
      p.join(files.directory, 'mcp-credentials', g.id(801)),
    );
    final pending = folder
        .listSync(followLinks: false)
        .whereType<File>()
        .where((file) => p.basename(file.path).endsWith('.pending'))
        .length;
    check(pending == (point == McpLookupWriteBoundary.afterPending ? 1 : 0));
    if (corrupt) {
      validLookup = await readProtectedFile(
        files.localAppData,
        lookupPath,
        files.ownerSid,
        maxBytes: 4096,
      );
      await replaceProtectedFile(
        files.localAppData,
        lookupPath,
        files.ownerSid,
        [1, 2, 3],
      );
      return;
    }
    if (kill) {
      stdout.writeln('GRANT_POINTER_BOUNDARY:$operation:${point.name}');
      await stdout.flush();
      await Completer<void>().future;
      return;
    }
    throw StateError('PRIVATE_LOOKUP_BOUNDARY_FAILURE');
  });
  try {
    await refusal(
      () => service().submitOwner(
        'grant.$operation',
        publicationRequest(operation),
      ),
    );
    check(fired && !store.isAutomationReady);
    await refusal(() async => store.operational);
    await refusal(
      () => service().submitOwner('grant.create', grantCreate(804, 805)),
    );
    check(StateStore.hasOpenReservation);
    await store.close();
    if (validLookup != null) {
      await refusal(reopen);
      // Explicit fixture repair of the same saved protected current snapshot.
      // Product startup must have refused rather than silently repairing it.
      await replaceProtectedFile(
        files.localAppData,
        lookupPath,
        files.ownerSid,
        validLookup!,
      );
    }
    store = await reopen();
    return await verifyPublicationRecovery(store, reopen, files, operation);
  } catch (_) {
    if (!identical(store, initial)) await store.close();
    rethrow;
  }
}
