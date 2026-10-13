import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:serverdeck_locald/profiles/mutation_coordinator.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/models.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/models.dart';

import '../models_test.dart' as fixture;
import 'mutations.dart' show GateProtection;
import 'state_store_child.dart' show check, rejects;

Future<void> verifyMutationBoundaries(
  StateStore initial,
  KeyCustody custody,
  ReceiptKeyMaterial key,
  Future<StateStore> Function() open,
  String mode,
) async {
  StateStore? store = initial;
  var coordinator = MutationCoordinator(initial, custody, key);
  var counter = 0;
  String request() =>
      '82345678-1234-4234-8234-${(++counter).toRadixString(16).padLeft(12, '0')}';
  String profileId(int index) =>
      '92345678-1234-4234-8234-${index.toRadixString(16).padLeft(12, '0')}';
  Map<String, Object?> create(int index) => {
    'profileId': profileId(index),
    'name': 'Synthetic $index',
    'address': 'example.invalid',
    'sshUser': 'synthetic',
  };
  Map<String, Object?> update() {
    final p = store!.state.profiles[profileId(1)]!.toJson();
    return {
      'profileId': p['id'],
      'expectedRevision': p['revision'],
      for (final field in ['name', 'address', 'port', 'sshUser', 'tags'])
        field: p[field],
      'credential': {'action': 'keep'},
    };
  }

  Future<MutationResult> submit(
    String id,
    ApiMethod method,
    Map<String, Object?> input,
  ) => coordinator.submit(id, method, input, requester: 'owned');
  final codec = StrictCodec();
  String snapshot() => base64.encode(codec.canonical(store!.state.toJson()));
  try {
    if (mode == 'mutation-native-failure') {
      check(await Isar.getInstance('workspace')!.close());
      final id = request();
      await rejects(
        submit(id, ApiMethod.profilesCreate, create(1)),
        'STORAGE_BLOCKED',
      );
      await rejects(
        Future.sync(() => coordinator.status(id)),
        'STORAGE_BLOCKED',
      );
      await rejects(
        submit(id, ApiMethod.profilesCreate, create(1)),
        'STORAGE_BLOCKED',
      );
      await coordinator.close();
      await rejects(store.close(), 'STORAGE_BLOCKED');
      store =
          null; // Already-closed native instance: reserved until this VM exits.
      stdout.writeln('COORDINATOR_UNKNOWN_NATIVE_BLOCKED');
      return;
    }
    await submit(request(), ApiMethod.profilesCreate, create(1));
    if (mode == 'mutation-allocation') {
      final native = Isar.getInstance('workspace')!;
      await native.writeTxn(() async {
        final row = (await native.storedProfiles.where().findFirst())!;
        await native.storedProfiles.delete(row.id);
        row.id = 9223372036854775807;
        await native.storedProfiles.put(row);
      });
      final before = snapshot(), id = request();
      await rejects(
        submit(id, ApiMethod.profilesCreate, create(2)),
        'RESOURCE_LIMIT',
      );
      check(
        snapshot() == before &&
            coordinator.status(id).state == MutationState.notFound,
      );
      check(coordinator.listProfiles().profiles.length == 1);
      await coordinator.close();
      await store.close();
      store = null;
      store = await open();
      coordinator = MutationCoordinator(store, custody, key);
      check(
        snapshot() == before &&
            coordinator.status(id).state == MutationState.notFound,
      );
      stdout.writeln('COORDINATOR_NATIVE_ID_ROLLBACK');
      return;
    }
    for (var i = 2; i <= 250; i++)
      await submit(request(), ApiMethod.profilesCreate, create(i));
    final fullProfiles = snapshot(), profileOverflow = request();
    await rejects(
      submit(profileOverflow, ApiMethod.profilesCreate, create(251)),
      'RESOURCE_LIMIT',
    );
    check(
      snapshot() == fullProfiles &&
          coordinator.listProfiles().profiles.length == 250,
    );
    check(coordinator.status(profileOverflow).state == MutationState.notFound);
    for (final (revision, code) in [
      ('9223372036854775807', 'REVISION_CONFLICT'),
      ('9223372036854775808', 'VALIDATION'),
    ]) {
      final id = request();
      await rejects(
        submit(id, ApiMethod.profilesUpdate, {
          ...update(),
          'expectedRevision': revision,
        }),
        code,
      );
      check(
        snapshot() == fullProfiles &&
            coordinator.status(id).state == MutationState.notFound,
      );
    }
    check(nextRevision('9223372036854775806') == '9223372036854775807');
    var exhausted = false;
    try {
      nextRevision('9223372036854775807');
    } on StateError catch (e) {
      exhausted = e.message == 'RESOURCE_LIMIT';
    }
    check(exhausted);

    await coordinator.close();
    final gate = GateProtection(custody.protection)
      ..reached = Completer<void>()
      ..release = Completer<void>();
    coordinator = MutationCoordinator(
      store,
      KeyCustody(gate, custody.ownerSid),
      key,
    );
    final runningId = request();
    final input = {
      ...update(),
      'credential': {
        'action': 'replace',
        'kind': 'password',
        'password': 'synthetic-shutdown',
      },
    };
    final running = submit(runningId, ApiMethod.profilesUpdate, input);
    await gate.reached!.future.timeout(const Duration(seconds: 5));
    final duplicate = submit(runningId, ApiMethod.profilesUpdate, input);
    final queuedId = request();
    final queued = rejects(
      submit(queuedId, ApiMethod.settingsUpdate, {
        'expectedRevision': '1',
        'theme': 'dark',
        'reduceMotion': true,
        'selectedProfileId': null,
      }),
      'SERVICE_UNAVAILABLE',
    );
    var closed = false;
    final close = coordinator.close();
    check(identical(close, coordinator.close()));
    unawaited(close.then((_) => closed = true));
    await queued;
    check(!closed);
    await rejects(
      submit(request(), ApiMethod.profilesCreate, create(251)),
      'NOT_READY',
    );
    gate.release!.complete();
    await Future.wait([running, duplicate]);
    await close;
    check(
      closed &&
          store.state.receipts.containsKey(runningId) &&
          !store.state.receipts.containsKey(queuedId),
    );
    check(store.state.settings.revision == '1');
    coordinator = MutationCoordinator(store, custody, key);
    check(coordinator.status(queuedId).state == MutationState.notFound);
    stdout.writeln('COORDINATOR_SHUTDOWN_DRAINED');

    final native = Isar.getInstance('workspace')!;
    final pinned = Completer<void>(), release = Completer<void>();
    final reader = native.txn(() async {
      await native.storedWorkspaces.get(1);
      pinned.complete();
      await release.future;
    });
    await pinned.future;
    var mapFull = false;
    const passphrase = ' e\u0301 synthetic-passphrase ';
    final pem =
        '-----BEGIN PRIVATE KEY-----\r\n${'QUFB' * 16300}\r\n-----END PRIVATE KEY-----\r\n';
    try {
      for (var i = 0; i < 1200; i++) {
        final before = snapshot(), id = request();
        try {
          await submit(id, ApiMethod.profilesUpdate, {
            ...update(),
            'credential': {
              'action': 'replace',
              'kind': 'privateKey',
              'privateKey': pem,
              'passphrase': passphrase,
            },
          });
        } on StateError catch (error) {
          check(error.message == 'RESOURCE_LIMIT');
          check(
            snapshot() == before &&
                coordinator.status(id).state == MutationState.notFound,
          );
          coordinator.listProfiles();
          coordinator.recent();
          mapFull = true;
          break;
        }
      }
      check(mapFull);
    } finally {
      release.complete();
      await reader;
    }
    final credential = store.state.credentials.values.single;
    final secret = await custody.openCredential(
      credential.protectedBlob,
      fixture.workspace,
      profileId(1),
      credential.id,
    );
    check(secret['privateKey'] == pem && secret['passphrase'] == passphrase);
    secret.clear();
    stdout.writeln('COORDINATOR_MAP_FULL_ROLLBACK');
    final durable = snapshot();
    await coordinator.close();
    await store.close();
    store = null;
    store = await open();
    coordinator = MutationCoordinator(store, custody, key);
    check(snapshot() == durable);

    // Owned fixture baseline: 10,000 valid stored receipts, not a claim of
    // executing 10,000 coordinator operations. Reopen validates the whole state.
    await coordinator.close();
    final empty = WorkspaceState.empty(
      workspaceId: fixture.workspace,
      receiptKeyId: fixture.receiptKeyId,
      ownerSid: custody.ownerSid,
    ).toJson();
    empty['storeRevision'] = '10000';
    empty['settings'] = {
      'revision': '10001',
      'theme': 'system',
      'reduceMotion': false,
      'selectedProfileId': null,
    };
    final receipts = <String, Object?>{};
    Map<String, Object?> historical(int index) => {
      'expectedRevision': index.toString(),
      'theme': 'system',
      'reduceMotion': false,
      'selectedProfileId': null,
    };
    String historicalId(int index) =>
        'a2345678-1234-4234-8234-${index.toRadixString(16).padLeft(12, '0')}';
    for (var i = 1; i <= 10000; i++) {
      receipts[historicalId(i)] = {
        'requestId': historicalId(i),
        'inputDigest': i == 1
            ? custody.receiptDigestSync(key, {
                'operation': 'settings.update',
                'params': historical(i),
              })
            : base64.encode(List.filled(32, 0)),
        'operation': 'settings.update',
        'profileId': null,
        'result': {
          'entityId': null,
          'entityRevision': (i + 1).toString(),
          'storeRevision': i.toString(),
          'deleted': false,
        },
        'committedAt': fixture.time,
      };
    }
    empty['receipts'] = receipts;
    final baseline = WorkspaceState.fromJson(
      empty,
      workspaceId: fixture.workspace,
      receiptKeyId: fixture.receiptKeyId,
      ownerSid: custody.ownerSid,
    );
    final rows = WorkspaceRecords.fromState(baseline),
        live = Isar.getInstance('workspace')!;
    await live.writeTxn(() async {
      await live.storedProfiles.clear();
      await live.storedCredentials.clear();
      await live.storedReceipts.clear();
      await live.storedWorkspaces.put(rows.workspace);
      await live.storedSettings.put(rows.settings);
      await live.storedReceipts.putAll(rows.receipts);
    });
    await store.close();
    store = null;
    store = await open();
    coordinator = MutationCoordinator(store, custody, key);
    final before = snapshot(), quotaId = request();
    await rejects(
      submit(quotaId, ApiMethod.settingsUpdate, historical(10001)),
      'RESOURCE_LIMIT',
    );
    check(
      snapshot() == before &&
          coordinator.status(quotaId).state == MutationState.notFound,
    );
    check(
      coordinator.recent(limit: 100).receipts.length == 100 &&
          coordinator.getSettings().settings.revision == '10001',
    );
    check(
      (await submit(
            historicalId(1),
            ApiMethod.settingsUpdate,
            historical(1),
          )).storeRevision ==
          '1',
    );
    check(snapshot() == before && store.state.receipts.length == 10000);
    stdout.writeln('COORDINATOR_RECEIPT_QUOTA_PRESERVED');
  } finally {
    await coordinator.close();
    await store?.close();
  }
}
