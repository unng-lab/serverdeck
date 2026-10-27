import 'dart:convert';
import 'dart:io';

import 'package:cryptography/dart.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/profiles/mutation_coordinator.dart';
import 'package:serverdeck_locald/storage/automation_records.dart';
import 'package:serverdeck_locald/storage/foundation_snapshot.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_locald/storage/workspace.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/process.dart';
import 'package:serverdeck_windows/security.dart';

void check(bool value) {
  if (!value) throw StateError('MIGRATION_FIXTURE_FAILED');
}

Future<void> rejects(Future<Object?> future) async {
  try {
    await future;
  } on StateError catch (error) {
    check(error.message == 'STORAGE_BLOCKED');
    return;
  }
  throw StateError('INVALID_MIGRATION_COPY_ACCEPTED');
}

final class ToggleProtection implements UserProtection {
  final UserProtection actual = DpapiProtection();
  bool unavailable = false;
  @override
  Future<List<int>> protect(List<int> cleartext, List<int> entropy) =>
      actual.protect(cleartext, entropy);
  @override
  Future<List<int>> unprotect(List<int> ciphertext, List<int> entropy) {
    if (unavailable) throw StateError('STORAGE_BLOCKED');
    return actual.unprotect(ciphertext, entropy);
  }
}

Future<void> main(List<String> args) async {
  final root = p.normalize(p.absolute(args[0])), bundle = args[1];
  check(
    p.isWithin(p.normalize(p.absolute(Directory.systemTemp.path)), root) &&
        p.basename(root).startsWith('serverdeck-migration-fixture-'),
  );
  check(args[2] == 'semantic');
  final sid = currentUserSid();
  final hash = const DartSha256()
      .hashSync(utf8.encode('migration-fixture-$root'))
      .bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  final lease = await MutexLease.acquire(
    'Global\\ServerDeckNext.v1.$hash',
    sid,
  );
  check(lease.isHeld);
  final protection = ToggleProtection(),
      custody = KeyCustody(ToggleProtection(), sid);
  final local = p.join(root, 'local');
  createProtectedDirectory(root, local, sid);
  final stage = p.join(root, 'stage');
  createProtectedDirectory(root, stage, sid);
  Workspace? source;
  ReceiptKeyMaterial? key;
  Isar? database;
  try {
    source = await Workspace.open(
      localAppData: local,
      appRoot: bundle,
      lease: lease,
      custody: custody,
    );
    final coordinator = MutationCoordinator(
      source.store,
      custody,
      source.receiptKey,
    );
    try {
      await coordinator.submit(
        '10000000-0000-4000-8000-000000000001',
        ApiMethod.profilesCreate,
        {
          'profileId': '10000000-0000-4000-8000-000000000002',
          'name': 'Migration fixture',
          'address': 'example.invalid',
          'sshUser': 'synthetic',
          'credential': {
            'action': 'replace',
            'kind': 'password',
            'password': 'synthetic-migration-only-password',
          },
        },
        requester: 'owned-migration-fixture',
      );
    } finally {
      await coordinator.close();
    }
    final originalState = source.store.state.toJson();
    final identity = source.store.state;
    final wrapper = source.receiptKey.wrapper;
    await source.close();
    source = null;
    final active = p.join(
      local,
      'ServerDeckNext',
      'v1',
      'workspaces',
      'default',
    );
    final sourceDb = p.join(active, 'workspace.isar');
    final before = fileSha256(sourceDb);
    final stagedDb = p.join(stage, 'workspace.isar');
    await copyProtectedFile(root, sourceDb, stagedDb, sid);
    await createProtectedEmptyFile(
      root,
      p.join(stage, 'workspace.isar-lck'),
      sid,
    );
    final copiedCustody = KeyCustody(protection, sid);
    key = await copiedCustody.openReceiptKey(
      wrapper,
      identity.workspaceId,
      identity.receiptKeyId,
    );
    database = await Isar.open(
      workspaceSchemas,
      directory: stage,
      name: 'workspace',
      maxSizeMiB: 64,
      relaxedDurability: false,
      inspector: false,
    );
    final old = await readFoundationSnapshot(database, key, copiedCustody);
    check(
      base64.encode(StrictCodec().canonical(old.state.toJson())) ==
          base64.encode(StrictCodec().canonical(originalState)),
    );
    final rowsDigest = old.rows.digest();
    check(await database.close());
    database = null;
    database = await Isar.open(
      automationWorkspaceSchemas,
      directory: stage,
      name: 'workspace',
      maxSizeMiB: 64,
      relaxedDurability: false,
      inspector: false,
    );
    final candidate = database;
    await candidate.writeTxn(() async {
      final row = (await candidate.storedWorkspaces.get(1))!;
      final metadata = StrictCodec().decode(
        utf8.encode(row.payload),
        maxBytes: 4096,
      )..['schemaVersion'] = 2;
      row.payload = utf8.decode(StrictCodec().canonical(metadata));
      await candidate.storedWorkspaces.put(row);
    });
    final target = await readFoundationSnapshot(
      candidate,
      key,
      copiedCustody,
      expectedSchema: 2,
    );
    check(target.rows.digest() == rowsDigest);
    check(
      base64.encode(StrictCodec().canonical(target.state.toJson())) ==
          base64.encode(StrictCodec().canonical(originalState)),
    );
    protection.unavailable = true;
    await rejects(
      readFoundationSnapshot(candidate, key, copiedCustody, expectedSchema: 2),
    );
    protection.unavailable = false;
    await candidate.writeTxn(() async {
      await candidate.storedMcpGrants.put(
        StoredMcpGrant()
          ..entityId = identity.workspaceId
          ..payload = '{}',
      );
    });
    await rejects(
      readFoundationSnapshot(candidate, key, copiedCustody, expectedSchema: 2),
    );
    await candidate.writeTxn(() async {
      await candidate.storedMcpGrants.clear();
    });
    final profile = (await candidate.storedProfiles.where().findAll()).single;
    final oldPayload = profile.payload;
    await candidate.writeTxn(() async {
      profile.payload = '{}';
      await candidate.storedProfiles.put(profile);
    });
    await rejects(
      readFoundationSnapshot(candidate, key, copiedCustody, expectedSchema: 2),
    );
    await candidate.writeTxn(() async {
      profile.payload = oldPayload;
      await candidate.storedProfiles.put(profile);
    });
    key.close();
    await rejects(
      readFoundationSnapshot(candidate, key, copiedCustody, expectedSchema: 2),
    );
    check(await candidate.close());
    database = null;
    check(fileSha256(sourceDb) == before);
    stdout.writeln('MIGRATION_COPIED_SEMANTIC_DPAPI_PRESERVATION_PROVED');
  } finally {
    if (database != null) check(await database.close());
    if (source != null) await source.close();
    key?.close();
    if (!Workspace.hasOpenReservation) await lease.close();
  }
}
