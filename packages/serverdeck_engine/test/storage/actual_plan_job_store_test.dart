import 'package:serverdeck_engine/automation/job_commands.dart';
import 'package:serverdeck_engine/automation/plan_commands.dart';
import 'package:serverdeck_engine/storage/state_store.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:test/test.dart';

import '../support/actual_plan_fixture.dart';
import 'actual_state_store_test.dart' as actual;

Future<Map<String, Object?>> job(
  StateStore store,
  String operation,
  int request,
  String object, {
  String? verifiedDigest,
}) => store.mutateTrustedJob(
  JobMutationCommand.parse(operation, {
    'requestId': actual.id(request),
    operation == 'job.apply' ? 'planId' : 'jobId': object,
  }),
  originGrantId: null,
  expectedGrantRevision: null,
  clock: actual.now,
  verifiedPlanDigest: verifiedDigest,
);

void main() {
  tearDown(() => expect(StateStore.hasOpenReservation, isFalse));

  test(
    'actual plan persistence/replay preserves compiled program and exact IDs',
    () async {
      final setup = await actual.Setup.create(), store = await setup.open();
      final fixture = await planFixture(store, 40);
      final saved = await persist(store, fixture);
      expect(saved['planId'], fixture.$2.id);
      expect(saved['planDigest'], fixture.$2.toJson()['digest']);
      expect(
        store.snapshot.automation.plans[fixture.$2.id]!.toJson(),
        fixture.$2.toJson(),
      );
      expect(store.snapshot.rows['StoredAutomationPlan']!.single.nativeId, 1);
      final commits = setup.provider.lastOpened!.commits;
      expect(await persist(store, fixture), saved);
      expect(
        await store.replayTrustedPlan(
          fixture.$1,
          originGrantId: null,
          expectedGrantRevision: null,
          at: actual.now(),
        ),
        saved,
      );
      expect(setup.provider.lastOpened!.commits, commits);
      final changed = PlanCreateCommand.fromJson({
        ...fixture.$1.toJson(),
        'parameters': {'message': 'different'},
      });
      await expectLater(
        store.persistTrustedPlan(
          changed,
          fixture.$2,
          originGrantId: null,
          expectedGrantRevision: null,
          clock: actual.now,
        ),
        actual.failure('IDEMPOTENCY_CONFLICT'),
      );
      expect(setup.provider.lastOpened!.commits, commits);
    },
  );

  test(
    'plan TTL equality refuses before row transaction and retains prior graph',
    () async {
      final setup = await actual.Setup.create(), store = await setup.open();
      final fixture = await planFixture(store, 41),
          before = actual.rawRows(store);
      final commits = setup.provider.lastOpened!.commits;
      await expectLater(
        persist(
          store,
          fixture,
          clock: () => actual.now().add(const Duration(minutes: 5)),
        ),
        actual.failure('PLAN_EXPIRED'),
      );
      expect(actual.rawRows(store), before);
      expect(setup.provider.lastOpened!.commits, commits);
      expect(store.isReady, isTrue);
    },
  );

  test(
    'blocked plan is retained history and cannot request approval or apply',
    () async {
      final setup = await actual.Setup.create(), store = await setup.open();
      final fixture = await planFixture(store, 42, blocked: true);
      await persist(store, fixture);
      expect(store.snapshot.automation.plans[fixture.$2.id]!.status, 'blocked');
      final before = actual.rawRows(store);
      await expectLater(
        approve(store, fixture.$2, 43),
        actual.failure('PLAN_STALE'),
      );
      await expectLater(
        job(
          store,
          'job.apply',
          45,
          fixture.$2.id,
          verifiedDigest: fixture.$2.toJson()['digest'] as String,
        ),
        actual.failure('PLAN_STALE'),
      );
      expect(actual.rawRows(store), before);
    },
  );

  test('approval is mandatory and consumed atomically with canonical job admission', () async {
    final setup = await actual.Setup.create(), store = await setup.open();
    final fixture = await planFixture(store, 50),
        digest = fixture.$2.toJson()['digest'] as String;
    await persist(store, fixture);
    await expectLater(
      job(store, 'job.apply', 51, fixture.$2.id, verifiedDigest: digest),
      actual.failure('APPROVAL_REQUIRED'),
    );
    final approval = await approve(store, fixture.$2, 52);
    final result = await job(
      store,
      'job.apply',
      54,
      fixture.$2.id,
      verifiedDigest: digest,
    );
    final jobId = result['jobId'] as String;
    expect(store.snapshot.automation.approvals[approval]!.state, 'consumed');
    expect(
      store.snapshot.automation.approvals[approval]!.toJson()['jobId'],
      jobId,
    );
    expect(store.snapshot.automation.jobs[jobId]!.state, 'queued');
    expect(store.snapshot.automation.jobs[jobId]!.requestId, actual.id(54));
    final alias = await job(
      store,
      'job.apply',
      55,
      fixture.$2.id,
      verifiedDigest: digest,
    );
    expect(alias, result);
    expect(store.snapshot.automation.jobs, hasLength(1));
    expect(store.snapshot.automation.jobs[jobId]!.requestId, actual.id(54));
    expect(store.snapshot.automation.events.values.single.sequence, 1);
    expect(
      await store.replayTrustedJob(
        JobMutationCommand.parse('job.apply', {
          'requestId': actual.id(54),
          'planId': fixture.$2.id,
        }),
        originGrantId: null,
        expectedGrantRevision: null,
        at: actual.now(),
      ),
      result,
    );
  });

  test('job progress CAS, events and checked success publish desired state together', () async {
    final setup = await actual.Setup.create(), store = await setup.open();
    final fixture = await planFixture(store, 60);
    await persist(store, fixture);
    await approve(store, fixture.$2, 61);
    final admitted = await job(
      store,
      'job.apply',
      63,
      fixture.$2.id,
      verifiedDigest: fixture.$2.toJson()['digest'] as String,
    );
    final jobId = admitted['jobId'] as String;
    final nativeId =
        store.snapshot.rows['StoredAutomationJob']!.single.nativeId;
    await store.publishTrustedJobProgress(
      jobId: jobId,
      expectedSequence: 2,
      state: 'running',
      outcome: null,
      clock: actual.now,
    );
    final before = actual.rawRows(store);
    await expectLater(
      store.publishTrustedJobProgress(
        jobId: jobId,
        expectedSequence: 2,
        state: 'running',
        outcome: null,
        clock: actual.now,
      ),
      actual.failure('REVISION_CONFLICT'),
    );
    expect(actual.rawRows(store), before);
    final checks = (fixture.$2.toJson()['checks'] as List)
        .cast<Map<String, Object?>>();
    final outcome = AutomationJobOutcome.fromJson({
      'effects': 'confirmed',
      'safeCode': null,
      'checks': [
        for (final c in checks)
          {
            'checkId': c['id'],
            'stepId': c['effectId'],
            'result': 'passed',
            'safeCode': null,
          },
      ],
    });
    final succeeded = await store.publishTrustedJobProgress(
      jobId: jobId,
      expectedSequence: 3,
      state: 'succeeded',
      outcome: outcome,
      clock: actual.now,
    );
    expect(succeeded.nextSequence, 4);
    expect(
      store.snapshot.rows['StoredAutomationJob']!.single.nativeId,
      nativeId,
    );
    final sequences =
        store.snapshot.automation.events.values.map((e) => e.sequence).toList()
          ..sort();
    expect(sequences, [1, 2, 3]);
    final desired = store.snapshot.automation.desired.values.single;
    expect(desired.toJson(), containsPair('lastJobId', jobId));
    expect(desired.toJson(), containsPair('desiredRevision', 1));
    expect(desired.toJson(), containsPair('resourceId', 'system.motd'));
    final retained = actual.rawRows(store);
    await store.close();
    final reopened = await setup.open();
    expect(actual.rawRows(reopened), retained);
    expect(reopened.snapshot.automation.jobs[jobId]!.state, 'succeeded');
  });

  test(
    'queued cancellation persists one terminal event and idempotent receipt',
    () async {
      final setup = await actual.Setup.create(), store = await setup.open();
      final fixture = await planFixture(store, 70);
      await persist(store, fixture);
      await approve(store, fixture.$2, 71);
      final admitted = await job(
        store,
        'job.apply',
        73,
        fixture.$2.id,
        verifiedDigest: fixture.$2.toJson()['digest'] as String,
      );
      final jobId = admitted['jobId'] as String;
      final cancelled = await job(store, 'job.cancel', 74, jobId);
      expect(store.snapshot.automation.jobs[jobId]!.state, 'cancelled');
      expect(store.snapshot.automation.jobs[jobId]!.outcome!.effects, 'none');
      expect(
        store.snapshot.automation.jobs[jobId]!.outcome!.safeCode,
        'CANCELLED',
      );
      final commits = setup.provider.lastOpened!.commits;
      expect(await job(store, 'job.cancel', 74, jobId), cancelled);
      expect(setup.provider.lastOpened!.commits, commits);
      expect(store.snapshot.automation.events, hasLength(2));
    },
  );

  test(
    'unknown outcome retains host occupancy until explicit reconciliation',
    () async {
      final setup = await actual.Setup.create(), store = await setup.open();
      final first = await planFixture(store, 80);
      await persist(store, first);
      await approve(store, first.$2, 81);
      final admitted = await job(
        store,
        'job.apply',
        83,
        first.$2.id,
        verifiedDigest: first.$2.toJson()['digest'] as String,
      );
      final jobId = admitted['jobId'] as String;
      await store.publishTrustedJobProgress(
        jobId: jobId,
        expectedSequence: 2,
        state: 'running',
        outcome: null,
        clock: actual.now,
      );
      await store.publishTrustedJobProgress(
        jobId: jobId,
        expectedSequence: 3,
        state: 'unknown',
        outcome: AutomationJobOutcome.fromJson({
          'effects': 'uncertain',
          'checks': [],
          'safeCode': 'UNKNOWN_OUTCOME',
        }),
        clock: actual.now,
      );
      final second = await planFixture(
        store,
        84,
        profileId: first.$1.profileId,
      );
      await persist(store, second);
      await approve(store, second.$2, 85);
      await expectLater(
        job(
          store,
          'job.apply',
          87,
          second.$2.id,
          verifiedDigest: second.$2.toJson()['digest'] as String,
        ),
        actual.failure('HOST_BUSY'),
      );
      await job(store, 'job.reconcile', 88, jobId);
      final reconciling = store.snapshot.automation.jobs[jobId]!;
      expect(reconciling.state, 'reconciling');
      await store.publishTrustedJobProgress(
        jobId: jobId,
        expectedSequence: reconciling.nextSequence,
        state: 'cancelled',
        outcome: AutomationJobOutcome.fromJson({
          'effects': 'none',
          'checks': [],
          'safeCode': 'CANCELLED',
        }),
        clock: actual.now,
      );
      final next = await job(
        store,
        'job.apply',
        89,
        second.$2.id,
        verifiedDigest: second.$2.toJson()['digest'] as String,
      );
      expect(next['jobId'], isNot(jobId));
      expect(store.snapshot.automation.jobs, hasLength(2));
    },
  );
}
