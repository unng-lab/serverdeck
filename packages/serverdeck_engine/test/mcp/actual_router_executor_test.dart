import 'package:serverdeck_engine/platform/ports.dart';

import 'dart:async';

import 'package:test/test.dart';

import '../automation/portable_program_test.dart' show motdBody;
import '../storage/actual_state_store_test.dart' as repository;
import '../support/actual_mcp_setup.dart';
import '../support/executor_byte_peer.dart';
import '../support/schema3_fixture.dart' as fixture;

Future<(Setup, ExecutorBytePeer)> enrolled({EngineClock? readClock}) async {
  final peer = ExecutorBytePeer();
  final s = await Setup.create(
    executorRelease: peer.release,
    executor: peer.attach,
    readClock: readClock,
  );
  final connecting = await s.ownerCall('servers.connect', {
    'profileId': fixture.profile,
  });
  var connected = await s.ownerCall('servers.connectStatus', {
    'operationId': connecting['operationId'],
  });
  for (var i = 0; connected['state'] == 'running' && i < 100; i++) {
    await Future<void>.delayed(Duration.zero);
    connected = await s.ownerCall('servers.connectStatus', {
      'operationId': connecting['operationId'],
    });
  }
  expect(connected['state'], 'succeeded');
  final inspected = await s.ownerRead('servers.executorInspect', {
    'profileId': fixture.profile,
  });
  final confirmed = await s.ownerCall('executor.confirm', {
    'profileId': fixture.profile,
    'challengeId': inspected['challengeId'],
    'hostId': peer.hostId,
  });
  expect(confirmed, isNotEmpty);
  expect(
    (await s.store.readExecutorEnrollments())[fixture.profile]!.hostId,
    peer.hostId,
  );
  expect(peer.requests.where((r) => r['method'] == 'hello'), isNotEmpty);
  expect(peer.errors, isEmpty);
  return (s, peer);
}

Future<Map<String, Object?>> plan(
  Setup s,
  Client client,
  String profile,
  int request, {
  int revision = 1,
}) async => success(
  await s.tool(client, 'plan_create', {
    'requestId': repository.id(request),
    'serverId': fixture.profile,
    'profileId': profile,
    'revision': revision,
    'parameters': {'message': 'executor unit'},
  }),
);

Future<void> approve(
  Setup s,
  Client client,
  Map<String, Object?> plan,
  int request,
) async {
  final asked = success(
    await s.tool(client, 'approval_request', {
      'requestId': repository.id(request),
      'planId': plan['planId'],
    }),
  );
  final decided = await s.ownerCall('approvals.decide', {
    'requestId': repository.id(request + 400),
    'approvalId': asked['approvalId'],
    'planDigest': asked['planDigest'],
    'decision': 'approved',
  });
  expect(decided, isNotEmpty);
  expect(
    s.store.snapshot.automation.approvals[asked['approvalId']]!.state,
    'approved',
  );
}

