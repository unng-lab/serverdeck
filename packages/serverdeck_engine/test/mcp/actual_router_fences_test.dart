import 'dart:async';

import 'package:serverdeck_engine/mcp/grants.dart';
import 'package:test/test.dart';

import '../storage/actual_state_store_test.dart' as repository;
import '../support/actual_mcp_setup.dart';
import '../support/actual_direct_setup.dart';
import '../support/schema3_fixture.dart' as fixture;
import 'actual_router_executor_test.dart' as positive;

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

void main() {
  for (final fault in ['digest', 'effects', 'target']) {
    test(
      'actual plan retains blocked diagnostic for untrusted preflight $fault',
      () async {
        final (s, peer, client, profile) = await directReady();
        if (fault == 'target') {
          var probes = 0;
          peer.reads.beforeOutput = (command) async {
            if (command.kind == 'inspect' && ++probes == 2)
              peer.reads.inspectRows['boot'] = repository.id(3309);
          };
        } else {
          peer.reads.alterRows = (command, rows) {
            if (command.kind != 'observation') return rows;
            if (fault == 'digest')
              return {...rows, 'digest': '${'0' * 64}  /etc/motd'};
            // A remote peer cannot introduce a managed effect descriptor into
            // the closed raw observation frame consumed by the local compiler.
            return {...rows, 'effects': 'PRIVATE_FORGED_EFFECT'};
          };
        }
        final saved = success(
          await s.tool(client, 'plan_create', planArgs(profile)),
        );
        final plan = s.store.snapshot.automation.plans[saved['planId']]!;
        expect(plan.status, 'blocked');
        expect(
          (plan.toJson()['reasons'] as List).single,
          containsPair(
            'code',
            fault == 'target' ? 'PLAN_STALE' : 'UNSUPPORTED',
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
        expect(peer.records, isEmpty);
        noDirectEffect(peer);
        expect(s.store.isReady, isTrue);
      },
    );
  }

  for (final fault in ['proof', 'revoke']) {
    test(
      'actual $fault during preflight suppresses plan persistence and ACK',
      () async {
        final (s, peer, client, profile) = await directReady();
        var injected = false;
        peer.reads.beforeOutput = (command) async {
          if (injected || command.kind != 'packages') return;
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
        expect(peer.records, isEmpty);
        noDirectEffect(peer);
        expect(s.store.isReady, isTrue);
        expect(s.successful, isNot(contains('plan_create')));
      },
    );
  }

  test('actual committed plan survives lost publication proof and explicit replay without preflight', () async {
    final (s, peer, client, profile) = await directReady();
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
    noDirectEffect(peer);
  });

  for (final policy in ['foreign_grant', 'removed_target']) {
    test(
      'actual object tools deny $policy before metadata or root effects',
      () async {
        final (s, peer, client, profile) = await directReady();
        peer.dropReserveAck = true;
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
        final requests = peer.requests.length, launches = peer.launches;
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
        expect(peer.launches, launches);
        expect(peer.effects, 0);
      },
    );
  }

  for (final fault in ['proof', 'revoke', 'admission', 'reserve_ack']) {
    test(
      'actual $fault after reserve preserves unknown without step permit or another reserve',
      () async {
        final (s, peer, client, profile) = await directReady();
        final plan = await positive.plan(s, client, profile, 3301);
        await positive.approve(s, client, plan, 3302);
        final reached = Completer<void>(),
            release = Completer<void>(),
            injectedDone = Completer<void>();
        addTearDown(() {
          if (!release.isCompleted) release.complete();
        });
        var injected = false;
        String? admittedJobId;
        peer.beforeReply = (command, session) async {
          if (injected || command.kind != 'reserve') return;
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
            case 'admission':
              peer.alterReply = (command, rows) => command.kind == 'reserve'
                  ? {
                      ...rows,
                      'admission': rows['admission']!.replaceFirst(
                        admittedJobId!,
                        repository.id(3309),
                      ),
                    }
                  : rows;
            case 'reserve_ack':
              peer.dropReserveAck = true;
          }
          injectedDone.complete();
        };
        final args = <String, Object?>{
          'requestId': repository.id(3304),
          'planId': plan['planId'],
        };
        final admitted = success(await s.tool(client, 'apply', args));
        admittedJobId = admitted['jobId'] as String;
        await reached.future.timeout(const Duration(seconds: 5));
        expect(peer.records['admission'], isNotNull);
        noDirectEffect(peer);
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
          peer.requests.where((command) => command.kind == 'reserve'),
          hasLength(1),
        );
        noDirectEffect(peer);
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
          peer.requests.where((command) => command.kind == 'reserve'),
          hasLength(1),
        );
        expect(
          peer.requests.where((command) => command.kind == 'stop'),
          isEmpty,
        );
        expect(
          peer.requests.where((command) => command.kind == 'terminal'),
          isEmpty,
        );
        expect(s.store.isReady, isTrue);
      },
    );
  }
}
