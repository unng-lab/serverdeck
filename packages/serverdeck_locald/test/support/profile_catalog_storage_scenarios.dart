import 'dart:io';

import 'package:isar_community/isar.dart';

import 'package:serverdeck_locald/automation/profile_commands.dart';
import 'package:serverdeck_locald/mcp/grants.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_windows/mcp_credential_files.dart';

import '../automation/snapshot_test.dart' as g;
import 'operational_open_scenarios.dart' show refusal;
import 'operational_snapshot_child.dart' show check, sameJson;
import 'profile_catalog_quota_scenarios.dart';
import 'profile_catalog_failure_scenarios.dart';
import 'grant_transaction_scenarios.dart' show grantCreate;

const profileCatalogModes = {
  'catalog-basic',
  'catalog-trusted-refusal',
  'catalog-origin',
  'catalog-queue',
  'catalog-revisions',
  'catalog-cas-race',
  'catalog-mixed-queue',
  ...profileCatalogQuotaModes,
  ...profileCatalogFailureModes,
};
Map<String, Object?> catalogBody() => {
  'format': 1,
  'environment': 'ubuntu24.04-amd64-systemd',
  'parameters': <String, Object?>{},
  'steps': <Object?>[],
};
AutomationProfileCommand createCatalogCommand(int id) =>
    AutomationProfileCommand.parse('profile.create', {
      'requestId': g.id(id),
      'name': 'Synthetic catalog profile',
      'body': catalogBody(),
    });

