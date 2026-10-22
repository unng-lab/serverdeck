import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/storage/automation_records.dart';
import 'package:serverdeck_locald/storage/host_trust_records.dart';
import 'package:serverdeck_locald/storage/native_schema.dart';
import 'package:serverdeck_locald/storage/records.dart';

void check(bool value) {
  if (!value) throw StateError('TRUSTED_SCHEMA_FIXTURE_FAILED');
}

List<IsarCollection<dynamic>> retained(Isar db) => [
  db.storedWorkspaces,
  db.storedSettings,
  db.storedProfiles,
  db.storedCredentials,
  db.storedReceipts,
  db.storedMcpGrants,
  db.storedDelegations,
  db.storedAutomationProfiles,
  db.storedAutomationRevisions,
  db.storedAutomationPlans,
  db.storedAutomationApprovals,
  db.storedAutomationJobs,
  db.storedDesiredStates,
  db.storedAutomationReceipts,
  db.storedAutomationEvents,
];

// Deliberately structural raw payloads, not a valid application/DPAPI graph.
// The preflight must inspect the actual registry without decoding these rows.
List<dynamic> seedRows() => [
  StoredWorkspace()
    ..id = 1
    ..payload = '{"schemaVersion":2}',
  StoredSettings()
    ..id = 1
    ..payload = '{ "text":"Система 🐧" }',
  StoredProfile()
    ..id = 7
    ..entityId = 'profile'
    ..payload = '{"private":"raw\\u0000"}',
  StoredCredential()
    ..id = 9
    ..entityId = 'credential'
    ..payload = 'opaque credential bytes',
  StoredReceipt()
    ..id = 11
    ..entityId = 'receipt'
    ..payload = '{"revision":"9223372036854775807"}',
  StoredMcpGrant()
    ..id = 13
    ..entityId = 'grant'
    ..payload = '{ "g":1 }',
  StoredDelegation()
    ..id = 15
    ..entityId = 'delegation'
    ..payload = '{}',
  StoredAutomationProfile()
    ..id = 17
    ..entityId = 'automation-profile'
    ..payload = '{"text":"e\u0301"}',
  StoredAutomationRevision()
    ..id = 19
    ..entityId = 'revision:1'
    ..payload = '{}',
  StoredAutomationPlan()
    ..id = 21
    ..entityId = 'plan'
    ..payload = '{}',
  StoredAutomationApproval()
    ..id = 23
    ..entityId = 'approval'
    ..payload = '{}',
  StoredAutomationJob()
    ..id = 25
    ..entityId = 'job'
    ..payload = '{}',
  StoredDesiredState()
    ..id = 27
    ..entityId = 'desired'
    ..payload = '{}',
  StoredAutomationReceipt()
    ..id = 29
    ..entityId = 'automation-receipt'
    ..payload = '{}',
  StoredAutomationEvent()
    ..id = 31
    ..entityId = 'event:1'
    ..payload = '{}',
];

Future<String> capture(Isar db) async {
  final result = <String, Object?>{};
  for (final collection in retained(db)) {
    final rows = await collection.where().findAll();
    rows.sort((dynamic a, dynamic b) => (a.id as int).compareTo(b.id as int));
    result[collection.name] = [
      for (final dynamic row in rows)
        {
          'nativeId': row.id as int,
          'entityId': collection.schema.indexes.isEmpty
              ? null
              : row.entityId as String,
          'payloadBase64': base64.encode(utf8.encode(row.payload as String)),
        },
    ];
  }
  return jsonEncode(result);
}

Future<Isar> open(Directory dir, List<CollectionSchema> schemas) => Isar.open(
  schemas,
  directory: dir.path,
  name: 'workspace',
  maxSizeMiB: 64,
  relaxedDurability: false,
  inspector: false,
);

