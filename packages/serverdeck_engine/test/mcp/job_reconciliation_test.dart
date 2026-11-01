import 'dart:async';

import 'package:test/test.dart';

import '../storage/actual_state_store_test.dart' as repository;
import '../support/actual_mcp_setup.dart';
import '../support/executor_byte_peer.dart';
import 'actual_router_executor_test.dart' as positive;
import 'actual_router_fences_test.dart' as fences;

Future<(Setup, ExecutorBytePeer, Client, String)> uncertain() async {
  final (s, peer, client, profile) = await fences.ready();
  peer.unknownAfterAuthorize = true;
  final plan = await positive.plan(s, client, profile, 3600);
  await positive.approve(s, client, plan, 3601);
  final admitted = success(
    await s.tool(client, 'apply', {
      'requestId': repository.id(3602),
      'planId': plan['planId'],
    }),
  );
  final job = admitted['jobId'] as String;
  await positive.waitJob(s, client, job, 'unknown');
  expect(peer.permits, 1);
  expect(peer.effects, 0);
  return (s, peer, client, job);
}

Future<String> settled(Setup s, Client client, String job) async {
  final watch = Stopwatch()..start();
  var state = '';
  while (watch.elapsed < const Duration(seconds: 5)) {
    final value = success(await s.tool(client, 'jobs_get', {'jobId': job}));
    state = (value['job'] as Map)['state'] as String;
    if (!{
      'queued',
      'running',
      'cancel-requested',
      'reconciling',
    }.contains(state))
      break;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return state;
}

void main() {
  for (final fault in [
    'children',
    'floor',
    'foreign',
    'state',
    'negative',
    'sequence_type',
    'boolean',
    'status_foreign',
    'postchecks',
  ]) {
    test(
      'actual reconciliation refuses $fault terminal evidence and keeps host occupied',
      () async {
        final (s, peer, client, job) = await uncertain();
        var injected = false;
        peer.beforeReply = (request, response, _) async {
          if (request['method'] == 'reconcile') {
            injected = true;
            switch (fault) {
              case 'children':
                response['childrenStopped'] = false;
              case 'floor':
                response['sequence'] = (response['sequence'] as int) + 100;
              case 'foreign':
                response['attemptId'] = repository.id(3609);
              case 'state':
                response['state'] = 'PRIVATE_INVALID_STATE';
              case 'negative':
                response['sequence'] = -1;
              case 'sequence_type':
                response['sequence'] = '1';
              case 'boolean':
                response['childrenStopped'] = 'true';
              case 'postchecks':
                peer.attempts.values.single.state = 'succeeded';
                peer.attempts.values.single.step = 1;
                response['state'] = 'succeeded';
            }
          }
          if (request['method'] == 'status') {
            if (fault == 'status_foreign')
              response['attemptId'] = repository.id(3609);
            if (fault == 'postchecks') response['checks'] = <Object?>[];
          }
        };
        success(
          await s.tool(client, 'jobs_reconcile', {
            'requestId': repository.id(3603),
            'jobId': job,
          }),
        );
        expect(await settled(s, client, job), 'unknown');
        expect(injected, isTrue);
        expect(
          s.store.snapshot.automation.jobs[job]!.outcome?.safeCode,
          'UNKNOWN_OUTCOME',
        );
        expect(
          success(await s.tool(client, 'jobs_get', {'jobId': job})).toString(),
          isNot(contains('PRIVATE_INVALID_STATE')),
        );
        expect(peer.permits, 1);
        expect(peer.effects, 0);
        expect(
          peer.requests.where((r) => r['method'] == 'submit'),
          hasLength(1),
        );
        expect(s.store.snapshot.automation.desired, isEmpty);
        expect(s.store.isReady, isTrue);
        peer.beforeReply = null;
        peer.unknownAfterAuthorize = false;
        final profile = s.store.snapshot.automation.profiles.keys.single;
        final nextPlan = await positive.plan(s, client, profile, 3610);
        await positive.approve(s, client, nextPlan, 3611);
        final args = <String, Object?>{
          'requestId': repository.id(3612),
          'planId': nextPlan['planId'],
        };
        final commits = s.repository.provider.lastOpened!.commits;
        fences.toolError(await s.tool(client, 'apply', args), 'HOST_BUSY');
        expect(s.repository.provider.lastOpened!.commits, commits);
        expect(s.store.snapshot.automation.jobs, hasLength(1));
        if (fault == 'children') {
          success(
            await s.tool(client, 'jobs_reconcile', {
              'requestId': repository.id(3613),
              'jobId': job,
            }),
          );
          expect(await settled(s, client, job), 'cancelled');
          final next = success(await s.tool(client, 'apply', args));
          await positive.waitJob(
            s,
            client,
            next['jobId'] as String,
            'succeeded',
          );
          expect(
            peer.requests.where((r) => r['method'] == 'submit'),
            hasLength(2),
          );
          expect(peer.permits, 2);
          expect(peer.effects, 1);
        }
        expect(peer.errors, isEmpty);
      },
    );
  }

  test('actual cancel of unknown preserves graph and occupancy until explicit stopped reconciliation', () async {
    final (s, peer, client, job) = await uncertain();
    success(
      await s.tool(client, 'jobs_cancel', {
        'requestId': repository.id(3603),
        'jobId': job,
      }),
    );
    final watch = Stopwatch()..start();
    while (peer.cancellations == 0 &&
        watch.elapsed < const Duration(seconds: 5)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(peer.cancellations, 1);
    expect(await settled(s, client, job), 'unknown');
    expect(s.store.snapshot.automation.jobs[job]!.cancelRequested, isTrue);
    expect(s.store.isReady, isTrue);
    expect(peer.reconciliations, 0);
    success(
      await s.tool(client, 'jobs_reconcile', {
        'requestId': repository.id(3604),
        'jobId': job,
      }),
    );
    expect(await settled(s, client, job), 'cancelled');
    expect(peer.permits, 1);
    expect(peer.effects, 0);
    expect(peer.requests.where((r) => r['method'] == 'submit'), hasLength(1));
    expect(peer.errors, isEmpty);
  });

  test('actual negative submit ACK sequence leaves accepted attempt unknown before any step permit', () async {
    final (s, peer, client, profile) = await fences.ready();
    final plan = await positive.plan(s, client, profile, 3600);
    await positive.approve(s, client, plan, 3601);
    peer.beforeReply = (request, response, _) async {
      if (request['method'] == 'submit') response['sequence'] = -1;
    };
    final admitted = success(
      await s.tool(client, 'apply', {
        'requestId': repository.id(3602),
        'planId': plan['planId'],
      }),
    );
    expect(await settled(s, client, admitted['jobId'] as String), 'unknown');
    expect(peer.attempts, hasLength(1));
    expect(peer.requests.where((r) => r['method'] == 'submit'), hasLength(1));
    fences.noRootEffect(peer);
    expect(s.store.isReady, isTrue);
    expect(peer.errors, isEmpty);
  });
}
