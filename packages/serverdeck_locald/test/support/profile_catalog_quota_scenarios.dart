import 'dart:convert';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:serverdeck_locald/automation/profile_commands.dart';
import 'package:serverdeck_locald/storage/automation_records.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_protocol/codec.dart';

import '../automation/snapshot_test.dart' as g;
import 'operational_open_scenarios.dart' show refusal;
import 'operational_snapshot_child.dart' show check, sameJson;

const profileCatalogQuotaModes = {
  'catalog-profile-limit',
  'catalog-receipt-limit',
  'catalog-profile-id-limit',
  'catalog-revision-id-limit',
  'catalog-receipt-id-limit',
};

String encoded(Map<String, Object?> value) =>
    utf8.decode(StrictCodec().canonical(value));

Object retained(StateStore store) => {
  'foundation': store.state.toJson(),
  'rows': {
    for (final entry in store.operational.rows.entries)
      entry.key: {
        for (final row in entry.value)
          '${row.nativeId}': {'entityId': row.entityId, 'payload': row.payload},
      },
  },
};

/// Seed genuine native rows, close and fully reload them before exercising the
/// real writer. No quota, loader, clock or storage result is replaced.
Future<StateStore> verifyProfileCatalogQuotas(
  StateStore store,
  Future<StateStore> Function() reopen,
  String mode,
  AutomationProfileCommand original,
  Map<String, Object?> ack,
) async {
  final native = Isar.getInstance('workspace')!;
  final profileId = ack['profileId'] as String;
  final metadata = store.operational.automation.profiles[profileId]!.toJson();
  final revision = store.operational.automation.revisions['$profileId:1']!
      .toJson();
  final receipt = store.operational.automation.receipts[original.requestId]!
      .toJson();
  final profiles = <StoredAutomationProfile>[];
  final revisions = <StoredAutomationRevision>[];
  final receipts = <StoredAutomationReceipt>[];
  var profileNativeId = store.operational.rows['profiles']!
      .map((r) => r.nativeId)
      .reduce((a, b) => a > b ? a : b);
  var revisionNativeId = store.operational.rows['revisions']!
      .map((r) => r.nativeId)
      .reduce((a, b) => a > b ? a : b);
  var receiptNativeId = store.operational.rows['receipts']!
      .map((r) => r.nativeId)
      .reduce((a, b) => a > b ? a : b);
  if (mode == 'catalog-profile-limit') {
    for (var n = store.operational.automation.profiles.length; n < 249; n++) {
      final id = g.id(900000 + n), request = g.id(800000 + n);
      profiles.add(
        StoredAutomationProfile()
          ..id = ++profileNativeId
          ..entityId = id
          ..payload = encoded({...metadata, 'id': id}),
      );
      revisions.add(
        StoredAutomationRevision()
          ..id = ++revisionNativeId
          ..entityId = '$id:1'
          ..payload = encoded({...revision, 'profileId': id}),
      );
      receipts.add(
        StoredAutomationReceipt()
          ..id = ++receiptNativeId
          ..entityId = request
          ..payload = encoded({
            ...receipt,
            'requestId': request,
            'result': {...ack, 'profileId': id},
          }),
      );
    }
  } else if (mode == 'catalog-receipt-limit') {
    final existing = await native.storedAutomationProfiles.getByEntityId(
      profileId,
    );
    profiles.add(existing!..payload = encoded({...metadata, 'archived': true}));
    for (var n = store.operational.automation.receipts.length; n < 9999; n++) {
      final request = g.id(800000 + n);
      receipts.add(
        StoredAutomationReceipt()
          ..id = ++receiptNativeId
          ..entityId = request
          ..payload = encoded({
            ...receipt,
            'requestId': request,
            'operation': 'profile.archive',
            'result': {'profileId': profileId, 'revision': 1, 'archived': true},
          }),
      );
    }
  }
  const maximum = 9223372036854775807;
  await native.writeTxn(() async {
    if (mode == 'catalog-profile-id-limit') {
      final row = (await native.storedAutomationProfiles.getByEntityId(
        profileId,
      ))!;
      check(await native.storedAutomationProfiles.delete(row.id));
      profiles.add(row..id = maximum);
    } else if (mode == 'catalog-revision-id-limit') {
      final row = (await native.storedAutomationRevisions.getByEntityId(
        '$profileId:1',
      ))!;
      check(await native.storedAutomationRevisions.delete(row.id));
      revisions.add(row..id = maximum);
    } else if (mode == 'catalog-receipt-id-limit') {
      final row = (await native.storedAutomationReceipts.getByEntityId(
        original.requestId,
      ))!;
      check(await native.storedAutomationReceipts.delete(row.id));
      receipts.add(row..id = maximum);
    }
    await native.storedAutomationProfiles.putAll(profiles);
    await native.storedAutomationRevisions.putAll(revisions);
    await native.storedAutomationReceipts.putAll(receipts);
  });
  await store.close();
  store = await reopen();
  check(store.isAutomationReady);
  Future<Map<String, Object?>> write(AutomationProfileCommand command) =>
      store.mutateAutomationProfile(
        command,
        originGrantId: null,
        expectedGrantRevision: null,
        clock: () => DateTime.utc(2026, 10, 21, 12),
      );
  AutomationProfileCommand create(int n) =>
      AutomationProfileCommand.parse('profile.create', {
        'requestId': g.id(n),
        'name': 'Quota boundary',
        'body': original.body!.toJson(),
      });
  AutomationProfileCommand archive(int n) => AutomationProfileCommand.parse(
    'profile.archive',
    {'requestId': g.id(n), 'profileId': profileId, 'expectedRevision': 1},
  );
  AutomationProfileCommand update(int n) =>
      AutomationProfileCommand.parse('profile.update', {
        'requestId': g.id(n),
        'profileId': profileId,
        'expectedRevision': 1,
        'body': original.body!.toJson(),
      });
  Future<void> denied(AutomationProfileCommand command) async {
    final before = retained(store);
    await refusal(() => write(command), 'RESOURCE_LIMIT');
    check(store.isAutomationReady);
    sameJson(before, retained(store), '$mode-cached-refusal');
    await store.close();
    store = await reopen();
    check(store.isAutomationReady);
    sameJson(before, retained(store), '$mode-native-reopened-refusal');
  }

  if (mode == 'catalog-profile-limit') {
    check(store.operational.automation.profiles.length == 249);
    await write(create(79000));
    check(store.operational.automation.profiles.length == 250);
    await denied(create(79001));
    await write(archive(79002));
    check(store.operational.automation.profiles[profileId]!.archived);
    // Archive does not reclaim the lifetime catalog slot.
    await denied(create(79003));
  } else if (mode == 'catalog-receipt-limit') {
    check(store.operational.automation.receipts.length == 9999);
    final last = archive(79000);
    final accepted = await write(last);
    check(store.operational.automation.receipts.length == 10000);
    await denied(create(79001));
    await denied(update(79002));
    await denied(archive(79003));
    sameJson(accepted, await write(last), '$mode-last-replay');
  } else {
    final group = mode == 'catalog-profile-id-limit'
        ? 'profiles'
        : mode == 'catalog-revision-id-limit'
        ? 'revisions'
        : 'receipts';
    check(store.operational.rows[group]!.any((r) => r.nativeId == maximum));
    await denied(create(79000));
    if (group == 'profiles') {
      await write(update(79001));
      check(
        store.operational.automation.profiles[profileId]!.headRevision == 2,
      );
      check(
        store.operational.rows['profiles']!
                .singleWhere((r) => r.entityId == profileId)
                .nativeId ==
            maximum,
      );
    } else if (group == 'revisions') {
      await denied(update(79001));
      await write(archive(79002));
      check(store.operational.automation.profiles[profileId]!.archived);
    } else {
      await denied(update(79001));
      await denied(archive(79002));
    }
  }
  sameJson(ack, await write(original), '$mode-original-durable-replay');
  final finalRows = retained(store);
  await store.close();
  store = await reopen();
  sameJson(finalRows, retained(store), '$mode-final-native-reopen');
  sameJson(ack, await write(original), '$mode-final-durable-replay');
  stdout.writeln(
    'ACTUAL_PROFILE_CATALOG_${mode.toUpperCase().replaceAll('-', '_')}_PROVED',
  );
  return store;
}
