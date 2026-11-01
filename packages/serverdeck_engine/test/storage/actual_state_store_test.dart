import 'package:path/path.dart' as p;
import 'package:serverdeck_engine/automation/authority_commands.dart';
import 'package:serverdeck_engine/automation/profile_commands.dart';
import 'package:serverdeck_engine/mcp/grants.dart';
import 'package:serverdeck_engine/profiles/mutation_coordinator.dart';
import 'package:serverdeck_engine/storage/state_store.dart';
import 'package:serverdeck_engine/storage/workspace_rows.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:test/test.dart';

import '../automation/portable_program_test.dart' show motdBody;
import '../support/memory_workspace_provider.dart';
import '../support/memory_workspace_storage.dart';
import '../support/schema3_fixture.dart' as fixture;
import 'store_preopen_test.dart' show Runtime;
import 'workspace_snapshot_test.dart' as snapshot;

String id(int n) =>
    '12345678-1234-4234-9234-12345678b${n.toRadixString(16).padLeft(3, '0')}';
DateTime now() => DateTime.parse('2026-10-30T10:00:02.000Z');
Matcher failure(String code) =>
    throwsA(isA<StateError>().having((e) => e.message, 'safe code', code));

final class Setup {
  Setup(this.source, this.provider);
  final snapshot.Setup source;
  final MemoryWorkspaceProvider provider;
  final runtime = Runtime();
  String get database => p.join(source.source.directory, 'workspace.isar');

  static Future<Setup> create({bool populated = true}) async {
    final source = await snapshot.Setup.create(populated: populated);
    final directory = source.source.directory;
    final database = p.join(directory, 'workspace.isar');
    source.files.data[database] = MemoryWorkspaceProvider.encode(
      source.source.data,
    );
    source.files.data[p.join(
      directory,
      'workspace.manifest.json',
    )] = StrictCodec().encode(
      await source.custody.createWorkspaceManifest(source.key),
      maxBytes: 4096,
    );
    source.files.data[p.join(directory, 'receipt-key.dpapi')] = List.of(
      source.key.wrapper,
    );
    final provider = MemoryWorkspaceProvider(
      readBytes: () => List.of(source.files.data[database]!),
      persistBytes: (bytes) => source.files.data[database] = List.of(bytes),
    );
    return Setup(source, provider);
  }

  Future<StateStore> open() async {
    final store = await StateStore.open(
      files: source.files,
      runtime: runtime,
      lease: source.lease,
      custody: source.custody,
      receiptKey: source.key,
      storageProvider: provider,
    );
    addTearDown(store.close);
    return store;
  }

  MutationCoordinator coordinator(StateStore store) {
    final coordinator = MutationCoordinator(
      store,
      source.custody,
      source.key,
      clock: now,
    );
    addTearDown(coordinator.close);
    return coordinator;
  }
}

Map<String, Object?> settings() => {
  'expectedRevision': '1',
  'theme': 'light',
  'reduceMotion': false,
  'selectedProfileId': fixture.profile,
};

AutomationProfileCommand createProfile(int request) =>
    AutomationProfileCommand.parse('profile.create', {
      'requestId': id(request),
      'name': 'RAM actual profile',
      'body': motdBody(),
    });

Future<Map<String, Object?>> profile(
  StateStore store,
  AutomationProfileCommand command,
) => store.mutateAutomationProfile(
  command,
  originGrantId: null,
  expectedGrantRevision: null,
  clock: now,
);

OwnerGrantCommand createGrant(int request, String grant) =>
    OwnerGrantCommand.parse('grant.create', {
      'requestId': id(request),
      'grantId': grant,
      'label': 'RAM actual grant',
      'scopes': ['read', 'author', 'plan', 'apply'],
      'serverIds': [fixture.profile],
      'lifetimeSeconds': 3600,
    });

Map<String, Object?> rawRows(StateStore store) => {
  for (final e in store.snapshot.rows.entries)
    e.key: [for (final r in e.value) (r.nativeId, r.entityId, r.payload)],
};

