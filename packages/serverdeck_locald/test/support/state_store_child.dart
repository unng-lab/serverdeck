import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_locald/bootstrap/native_runtime.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/models.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';

import '../models_test.dart' as fixture;
import '../credential_validation_test.dart' as credentialFixture;
import 'credential_lifecycle.dart';
import 'mutations.dart';
import 'mutation_boundaries.dart';
import 'service_lifecycle.dart';
import 'api_scenarios.dart';
import 'channel_scenarios.dart';
import 'open_close_failure.dart';
import 'resource_scenarios.dart';

void check(bool condition) {
  if (!condition) throw StateError('FIXTURE_ASSERTION');
}

Future<void> rejects(Future<Object?> operation, [String? code]) async {
  try {
    await operation;
  } on StateError catch (error) {
    if (code == null || error.message == code) return;
    rethrow;
  }
  throw StateError('EXPECTED_REJECTION');
}

Future<void> mapFull(StateStore store, KeyCustody custody) async {
  final native = Isar.getInstance('workspace')!;
  final pinned = Completer<void>(), release = Completer<void>();
  // A real retained native reader prevents reclaim of replaced pages. This
  // test pressure preserves valid model/DPAPI records and production64MiB.
  final reader = native.txn(() async {
    await native.storedWorkspaces.get(1);
    pinned.complete();
    await release.future;
  });
  await pinned.future;
  var full = false;
  try {
    final syntheticPem =
        '-----BEGIN PRIVATE KEY-----\n${'QUFB' * 16300}\n-----END PRIVATE KEY-----\n';
    for (var i = 0; i < 1200; i++) {
      final current = store.state;
      final number = (i + 1).toRadixString(16).padLeft(12, '0');
      final credentialId = '22345678-1234-4234-8234-$number';
      final requestId = '32345678-1234-4234-8234-$number';
      final revision = nextRevision(current.storeRevision);
      final profile = current.profiles[fixture.profileId]!.toJson();
      final entityRevision = nextRevision(profile['revision'] as String);
      final credentialRevision = nextRevision(
        profile['credentialRevision'] as String,
      );
      final blob = await custody.wrapCredential(
        fixture.workspace,
        fixture.profileId,
        credentialId,
        {
          'action': 'replace',
          'kind': 'privateKey',
          'privateKey': syntheticPem,
          'passphrase': null,
        },
      );
      final value = current.toJson()..['storeRevision'] = revision;
      (value['profiles'] as Map)[fixture.profileId] = {
        ...profile,
        'revision': entityRevision,
        'address': 'capacity-$i.example.invalid',
        'credentialRevision': credentialRevision,
        'connectionRevision': nextRevision(
          profile['connectionRevision'] as String,
        ),
        'trustRevision': nextRevision(profile['trustRevision'] as String),
        'credentialRef': credentialId,
      };
      value['credentials'] = {
        credentialId: {
          'id': credentialId,
          'revision': credentialRevision,
          'profileId': fixture.profileId,
          'kind': 'privateKey',
          'protectedBlob': blob,
          'createdAt': fixture.time,
          'updatedAt': fixture.time,
        },
      };
      (value['receipts'] as Map)[requestId] = {
        ...fixture.receipt(),
        'requestId': requestId,
        'operation': 'profiles.update',
        'result': {
          'entityId': fixture.profileId,
          'entityRevision': entityRevision,
          'storeRevision': revision,
          'deleted': false,
        },
      };
      final next = WorkspaceState.fromJson(
        value,
        workspaceId: fixture.workspace,
        receiptKeyId: fixture.receiptKeyId,
        ownerSid: custody.ownerSid,
      );
      try {
        await store.commit(next);
      } on StateError catch (error) {
        check(error.message == 'RESOURCE_LIMIT');
        check(
          base64.encode(StrictCodec().canonical(store.state.toJson())) ==
              base64.encode(StrictCodec().canonical(current.toJson())),
        );
        check(!store.state.receipts.containsKey(requestId));
        full = true;
        break;
      }
      if ((i + 1) % 100 == 0) stdout.writeln('CAPACITY_COMMITS=${i + 1}');
    }
    check(full);
  } finally {
    release.complete();
    await reader;
  }
  stdout.writeln('STATESTORE_MAP_FULL_ROLLBACK_PROVED');
}

