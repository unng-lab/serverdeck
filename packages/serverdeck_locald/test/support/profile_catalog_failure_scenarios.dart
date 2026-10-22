import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/automation/profile_commands.dart';
import 'package:serverdeck_locald/storage/automation_records.dart';
import 'package:serverdeck_locald/storage/native_failure.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_windows/mcp_credential_files.dart';
import 'package:serverdeck_windows/paths.dart';

import '../automation/snapshot_test.dart' as g;
import 'operational_open_scenarios.dart' show refusal;
import 'operational_snapshot_child.dart' show check, sameJson;
import 'profile_catalog_quota_scenarios.dart' show retained;

const profileCatalogFailureModes = {
  'catalog-capacity',
  'catalog-readback-corrupt',
};

Future<Map<String, Map<String, Object?>>> catalogRawNative(Isar native) async {
  final result = <String, Map<String, Object?>>{};
  Future<void> capture<T>(IsarCollection<T> collection, String name) async {
    final values = <String, Object?>{};
    for (final row in await collection.where().findAll()) {
      final dynamic value = row;
      values['${value.id}'] = {
        'payload': value.payload,
        if (name != StoredWorkspaceSchema.name &&
            name != StoredSettingsSchema.name)
          'entityId': value.entityId,
      };
    }
    result[name] = values;
  }

  await capture(native.storedWorkspaces, StoredWorkspaceSchema.name);
  await capture(native.storedSettings, StoredSettingsSchema.name);
  await capture(native.storedProfiles, StoredProfileSchema.name);
  await capture(native.storedCredentials, StoredCredentialSchema.name);
  await capture(native.storedReceipts, StoredReceiptSchema.name);
  await capture(native.storedMcpGrants, StoredMcpGrantSchema.name);
  await capture(native.storedDelegations, StoredDelegationSchema.name);
  await capture(
    native.storedAutomationProfiles,
    StoredAutomationProfileSchema.name,
  );
  await capture(
    native.storedAutomationRevisions,
    StoredAutomationRevisionSchema.name,
  );
  await capture(native.storedAutomationPlans, StoredAutomationPlanSchema.name);
  await capture(
    native.storedAutomationApprovals,
    StoredAutomationApprovalSchema.name,
  );
  await capture(native.storedAutomationJobs, StoredAutomationJobSchema.name);
  await capture(native.storedDesiredStates, StoredDesiredStateSchema.name);
  await capture(
    native.storedAutomationReceipts,
    StoredAutomationReceiptSchema.name,
  );
  await capture(
    native.storedAutomationEvents,
    StoredAutomationEventSchema.name,
  );
  check(result.length == automationWorkspaceSchemas.length);
  return result;
}

