import 'package:serverdeck_engine/automation/configuration.dart';
import 'package:serverdeck_engine/automation/profile_commands.dart';
import 'package:serverdeck_engine/storage/state_store.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:test/test.dart';

import '../storage/actual_state_store_test.dart' as actual;
import '../storage/actual_plan_job_store_test.dart' as commands;
import '../support/actual_plan_fixture.dart';

Map<String, Object?> values(String product) => product == 'postgresql'
    ? {'max_connections': 100, 'shared_buffers_mb': 256}
    : {'max_connections': 4096, 'max_server_memory_usage_mb': 2048};

Future<String> profile(
  StateStore store,
  String product, {
  bool stopAfterConfig = false,
}) async =>
    (await actual.profile(
          store,
          AutomationProfileCommand.parse('profile.create', {
            'requestId': actual.id(2),
            'name': 'RAM database config',
            'body': {
              'format': 1,
              'environment': 'ubuntu24.04-amd64-systemd',
              'parameters': <String, Object?>{},
              'steps': [
                {
                  'id': 'configure',
                  'kind': 'config_file',
                  'resourceId': product + '.settings',
                  'values': values(product),
                },
                if (stopAfterConfig)
                  {
                    'id': 'stop',
                    'kind': 'service',
                    'resourceId': product + '.service',
                    'state': 'stopped',
                    'enabled': true,
                  },
              ],
            },
          }),
        ))['profileId']
        as String;

Future<(AutomationPlanRecord, String)> running(
  StateStore store,
  String product,
  String profileId,
  int request, {
  bool direct = true,
}) async {
  final fixture = await planFixture(
    store,
    request,
    profileId: profileId,
    directSsh: direct,
    exactParameters: {},
    baselineFingerprints: {
      product + '.settings': 'a' * 64,
      product + '.service': 'b' * 64,
    },
  );
  await persist(store, fixture);
  await approve(store, fixture.$2, request + 1);
  final saved = await commands.job(
    store,
    'job.apply',
    request + 3,
    fixture.$2.id,
    verifiedDigest: fixture.$2.toJson()['digest'] as String,
  );
  final id = saved['jobId'] as String;
  await store.publishTrustedJobProgress(
    jobId: id,
    expectedSequence: 2,
    state: 'running',
    outcome: null,
    clock: actual.now,
  );
  return (fixture.$2, id);
}

AutomationJobOutcome outcome(
  AutomationPlanRecord plan, {
  String state = 'succeeded',
}) => AutomationJobOutcome.fromJson({
  'effects': state == 'unknown' ? 'uncertain' : 'confirmed',
  'safeCode': switch (state) {
    'succeeded' => null,
    'unknown' => 'UNKNOWN_OUTCOME',
    _ => 'CHECK_FAILED',
  },
  'checks': [
    for (final raw in plan.toJson()['checks'] as List)
      {
        'checkId': (raw as Map)['id'],
        'stepId': raw['effectId'],
        'result': state == 'succeeded' ? 'passed' : 'failed',
        'safeCode': state == 'succeeded' ? null : 'CHECK_FAILED',
      },
  ],
});

Future<void> finish(
  StateStore store,
  AutomationPlanRecord plan,
  String id, {
  String state = 'succeeded',
}) => store.publishTrustedJobProgress(
  jobId: id,
  expectedSequence: store.snapshot.automation.jobs[id]!.nextSequence,
  state: state,
  outcome: outcome(plan, state: state),
  clock: actual.now,
);

// Structural observation input to the pure comparison; not remote ownership or
// SQL evidence. Actual byte collection is covered by the direct-read suites.
ManagedResourceObservationRecord observation(
  AutomationPlanRecord plan,
  String resource, {
  Map<String, Object?>? change,
  String status = 'known',
}) {
  final effect = (plan.toJson()['effects'] as List).cast<Map>().first;
  return ManagedResourceObservationRecord.fromTrustedJson({
    'workspaceId': plan.workspaceId,
    'serverId': plan.serverId,
    'resourceId': resource,
    'targetRevision': plan.serverRevision,
    'connectionRevision': plan.connectionRevision,
    'accessRevision': plan.accessRevision,
    'trustRevision': plan.trustRevision,
    'hostId': plan.hostId,
    'resourceRegistryDigest': plan.registryDigest,
    'observedAt': actual.now().toIso8601String(),
    'status': status,
    'value': !const {'known', 'stale'}.contains(status)
        ? null
        : {
            if (resource.endsWith('.settings')) ...{
              'exists': true,
              'fileDigest': effect['renderedDigest'],
              'values': effect['values'],
              'baselineDigest': 'c' * 64,
            } else ...{
              'activeState': 'active',
              'unitFileState': 'disabled',
              'mainPid': 1234,
              'startMonotonicUs': '1000000',
              'baselineDigest': 'd' * 64,
            },
            ...?change,
          },
  });
}

