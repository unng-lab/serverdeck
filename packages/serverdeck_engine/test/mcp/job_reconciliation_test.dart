import 'dart:convert';

import 'package:serverdeck_engine/remote/direct_ssh_records.dart';

import 'dart:async';

import 'package:test/test.dart';

import '../storage/actual_state_store_test.dart' as repository;
import '../support/actual_mcp_setup.dart';
import '../support/direct_host_byte_peer.dart';
import '../support/actual_direct_setup.dart';
import 'actual_router_executor_test.dart' as positive;
import 'actual_router_fences_test.dart' as fences;

/// A staged permit expired before start; root receipts exist but launch ACK
/// was lost. Actual driver/store/authorization are used, with RAM OS facts.
Future<(Setup, DirectHostBytePeer, Client, String)> directUncertain() async {
  final (s, peer, client, profile) = await directReady();
  peer.stopBeforeStart = true;
  peer.dropLaunchAck = true;
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
  expect(s.store.snapshot.automation.jobs[job]!.sshDispatch, isNotNull);
  expect((peer.launches, peer.effects), (1, 0));
  return (s, peer, client, job);
}

String corruptStep(String raw, String field, String value) {
  final parsed = DirectHostRecord.parse(utf8.encode(raw), expectedKind: 'step');
  return 'SDSSH1\nstep\n' +
      parsed.fields.entries
          .map((entry) => entry.key == field ? value : entry.value)
          .join('\n') +
      '\n';
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
        final (s, peer, client, job) = await directUncertain();
        var injected = false;
        peer.alterReply = (command, rows) {
          if (fault == 'status_foreign' && command.kind == 'status') {
            injected = true;
            return {
              ...rows,
              'admission': rows['admission']!.replaceFirst(
                s.store.snapshot.automation.jobs[job]!.hostAttemptId,
                repository.id(3609),
              ),
            };
          }
          if (command.kind != 'step-status') return rows;
          injected = true;
          final changed = {...rows};
          switch (fault) {
            case 'children':
              changed['cgroup'] = 'populated 1\nfrozen 0';
            case 'floor':
              changed['result'] = corruptStep(
                rows['result']!,
                'issuedUptimeMs',
                '0',
              );
            case 'foreign':
              changed['result'] = corruptStep(
                rows['result']!,
                'attemptId',
                repository.id(3609),
              );
            case 'state':
              changed['result'] = corruptStep(
                rows['result']!,
                'state',
                'PRIVATE_INVALID_STATE',
              );
            case 'negative':
              changed['result'] = corruptStep(
                rows['result']!,
                'issuedUptimeMs',
                '-1',
              );
            case 'sequence_type':
              changed['result'] = corruptStep(
                rows['result']!,
                'issuedUptimeMs',
                'not-a-number',
              );
            case 'boolean':
              changed['cgroup'] = 'populated true\nfrozen 0';
            case 'postchecks':
              final intent = DirectHostRecord.parse(
                utf8.encode(rows['intent']!),
                expectedKind: 'step',
              );
              changed['start'] = ascii.decode(
                DirectHostRecord.create('step', {
                  ...intent.fields,
                  'state': 'started',
                }).encode(),
              );
              changed['result'] = corruptStep(
                rows['result']!,
                'state',
                'succeeded',
              );
              changed['checks'] = '[]';
          }
          return changed;
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
        expect(peer.launches, 1);
        expect(peer.effects, 0);
        expect(
          peer.requests.where((command) => command.kind == 'reserve'),
          hasLength(1),
        );
        expect(s.store.snapshot.automation.desired, isEmpty);
        expect(s.store.isReady, isTrue);
        peer.alterReply = null;
        peer.stopBeforeStart = false;
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
            peer.requests.where((command) => command.kind == 'reserve'),
            hasLength(2),
          );
          expect(peer.launches, 2);
          expect(peer.effects, 1);
        }
      },
    );
  }

  test('actual cancel of unknown preserves graph and occupancy until explicit stopped reconciliation', () async {
    final (s, peer, client, job) = await directUncertain();
    peer.alterReply = (command, rows) => command.kind == 'step-status'
        ? {...rows, 'cgroup': 'populated 1\nfrozen 0'}
        : rows;
    success(
      await s.tool(client, 'jobs_cancel', {
        'requestId': repository.id(3603),
        'jobId': job,
      }),
    );
    final watch = Stopwatch()..start();
    while (peer.requests.where((command) => command.kind == 'stop').isEmpty &&
        watch.elapsed < const Duration(seconds: 5)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(
      peer.requests.where((command) => command.kind == 'stop'),
      hasLength(1),
    );
    expect(await settled(s, client, job), 'unknown');
    expect(s.store.snapshot.automation.jobs[job]!.cancelRequested, isTrue);
    expect(s.store.isReady, isTrue);
    expect(
      peer.requests.where((command) => command.kind == 'terminal'),
      isEmpty,
    );
    peer.alterReply = null;
    success(
      await s.tool(client, 'jobs_reconcile', {
        'requestId': repository.id(3604),
        'jobId': job,
      }),
    );
    expect(await settled(s, client, job), 'cancelled');
    expect(peer.launches, 1);
    expect(peer.effects, 0);
    expect(
      peer.requests.where((command) => command.kind == 'reserve'),
      hasLength(1),
    );
  });

  test('actual malformed reserve ACK leaves accepted attempt unknown before any step permit', () async {
    final (s, peer, client, profile) = await directReady();
    final plan = await positive.plan(s, client, profile, 3600);
    await positive.approve(s, client, plan, 3601);
    peer.alterReply = (command, rows) =>
        command.kind == 'reserve' ? {...rows, 'disposition': '-1'} : rows;
    final admitted = success(
      await s.tool(client, 'apply', {
        'requestId': repository.id(3602),
        'planId': plan['planId'],
      }),
    );
    expect(await settled(s, client, admitted['jobId'] as String), 'unknown');
    expect(peer.records['admission'], isNotNull);
    expect(
      peer.requests.where((command) => command.kind == 'reserve'),
      hasLength(1),
    );
    noDirectEffect(peer);
    expect(s.store.isReady, isTrue);
  });
}