Future<void> startupDamage(
  Future<StateStore> Function() open,
  Future<Isar> Function() nativeOpen,
  KeyCustody custody,
) async {
  final initial = await nativeOpen();
  final profile = (await initial.storedProfiles.where().findFirst())!;
  final credential = (await initial.storedCredentials.where().findFirst())!;
  final workspace = (await initial.storedWorkspaces.get(1))!;
  check(await initial.close());
  await verifyRecordByteLimits(open, nativeOpen);
  final credentialJson = jsonDecode(credential.payload) as Map<String, Object?>;
  final foreign = await custody.wrapCredential(
    fixture.workspace,
    '12345678-1234-4234-8234-123456789ac1',
    fixture.credentialId,
    {'action': 'replace', 'kind': 'password', 'password': 'synthetic-foreign'},
  );
  final foreignWorkspace = await custody.wrapCredential(
    '62345678-1234-4234-8234-123456789abc',
    fixture.profileId,
    fixture.credentialId,
    {'action': 'replace', 'kind': 'password', 'password': 'synthetic-foreign'},
  );
  final foreignCredential = await custody.wrapCredential(
    fixture.workspace,
    fixture.profileId,
    '72345678-1234-4234-8234-123456789abc',
    {'action': 'replace', 'kind': 'password', 'password': 'synthetic-foreign'},
  );
  for (final candidate in [
    (
      foreign,
      fixture.workspace,
      '12345678-1234-4234-8234-123456789ac1',
      fixture.credentialId,
    ),
    (
      foreignWorkspace,
      '62345678-1234-4234-8234-123456789abc',
      fixture.profileId,
      fixture.credentialId,
    ),
    (
      foreignCredential,
      fixture.workspace,
      fixture.profileId,
      '72345678-1234-4234-8234-123456789abc',
    ),
  ]) {
    final secret = await custody.openCredential(
      candidate.$1,
      candidate.$2,
      candidate.$3,
      candidate.$4,
    );
    try {
      check(secret['kind'] == 'password');
      check(secret['password'] == 'synthetic-foreign');
    } finally {
      secret.clear();
    }
  }
  final damaged = base64.decode(credentialJson['protectedBlob'] as String);
  check(damaged.length > 32);
  damaged[damaged.length - 1] ^= 1;
  final entropy = utf8.encode(
    'ServerDeckNext\nv1\n${fixture.workspace}\n${fixture.profileId}\n${fixture.credentialId}\ncredential',
  );
  final protection = DpapiProtection();
  final cleartext = await protection.unprotect(
    base64.decode(credentialJson['protectedBlob'] as String),
    entropy,
  );
  late String unknownVersion;
  List<int>? modified;
  try {
    final value = StrictCodec().decode(cleartext, maxBytes: 256 * 1024);
    value['version'] = 2;
    modified = StrictCodec().encode(value, maxBytes: 256 * 1024);
    final wrapper = await protection.protect(modified, entropy);
    final reopened = await protection.unprotect(wrapper, entropy);
    try {
      check(base64.encode(reopened) == base64.encode(modified));
    } finally {
      reopened.fillRange(0, reopened.length, 0);
    }
    unknownVersion = base64.encode(wrapper);
  } finally {
    cleartext.fillRange(0, cleartext.length, 0);
    modified?.fillRange(0, modified.length, 0);
  }
  final mutations = <(String, String)>[
    ('profile', profile.payload.replaceFirst('{', '{"name":"duplicate",')),
    (
      'profile',
      jsonEncode({
        ...jsonDecode(profile.payload) as Map,
        'privateField': 'synthetic-unknown',
      }),
    ),
    (
      'credential',
      jsonEncode({
        ...credentialJson,
        'protectedBlob': base64.encode([1, 2, 3]),
      }),
    ),
    ('credential', jsonEncode({...credentialJson, 'protectedBlob': foreign})),
    ('credential', jsonEncode({...credentialJson, 'kind': 'privateKey'})),
    (
      'credential',
      jsonEncode({...credentialJson, 'protectedBlob': base64.encode(damaged)}),
    ),
    (
      'credential',
      jsonEncode({...credentialJson, 'protectedBlob': foreignWorkspace}),
    ),
    (
      'credential',
      jsonEncode({...credentialJson, 'protectedBlob': foreignCredential}),
    ),
    (
      'credential-version',
      jsonEncode({...credentialJson, 'protectedBlob': unknownVersion}),
    ),
    (
      'workspace-version',
      jsonEncode({...jsonDecode(workspace.payload) as Map, 'schemaVersion': 2}),
    ),
    (
      'workspace',
      jsonEncode({
        ...jsonDecode(workspace.payload) as Map,
        'workspaceId': '62345678-1234-4234-8234-123456789abc',
      }),
    ),
    (
      'workspace',
      jsonEncode({
        ...jsonDecode(workspace.payload) as Map,
        'receiptKeyId': '72345678-1234-4234-8234-123456789abc',
      }),
    ),
    (
      'workspace',
      jsonEncode({
        ...jsonDecode(workspace.payload) as Map,
        'storeRevision': '4',
      }),
    ),
  ];
  Future<String> rows(Isar native) async => jsonEncode({
    'workspace': [
      for (final row in await native.storedWorkspaces.where().findAll())
        [row.id, row.payload],
    ],
    'settings': [
      for (final row in await native.storedSettings.where().findAll())
        [row.id, row.payload],
    ],
    'profiles': [
      for (final row in await native.storedProfiles.where().findAll())
        [row.id, row.entityId, row.payload],
    ],
    'credentials': [
      for (final row in await native.storedCredentials.where().findAll())
        [row.id, row.entityId, row.payload],
    ],
    'receipts': [
      for (final row in await native.storedReceipts.where().findAll())
        [row.id, row.entityId, row.payload],
    ],
  });
  final baseline = await nativeOpen();
  final baselineRows = await rows(baseline);
  check(await baseline.close());
  for (final mutation in mutations) {
    final raw = await nativeOpen();
    await raw.writeTxn(() async {
      switch (mutation.$1) {
        case 'profile':
          await raw.storedProfiles.put(
            StoredProfile()
              ..id = profile.id
              ..entityId = profile.entityId
              ..payload = mutation.$2,
          );
        case 'credential':
        case 'credential-version':
          await raw.storedCredentials.put(
            StoredCredential()
              ..id = credential.id
              ..entityId = credential.entityId
              ..payload = mutation.$2,
          );
        case 'workspace':
        case 'workspace-version':
          await raw.storedWorkspaces.put(
            StoredWorkspace()..payload = mutation.$2,
          );
      }
    });
    final beforeRows = await rows(raw);
    check(await raw.close());
    final deadline = Stopwatch()..start();
    await rejects(
      open(),
      mutation.$1.endsWith('-version') ? 'INCOMPATIBLE' : 'STORAGE_BLOCKED',
    );
    check(deadline.elapsed < const Duration(seconds: 30));
    final preserved = await nativeOpen();
    check(await rows(preserved) == beforeRows);
    final payload = switch (mutation.$1) {
      'profile' => (await preserved.storedProfiles.get(profile.id))!.payload,
      'credential' || 'credential-version' =>
        (await preserved.storedCredentials.get(credential.id))!.payload,
      _ => (await preserved.storedWorkspaces.get(1))!.payload,
    };
    check(payload == mutation.$2);
    await preserved.writeTxn(() async {
      await preserved.storedProfiles.put(profile);
      await preserved.storedCredentials.put(credential);
      await preserved.storedWorkspaces.put(workspace);
    });
    check(await preserved.close());
    final restored = await open();
    check(restored.state.storeRevision == '2');
    check(await rows(Isar.getInstance('workspace')!) == baselineRows);
    await restored.close();
  }
  final extra = await nativeOpen();
  await extra.writeTxn(() async {
    final settings = (await extra.storedSettings.get(1))!;
    await extra.storedSettings.put(
      StoredSettings()
        ..id = 2
        ..payload = settings.payload,
    );
  });
  check(await extra.close());
  await rejects(open(), 'STORAGE_BLOCKED');
  final singletonRecovery = await nativeOpen();
  check(await singletonRecovery.storedSettings.count() == 2);
  await singletonRecovery.writeTxn(() async {
    check(await singletonRecovery.storedSettings.delete(2));
  });
  check(await singletonRecovery.close());
  final restoredSingleton = await open();
  check(restoredSingleton.state.storeRevision == '2');
  await restoredSingleton.close();
  stdout.writeln('CREDENTIAL_AND_WORKSPACE_STARTUP_MATRIX_PROVED');
  stdout.writeln('STARTUP_DAMAGE_FAIL_CLOSED_PROVED');
}

