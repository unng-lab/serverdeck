import 'dart:convert';

import 'package:isar_community/isar.dart';
import 'package:serverdeck_locald/storage/automation_records.dart';
import 'package:serverdeck_locald/storage/host_trust_models.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/models.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_protocol/host_trust.dart';

import '../models_test.dart' as f;
import 'mcp_runtime_actor.dart' show check, refusal;

String id(int n) => '20000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

Map<String, Object?> seededTrustedWrite(Map<String, Object?> empty) => {
  ...empty,
  'storeRevision': '1',
  'profiles': {f.profileId: f.profile()},
  'receipts': {f.requestId: f.receipt()},
};

Future<void> exerciseTrustedWrite(
  StateStore store,
  KeyCustody custody,
  ReceiptKeyMaterial key,
  String mode,
) async {
  final db = Isar.getInstance('workspace')!;
  const server = f.profileId;
  HostTrustState next(
    String operation, {
    Map<String, Object?>? profile,
    Map<String, Object?>? credential,
    Map<String, HostTrustRecord>? trust,
    bool delete = false,
  }) {
    final old = store.state;
    final n = int.parse(old.storeRevision) + 1;
    final doc = old.toJson()..['storeRevision'] = '$n';
    if (profile != null) (doc['profiles'] as Map)[server] = profile;
    if (credential != null)
      (doc['credentials'] as Map)[f.credentialId] = credential;
    if (delete) {
      (doc['profiles'] as Map).clear();
      (doc['credentials'] as Map).clear();
    }
    (doc['receipts'] as Map)[id(n)] = {
      'requestId': id(n),
      'operation': operation,
      'inputDigest': custody.receiptDigestSync(key, {
        'operation': operation,
        'n': n,
      }),
      'profileId': server,
      'result': {
        'entityId': server,
        'entityRevision': delete
            ? old.profiles[server]!.revision
            : profile!['revision'],
        'storeRevision': '$n',
        'deleted': delete,
      },
      'committedAt': f.time,
    };
    return HostTrustState.fromRecords(
      WorkspaceState.fromTrustedJson(
        doc,
        workspaceId: old.workspaceId,
        receiptKeyId: old.receiptKeyId,
        ownerSid: old.ownerSid,
      ),
      trust ?? store.trustedOperational.foundation.trust,
    );
  }

  Map<String, Object?> profile(int revision, int epoch) => {
    ...f.profile(revision: '$revision'),
    'trustRevision': '$epoch',
  };
  HostTrustRecord trust(int epoch, String status) => HostTrustRecord.fromJson({
    'workspaceId': key.workspaceId,
    'profileId': server,
    'revision': '$epoch',
    'connectionRevision': '1',
    'status': status,
    'key': {
      'format': 'ssh-ed25519',
      'fingerprint':
          'SHA256:${base64.encode(List.filled(32, 0)).replaceAll('=', '')}',
    },
    'createdAt': f.time,
    'updatedAt': f.time,
  });
  final settingsPayload =
      store.trustedOperational.rows['StoredSettings']!.single.payload;
  if (store.state.storeRevision == '0') {
    await store.commitTrustedFoundation(
      next('profiles.create', profile: profile(1, 1)),
    );
  }
  check(store.state.storeRevision == '1' && !store.isAutomationReady);
  final initialProfile = (await db.storedProfiles.where().findAll()).single;
  final nativeProfileId = initialProfile.id;
  final confirm = next(
    'servers.trust.confirm',
    profile: profile(2, 2),
    trust: {server: trust(2, 'trusted')},
  );
  if (mode == 'write-overflow') {
    final before = store.trustedOperational.preservationDigest();
    await refusal(
      () => store.commitTrustedFoundation(confirm),
      'RESOURCE_LIMIT',
    );
    check(
      store.isTrustedSnapshotLoaded &&
          store.trustedOperational.preservationDigest() == before,
    );
    check(await db.storedReceipts.count() == 1);
    return;
  }
  if (mode == 'write-race' || mode == 'write-queue') {
    final count = mode == 'write-queue' ? 33 : 2;
    final results = await Future.wait([
      for (var i = 0; i < count; i++)
        store
            .commitTrustedFoundation(confirm)
            .then<String>(
              (_) => 'ok',
              onError: (Object error) => (error as StateError).message,
            ),
    ]);
    check(results.first == 'ok');
    check(
      results.where((s) => s == 'REVISION_CONFLICT').length ==
          (count == 33 ? 31 : 1),
    );
    if (count == 33) check(results.last == 'RESOURCE_LIMIT');
  } else if (mode == 'write-corrupt') {
    await db.writeTxn(
      () => db.storedAutomationEvents.put(
        StoredAutomationEvent()
          ..entityId = '${id(99)}:1'
          ..payload = '{}',
      ),
    );
    await refusal(
      () => store.commitTrustedFoundation(confirm),
      'STORAGE_BLOCKED',
    );
    check(!store.isTrustedSnapshotLoaded);
    await refusal(() async => store.state, 'STORAGE_BLOCKED');
    // The commit really happened, but incomplete readback cannot publish RAM.
    check((await db.storedReceipts.where().findAll()).length == 2);
    check(
      jsonDecode(
            (await db.storedWorkspaces.get(1))!.payload,
          )['storeRevision'] ==
          '2',
    );
    return;
  } else {
    await store.commitTrustedFoundation(confirm);
  }
  check(
    (await db.storedProfiles.where().findAll()).single.id == nativeProfileId,
  );
  final trustId =
      store.trustedOperational.rows['StoredHostTrust']!.single.nativeId;
  final createReceipt = store.trustedOperational.rows['StoredReceipt']!.first;
  await store.commitTrustedFoundation(
    next(
      'servers.trust.revoke',
      profile: profile(3, 3),
      trust: {server: trust(3, 'revoked')},
    ),
  );
  check(
    store.trustedOperational.rows['StoredHostTrust']!.single.nativeId ==
        trustId,
  );
  // A repeat revoke is another durable mutation; credential replacement leaves
  // trust bytes unchanged and remains a real user DPAPI blob.
  await store.commitTrustedFoundation(
    next(
      'servers.trust.revoke',
      profile: profile(4, 4),
      trust: {server: trust(4, 'revoked')},
    ),
  );
  final retainedTrust =
      store.trustedOperational.rows['StoredHostTrust']!.single.payload;
  final wrapped = await custody.wrapCredential(
    key.workspaceId,
    server,
    f.credentialId,
    {
      'action': 'replace',
      'kind': 'password',
      'password': 'disposable-trusted-writer',
    },
  );
  await store.commitTrustedFoundation(
    next(
      'profiles.update',
      profile: {
        ...profile(5, 4),
        'credentialRef': f.credentialId,
        'credentialRevision': '2',
      },
      credential: {
        'id': f.credentialId,
        'revision': '2',
        'profileId': server,
        'kind': 'password',
        'protectedBlob': wrapped,
        'createdAt': f.time,
        'updatedAt': f.time,
      },
    ),
  );
  check(
    store.trustedOperational.rows['StoredHostTrust']!.single.payload ==
        retainedTrust,
  );
  final receiptAfter = store.trustedOperational.rows['StoredReceipt']!.first;
  check(
    receiptAfter.nativeId == createReceipt.nativeId &&
        receiptAfter.payload == createReceipt.payload,
  );
  // Metadata update preserves credential and trust; deletion removes all3 rows
  // atomically and permanently retains every historical receipt.
  await store.commitTrustedFoundation(
    next(
      'profiles.update',
      profile: {
        ...store.state.profiles[server]!.toJson(),
        'revision': '6',
        'name': 'Metadata 🐧',
      },
    ),
  );
  await store.commitTrustedFoundation(
    next('profiles.delete', delete: true, trust: {}),
  );
  check(store.state.storeRevision == '7' && store.state.receipts.length == 7);
  check(
    store.trustedOperational.foundation.trust.isEmpty &&
        store.state.credentials.isEmpty,
  );
  await refusal(
    () => store.commitTrustedFoundation(
      next('profiles.create', profile: profile(1, 1)),
    ),
    'ALREADY_EXISTS',
  );
  check(store.isTrustedSnapshotLoaded);
  check(
    store.trustedOperational.rows['StoredSettings']!.single.payload ==
        settingsPayload,
  );
  final tampered = next('profiles.create', profile: profile(1, 1));
  final doc = tampered.foundation.toJson();
  final first = (doc['receipts'] as Map).values.first as Map;
  first['inputDigest'] = base64.encode(List.filled(32, 9));
  final changedHistory = HostTrustState.fromRecords(
    WorkspaceState.fromTrustedJson(
      doc,
      workspaceId: key.workspaceId,
      receiptKeyId: key.receiptKeyId,
      ownerSid: key.ownerSid,
    ),
    {},
  );
  await refusal(
    () => store.commitTrustedFoundation(changedHistory),
    'STORAGE_BLOCKED',
  );
  check(store.isTrustedSnapshotLoaded && store.state.storeRevision == '7');
}
