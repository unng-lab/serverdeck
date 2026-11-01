import 'dart:async';

import 'package:serverdeck_protocol/automation/job_observation.dart';
import 'package:test/test.dart';

import '../storage/actual_state_store_test.dart' as repository;
import '../support/actual_mcp_setup.dart';
import 'actual_router_executor_test.dart' as positive;
import 'actual_router_fences_test.dart' as fences;

void main() {
  for (final disconnect in [false, true]) {
    test(
      'actual owner/MCP observation is separate read data, disconnect=$disconnect',
      () async {
        final (s, peer, client, profile) = await fences.ready();
        peer.queueWithoutChallenge = true;
        final plan = await positive.plan(s, client, profile, 3500);
        await positive.approve(s, client, plan, 3501);
        final held = Completer<void>(), release = Completer<void>();
        addTearDown(() {
          if (!release.isCompleted) release.complete();
        });
        peer.beforeReply = (request, response, _) async {
          if (request['method'] == 'status' &&
              peer.attempts.values.single.statusCalls == 2) {
            held.complete();
            await release.future;
          }
        };
        final admitted = success(
          await s.tool(client, 'apply', {
            'requestId': repository.id(3502),
            'planId': plan['planId'],
          }),
        );
        final jobId = admitted['jobId'] as String;
        await held.future.timeout(const Duration(seconds: 5));
        final beforeRequests = peer.requests.length,
            beforeCommits = s.repository.provider.lastOpened!.commits;
        final viewed = success(
          await s.tool(client, 'jobs_get', {'jobId': jobId}),
        );
        final observation = LocalJobObservationView.fromJson(
          Map<String, Object?>.from(viewed['observation'] as Map),
        );
        expect(observation.state, JobObservationState.attached);
        expect(observation.generation, s.sessions.generation);
        expect(
          observation.attemptId,
          s.store.snapshot.automation.jobs[jobId]!.hostAttemptId,
        );
        expect(observation.lastSequence, 1);
        expect(observation.observedAt, isNotNull);
        final owner = success(await s.ownerCall('jobs.get', {'jobId': jobId}));
        expect(
          (owner['observation'] as Map)['attemptId'],
          observation.attemptId,
        );
        final list = success(await s.tool(client, 'jobs_list', {}));
        expect(
          ((list['items'] as List).single as Map)['observation'],
          isA<Map>(),
        );
        expect(peer.requests.length, beforeRequests);
        expect(s.repository.provider.lastOpened!.commits, beforeCommits);
        expect(
          s.store.snapshot.automation.jobs[jobId]!.toJson().containsKey(
            'observation',
          ),
          isFalse,
        );
        if (disconnect) {
          s.sessions.disconnect(client.channel);
          final detached = success(
            await s.ownerCall('jobs.get', {'jobId': jobId}),
          );
          expect((detached['observation'] as Map)['state'], 'detached');
          expect((detached['observation'] as Map)['lastSequence'], 1);
          release.complete();
          final watch = Stopwatch()..start();
          var state = '';
          while (watch.elapsed < const Duration(seconds: 5)) {
            state =
                (success(await s.ownerCall('jobs.get', {'jobId': jobId}))['job']
                        as Map)['state']
                    as String;
            if (state == 'unknown') break;
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          expect(state, 'unknown');
          expect(peer.cancellations, 0);
          expect(peer.reconciliations, 0);
        } else {
          release.complete();
          success(
            await s.tool(client, 'jobs_cancel', {
              'requestId': repository.id(3503),
              'jobId': jobId,
            }),
          );
          final terminal = await positive.waitJob(
            s,
            client,
            jobId,
            'cancelled',
          );
          expect((terminal['observation'] as Map)['state'], 'detached');
        }
        expect(peer.permits, 0);
        expect(peer.effects, 0);
        expect(peer.errors, isEmpty);
        expect(
          peer.requests.where((r) => r['method'] == 'submit'),
          hasLength(1),
        );
      },
    );
  }
}