Future<void> main(List<String> arguments) async {
  final root = arguments[0], bundle = arguments[1], sid = currentUserSid();
  final hash = await Sha256().hash(utf8.encode('synthetic-repository-$root'));
  final name =
      'Global\\ServerDeckNext.v1.${hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  final lease = await MutexLease.acquire(name, sid);
  stdout.writeln('LEASE_ACQUIRED');
  check(lease.isHeld);
  final custody = KeyCustody(DpapiProtection(), sid);
  final key = await custody.createReceiptKey(
    fixture.workspace,
    fixture.receiptKeyId,
  );
  StateStore? store;
  Isar? native;
  final failedOpenMode =
      arguments.length > 2 && arguments[2] == 'open-close-failure';
  final directory = failedOpenMode
      ? p.join(root, 'ServerDeckNext', 'v1', 'workspaces', 'default')
      : p.join(root, 'workspace');
  try {
    await initializeNativeRuntime(bundle);
    stdout.writeln('BUNDLE_VERIFIED');
    if (failedOpenMode) {
      for (final path in [
        p.join(root, 'ServerDeckNext'),
        p.join(root, 'ServerDeckNext', 'v1'),
        p.dirname(directory),
      ]) {
        createProtectedDirectory(root, path, sid);
      }
    }
    createProtectedDirectory(root, directory, sid);
    await writeNewProtectedFile(
      root,
      p.join(directory, 'workspace.manifest.json'),
      sid,
      utf8.encode(jsonEncode(await custody.createWorkspaceManifest(key))),
    );
    await writeNewProtectedFile(
      root,
      p.join(directory, 'receipt-key.dpapi'),
      sid,
      key.wrapper,
    );
    for (final name in ['workspace.isar', 'workspace.isar-lck'])
      await createProtectedEmptyFile(root, p.join(directory, name), sid);
    native = await Isar.open(
      workspaceSchemas,
      directory: directory,
      name: 'workspace',
      maxSizeMiB: 64,
      relaxedDurability: false,
      inspector: false,
    );
    final empty = WorkspaceState.empty(
      workspaceId: fixture.workspace,
      receiptKeyId: fixture.receiptKeyId,
      ownerSid: sid,
    );
    final rows = WorkspaceRecords.fromState(empty), initial = native;
    await initial.writeTxn(() async {
      await initial.storedWorkspaces.put(rows.workspace);
      await initial.storedSettings.put(rows.settings);
    });
    await native.close();
    native = null;
    stdout.writeln('INITIAL_FIXTURE_DURABLE');
    Future<StateStore> open() => StateStore.open(
      localAppData: root,
      directory: directory,
      appRoot: bundle,
      lease: lease,
      custody: custody,
      receiptKey: key,
    );
    final firstOpen = open();
    final concurrentOpen = open();
    await rejects(concurrentOpen, 'STORAGE_BLOCKED');
    store = await firstOpen;
    stdout.writeln('REPOSITORY_OPENED');
    check(store.state.isInitialEmpty);
    await rejects(open(), 'STORAGE_BLOCKED');
    check(store.state.isInitialEmpty);
    if (arguments.length > 2 && arguments[2] == 'lifecycle') {
      await store.close();
      store = null;
      await verifyCredentialSnapshots(open, custody);
      stdout.writeln('CREDENTIAL_SNAPSHOTS_PASSED');
      return;
    }
    if (arguments.length > 2 && arguments[2] == 'mutations') {
      await verifyMutations(store, custody, key, open);
      store = null;
      stdout.writeln('MUTATIONS_PASSED');
      return;
    }
    if (arguments.length > 2 && arguments[2] == 'service-lifecycle') {
      await verifyServiceLifecycle(
        store,
        custody,
        key,
        lease,
        name,
        root,
        directory,
        bundle,
      );
      store = null;
      stdout.writeln('SERVICE_LIFECYCLE_PASSED');
      return;
    }
    if (arguments.length > 2 && arguments[2] == 'api') {
      await verifyApi(store, custody, key);
      store = null;
      stdout.writeln('ROUTER_METHODS_PASSED');
      return;
    }
    if (arguments.length > 2 && arguments[2] == 'channel') {
      await verifyChannel(store, custody, key);
      store = null;
      stdout.writeln('CHANNEL_PASSED');
      return;
    }
    if (arguments.length > 2 && arguments[2].startsWith('mutation-')) {
      await verifyMutationBoundaries(store, custody, key, open, arguments[2]);
      store = null;
      stdout.writeln('MUTATION_BOUNDARIES_PASSED');
      return;
    }
    final blob = await custody.wrapCredential(
      fixture.workspace,
      fixture.profileId,
      fixture.credentialId,
      {
        'action': 'replace',
        'kind': 'password',
        'password': 'synthetic-repository-password',
      },
    );
    final populated = credentialFixture.state(sid, blob);
    await store.commit(populated);
    stdout.writeln('FIRST_COMMIT');
    if (arguments.length > 2 && arguments[2] == 'open-close-failure') {
      await store.close();
      store = null;
      await verifyOpenCloseFailure(root, bundle, directory, lease, sid);
      stdout.writeln('FAILED_OPEN_RETAINS_MUTEX_PROVED');
      return;
    }
    final firstId = (await Isar.getInstance(
      'workspace',
    )!.storedProfiles.where().findFirst())!.id;
    final changed = populated.toJson();
    changed['storeRevision'] = '2';
    (changed['profiles'] as Map)[fixture.profileId] = {
      ...(changed['profiles'] as Map)[fixture.profileId]
          as Map<String, Object?>,
      'revision': '2',
      'name': 'Changed',
    };
    const request2 = '12345678-1234-4234-8234-123456789ab1';
    (changed['receipts'] as Map)[request2] = {
      ...fixture.receipt(),
      'requestId': request2,
      'operation': 'profiles.update',
      'result': {
        'entityId': fixture.profileId,
        'entityRevision': '2',
        'storeRevision': '2',
        'deleted': false,
      },
    };
    final next = WorkspaceState.fromJson(
      changed,
      workspaceId: fixture.workspace,
      receiptKeyId: fixture.receiptKeyId,
      ownerSid: sid,
    );
    await store.commit(next);
    stdout.writeln('SECOND_COMMIT');
    check(
      (await Isar.getInstance(
            'workspace',
          )!.storedProfiles.where().findFirst())!.id ==
          firstId,
    );
    check(store.state.storeRevision == '2');
    await rejects(store.commit(populated));
    check(store.state.storeRevision == '2');
    await Future.wait([store.close(), store.close()]);
    store = null;
    store = await open();
    check(
      base64.encode(StrictCodec().canonical(store.state.toJson())) ==
          base64.encode(StrictCodec().canonical(next.toJson())),
    );
    await store.close();
    store = null;
    final manifestFile = File(p.join(directory, 'workspace.manifest.json'));
    final original = manifestFile.readAsBytesSync();
    final altered = jsonDecode(utf8.decode(original)) as Map<String, Object?>;
    altered['schema'] = 2;
    await replaceProtectedFile(
      root,
      manifestFile.path,
      sid,
      utf8.encode(jsonEncode(altered)),
    );
    final dbFile = File(p.join(directory, 'workspace.isar')),
        before = dbFile.readAsBytesSync();
    await rejects(open(), 'INCOMPATIBLE');
    check(base64.encode(dbFile.readAsBytesSync()) == base64.encode(before));
    await replaceProtectedFile(root, manifestFile.path, sid, original);
    Future<Isar> nativeOpen() => Isar.open(
      workspaceSchemas,
      directory: directory,
      name: 'workspace',
      maxSizeMiB: 64,
      relaxedDurability: false,
      inspector: false,
    );
    await startupDamage(open, nativeOpen, custody);
    store = await open();
    check(store.state.storeRevision == '2');
    await mapFull(store, custody);
    final afterCapacity = store.state;
    await store.close();
    store = null;
    // Exhaust the real native allocator without inventing invalid business rows.
    native = await Isar.open(
      workspaceSchemas,
      directory: directory,
      name: 'workspace',
      maxSizeMiB: 64,
      relaxedDurability: false,
      inspector: false,
    );
    final allocatorFixture = native;
    await allocatorFixture.writeTxn(() async {
      final row = (await allocatorFixture.storedProfiles.where().findFirst())!;
      await allocatorFixture.storedProfiles.delete(row.id);
      row.id = 9223372036854775807;
      await allocatorFixture.storedProfiles.put(row);
    });
    check(await native.close());
    native = null;
    store = await open();
    const profile2 = '12345678-1234-4234-8234-123456789ac1';
    const request3 = '12345678-1234-4234-8234-123456789ac2';
    final overflow = store.state.toJson()
      ..['storeRevision'] = nextRevision(store.state.storeRevision);
    (overflow['profiles'] as Map)[profile2] = {
      ...fixture.profile(),
      'id': profile2,
    };
    (overflow['receipts'] as Map)[request3] = {
      ...fixture.receipt(),
      'requestId': request3,
      'profileId': profile2,
      'result': {
        'entityId': profile2,
        'entityRevision': '1',
        'storeRevision': overflow['storeRevision'],
        'deleted': false,
      },
    };
    final exhausted = WorkspaceState.fromJson(
      overflow,
      workspaceId: fixture.workspace,
      receiptKeyId: fixture.receiptKeyId,
      ownerSid: sid,
    );
    await rejects(store.commit(exhausted), 'RESOURCE_LIMIT');
    check(store.state.storeRevision == afterCapacity.storeRevision);
    check(!store.state.profiles.containsKey(profile2));
    check(!store.state.receipts.containsKey(request3));
    await store.close();
    store = null;
    store = await open();
    check(
      base64.encode(StrictCodec().canonical(store.state.toJson())) ==
          base64.encode(StrictCodec().canonical(afterCapacity.toJson())),
    );
    await store.close();
    store = null;
    stdout.writeln('NATIVE_ALLOCATOR_ROLLBACK_PROVED');
    await lease.close();
    check(!lease.isHeld);
    await rejects(open(), 'STORAGE_BLOCKED');
    stdout.writeln('REPOSITORY_NATIVE_CHECKS_PASSED');
  } finally {
    await store?.close();
    await native?.close();
    key.close();
    await lease.close();
  }
}
