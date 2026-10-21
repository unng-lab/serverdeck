import 'dart:io';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/mcp/grants.dart';
import 'package:serverdeck_locald/storage/foundation_snapshot.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_windows/mcp_credential_files.dart';

import '../automation/snapshot_test.dart' as g;
import 'operational_open_scenarios.dart' show refusal;
import 'operational_snapshot_child.dart' show check, sameJson;

const grantBoundaryModes = {
  'grant-empty',
  'grant-count',
  'grant-receipts',
  'grant-id-limit',
  'grant-receipt-id-limit',
};

void prepareGrantBoundaryGraph(
  Map<String, List<Map<String, Object?>>> data,
  String mode,
  KeyCustody custody,
  ReceiptKeyMaterial key,
) {
  if (!grantBoundaryModes.contains(mode)) return;
  for (final group in data.values) {
    group.clear();
  }
  if (mode == 'grant-empty') return;
  const timestamp = '2026-10-21T10:00:00.000Z';
  final count = mode == 'grant-count' ? 32 : 1;
  for (var n = 0; n < count; n++) {
    final input = grantCreate(100 + n, 101 + n);
    final command = OwnerGrantCommand.parse('grant.create', input);
    final digest = base64
        .decode(custody.receiptDigestSync(key, command.canonicalRequest))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    data['grants']!.add({
      'workspaceId': key.workspaceId,
      'id': g.id(101 + n),
      'label': input['label'],
      'revision': mode == 'grant-receipts' ? 10000 : 1,
      'scopes': ['author'],
      'serverIds': <String>[],
      'createdAt': timestamp,
      'issuedAt': timestamp,
      'expiresAt': '2026-10-21T18:00:00.000Z',
      'revokedAt': null,
      'secretRef': g.id(600 + n),
    });
    data['receipts']!.add({
      'workspaceId': key.workspaceId,
      'requestId': g.id(100 + n),
      'originGrantId': null,
      'objectGrantId': null,
      'canonicalDigest': digest,
      'operation': 'grant.create',
      'result': {'grantId': g.id(101 + n), 'revision': 1},
      'createdAt': timestamp,
    });
  }
  if (mode == 'grant-receipts') {
    for (var r = 2; r <= 10000; r++) {
      data['receipts']!.add({
        'workspaceId': key.workspaceId,
        'requestId': g.id(1000 + r),
        'originGrantId': null,
        'objectGrantId': null,
        'canonicalDigest': '0' * 64,
        'operation': 'grant.replace',
        'result': {'grantId': g.id(101), 'revision': r},
        'createdAt': timestamp,
      });
    }
  }
}

Future<void> verifyNativeGrantBoundaries(
  StateStore store,
  String mode,
  McpCredentialFiles files,
) async {
  check(grantBoundaryModes.contains(mode));
  final service = OwnerGrantService(
    store,
    clock: () => DateTime.utc(2026, 11, 30),
  );
  final before = store.operational;
  if (mode == 'grant-empty') {
    check(
      store.state.profiles.isEmpty &&
          store.state.receipts.isEmpty &&
          store.state.storeRevision == '0',
    );
    final ack = await service.submitOwner(
      'grant.create',
      grantCreate(100, 101),
    );
    sameJson({'grantId': g.id(101), 'revision': 1}, ack, 'empty-author');
    await service.submitOwner('grant.create', {
      ...grantCreate(102, 103),
      'scopes': <String>[],
    });
    check(store.operational.automation.grants.length == 2);
    check(store.state.storeRevision == '0' && store.state.receipts.isEmpty);
    await refusal(
      () => service.submitOwner('grant.create', {
        ...grantCreate(104, 105),
        'scopes': ['read'],
        'serverIds': [g.id(999)],
      }),
      'FORBIDDEN',
    );
    check(store.isAutomationReady);
    stdout.writeln(
      'ACTUAL_EMPTY_FOUNDATION_AUTHOR_AND_EMPTY_SCOPE_GRANTS_PROVED',
    );
    return;
  }
  final count = credentialFiles(files);
  await refusal(
    () => service.submitOwner('grant.create', grantCreate(500, 501)),
    'RESOURCE_LIMIT',
  );
  check(credentialFiles(files) == count && store.isAutomationReady);
  baselineRetained(before, store.operational);
  sameJson(
    {'grantId': g.id(101), 'revision': 1},
    await service.submitOwner('grant.create', grantCreate(100, 101)),
    'quota-replay',
  );
  check(credentialFiles(files) == count);
  if (mode == 'grant-count' || mode == 'grant-id-limit') {
    await service.submitOwner('grant.replace', {
      ...grantCreate(510, 101),
      'expectedRevision': 1,
    });
    await service.submitOwner('grant.revoke', {
      'requestId': g.id(511),
      'grantId': g.id(101),
      'expectedRevision': 2,
    });
    check(
      store.operational.automation.grants.length ==
          (mode == 'grant-count' ? 32 : 1),
    );
  } else {
    await refusal(
      () => service.submitOwner('grant.replace', {
        ...grantCreate(510, 101),
        'expectedRevision': mode == 'grant-receipts' ? 10000 : 1,
      }),
      'RESOURCE_LIMIT',
    );
  }
  stdout.writeln('ACTUAL_NATIVE_GRANT_RECEIPT_ID_QUOTA_REPLAY_PROVED');
}

