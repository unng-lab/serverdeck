import 'package:serverdeck_engine/platform/ports.dart';

import 'dart:async';

import 'package:serverdeck_engine/mcp/grants.dart';
import 'package:test/test.dart';

import '../automation/portable_program_test.dart' show motdBody;
import '../storage/actual_state_store_test.dart' as repository;
import '../support/actual_mcp_setup.dart';
import '../support/executor_byte_peer.dart';
import '../support/schema3_fixture.dart' as fixture;
import 'actual_router_executor_test.dart' as positive;

Future<(Setup, ExecutorBytePeer, Client, String)> ready({
  EngineClock? readClock,
}) async {
  final (s, peer) = await positive.enrolled(readClock: readClock);
  final client = await s.client(await s.grant());
  success(
    await s.tool(client, 'server_connect', {'serverId': fixture.profile}),
  );
  final profile =
      success(
            await s.tool(client, 'profiles_create', {
              'requestId': repository.id(3300),
              'name': 'fenced unit profile',
              'body': motdBody(),
            }),
          )['profileId']
          as String;
  return (s, peer, client, profile);
}

Map<String, Object?> planArgs(String profile) => {
  'requestId': repository.id(3301),
  'serverId': fixture.profile,
  'profileId': profile,
  'revision': 1,
  'parameters': {'message': 'executor unit'},
};

void toolError(Map<String, Object?> result, String code) {
  expect((result['result'] as Map)['isError'], isTrue);
  final structured = (result['result'] as Map)['structuredContent'] as Map;
  expect(structured['ok'], isFalse);
  expect((structured['error'] as Map)['code'], code);
}

void noRootEffect(ExecutorBytePeer peer) {
  expect(peer.permits, 0);
  expect(peer.effects, 0);
  expect(peer.motd, 'unit baseline\n');
  expect(peer.requests.where((r) => r['method'] == 'authorize_step'), isEmpty);
}

