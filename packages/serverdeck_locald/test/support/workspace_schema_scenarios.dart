import 'dart:convert';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/profiles/mutation_coordinator.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_locald/storage/workspace.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/process.dart';

import 'state_store_child.dart' show check;

/// A valid foreign native database, not malformed pages or a manifest version.
/// Every file and operation belongs to this fresh synthetic acceptance root.
Future<void> verifyForeignWorkspaceSchema(
  String root,
  String bundle,
  MutexLease lease,
  String sid,
) async {
  final local = p.join(root, 'foreign-native-schema');
  check(p.isAbsolute(root) && p.isWithin(root, local));
  check(!Directory(local).existsSync());
  createProtectedDirectory(root, local, sid);
  final active = p.join(local, 'ServerDeckNext', 'v1', 'workspaces', 'default');
  final database = p.join(active, 'workspace.isar');
  final retained = p.join(local, 'retained-original.isar');
  final foreignDirectory = p.join(local, 'foreign-database');
  final custody = KeyCustody(DpapiProtection(), sid);
  Future<Workspace> open() => Workspace.open(
    localAppData: local,
    appRoot: bundle,
    lease: lease,
    custody: custody,
  );
  Map<String, String> inventory() => {
    for (final entry in Directory(active).listSync(followLinks: false))
      p.basename(entry.path): fileSha256(entry.path),
  };
  bool sameInventory(Map<String, String> before, Map<String, String> after) =>
      before.length == after.length &&
      before.entries.every((entry) => after[entry.key] == entry.value);
  String canonicalState(Workspace workspace) =>
      base64.encode(StrictCodec().encode(workspace.store.state.toJson()));

  Workspace? owned;
  Isar? foreign;
  try {
    owned = await open();
    final coordinator = MutationCoordinator(
      owned.store,
      custody,
      owned.receiptKey,
    );
    try {
      await coordinator.submit(
        'a2345678-1234-4234-8234-123456789012',
        ApiMethod.profilesCreate,
        {
          'profileId': 'b2345678-1234-4234-8234-123456789012',
          'name': 'Foreign schema recovery',
          'address': 'example.invalid',
          'sshUser': 'synthetic',
          'credential': {
            'action': 'replace',
            'kind': 'password',
            'password': 'synthetic-schema-recovery-password',
          },
        },
        requester: 'owned-schema-fixture',
      );
    } finally {
      await coordinator.close();
    }
    final beforeState = canonicalState(owned);
    check(owned.store.state.profiles.length == 1);
    check(owned.store.state.credentials.length == 1);
    check(owned.store.state.receipts.length == 1);
    await owned.close();
    owned = null;
    final original = inventory();
    check(original.length == 4 && original.containsKey('workspace.isar'));

    createProtectedDirectory(local, foreignDirectory, sid);
    for (final name in ['foreign.isar', 'foreign.isar-lck']) {
      await createProtectedEmptyFile(
        local,
        p.join(foreignDirectory, name),
        sid,
      );
    }
    final foreignSchemas = workspaceSchemas
        .where((schema) => schema.name != 'StoredSettings')
        .toList();
    check(foreignSchemas.length == 4);
    foreign = await Isar.open(
      foreignSchemas,
      directory: foreignDirectory,
      name: 'foreign',
      maxSizeMiB: 64,
      relaxedDurability: false,
      inspector: false,
    );
    check(await foreign.close());
    foreign = null;
    final foreignBytes = await readProtectedFile(
      local,
      p.join(foreignDirectory, 'foreign.isar'),
      sid,
      maxBytes: 64 * 1024 * 1024,
    );
    await promoteProtectedPath(local, database, retained, sid);
    check(fileSha256(retained) == original['workspace.isar']);
    await writeNewProtectedFile(local, database, sid, foreignBytes);
    final rejectedInventory = inventory();
    check(rejectedInventory.length == original.length);
    check(rejectedInventory['workspace.isar'] != original['workspace.isar']);
    for (final entry in original.entries) {
      if (entry.key != 'workspace.isar') {
        check(rejectedInventory[entry.key] == entry.value);
      }
    }
    final watch = Stopwatch()..start();
    try {
      owned = await open().timeout(const Duration(seconds: 30));
      throw StateError('FOREIGN_SCHEMA_ACCEPTED');
    } on StateError catch (error) {
      check(error.message == 'INCOMPATIBLE');
    }
    check(watch.elapsed <= const Duration(seconds: 30));
    check(owned == null && Isar.getInstance('workspace') == null);
    check(sameInventory(rejectedInventory, inventory()));
    check(fileSha256(retained) == original['workspace.isar']);
    check(!Directory('$active.creating').existsSync());
    stdout.writeln('WORKSPACE_FOREIGN_NATIVE_SCHEMA_PRESERVED_REFUSAL_PROVED');

    await promoteProtectedPath(local, retained, database, sid, replace: true);
    check(sameInventory(original, inventory()));
    owned = await open();
    check(canonicalState(owned) == beforeState);
    final credential = owned.store.state.credentials.values.single;
    final plaintext = await custody.openCredential(
      credential.protectedBlob,
      owned.store.state.workspaceId,
      credential.profileId,
      credential.id,
    );
    try {
      check(plaintext['password'] == 'synthetic-schema-recovery-password');
    } finally {
      plaintext.clear();
    }
    stdout.writeln(
      'WORKSPACE_FOREIGN_SCHEMA_ORIGINAL_CREDENTIAL_RECOVERY_PROVED',
    );
  } finally {
    await foreign?.close();
    await owned?.close();
    // Retain failed cases, foreign DB and the original DB without reset/cleanup.
  }
}
