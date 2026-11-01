import 'dart:async';

import 'package:serverdeck_engine/storage/state_store.dart';
import 'package:serverdeck_engine/mcp/grants.dart';
import 'package:serverdeck_engine/automation/authority_commands.dart';
import 'package:test/test.dart';

import '../support/actual_plan_fixture.dart';
import 'actual_plan_job_store_test.dart' show job;
import 'actual_state_store_test.dart' as actual;
import '../support/schema3_fixture.dart' as fixture;

void main() {
  tearDown(() => expect(StateStore.hasOpenReservation, isFalse));
  for (final cause in ['permit', 'grant', 'delegation', 'proof']) {
    test(
      '$cause loss during held native put rolls back job and event together',
      () async {
        final setup = await actual.Setup.create(), store = await setup.open();
        final granted = cause == 'grant' || cause == 'delegation';
        final grantId = granted ? actual.id(25) : null;
        if (granted)
          await store.mutateOwnerGrant(
            actual.createGrant(26, grantId!),
            clock: actual.now,
          );
        final built = await planFixture(
          store,
          40,
          directSsh: true,
          originGrantId: grantId,
        );
        await store.persistTrustedPlan(
          built.$1,
          built.$2,
          originGrantId: grantId,
          expectedGrantRevision: granted ? 1 : null,
          clock: actual.now,
        );
        if (cause == 'delegation') {
          await store.mutateTrustedAuthority(
            AutomationAuthorityCommand.parse('delegation.create', {
              'requestId': actual.id(51),
              'grantId': grantId,
              'serverIds': [fixture.profile],
              'profileRevisions': [built.$2.key.toJson()],
              'predicates': {
                'message': {
                  'type': 'enum',
                  'values': ['actual unit storage'],
                },
              },
              'lifetimeSeconds': 300,
            }),
            originGrantId: null,
            expectedGrantRevision: null,
            clock: actual.now,
          );
        } else {
          await approve(store, built.$2, 50);
        }
        final admitted = await job(
          store,
          'job.apply',
          60,
          built.$2.id,
          verifiedDigest: built.$2.toJson()['digest'] as String,
        );
        final before = actual.rawRows(store),
            storage = setup.provider.lastOpened!;
        final commits = storage.commits, puts = storage.putCalls;
        final held = storage.holdPut = Completer<void>();
        var at = actual.now().add(
          Duration(
            seconds: cause == 'grant'
                ? 3599
                : cause == 'delegation'
                ? 299
                : 0,
          ),
        );
        var elapsed = Duration.zero, live = true;
        final effect = (built.$2.toJson()['effects'] as List).first as Map;
        final pending = store.authorizeDirectSshStep(
          jobId: admitted['jobId'] as String,
          expectedSequence: 2,
          stepId: effect['id'] as String,
          bootIdHash: built.$2.preflight!.toJson()['bootIdHash'] as String,
          observedUptimeMs: 1000,
          elapsedSinceProbe: () => elapsed,
          originGrantId: grantId,
          expectedGrantRevision: granted ? 1 : null,
          clock: () => at,
          revalidate: () {
            if (!live) throw StateError('FORBIDDEN');
          },
        );
        final checked = expectLater(pending, actual.failure('FORBIDDEN'));
        try {
          for (
            var count = 0;
            storage.putCalls == puts && count < 1000;
            count++
          ) {
            await Future<void>.delayed(Duration.zero);
          }
          expect(storage.putCalls, greaterThan(puts));
          if (cause == 'permit') elapsed = const Duration(seconds: 5);
          if (cause == 'grant' || cause == 'delegation')
            at = at.add(const Duration(seconds: 1));
          if (cause == 'proof') live = false;
        } finally {
          held.complete();
          storage.holdPut = null;
        }
        await checked;
        expect(storage.commits, commits);
        expect(actual.rawRows(store), before);
        expect(store.isReady, isTrue);
      },
    );
  }
  test(
    'consumed approval survives plan TTL but current grant limits the permit',
    () async {
      final setup = await actual.Setup.create(), store = await setup.open();
      final grantId = actual.id(25);
      await store.mutateOwnerGrant(
        actual.createGrant(26, grantId),
        clock: actual.now,
      );
      final built = await planFixture(
        store,
        40,
        directSsh: true,
        originGrantId: grantId,
      );
      await store.persistTrustedPlan(
        built.$1,
        built.$2,
        originGrantId: grantId,
        expectedGrantRevision: 1,
        clock: actual.now,
      );
      await approve(store, built.$2, 50);
      final admitted = await job(
        store,
        'job.apply',
        60,
        built.$2.id,
        verifiedDigest: built.$2.toJson()['digest'] as String,
      );
      final effect = (built.$2.toJson()['effects'] as List).first as Map;
      final authorized = await store.authorizeDirectSshStep(
        jobId: admitted['jobId'] as String,
        expectedSequence: 2,
        stepId: effect['id'] as String,
        bootIdHash: built.$2.preflight!.toJson()['bootIdHash'] as String,
        observedUptimeMs: 1000,
        elapsedSinceProbe: () => const Duration(milliseconds: 120),
        originGrantId: grantId,
        expectedGrantRevision: 1,
        clock: () => actual.now().add(const Duration(seconds: 3598)),
        revalidate: () {},
      );
      expect(authorized.sshDispatch!.grantRevision, 1);
      expect(authorized.sshDispatch!.expiresUptimeMs, 2880);
      expect(
        authorized.sshDispatch!.grantExpiresAt,
        store.snapshot.automation.grants[grantId]!.expiresAt,
      );
      await store.mutateOwnerGrant(
        OwnerGrantCommand.parse('grant.replace', {
          'requestId': actual.id(61),
          'grantId': grantId,
          'expectedRevision': 1,
          'label': 'replacement',
          'scopes': ['read'],
          'serverIds': [fixture.profile],
          'lifetimeSeconds': 3600,
        }),
        clock: () => actual.now().add(const Duration(seconds: 3599)),
      );
      expect(
        store.snapshot.automation.jobs[authorized.id]!.sshDispatch!.toJson(),
        authorized.sshDispatch!.toJson(),
      );
    },
  );
  test(
    'direct authorization atomically publishes a bound permit and step event',
    () async {
      final setup = await actual.Setup.create(), store = await setup.open();
      final built = await planFixture(store, 40, directSsh: true);
      await persist(store, built);
      await approve(store, built.$2, 50);
      final admitted = await job(
        store,
        'job.apply',
        60,
        built.$2.id,
        verifiedDigest: built.$2.toJson()['digest'] as String,
      );
      final jobId = admitted['jobId'] as String;
      final effect = (built.$2.toJson()['effects'] as List).first as Map;
      var proofs = 0;
      final authorized = await store.authorizeDirectSshStep(
        jobId: jobId,
        expectedSequence: 2,
        stepId: effect['id'] as String,
        bootIdHash: built.$2.preflight!.toJson()['bootIdHash'] as String,
        observedUptimeMs: 1000,
        elapsedSinceProbe: () => const Duration(milliseconds: 120),
        originGrantId: null,
        expectedGrantRevision: null,
        clock: actual.now,
        revalidate: () {
          proofs++;
        },
      );
      expect(proofs, greaterThanOrEqualTo(2));
      expect(authorized.state, 'running');
      expect(authorized.nextSequence, 3);
      expect(authorized.sshDispatch!.state, 'authorized');
      expect(authorized.sshDispatch!.issuedUptimeMs, 1000);
      expect(authorized.sshDispatch!.expiresUptimeMs, 5880);
      expect(
        store.snapshot.automation.events['$jobId:2']!.toJson(),
        containsPair('stepId', effect['id']),
      );
      final before = actual.rawRows(store);
      await expectLater(
        store.authorizeDirectSshStep(
          jobId: jobId,
          expectedSequence: 2,
          stepId: effect['id'] as String,
          bootIdHash: built.$2.preflight!.toJson()['bootIdHash'] as String,
          observedUptimeMs: 1000,
          elapsedSinceProbe: () => Duration.zero,
          originGrantId: null,
          expectedGrantRevision: null,
          clock: actual.now,
          revalidate: () {},
        ),
        actual.failure('REVISION_CONFLICT'),
      );
      expect(actual.rawRows(store), before);
    },
  );

  for (final scenario in [
    'legacy',
    'boot',
    'step',
    'elapsed',
    'negative',
    'proof',
    'late-proof',
    'transaction-proof',
    'late-expiry',
    'rollback',
  ]) {
    test('$scenario prevents durable intent before any effect', () async {
      final setup = await actual.Setup.create(), store = await setup.open();
      final built = await planFixture(
        store,
        40,
        directSsh: scenario != 'legacy',
      );
      await persist(store, built);
      await approve(store, built.$2, 50);
      final admitted = await job(
        store,
        'job.apply',
        60,
        built.$2.id,
        verifiedDigest: built.$2.toJson()['digest'] as String,
      );
      final before = actual.rawRows(store);
      final effect = (built.$2.toJson()['effects'] as List).first as Map;
      var proofs = 0, elapsedReads = 0;
      await expectLater(
        store.authorizeDirectSshStep(
          jobId: admitted['jobId'] as String,
          expectedSequence: 2,
          stepId: scenario == 'step' ? 'absent' : effect['id'] as String,
          bootIdHash: scenario == 'boot'
              ? 'a' * 64
              : built.$2.preflight!.toJson()['bootIdHash'] as String,
          observedUptimeMs: 1000,
          elapsedSinceProbe: () {
            elapsedReads++;
            if (scenario == 'elapsed' ||
                scenario == 'late-expiry' && elapsedReads > 1)
              return const Duration(seconds: 5);
            if (scenario == 'negative') return const Duration(microseconds: -1);
            if (scenario == 'rollback')
              return Duration(milliseconds: elapsedReads == 1 ? 100 : 99);
            return Duration.zero;
          },
          originGrantId: null,
          expectedGrantRevision: null,
          clock: actual.now,
          revalidate: () {
            proofs++;
            if (scenario == 'proof' ||
                scenario == 'late-proof' && proofs == 2 ||
                scenario == 'transaction-proof' && proofs == 3)
              throw StateError('FORBIDDEN');
          },
        ),
        actual.failure(switch (scenario) {
          'legacy' => 'RUNTIME_INCOMPATIBLE',
          'boot' => 'PLAN_STALE',
          'step' => 'VALIDATION',
          'elapsed' => 'TIMEOUT',
          'negative' => 'VALIDATION',
          _ => 'FORBIDDEN',
        }),
      );
      expect(actual.rawRows(store), before);
      expect(store.isReady, isTrue);
    });
  }
}
