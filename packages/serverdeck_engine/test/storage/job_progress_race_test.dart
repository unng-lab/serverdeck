import 'dart:async';

import 'package:serverdeck_engine/automation/job_progress.dart';
import 'package:serverdeck_engine/storage/state_store.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:test/test.dart';

import '../support/actual_plan_fixture.dart';
import 'actual_state_store_test.dart' as actual;
import 'actual_plan_job_store_test.dart' as commands;

AutomationJobOutcome unknown() => AutomationJobOutcome.fromJson({
  'effects': 'uncertain',
  'checks': [],
  'safeCode': 'UNKNOWN_OUTCOME',
});
Future<(actual.Setup, StateStore, String)> running() async {
  final setup = await actual.Setup.create(), store = await setup.open();
  final fixture = await planFixture(store, 900);
  await persist(store, fixture);
  await approve(store, fixture.$2, 901);
  final admitted = await commands.job(
    store,
    'job.apply',
    903,
    fixture.$2.id,
    verifiedDigest: fixture.$2.toJson()['digest'] as String,
  );
  final id = admitted['jobId'] as String;
  await store.publishTrustedJobProgress(
    jobId: id,
    expectedSequence: store.snapshot.automation.jobs[id]!.nextSequence,
    state: 'running',
    outcome: null,
    clock: actual.now,
  );
  return (setup, store, id);
}

Future<void> uncertain(StateStore store, String id) =>
    store.publishTrustedJobProgress(
      jobId: id,
      expectedSequence: store.snapshot.automation.jobs[id]!.nextSequence,
      state: 'unknown',
      outcome: unknown(),
      clock: actual.now,
    );

void main() {
  for (final scenario in ['owned', 'superseded', 'CAS conflict']) {
    test(
      'cancel can publish only its exact reconciliation phase: $scenario',
      () async {
        final (_, store, id) = await running();
        await uncertain(store, id);
        await commands.job(store, 'job.reconcile', 904, id);
        final owned = store.snapshot.automation.jobs[id]!.nextSequence;
        Future<void> newer() async {
          await uncertain(store, id);
          await commands.job(store, 'job.reconcile', 905, id);
        }

        if (scenario == 'superseded') await newer();
        var calls = 0;
        final result = await publishJobProgress(
          mode: 'cancel',
          state: 'cancelled',
          ownedReconciliationSequence: owned,
          readCurrent: () async => store.snapshot.automation.jobs[id]!,
          compareAndSwap: (previous, next) async {
            if (scenario == 'CAS conflict' && calls++ == 0) await newer();
            return store.publishTrustedJobProgress(
              jobId: id,
              expectedSequence: previous.nextSequence,
              state: next,
              outcome: AutomationJobOutcome.fromJson({
                'effects': 'none',
                'checks': [],
                'safeCode': 'CANCELLED',
              }),
              clock: actual.now,
            );
          },
        );
        expect(result.state, scenario == 'owned' ? 'cancelled' : 'reconciling');
        expect(store.snapshot.automation.jobs[id]!.state, result.state);
      },
    );
  }
  for (final mode in ['apply', 'cancel']) {
    for (final retry in [false, true]) {
      test(
        'actual $mode progress preserves newer reconciling after ${retry ? 'CAS conflict' : 'awaited read'}',
        () async {
          final (setup, store, id) = await running();
          if (!retry) await uncertain(store, id);
          final entered = Completer<void>(), release = Completer<void>();
          addTearDown(() {
            if (!release.isCompleted) release.complete();
          });
          var reads = 0;
          final pending = publishJobProgress(
            mode: mode,
            state: 'unknown',
            readCurrent: () async {
              reads++;
              final captured = store.snapshot.automation.jobs[id]!;
              if (reads == 1) {
                entered.complete();
                await release.future;
              }
              return retry ? captured : store.snapshot.automation.jobs[id]!;
            },
            compareAndSwap: (previous, next) => store.publishTrustedJobProgress(
              jobId: id,
              expectedSequence: previous.nextSequence,
              state: next,
              outcome: unknown(),
              clock: actual.now,
            ),
          );
          await entered.future;
          if (retry) await uncertain(store, id);
          await commands.job(store, 'job.reconcile', 904, id);
          final accepted = store.snapshot.automation.jobs[id]!;
          final commits = setup.provider.lastOpened!.commits;
          expect(accepted.state, 'reconciling');
          release.complete();
          final result = await pending;
          expect(result.toJson(), accepted.toJson());
          expect(
            store.snapshot.automation.jobs[id]!.toJson(),
            accepted.toJson(),
          );
          expect(setup.provider.lastOpened!.commits, commits);
          expect(reads, retry ? 2 : 1);
          expect(store.isReady, isTrue);
        },
      );
    }
  }
}
