import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/automation/models.dart'
    show ClientGrantRecord;
import 'package:serverdeck_locald/automation/snapshot.dart';
import 'package:serverdeck_locald/storage/automation_records.dart';
import 'package:serverdeck_locald/storage/foundation_snapshot.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/models.dart';
import 'package:serverdeck_locald/storage/native_schema.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mcp_credentials.dart';
import 'package:serverdeck_windows/mcp_credential_files.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';

import '../automation/snapshot_test.dart' as g;
import 'operational_open_scenarios.dart';
import 'grant_transaction_scenarios.dart';
import 'grant_failure_scenarios.dart';
import 'grant_key_loss_scenarios.dart';
import 'grant_publication_scenarios.dart';
import 'foundation_transaction_scenarios.dart';

void check(bool value) {
  if (!value) throw StateError('OPERATIONAL_FIXTURE_FAILED');
}

Map<String, Object?> graphDocument(OperationalSnapshot snapshot) {
  Map<String, Object?> entries(Map<String, dynamic> values) => {
    for (final entry in values.entries) entry.key: entry.value.toJson(),
  };
  final graph = snapshot.automation;
  return {
    'grants': entries(graph.grants),
    'delegations': entries(graph.delegations),
    'profiles': entries(graph.profiles),
    'revisions': entries(graph.revisions),
    'plans': entries(graph.plans),
    'approvals': entries(graph.approvals),
    'jobs': entries(graph.jobs),
    'desired': entries(graph.desired),
    'events': entries(graph.events),
    'receipts': entries(graph.receipts),
  };
}

void sameJson(Object? a, Object? b, String group) {
  final expected = StrictCodec().canonical(a),
      actual = StrictCodec().canonical(b);
  if (expected.length != actual.length)
    throw StateError('RETAINED_LENGTH_MISMATCH:$group');
  for (var n = 0; n < expected.length; n++) {
    if (expected[n] != actual[n])
      throw StateError('RETAINED_CONTENT_MISMATCH:$group');
  }
}

