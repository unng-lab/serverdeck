import 'dart:async';
import 'dart:convert';

import 'package:serverdeck_engine/mcp/grants.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:test/test.dart';

import '../storage/actual_state_store_test.dart' as repository;
import '../support/actual_mcp_setup.dart';
import '../support/executor_byte_peer.dart';
import '../support/memory_workspace_provider.dart';
import '../support/schema3_fixture.dart' as fixture;
import 'actual_router_executor_test.dart' as positive;
import 'actual_router_fences_test.dart' as fences;
import 'job_control_roles_test.dart' show until, ownerControl, Held;

final class Retained {
  Retained(
    this.old,
    this.peer,
    this.client,
    this.profile,
    this.bytes,
    this.job,
  );
  final Setup old;
  final ExecutorBytePeer peer;
  final Client client;
  final String profile;
  final List<int> bytes;
  final AutomationJobRecord job;
  static Future<Retained> capture(String state, {bool revoked = false}) async {
    final (s, peer, client, profile) = await fences.ready();
    peer.queueWithoutChallenge = {
      'cancel-requested',
      'cancelled',
    }.contains(state);
    final snapshots = <String, List<int>>{};
    Future<void>? paused;
    s.repository.provider.afterCommit = () {
      final bytes = s.repository.provider.readBytes();
      final rows = MemoryWorkspaceProvider.decode(
        bytes,
      )['StoredAutomationJob']!;
      if (rows.isEmpty) return;
      final job = jsonDecode(rows.single.payload) as Map<String, Object?>;
      snapshots.putIfAbsent(job['state'] as String, () => List.of(bytes));
      if (state == 'queued' && job['state'] == 'queued' && paused == null) {
        paused = s.services.jobs.suspend();
        paused!.ignore();
      }
    };
    peer.beforeReply = (request, response, session) async {
      if (request['method'] == 'submit') {
        if ({'running', 'unknown', 'reconciling'}.contains(state)) {
          // The root journal accepted submit; the framed ACK is lost at EOF.
          session.close();
        }
        if (state == 'failed') {
          final attempt = peer.attempts.values.single;
          attempt.state = 'failed';
          attempt.event('terminal', 'STEP_FAILED');
        }
      }
      if (state == 'failed' && request['method'] == 'status')
        response['failureCode'] = 'STEP_FAILED';
      if (state == 'reconciling' && request['method'] == 'reconcile')
        response['childrenStopped'] = false;
    };
    final plan = await positive.plan(s, client, profile, 3600);
    await positive.approve(s, client, plan, 3601);
    final result = await s.tool(client, 'apply', {
      'requestId': repository.id(3602),
      'planId': plan['planId'],
    });
    String job;
    if (state == 'queued') {
      fences.toolError(result, 'SERVICE_UNAVAILABLE');
      await paused;
      job = s.store.snapshot.automation.jobs.values.single.id;
      expect(peer.requests.where((r) => r['method'] == 'submit'), isEmpty);
    } else {
      job = success(result)['jobId'] as String;
      if ({'cancel-requested', 'cancelled'}.contains(state)) {
        await until(s, () => peer.attempts.values.single.statusCalls > 0);
        success(
          await s.tool(client, 'jobs_cancel', {
            'requestId': repository.id(3603),
            'jobId': job,
          }),
        );
        await positive.waitJob(s, client, job, 'cancelled');
      } else if (state == 'reconciling') {
        await positive.waitJob(s, client, job, 'unknown');
        success(
          await s.tool(client, 'jobs_reconcile', {
            'requestId': repository.id(3603),
            'jobId': job,
          }),
        );
        await until(
          s,
          () =>
              peer.reconciliations == 1 &&
              s.store.snapshot.automation.jobs[job]!.state == 'unknown',
        );
      } else {
        await positive.waitJob(
          s,
          client,
          job,
          state == 'running' ? 'unknown' : state,
        );
      }
    }
    if (revoked) {
      await s.store.mutateOwnerGrant(
        OwnerGrantCommand.parse('grant.revoke', {
          'requestId': repository.id(3619),
          'grantId': client.grantId,
          'expectedRevision': 1,
        }),
        clock: utcNow,
      );
      snapshots[state] = List.of(s.repository.provider.readBytes());
    }
    s.repository.provider.afterCommit = null;
    expect(
      snapshots.containsKey(state),
      isTrue,
      reason: 'capture from actual committed admission/progress, not constructed rows',
    );
    final bytes = snapshots[state]!;
    final row = MemoryWorkspaceProvider.decode(
      bytes,
    )['StoredAutomationJob']!.single;
    final captured = AutomationJobRecord.fromJson(
      jsonDecode(row.payload) as Map<String, Object?>,
    );
    expect(captured.id, job);
    expect(captured.state, state);
    await s.close();
    expect(s.repository.provider.hasOpenInstance, isFalse);
    peer.beforeReply = null;
    return Retained(s, peer, client, profile, bytes, captured);
  }

