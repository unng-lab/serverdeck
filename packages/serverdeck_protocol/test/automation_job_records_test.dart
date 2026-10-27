import 'dart:convert';

import 'package:serverdeck_protocol/automation/models.dart';
import 'package:test/test.dart';

const workspace = '10000000-0000-4000-8000-000000000001';
const grant = '10000000-0000-4000-8000-000000000002';
const profile = '10000000-0000-4000-8000-000000000003';
const plan = '10000000-0000-4000-8000-000000000004';
const jobId = '10000000-0000-4000-8000-000000000005';
const requestId = '10000000-0000-4000-8000-000000000006';
const authority = '10000000-0000-4000-8000-000000000007';
const other = '10000000-0000-4000-8000-000000000008';
const hash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const created = '2026-10-21T10:00:00.000Z';
const expires = '2026-10-21T10:05:00.000Z';

Map<String, Object?> authorityJson({String kind = 'delegation'}) => {
  'kind': kind,
  'id': authority,
  'revision': 1,
};
Map<String, Object?> outcome(String state) => {
  'effects': state == 'unknown' ? 'uncertain' : 'none',
  'checks': <Object?>[],
  'safeCode': switch (state) {
    'unknown' => 'UNKNOWN_OUTCOME',
    'failed' => 'CHECK_FAILED',
    'cancelled' => 'CANCELLED',
    _ => null,
  },
};
Map<String, Object?> jobJson({
  String state = 'queued',
  String? origin = grant,
}) => {
  'workspaceId': workspace,
  'id': jobId,
  'requestId': requestId,
  'immutablePlanId': plan,
  'planDigest': hash,
  'profileId': profile,
  'profileRevision': 1,
  'profileDigest': hash,
  'grantId': origin,
  'authorityRef': authorityJson(
    kind: origin == null ? 'approval' : 'delegation',
  ),
  'hostAttemptId': other,
  'state': state,
  'nextSequence': 1,
  'cancelRequested': state == 'cancel-requested',
  'createdAt': created,
  'updatedAt': created,
  'outcome': {'succeeded', 'failed', 'cancelled', 'unknown'}.contains(state)
      ? outcome(state)
      : null,
};
Map<String, Object?> approvalJson({String state = 'pending'}) => {
  'workspaceId': workspace,
  'id': authority,
  'planId': plan,
  'planDigest': hash,
  'grantId': grant,
  'createdAt': created,
  'expiresAt': expires,
  'state': state,
  'jobId': state == 'consumed' ? jobId : null,
};
Map<String, Object?> desiredJson() => {
  'workspaceId': workspace,
  'id': other,
  'serverId': grant,
  'resourceId': 'system.motd',
  'desiredRevision': 1,
  'bodyDigest': hash,
  'inputDigest': hash,
  'lastJobId': jobId,
  'observedRevision': null,
};
Map<String, Object?> eventJson({String kind = 'state'}) => {
  'workspaceId': workspace,
  'jobId': jobId,
  'sequence': 1,
  'timestamp': created,
  'kind': kind,
  'stepId': {'step', 'check'}.contains(kind) ? 'motd' : null,
  'state': kind == 'state' ? 'running' : null,
  'safeCode': null,
  'checkResult': kind == 'check' ? 'passed' : null,
  'droppedCount': kind == 'dropped' ? 1 : 0,
};
Map<String, Object?> receiptJson({
  String operation = 'profile.update',
  String? origin = grant,
  String? objectOrigin,
}) => {
  'workspaceId': workspace,
  'requestId': requestId,
  'originGrantId': origin,
  'objectGrantId': objectOrigin,
  'canonicalDigest': hash,
  'operation': operation,
  'createdAt': created,
  'result': switch (operation) {
    'grant.create' ||
    'grant.replace' ||
    'grant.revoke' => {'grantId': grant, 'revision': 1},
    'delegation.create' ||
    'delegation.revoke' => {'delegationId': authority, 'revision': 1},
    'profile.create' ||
    'profile.update' => {'profileId': profile, 'revision': 1, 'digest': hash},
    'profile.archive' => {
      'profileId': profile,
      'revision': 1,
      'archived': true,
    },
    'plan.create' => {'planId': plan, 'planDigest': hash},
    'approval.request' => {
      'approvalId': authority,
      'planId': plan,
      'planDigest': hash,
    },
    'approval.decide' => {
      'approvalId': authority,
      'planId': plan,
      'planDigest': hash,
      'decision': 'approved',
    },
    'job.apply' => {
      'jobId': jobId,
      'planId': plan,
      'planDigest': hash,
      'authorityRef': authorityJson(),
    },
    _ => {'jobId': jobId},
  },
};

