import 'dart:convert';

import 'package:serverdeck_locald/automation/snapshot.dart';
import 'package:serverdeck_locald/storage/host_trust_models.dart';
import 'package:serverdeck_locald/storage/models.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:test/test.dart';

import '../../../serverdeck_protocol/test/automation_plan_records_test.dart'
    as p;
import '../../../serverdeck_protocol/test/trusted_target_records_test.dart'
    as targets;
import 'snapshot_test.dart' as fixture;

HostTrustState foundation({int revision = 2}) {
  final data = fixture.foundation().toJson();
  data['schemaVersion'] = 3;
  data['storeRevision'] = '$revision';
  final profile = ((data['profiles'] as Map)[p.server] as Map<String, Object?>);
  profile['revision'] = '$revision';
  profile['connectionRevision'] = '1';
  profile['trustRevision'] = '$revision';
  final receipts = data['receipts'] as Map<String, Object?>;
  (receipts[fixture.id(42)] as Map<String, Object?>)['operation'] =
      'servers.trust.confirm';
  for (var n = 3; n <= revision; n++) {
    receipts[fixture.id(40 + n)] = {
      ...(receipts[fixture.id(42)] as Map<String, Object?>),
      'requestId': fixture.id(40 + n),
      'result': {
        'entityId': p.server,
        'entityRevision': '$n',
        'storeRevision': '$n',
        'deleted': false,
      },
    };
  }
  final state = WorkspaceState.fromTrustedJson(
    data,
    workspaceId: p.workspace,
    receiptKeyId: fixture.id(30),
    ownerSid: 'S-1-5-21-1-2-3-1001',
  );
  return HostTrustState.fromRecords(state, {
    p.server: HostTrustRecord.fromJson({
      'workspaceId': p.workspace,
      'profileId': p.server,
      'revision': '$revision',
      'connectionRevision': '1',
      'status': 'trusted',
      'key': {
        'format': 'ssh-ed25519',
        'fingerprint':
            'SHA256:${base64Encode(List.filled(32, 0)).replaceAll('=', '')}',
      },
      'createdAt': p.created,
      'updatedAt': p.created,
    }),
  });
}

Future<Map<String, List<AutomationSnapshotRow>>> rows() async {
  final revision = await p.revision();
  final plan = await targets.plan(revision);
  Map<String, Object?> receipt(
    int request,
    String operation,
    Map<String, Object?> result,
  ) => {
    'workspaceId': p.workspace,
    'requestId': fixture.id(request),
    'originGrantId': null,
    'objectGrantId': null,
    'canonicalDigest': p.hash,
    'operation': operation,
    'result': result,
    'createdAt': p.created,
  };
  return fixture.rows({
    for (final name in [
      'grants',
      'delegations',
      'approvals',
      'jobs',
      'desired',
      'events',
    ])
      name: <Map<String, Object?>>[],
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
    'revisions': [revision.toJson()],
    'plans': [plan],
    'receipts': [
      receipt(14, 'profile.create', {
        'profileId': p.profile,
        'revision': 1,
        'digest': revision.key.bodyDigest,
      }),
      receipt(6, 'plan.create', {
        'planId': p.planId,
        'planDigest': plan['digest'],
      }),
    ],
  });
}

void main() {
  test(
    'explicit schema3 graph loads independent epochs while old path refuses',
    () async {
      final trust = foundation(), input = await rows();
      final graph = await AutomationSnapshot.loadTrusted(
        foundation: trust,
        collections: input,
      );
      expect(graph.plans[p.planId]!.connectionRevision, '1');
      expect(graph.plans[p.planId]!.trustRevision, '2');
      await expectLater(
        AutomationSnapshot.load(
          foundation: trust.foundation,
          collections: input,
        ),
        throwsStateError,
      );
      await expectLater(
        AutomationSnapshot.load(
          foundation: fixture.foundation(),
          collections: input,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'later trust does not corrupt retained history or canonical digest',
    () async {
      final input = await rows();
      final before = await AutomationSnapshot.loadTrusted(
        foundation: foundation(),
        collections: input,
      );
      final after = await AutomationSnapshot.loadTrusted(
        foundation: foundation(revision: 3),
        collections: input,
      );
      expect(after.plans[p.planId]!.toJson(), before.plans[p.planId]!.toJson());
      expect(after.plans[p.planId]!.trustRevision, '2');
    },
  );

  test(
    'schema3 loader captures all rows before awaits and validates references',
    () async {
      final input = await rows();
      final pending = AutomationSnapshot.loadTrusted(
        foundation: foundation(),
        collections: input,
      );
      input['plans']!.clear();
      input.clear();
      final graph = await pending;
      expect(graph.plans.length, 1);
      expect(() => graph.plans.clear(), throwsUnsupportedError);
      final dangling = await rows();
      dangling['revisions']!.clear();
      await expectLater(
        AutomationSnapshot.loadTrusted(
          foundation: foundation(),
          collections: dangling,
        ),
        throwsStateError,
      );
    },
  );
}
