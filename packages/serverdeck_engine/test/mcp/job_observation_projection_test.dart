import 'dart:async';

import 'package:serverdeck_protocol/automation/job_observation.dart';
import 'package:test/test.dart';

import '../storage/actual_state_store_test.dart' as repository;
import '../support/actual_mcp_setup.dart';
import 'actual_router_executor_test.dart' as positive;
import '../support/actual_direct_setup.dart';

void main() {
  for (final disconnect in [false, true]) {
    test(
      'actual owner/MCP observation is separate read data, disconnect=$disconnect',
      () async {
        final (s, peer, client, profile) = await directReady();
        peer.stopBeforeStart = true;
        final plan = await positive.plan(s, client, profile, 3500);
        await positive.approve(s, client, plan, 3501);
        final held = Completer<void>(), release = Completer<void>();
        addTearDown(() {
          if (!release.isCompleted) release.complete();
        });
        peer.reads.beforeOutput = (command) async {
          // Retain one attached queued sample, then pause the actual finite
          // pre-permit read. No job/projection method is substituted.
          if (command.kind == 'packages' &&
              peer.records['admission'] != null &&
              !held.isCompleted) {
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
          expect(
            peer.requests.where((command) => command.kind == 'stop'),
            isEmpty,
          );
          expect(
            peer.requests.where((command) => command.kind == 'terminal'),
            isEmpty,
          );
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
        expect(peer.launches, 0);
        expect(s.store.snapshot.automation.jobs[jobId]!.sshDispatch, isNull);
        expect(peer.effects, 0);
        expect(
          peer.requests.where((command) => command.kind == 'reserve'),
          hasLength(1),
        );
      },
    );
  }
}
