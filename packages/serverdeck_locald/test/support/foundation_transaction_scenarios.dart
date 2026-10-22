import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:serverdeck_locald/credentials/provider.dart';
import 'package:serverdeck_locald/profiles/service.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/models.dart';
import 'package:serverdeck_locald/storage/native_failure.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/models.dart';

import '../automation/snapshot_test.dart' as g;
import 'operational_open_scenarios.dart' show refusal;
import 'operational_snapshot_child.dart' show check, sameJson, graphDocument;

const foundationWriteModes = {
  'foundation-settings',
  'foundation-delete',
  'foundation-active',
  'foundation-unknown',
  'foundation-queue',
  'foundation-capacity',
};

void prepareFoundationJobs(
  Map<String, List<Map<String, Object?>>> data,
  String mode,
) {
  if (mode != 'foundation-active' && mode != 'foundation-unknown') return;
  data['jobs']!.single.addAll({
    'state': mode == 'foundation-active' ? 'running' : 'unknown',
    'nextSequence': 1,
    'outcome': mode == 'foundation-active'
        ? null
        : {
            'effects': 'uncertain',
            'checks': <Object?>[],
            'safeCode': 'UNKNOWN_OUTCOME',
          },
  });
  data['events']!.clear();
  data['desired']!.clear();
}