void main() {
  tearDown(() => expect(StateStore.hasOpenReservation, isFalse));
  for (final product in ['postgresql', 'clickhouse']) {
    test(
      '$product compound requires every declared check before publishing either desired row',
      () async {
        final setup = await actual.Setup.create(), store = await setup.open();
        final profileId = await profile(store, product);
        final (plan, id) = await running(store, product, profileId, 90);
        final checks = outcome(plan).toJson()['checks'] as List;
        expect(checks, hasLength(5));
        final before = actual.rawRows(store),
            commits = setup.provider.lastOpened!.commits;
        for (var missing = 0; missing < checks.length; missing++) {
          final partial = AutomationJobOutcome.fromJson({
            ...outcome(plan).toJson(),
            'checks': [
              for (var i = 0; i < checks.length; i++)
                if (i != missing) checks[i],
            ],
          });
          await expectLater(
            store.publishTrustedJobProgress(
              jobId: id,
              expectedSequence: 3,
              state: 'succeeded',
              outcome: partial,
              clock: actual.now,
            ),
            actual.failure('VALIDATION'),
          );
          expect(actual.rawRows(store), before);
          expect(setup.provider.lastOpened!.commits, commits);
          expect(store.snapshot.automation.desired, isEmpty);
        }
        await finish(store, plan, id);
        expect(setup.provider.lastOpened!.commits, commits + 1);
        expect(
          store.snapshot.automation.desired.values
              .map((row) => row.resourceId)
              .toSet(),
          {product + '.settings', product + '.service'},
        );
      },
    );

    for (final direct in [true, false]) {
      test(
        '$product final stop after ${direct ? 'compound' : 'historical config'} wins comparison without losing enable intent',
        () async {
          final setup = await actual.Setup.create(), store = await setup.open();
          final profileId = await profile(
            store,
            product,
            stopAfterConfig: true,
          );
          final (plan, id) = await running(
            store,
            product,
            profileId,
            80,
            direct: direct,
          );
          await finish(store, plan, id);
          final view = configurationView(
            graph: store.snapshot.automation,
            observation: observation(
              plan,
              product + '.service',
              change: {
                'activeState': 'inactive',
                'mainPid': 0,
                'unitFileState': 'enabled',
              },
            ),
            at: actual.now(),
          );
          expect((view['comparison'] as Map)['status'], 'matched');
          expect(view['expected'], {
            'kind': 'service',
            'activeState': 'inactive',
            'unitFileState': 'enabled',
          });
        },
      );

      test(
        '$product ${direct ? 'compound' : 'historical two-effect'} success retains both desired resources and comparison',
        () async {
          final setup = await actual.Setup.create(), store = await setup.open();
          final profileId = await profile(store, product);
          final (plan, id) = await running(
            store,
            product,
            profileId,
            40,
            direct: direct,
          );
          final planBytes = plan.toJson();
          await finish(store, plan, id);
          expect(
            store.snapshot.automation.desired.values
                .map((row) => row.resourceId)
                .toSet(),
            {product + '.settings', product + '.service'},
          );
          final retained = actual.rawRows(store);
          await store.close();
          final reopened = await setup.open();
          expect(actual.rawRows(reopened), retained);
          expect(
            reopened.snapshot.automation.plans[plan.id]!.toJson(),
            planBytes,
          );
          final graph = reopened.snapshot.automation;
          for (final resource in [
            product + '.settings',
            product + '.service',
          ]) {
            final view = configurationView(
              graph: graph,
              observation: observation(plan, resource),
              at: actual.now(),
            );
            expect((view['comparison'] as Map)['status'], 'matched');
            expect((view['desired'] as Map)['lastJobId'], id);
            expect(
              (view['expected'] as Map)['kind'],
              resource.endsWith('.settings') ? 'config_file' : 'service',
            );
          }
          final service = configurationView(
            graph: graph,
            observation: observation(
              plan,
              product + '.service',
              change: {'activeState': 'inactive'},
            ),
            at: actual.now(),
          );
          expect((service['comparison'] as Map)['status'], 'drift');
          expect((service['comparison'] as Map)['differences'], [
            {
              'field': 'activeState',
              'desired': 'active',
              'observed': 'inactive',
            },
          ]);
          final file = configurationView(
            graph: graph,
            observation: observation(
              plan,
              product + '.settings',
              change: {'fileDigest': 'e' * 64},
            ),
            at: actual.now(),
          );
          expect((file['comparison'] as Map)['status'], 'drift');
          final stale = configurationView(
            graph: graph,
            observation: observation(plan, product + '.settings'),
            at: actual.now().add(const Duration(seconds: 16)),
          );
          expect((stale['comparison'] as Map)['status'], 'stale');
          final denied = configurationView(
            graph: graph,
            observation: observation(
              plan,
              product + '.settings',
              status: 'denied',
            ),
            at: actual.now(),
          );
          expect((denied['comparison'] as Map)['status'], 'unknown');
        },
      );
    }
    for (final state in ['failed', 'unknown']) {
      test(
        '$product $state compound preserves last successful intent across reopen',
        () async {
          final setup = await actual.Setup.create(), store = await setup.open();
          final profileId = await profile(store, product);
          final (prior, first) = await running(store, product, profileId, 50);
          await finish(store, prior, first);
          final desired = store.snapshot.automation.desired.values
              .map((row) => row.toJson())
              .toList();
          final (next, second) = await running(store, product, profileId, 60);
          await finish(store, next, second, state: state);
          expect(
            store.snapshot.automation.desired.values
                .map((row) => row.toJson())
                .toList(),
            desired,
          );
          await store.close();
          final reopened = await setup.open();
          expect(
            reopened.snapshot.automation.desired.values
                .map((row) => row.toJson())
                .toList(),
            desired,
          );
          expect(reopened.snapshot.automation.jobs[second]!.state, state);
          expect(desired.map((row) => row['lastJobId']).toSet(), {first});
        },
      );
    }
  }
}