Future<Map<String, Object?>> waitJob(
  Setup s,
  Client client,
  String id,
  String state,
) async {
  final watch = Stopwatch()..start();
  Map<String, Object?> last = {};
  while (watch.elapsed < const Duration(seconds: 10)) {
    last = success(await s.tool(client, 'jobs_get', {'jobId': id}));
    if ((last['job'] as Map)['state'] == state) return last;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('expected real job $state, got ${(last['job'] as Map?)?['state']}');
}

void main() {
  test('all24 tools use actual factory and enrolled framed peer through success cancel reconcile', () async {
    final (s, peer) = await enrolled();
    final client = await s.client(await s.grant());
    success(
      await s.tool(client, 'server_connect', {'serverId': fixture.profile}),
    );
    final catalogue = success(
      await s.tool(client, 'recipes_list', {'serverId': fixture.profile}),
    );
    expect((catalogue['catalog'] as Map)['hostId'], peer.hostId);
    expect((catalogue['catalog'] as Map)['installEnabled'], isFalse);
    expect((catalogue['catalog'] as Map)['unavailable'], hasLength(2));
    final configuration = success(
      await s.tool(client, 'configuration_get', {
        'serverId': fixture.profile,
        'resourceId': 'system.motd',
        'refresh': true,
      }),
    );
    final observed = configuration['observation'] as Map;
    expect(observed['hostId'], peer.hostId);
    expect(observed['resourceId'], 'system.motd');
    expect(((observed['value'] as Map)['values'] as Map)['text'], peer.motd);

    success(await s.tool(client, 'profiles_validate', {'body': motdBody()}));
    final created = success(
      await s.tool(client, 'profiles_create', {
        'requestId': repository.id(3200),
        'name': 'executor profile',
        'body': motdBody(),
      }),
    );
    final profile = created['profileId'] as String;
    success(await s.tool(client, 'profiles_get', {'profileId': profile}));
    success(await s.tool(client, 'profiles_list', {}));
    success(
      await s.tool(client, 'profiles_update', {
        'requestId': repository.id(3201),
        'profileId': profile,
        'expectedRevision': 1,
        'body': motdBody(),
        'name': 'updated executor profile',
      }),
    );
    success(
      await s.tool(client, 'profiles_compare', {
        'profileId': profile,
        'fromRevision': 1,
        'toRevision': 2,
      }),
    );
    success(await s.tool(client, 'servers_list', {}));
    success(await s.tool(client, 'server_get', {'serverId': fixture.profile}));
    success(
      await s.tool(client, 'state_get', {
        'serverId': fixture.profile,
        'refresh': true,
      }),
    );
    success(await s.tool(client, 'logs_read', {'serverId': fixture.profile}));

    final first = await plan(s, client, profile, 3202, revision: 2);
    final fetched = success(
      await s.tool(client, 'plans_get', {'planId': first['planId']}),
    );
    expect(fetched, isNotEmpty);
    expect(
      s.store.snapshot.automation.plans[first['planId']]!.status,
      'runnable',
    );
    await approve(s, client, first, 3203);
    final admitted = success(
      await s.tool(client, 'apply', {
        'requestId': repository.id(3204),
        'planId': first['planId'],
      }),
    );
    final jobId = admitted['jobId'] as String;
    await waitJob(s, client, jobId, 'succeeded');
    expect(peer.permits, 1);
    expect(peer.effects, 1);
    expect(peer.motd, 'executor unit\n');
    final jobs = success(
      await s.tool(client, 'jobs_list', {'serverId': fixture.profile}),
    );
    expect(
      (jobs['items'] as List).map((r) => ((r as Map)['job'] as Map)['id']),
      contains(jobId),
    );
    final events = success(
      await s.tool(client, 'jobs_events', {'jobId': jobId}),
    );
    expect(events['events'], isNotEmpty);
    expect(
      (events['events'] as List).every((row) => (row as Map)['jobId'] == jobId),
      isTrue,
    );
    expect(
      s.store.snapshot.automation.desired.values.single.toJson()['lastJobId'],
      jobId,
    );
    final submits = peer.requests.where((r) => r['method'] == 'submit').length;
    expect(
      success(
        await s.tool(client, 'apply', {
          'requestId': repository.id(3204),
          'planId': first['planId'],
        }),
      ),
      admitted,
    );
    expect(peer.requests.where((r) => r['method'] == 'submit').length, submits);

    peer.queueWithoutChallenge = true;
    final second = await plan(s, client, profile, 3205, revision: 2);
    await approve(s, client, second, 3206);
    final queued = success(
      await s.tool(client, 'apply', {
        'requestId': repository.id(3207),
        'planId': second['planId'],
      }),
    );
    final secondId = queued['jobId'] as String;
    final watch = Stopwatch()..start();
    while (peer.attempts.values
            .where((a) => a.input['jobId'] == secondId && a.statusCalls > 0)
            .isEmpty &&
        watch.elapsed < const Duration(seconds: 5)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(
      peer.attempts.values
          .singleWhere((a) => a.input['jobId'] == secondId)
          .statusCalls,
      greaterThan(0),
    );
    success(
      await s.tool(client, 'jobs_cancel', {
        'requestId': repository.id(3208),
        'jobId': secondId,
      }),
    );
    await waitJob(s, client, secondId, 'cancelled');
    expect(peer.cancellations, 1);
    expect(peer.permits, 1);
    expect(peer.effects, 1);

    peer.queueWithoutChallenge = false;
    peer.unknownAfterAuthorize = true;
    final third = await plan(s, client, profile, 3209, revision: 2);
    await approve(s, client, third, 3210);
    final uncertain = success(
      await s.tool(client, 'apply', {
        'requestId': repository.id(3211),
        'planId': third['planId'],
      }),
    );
    final thirdId = uncertain['jobId'] as String;
    await waitJob(s, client, thirdId, 'unknown');
    final permits = peer.permits,
        submitCount = peer.requests
            .where((r) => r['method'] == 'submit')
            .length;
    success(
      await s.tool(client, 'jobs_reconcile', {
        'requestId': repository.id(3212),
        'jobId': thirdId,
      }),
    );
    await waitJob(s, client, thirdId, 'cancelled');
    expect(peer.reconciliations, 1);
    expect(peer.permits, permits);
    expect(
      peer.requests.where((r) => r['method'] == 'submit').length,
      submitCount,
    );
    expect(peer.effects, 1);
    success(
      await s.tool(client, 'profiles_archive', {
        'requestId': repository.id(3213),
        'profileId': profile,
        'expectedRevision': 2,
      }),
    );
    success(
      await s.tool(client, 'server_disconnect', {'serverId': fixture.profile}),
    );
    expect(s.successful, allToolNames);
    expect(peer.requests.map((r) => r['method']).toSet(), {
      'hello',
      'observe',
      'recipes',
      'preflight',
      'preflight_get',
      'submit',
      'status',
      'authorize_step',
      'cancel',
      'reconcile',
    });
    expect(peer.release.validations, greaterThan(0));
    expect(peer.errors, isEmpty);
  }, timeout: Timeout(const Duration(seconds: 30)));
}
