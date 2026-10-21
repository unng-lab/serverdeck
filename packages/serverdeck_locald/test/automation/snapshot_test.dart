import 'dart:convert';

import 'package:serverdeck_locald/automation/snapshot.dart';
import 'package:serverdeck_locald/storage/models.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:test/test.dart';

import '../../../serverdeck_protocol/test/automation_plan_records_test.dart'
    as p;

String id(int n) =>
    '10000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';
const grantId = '10000000-0000-4000-8000-000000000007';
const delegationId = '10000000-0000-4000-8000-000000000009';
const approvalId = '10000000-0000-4000-8000-00000000000a';
const jobId = '10000000-0000-4000-8000-00000000000b';
const admitted = '2026-10-21T10:00:02.000Z';
const finished = '2026-10-21T10:10:00.000Z';

WorkspaceState foundation() {
  final value = WorkspaceState.empty(
    workspaceId: p.workspace,
    receiptKeyId: id(30),
    ownerSid: 'S-1-5-21-1-2-3-1001',
  ).toJson();
  value['storeRevision'] = '2';
  value['profiles'] = {
    p.server: {
      'id': p.server,
      'revision': '2',
      'name': 'Synthetic',
      'address': 'example.invalid',
      'port': 22,
      'sshUser': 'synthetic',
      'tags': <String>[],
      'credentialRef': null,
      'credentialRevision': '1',
      'connectionRevision': '2',
      'trustRevision': '2',
      'createdAt': p.created,
      'updatedAt': p.created,
    },
  };
  value['receipts'] = {
    for (var n = 1; n <= 2; n++)
      id(40 + n): {
        'requestId': id(40 + n),
        'inputDigest': base64Encode(List.filled(32, 0)),
        'operation': n == 1 ? 'profiles.create' : 'profiles.update',
        'profileId': p.server,
        'result': {
          'entityId': p.server,
          'entityRevision': '$n',
          'storeRevision': '$n',
          'deleted': false,
        },
        'committedAt': p.created,
      },
  };
  return WorkspaceState.fromJson(
    value,
    workspaceId: p.workspace,
    receiptKeyId: id(30),
    ownerSid: 'S-1-5-21-1-2-3-1001',
  );
}

