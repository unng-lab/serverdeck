import 'dart:convert';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as path;
import 'package:serverdeck_locald/storage/automation_records.dart';
import 'package:serverdeck_locald/storage/host_trust_models.dart';
import 'package:serverdeck_locald/storage/host_trust_records.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/models.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_windows/mutex.dart';

import '../automation/snapshot_test.dart' as g;
import 'mcp_runtime_actor.dart' show check, refusal;
import 'trusted_schema_child.dart' as raw;

/// Owned full historical graph, actual format3 opener and genuine DPAPI keys.
/// Tests storage only; no challenge, native target fence or service is faked.
Future<void> exerciseTrustedGraphWrite(
  String root,
  KeyCustody custody,
  ReceiptKeyMaterial key,
  MutexLease lease, {
  String? busyState,
}) async {
  final busy = busyState != null;
  Future<StateStore> open() => StateStore.openTrustedOperational(
    localAppData: root,
    appRoot: root,
    custody: custody,
    receiptKey: key,
    lease: lease,
  );
  StateStore? store;
  Isar? maintenance;
  try {
    store = await open();
    final server = store.state.profiles.keys.single;
    final initial = store.trustedOperational;
    final automationNames = initial.rows.keys
        .where(
          (n) => !const {
            'StoredWorkspace',
            'StoredSettings',
            'StoredProfile',
            'StoredCredential',
            'StoredReceipt',
            'StoredHostTrust',
          }.contains(n),
        )
        .toSet();
    check(
      automationNames.length == 10 &&
          automationNames.every((n) => initial.rows[n]!.isNotEmpty),
    );
    final originalPlan = initial.automation.plans.values.single.toJson();
    final initialCredential = initial.rows['StoredCredential']!.single;
    final settings = initial.rows['StoredSettings']!.single;
    final firstReceipts = initial.rows['StoredReceipt']!;
    String automationRaw() {
      final value = store!.trustedOperational;
      return jsonEncode({
        for (final n in automationNames)
          n: [
            for (final r in value.rows[n]!) [r.nativeId, r.entityId, r.payload],
          ],
      });
    }

    var automationBefore = automationRaw();
    Future<String> nativeAutomationRaw() async {
      final native =
          jsonDecode(await raw.capture(Isar.getInstance('workspace')!)) as Map;
      return jsonEncode({for (final n in automationNames) n: native[n]});
    }

    var nativeAutomationBefore = await nativeAutomationRaw();
    HostTrustState next(
      String operation,
      Map<String, Object?>? profile,
      Map<String, HostTrustRecord> trust, {
      Map<String, Object?>? credential,
      String? request,
    }) {
      final current = store!.state;
      final revision = '${int.parse(current.storeRevision) + 1}';
      final doc = current.toJson()..['storeRevision'] = revision;
      if (profile == null) {
        (doc['profiles'] as Map).clear();
        (doc['credentials'] as Map).clear();
      } else {
        (doc['profiles'] as Map)[server] = profile;
      }
      if (credential != null)
        doc['credentials'] = {credential['id'] as String: credential};
      final requestId = request ?? g.id(200 + int.parse(revision));
      (doc['receipts'] as Map)[requestId] = {
        'requestId': requestId,
        'inputDigest': custody.receiptDigestSync(key, {
          'operation': operation,
          'revision': revision,
        }),
        'operation': operation,
        'profileId': server,
        'result': {
          'entityId': server,
          'entityRevision':
              profile?['revision'] ?? current.profiles[server]!.revision,
          'storeRevision': revision,
          'deleted': profile == null,
        },
        'committedAt': g.finished,
      };
      return HostTrustState.fromRecords(
        WorkspaceState.fromTrustedJson(
          doc,
          workspaceId: key.workspaceId,
          receiptKeyId: key.receiptKeyId,
          ownerSid: key.ownerSid,
        ),
        trust,
      );
    }

    Map<String, Object?> profile({
      bool trustChange = false,
      bool connection = false,
    }) {
      final p = store!.state.profiles[server]!;
      return {
        ...p.toJson(),
        'revision': '${int.parse(p.revision) + 1}',
        'trustRevision':
            '${int.parse(p.trustRevision) + (trustChange ? 1 : 0)}',
        'connectionRevision':
            '${int.parse(p.connectionRevision) + (connection ? 1 : 0)}',
        'updatedAt': g.finished,
      };
    }

    HostTrustRecord trust(
      Map<String, Object?> p,
      String status, {
      bool newPin = false,
    }) {
      final old = store!.trustedOperational.foundation.trust[server];
      return HostTrustRecord.fromJson({
        'workspaceId': key.workspaceId,
        'profileId': server,
        'revision': p['trustRevision'],
        'connectionRevision': status == 'trusted'
            ? p['connectionRevision']
            : old!.connectionRevision,
        'status': status,
        'key': newPin || old == null
            ? {
                'format': 'ssh-ed25519',
                'fingerprint':
                    'SHA256:${base64.encode(List.filled(32, newPin ? 1 : 0)).replaceAll('=', '')}',
              }
            : old.key.toJson(),
        'createdAt': old?.createdAt ?? g.finished,
        'updatedAt': g.finished,
      });
    }

    Future<void> retained() async {
      check(automationRaw() == automationBefore);
      check(await nativeAutomationRaw() == nativeAutomationBefore);
      final value = store!.trustedOperational;
      check(
        jsonEncode(value.automation.plans.values.single.toJson()) ==
            jsonEncode(originalPlan),
      );
      check(value.rows['StoredSettings']!.single.payload == settings.payload);
      for (final old in firstReceipts) {
        final current = value.rows['StoredReceipt']!.singleWhere(
          (r) => r.entityId == old.entityId,
        );
        check(
          current.nativeId == old.nativeId && current.payload == old.payload,
        );
      }
      check(!store.isAutomationReady);
    }

    Future<String> capture() async {
      final db = Isar.getInstance('workspace')!;
      final rows = await db.storedHostTrusts.where().findAll();
      rows.sort((a, b) => a.id.compareTo(b.id));
      return '${await raw.capture(db)}\n${jsonEncode([
        for (final r in rows) [r.id, r.entityId, r.payload],
      ])}';
    }

    var p = profile(trustChange: true);
    await store.commitTrustedFoundation(
      next('servers.trust.confirm', p, {server: trust(p, 'trusted')}),
    );
    await retained();
    check(
      store.trustedOperational.rows['StoredCredential']!.single.payload ==
          initialCredential.payload,
    );
    final confirmedId =
        store.trustedOperational.rows['StoredHostTrust']!.single.nativeId;
    if (busy) {
      // Persist a valid nonterminal job only after migration has finished.
      // Migration's occupied-source guard stays intact; reopen loads this graph.
      await store.close();
      store = null;
      maintenance = await Isar.open(
        trustedWorkspaceSchemas,
        directory: path.join(
          root,
          'ServerDeckNext',
          'v1',
          'workspaces',
          'default',
        ),
        name: 'workspace',
        maxSizeMiB: 64,
        relaxedDurability: false,
        inspector: false,
      );
      final db = maintenance;
      await db.writeTxn(() async {
        final row = (await db.storedAutomationJobs.where().findAll()).single;
        final doc = jsonDecode(row.payload) as Map;
        doc['state'] = busyState;
        doc['cancelRequested'] = busyState == 'cancel-requested';
        doc['nextSequence'] = 1;
        doc['outcome'] = busyState == 'unknown'
            ? {
                'effects': 'uncertain',
                'checks': <Object?>[],
                'safeCode': 'UNKNOWN_OUTCOME',
              }
            : null;
        row.payload = jsonEncode(doc);
        await db.storedAutomationJobs.put(row);
        await db.storedDesiredStates.clear();
        await db.storedAutomationEvents.clear();
      });
      check(await db.close());
      maintenance = null;
      store = await open();
      automationBefore = automationRaw();
      nativeAutomationBefore = await nativeAutomationRaw();
    }
    // Metadata remains allowed even with a nonterminal target job.
    p = profile()..['name'] = 'Retained history 🐧';
    p['tags'] = ['retained', 'storage'];
    await store.commitTrustedFoundation(
      next('profiles.update', p, store.trustedOperational.foundation.trust),
    );
    await retained();
    final beforeRefusals = await capture();
    await refusal(
      () => store!.commitTrustedFoundation(
        next(
          'profiles.update',
          profile(),
          store.trustedOperational.foundation.trust,
          request: g.id(12),
        ),
      ),
      'IDEMPOTENCY_CONFLICT',
    );
    check(await capture() == beforeRefusals && store.isTrustedSnapshotLoaded);
    final cred = store.state.credentials.values.single;
    final replacement = {
      ...cred.toJson(),
      'id': g.id(92),
      'revision': '${int.parse(cred.revision) + 1}',
      'protectedBlob': await custody.wrapCredential(
        key.workspaceId,
        server,
        g.id(92),
        {
          'action': 'replace',
          'kind': 'password',
          'password': 'owned-full-graph-replacement',
        },
      ),
      'createdAt': g.finished,
      'updatedAt': g.finished,
    };
    final credentialProfile = profile()
      ..['credentialRevision'] = replacement['revision']
      ..['credentialRef'] = replacement['id'];
    if (busy) {
      p = profile(trustChange: true);
      for (final candidate in [
        next('servers.trust.confirm', p, {server: trust(p, 'trusted')}),
        next('servers.trust.revoke', p, {server: trust(p, 'revoked')}),
        next(
          'profiles.update',
          {
            ...profile(trustChange: true, connection: true),
            'address': 'changed.invalid',
          },
          {server: trust(p, 'revoked')},
        ),
        next(
          'profiles.update',
          credentialProfile,
          store.trustedOperational.foundation.trust,
          credential: replacement,
        ),
        next('profiles.delete', null, {}),
      ]) {
        await refusal(
          () => store!.commitTrustedFoundation(candidate),
          'HOST_BUSY',
        );
        check(
          await capture() == beforeRefusals && store.isTrustedSnapshotLoaded,
        );
      }
      await retained();
    } else {
      await store.commitTrustedFoundation(
        next(
          'profiles.update',
          credentialProfile,
          store.trustedOperational.foundation.trust,
          credential: replacement,
        ),
      );
      await retained();
      p = profile(trustChange: true, connection: true)
        ..['address'] = 'changed.invalid';
      await store.commitTrustedFoundation(
        next('profiles.update', p, {server: trust(p, 'revoked')}),
      );
      await retained();
      check(
        store.trustedOperational.foundation.trust[server]!.connectionRevision ==
            '2',
      );
      p = profile(trustChange: true);
      await store.commitTrustedFoundation(
        next('servers.trust.revoke', p, {server: trust(p, 'revoked')}),
      );
      await retained();
      p = profile(trustChange: true);
      await store.commitTrustedFoundation(
        next('servers.trust.confirm', p, {
          server: trust(p, 'trusted', newPin: true),
        }),
      );
      await retained();
      check(
        store.trustedOperational.rows['StoredHostTrust']!.single.nativeId ==
            confirmedId,
      );
      await store.commitTrustedFoundation(next('profiles.delete', null, {}));
      await retained();
      check(
        store.state.profiles.isEmpty &&
            store.state.credentials.isEmpty &&
            store.trustedOperational.foundation.trust.isEmpty,
      );
    }
    final durable = await capture();
    await store.close();
    store = await open();
    check(await capture() == durable);
    await retained();
  } finally {
    if (store != null) await store.close();
    if (maintenance != null) check(await maintenance.close());
  }
}