Future<StateStore> verifyProfileCatalogFailure(
  StateStore store,
  Future<StateStore> Function() reopen,
  McpCredentialFiles files,
  String mode,
  AutomationProfileCommand original,
  Map<String, Object?> originalAck,
) async {
  final native = Isar.getInstance('workspace')!;
  final before = retained(store), rawBefore = await catalogRawNative(native);
  final foundationDigest = store.operational.foundation.rows.digest();
  final next = AutomationProfileCommand.parse('profile.create', {
    'requestId': g.id(78000),
    'name': 'Actual storage failure recovery',
    'body': original.body!.toJson(),
  });
  Future<Map<String, Object?>> write(AutomationProfileCommand command) =>
      store.mutateAutomationProfile(
        command,
        originGrantId: null,
        expectedGrantRevision: null,
        clock: () => DateTime.utc(2026, 10, 21, 12),
      );
  try {
    if (mode == 'catalog-capacity') {
      final ready = Completer<void>(), release = Completer<void>();
      final reader = native.txn(() async {
        check(await native.storedSettings.get(1) != null);
        ready.complete();
        await release.future;
      });
      await ready.future;
      try {
        final originalPayload = (await native.storedSettings.get(1))!.payload;
        final value = jsonDecode(originalPayload) as Map;
        final alternate = jsonEncode({
          ...value,
          'reduceMotion': !(value['reduceMotion'] as bool),
        });
        var actualFull = false;
        // The retained reader pins genuine native page versions. Every real
        // committed maintenance transaction restores the identical original row.
        for (var n = 0; n < 20000; n++) {
          try {
            await native.writeTxn(() async {
              await native.storedSettings.put(
                StoredSettings()..payload = alternate,
              );
              await native.storedSettings.put(
                StoredSettings()..payload = originalPayload,
              );
            });
          } catch (error) {
            if (!isNativeCapacityFailure(error)) rethrow;
            actualFull = true;
            break;
          }
        }
        check(actualFull);
        sameJson(
          rawBefore,
          await catalogRawNative(native),
          'catalog-pinned-native-full-no-logical-change',
        );
        check(
          store.operational.automation.profiles.length < 250 &&
              store.operational.automation.receipts.length < 10000,
        );
        await refusal(() => write(next), 'RESOURCE_LIMIT');
        check(store.isAutomationReady);
        sameJson(before, retained(store), 'catalog-native-full-cache-rollback');
        sameJson(
          rawBefore,
          await catalogRawNative(native),
          'catalog-native-full-actual-rollback',
        );
        check(
          await native.storedAutomationReceipts.getByEntityId(next.requestId) ==
              null,
        );
      } finally {
        release.complete();
        await reader;
      }
      final accepted = await write(next);
      sameJson(
        accepted,
        await write(next),
        'catalog-capacity-exact-retry-replay',
      );
      final rawAfter = await catalogRawNative(native);
      await store.close();
      store = await reopen();
      sameJson(
        rawAfter,
        await catalogRawNative(Isar.getInstance('workspace')!),
        'catalog-capacity-native-reopened',
      );
      sameJson(accepted, await write(next), 'catalog-capacity-reopened-replay');
    } else {
      final grant = store.operational.automation.grants.values.first;
      final blob = p.join(
        files.directory,
        'mcp-credentials',
        grant.id,
        '${grant.secretRef}.dpapi',
      );
      final ciphertext = await readProtectedFile(
        files.localAppData,
        blob,
        files.ownerSid,
        maxBytes: 16384,
      );
      try {
        // Real referenced ciphertext damage makes actual postcommit readback
        // fail. No fake callback, returned snapshot or injected storage error.
        await replaceProtectedFile(files.localAppData, blob, files.ownerSid, [
          1,
          2,
          3,
        ]);
        await refusal(() => write(next));
        check(!store.isAutomationReady);
        await refusal(() async => store.operational);
        await refusal(() => write(original));
        final receipt = await native.storedAutomationReceipts.getByEntityId(
          next.requestId,
        );
        check(receipt != null);
        final result = Map<String, Object?>.from(
          (jsonDecode(receipt!.payload) as Map)['result'] as Map,
        );
        final id = result['profileId'] as String;
        check(
          await native.storedAutomationProfiles.getByEntityId(id) != null &&
              await native.storedAutomationRevisions.getByEntityId('$id:1') !=
                  null,
        );
        final rawCommitted = await catalogRawNative(native);
        final changed = {
          StoredAutomationProfileSchema.name,
          StoredAutomationRevisionSchema.name,
          StoredAutomationReceiptSchema.name,
        };
        for (final group in rawBefore.entries) {
          final actual = rawCommitted[group.key]!;
          check(
            actual.length ==
                group.value.length + (changed.contains(group.key) ? 1 : 0),
          );
          for (final row in group.value.entries) {
            sameJson(
              row.value,
              actual[row.key],
              'catalog-readback-preserved-${group.key}',
            );
          }
        }
        await store.close();
        await refusal(reopen);
        // Explicit owned fixture repair, never automatic product fallback.
        await replaceProtectedFile(
          files.localAppData,
          blob,
          files.ownerSid,
          ciphertext,
        );
        store = await reopen();
        sameJson(
          rawCommitted,
          await catalogRawNative(Isar.getInstance('workspace')!),
          'catalog-readback-exact-native-recovery',
        );
        sameJson(
          result,
          await write(next),
          'catalog-readback-durable-committed-replay',
        );
        check(
          store.operational.automation.receipts.containsKey(next.requestId),
        );
      } finally {
        await replaceProtectedFile(
          files.localAppData,
          blob,
          files.ownerSid,
          ciphertext,
        );
      }
    }
    check(store.isAutomationReady);
    check(store.operational.foundation.rows.digest() == foundationDigest);
    sameJson(
      originalAck,
      await write(original),
      'catalog-original-replay-after-native-failure',
    );
    stdout.writeln(
      'ACTUAL_PROFILE_CATALOG_${mode.toUpperCase().replaceAll('-', '_')}_ROLLBACK_RECOVERY_PROVED',
    );
    return store;
  } catch (_) {
    await store.close();
    rethrow;
  }
}