Future<StateStore> verifyFoundationTransactions(
  StateStore store,
  Future<StateStore> Function() open,
  KeyCustody custody,
  ReceiptKeyMaterial key,
  String mode,
) async {
  final expectedGraph = graphDocument(store.operational);
  final oldRows = store.operational.rows;
  final service = ProfileService(CredentialProvider(custody));
  var request = 60000;
  Future<WorkspaceState> prepare(
    ApiMethod method,
    Map<String, Object?> input,
  ) async {
    final id = g.id(request++), state = store.state;
    const now = '2026-10-21T12:00:00.000Z';
    final prepared = await service.prepare(state, method, input, now);
    (prepared.value['receipts'] as Map)[id] = {
      'requestId': id,
      'inputDigest': custody.receiptDigestSync(key, {
        'operation': method.wireName,
        'params': input,
      }),
      'operation': method.wireName,
      'profileId': prepared.result.entityId,
      'result': prepared.result.toJson(),
      'committedAt': now,
    };
    return WorkspaceState.fromJson(
      prepared.value,
      workspaceId: state.workspaceId,
      receiptKeyId: state.receiptKeyId,
      ownerSid: state.ownerSid,
    );
  }

  Map<String, Object?> update({bool connection = false}) {
    final profile = store.state.profiles.values.single.toJson();
    return {
      'profileId': profile['id'],
      'expectedRevision': profile['revision'],
      for (final field in ['name', 'address', 'port', 'sshUser', 'tags'])
        field: profile[field],
      'name': 'Renamed',
      'tags': ['synthetic'],
      if (connection) 'address': 'changed.invalid',
      'credential': {'action': 'keep'},
    };
  }

  if (mode == 'foundation-active' || mode == 'foundation-unknown') {
    final original = store.state.toJson();
    await refusal(
      () async => store.commitOperationalFoundation(
        await prepare(ApiMethod.profilesUpdate, update(connection: true)),
      ),
      'HOST_BUSY',
    );
    await refusal(
      () async => store.commitOperationalFoundation(
        await prepare(ApiMethod.profilesDelete, {
          'profileId': store.state.profiles.keys.single,
          'expectedRevision': store.state.profiles.values.single.revision,
        }),
      ),
      'HOST_BUSY',
    );
    sameJson(original, store.state.toJson(), 'occupied-unchanged');
    check(store.isAutomationReady);
    await store.commitOperationalFoundation(
      await prepare(ApiMethod.profilesUpdate, update()),
    );
    check(store.state.profiles.values.single.name == 'Renamed');
  } else if (mode == 'foundation-delete') {
    final profile = store.state.profiles.values.single.toJson();
    await store.commitOperationalFoundation(
      await prepare(ApiMethod.profilesDelete, {
        'profileId': profile['id'],
        'expectedRevision': profile['revision'],
      }),
    );
    check(
      store.state.profiles.isEmpty &&
          store.operational.automation.jobs.isNotEmpty,
    );
    await refusal(
      () async => store.commitOperationalFoundation(
        await prepare(ApiMethod.profilesCreate, {
          'profileId': profile['id'],
          for (final field in ['name', 'address', 'port', 'sshUser', 'tags'])
            field: profile[field],
          'credential': {'action': 'clear'},
        }),
      ),
      'ALREADY_EXISTS',
    );
    check(store.isAutomationReady && store.state.profiles.isEmpty);
  } else {
    final next = await prepare(ApiMethod.settingsUpdate, {
      'expectedRevision': store.state.settings.revision,
      'theme': 'dark',
      'reduceMotion': true,
      'selectedProfileId': store.state.profiles.keys.single,
    });
    if (mode == 'foundation-capacity') {
      final native = Isar.getInstance('workspace')!;
      final ready = Completer<void>(), release = Completer<void>();
      stdout.writeln('FOUNDATION_CAPACITY:reader-start');
      final reader = native.txn(() async {
        check(await native.storedSettings.get(1) != null);
        ready.complete();
        await release.future;
      });
      await ready.future;
      stdout.writeln('FOUNDATION_CAPACITY:reader-ready');
      try {
        final original = (await native.storedSettings.get(1))!.payload;
        final alternate = jsonEncode({
          ...jsonDecode(original) as Map,
          'reduceMotion': !(jsonDecode(original)['reduceMotion'] as bool),
        });
        var full = false;
        // Owned native fixture maintenance: each committed transaction restores
        // the exact original row. A retained reader forces real page versions,
        // filling the production 64MiB map without corrupt rows or fake limits.
        for (var n = 0; n < 20000; n++) {
          if (n % 1000 == 0) stdout.writeln('FOUNDATION_CAPACITY:writes-$n');
          try {
            await native.writeTxn(() async {
              await native.storedSettings.put(
                StoredSettings()..payload = alternate,
              );
              await native.storedSettings.put(
                StoredSettings()..payload = original,
              );
            });
          } catch (error) {
            if (!isNativeCapacityFailure(error)) rethrow;
            stdout.writeln('FOUNDATION_CAPACITY:native-full');
            full = true;
            break;
          }
        }
        check(
          full && (await native.storedSettings.get(1))!.payload == original,
        );
        final before = store.state.toJson();
        stdout.writeln('FOUNDATION_CAPACITY:before-store-write');
        await refusal(
          () => store.commitOperationalFoundation(next),
          'RESOURCE_LIMIT',
        );
        sameJson(before, store.state.toJson(), 'capacity-abort');
        sameJson(
          expectedGraph,
          graphDocument(store.operational),
          'capacity-graph',
        );
        check(store.isAutomationReady);
        stdout.writeln('FOUNDATION_CAPACITY:rollback-proved');
      } finally {
        release.complete();
        await reader;
      }
      await store.commitOperationalFoundation(next);
      stdout.writeln('FOUNDATION_CAPACITY:retry-proved');
    } else if (mode == 'foundation-queue') {
      final results = <Future<String>>[];
      for (var n = 0; n < 33; n++) {
        results.add(
          store
              .commitOperationalFoundation(next)
              .then(
                (_) => 'OK',
                onError: (Object error) => (error as StateError).message,
              ),
        );
      }
      final codes = await Future.wait(results);
      check(codes.where((v) => v == 'OK').length == 1);
      check(codes.where((v) => v == 'REVISION_CONFLICT').length == 31);
      check(codes.where((v) => v == 'RESOURCE_LIMIT').length == 1);
    } else {
      await store.commitOperationalFoundation(next);
    }
    check(
      store.state.settings.toJson()['theme'] == 'dark' &&
          store.isAutomationReady,
    );
  }
  final committed = store.state.toJson();
  sameJson(
    expectedGraph,
    graphDocument(store.operational),
    'after-foundation-graph',
  );
  for (final collection in oldRows.keys) {
    sameJson(
      [
        for (final row in oldRows[collection]!)
          [row.nativeId, row.entityId, row.payload],
      ],
      [
        for (final row in store.operational.rows[collection]!)
          [row.nativeId, row.entityId, row.payload],
      ],
      'retained-native-$collection',
    );
  }
  final physical = await Isar.getInstance('workspace')!.storedWorkspaces.get(1);
  check(jsonDecode(physical!.payload)['schemaVersion'] == 2);
  await refusal(() => store.commit(store.state));
  await store.close();
  store = await open();
  sameJson(committed, store.state.toJson(), 'foundation-reopened');
  sameJson(
    expectedGraph,
    graphDocument(store.operational),
    'foundation-reopened-graph',
  );
  check(
    StrictCodec().canonical(committed).isNotEmpty && store.isAutomationReady,
  );
  return store;
}