void main() {
  test('all record envelopes reject unknown/missing fields, invalid workspace and unsafe error text', () {
    final cases =
        <(Map<String, Object?>, Object Function(Map<String, Object?>))>[
          (jobJson(), AutomationJobRecord.fromJson),
          (approvalJson(), AutomationApprovalRecord.fromJson),
          (desiredJson(), AutomationDesiredStateRecord.fromJson),
          (eventJson(), AutomationJobEventRecord.fromJson),
          (receiptJson(), AutomationMutationReceiptRecord.fromJson),
        ];
    for (final (input, parse) in cases) {
      for (final invalid in [
        {...input, 'private-marker': 'private-marker'},
        {...input}..remove(input.keys.first),
        {...input, 'workspaceId': other.replaceFirst('1', 'A')},
        {...input, 'private-marker': 'private-marker' * 100000},
      ]) {
        try {
          parse(invalid);
          fail('Invalid record accepted');
        } on FormatException catch (error) {
          expect(error.source, isNull);
          expect(error.toString(), isNot(contains('private-marker')));
        }
      }
    }
  });

  test('outcome summaries enforce check IDs, uniqueness, limits and success checks', () {
    Map<String, Object?> check(int index) => {
      'checkId': 'check_$index',
      'stepId': 'motd',
      'result': 'passed',
      'safeCode': null,
    };
    final input = {
      ...jobJson(state: 'succeeded'),
      'outcome': {
        ...outcome('succeeded'),
        'checks': [for (var i = 0; i < 32; i++) check(i)],
      },
    };
    final parsed = AutomationJobRecord.fromJson(input);
    expect(parsed.outcome!.checks.length, 32);
    expect(() => parsed.outcome!.checks.clear(), throwsUnsupportedError);
    for (final checks in [
      [for (var i = 0; i < 33; i++) check(i)],
      [check(0), check(0)],
      [
        {...check(0), 'result': 'failed'},
      ],
      [
        {...check(0), 'safeCode': 'private-marker'},
      ],
      [
        {...check(0), 'checkId': 'bad\u0085id'},
      ],
      [
        {...check(0), 'rawOutput': 'private-marker'},
      ],
    ])
      expect(
        () => AutomationJobRecord.fromJson({
          ...jobJson(state: 'succeeded'),
          'outcome': {...outcome('succeeded'), 'checks': checks},
        }),
        throwsFormatException,
      );
    final changed = AutomationJobRecord.fromJson({
      ...jobJson(state: 'succeeded'),
      'outcome': {...outcome('succeeded'), 'effects': 'confirmed'},
    });
    expect(
      () =>
          AutomationJobRecord.fromJson(jobJson(state: 'succeeded'))
              .validateTransitionTo(changed),
      throwsFormatException,
    );
  });

  test('job and approval references bind full revision identity and original origin', () {
    final job = AutomationJobRecord.fromJson(jobJson());
    final key = AutomationRevisionKey.fromJson({
      'profileId': profile,
      'revision': 1,
      'bodyDigest': hash,
    });
    job.validatePlanIdentity(
      workspaceId: workspace,
      planId: plan,
      digest: hash,
      profileKey: key,
      originGrantId: grant,
    );
    for (final replacement in [
      AutomationRevisionKey.fromJson({
        'profileId': profile,
        'revision': 2,
        'bodyDigest': hash,
      }),
      AutomationRevisionKey.fromJson({
        'profileId': other,
        'revision': 1,
        'bodyDigest': hash,
      }),
    ])
      expect(
        () => job.validatePlanIdentity(
          workspaceId: workspace,
          planId: plan,
          digest: hash,
          profileKey: replacement,
          originGrantId: grant,
        ),
        throwsFormatException,
      );
    expect(
      () => job.validatePlanIdentity(
        workspaceId: other,
        planId: plan,
        digest: hash,
        profileKey: key,
        originGrantId: grant,
      ),
      throwsFormatException,
    );
    expect(
      () => job.validatePlanIdentity(
        workspaceId: workspace,
        planId: other,
        digest: hash,
        profileKey: key,
        originGrantId: grant,
      ),
      throwsFormatException,
    );
    expect(
      () => job.validatePlanIdentity(
        workspaceId: workspace,
        planId: plan,
        digest: hash,
        profileKey: key,
        originGrantId: other,
      ),
      throwsFormatException,
    );
    final approval = AutomationApprovalRecord.fromJson(approvalJson());
    approval.validatePlanIdentity(
      workspaceId: workspace,
      planId: plan,
      digest: hash,
      originGrantId: grant,
      planCreatedAt: DateTime.parse(created),
      planExpiresAt: DateTime.parse(expires),
    );
    expect(
      () => approval.validatePlanIdentity(
        workspaceId: workspace,
        planId: plan,
        digest: hash,
        originGrantId: other,
        planCreatedAt: DateTime.parse(created),
        planExpiresAt: DateTime.parse(expires),
      ),
      throwsFormatException,
    );
    expect(
      () => approval.validatePlanIdentity(
        workspaceId: workspace,
        planId: plan,
        digest: hash,
        originGrantId: grant,
        planCreatedAt: DateTime.parse(created),
        planExpiresAt: DateTime.parse('2026-10-21T10:04:59.999Z'),
      ),
      throwsFormatException,
    );
  });

  test('desired state only binds a successful exact job and event sequences bind the same job', () {
    final desired = AutomationDesiredStateRecord.fromJson(desiredJson());
    final job = AutomationJobRecord.fromJson({
      ...jobJson(state: 'succeeded'),
      'nextSequence': 2,
    });
    desired.validateConfirmedJobIdentity(
      job,
      planId: plan,
      planDigest: hash,
      planServerId: grant,
      resolvedInputDigest: hash,
      ownedResources: {'system.motd'},
    );
    expect(
      () => desired.validateConfirmedJobIdentity(
        AutomationJobRecord.fromJson(jobJson(state: 'failed')),
        planId: plan,
        planDigest: hash,
        planServerId: grant,
        resolvedInputDigest: hash,
        ownedResources: {'system.motd'},
      ),
      throwsFormatException,
    );
    expect(
      () => desired.validateConfirmedJobIdentity(
        job,
        planId: other,
        planDigest: hash,
        planServerId: grant,
        resolvedInputDigest: hash,
        ownedResources: {'system.motd'},
      ),
      throwsFormatException,
    );
    expect(
      () => desired.validateConfirmedJobIdentity(
        job,
        planId: plan,
        planDigest: hash,
        planServerId: other,
        resolvedInputDigest: hash,
        ownedResources: {'system.motd'},
      ),
      throwsFormatException,
    );
    expect(
      () => desired.validateConfirmedJobIdentity(
        job,
        planId: plan,
        planDigest: hash,
        planServerId: grant,
        resolvedInputDigest: 'b' * 64,
        ownedResources: {'system.motd'},
      ),
      throwsFormatException,
    );
    expect(
      () => desired.validateConfirmedJobIdentity(
        job,
        planId: plan,
        planDigest: hash,
        planServerId: grant,
        resolvedInputDigest: hash,
        ownedResources: {},
      ),
      throwsFormatException,
    );
    final event = AutomationJobEventRecord.fromJson(eventJson());
    event.validateJobIdentity(
      job,
      previousSequence: 0,
      previousTimestamp: DateTime.parse(created),
    );
    expect(
      () => event.validateJobIdentity(AutomationJobRecord.fromJson(jobJson())),
      throwsFormatException,
    );
    expect(
      () => event.validateJobIdentity(job, previousSequence: 1),
      throwsFormatException,
    );
    expect(
      () => event.validateJobIdentity(
        job,
        previousTimestamp: DateTime.parse('2026-10-21T10:00:00.001Z'),
      ),
      throwsFormatException,
    );
    expect(
      () => event.validateJobIdentity(
        AutomationJobRecord.fromJson({...job.toJson(), 'workspaceId': other}),
      ),
      throwsFormatException,
    );
  });

  test('receipt identity validation accepts owner decisions after consumption and rejects cross-grant job links', () {
    final receipt = AutomationMutationReceiptRecord.fromJson(
      receiptJson(
        operation: 'approval.decide',
        origin: null,
        objectOrigin: grant,
      ),
    );
    receipt.validateApprovalIdentity(
      AutomationApprovalRecord.fromJson(approvalJson(state: 'consumed')),
    );
    expect(
      () => receipt.validateApprovalIdentity(
        AutomationApprovalRecord.fromJson({
          ...approvalJson(state: 'consumed'),
          'grantId': other,
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => receipt.validateApprovalIdentity(
        AutomationApprovalRecord.fromJson(approvalJson(state: 'denied')),
      ),
      throwsFormatException,
    );
    final apply = AutomationMutationReceiptRecord.fromJson(
      receiptJson(operation: 'job.apply', objectOrigin: grant),
    );
    apply.validateJobIdentity(
      AutomationJobRecord.fromJson(jobJson(state: 'succeeded')),
    );
    expect(
      () => apply.validateJobIdentity(
        AutomationJobRecord.fromJson({
          ...jobJson(state: 'succeeded'),
          'grantId': other,
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => apply.validateJobIdentity(
        AutomationJobRecord.fromJson({
          ...jobJson(state: 'succeeded'),
          'immutablePlanId': other,
        }),
      ),
      throwsFormatException,
    );
  });
  test('job outcomes and complete profile authority survive independent round trip', () {
    for (final state in [
      'queued',
      'running',
      'cancel-requested',
      'succeeded',
      'failed',
      'cancelled',
      'unknown',
      'reconciling',
    ]) {
      final input = jobJson(state: state);
      final record = AutomationJobRecord.fromJson(input);
      expect(record.toJson(), input);
      expect(
        record.profileKey,
        AutomationRevisionKey.fromJson({
          'profileId': profile,
          'revision': 1,
          'bodyDigest': hash,
        }),
      );
    }
    expect(AutomationJobRecord.fromJson(jobJson(origin: null)).grantId, isNull);
    expect(
      () => AutomationJobRecord.fromJson({
        ...jobJson(origin: null),
        'authorityRef': authorityJson(),
      }),
      throwsFormatException,
    );
  });

  test(
    'job record rejects malformed unions, fields, ranges and private outcomes',
    () {
      for (final input in <Map<String, Object?>>[
        {...jobJson(), 'rawOutput': 'private-marker'},
        {...jobJson(), 'workspaceId': 'bad'},
        {...jobJson(), 'nextSequence': 0},
        {...jobJson(), 'nextSequence': 9223372036854775808.0},
        {...jobJson(), 'profileRevision': 1.0},
        {...jobJson(), 'planDigest': 'A' * 64},
        {...jobJson(), 'createdAt': '2026-10-21T10:00:00Z'},
        {...jobJson(), 'updatedAt': '2026-10-21T09:59:59.999Z'},
        {...jobJson(), 'cancelRequested': true},
        {...jobJson(state: 'running'), 'cancelRequested': true},
        {...jobJson(state: 'cancel-requested'), 'cancelRequested': false},
        {...jobJson(), 'outcome': outcome('succeeded')},
        {...jobJson(state: 'succeeded'), 'outcome': null},
        {...jobJson(state: 'succeeded'), 'outcome': outcome('unknown')},
        {...jobJson(state: 'failed'), 'outcome': outcome('succeeded')},
        {...jobJson(state: 'unknown'), 'outcome': outcome('failed')},
        {...jobJson(state: 'cancelled'), 'outcome': outcome('failed')},
        {
          ...jobJson(state: 'failed'),
          'outcome': {...outcome('failed'), 'safeCode': 'private-marker'},
        },
        {
          ...jobJson(),
          'authorityRef': {...authorityJson(), 'shell': 'private-marker'},
        },
        {...jobJson(), 'authorityRef': authorityJson(kind: 'owner')},
        {
          ...jobJson(),
          'authorityRef': {...authorityJson(kind: 'approval'), 'revision': 2},
        },
      ])
        expect(
          () => AutomationJobRecord.fromJson(input),
          throwsFormatException,
        );
    },
  );

  test('every job state edge is checked, terminal restart and cancel reset rejected', () {
    const edges = <String, Set<String>>{
      'queued': {'running', 'cancelled'},
      'running': {
        'cancel-requested',
        'succeeded',
        'failed',
        'cancelled',
        'unknown',
      },
      'cancel-requested': {'succeeded', 'failed', 'cancelled', 'unknown'},
      'unknown': {'reconciling'},
      'reconciling': {'succeeded', 'failed', 'cancelled', 'unknown'},
    };
    for (final from in AutomationJobRecord.states) {
      for (final to in AutomationJobRecord.states) {
        final current = AutomationJobRecord.fromJson(jobJson(state: from));
        final nextValue = jobJson(state: to);
        if (current.cancelRequested) nextValue['cancelRequested'] = true;
        if (to == 'queued' || to == 'running')
          nextValue['cancelRequested'] = false;
        final next = AutomationJobRecord.fromJson(nextValue);
        final allowed =
            (from == to || (edges[from]?.contains(to) ?? false)) &&
            !(current.cancelRequested && !next.cancelRequested);
        if (allowed)
          expect(() => current.validateTransitionTo(next), returnsNormally);
        else
          expect(
            () => current.validateTransitionTo(next),
            throwsFormatException,
            reason: '$from->$to',
          );
      }
    }
    final original = AutomationJobRecord.fromJson(jobJson());
    for (final input in [
      {...jobJson(), 'profileRevision': 2},
      {...jobJson(), 'hostAttemptId': authority},
      {...jobJson(), 'grantId': other},
      {...jobJson(), 'requestId': other},
    ]) {
      expect(
        () =>
            original.validateTransitionTo(AutomationJobRecord.fromJson(input)),
        throwsFormatException,
      );
    }
    final progressed = AutomationJobRecord.fromJson({
      ...jobJson(),
      'nextSequence': 2,
      'updatedAt': '2026-10-21T10:00:01.000Z',
    });
    expect(
      () => progressed.validateTransitionTo(original),
      throwsFormatException,
    );
  });

  test('approval state/window/job constraints are strict and transitions are single-use', () {
    for (final state in AutomationApprovalRecord.states) {
      expect(
        AutomationApprovalRecord.fromJson(approvalJson(state: state)).toJson(),
        approvalJson(state: state),
      );
    }
    for (final input in [
      {...approvalJson(), 'expiresAt': created},
      {...approvalJson(), 'expiresAt': '2026-10-21T10:05:00.001Z'},
      {...approvalJson(), 'jobId': jobId},
      {...approvalJson(state: 'consumed'), 'jobId': null},
      {...approvalJson(), 'state': 'private-marker'},
      {...approvalJson(), 'secret': hash},
    ])
      expect(
        () => AutomationApprovalRecord.fromJson(input),
        throwsFormatException,
      );
    const edges = {
      'pending': {'approved', 'denied', 'expired'},
      'approved': {'consumed', 'expired'},
    };
    for (final from in AutomationApprovalRecord.states)
      for (final to in AutomationApprovalRecord.states) {
        final current = AutomationApprovalRecord.fromJson(
          approvalJson(state: from),
        );
        final next = AutomationApprovalRecord.fromJson(approvalJson(state: to));
        if (from == to || (edges[from]?.contains(to) ?? false))
          expect(() => current.validateTransitionTo(next), returnsNormally);
        else
          expect(
            () => current.validateTransitionTo(next),
            throwsFormatException,
            reason: '$from->$to',
          );
      }
  });

  test('desired state and events reject private fields, invalid IDs and impossible variants', () {
    final desired = AutomationDesiredStateRecord.fromJson(desiredJson());
    expect(desired.toJson(), desiredJson());
    for (final input in [
      {...desiredJson(), 'observedRevision': 2},
      {...desiredJson(), 'desiredRevision': 0},
      {...desiredJson(), 'resourceId': '/etc/private'},
      {...desiredJson(), 'rawConfig': 'private-marker'},
    ])
      expect(
        () => AutomationDesiredStateRecord.fromJson(input),
        throwsFormatException,
      );
    for (final kind in ['state', 'step', 'check', 'progress', 'dropped'])
      expect(
        AutomationJobEventRecord.fromJson(eventJson(kind: kind)).toJson(),
        eventJson(kind: kind),
      );
    for (final input in [
      {...eventJson(), 'sequence': 0},
      {...eventJson(), 'sequence': '1'},
      {...eventJson(), 'state': null},
      {...eventJson(), 'stepId': 'step'},
      {...eventJson(kind: 'step'), 'stepId': null},
      {...eventJson(kind: 'check'), 'checkResult': null},
      {...eventJson(kind: 'progress'), 'droppedCount': 1},
      {...eventJson(kind: 'dropped'), 'droppedCount': 0},
      {...eventJson(), 'safeCode': 'private-marker'},
      {...eventJson(), 'rawOutput': 'private-marker'},
      {...eventJson(), 'timestamp': 'bad'},
    ])
      expect(
        () => AutomationJobEventRecord.fromJson(input),
        throwsFormatException,
      );
  });

  test(
    'stable receipts separate owner initiator from grant-origin objects',
    () {
      for (final operation in AutomationMutationReceiptRecord.operations) {
        final ownerOnly =
            operation.startsWith('grant.') ||
            operation.startsWith('delegation.') ||
            operation == 'approval.decide';
        final target =
            operation.startsWith('profile.') || operation.startsWith('grant.')
            ? null
            : grant;
        final input = receiptJson(
          operation: operation,
          origin: ownerOnly ? null : grant,
          objectOrigin: target,
        );
        final record = AutomationMutationReceiptRecord.fromJson(input);
        expect(record.toJson(), input);
        expect(
          record.matchesInitiator(
            workspaceId: workspace,
            grantId: record.originGrantId,
          ),
          isTrue,
        );
        expect(
          record.matchesInitiator(
            workspaceId: other,
            grantId: record.originGrantId,
          ),
          isFalse,
        );
        expect(
          record.matchesInitiator(workspaceId: workspace, grantId: other),
          isFalse,
        );
      }
      final ownerDecision = AutomationMutationReceiptRecord.fromJson(
        receiptJson(
          operation: 'approval.decide',
          origin: null,
          objectOrigin: grant,
        ),
      );
      expect(ownerDecision.originGrantId, isNull);
      expect(ownerDecision.objectGrantId, grant);
      expect(
        ownerDecision.matchesInitiator(workspaceId: workspace, grantId: grant),
        isFalse,
      );
      for (final input in [
        receiptJson(operation: 'approval.decide', objectOrigin: grant),
        receiptJson(operation: 'grant.replace', objectOrigin: null),
        receiptJson(
          operation: 'delegation.create',
          origin: null,
          objectOrigin: null,
        ),
        receiptJson(operation: 'job.apply', objectOrigin: other),
        receiptJson(operation: 'profile.update', objectOrigin: grant),
        {
          ...receiptJson(),
          'response': {'rawOutput': 'private-marker'},
        },
        {
          ...receiptJson(),
          'result': {
            'profileId': profile,
            'revision': 1,
            'digest': hash,
            'name': 'private-marker',
          },
        },
      ])
        expect(
          () => AutomationMutationReceiptRecord.fromJson(input),
          throwsFormatException,
        );
    },
  );

  test('recorded acknowledgements survive changed later objects and independent round trips', () {
    final input = receiptJson();
    final record = AutomationMutationReceiptRecord.fromJson(input);
    final committed = record.result;
    (input['result'] as Map)['revision'] = 99;
    record.result['revision'] = 100;
    record.toJson()['operation'] = 'private-marker';
    final reopened = AutomationMutationReceiptRecord.fromJson(
      jsonDecode(jsonEncode(record.toJson())) as Map<String, Object?>,
    );
    expect(reopened.result, committed);
    expect(reopened.result, {
      'profileId': profile,
      'revision': 1,
      'digest': hash,
    });
    final original = jobJson(state: 'succeeded');
    final job = AutomationJobRecord.fromJson(original);
    (original['outcome'] as Map)['effects'] = 'uncertain';
    (job.toJson()['outcome'] as Map)['effects'] = 'uncertain';
    expect((job.toJson()['outcome'] as Map)['effects'], 'none');
  });
}