Future<Map<String, List<Map<String, Object?>>>> graph() async {
  final rev = await p.revision();
  final plan = await p.signPlan(
    await p.plan(rev)
      ..['originGrantId'] = grantId,
  );
  plan['serverRevision'] = '2';
  final observed = p.observation()..['targetRevision'] = '2';
  final baseline = await ManagedResourceObservationRecord.fromJson(observed)
      .fingerprint();
  ((plan['baseObservations'] as List).single as Map)['fingerprint'] = baseline;
  final capsule = plan['preflight'] as Map<String, Object?>;
  ((capsule['baseObservations'] as List).single as Map)['fingerprint'] =
      baseline;
  plan['preflightDigest'] = await p.digest(capsule);
  final signed = await p.signPlan(plan);
  plan['digest'] = signed['digest'];
  final authority = <String, Object?>{
    'kind': 'approval',
    'id': approvalId,
    'revision': 1,
  };
  final inputDigest = plan['inputDigest'];
  Map<String, Object?> receipt(
    int request,
    String operation,
    Map<String, Object?> result, {
    String? origin,
    String? object,
    String at = p.created,
  }) => {
    'workspaceId': p.workspace,
    'requestId': id(request),
    'originGrantId': origin,
    'objectGrantId': object,
    'canonicalDigest': p.hash,
    'operation': operation,
    'result': result,
    'createdAt': at,
  };
  return {
    'grants': [
      {
        'workspaceId': p.workspace,
        'id': grantId,
        'label': 'Synthetic client',
        'revision': 1,
        'scopes': ['read', 'plan', 'apply', 'author'],
        'serverIds': [p.server],
        'createdAt': p.created,
        'issuedAt': p.created,
        'expiresAt': '2026-10-21T18:00:00.000Z',
        'revokedAt': null,
        'secretRef': id(8),
      },
    ],
    'delegations': [
      {
        'workspaceId': p.workspace,
        'id': delegationId,
        'grantId': grantId,
        'revision': 1,
        'serverIds': [p.server],
        'profileRevisions': [rev.key.toJson()],
        'predicates': {
          'greeting': {
            'type': 'enum',
            'values': ['hello'],
          },
        },
        'expiresAt': '2026-10-21T11:00:00.000Z',
        'revokedAt': null,
      },
    ],
    'profiles': [
      {
        'workspaceId': p.workspace,
        'id': p.profile,
        'name': 'Synthetic profile',
        'description': '',
        'headRevision': 1,
        'archived': false,
      },
    ],
    'revisions': [rev.toJson()],
    'plans': [plan],
    'approvals': [
      {
        'workspaceId': p.workspace,
        'id': approvalId,
        'planId': p.planId,
        'planDigest': plan['digest'],
        'grantId': grantId,
        'createdAt': p.created,
        'expiresAt': p.expires,
        'state': 'consumed',
        'jobId': jobId,
      },
    ],
    'jobs': [
      {
        'workspaceId': p.workspace,
        'id': jobId,
        'requestId': id(19),
        'immutablePlanId': p.planId,
        'planDigest': plan['digest'],
        'profileId': p.profile,
        'profileRevision': 1,
        'profileDigest': rev.key.bodyDigest,
        'grantId': grantId,
        'authorityRef': authority,
        'hostAttemptId': id(21),
        'state': 'succeeded',
        'nextSequence': 3,
        'cancelRequested': false,
        'createdAt': admitted,
        'updatedAt': finished,
        'outcome': {
          'effects': 'confirmed',
          'checks': [
            {
              'checkId': 'written',
              'stepId': 'write',
              'result': 'passed',
              'safeCode': null,
            },
          ],
          'safeCode': null,
        },
      },
    ],
    'desired': [
      {
        'workspaceId': p.workspace,
        'id': id(20),
        'serverId': p.server,
        'resourceId': 'system.motd',
        'desiredRevision': 1,
        'bodyDigest': rev.key.bodyDigest,
        'inputDigest': inputDigest,
        'lastJobId': jobId,
        'observedRevision': 1,
      },
    ],
    'events': [
      {
        'workspaceId': p.workspace,
        'jobId': jobId,
        'sequence': 1,
        'timestamp': finished,
        'kind': 'state',
        'stepId': null,
        'state': 'succeeded',
        'safeCode': null,
        'checkResult': null,
        'droppedCount': 0,
      },
      {
        'workspaceId': p.workspace,
        'jobId': jobId,
        'sequence': 2,
        'timestamp': finished,
        'kind': 'check',
        'stepId': 'write',
        'state': null,
        'safeCode': null,
        'checkResult': 'passed',
        'droppedCount': 0,
      },
    ],
    'receipts': [
      receipt(12, 'grant.create', {'grantId': grantId, 'revision': 1}),
      receipt(13, 'delegation.create', {
        'delegationId': delegationId,
        'revision': 1,
      }, object: grantId),
      receipt(14, 'profile.create', {
        'profileId': p.profile,
        'revision': 1,
        'digest': rev.key.bodyDigest,
      }),
      receipt(
        6,
        'plan.create',
        {'planId': p.planId, 'planDigest': plan['digest']},
        origin: grantId,
        object: grantId,
      ),
      receipt(17, 'approval.request', {
        'approvalId': approvalId,
        'planId': p.planId,
        'planDigest': plan['digest'],
      }, object: grantId),
      receipt(
        18,
        'approval.decide',
        {
          'approvalId': approvalId,
          'planId': p.planId,
          'planDigest': plan['digest'],
          'decision': 'approved',
        },
        object: grantId,
        at: '2026-10-21T10:00:01.000Z',
      ),
      receipt(
        19,
        'job.apply',
        {
          'jobId': jobId,
          'planId': p.planId,
          'planDigest': plan['digest'],
          'authorityRef': authority,
        },
        object: grantId,
        at: admitted,
      ),
    ],
  };
}

Map<String, List<AutomationSnapshotRow>> rows(
  Map<String, List<Map<String, Object?>>> graph,
) => {
  for (final entry in graph.entries)
    entry.key: [
      for (var i = 0; i < entry.value.length; i++)
        AutomationSnapshotRow(i + 1, switch (entry.key) {
          'revisions' =>
            '${entry.value[i]['profileId']}:${entry.value[i]['revision']}',
          'events' =>
            '${entry.value[i]['jobId']}:${entry.value[i]['sequence']}',
          'receipts' => entry.value[i]['requestId'] as String,
          _ => entry.value[i]['id'] as String,
        }, jsonEncode(entry.value[i])),
    ],
};