Future<void> main(List<String> args) async {
  final root = p.normalize(p.absolute(args[0]));
  check(
    p.isWithin(p.normalize(p.absolute(Directory.systemTemp.path)), root) &&
        p.basename(root).startsWith('serverdeck-trusted-schema-'),
  );
  await Isar.initializeIsarCore(
    libraries: {Abi.windowsX64: args[1]},
    download: false,
  );
  Isar? db;
  try {
    final source = Directory(p.join(root, 'source'))..createSync();
    final stage = Directory(p.join(root, 'stage'))..createSync();
    db = await open(source, automationWorkspaceSchemas);
    final sourceDb = db;
    final collections = retained(sourceDb), rows = seedRows();
    check(collections.length == 15 && rows.length == 15);
    await sourceDb.writeTxn(() async {
      for (var i = 0; i < collections.length; i++) {
        await collections[i].put(rows[i]);
      }
    });
    final before = await capture(sourceDb);
    check(await sourceDb.close());
    db = null;
    final sourceFile = File(p.join(source.path, 'workspace.isar'));
    final sourceBytes = await sourceFile.readAsBytes();
    check(inspectNativeWorkspaceSchema(sourceBytes) == 2);
    check(inspectTrustedNativeWorkspaceSchema(sourceBytes) == 2);
    sourceFile.copySync(p.join(stage.path, 'workspace.isar'));
    db = await open(stage, trustedWorkspaceSchemas);
    check(await capture(db) == before);
    check(await db.storedHostTrusts.count() == 0);
    check(await db.close());
    db = null;
    final bytes = await File(p.join(stage.path, 'workspace.isar'))
        .readAsBytes();
    check(inspectTrustedNativeWorkspaceSchema(bytes) == 3);
    for (final inspect in [
      validateNativeSnapshot,
      inspectNativeWorkspaceSchema,
    ]) {
      var refused = false;
      try {
        inspect(bytes);
      } on StateError catch (error) {
        check(error.message == 'INCOMPATIBLE');
        refused = true;
      }
      check(refused);
    }
    // Reopen the actual16-collection file and prove generated unique index.
    db = await open(stage, trustedWorkspaceSchemas);
    final target = db;
    await target.writeTxn(() async {
      await target.storedHostTrusts.put(
        StoredHostTrust()
          ..id = 41
          ..entityId = 'trust'
          ..payload = '{"status":"trusted"}',
      );
    });
    var duplicateRefused = false;
    try {
      await target.writeTxn(() async {
        await target.storedHostTrusts.put(
          StoredHostTrust()
            ..id = 43
            ..entityId = 'trust'
            ..payload = '{"status":"revoked"}',
        );
      });
    } on IsarError {
      duplicateRefused = true;
    }
    check(duplicateRefused && await target.storedHostTrusts.count() == 1);
    check(
      (await target.storedHostTrusts.get(41))!.payload ==
          '{"status":"trusted"}',
    );
    check(await capture(target) == before);
    check(await target.close());
    db = null;
    check(
      base64.encode(await sourceFile.readAsBytes()) ==
          base64.encode(sourceBytes),
    );
    final partial = Directory(p.join(root, 'partial'))..createSync();
    db = await open(partial, [
      for (final schema in trustedWorkspaceSchemas)
        if (schema.name != 'StoredAutomationJob') schema,
    ]);
    check(await db.close());
    db = null;
    var partialRefused = false;
    try {
      inspectTrustedNativeWorkspaceSchema(
        await File(p.join(partial.path, 'workspace.isar')).readAsBytes(),
      );
    } on StateError catch (error) {
      check(error.message == 'INCOMPATIBLE');
      partialRefused = true;
    }
    check(partialRefused);
    stdout.writeln(
      'ACTUAL_NATIVE_SCHEMA3_REGISTRY_RAW15_PRESERVATION_LEGACY_REFUSAL_AND_UNIQUE_INDEX_PROVED',
    );
  } finally {
    if (db != null) check(await db.close());
  }
}