Future<StateStore> verifyProfileCatalogStorage(
  StateStore store,
  Future<StateStore> Function() reopen,
  String mode,
  McpCredentialFiles files,
) async {
  final originalFoundation = store.state.toJson();
  final originalRows = store.operational.rows;
  final clock = () => DateTime.utc(2026, 10, 21, 12);
  Future<Map<String, Object?>> write(
    AutomationProfileCommand command, {
    String? origin,
    int? revision,
  }) => store.mutateAutomationProfile(
    command,
    originGrantId: origin,
    expectedGrantRevision: revision,
    clock: clock,
  );
  final command = createCatalogCommand(72000);
  if (mode == 'catalog-trusted-refusal') {
    final original = store.operational;
    await refusal(
      () => store.mutateTrustedOwnerGrant(
        OwnerGrantCommand.parse('grant.create', grantCreate(78000, 78001)),
        clock: clock,
      ),
      'STORAGE_BLOCKED',
    );
    await refusal(
      () => store.mutateTrustedAutomationProfile(
        command,
        originGrantId: null,
        expectedGrantRevision: null,
        clock: clock,
      ),
      'STORAGE_BLOCKED',
    );
    await refusal(
      () async => store.currentTrustedMcpGrant(g.grantId, at: clock()),
      'STORAGE_BLOCKED',
    );
    await refusal(
      () => store.openTrustedMcpGrantKey(g.grantId, clock: clock),
      'STORAGE_BLOCKED',
    );
    check(store.isAutomationReady && identical(store.operational, original));
    check(store.currentMcpGrant(g.grantId, at: clock()).id == g.grantId);
  }
  final first = write(command);
  first.ignore();
  check(identical(first, write(command)));
  if (mode == 'catalog-origin') {
    // A different initiator cannot attach to an owner's pending result.
    await refusal(
      () => write(command, origin: g.grantId, revision: 1),
      'FORBIDDEN',
    );
  }
  final ack = await first;
  final id = ack['profileId'] as String;
  check(ack['revision'] == 1 && ack['digest'] == await command.body!.digest());
  if (profileCatalogQuotaModes.contains(mode))
    return verifyProfileCatalogQuotas(store, reopen, mode, command, ack);
  if (profileCatalogFailureModes.contains(mode))
    return verifyProfileCatalogFailure(
      store,
      reopen,
      files,
      mode,
      command,
      ack,
    );
  final oldRevision = store.operational.automation.revisions['$id:1']!.toJson();
  if (mode == 'catalog-cas-race') {
    final oldNativeId = store.operational.rows['profiles']!
        .singleWhere((r) => r.entityId == id)
        .nativeId;
    final commands = [
      for (var n = 0; n < 2; n++)
        AutomationProfileCommand.parse('profile.update', {
          'requestId': g.id(72210 + n),
          'profileId': id,
          'expectedRevision': 1,
          'name': 'Concurrent author $n',
          'body': catalogBody(),
        }),
    ];
    final results = await Future.wait<Object?>([
      for (final next in commands)
        write(next).then<Object?>(
          (value) => value,
          onError: (Object error) {
            if (error is StateError) return error.message;
            throw error;
          },
        ),
    ]);
    check(
      results.whereType<Map<String, Object?>>().length == 1 &&
          results.where((r) => r == 'REVISION_CONFLICT').length == 1,
    );
    final acceptedIndex = results.indexWhere((r) => r is Map);
    final accepted = results[acceptedIndex] as Map<String, Object?>;
    check(
      accepted['revision'] == 2 &&
          store.operational.automation.profiles[id]!.headRevision == 2,
    );
    check(
      store.operational.rows['profiles']!
              .singleWhere((r) => r.entityId == id)
              .nativeId ==
          oldNativeId,
    );
    check(
      store.operational.automation.receipts.containsKey(
            commands[acceptedIndex].requestId,
          ) &&
          !store.operational.automation.receipts.containsKey(
            commands[1 - acceptedIndex].requestId,
          ),
    );
    final rawAfter = await catalogRawNative(Isar.getInstance('workspace')!);
    await store.close();
    store = await reopen();
    sameJson(
      rawAfter,
      await catalogRawNative(Isar.getInstance('workspace')!),
      'catalog-cas-native-reopened',
    );
    sameJson(
      accepted,
      await write(commands[acceptedIndex]),
      'catalog-cas-replay',
    );
    sameJson(
      oldRevision,
      store.operational.automation.revisions['$id:1']!.toJson(),
      'catalog-cas-immutable-history',
    );
    check(
      store.operational.automation.revisions.keys
              .where((k) => k.startsWith('$id:'))
              .length ==
          2,
    );
    check(store.isAutomationReady);
    stdout.writeln('ACTUAL_PROFILE_CATALOG_CAS_RACE_PROVED');
    return store;
  }
  sameJson(ack, await write(command), 'catalog-stable-create');
  if (mode == 'catalog-origin') {
    await refusal(
      () => write(command, origin: g.grantId, revision: 1),
      'FORBIDDEN',
    );
    final byAuthor = createCatalogCommand(72001);
    final pending = write(byAuthor, origin: g.grantId, revision: 1);
    pending.ignore();
    check(identical(pending, write(byAuthor, origin: g.grantId, revision: 1)));
    await refusal(() => write(byAuthor), 'FORBIDDEN');
    await refusal(
      () => store.mutateOwnerGrant(
        OwnerGrantCommand.parse('grant.revoke', {
          'requestId': byAuthor.requestId,
          'grantId': g.grantId,
          'expectedRevision': 1,
        }),
        clock: clock,
      ),
      'FORBIDDEN',
    );
    final authored = await pending;
    check(
      store
              .operational
              .automation
              .revisions['${authored['profileId']}:1']!
              .authorGrantId ==
          g.grantId,
    );
    await refusal(() => write(byAuthor), 'FORBIDDEN');
    await refusal(
      () => store.mutateAutomationProfile(
        createCatalogCommand(72002),
        originGrantId: g.grantId,
        expectedGrantRevision: 1,
        clock: () => DateTime.utc(2026, 10, 22),
      ),
      'FORBIDDEN',
    );
    check(store.isAutomationReady);
    await refusal(
      () => write(
        AutomationProfileCommand.parse('profile.create', {
          'requestId': g.id(41),
          'name': 'Foundation ID collision',
          'body': catalogBody(),
        }),
      ),
      'IDEMPOTENCY_CONFLICT',
    );
  }
  if (mode == 'catalog-queue') {
    final pending = <Future<Map<String, Object?>>>[];
    for (var n = 0; n < 32; n++) {
      final value = write(createCatalogCommand(72100 + n));
      value.ignore();
      pending.add(value);
    }
    await refusal(() => write(createCatalogCommand(72200)), 'RESOURCE_LIMIT');
    await Future.wait(pending);
    check(store.operational.automation.profiles.length == 34);
  }
  if (mode == 'catalog-mixed-queue') {
    final grants = OwnerGrantService(store, clock: clock);
    final pending = <Future<Map<String, Object?>>>[];
    for (var n = 0; n < 32; n++) {
      final value = n.isEven
          ? write(createCatalogCommand(72600 + n))
          : grants.submitOwner(
              'grant.create',
              grantCreate(72600 + n, 72700 + n),
            );
      value.ignore();
      pending.add(value);
    }
    // Reserve all three denials synchronously before a pending write starts
    // its authority publication. These are admission checks, never effects.
    final catalogDenied = write(createCatalogCommand(72800))..ignore();
    final grantDenied = grants.submitOwner(
      'grant.create',
      grantCreate(72801, 72802),
    )..ignore();
    final foundationDenied = store.commitOperationalFoundation(store.state)
      ..ignore();
    await refusal(() => catalogDenied, 'RESOURCE_LIMIT');
    await refusal(() => grantDenied, 'RESOURCE_LIMIT');
    await refusal(() => foundationDenied, 'RESOURCE_LIMIT');
    await Future.wait(pending);
    check(
      store.operational.automation.profiles.length == 18 &&
          store.operational.automation.grants.length == 17,
    );
  }
  final maximum = mode == 'catalog-revisions' ? 20 : 2;
  for (var revision = 2; revision <= maximum; revision++) {
    final next = await write(
      AutomationProfileCommand.parse('profile.update', {
        'requestId': g.id(72300 + revision),
        'profileId': id,
        'expectedRevision': revision - 1,
        'body': catalogBody(),
      }),
    );
    check(next['revision'] == revision && next['digest'] == ack['digest']);
    check(
      store.operational.automation.profiles[id]!.name ==
          'Synthetic catalog profile',
    );
  }
  await refusal(
    () => write(
      AutomationProfileCommand.parse('profile.update', {
        'requestId': g.id(72400),
        'profileId': id,
        'expectedRevision': 1,
        'body': catalogBody(),
      }),
    ),
    'REVISION_CONFLICT',
  );
  if (mode == 'catalog-revisions') {
    await refusal(
      () => write(
        AutomationProfileCommand.parse('profile.update', {
          'requestId': g.id(72401),
          'profileId': id,
          'expectedRevision': 20,
          'body': catalogBody(),
        }),
      ),
      'RESOURCE_LIMIT',
    );
  }
  final archive = AutomationProfileCommand.parse('profile.archive', {
    'requestId': g.id(72500),
    'profileId': id,
    'expectedRevision': maximum,
  });
  final archived = await write(archive);
  sameJson(
    {'profileId': id, 'revision': maximum, 'archived': true},
    archived,
    'catalog-archive',
  );
  sameJson(ack, await write(command), 'catalog-create-replay-after-archive');
  sameJson(
    oldRevision,
    store.operational.automation.revisions['$id:1']!.toJson(),
    'catalog-immutable-first',
  );
  if (mode == 'catalog-basic') {
    await write(
      AutomationProfileCommand.parse('profile.update', {
        'requestId': g.id(72501),
        'profileId': id,
        'expectedRevision': 2,
        'name': 'Changed archived metadata',
        'description': '',
        'body': catalogBody(),
      }),
    );
    check(store.operational.automation.profiles[id]!.archived);
  }
  sameJson(
    originalFoundation,
    store.state.toJson(),
    'catalog-foundation-unchanged',
  );
  for (final group in originalRows.entries) {
    final actual = {
      for (final row in store.operational.rows[group.key]!) row.nativeId: row,
    };
    for (final row in group.value) {
      check(
        actual[row.nativeId]!.entityId == row.entityId &&
            actual[row.nativeId]!.payload == row.payload,
      );
    }
  }
  await store.close();
  store = await reopen();
  sameJson(ack, await write(command), 'catalog-create-replay-reopened');
  sameJson(archived, await write(archive), 'catalog-archive-replay-reopened');
  sameJson(
    oldRevision,
    store.operational.automation.revisions['$id:1']!.toJson(),
    'catalog-reopened-history',
  );
  check(store.isAutomationReady);
  stdout.writeln(
    'ACTUAL_PROFILE_CATALOG_${mode.toUpperCase().replaceAll('-', '_')}_PROVED',
  );
  return store;
}