Future<void> main(List<String> args) async {
  final root = p.normalize(p.absolute(args[0]));
  final owned = args[2].startsWith('owned-');
  final mode = owned ? args[2].substring(6) : args[2];
  check(
    p.isWithin(p.normalize(p.absolute(Directory.systemTemp.path)), root) &&
        p.basename(root).startsWith('serverdeck-operational-snapshot-'),
  );
  final sid = currentUserSid();
  final custody = KeyCustody(DpapiProtection(), sid);
  final base = g.foundation().toJson()..['ownerSid'] = sid;
  final workspaceId = base['workspaceId'] as String,
      keyId = base['receiptKeyId'] as String;
  if (grantBoundaryModes.contains(mode) ||
      grantFaultModes.contains(mode) ||
      grantKillModes.contains(mode) ||
      grantKeyLossModes.contains(mode) ||
      grantPublicationModes.contains(mode) ||
      mode == 'grant-capacity') {
    base
      ..clear()
      ..addAll(
        WorkspaceState.empty(
          workspaceId: workspaceId,
          receiptKeyId: keyId,
          ownerSid: sid,
        ).toJson(),
      );
  }
  final foundation = WorkspaceState.fromJson(
    base,
    workspaceId: workspaceId,
    receiptKeyId: keyId,
    ownerSid: sid,
  );
  final key = await custody.createReceiptKey(workspaceId, keyId);
  final leaseName = (await Sha256().hash(
    utf8.encode('operational-fixture-$root'),
  )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final lease = await MutexLease.acquire(
    'Global\\ServerDeckNext.v1.$leaseName',
    sid,
  );
  Isar? database;
  ReceiptKeyMaterial? wrongKey;
  try {
    check(lease.isHeld);
    var path = root;
    for (final name in ['ServerDeckNext', 'v1', 'workspaces', 'default']) {
      path = p.join(path, name);
      createProtectedDirectory(root, path, sid);
    }
    final files = McpCredentialFiles(
      localAppData: root,
      workspaceId: workspaceId,
      ownerSid: sid,
      custody: McpCredentialCustody(DpapiProtection()),
    );
    final data = await g.graph();
    prepareFoundationJobs(data, mode);
    prepareGrantBoundaryGraph(data, mode, custody, key);
    if (grantFaultModes.contains(mode) ||
        grantKillModes.contains(mode) ||
        grantKeyLossModes.contains(mode) ||
        grantPublicationModes.contains(mode) ||
        mode == 'grant-capacity') {
      for (final rows in data.values) {
        rows.clear();
      }
    }
    final second = g.id(80), secondRef = g.id(81);
    if (mode.startsWith('second-')) {
      data['grants']!.add({
        ...data['grants']!.first,
        'id': second,
        'secretRef': secondRef,
        'scopes': ['author'],
        'serverIds': <String>[],
      });
      data['receipts']!.add({
        ...data['receipts']!.first,
        'requestId': g.id(90),
        'result': {'grantId': second, 'revision': 1},
      });
    }
    if (mode == 'empty' || mode == 'empty-inventory') {
      for (final group in data.values) {
        group.clear();
      }
    }
    if (mode == 'bad-graph') data['jobs']!.single['grantId'] = g.id(99);
    if (mode == 'revoked') {
      data['grants']!.first.addAll({
        'revision': 2,
        'revokedAt': '2026-10-21T10:20:00.000Z',
      });
      data['receipts']!.add({
        ...data['receipts']!.first,
        'requestId': g.id(91),
        'operation': 'grant.revoke',
        'createdAt': '2026-10-21T10:20:00.000Z',
        'result': {'grantId': g.grantId, 'revision': 2},
      });
    }
    McpCredentialBinding binding(Map<String, Object?> grant) =>
        McpCredentialBinding(
          workspaceId: workspaceId,
          grantId: grant['id'] as String,
          secretRef: grant['secretRef'] as String,
          ownerSid: sid,
          issuedAt: grant['issuedAt'] as String,
        );
    for (final grant in data['grants']!) {
      if (mode == 'second-missing' && grant['id'] == second) continue;
      await files.stage(binding(grant));
    }
    if (mode == 'second-corrupt') {
      await replaceProtectedFile(
        root,
        p.join(files.directory, 'mcp-credentials', second, '$secondRef.dpapi'),
        sid,
        [1, 2, 3],
      );
    }
    if (mode == 'second-lookup' || mode == 'second-foreign') {
      await files.publish(binding(data['grants']!.last), revoked: false);
      final pointer = p.join(
        files.directory,
        'mcp-credentials',
        second,
        'current.json',
      );
      final value = jsonDecode(File(pointer).readAsStringSync()) as Map;
      if (mode == 'second-foreign') value['workspaceId'] = g.id(99);
      await replaceProtectedFile(
        root,
        pointer,
        sid,
        utf8.encode(mode == 'second-lookup' ? '{}' : jsonEncode(value)),
      );
    }
    if (mode == 'stale') {
      final current = data['grants']!.first;
      final old = {...current, 'secretRef': secondRef};
      await files.stage(binding(old));
      await files.publish(binding(old), revoked: false);
    }
    if (mode == 'empty-inventory') {
      final folder = p.join(files.directory, 'mcp-credentials');
      createProtectedDirectory(root, folder, sid);
      await writeNewProtectedFile(root, p.join(folder, 'unexpected'), sid, [1]);
    }
    await Isar.initializeIsarCore(
      libraries: {Abi.windowsX64: args[1]},
      download: false,
    );
    final name = mode == 'wrong-name' ? 'foreign' : 'workspace';
    if (owned) {
      await createProtectedEmptyFile(
        root,
        p.join(files.directory, 'workspace.isar'),
        sid,
      );
      await createProtectedEmptyFile(
        root,
        p.join(files.directory, 'workspace.isar-lck'),
        sid,
      );
    }
    database = await Isar.open(
      mode == 'native-schema1' ? workspaceSchemas : automationWorkspaceSchemas,
      directory: files.directory,
      name: name,
      maxSizeMiB: 64,
      relaxedDurability: false,
      inspector: false,
    );
    final db = database;
    final records = WorkspaceRecords.fromState(foundation);
    final metadata = jsonDecode(records.workspace.payload) as Map;
    metadata['schemaVersion'] =
        mode == 'wrong-schema' || mode == 'native-schema1' ? 1 : 2;
    if (mode == 'bad-foundation') metadata['storeRevision'] = '3';
    records.workspace.payload = jsonEncode(metadata);
    final rows = g.rows(data);
    for (final group in ['grants', 'receipts']) {
      if (mode ==
          (group == 'grants' ? 'grant-id-limit' : 'grant-receipt-id-limit')) {
        final row = rows[group]!.single;
        rows[group]![0] = AutomationSnapshotRow(
          9223372036854775807,
          row.entityId,
          row.payload,
        );
      }
    }
    final expectedGraph = {
      for (final group in rows.entries)
        group.key: {
          for (final row in group.value)
            row.entityId: group.key == 'grants'
                ? ClientGrantRecord.fromJson(
                    jsonDecode(row.payload) as Map<String, Object?>,
                  ).toJson()
                : jsonDecode(row.payload),
        },
    };
    Future<void> unchanged(Isar native) async {
      Future<void> verify<T>(
        IsarCollection<T> collection,
        String group,
        AutomationSnapshotRow Function(T) convert,
      ) async {
        final current = {
          for (final value in await collection.where().findAll())
            convert(value).nativeId: convert(value),
        };
        check(current.length == rows[group]!.length);
        for (final expected in rows[group]!) {
          final actual = current[expected.nativeId];
          check(
            actual != null &&
                actual.entityId == expected.entityId &&
                actual.payload == expected.payload,
          );
        }
      }

      await verify(
        native.storedMcpGrants,
        'grants',
        (r) => AutomationSnapshotRow(r.id, r.entityId, r.payload),
      );
      await verify(
        native.storedDelegations,
        'delegations',
        (r) => AutomationSnapshotRow(r.id, r.entityId, r.payload),
      );
      await verify(
        native.storedAutomationProfiles,
        'profiles',
        (r) => AutomationSnapshotRow(r.id, r.entityId, r.payload),
      );
      await verify(
        native.storedAutomationRevisions,
        'revisions',
        (r) => AutomationSnapshotRow(r.id, r.entityId, r.payload),
      );
      await verify(
        native.storedAutomationPlans,
        'plans',
        (r) => AutomationSnapshotRow(r.id, r.entityId, r.payload),
      );
      await verify(
        native.storedAutomationApprovals,
        'approvals',
        (r) => AutomationSnapshotRow(r.id, r.entityId, r.payload),
      );
      await verify(
        native.storedAutomationJobs,
        'jobs',
        (r) => AutomationSnapshotRow(r.id, r.entityId, r.payload),
      );
      await verify(
        native.storedDesiredStates,
        'desired',
        (r) => AutomationSnapshotRow(r.id, r.entityId, r.payload),
      );
      await verify(
        native.storedAutomationEvents,
        'events',
        (r) => AutomationSnapshotRow(r.id, r.entityId, r.payload),
      );
      await verify(
        native.storedAutomationReceipts,
        'receipts',
        (r) => AutomationSnapshotRow(r.id, r.entityId, r.payload),
      );
    }

    Future<void> put<T>(
      IsarCollection<T> collection,
      String group,
      T Function(AutomationSnapshotRow) make,
    ) async {
      await collection.putAll([for (final row in rows[group]!) make(row)]);
    }

    await db.writeTxn(() async {
      await db.storedWorkspaces.put(records.workspace);
      await db.storedSettings.put(records.settings);
      await db.storedProfiles.putAll(records.profiles);
      await db.storedCredentials.putAll(records.credentials);
      await db.storedReceipts.putAll(records.receipts);
      if (mode == 'native-schema1') return;
      await put(
        db.storedMcpGrants,
        'grants',
        (r) => StoredMcpGrant()
          ..id = r.nativeId
          ..entityId = r.entityId
          ..payload = r.payload,
      );
      await put(
        db.storedDelegations,
        'delegations',
        (r) => StoredDelegation()
          ..id = r.nativeId
          ..entityId = r.entityId
          ..payload = r.payload,
      );
      await put(
        db.storedAutomationProfiles,
        'profiles',
        (r) => StoredAutomationProfile()
          ..id = mode == 'bad-native-id' ? 0 : r.nativeId
          ..entityId = r.entityId
          ..payload = r.payload,
      );
      await put(
        db.storedAutomationRevisions,
        'revisions',
        (r) => StoredAutomationRevision()
          ..id = r.nativeId
          ..entityId = r.entityId
          ..payload = r.payload,
      );
      await put(
        db.storedAutomationPlans,
        'plans',
        (r) => StoredAutomationPlan()
          ..id = r.nativeId
          ..entityId = r.entityId
          ..payload = r.payload,
      );
      await put(
        db.storedAutomationApprovals,
        'approvals',
        (r) => StoredAutomationApproval()
          ..id = r.nativeId
          ..entityId = r.entityId
          ..payload = r.payload,
      );
      await put(
        db.storedAutomationJobs,
        'jobs',
        (r) => StoredAutomationJob()
          ..id = r.nativeId
          ..entityId = r.entityId
          ..payload = r.payload,
      );
      await put(
        db.storedDesiredStates,
        'desired',
        (r) => StoredDesiredState()
          ..id = r.nativeId
          ..entityId = r.entityId
          ..payload = r.payload,
      );
      await put(
        db.storedAutomationEvents,
        'events',
        (r) => StoredAutomationEvent()
          ..id = r.nativeId
          ..entityId = r.entityId
          ..payload = r.payload,
      );
      await put(
        db.storedAutomationReceipts,
        'receipts',
        (r) => StoredAutomationReceipt()
          ..id = r.nativeId
          ..entityId = r.entityId
          ..payload = r.payload,
      );
    });
    if (owned) {
      check(await db.close());
      database = null;
      try {
        await verifyOwnedOperationalOpen(
          root: root,
          bundle: args[3],
          mode: mode,
          files: files,
          key: key,
          lease: lease,
          custody: custody,
          expected: expectedGraph,
          unchanged: unchanged,
        );
      } catch (error, stack) {
        stderr.writeln('OWNED_FIXTURE_FAILED: $error\n$stack');
        rethrow;
      }
      // Retained ownership deliberately keeps the mutex isolate alive. End the
      // successful proof without releasing key/lease before process termination.
      if (StateStore.hasOpenReservation) exit(0);
      return;
    }
    if (data['grants']!.isNotEmpty) {
      try {
        await readFoundationSnapshot(db, key, custody, expectedSchema: 2);
        throw StateError('MIGRATION_ACCEPTED_NONEMPTY_AUTOMATION');
      } on StateError catch (e) {
        check(e.message == 'STORAGE_BLOCKED');
      }
    }
    if (mode == 'closed-lease') await lease.close();
    if (mode == 'wrong-key')
      wrongKey = await custody.createReceiptKey(workspaceId, g.id(99));
    final loadCustody = mode == 'wrong-owner'
        ? KeyCustody(DpapiProtection(), '$sid-1')
        : custody;
    const positive = {'good', 'empty', 'stale', 'revoked'};
    try {
      final snapshot = await readOperationalSnapshot(
        db,
        wrongKey ?? key,
        loadCustody,
        localAppData: mode == 'wrong-directory'
            ? p.join(root, 'foreign')
            : root,
        lease: lease,
      );
      check(positive.contains(mode));
      final actualGraph = graphDocument(snapshot);
      await unchanged(db);
      for (final entry in expectedGraph.entries) {
        sameJson(entry.value, actualGraph[entry.key], entry.key);
      }
      check(snapshot.automation.jobs.length == (mode == 'empty' ? 0 : 1));
      check(snapshot.automation.grants.length == data['grants']!.length);
      try {
        snapshot.automation.grants.clear();
        throw StateError('MUTABLE_GRAPH');
      } on UnsupportedError {
        /* expected immutable maps */
      }
      final digest = snapshot.foundation.rows.digest();
      check(await db.close());
      database = null;
      check(
        inspectNativeWorkspaceSchema(
              await File(p.join(files.directory, 'workspace.isar'))
                  .readAsBytes(),
            ) ==
            2,
      );
      database = await Isar.open(
        automationWorkspaceSchemas,
        directory: files.directory,
        name: 'workspace',
        maxSizeMiB: 64,
        relaxedDurability: false,
        inspector: false,
      );
      final reopened = await readOperationalSnapshot(
        database,
        key,
        custody,
        localAppData: root,
        lease: lease,
      );
      check(reopened.foundation.rows.digest() == digest);
      final reopenedGraph = graphDocument(reopened);
      await unchanged(database);
      for (final entry in expectedGraph.entries) {
        sameJson(entry.value, reopenedGraph[entry.key], entry.key);
      }
      check(reopened.automation.jobs.length == snapshot.automation.jobs.length);
      if (mode != 'empty') {
        final lookup = await files.readLookupForRecovery(g.grantId);
        check(
          lookup != null &&
              lookup.binding.secretRef == data['grants']!.first['secretRef'],
        );
        check(lookup!.revoked == (mode == 'revoked'));
        if (mode == 'revoked') {
          try {
            await files.readForBridge(g.grantId);
            throw StateError('REVOKED_REVIVED');
          } on StateError catch (e) {
            check(e.message == 'FORBIDDEN');
          }
        }
      }
      stdout.writeln('NATIVE_OPERATIONAL_LOAD_REOPEN_PROVED');
    } on StateError catch (e) {
      if (positive.contains(mode)) rethrow;
      check(!positive.contains(mode));
      check(
        e.message ==
            (mode == 'wrong-schema' ? 'INCOMPATIBLE' : 'STORAGE_BLOCKED'),
      );
      check(
        !File(
          p.join(files.directory, 'mcp-credentials', g.grantId, 'current.json'),
        ).existsSync(),
      );
      stdout.writeln('NATIVE_PREFLIGHT_REFUSAL_NO_FIRST_PUBLICATION_PROVED');
    }
  } finally {
    if (database != null) check(await database.close());
    wrongKey?.close();
    // Preserve a failure exit code if uncertain ownership accompanies an error.
    if (owned && StateStore.hasOpenReservation) exit(1);
    key.close();
    await lease.close();
  }
}