Future<AutomationSnapshot> load(
  Map<String, List<Map<String, Object?>>> value,
) =>
    AutomationSnapshot.load(foundation: foundation(), collections: rows(value));
final blocked = throwsA(
  isA<StateError>().having((e) => e.message, 'code', 'STORAGE_BLOCKED'),
);

void main() {
  test('delegation issuance cannot precede any selected revision, including revoked history', () async {
    for (final revoked in [false, true]) {
      for (final at in ['09:59:59.999', '10:00:00.000', '10:00:00.001']) {
        final value = await graph();
        for (final key in ['jobs', 'desired', 'events', 'approvals', 'plans']) {
          value[key]!.clear();
        }
        value['receipts']!.removeWhere(
          (r) => [
            'job.apply',
            'approval.request',
            'approval.decide',
            'plan.create',
          ].contains(r['operation']),
        );
        value['grants']!.single.addAll({
          'createdAt': '2026-10-21T09:00:00.000Z',
          'issuedAt': '2026-10-21T09:00:00.000Z',
        });
        for (final receipt in value['receipts']!) {
          if (receipt['operation'] == 'grant.create') {
            receipt['createdAt'] = '2026-10-21T09:00:00.000Z';
          }
          if (receipt['operation'] == 'delegation.create') {
            receipt['createdAt'] = '2026-10-21T${at}Z';
          }
        }
        if (revoked) {
          value['delegations']!.single.addAll({
            'revision': 2,
            'revokedAt': finished,
          });
          value['receipts']!.add({
            ...value['receipts']!.firstWhere(
              (r) => r['operation'] == 'delegation.create',
            ),
            'requestId': id(99),
            'operation': 'delegation.revoke',
            'createdAt': finished,
            'result': {'delegationId': delegationId, 'revision': 2},
          });
        }
        if (at == '09:59:59.999') {
          await expectLater(load(value), blocked);
        } else {
          expect((await load(value)).delegations.length, 1);
        }
      }
    }
  });
  test('provably applicable grant scopes constrain plan and author creation, older policy remains unknown', () async {
    final planned = await graph();
    for (final name in [
      'delegations',
      'approvals',
      'jobs',
      'desired',
      'events',
    ]) {
      planned[name]!.clear();
    }
    planned['receipts']!.removeWhere(
      (r) => ![
        'grant.create',
        'profile.create',
        'plan.create',
      ].contains(r['operation']),
    );
    planned['grants']!.single['scopes'] = ['read', 'plan'];
    expect((await load(planned)).plans.length, 1);
    planned['grants']!.single['scopes'] = ['read'];
    await expectLater(load(planned), blocked);
    final authored = await graph();
    for (final name in [
      'delegations',
      'plans',
      'approvals',
      'jobs',
      'desired',
      'events',
    ]) {
      authored[name]!.clear();
    }
    authored['receipts']!.removeWhere(
      (r) => !['grant.create', 'profile.create'].contains(r['operation']),
    );
    authored['revisions']!.single['authorGrantId'] = grantId;
    authored['receipts']!.last['originGrantId'] = grantId;
    authored['grants']!.single['scopes'] = ['read'];
    await expectLater(load(authored), blocked);
    authored['grants']!.single.addAll({
      'scopes': ['author'],
      'serverIds': <String>[],
    });
    expect((await load(authored)).revisions.length, 1);
  });
  test('known latest grant issuance expiry bounds history without replaying older epochs', () async {
    final expired = await graph();
    expired['grants']!.single.addAll({
      'createdAt': '2026-10-21T09:00:00.000Z',
      'issuedAt': '2026-10-21T09:00:00.000Z',
      'expiresAt': '2026-10-21T09:05:00.000Z',
    });
    expired['receipts']!.first['createdAt'] = '2026-10-21T09:00:00.000Z';
    await expectLater(load(expired), blocked);
    for (final expiry in [admitted, '2026-10-21T10:00:02.001Z']) {
      final value = await graph();
      value['delegations']!.clear();
      value['receipts']!.removeWhere(
        (r) => r['operation'] == 'delegation.create',
      );
      value['grants']!.single.addAll({
        'createdAt': '2026-10-21T09:55:00.000Z',
        'issuedAt': '2026-10-21T09:55:00.000Z',
        'expiresAt': expiry,
      });
      value['receipts']!.first['createdAt'] = '2026-10-21T09:55:00.000Z';
      if (expiry == admitted) {
        await expectLater(load(value), blocked);
      } else {
        expect((await load(value)).jobs[jobId]!.state, 'succeeded');
      }
    }
  });

  test('delegation expiry respects a provably applicable grant epoch, not later replacement', () async {
    final invalid = await graph();
    invalid['grants']!.single['expiresAt'] = p.expires;
    await expectLater(load(invalid), blocked);
    for (final issued in [p.created, '2026-10-21T10:00:00.001Z']) {
      final value = await graph();
      value['grants']!.single.addAll({
        'revision': 2,
        'issuedAt': issued,
        'expiresAt': DateTime.parse(issued)
            .add(const Duration(minutes: 5))
            .toIso8601String(),
        'secretRef': id(90),
      });
      value['receipts']!.add({
        ...value['receipts']!.first,
        'requestId': id(91),
        'operation': 'grant.replace',
        'createdAt': issued,
        'result': {'grantId': grantId, 'revision': 2},
      });
      // Same-ms replacement order relative to delegation issuance is unknown.
      expect(
        (await load(value)).delegations[delegationId]!.expiresAt
            .toIso8601String(),
        '2026-10-21T11:00:00.000Z',
      );
    }
  });
  test('canonical positive owner consent precedes terminal G revoke while aliases and denial remain history', () async {
    for (final state in ['approved', 'expired', 'denied']) {
      for (final time in [
        '2026-10-21T10:00:00.500Z',
        '2026-10-21T10:00:01.000Z',
        '2026-10-21T10:00:01.500Z',
      ]) {
        final value = await graph();
        value['jobs']!.clear();
        value['desired']!.clear();
        value['events']!.clear();
        value['receipts']!.removeWhere((r) => r['operation'] == 'job.apply');
        value['approvals']!.single.addAll({'state': state, 'jobId': null});
        final decision = value['receipts']!.firstWhere(
          (r) => r['operation'] == 'approval.decide',
        );
        decision['createdAt'] = time;
        if (state == 'denied')
          (decision['result'] as Map)['decision'] = 'denied';
        value['receipts']!.add(
          p.copy(decision)
            ..addAll({'requestId': id(80), 'createdAt': finished}),
        );
        value['grants']!.single.addAll({
          'revision': 2,
          'revokedAt': '2026-10-21T10:00:01.000Z',
        });
        value['receipts']!.add({
          ...value['receipts']!.first,
          'requestId': id(92),
          'operation': 'grant.revoke',
          'createdAt': '2026-10-21T10:00:01.000Z',
          'result': {'grantId': grantId, 'revision': 2},
        });
        if (state != 'denied' && time == '2026-10-21T10:00:01.500Z') {
          await expectLater(load(value), blocked);
        } else {
          expect((await load(value)).approvals[approvalId]!.state, state);
        }
      }
    }
  });
  test('canonical owner delegation/approval issuance respects terminal object G revoke', () async {
    for (final kind in ['delegation', 'approval']) {
      for (final time in [
        p.created,
        '2026-10-21T10:01:00.000Z',
        '2026-10-21T10:02:00.000Z',
      ]) {
        final value = await graph();
        value['jobs']!.clear();
        value['desired']!.clear();
        value['events']!.clear();
        value['receipts']!.removeWhere(
          (r) => ['job.apply', 'approval.decide'].contains(r['operation']),
        );
        if (kind == 'delegation') {
          value['plans']!.clear();
          value['approvals']!.clear();
          value['receipts']!.removeWhere(
            (r) => ['plan.create', 'approval.request'].contains(r['operation']),
          );
          value['receipts']!.firstWhere(
            (r) => r['operation'] == 'delegation.create',
          )['createdAt'] = time;
        } else {
          value['approvals']!.single.addAll({
            'state': 'pending',
            'jobId': null,
            'createdAt': time,
          });
          value['receipts']!.firstWhere(
            (r) => r['operation'] == 'approval.request',
          )['createdAt'] = time;
        }
        value['grants']!.single.addAll({
          'revision': 2,
          'revokedAt': '2026-10-21T10:01:00.000Z',
        });
        value['receipts']!.add({
          ...value['receipts']!.first,
          'requestId': id(92),
          'operation': 'grant.revoke',
          'createdAt': '2026-10-21T10:01:00.000Z',
          'result': {'grantId': grantId, 'revision': 2},
        });
        if (time == '2026-10-21T10:02:00.000Z') {
          await expectLater(load(value), blocked);
        } else {
          expect((await load(value)).jobs, isEmpty);
        }
      }
    }
  });
  test(
    'a grant-origin author mutation cannot occur after its terminal revoke',
    () async {
      final value = await graph();
      for (final name in [
        'delegations',
        'plans',
        'approvals',
        'jobs',
        'desired',
        'events',
      ]) {
        value[name]!.clear();
      }
      final profileReceipt = p.copy(value['receipts']![2])
        ..['originGrantId'] = grantId;
      final grantReceipt = p.copy(value['receipts']!.first)
        ..['createdAt'] = '2026-10-21T09:00:00.000Z';
      value['receipts'] = [grantReceipt, profileReceipt];
      value['revisions']!.single['authorGrantId'] = grantId;
      value['grants']!.single.addAll({
        'createdAt': '2026-10-21T09:00:00.000Z',
        'issuedAt': '2026-10-21T09:00:00.000Z',
        'revision': 2,
        'revokedAt': '2026-10-21T09:30:00.000Z',
      });
      value['receipts']!.add({
        ...grantReceipt,
        'requestId': id(92),
        'operation': 'grant.revoke',
        'createdAt': '2026-10-21T09:30:00.000Z',
        'result': {'grantId': grantId, 'revision': 2},
      });
      await expectLater(load(value), blocked);
    },
  );
  test(
    'revoke-only delegation revision is never historical issued authority',
    () async {
      final value = await graph();
      final authority = <String, Object?>{
        'kind': 'delegation',
        'id': delegationId,
        'revision': 1,
      };
      value['jobs']!.single['authorityRef'] = authority;
      value['approvals']!.single.addAll({'state': 'approved', 'jobId': null});
      (value['receipts']!.last['result'] as Map)['authorityRef'] = authority;
      value['delegations']!.single.addAll({
        'revision': 2,
        'revokedAt': finished,
      });
      value['receipts']!.add({
        ...value['receipts']![1],
        'requestId': id(93),
        'operation': 'delegation.revoke',
        'createdAt': finished,
        'result': {'delegationId': delegationId, 'revision': 2},
      });
      expect((await load(value)).jobs[jobId]!.authority.revision, 1);
      authority['revision'] = 2;
      await expectLater(load(value), blocked);
    },
  );

  test('terminal grant revoke bounds admission for both owner apply authority paths', () async {
    for (final delegated in [false, true]) {
      for (final revokedAt in [
        '2026-10-21T10:00:01.000Z',
        admitted,
        '2026-10-21T10:00:03.000Z',
      ]) {
        final value = await graph();
        if (delegated) {
          final authority = <String, Object?>{
            'kind': 'delegation',
            'id': delegationId,
            'revision': 1,
          };
          value['jobs']!.single['authorityRef'] = authority;
          value['approvals']!.single.addAll({
            'state': 'approved',
            'jobId': null,
          });
          (value['receipts']!.last['result'] as Map)['authorityRef'] =
              authority;
        }
        value['grants']!.single.addAll({'revision': 2, 'revokedAt': revokedAt});
        value['receipts']!.add({
          ...value['receipts']!.first,
          'requestId': id(92),
          'operation': 'grant.revoke',
          'createdAt': revokedAt,
          'result': {'grantId': grantId, 'revision': 2},
        });
        if (revokedAt.compareTo(admitted) < 0) {
          await expectLater(load(value), blocked);
        } else {
          expect((await load(value)).jobs[jobId]!.state, 'succeeded');
        }
      }
    }
  });
  test(
    'admission time must lie within the actual approval or delegation lifetime',
    () async {
      final value = await graph();
      value['approvals']!.single['expiresAt'] = '2026-10-21T10:00:01.500Z';
      await expectLater(load(value), blocked);
      final delegated = await graph();
      final authority = {
        'kind': 'delegation',
        'id': delegationId,
        'revision': 1,
      };
      delegated['jobs']!.single['authorityRef'] = authority;
      delegated['approvals']!.single.addAll({
        'state': 'approved',
        'jobId': null,
      });
      (delegated['receipts']!.last['result'] as Map)['authorityRef'] =
          authority;
      // Keep plan admission independently valid so the delegation boundary is tested.
      delegated['jobs']!.single['createdAt'] = '2026-10-21T10:04:59.999Z';
      delegated['receipts']![1]['createdAt'] = '2026-10-21T09:59:59.999Z';
      delegated['grants']!.single.addAll({
        'createdAt': '2026-10-21T09:59:59.999Z',
        'issuedAt': '2026-10-21T09:59:59.999Z',
      });
      delegated['receipts']!.first['createdAt'] = '2026-10-21T09:59:59.999Z';
      delegated['delegations']!.single['expiresAt'] =
          '2026-10-21T10:04:59.999Z';
      delegated['receipts']!.last['createdAt'] = '2026-10-21T10:04:59.999Z';
      await expectLater(load(delegated), blocked);
    },
  );
  test(
    'same-time revision chain and later archive preserve old exact job tuple',
    () async {
      final value = await graph();
      final first = value['revisions']!.single;
      for (var revision = 2; revision <= 3; revision++) {
        value['revisions']!.add({
          ...first,
          'revision': revision,
          'parentRevision': revision - 1,
        });
        value['receipts']!.add({
          ...value['receipts']![2],
          'requestId': id(100 + revision),
          'operation': 'profile.update',
          'result': {
            'profileId': p.profile,
            'revision': revision,
            'digest': first['digest'],
          },
        });
      }
      value['profiles']!.single.addAll({'headRevision': 3, 'archived': true});
      value['receipts']!.add({
        ...value['receipts']![2],
        'requestId': id(104),
        'operation': 'profile.archive',
        'result': {'profileId': p.profile, 'revision': 3, 'archived': true},
      });
      final snapshot = await load(value);
      expect(snapshot.jobs[jobId]!.profileKey.revision, 1);
      expect(snapshot.profiles[p.profile]!.headRevision, 3);
      value['revisions']!.removeAt(1);
      await expectLater(load(value), blocked);
    },
  );

  test('deleted server history resolves exact foundation deletion receipt only', () async {
    final value = await graph(), doc = foundation().toJson();
    doc['profiles'] = <String, Object?>{};
    doc['storeRevision'] = '3';
    (doc['receipts'] as Map<String, Object?>)[id(43)] = {
      'requestId': id(43),
      'inputDigest': base64Encode(List.filled(32, 0)),
      'operation': 'profiles.delete',
      'profileId': p.server,
      'result': {
        'entityId': p.server,
        'entityRevision': '2',
        'storeRevision': '3',
        'deleted': true,
      },
      'committedAt': finished,
    };
    WorkspaceState parse() => WorkspaceState.fromJson(
      doc,
      workspaceId: p.workspace,
      receiptKeyId: id(30),
      ownerSid: 'S-1-5-21-1-2-3-1001',
    );
    expect(
      (await AutomationSnapshot.load(
        foundation: parse(),
        collections: rows(value),
      )).jobs.length,
      1,
    );
    // A different deleted identity is not proof that this target ever existed.
    final deletion = (doc['receipts'] as Map)[id(43)] as Map;
    deletion['profileId'] = id(99);
    (deletion['result'] as Map)['entityId'] = id(99);
    await expectLater(
      AutomationSnapshot.load(foundation: parse(), collections: rows(value)),
      blocked,
    );
  });

  test('events may arrive unordered with sequence gaps, but identity and time bind', () async {
    final value = await graph();
    value['jobs']!.single['nextSequence'] = 5;
    value['events']!.last['sequence'] = 4;
    value['events'] = value['events']!.reversed.toList();
    expect((await load(value)).events.length, 2);
    value['events']!.first['timestamp'] = '2026-10-21T10:10:00.001Z';
    await expectLater(load(value), blocked);
  });
  test(
    'captures all rows before awaits and supports fresh empty automation',
    () async {
      final value = rows(await graph());
      final pending = AutomationSnapshot.load(
        foundation: foundation(),
        collections: value,
      );
      for (final rows in value.values) {
        rows.clear();
      }
      expect((await pending).jobs.length, 1);
      final empty = await graph();
      for (final rows in empty.values) {
        rows.clear();
      }
      expect((await load(empty)).grants, isEmpty);
    },
  );

  test('retained grant issuance provenance survives renewal and revoke but rejects shifts', () async {
    for (final replaced in [false, true]) {
      final value = await graph();
      final grant = value['grants']!.single;
      var revision = 1;
      if (replaced) {
        revision++;
        grant.addAll({
          'revision': revision,
          'issuedAt': '2026-11-21T10:00:00.000Z',
          'expiresAt': '2026-12-21T10:00:00.000Z',
          'secretRef': id(90),
        });
        value['receipts']!.add({
          ...value['receipts']!.first,
          'requestId': id(91),
          'operation': 'grant.replace',
          'createdAt': grant['issuedAt'],
          'result': {'grantId': grantId, 'revision': revision},
        });
        expect(
          (await load(value)).grants[grantId]!.issuedAt.toIso8601String(),
          grant['issuedAt'],
        );
      }
      revision++;
      final revokedAt = replaced
          ? '2026-11-21T12:00:00.000Z'
          : '2026-10-21T12:00:00.000Z';
      grant.addAll({'revision': revision, 'revokedAt': revokedAt});
      value['receipts']!.add({
        ...value['receipts']!.first,
        'requestId': id(92),
        'operation': 'grant.revoke',
        'createdAt': revokedAt,
        'result': {'grantId': grantId, 'revision': revision},
      });
      expect((await load(value)).grants[grantId]!.revokedAt, isNotNull);
      final issued = DateTime.parse(grant['issuedAt'] as String)
          .add(const Duration(hours: 1));
      grant['issuedAt'] = issued.toIso8601String();
      grant['expiresAt'] = issued
          .add(const Duration(hours: 8))
          .toIso8601String();
      await expectLater(load(value), blocked);
    }
  });

  test(
    'delegation authority loads history without rerunning current grant scope',
    () async {
      final value = await graph();
      final authority = {
        'kind': 'delegation',
        'id': delegationId,
        'revision': 1,
      };
      value['jobs']!.single['authorityRef'] = authority;
      value['approvals']!.single.addAll({'state': 'approved', 'jobId': null});
      (value['receipts']!.last['result'] as Map)['authorityRef'] = authority;
      final grant = value['grants']!.single;
      grant.addAll({
        'revision': 2,
        'issuedAt': '2026-11-21T10:00:00.000Z',
        'expiresAt': '2026-11-21T18:00:00.000Z',
        'secretRef': id(90),
        'scopes': ['author'],
        'serverIds': <String>[],
      });
      value['receipts']!.add({
        ...value['receipts']!.first,
        'requestId': id(91),
        'operation': 'grant.replace',
        'createdAt': grant['issuedAt'],
        'result': {'grantId': grantId, 'revision': 2},
      });
      expect((await load(value)).jobs[jobId]!.authority.kind, 'delegation');
      (value['delegations']!.single['predicates'] as Map)['greeting'] = {
        'type': 'enum',
        'values': ['another'],
      };
      await expectLater(load(value), blocked);
    },
  );

  test('later consistent aliases preserve canonical decision and admission evidence', () async {
    final value = await graph();
    final decision = p.copy(value['receipts']![5])
      ..addAll({'requestId': id(80), 'createdAt': finished});
    final apply = p.copy(value['receipts']![6])
      ..addAll({'requestId': id(81), 'createdAt': finished});
    value['receipts']!.addAll([decision, apply]);
    expect((await load(value)).receipts.length, 9);
    value['receipts']!.removeWhere((row) => row['requestId'] == id(18));
    await expectLater(
      load(value),
      blocked,
    ); // late-only consent cannot authorize.
    final missingCanonicalApply = await graph();
    missingCanonicalApply['receipts']!.add(apply);
    missingCanonicalApply['receipts']!.removeWhere(
      (row) => row['requestId'] == id(19),
    );
    await expectLater(load(missingCanonicalApply), blocked);
  });

  test('approval decision union covers pending, denied, expired and approved histories', () async {
    for (final state in ['pending', 'denied', 'expired', 'approved']) {
      final value = await graph();
      value['jobs']!.clear();
      value['desired']!.clear();
      value['events']!.clear();
      value['receipts']!.removeWhere((r) => r['operation'] == 'job.apply');
      value['approvals']!.single.addAll({'state': state, 'jobId': null});
      if (state == 'pending' || state == 'expired') {
        value['receipts']!.removeWhere(
          (r) => r['operation'] == 'approval.decide',
        );
      } else if (state == 'denied') {
        (value['receipts']!.last['result'] as Map)['decision'] = 'denied';
      }
      expect((await load(value)).approvals[approvalId]!.state, state);
      if (state == 'approved' || state == 'denied') {
        value['receipts']!.removeWhere(
          (r) => r['operation'] == 'approval.decide',
        );
        await expectLater(load(value), blocked);
      }
    }
  });

  test(
    'metadata quotas reject before DTO parsing and do not silently prune',
    () async {
      final original = rows(await graph());
      for (final entry in {
        'grants': 33,
        'delegations': 1001,
        'profiles': 251,
        'revisions': 5001,
        'plans': 1001,
        'approvals': 101,
        'jobs': 1251,
        'desired': 6,
        'events': 10001,
        'receipts': 10001,
      }.entries) {
        final value = {
          for (final e in original.entries)
            e.key: List<AutomationSnapshotRow>.of(e.value),
        };
        value[entry.key] = List.generate(
          entry.value,
          (i) => AutomationSnapshotRow(i + 1, 'invalid-$i', '{}'),
        );
        await expectLater(
          AutomationSnapshot.load(foundation: foundation(), collections: value),
          blocked,
        );
      }
    },
  );
  test('full nonempty graph loads as immutable history, owner initiator preserves G', () async {
    final value = await graph();
    final snapshot = await load(value);
    expect(snapshot.jobs[jobId]!.state, 'succeeded');
    expect(
      snapshot.plans[p.planId]!.key,
      snapshot.revisions['${p.profile}:1']!.key,
    );
    expect(snapshot.receipts[id(19)]!.originGrantId, isNull);
    expect(snapshot.receipts[id(19)]!.objectGrantId, grantId);
    expect(() => snapshot.grants.clear(), throwsUnsupportedError);
    expect(snapshot.events.length, 2);
  });

  test('missing any required creation or owner consent receipt rejects whole graph', () async {
    final original = await graph();
    for (var i = 0; i < original['receipts']!.length; i++) {
      final value = await graph();
      value['receipts']!.removeAt(i);
      await expectLater(load(value), blocked);
    }
  });

  test('all dangling foreign and mismatched links reject, despite valid row shapes', () async {
    for (final edit in <void Function(Map<String, List<Map<String, Object?>>>)>[
      (v) => v['grants']!.single['workspaceId'] = id(99),
      (v) => v['delegations']!.single['grantId'] = id(99),
      (v) => v['delegations']!.single['serverIds'] = [id(99)],
      (v) => v['profiles']!.single['headRevision'] = 2,
      (v) => v['revisions']!.clear(),
      (v) => v['approvals']!.single['jobId'] = id(99),
      (v) => v['jobs']!.single['immutablePlanId'] = id(99),
      (v) => v['jobs']!.single['createdAt'] = p.expires,
      (v) => v['desired']!.single['lastJobId'] = id(99),
      (v) => v['desired']!.single['resourceId'] = 'netbird.service',
      (v) => v['events']!.last['stepId'] = 'missing',
      (v) => v['events']!.last['sequence'] = 3,
      (v) => v['events']!.last['timestamp'] = p.created,
      (v) => (v['receipts']![5]['result'] as Map)['decision'] = 'denied',
      (v) => v['receipts']![5]['createdAt'] = p.expires,
    ]) {
      final value = await graph();
      edit(value);
      await expectLater(load(value), blocked);
    }
  });

  test('missing/unknown collections, duplicate native keys and malformed private JSON fail closed', () async {
    final original = rows(await graph());
    for (final edit
        in <void Function(Map<String, List<AutomationSnapshotRow>>)>[
          (v) => v.remove('events'),
          (v) => v['unknown'] = [],
          (v) => v['grants']!.add(v['grants']!.single),
          (v) => v['grants'] = [const AutomationSnapshotRow(0, grantId, '{}')],
          (v) => v['grants'] = [
            const AutomationSnapshotRow(
              1,
              grantId,
              '{"private":"DO_NOT_ECHO","private":2}',
            ),
          ],
        ]) {
      final value = {
        for (final e in original.entries)
          e.key: List<AutomationSnapshotRow>.of(e.value),
      };
      edit(value);
      await expectLater(
        AutomationSnapshot.load(foundation: foundation(), collections: value),
        blocked,
      );
    }
  });
}