  Future<Setup> reopen() async {
    // Only this declared RAM provider is reset to the captured crash image.
    // The production storage/runtime and user files are never touched.
    old.repository.provider.persistBytes(List.of(bytes));
    return Setup.reopen(
      old.repository,
      generation: repository.id(3800),
      executorRelease: peer.release,
      executor: peer.attach,
    );
  }
}

void main() {
  for (final event in ['detach', 'power', 'close']) {
    test(
      'actual $event drains an admitted attempt and new generation never restores its permit',
      () async {
        final h = await Held.create(), peer = h.peer;
        final original = h.s.store.snapshot.automation.jobs[h.job]!;
        if (event == 'detach') h.s.sessions.disconnect(h.client.channel);
        if (event == 'power') {
          final pause = h.s.services.suspend();
          var paused = false;
          pause.settled.then((_) => paused = true).ignore();
          await Future<void>.delayed(Duration.zero);
          expect(paused, isFalse);
          await h.session.finish();
          await pause.settled;
          final calls = peer.requests.length;
          h.s.services.resume(pause);
          await Future<void>.delayed(Duration.zero);
          expect(peer.requests.length, calls);
        }
        final closing = h.s.close();
        var closed = false;
        closing.then((_) => closed = true).ignore();
        if (event != 'power') {
          await Future<void>.delayed(Duration.zero);
          expect(closed, isFalse);
          await h.session.finish();
        }
        await closing;
        final calls = peer.requests.length;
        final s = await Setup.reopen(
          h.s.repository,
          generation: repository.id(3800),
          executorRelease: peer.release,
          executor: peer.attach,
        );
        expect(s.io.attempts, isEmpty);
        expect(peer.requests.length, calls);
        final job = s.store.snapshot.automation.jobs[h.job]!;
        expect(job.state, 'unknown');
        expect(job.hostAttemptId, original.hostAttemptId);
        expect(job.authority.toJson(), original.authority.toJson());
        final client = await s.client(h.client.grantId);
        final view = success(
          await s.tool(client, 'jobs_get', {'jobId': h.job}),
        );
        expect((view['observation'] as Map)['state'], 'detached');
        expect(
          (view['observation'] as Map)['generation'],
          s.sessions.generation,
        );
        success(
          await s.tool(client, 'apply', {
            'requestId': repository.id(3602),
            'planId': job.immutablePlanId,
          }),
        );
        expect(peer.requests.length, calls);
        success(
          await s.tool(client, 'server_connect', {'serverId': fixture.profile}),
        );
        success(
          await s.tool(client, 'jobs_reconcile', {
            'requestId': repository.id(3623),
            'jobId': h.job,
          }),
        );
        await positive.waitJob(s, client, h.job, 'cancelled');
        expect(
          peer.requests.where((r) => r['method'] == 'submit'),
          hasLength(1),
        );
        expect(
          peer.requests.where((r) => r['method'] == 'authorize_step'),
          hasLength(1),
        );
        expect(peer.cancellations, 0);
        expect(peer.permits, 1);
        expect(peer.effects, 0);
        expect(peer.errors, isEmpty);
        expect(s.repository.source.lease.closes, 0);
      },
    );
  }
  test('checked reopen keeps revoked grant retired but permits actual owner observational recovery', () async {
    final source = await Retained.capture('unknown', revoked: true),
        peer = source.peer;
    final calls = peer.requests.length;
    final s = await source.reopen();
    expect(peer.requests.length, calls);
    expect(s.io.attempts, isEmpty);
    expect(
      s.store.snapshot.automation.grants[source.client.grantId]!.revokedAt,
      isNotNull,
    );
    await expectLater(s.client(source.client.grantId), throwsStateError);
    var denied = await s.ownerCall('jobs.apply', {
      'requestId': repository.id(3602),
      'planId': source.job.immutablePlanId,
    });
    final operation = denied['operationId'];
    final watch = Stopwatch()..start();
    while (denied['state'] == 'running' &&
        watch.elapsed < const Duration(seconds: 3)) {
      await Future<void>.delayed(Duration.zero);
      denied = await s.ownerCall('automation.status', {
        'operationId': operation,
      });
    }
    expect(denied['state'], 'done');
    final failure = (denied['result'] as Map)['structuredContent'] as Map;
    expect(failure['ok'], isFalse);
    expect((failure['error'] as Map)['code'], 'FORBIDDEN');
    expect(peer.requests.length, calls);
    expect(s.io.attempts, isEmpty);
    final connecting = await s.ownerCall('servers.connect', {
      'profileId': fixture.profile,
    });
    var connection = await s.ownerCall('servers.connectStatus', {
      'operationId': connecting['operationId'],
    });
    final wait = Stopwatch()..start();
    while (connection['state'] == 'running' &&
        wait.elapsed < const Duration(seconds: 3)) {
      await Future<void>.delayed(Duration.zero);
      connection = await s.ownerCall('servers.connectStatus', {
        'operationId': connecting['operationId'],
      });
    }
    expect(connection['state'], 'succeeded');
    await ownerControl(s, 'jobs.reconcile', source.job.id, 3620);
    await until(
      s,
      () =>
          s.store.snapshot.automation.jobs[source.job.id]!.state == 'cancelled',
    );
    final job = s.store.snapshot.automation.jobs[source.job.id]!;
    expect(job.grantId, source.client.grantId);
    expect(job.hostAttemptId, source.job.hostAttemptId);
    expect(job.authority.toJson(), source.job.authority.toJson());
    final receipt = s.store.snapshot.automation.receipts[repository.id(3620)]!;
    expect(receipt.originGrantId, isNull);
    expect(receipt.toJson()['objectGrantId'], source.client.grantId);
    expect(
      s.store.snapshot.automation.grants[source.client.grantId]!.revokedAt,
      isNotNull,
    );
    expect(peer.requests.where((r) => r['method'] == 'submit'), hasLength(1));
    expect(peer.permits, 0);
    expect(peer.effects, 0);
    expect(peer.errors, isEmpty);
  });
  for (final state in [
    'queued',
    'running',
    'cancel-requested',
    'unknown',
    'reconciling',
    'succeeded',
    'failed',
    'cancelled',
  ]) {
    test(
      'actual checked reopen recovers $state without submit or authority restoration',
      () async {
        final source = await Retained.capture(state), peer = source.peer;
        final calls = peer.requests.length,
            permits = peer.permits,
            effects = peer.effects;
        final previousRows = MemoryWorkspaceProvider.decode(source.bytes);
        final s = await source.reopen();
        expect(s.sessions.generation, repository.id(3800));
        expect(s.sessions.generation, isNot(source.old.sessions.generation));
        expect(s.io.attempts, isEmpty);
        expect(peer.requests.length, calls);
        expect((peer.permits, peer.effects), (permits, effects));
        expect(s.repository.provider.opens, 2);
        expect(s.repository.provider.preflights, 2);
        final changed = {
          'queued',
          'running',
          'cancel-requested',
          'reconciling',
        }.contains(state);
        final expected = state == 'queued'
            ? 'cancelled'
            : changed
            ? 'unknown'
            : state;
        final retained = s.store.snapshot.automation.jobs[source.job.id]!;
        expect(retained.state, expected);
        expect(retained.hostAttemptId, source.job.hostAttemptId);
        expect(retained.immutablePlanId, source.job.immutablePlanId);
        expect(retained.requestId, source.job.requestId);
        expect(retained.authority.toJson(), source.job.authority.toJson());
        expect(retained.cancelRequested, source.job.cancelRequested);
        expect(
          retained.nextSequence,
          source.job.nextSequence + (changed ? 1 : 0),
        );
        if (!changed) expect(retained.toJson(), source.job.toJson());
        if (changed)
          expect(
            retained.outcome!.effects,
            state == 'queued' ? 'none' : 'uncertain',
          );
        final afterRows = repository.rawRows(s.store);
        for (final family in previousRows.entries) {
          if ([
            'StoredAutomationJob',
            'StoredAutomationEvent',
          ].contains(family.key))
            continue;
          final before =
              family.value
                  .map((r) => (r.nativeId, r.entityId, r.payload))
                  .toList()
                ..sort((a, b) => a.$1.compareTo(b.$1));
          expect(
            afterRows[family.key],
            before,
            reason: 'retained native rows of ${family.key}',
          );
        }
        final events = s.store.snapshot.rows['StoredAutomationEvent']!;
        for (final old in previousRows['StoredAutomationEvent']!) {
          expect(
            events.any(
              (r) =>
                  r.nativeId == old.nativeId &&
                  r.entityId == old.entityId &&
                  r.payload == old.payload,
            ),
            isTrue,
          );
        }
        expect(
          events.length,
          previousRows['StoredAutomationEvent']!.length + (changed ? 1 : 0),
        );
        await expectLater(
          source.old.tool(source.client, 'jobs_get', {'jobId': retained.id}),
          throwsStateError,
        );
        final client = await s.client(source.client.grantId);
        final view = success(
          await s.tool(client, 'jobs_get', {'jobId': retained.id}),
        );
        final observation = view['observation'] as Map;
        expect(observation['generation'], s.sessions.generation);
        expect(observation['attemptId'], retained.hostAttemptId);
        expect(observation['state'], 'detached');
        expect(observation['lastSequence'], isNull);
        expect(observation['observedAt'], isNull);
        final receipt =
            s.store.snapshot.automation.receipts[repository.id(3602)]!;
        final replay = success(
          await s.tool(client, 'apply', {
            'requestId': repository.id(3602),
            'planId': retained.immutablePlanId,
          }),
        );
        expect(replay, receipt.result);
        expect(peer.requests.length, calls);
        expect(s.io.attempts, isEmpty);
        if (expected != 'unknown') {
          final terminal = retained.toJson();
          final events = s.store.snapshot.automation.events.length;
          for (final tool in ['jobs_cancel', 'jobs_reconcile']) {
            success(
              await s.tool(client, tool, {
                'requestId': repository.id(tool == 'jobs_cancel' ? 3624 : 3625),
                'jobId': retained.id,
              }),
            );
          }
          expect(
            s.store.snapshot.automation.jobs[retained.id]!.toJson(),
            terminal,
          );
          expect(s.store.snapshot.automation.events.length, events);
          expect(peer.requests.length, calls);
          expect(s.io.attempts, isEmpty);
        }
        if (expected == 'unknown') {
          success(
            await s.tool(client, 'server_connect', {
              'serverId': fixture.profile,
            }),
          );
          final plan = await positive.plan(s, client, source.profile, 3610);
          await positive.approve(s, client, plan, 3611);
          fences.toolError(
            await s.tool(client, 'apply', {
              'requestId': repository.id(3612),
              'planId': plan['planId'],
            }),
            'HOST_BUSY',
          );
          expect((peer.permits, peer.effects), (permits, effects));
          success(
            await s.tool(client, 'jobs_reconcile', {
              'requestId': repository.id(3613),
              'jobId': retained.id,
            }),
          );
          await positive.waitJob(s, client, retained.id, 'cancelled');
          peer.queueWithoutChallenge = false;
          peer.unknownAfterAuthorize = false;
          final next = success(
            await s.tool(client, 'apply', {
              'requestId': repository.id(3612),
              'planId': plan['planId'],
            }),
          );
          expect(next['jobId'], isNot(retained.id));
          await positive.waitJob(
            s,
            client,
            next['jobId'] as String,
            'succeeded',
          );
          expect(peer.permits, permits + 1);
          expect(peer.effects, effects + 1);
        }
        expect(peer.errors, isEmpty);
        expect(s.repository.source.lease.closes, 0);
      },
    );
  }
  for (final fault in ['missing', 'unavailable', 'foreign']) {
    test(
      'reopened actual $fault receipt stays occupied until separate valid recovery',
      () async {
        final source = await Retained.capture('running'), peer = source.peer;
        final attempt = peer.attempts.values.single;
        final s = await source.reopen(),
            client = await s.client(source.client.grantId);
        success(
          await s.tool(client, 'server_connect', {'serverId': fixture.profile}),
        );
        if (fault == 'missing') peer.attempts.clear();
        if (fault == 'unavailable')
          peer.controlFailure = 'EXECUTOR_UNAVAILABLE';
        if (fault == 'foreign')
          peer.beforeReply = (request, response, _) async {
            if (request['method'] == 'status')
              response['attemptId'] = repository.id(3801);
          };
        success(
          await s.tool(client, 'jobs_reconcile', {
            'requestId': repository.id(3613),
            'jobId': source.job.id,
          }),
        );
        await until(
          s,
          () =>
              peer.requests.any((r) => r['method'] == 'reconcile') &&
              s.store.snapshot.automation.jobs[source.job.id]!.state ==
                  'unknown',
        );
        final plan = await positive.plan(s, client, source.profile, 3610);
        await positive.approve(s, client, plan, 3611);
        fences.toolError(
          await s.tool(client, 'apply', {
            'requestId': repository.id(3612),
            'planId': plan['planId'],
          }),
          'HOST_BUSY',
        );
        expect(
          peer.requests.where((r) => r['method'] == 'submit'),
          hasLength(1),
        );
        expect(peer.permits, 0);
        expect(peer.effects, 0);
        peer.attempts[source.job.hostAttemptId] = attempt;
        peer.controlFailure = null;
        peer.beforeReply = null;
        success(
          await s.tool(client, 'jobs_reconcile', {
            'requestId': repository.id(3614),
            'jobId': source.job.id,
          }),
        );
        await positive.waitJob(s, client, source.job.id, 'cancelled');
        final next = success(
          await s.tool(client, 'apply', {
            'requestId': repository.id(3612),
            'planId': plan['planId'],
          }),
        );
        await positive.waitJob(s, client, next['jobId'] as String, 'succeeded');
        expect(peer.permits, 1);
        expect(peer.effects, 1);
        expect(peer.errors, isEmpty);
      },
    );
  }
}