Map<String, Object?> grantCreate(int request, int grant) => {
  'requestId': g.id(request),
  'grantId': g.id(grant),
  'label': 'Synthetic owner grant',
  'scopes': ['author'],
  'serverIds': <String>[],
};

Future<Object?> outcome(Future<Object?> future) async {
  try {
    return await future;
  } on StateError catch (e) {
    return e.message;
  }
}

void baselineRetained(
  OperationalSnapshot baseline,
  OperationalSnapshot current,
) {
  check(baseline.foundation.rows.digest() == current.foundation.rows.digest());
  for (final group in baseline.rows.entries) {
    final retained = {for (final r in current.rows[group.key]!) r.nativeId: r};
    for (final old in group.value) {
      final actual = retained[old.nativeId];
      check(
        actual != null &&
            actual.entityId == old.entityId &&
            actual.payload == old.payload,
      );
    }
  }
}

int credentialFiles(McpCredentialFiles files) {
  final directory = Directory(p.join(files.directory, 'mcp-credentials'));
  return directory.existsSync()
      ? directory
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .length
      : 0;
}

Future<StateStore> verifyNativeGrantTransactions(
  StateStore initial,
  Future<StateStore> Function() reopen,
  McpCredentialFiles files,
) async {
  var store = initial;
  var now = DateTime.utc(2026, 10, 21, 11);
  OwnerGrantService service() => OwnerGrantService(store, clock: () => now);
  final original = store.operational;
  final foundation = original.foundation.rows.digest();
  try {
    final create = grantCreate(100, 101);
    final first = service().submitOwner('grant.create', create);
    final duplicate = service().submitOwner('grant.create', {
      ...create,
      'lifetimeSeconds': 28800,
    });
    check(identical(first, duplicate));
    await refusal(
      () => service().submitOwner('grant.create', {
        ...create,
        'label': 'different',
      }),
      'IDEMPOTENCY_CONFLICT',
    );
    final firstAck = await first;
    sameJson({'grantId': g.id(101), 'revision': 1}, firstAck, 'grant-create');
    check(identical(firstAck, await duplicate));
    try {
      firstAck['revision'] = 99;
      throw StateError('MUTABLE_ACK');
    } on UnsupportedError {
      /* closed result */
    }
    final created = store.operational.automation.grants[g.id(101)]!;
    check(
      created.policy.serverIds.isEmpty &&
          created.policy.scopes.single.name == 'author',
    );
    check(created.issuedAt == now && created.createdAt == now);
    final count = credentialFiles(files);
    sameJson(
      firstAck,
      await service().submitOwner('grant.create', create),
      'grant-replay',
    );
    check(credentialFiles(files) == count);
    await refusal(
      () => service().submitOwner('grant.create', grantCreate(102, 101)),
      'REVISION_CONFLICT',
    );
    await refusal(
      () => service().submitOwner('grant.replace', {
        ...grantCreate(103, 101),
        'expectedRevision': 9,
      }),
      'REVISION_CONFLICT',
    );
    await refusal(
      () => service().submitOwner('grant.create', {
        ...grantCreate(104, 105),
        'scopes': ['read'],
        'serverIds': [g.id(999)],
      }),
      'FORBIDDEN',
    );
    await refusal(
      () => service().submitOwner('grant.create', {
        ...grantCreate(106, 107),
        'requestId': original.foundation.state.receipts.keys.first,
      }),
      'IDEMPOTENCY_CONFLICT',
    );
    final foreign = original.automation.receipts.values.firstWhere(
      (r) => r.originGrantId != null,
    );
    await refusal(
      () => service().submitOwner('grant.create', {
        ...grantCreate(108, 109),
        'requestId': foreign.requestId,
      }),
      'FORBIDDEN',
    );
    check(credentialFiles(files) == count && store.isAutomationReady);
    now = DateTime.utc(2026, 11, 30, 12);
    check(!created.isCurrentAt(now));
    final replace = {
      ...grantCreate(110, 101),
      'expectedRevision': 1,
      'label': 'Renewed after original thirty days',
    };
    final replacedAck = await service().submitOwner('grant.replace', replace);
    sameJson(
      {'grantId': g.id(101), 'revision': 2},
      replacedAck,
      'grant-replace',
    );
    final replaced = store.operational.automation.grants[g.id(101)]!;
    check(
      replaced.createdAt == created.createdAt &&
          replaced.issuedAt == now &&
          replaced.secretRef != created.secretRef,
    );
    final rotated = await files.readLookupForRecovery(g.id(101));
    check(rotated!.binding.secretRef == replaced.secretRef && !rotated.revoked);
    now = DateTime.utc(2026, 10, 1); // persisted floor, not backwards issuance.
    final revokedAck = await service().submitOwner('grant.revoke', {
      'requestId': g.id(111),
      'grantId': g.id(101),
      'expectedRevision': 2,
    });
    sameJson({'grantId': g.id(101), 'revision': 3}, revokedAck, 'grant-revoke');
    final revoked = store.operational.automation.grants[g.id(101)]!;
    check(
      revoked.revokedAt == replaced.issuedAt &&
          revoked.secretRef == replaced.secretRef,
    );
    await refusal(() => files.readForBridge(g.id(101)), 'FORBIDDEN');
    final afterRevoke = credentialFiles(files);
    sameJson(
      firstAck,
      await service().submitOwner('grant.create', create),
      'old-create-after-revoke',
    );
    sameJson(
      replacedAck,
      await service().submitOwner('grant.replace', replace),
      'old-replace-after-revoke',
    );
    check((await files.readLookupForRecovery(g.id(101)))!.revoked);
    check(credentialFiles(files) == afterRevoke);
    await refusal(
      () => service().submitOwner('grant.replace', {
        ...grantCreate(112, 101),
        'expectedRevision': 3,
      }),
      'REVISION_CONFLICT',
    );
    await refusal(
      () => service().submitOwner('grant.revoke', {
        'requestId': g.id(113),
        'grantId': g.id(101),
        'expectedRevision': 3,
      }),
      'REVISION_CONFLICT',
    );
    await service().submitOwner('grant.create', grantCreate(120, 121));
    final results = await Future.wait([
      outcome(
        service().submitOwner('grant.replace', {
          ...grantCreate(122, 121),
          'expectedRevision': 1,
        }),
      ),
      outcome(
        service().submitOwner('grant.replace', {
          ...grantCreate(123, 121),
          'expectedRevision': 1,
        }),
      ),
    ]);
    check(results.first is Map && results.last == 'REVISION_CONFLICT');
    final queued = [
      for (var i = 0; i < 32; i++)
        outcome(
          service().submitOwner('grant.replace', {
            ...grantCreate(200 + i, 121),
            'expectedRevision': 1,
          }),
        ),
    ];
    await refusal(
      () => service().submitOwner('grant.replace', {
        ...grantCreate(240, 121),
        'expectedRevision': 1,
      }),
      'RESOURCE_LIMIT',
    );
    check((await Future.wait(queued)).every((r) => r == 'REVISION_CONFLICT'));
    check(store.isAutomationReady);
    baselineRetained(original, store.operational);
    final beforeClose = store.operational;
    await store.close();
    store = await reopen();
    baselineRetained(beforeClose, store.operational);
    sameJson(
      firstAck,
      await service().submitOwner('grant.create', create),
      'restart-old-create',
    );
    sameJson(
      replacedAck,
      await service().submitOwner('grant.replace', replace),
      'restart-old-replace',
    );
    check((await files.readLookupForRecovery(g.id(101)))!.revoked);
    final draining = service().submitOwner(
      'grant.create',
      grantCreate(250, 251),
    );
    final closing = store.close();
    await refusal(
      () => service().submitOwner('grant.create', grantCreate(252, 253)),
      'NOT_READY',
    );
    final drainedAck = await draining;
    await closing;
    sameJson(
      {'grantId': g.id(251), 'revision': 1},
      drainedAck,
      'shutdown-drain',
    );
    store = await reopen();
    check(store.operational.automation.grants.containsKey(g.id(251)));
    check(store.operational.foundation.rows.digest() == foundation);
    baselineRetained(original, store.operational);
    try {
      store.operational.rows['grants']!.clear();
      throw StateError('MUTABLE_RAW_ROWS');
    } on UnsupportedError {
      /* exact rows are immutable */
    }
    stdout.writeln(
      'ACTUAL_GRANT_NATIVE_CAS_RECEIPT_REPLAY_REVOKE_DRAIN_PROVED',
    );
    return store;
  } catch (_) {
    if (!identical(store, initial)) await store.close();
    rethrow;
  }
}
