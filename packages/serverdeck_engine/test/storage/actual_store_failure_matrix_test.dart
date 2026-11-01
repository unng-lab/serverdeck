import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:serverdeck_engine/mcp/grants.dart';
import 'package:serverdeck_engine/storage/state_store.dart';
import 'package:serverdeck_engine/storage/workspace_rows.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:test/test.dart';

import '../support/memory_workspace_provider.dart';
import '../support/memory_workspace_storage.dart';
import '../support/schema3_fixture.dart' as fixture;
import 'actual_state_store_test.dart' as actual;

void main() {
  tearDown(() => expect(StateStore.hasOpenReservation, isFalse));

  test(
    'grant replacement rotates secret and publishes current revision policy',
    () async {
      final setup = await actual.Setup.create(), store = await setup.open();
      final grantId = actual.id(650);
      await store.mutateOwnerGrant(
        actual.createGrant(651, grantId),
        clock: actual.now,
      );
      final old = store.currentMcpGrant(grantId, at: actual.now());
      await store.mutateOwnerGrant(
        OwnerGrantCommand.parse('grant.replace', {
          'requestId': actual.id(652),
          'grantId': grantId,
          'expectedRevision': 1,
          'label': 'replacement',
          'scopes': ['read'],
          'serverIds': [fixture.profile],
          'lifetimeSeconds': 3600,
        }),
        clock: actual.now,
      );
      final current = store.currentMcpGrant(grantId, at: actual.now());
      expect(current.revision, 2);
      expect(current.secretRef, isNot(old.secretRef));
      expect(current.toJson()['scopes'], ['read']);
      final key = await store.openMcpGrantKey(grantId, clock: actual.now);
      addTearDown(key.close);
      expect(key.grant.secretRef, current.secretRef);
      final before = actual.rawRows(store);
      await expectLater(
        store.mutateAutomationProfile(
          actual.createProfile(653),
          originGrantId: grantId,
          expectedGrantRevision: 1,
          clock: actual.now,
        ),
        actual.failure('FORBIDDEN'),
      );
      expect(actual.rawRows(store), before);
      expect(setup.provider.lastOpened!.commits, 2);
    },
  );

  test(
    'grant expires inside actual writer callback before any row put',
    () async {
      final setup = await actual.Setup.create(), store = await setup.open();
      final grantId = actual.id(654);
      await store.mutateOwnerGrant(
        actual.createGrant(655, grantId),
        clock: actual.now,
      );
      final before = actual.rawRows(store),
          storage = setup.provider.lastOpened!;
      final puts = storage.putCalls;
      var at = actual.now();
      storage.beforeWrite = () => at = at.add(const Duration(hours: 2));
      await expectLater(
        store.mutateAutomationProfile(
          actual.createProfile(656),
          originGrantId: grantId,
          expectedGrantRevision: 1,
          clock: () => at,
        ),
        actual.failure('FORBIDDEN'),
      );
      storage.beforeWrite = null;
      expect(storage.putCalls, puts);
      expect(storage.commits, 1);
      expect(actual.rawRows(store), before);
      expect(store.isReady, isTrue);
    },
  );

  test('foundation profile/credential/trust creation rotation and deletion use actual rows', () async {
    final setup = await actual.Setup.create(), store = await setup.open();
    final coordinator = setup.coordinator(store), profileId = actual.id(500);
    Map<String, Object?> fields(String password) => {
      'profileId': profileId,
      'name': 'unit additional host',
      'address': 'unit.invalid',
      'port': 22,
      'sshUser': 'unit_user',
      'tags': <String>[],
      'credential': {
        'action': 'replace',
        'kind': 'password',
        'password': password,
      },
    };
    await coordinator.submit(
      actual.id(501),
      ApiMethod.profilesCreate,
      fields('unit-one'),
      requester: 'unit-owner',
    );
    final first = store.state.profiles[profileId]!;
    final profileNative = store.snapshot.rows['StoredProfile']!
        .singleWhere((r) => r.entityId == profileId)
        .nativeId;
    expect(store.snapshot.foundation.trust.containsKey(profileId), isFalse);
    expect(store.state.credentials.containsKey(first.credentialRef), isTrue);
    await coordinator.submit(actual.id(502), ApiMethod.profilesUpdate, {
      ...fields('unit-two'),
      'expectedRevision': first.revision,
    }, requester: 'unit-owner');
    final updated = store.state.profiles[profileId]!;
    expect(updated.credentialRef, isNot(first.credentialRef));
    expect(store.state.credentials.containsKey(first.credentialRef), isFalse);
    expect(
      store.snapshot.rows['StoredProfile']!
          .singleWhere((r) => r.entityId == profileId)
          .nativeId,
      profileNative,
    );
    await coordinator.submit(actual.id(503), ApiMethod.profilesDelete, {
      'profileId': profileId,
      'expectedRevision': updated.revision,
    }, requester: 'unit-owner');
    expect(store.state.profiles.containsKey(profileId), isFalse);
    expect(store.snapshot.foundation.trust.containsKey(profileId), isFalse);
    expect(store.state.credentials.keys, [fixture.credential]);
    expect(store.state.receipts[actual.id(503)]!.result.deleted, isTrue);
    expect(store.snapshot.rows['StoredProfile']!.single.nativeId, 71);
    expect(store.snapshot.rows['StoredCredential']!.single.nativeId, 83);
    final original = store.state.profiles[fixture.profile]!;
    await coordinator.submit(actual.id(504), ApiMethod.profilesUpdate, {
      'profileId': fixture.profile,
      'expectedRevision': original.revision,
      'name': original.name,
      'address': 'changed-unit.invalid',
      'port': original.toJson()['port'],
      'sshUser': original.toJson()['sshUser'],
      'tags': original.toJson()['tags'],
      'credential': {'action': 'keep'},
    }, requester: 'unit-owner');
    expect(
      store.snapshot.foundation.trust[fixture.profile]!.toJson()['status'],
      'revoked',
    );
    expect(store.snapshot.rows['StoredHostTrust']!.single.nativeId, 97);
  });

  test('actual pending32 admission shares request and rejects33 without extra writer', () async {
    final setup = await actual.Setup.create(), store = await setup.open();
    final held = setup.provider.lastOpened!.holdPut = Completer<void>();
    final commands = [
      for (var i = 0; i < 32; i++) actual.createProfile(600 + i),
    ];
    final pending = [
      for (final command in commands) actual.profile(store, command),
    ];
    expect(actual.profile(store, commands.first), same(pending.first));
    await expectLater(
      actual.profile(store, actual.createProfile(632)),
      actual.failure('RESOURCE_LIMIT'),
    );
    expect(setup.provider.lastOpened!.commits, 0);
    expect(StateStore.hasOpenReservation, isTrue);
    held.complete();
    await Future.wait(pending);
    expect(store.snapshot.automation.profiles, hasLength(32));
    expect(setup.provider.lastOpened!.commits, 32);
    expect(
      store.snapshot.automation.receipts.containsKey(actual.id(632)),
      isFalse,
    );
  });

  test('capacity with failed prior-snapshot proof blocks instead of RESOURCE_LIMIT', () async {
    final setup = await actual.Setup.create(), store = await setup.open();
    final storage = setup.provider.lastOpened!;
    storage.nextPutFailure = MemoryCapacityFailure();
    storage.afterAbort = () =>
        storage.nextReadFailure = StateError('SYNTHETIC_READBACK_FAILURE');
    await expectLater(
      setup
          .coordinator(store)
          .submit(
            actual.id(640),
            ApiMethod.settingsUpdate,
            actual.settings(),
            requester: 'unit-owner',
          ),
      actual.failure('STORAGE_BLOCKED'),
    );
    expect(storage.commits, 0);
    expect(store.isReady, isFalse);
    expect(() => store.snapshot, throwsStateError);
    expect(StateStore.hasOpenReservation, isTrue);
    expect(setup.source.lease.closes, 0);
  });

  test(
    'actual close retains reservation and lease until admitted write drains',
    () async {
      final setup = await actual.Setup.create(), store = await setup.open();
      final hold = setup.provider.lastOpened!.holdPut = Completer<void>();
      final mutation = actual.profile(store, actual.createProfile(641));
      await Future<void>.delayed(Duration.zero);
      final closing = store.close();
      expect(StateStore.hasOpenReservation, isTrue);
      expect(setup.provider.lastOpened!.closeCalls, 0);
      expect(setup.source.lease.isHeld, isTrue);
      expect(setup.source.lease.closes, 0);
      hold.complete();
      await mutation;
      await closing;
      expect(setup.provider.lastOpened!.commits, 1);
      expect(setup.provider.lastOpened!.closeCalls, 1);
      expect(StateStore.hasOpenReservation, isFalse);
    },
  );

  test(
    'provably pre-owning failed open cleans once and permits checked retry',
    () async {
      final setup = await actual.Setup.create();
      setup.provider.openFailure = StateError('SYNTHETIC_PREOWNING_FAILURE');
      await expectLater(setup.open(), actual.failure('STORAGE_BLOCKED'));
      expect(setup.provider.cleanups, 1);
      expect(StateStore.hasOpenReservation, isFalse);
      expect(setup.source.lease.closes, 0);
      setup.provider.openFailure = null;
      final store = await setup.open();
      expect(store.isReady, isTrue);
      expect((setup.provider.preflights, setup.provider.opens), (2, 1));
    },
  );

  test(
    'target schema semantic faults never reach writable open or alter bytes',
    () async {
      for (final fault in ['schema', 'credential', 'key-wrapper']) {
        final setup = await actual.Setup.create();
        if (fault == 'key-wrapper') {
          setup.source.files.data[p.join(
            setup.source.source.directory,
            'receipt-key.dpapi',
          )] = [
            255,
          ];
        } else {
          final rows = {
            ...MemoryWorkspaceProvider.decode(
              setup.source.files.data[setup.database]!,
            ),
          };
          final family = fault == 'schema'
              ? 'StoredWorkspace'
              : 'StoredProfile';
          final row = rows[family]!.single;
          final json = StrictCodec().decode(utf8.encode(row.payload));
          json[fault == 'schema' ? 'schemaVersion' : 'credentialRef'] =
              fault == 'schema' ? 2 : actual.id(999);
          rows[family] = [
            StoredRow(row.nativeId, jsonEncode(json), entityId: row.entityId),
          ];
          setup.source.files.data[setup.database] =
              MemoryWorkspaceProvider.encode(rows);
        }
        final before = {
          for (final e in setup.source.files.data.entries)
            e.key: List<int>.of(e.value),
        };
        await expectLater(
          setup.open(),
          actual.failure(
            fault == 'schema' ? 'INCOMPATIBLE' : 'STORAGE_BLOCKED',
          ),
        );
        expect(setup.provider.opens, 0);
        expect(setup.source.files.data, before);
        expect(setup.source.lease.closes, 0);
      }
    },
  );
}