void main() {
  tearDown(() => expect(StateStore.hasOpenReservation, isFalse));

  test(
    'checked actual open preserves16 row families, custody and sole writer',
    () async {
      final setup = await Setup.create();
      final store = await setup.open();
      expect(store.isReady, isTrue);
      expect(store.snapshot.rows.keys, hasLength(16));
      for (final entry in setup.source.source.data.entries) {
        final expected =
            entry.value.map((r) => (r.nativeId, r.entityId, r.payload)).toList()
              ..sort((a, b) => a.$1.compareTo(b.$1));
        expect(rawRows(store)[entry.key], expected);
      }
      store.assertAutomationCustody(setup.source.custody, setup.source.key);
      expect((setup.provider.preflights, setup.provider.opens), (1, 1));
      expect(await store.readExecutorEnrollments(), isEmpty);
      await expectLater(setup.open(), failure('STORAGE_BLOCKED'));
      expect(setup.provider.opens, 1);
      expect(setup.source.lease.closes, 0);
      await store.close();
      expect(setup.provider.hasOpenInstance, isFalse);
      expect(setup.provider.lastOpened!.closeCalls, 1);
      expect(StateStore.hasOpenReservation, isFalse);
    },
  );

  test(
    'captured RAM bytes are decoded and invalid bytes never open storage',
    () async {
      final setup = await Setup.create();
      setup.source.files.data[setup.database] = [0];
      await expectLater(setup.open(), failure('STORAGE_BLOCKED'));
      expect((setup.provider.preflights, setup.provider.opens), (1, 0));
      expect(setup.source.files.data[setup.database], [0]);
      expect(setup.source.lease.closes, 0);
    },
  );

  test(
    'changed exact payload after preflight closes before lookup publication',
    () async {
      final setup = await Setup.create();
      setup.provider.beforeOpen = () {
        final rows = {
          ...MemoryWorkspaceProvider.decode(
            setup.source.files.data[setup.database]!,
          ),
        };
        final old = rows['StoredProfile']!.single;
        rows['StoredProfile'] = [
          StoredRow(old.nativeId, '${old.payload} ', entityId: old.entityId),
        ];
        setup.source.files.data[setup.database] =
            MemoryWorkspaceProvider.encode(rows);
      };
      await expectLater(setup.open(), failure('STORAGE_BLOCKED'));
      expect((setup.provider.opens, setup.provider.cleanups), (1, 1));
      expect(setup.provider.lastOpened!.closeCalls, 1);
      expect(
        await setup.source.artifacts.readLookupForRecovery(fixture.grant),
        isNull,
      );
      expect(setup.source.lease.closes, 0);
    },
  );

  test(
    'actual coordinator settings commit stores real HMAC receipt and replay',
    () async {
      final setup = await Setup.create();
      final store = await setup.open(), coordinator = setup.coordinator(store);
      final before = rawRows(store), input = settings();
      final result = await coordinator.submit(
        id(1),
        ApiMethod.settingsUpdate,
        input,
        requester: 'unit-owner',
      );
      expect(result.storeRevision, '3');
      expect(store.state.settings.revision, '2');
      expect(
        store.state.receipts[id(1)]!.inputDigest,
        setup.source.custody.receiptDigestSync(setup.source.key, {
          'operation': 'settings.update',
          'params': input,
        }),
      );
      for (final family in [
        'StoredProfile',
        'StoredCredential',
        'StoredHostTrust',
        'StoredMcpGrant',
      ]) {
        expect(rawRows(store)[family], before[family]);
      }
      final replay = await coordinator.submit(
        id(1),
        ApiMethod.settingsUpdate,
        input,
        requester: 'unit-owner',
      );
      expect(replay.toJson(), result.toJson());
      expect(setup.provider.lastOpened!.commits, 1);
      expect(store.snapshot.rows['StoredReceipt']!.last.nativeId, 102);
      await expectLater(
        coordinator.submit(id(1), ApiMethod.settingsUpdate, {
          ...input,
          'theme': 'dark',
        }, requester: 'unit-owner'),
        failure('IDEMPOTENCY_CONFLICT'),
      );
    },
  );

  test(
    'actual profile create/update/archive retains IDs and checks CAS/replay',
    () async {
      final setup = await Setup.create();
      final store = await setup.open(), command = createProfile(2);
      final created = await profile(store, command);
      final profileId = created['profileId'] as String;
      final nativeId =
          store.snapshot.rows['StoredAutomationProfile']!.single.nativeId;
      expect(await profile(store, command), created);
      expect(setup.provider.lastOpened!.commits, 1);
      final updated = await profile(
        store,
        AutomationProfileCommand.parse('profile.update', {
          'requestId': id(3),
          'profileId': profileId,
          'expectedRevision': 1,
          'body': motdBody(),
          'name': 'updated',
        }),
      );
      expect(updated['revision'], 2);
      expect(store.snapshot.automation.revisions, hasLength(2));
      expect(
        store.snapshot.rows['StoredAutomationProfile']!.single.nativeId,
        nativeId,
      );
      await expectLater(
        profile(
          store,
          AutomationProfileCommand.parse('profile.archive', {
            'requestId': id(4),
            'profileId': profileId,
            'expectedRevision': 1,
          }),
        ),
        failure('REVISION_CONFLICT'),
      );
      await profile(
        store,
        AutomationProfileCommand.parse('profile.archive', {
          'requestId': id(5),
          'profileId': profileId,
          'expectedRevision': 2,
        }),
      );
      expect(store.snapshot.automation.profiles[profileId]!.archived, isTrue);
      expect(store.snapshot.automation.revisions, hasLength(2));
      expect(
        store.snapshot.automation.receipts[id(5)]!.result['archived'],
        isTrue,
      );
      expect(setup.provider.lastOpened!.commits, 3);
    },
  );

  test(
    'current read-only grant cannot author before row write admission',
    () async {
      final setup = await Setup.create(), command = createProfile(6);
      final store = await setup.open(), before = rawRows(store);
      await expectLater(
        store.mutateAutomationProfile(
          command,
          originGrantId: fixture.grant,
          expectedGrantRevision: 1,
          clock: now,
        ),
        failure('FORBIDDEN'),
      );
      expect(rawRows(store), before);
      expect(setup.provider.lastOpened!.commits, 0);
      expect(store.isReady, isTrue);
    },
  );

  test(
    'grant publication waits for real commit and revoke retires actual key',
    () async {
      final setup = await Setup.create();
      final store = await setup.open();
      final publications = <(String, int)>[];
      final remove = store.onMcpGrantPublished((grant, revision) {
        expect(store.hasPendingMcpAuthorityPublication, isTrue);
        expect(store.isReady, isFalse);
        expect(setup.provider.lastOpened!.commits, publications.length + 1);
        publications.add((grant, revision));
      });
      addTearDown(remove);
      await store.mutateOwnerGrant(createGrant(7, id(20)), clock: now);
      final opened = await store.openMcpGrantKey(id(20), clock: now);
      expect(opened.grant.id, id(20));
      opened.close();
      await store.mutateOwnerGrant(
        OwnerGrantCommand.parse('grant.revoke', {
          'requestId': id(8),
          'grantId': id(20),
          'expectedRevision': 1,
        }),
        clock: now,
      );
      expect(publications, [(id(20), 1), (id(20), 2)]);
      await expectLater(
        store.openMcpGrantKey(id(20), clock: now),
        failure('UNAUTHORIZED'),
      );
      expect(store.snapshot.automation.grants[id(20)]!.revokedAt, now());
      expect(
        store.snapshot.automation.receipts[id(8)]!.operation,
        'grant.revoke',
      );
    },
  );

  test(
    'actual trusted delta creates/revokes delegation with receipt readback',
    () async {
      final setup = await Setup.create();
      final store = await setup.open();
      final created = await profile(store, createProfile(9));
      final revision =
          store.snapshot.automation.revisions['${created['profileId']}:1']!;
      await store.mutateOwnerGrant(createGrant(10, id(21)), clock: now);
      final result = await store.mutateTrustedAuthority(
        AutomationAuthorityCommand.parse('delegation.create', {
          'requestId': id(11),
          'grantId': id(21),
          'serverIds': [fixture.profile],
          'profileRevisions': [revision.key.toJson()],
          'predicates': {
            'message': {
              'type': 'enum',
              'values': ['hello'],
            },
          },
          'lifetimeSeconds': 300,
        }),
        originGrantId: null,
        expectedGrantRevision: null,
        clock: now,
      );
      final delegationId = result['delegationId'] as String;
      final nativeId = store.snapshot.rows['StoredDelegation']!.single.nativeId;
      await store.mutateTrustedAuthority(
        AutomationAuthorityCommand.parse('delegation.revoke', {
          'requestId': id(12),
          'delegationId': delegationId,
          'expectedRevision': 1,
        }),
        originGrantId: null,
        expectedGrantRevision: null,
        clock: now,
      );
      expect(
        store.snapshot.automation.delegations[delegationId]!.revokedAt,
        now(),
      );
      expect(
        store.snapshot.rows['StoredDelegation']!.single.nativeId,
        nativeId,
      );
      expect(
        store.snapshot.automation.receipts[id(12)]!.operation,
        'delegation.revoke',
      );
      expect(setup.provider.lastOpened!.commits, 4);
    },
  );

  test(
    'capacity returns RESOURCE_LIMIT only after actual prior graph readback',
    () async {
      final setup = await Setup.create();
      final store = await setup.open(), before = rawRows(store);
      setup.provider.lastOpened!.nextPutFailure = MemoryCapacityFailure();
      await expectLater(
        setup
            .coordinator(store)
            .submit(
              id(13),
              ApiMethod.settingsUpdate,
              settings(),
              requester: 'unit-owner',
            ),
        failure('RESOURCE_LIMIT'),
      );
      expect(rawRows(store), before);
      expect(store.isReady, isTrue);
      expect(setup.provider.lastOpened!.commits, 0);
    },
  );

  test(
    'failed post-commit runtime proof blocks instead of claiming rollback',
    () async {
      final setup = await Setup.create();
      final store = await setup.open();
      setup.provider.afterCommit = () =>
          setup.runtime.failValidation = setup.runtime.validations + 1;
      await expectLater(
        setup
            .coordinator(store)
            .submit(
              id(14),
              ApiMethod.settingsUpdate,
              settings(),
              requester: 'unit-owner',
            ),
        failure('STORAGE_BLOCKED'),
      );
      expect(store.isReady, isFalse);
      expect(() => store.snapshot, throwsStateError);
      expect(setup.provider.lastOpened!.commits, 1);
      expect(StateStore.hasOpenReservation, isTrue);
      await store.close();
      setup.provider.afterCommit = null;
      setup.runtime.failValidation = null;
      final reopened = await setup.open();
      expect(reopened.state.storeRevision, '3');
      expect(reopened.state.receipts.containsKey(id(14)), isTrue);
    },
  );
}
