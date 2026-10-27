import 'dart:ffi';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/storage/automation_records.dart';
import 'package:serverdeck_locald/storage/migration_rows.dart';
import 'package:serverdeck_locald/storage/native_schema.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_windows/process.dart';

void check(bool value) {
  if (!value) throw StateError('SCHEMA_FIXTURE_FAILED');
}

Future<MigrationRows> capture(
  Isar database,
  int schema,
) async => MigrationRows.capture(
  schema: schema,
  workspace: MigrationRow(1, (await database.storedWorkspaces.get(1))!.payload),
  settings: MigrationRow(1, (await database.storedSettings.get(1))!.payload),
  profiles: [
    for (final row in await database.storedProfiles.where().findAll())
      MigrationRow(row.id, row.payload, entityId: row.entityId),
  ],
  credentials: [
    for (final row in await database.storedCredentials.where().findAll())
      MigrationRow(row.id, row.payload, entityId: row.entityId),
  ],
  receipts: [
    for (final row in await database.storedReceipts.where().findAll())
      MigrationRow(row.id, row.payload, entityId: row.entityId),
  ],
);

Future<void> main(List<String> args) async {
  final root = p.normalize(p.absolute(args[0]));
  check(
    p.isWithin(p.normalize(p.absolute(Directory.systemTemp.path)), root) &&
        p.basename(root).startsWith('serverdeck-automation-schema-'),
  );
  await Isar.initializeIsarCore(
    libraries: {Abi.windowsX64: args[1]},
    download: false,
  );
  final source = Directory(p.join(root, 'source'))..createSync();
  final stage = Directory(p.join(root, 'stage'))..createSync();
  const uuid = '10000000-0000-4000-8000-000000000001';
  const key = '10000000-0000-4000-8000-000000000002';
  const profileId = '10000000-0000-4000-8000-000000000003';
  final metadata =
      '{"schemaVersion":1,"workspaceId":"$uuid","receiptKeyId":"$key","ownerSid":"S-1-5-21-123","storeRevision":"0"}';
  Isar? database;
  try {
    database = await Isar.open(
      workspaceSchemas,
      directory: source.path,
      name: 'workspace',
      maxSizeMiB: 64,
      relaxedDurability: false,
      inspector: false,
    );
    final original = database;
    await original.writeTxn(() async {
      await original.storedWorkspaces.put(
        StoredWorkspace()..payload = metadata,
      );
      await original.storedSettings.put(
        StoredSettings()..payload = '{"theme":"system"}',
      );
      await original.storedProfiles.put(
        StoredProfile()
          ..id = 7
          ..entityId = profileId
          ..payload = '{"id":"$profileId","name":"synthetic"}',
      );
    });
    final before = (await capture(original, 1)).digest();
    check(await original.close());
    database = null;
    final sourceFile = File(p.join(source.path, 'workspace.isar'));
    final sourceHash = fileSha256(sourceFile.path);
    check(inspectNativeWorkspaceSchema(await sourceFile.readAsBytes()) == 1);
    validateNativeSnapshot(await sourceFile.readAsBytes());
    sourceFile.copySync(p.join(stage.path, 'workspace.isar'));
    database = await Isar.open(
      automationWorkspaceSchemas,
      directory: stage.path,
      name: 'workspace',
      maxSizeMiB: 64,
      relaxedDurability: false,
      inspector: false,
    );
    final candidate = database;
    check((await candidate.storedWorkspaces.get(1))!.payload == metadata);
    // Schema open already migrated the native registry; the application marker
    // changes only in this explicit staged transaction.
    await candidate.writeTxn(() async {
      final row = (await candidate.storedWorkspaces.get(1))!;
      row.payload = metadata.replaceFirst(
        '"schemaVersion":1',
        '"schemaVersion":2',
      );
      await candidate.storedWorkspaces.put(row);
    });
    check((await capture(candidate, 2)).digest() == before);
    for (final collection in [
      candidate.storedMcpGrants,
      candidate.storedDelegations,
      candidate.storedAutomationProfiles,
      candidate.storedAutomationRevisions,
      candidate.storedAutomationPlans,
      candidate.storedAutomationApprovals,
      candidate.storedAutomationJobs,
      candidate.storedDesiredStates,
      candidate.storedAutomationReceipts,
      candidate.storedAutomationEvents,
    ]) {
      check(await collection.count() == 0);
    }
    check(await candidate.close());
    database = null;
    final targetBytes = await File(p.join(stage.path, 'workspace.isar'))
        .readAsBytes();
    check(inspectNativeWorkspaceSchema(targetBytes) == 2);
    try {
      validateNativeSnapshot(targetBytes);
      throw StateError('LEGACY_ACCEPTED_V2');
    } on StateError catch (error) {
      check(error.message == 'INCOMPATIBLE');
    }
    check(fileSha256(sourceFile.path) == sourceHash);
    stdout.writeln(
      'ACTUAL_STAGED_NATIVE_V1_V2_REGISTRY_AND_RAW_ROW_PRESERVATION_PROVED',
    );
  } finally {
    if (database != null) check(await database.close());
  }
}
