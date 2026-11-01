import 'dart:async';

import 'package:serverdeck_engine/mcp/grants.dart';
import 'package:test/test.dart';

import '../automation/job_controls_test.dart' show Clock;
import '../storage/actual_state_store_test.dart' as repository;
import '../support/actual_mcp_setup.dart';
import '../support/schema3_fixture.dart' as fixture;
import 'job_reconciliation_test.dart' as recovery;
import '../remote/ssh_io_policy_test.dart' as bytes;
import 'actual_router_executor_test.dart' as positive;
import 'actual_router_fences_test.dart' as fences;

void main() {
  test(
    'retired connection discards stop ACK before a fresh explicit cancel',
    () async {
      final (s, peer, client, job) = await recovery.uncertain();
      bytes.Session? stopSession;
      peer.beforeReply = (request, response, session) async {
        if (request['method'] == 'cancel') stopSession = session;
      };
      final original = s.store.snapshot.automation.jobs[job]!;
      success(
        await s.tool(client, 'jobs_cancel', {
          'requestId': repository.id(3603),
          'jobId': job,
        }),
      );
      final first = Stopwatch()..start();
      while (stopSession == null &&
          first.elapsed < const Duration(seconds: 3)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(stopSession, isNotNull);
      await stopSession!.done.timeout(const Duration(seconds: 3));
      expect(peer.cancellations, 1);
      expect(s.store.snapshot.automation.jobs[job]!.state, 'unknown');
      success(
        await s.tool(client, 'server_disconnect', {
          'serverId': fixture.profile,
        }),
      );
      await s.ownerCall('servers.disconnect', {'profileId': fixture.profile});
      var retired = await s.ownerCall('servers.connection', {
        'profileId': fixture.profile,
      });
      final retiring = Stopwatch()..start();
      while (retired['state'] != 'disconnected' &&
          retiring.elapsed < const Duration(seconds: 3)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        retired = await s.ownerCall('servers.connection', {
          'profileId': fixture.profile,
        });
      }
      expect(retired['state'], 'disconnected', reason: '$retired');
      final connecting = await s.ownerCall('servers.connect', {
        'profileId': fixture.profile,
      });
      var status = await s.ownerCall('servers.connectStatus', {
        'operationId': connecting['operationId'],
      });
      final watch = Stopwatch()..start();
      while (status['state'] == 'running' &&
          watch.elapsed < const Duration(seconds: 3)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        status = await s.ownerCall('servers.connectStatus', {
          'operationId': connecting['operationId'],
        });
      }
      expect(status['state'], 'succeeded', reason: '$status');
      success(
        await s.tool(client, 'server_connect', {'serverId': fixture.profile}),
      );
      final before = peer.requests.length;
      success(
        await s.tool(client, 'jobs_cancel', {
          'requestId': repository.id(3604),
          'jobId': job,
        }),
      );
      final again = Stopwatch()..start();
      while (peer.cancellations < 2 &&
          again.elapsed < const Duration(seconds: 3)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(peer.cancellations, 2);
      await stopSession!.done.timeout(const Duration(seconds: 3));
      final calls = peer.requests.skip(before).toList();
      final stops = calls.where((r) => r['method'] == 'cancel').toList();
      expect(stops, hasLength(1));
      expect((stops.single['params'] as Map)['requestId'], job);
      expect(
        (stops.single['params'] as Map)['attemptId'],
        original.hostAttemptId,
      );
      expect(calls.where((r) => r['method'] == 'status'), hasLength(1));
      expect(
        calls.where(
          (r) => r['method'] == 'submit' || r['method'] == 'authorize_step',
        ),
        isEmpty,
      );
      expect(s.store.snapshot.automation.jobs[job]!.state, 'unknown');
      expect(
        s.store.snapshot.automation.jobs[job]!.hostAttemptId,
        original.hostAttemptId,
      );
      expect(
        s.store.snapshot.automation.jobs[job]!.authority.toJson(),
        original.authority.toJson(),
      );
      for (final id in [3603, 3604]) {
        expect(
          s.store.snapshot.automation.receipts.values.where(
            (r) => r.requestId == repository.id(id),
          ),
          hasLength(1),
        );
      }
      expect(peer.permits, 1);
      expect(peer.effects, 0);
      expect(peer.errors, isEmpty);
    },
  );
  for (final scenario in [
    'handoff',
    'expired',
    'replacement',
    'revoked',
    'suspend',
  ]) {
    test('actual accepted control physical drain: $scenario', () async {
      final clock = Clock();
      final (s, peer, client, profile) = await fences.ready(readClock: clock);
      bytes.Session? heldSession;
      addTearDown(() async {
        await heldSession?.finish();
      });
      var held = false;
      peer.unknownAfterAuthorize = true;
      peer.beforeReply = (request, response, session) async {
        if (request['method'] == 'status' &&
            response['state'] == 'unknown' &&
            !held) {
          held = true;
          session.autoClose = false;
          heldSession = session;
        }
      };
      final plan = await positive.plan(s, client, profile, 3600);
      await positive.approve(s, client, plan, 3601);
      final ack = success(
        await s.tool(client, 'apply', {
          'requestId': repository.id(3602),
          'planId': plan['planId'],
        }),
      );
      final job = ack['jobId'] as String;
      await positive.waitJob(s, client, job, 'unknown');
      expect(held, isTrue);
      final identity = s.store.snapshot.automation.jobs[job]!;
      success(
        await s.tool(client, 'jobs_reconcile', {
          'requestId': repository.id(3603),
          'jobId': job,
        }),
      );
      expect(s.store.snapshot.automation.jobs[job]!.state, 'reconciling');
      expect(peer.reconciliations, 0);
      expect(heldSession!.closes, greaterThan(0));
      if (scenario == 'replacement') {
        final sequence = s.store.snapshot.automation.jobs[job]!.nextSequence;
        clock.elapsed = const Duration(seconds: 2);
        success(
          await s.tool(client, 'jobs_reconcile', {
            'requestId': repository.id(3604),
            'jobId': job,
          }),
        );
        expect(s.store.snapshot.automation.jobs[job]!.nextSequence, sequence);
      }
      if (scenario == 'expired' || scenario == 'replacement') {
        clock.elapsed = const Duration(seconds: 31);
        // Engine monotonic budget changes; the actual HMAC grant remains live.
        expect(
          s.store.currentMcpGrant(client.grantId, at: utcNow()).id,
          client.grantId,
        );
      }
      if (scenario == 'revoked') {
        await s.store.mutateOwnerGrant(
          OwnerGrantCommand.parse('grant.revoke', {
            'requestId': repository.id(3605),
            'grantId': client.grantId,
            'expectedRevision': 1,
          }),
          clock: utcNow,
        );
      }
      Future<void>? paused;
      if (scenario == 'suspend') {
        paused = s.services.jobs.suspend();
        var settled = false;
        paused.then((_) => settled = true).ignore();
        await Future<void>.delayed(Duration.zero);
        expect(settled, isFalse);
        expect(peer.reconciliations, 0);
      }
      await heldSession!.finish();
      if (paused != null) {
        await paused;
        s.services.jobs.resume();
      }
      final succeeds = scenario == 'handoff' || scenario == 'replacement';
      final watch = Stopwatch()..start();
      while (s.store.snapshot.automation.jobs[job]!.state !=
              (succeeds ? 'cancelled' : 'unknown') &&
          watch.elapsed < const Duration(seconds: 3)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final retained = s.store.snapshot.automation.jobs[job]!;
      expect(retained.state, succeeds ? 'cancelled' : 'unknown');
      expect(peer.reconciliations, succeeds ? 1 : 0);
      expect(peer.requests.where((r) => r['method'] == 'submit'), hasLength(1));
      expect(peer.requests.where((r) => r['method'] == 'cancel'), isEmpty);
      expect(peer.permits, 1);
      expect(peer.effects, 0);
      expect(retained.hostAttemptId, identity.hostAttemptId);
      expect(retained.planDigest, identity.planDigest);
      expect(retained.authority.toJson(), identity.authority.toJson());
      expect(
        s.store.snapshot.automation.receipts.values.where(
          (r) => r.requestId == repository.id(3603),
        ),
        hasLength(1),
      );
      expect(peer.errors, isEmpty);
    });
  }
}