void main() {
  for (final fault in ['digest', 'effects', 'target']) {
    test(
      'actual plan retains blocked diagnostic for untrusted preflight $fault',
      () async {
        final (s, peer, client, profile) = await ready();
        peer.beforeReply = (request, response, _) async {
          if (request['method'] != 'preflight_get') return;
          final facts = response['result'] as Map;
          switch (fault) {
            case 'digest':
              facts['digest'] = '0' * 64;
            case 'effects':
              ((facts['effects'] as List).single as Map)['values'] = {
                'text': 'PRIVATE_FORGED_EFFECT',
              };
            case 'target':
              ((facts['observations'] as List).single as Map)['serverId'] =
                  repository.id(3309);
          }
        };
        final saved = success(
          await s.tool(client, 'plan_create', planArgs(profile)),
        );
        final plan = s.store.snapshot.automation.plans[saved['planId']]!;
        expect(plan.status, 'blocked');
        expect(
          (plan.toJson()['reasons'] as List).single,
          containsPair(
            'code',
            fault == 'target' ? 'PLAN_STALE' : 'RUNTIME_INCOMPATIBLE',
          ),
        );
        expect(plan.toJson()['preflight'], isNull);
        expect(plan.toJson()['effects'], isEmpty);
        expect(
          plan.toJson().toString(),
          isNot(contains('PRIVATE_FORGED_EFFECT')),
        );
        final refused = await s.tool(client, 'approval_request', {
          'requestId': repository.id(3302),
          'planId': plan.id,
        });
        toolError(refused, 'PLAN_STALE');
        expect(s.store.snapshot.automation.approvals, isEmpty);
        expect(s.store.snapshot.automation.jobs, isEmpty);
        expect(peer.attempts, isEmpty);
        noRootEffect(peer);
        expect(peer.errors, isEmpty);
        expect(s.store.isReady, isTrue);
      },
    );
  }

  for (final fault in ['proof', 'revoke']) {
    test(
      'actual $fault during preflight suppresses plan persistence and ACK',
      () async {
        final (s, peer, client, profile) = await ready();
        var injected = false;
        peer.beforeReply = (request, response, _) async {
          if (request['method'] != 'preflight_get') return;
          injected = true;
          if (fault == 'proof') {
            client.peer.proofError = StateError('PRIVATE_PRE_COMMIT');
          } else {
            await s.store.mutateOwnerGrant(
              OwnerGrantCommand.parse('grant.revoke', {
                'requestId': repository.id(3303),
                'grantId': client.grantId,
                'expectedRevision': 1,
              }),
              clock: utcNow,
            );
          }
        };
        await expectLater(
          s.tool(client, 'plan_create', planArgs(profile)),
          repository.failure('UNAUTHORIZED'),
        );
        expect(injected, isTrue);
        expect(s.store.snapshot.automation.plans, isEmpty);
        expect(
          s.store.snapshot.automation.receipts.containsKey(repository.id(3301)),
          isFalse,
        );
        expect(s.store.snapshot.automation.jobs, isEmpty);
        expect(peer.attempts, isEmpty);
        noRootEffect(peer);
        expect(peer.errors, isEmpty);
        expect(s.store.isReady, isTrue);
        expect(s.successful, isNot(contains('plan_create')));
      },
    );
  }

  test('actual committed plan survives lost publication proof and explicit replay without preflight', () async {
    final (s, peer, client, profile) = await ready();
    final before = s.repository.provider.lastOpened!.commits;
    s.repository.provider.afterCommit = () =>
        client.peer.proofError = StateError('PRIVATE_PLAN_ACK');
    await expectLater(
      s.tool(client, 'plan_create', planArgs(profile)),
      repository.failure('UNAUTHORIZED'),
    );
    s.repository.provider.afterCommit = null;
    final receipt = s.store.snapshot.automation.receipts[repository.id(3301)]!;
    expect(s.store.snapshot.automation.plans, hasLength(1));
    expect(s.repository.provider.lastOpened!.commits, before + 1);
    expect(s.successful, isNot(contains('plan_create')));
    final requestCount = peer.requests.length;
    final fresh = await s.client(client.grantId);
    expect(
      success(await s.tool(fresh, 'plan_create', planArgs(profile))),
      receipt.result,
    );
    expect(peer.requests.length, requestCount);
    expect(s.repository.provider.lastOpened!.commits, before + 1);
    noRootEffect(peer);
    expect(peer.errors, isEmpty);
  });

  for (final policy in ['foreign_grant', 'removed_target']) {
    test(
      'actual object tools deny $policy before metadata or root effects',
      () async {
        final (s, peer, client, profile) = await ready();
        peer.unknownAfterAuthorize = true;
        final plan = await positive.plan(s, client, profile, 3301);
        await positive.approve(s, client, plan, 3302);
        final job = success(
          await s.tool(client, 'apply', {
            'requestId': repository.id(3304),
            'planId': plan['planId'],
          }),
        );
        await positive.waitJob(s, client, job['jobId'] as String, 'unknown');
        late final Client denied;
        if (policy == 'foreign_grant') {
          denied = await s.client(await s.grant());
        } else {
          await s.ownerCall('profiles.create', {
            'profileId': repository.id(3311),
            'name': 'other allowed host',
            'address': 'other-unit.invalid',
            'port': 22,
            'sshUser': 'unit',
            'tags': <String>[],
            'credential': {
              'action': 'replace',
              'kind': 'password',
              'password': 'unit-ephemeral-only',
            },
          });
          expect(
            s.store.state.profiles.containsKey(repository.id(3311)),
            isTrue,
          );
          await s.store.mutateOwnerGrant(
            OwnerGrantCommand.parse('grant.replace', {
              'requestId': repository.id(3305),
              'grantId': client.grantId,
              'expectedRevision': 1,
              'label': 'target removed',
              'scopes': ['read', 'logs', 'author', 'plan', 'apply'],
              'serverIds': [repository.id(3311)],
              'lifetimeSeconds': 300,
            }),
            clock: utcNow,
          );
          denied = await s.client(client.grantId);
        }
        final before = repository.rawRows(s.store);
        final commits = s.repository.provider.lastOpened!.commits;
        final requests = peer.requests.length, permits = peer.permits;
        final commands = <String, Map<String, Object?>>{
          'plans_get': {'planId': plan['planId']},
          'approval_request': {
            'requestId': repository.id(3306),
            'planId': plan['planId'],
          },
          'apply': {'requestId': repository.id(3307), 'planId': plan['planId']},
          'jobs_get': {'jobId': job['jobId']},
          'jobs_events': {'jobId': job['jobId']},
          'jobs_cancel': {
            'requestId': repository.id(3308),
            'jobId': job['jobId'],
          },
          'jobs_reconcile': {
            'requestId': repository.id(3310),
            'jobId': job['jobId'],
          },
        };
        for (final entry in commands.entries) {
          toolError(await s.tool(denied, entry.key, entry.value), 'FORBIDDEN');
        }
        expect(
          success(await s.tool(denied, 'jobs_list', {}))['items'],
          isEmpty,
        );
        final visible = success(await s.tool(denied, 'servers_list', {}));
        expect((visible['items'] as List).map((row) => (row as Map)['id']), [
          policy == 'foreign_grant' ? fixture.profile : repository.id(3311),
        ]);

        expect(repository.rawRows(s.store), before);
        expect(s.repository.provider.lastOpened!.commits, commits);
        expect(peer.requests.length, requests);
        expect(peer.permits, permits);
        expect(peer.effects, 0);
        expect(peer.errors, isEmpty);
      },
    );
  }

  for (final fault in ['proof', 'revoke', 'status', 'submit_ack']) {
    test(
      'actual $fault after submit preserves unknown without step permit or resubmit',
      () async {
        final (s, peer, client, profile) = await ready();
        final plan = await positive.plan(s, client, profile, 3301);
        await positive.approve(s, client, plan, 3302);
        final reached = Completer<void>(),
            release = Completer<void>(),
            injectedDone = Completer<void>();
        addTearDown(() {
          if (!release.isCompleted) release.complete();
        });
        var injected = false;
        peer.beforeReply = (request, response, session) async {
          if (injected ||
              request['method'] !=
                  (fault == 'submit_ack' ? 'submit' : 'status'))
            return;
          injected = true;
          reached.complete();
          await release.future;
          switch (fault) {
            case 'proof':
              client.peer.proofError = StateError('PRIVATE_BEFORE_PERMIT');
            case 'revoke':
              await s.store.mutateOwnerGrant(
                OwnerGrantCommand.parse('grant.revoke', {
                  'requestId': repository.id(3312),
                  'grantId': client.grantId,
                  'expectedRevision': 1,
                }),
                clock: utcNow,
              );
            case 'status':
              response['attemptId'] = repository.id(3309);
            case 'submit_ack':
              session.exitCode = 1;
              await session.finish();
          }
          injectedDone.complete();
        };
        final args = <String, Object?>{
          'requestId': repository.id(3304),
          'planId': plan['planId'],
        };
        final admitted = success(await s.tool(client, 'apply', args));
        await reached.future.timeout(const Duration(seconds: 5));
        expect(peer.attempts, hasLength(1));
        noRootEffect(peer);
        release.complete();
        await injectedDone.future.timeout(const Duration(seconds: 5));
        final observer = fault == 'proof'
            ? await s.client(client.grantId)
            : client;
        if (fault == 'revoke') {
          final watch = Stopwatch()..start();
          var state = '';
          while (watch.elapsed < const Duration(seconds: 5)) {
            final viewed = success(
              await s.ownerCall('jobs.get', {'jobId': admitted['jobId']}),
            );
            state = (viewed['job'] as Map)['state'] as String;
            if (state == 'unknown') break;
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          expect(state, 'unknown');
        } else {
          await positive.waitJob(
            s,
            observer,
            admitted['jobId'] as String,
            'unknown',
          );
        }
        expect(s.store.snapshot.automation.desired, isEmpty);
        expect(
          peer.requests.where((r) => r['method'] == 'submit'),
          hasLength(1),
        );
        noRootEffect(peer);
        if (fault == 'revoke') {
          await expectLater(
            s.tool(client, 'apply', args),
            repository.failure('UNAUTHORIZED'),
          );
          await expectLater(
            s.client(client.grantId),
            repository.failure('UNAUTHORIZED'),
          );
        } else {
          expect(success(await s.tool(observer, 'apply', args)), admitted);
        }
        expect(
          peer.requests.where((r) => r['method'] == 'submit'),
          hasLength(1),
        );
        expect(peer.cancellations, 0);
        expect(peer.reconciliations, 0);
        expect(peer.errors, isEmpty);
        expect(s.store.isReady, isTrue);
      },
    );
  }
}
