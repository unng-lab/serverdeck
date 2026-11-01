import 'dart:convert';
import 'dart:async';

import 'package:serverdeck_engine/remote/direct_ssh_records.dart';
import 'package:serverdeck_engine/storage/state_store.dart';
import 'package:test/test.dart';
import 'package:serverdeck_engine/mcp/grants.dart';

import '../storage/actual_state_store_test.dart' as repository;
import '../support/actual_mcp_setup.dart';
import '../support/direct_host_byte_peer.dart';
import '../support/schema3_fixture.dart' as fixture;
import 'actual_direct_plan_test.dart' show profile, arguments;

void main() {
  for (final scenario in [(false, false), (true, false), (false, true)]) {
    final lostAck = scenario.$1, newerReconcile = scenario.$2;
    test(
      'actual cancel after reserve before permit releases without effect, lost ACK=$lostAck, newer reconcile=$newerReconcile',
      () async {
        final peer = DirectHostBytePeer();
        final reserved = Completer<void>(), resume = Completer<void>();
        final terminalAck = Completer<void>(),
            releaseTerminal = Completer<void>();
        final reconcileRead = Completer<void>(),
            releaseRead = Completer<void>();
        var statusCount = 0;
        addTearDown(() {
          for (final wait in [resume, releaseTerminal, releaseRead]) {
            if (!wait.isCompleted) wait.complete();
          }
        });
        peer.beforeReply = (command, _) async {
          if (command.kind == 'reserve') {
            reserved.complete();
            await resume.future;
          }
          if (newerReconcile &&
              command.kind == 'terminal' &&
              !terminalAck.isCompleted) {
            terminalAck.complete();
            await releaseTerminal.future;
          }
          if (newerReconcile &&
              command.kind == 'status' &&
              ++statusCount == 2) {
            reconcileRead.complete();
            await releaseRead.future;
          }
        };
        final s = await Setup.create(direct: peer.attach);
        final id = await profile(s), client = await s.client(await s.grant());
        success(
          await s.tool(client, 'server_connect', {'serverId': fixture.profile}),
        );
        final plan = success(
          await s.tool(client, 'plan_create', arguments(id, 3950)),
        );
        final asked = success(
          await s.tool(client, 'approval_request', {
            'requestId': repository.id(3951),
            'planId': plan['planId'],
          }),
        );
        await s.ownerCall('approvals.decide', {
          'requestId': repository.id(3952),
          'approvalId': asked['approvalId'],
          'planDigest': asked['planDigest'],
          'decision': 'approved',
        });
        final admitted = success(
          await s.tool(client, 'apply', {
            'requestId': repository.id(3953),
            'planId': plan['planId'],
          }),
        );
        final jobId = admitted['jobId'] as String;
        await reserved.future.timeout(const Duration(seconds: 3));
        expect(s.store.snapshot.automation.jobs[jobId]!.sshDispatch, isNull);
        peer.dropTerminalAck = lostAck;
        success(
          await s.tool(client, 'jobs_cancel', {
            'requestId': repository.id(3954),
            'jobId': jobId,
          }),
        );
        expect(
          s.store.snapshot.automation.jobs[jobId]!.cancelRequested,
          isTrue,
        );
        final cancelled = s.store.snapshot.automation.jobs[jobId]!;
        final retained =
            s.store.snapshot.automation.plans[cancelled.immutablePlanId]!;
        await expectLater(
          s.store.authorizeDirectSshStep(
            jobId: jobId,
            expectedSequence: cancelled.nextSequence,
            stepId:
                ((retained.toJson()['effects'] as List).first as Map)['id']
                    as String,
            bootIdHash: retained.preflight!.toJson()['bootIdHash'] as String,
            observedUptimeMs: 1000000,
            elapsedSinceProbe: () => Duration.zero,
            originGrantId: client.grantId,
            expectedGrantRevision: 1,
            clock: utcNow,
            revalidate: () {},
          ),
          repository.failure('CANCELLED'),
        );
        resume.complete();
        if (newerReconcile) {
          await terminalAck.future.timeout(const Duration(seconds: 3));
          success(
            await s.tool(client, 'jobs_reconcile', {
              'requestId': repository.id(3957),
              'jobId': jobId,
            }),
          );
          final newerPhase = s.store.snapshot.automation.jobs[jobId]!;
          expect(newerPhase.state, 'reconciling');
          releaseTerminal.complete();
          await reconcileRead.future.timeout(const Duration(seconds: 3));
          expect(
            s.store.snapshot.automation.jobs[jobId]!.toJson(),
            newerPhase.toJson(),
          );
          releaseRead.complete();
        }
        for (var i = 0; i < 600; i++) {
          await s.tool(client, 'jobs_get', {'jobId': jobId});
          if (s.store.snapshot.automation.jobs[jobId]!.state ==
                  (lostAck ? 'unknown' : 'cancelled') &&
              peer.records['terminal'] != null)
            break;
          await Future<void>.delayed(const Duration(milliseconds: 3));
        }
        if (lostAck) {
          expect(s.store.snapshot.automation.jobs[jobId]!.state, 'unknown');
          await s.store.mutateOwnerGrant(
            OwnerGrantCommand.parse('grant.replace', {
              'requestId': repository.id(3955),
              'grantId': client.grantId,
              'expectedRevision': 1,
              'label': 'read recovery only',
              'scopes': ['read'],
              'serverIds': [fixture.profile],
              'lifetimeSeconds': 300,
            }),
            clock: utcNow,
          );
          final reader = await s.client(client.grantId);
          success(
            await s.tool(reader, 'server_connect', {
              'serverId': fixture.profile,
            }),
          );
          success(
            await s.tool(reader, 'jobs_reconcile', {
              'requestId': repository.id(3956),
              'jobId': jobId,
            }),
          );
          for (var i = 0; i < 600; i++) {
            await s.tool(reader, 'jobs_get', {'jobId': jobId});
            if (s.store.snapshot.automation.jobs[jobId]!.state == 'cancelled')
              break;
            await Future<void>.delayed(const Duration(milliseconds: 3));
          }
        }
        final job = s.store.snapshot.automation.jobs[jobId]!;
        expect(
          job.state,
          'cancelled',
          reason:
              '${peer.records}\n${s.store.snapshot.automation.events.values.map((e) => e.toJson()).toList()}',
        );
        expect(job.sshDispatch, isNull);
        expect(job.outcome!.effects, 'none');
        expect(job.outcome!.checks, isEmpty);
        expect(peer.records.containsKey('owner'), isFalse);
        expect(peer.records['stop'], isNotNull);
        expect((peer.launches, peer.effects), (0, 0));
        expect(s.store.snapshot.automation.desired, isEmpty);
      },
    );
  }
  for (final loss in [
    'launch',
    'terminal',
    'launch-read-scope',
    'terminal-new-owner-reboot',
  ]) {
    test(
      'lost $loss ACK reconciles original direct attempt without another effect',
      () async {
        final peer = DirectHostBytePeer();
        peer.dropLaunchAck = loss.startsWith('launch');
        peer.dropTerminalAck = loss.startsWith('terminal');
        final s = await Setup.create(direct: peer.attach);
        final id = await profile(s), client = await s.client(await s.grant());
        success(
          await s.tool(client, 'server_connect', {'serverId': fixture.profile}),
        );
        final plan = success(
          await s.tool(client, 'plan_create', arguments(id, 3930)),
        );
        final approval = success(
          await s.tool(client, 'approval_request', {
            'requestId': repository.id(3931),
            'planId': plan['planId'],
          }),
        );
        await s.ownerCall('approvals.decide', {
          'requestId': repository.id(3932),
          'approvalId': approval['approvalId'],
          'planDigest': approval['planDigest'],
          'decision': 'approved',
        });
        final admitted = success(
          await s.tool(client, 'apply', {
            'requestId': repository.id(3933),
            'planId': plan['planId'],
          }),
        );
        final jobId = admitted['jobId'] as String;
        for (var i = 0; i < 500; i++) {
          success(await s.tool(client, 'jobs_get', {'jobId': jobId}));
          if (s.store.snapshot.automation.jobs[jobId]!.state == 'unknown')
            break;
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        expect(s.store.snapshot.automation.jobs[jobId]!.state, 'unknown');
        expect(peer.effects, 1);
        String? foreignOwner;
        if (loss == 'terminal-new-owner-reboot') {
          final admission = DirectHostRecord.parse(
            utf8.encode(peer.records['admission']!),
            expectedKind: 'admission',
          );
          foreignOwner = ascii.decode(
            DirectHostRecord.create('owner', {
              ...admission.fields,
              'workspaceId': repository.id(3940),
              'jobId': repository.id(3941),
              'attemptId': repository.id(3942),
              'planDigest': 'a' * 64,
            }).encode(),
          );
          peer.records['owner'] = foreignOwner;
          peer.reads.files['system.motd'] = 'another workspace changed this\n';
          peer.reads.inspectRows['boot'] = repository.id(3943);
        }
        var controller = client;
        if (loss == 'launch-read-scope') {
          await s.store.mutateOwnerGrant(
            OwnerGrantCommand.parse('grant.replace', {
              'requestId': repository.id(3935),
              'grantId': client.grantId,
              'expectedRevision': 1,
              'label': 'read recovery only',
              'scopes': ['read'],
              'serverIds': [fixture.profile],
              'lifetimeSeconds': 300,
            }),
            clock: utcNow,
          );
          controller = await s.client(client.grantId);
          success(
            await s.tool(controller, 'server_connect', {
              'serverId': fixture.profile,
            }),
          );
        }
        success(
          await s.tool(controller, 'jobs_reconcile', {
            'requestId': repository.id(3934),
            'jobId': jobId,
          }),
        );
        for (var i = 0; i < 500; i++) {
          success(await s.tool(controller, 'jobs_get', {'jobId': jobId}));
          if (s.store.snapshot.automation.jobs[jobId]!.state == 'succeeded')
            break;
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        expect(s.store.snapshot.automation.jobs[jobId]!.state, 'succeeded');
        expect(peer.effects, 1);
        expect(peer.launches, 1);
        if (foreignOwner == null) {
          expect(peer.records.containsKey('owner'), isFalse);
        } else {
          expect(peer.records['owner'], foreignOwner);
          expect(
            peer.reads.files['system.motd'],
            'another workspace changed this\n',
          );
        }
      },
    );
  }
  test('actual direct plan approval apply reaches factual result and released host owner', () async {
    final peer = DirectHostBytePeer();
    final s = await Setup.create(direct: peer.attach);
    final id = await profile(s), client = await s.client(await s.grant());
    success(
      await s.tool(client, 'server_connect', {'serverId': fixture.profile}),
    );
    final plan = success(
      await s.tool(client, 'plan_create', arguments(id, 3920)),
    );
    final approval = success(
      await s.tool(client, 'approval_request', {
        'requestId': repository.id(3921),
        'planId': plan['planId'],
      }),
    );
    await s.ownerCall('approvals.decide', {
      'requestId': repository.id(3922),
      'approvalId': approval['approvalId'],
      'planDigest': approval['planDigest'],
      'decision': 'approved',
    });
    final admitted = success(
      await s.tool(client, 'apply', {
        'requestId': repository.id(3923),
        'planId': plan['planId'],
      }),
    );
    final jobId = admitted['jobId'] as String;
    for (var i = 0; i < 500; i++) {
      final view = success(await s.tool(client, 'jobs_get', {'jobId': jobId}));
      if ((view['job'] as Map)['state'] == 'succeeded') break;
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    final job = s.store.snapshot.automation.jobs[jobId]!;
    expect(job.state, 'succeeded');
    expect(job.sshDispatch!.state, 'completed');
    expect(job.outcome!.checks.single.result, 'passed');
    expect(peer.effects, 1);
    expect(peer.reads.files['system.motd'], 'direct plan\n');
    expect(peer.records.containsKey('owner'), isFalse);
    expect(s.store.snapshot.automation.desired.values.single.lastJobId, jobId);
    expect(
      s.io.attempts.single.client.commands.every(
        (command) => command.operation != null,
      ),
      isTrue,
    );
  });
}
