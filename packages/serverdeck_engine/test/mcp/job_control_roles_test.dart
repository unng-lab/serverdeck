import 'dart:convert';
import 'dart:async';

import 'package:serverdeck_engine/mcp/grants.dart';
import 'package:test/test.dart';

import '../storage/actual_state_store_test.dart' as repository;
import '../support/actual_mcp_setup.dart';
import '../support/direct_host_byte_peer.dart';
import '../support/actual_direct_setup.dart';
import '../support/memory_workspace_provider.dart';
import '../support/schema3_fixture.dart' as fixture;
import '../remote/ssh_io_policy_test.dart' as bytes;
import 'actual_router_executor_test.dart' as positive;
import 'actual_router_fences_test.dart' as fences;

Future<void> until(Setup s, bool Function() ready) async {
  bool observed() {
    try {
      return ready();
    } on StateError catch (error) {
      if (error.message == 'STORAGE_BLOCKED' &&
          s.store.hasPendingMcpAuthorityPublication)
        return false;
      rethrow;
    }
  }

  final watch = Stopwatch()..start();
  while (!observed() && watch.elapsed < const Duration(seconds: 3)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(
    observed(),
    isTrue,
    reason: 'actual RAM work must reach the asserted boundary',
  );
}

Future<Map<String, Object?>> ownerControl(
  Setup s,
  String method,
  String job,
  int id,
) async {
  var reply = await s.ownerCall(method, {
    'requestId': repository.id(id),
    'jobId': job,
  });
  final operation = reply['operationId'];
  final watch = Stopwatch()..start();
  while (reply['state'] == 'running' &&
      watch.elapsed < const Duration(seconds: 3)) {
    await Future<void>.delayed(Duration.zero);
    reply = await s.ownerCall('automation.status', {'operationId': operation});
  }
  expect(reply['state'], 'done');
  expect(reply['kind'], method);
  return success(reply);
}

final class Held {
  Held(this.s, this.peer, this.client, this.profile, this.job, this.session);
  final Setup s;
  final DirectHostBytePeer peer;
  final Client client;
  final String profile, job;
  final bytes.Session session;
  static Future<Held> create() async {
    final h = await DirectHeld.create();
    return Held(h.s, h.peer, h.client, h.profile, h.job, h.session);
  }

  Future<Client> readOnly() async {
    await s.store.mutateOwnerGrant(
      OwnerGrantCommand.parse('grant.replace', {
        'requestId': repository.id(3606),
        'grantId': client.grantId,
        'expectedRevision': 1,
        'label': 'read-only control unit',
        'scopes': ['read'],
        'serverIds': [fixture.profile],
        'lifetimeSeconds': 300,
      }),
      clock: utcNow,
    );
    final reader = await s.client(client.grantId);
    success(
      await s.tool(reader, 'server_connect', {'serverId': fixture.profile}),
    );
    return reader;
  }

  Future<void> reconcile(Client actor, {int id = 3603}) async {
    success(
      await s.tool(actor, 'jobs_reconcile', {
        'requestId': repository.id(id),
        'jobId': job,
      }),
    );
    expect(s.store.snapshot.automation.jobs[job]!.state, 'reconciling');
  }

  void noNewEffect() {
    expect(
      peer.requests.where((command) => command.kind == 'reserve'),
      hasLength(1),
    );
    expect(peer.launches, 1);
    expect(peer.effects, 0);
  }
}

void main() {
  for (final fairness in [false, true]) {
    test(
      'actual separate read actor and owner stop with one-cancel fairness=$fairness',
      () async {
        final h = await Held.create(), s = h.s, peer = h.peer;
        final original = s.store.snapshot.automation.jobs[h.job]!;
        final reader = await h.readOnly();
        await expectLater(
          s.tool(reader, 'jobs_cancel', {
            'requestId': repository.id(3607),
            'jobId': h.job,
          }),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'scope code',
              'FORBIDDEN',
            ),
          ),
        );
        await h.reconcile(reader);
        await ownerControl(s, 'jobs.cancel', h.job, 3604);
        expect(
          peer.requests.where((command) => command.kind == 'stop').length,
          0,
        );
        expect(
          peer.requests.where((command) => command.kind == 'status').length,
          0,
        );
        final entered = Completer<void>(), release = Completer<void>();
        addTearDown(() {
          if (!release.isCompleted) release.complete();
        });
        bytes.Session? lastStop;
        var stops = 0;
        peer.beforeReply = (command, session) async {
          if (command.kind == 'stop') {
            lastStop = session;
            stops++;
            if (fairness && stops == 1) {
              entered.complete();
              await release.future;
            }
          }
        };
        peer.alterReply = (command, rows) {
          if (fairness && command.kind == 'stop' && stops == 1)
            return {...rows, 'disposition': 'PRIVATE_INVALID_ACK'};
          if (fairness && command.kind == 'step-status')
            return {...rows, 'cgroup': 'populated 1\nfrozen 0'};
          return rows;
        };
        await h.session.finish();
        if (fairness) {
          await entered.future.timeout(const Duration(seconds: 3));
          await ownerControl(s, 'jobs.cancel', h.job, 3605);
          release.complete();
        }
        await until(
          s,
          () => fairness
              ? peer.requests
                        .where((command) => command.kind == 'stop')
                        .length ==
                    2
              : s.store.snapshot.automation.jobs[h.job]!.state == 'cancelled',
        );
        await lastStop!.done.timeout(const Duration(seconds: 3));
        await until(
          s,
          () =>
              peer.requests
                  .where((command) => command.kind == 'status')
                  .length ==
              2,
        );
        final order = peer.requests
            .where((command) => const {'stop', 'status'}.contains(command.kind))
            .map((command) => command.kind)
            .toList();
        expect(
          order,
          fairness
              ? ['stop', 'status', 'stop', 'status']
              : ['stop', 'status', 'status'],
        );
        final retained = s.store.snapshot.automation.jobs[h.job]!;
        expect(retained.state, fairness ? 'unknown' : 'cancelled');
        expect(retained.hostAttemptId, original.hostAttemptId);
        expect(retained.grantId, original.grantId);
        expect(retained.authority.toJson(), original.authority.toJson());
        for (final id in [3603, 3604, if (fairness) 3605]) {
          expect(
            s.store.snapshot.automation.receipts.values.where(
              (r) => r.requestId == repository.id(id),
            ),
            hasLength(1),
          );
        }
        h.noNewEffect();
      },
    );
  }
  test('actual changed profile target retires pending control, fresh invocation uses current target', () async {
    final h = await Held.create(), s = h.s;
    await h.reconcile(h.client);
    final old =
        s.store.snapshot.foundation.foundation.profiles[fixture.profile]!;
    await s.ownerCall('profiles.update', {
      'profileId': old.id,
      'expectedRevision': old.revision,
      'name': '${old.name} current',
      'address': old.toJson()['address'],
      'port': old.toJson()['port'],
      'sshUser': old.toJson()['sshUser'],
      'tags': old.toJson()['tags'],
      'credential': {'action': 'keep'},
    });
    expect(
      s.store.snapshot.foundation.foundation.profiles[old.id]!.revision,
      isNot(old.revision),
    );
    await h.session.finish();
    await until(
      s,
      () => s.store.snapshot.automation.jobs[h.job]!.state == 'unknown',
    );
    expect(
      h.peer.requests.where((command) => command.kind == 'status').length,
      0,
    );
    final fresh = await s.client(h.client.grantId);
    success(
      await s.tool(fresh, 'server_connect', {'serverId': fixture.profile}),
    );
    success(
      await s.tool(fresh, 'jobs_reconcile', {
        'requestId': repository.id(3604),
        'jobId': h.job,
      }),
    );
    await positive.waitJob(s, fresh, h.job, 'cancelled');
    expect(
      h.peer.requests.where((command) => command.kind == 'status').length,
      1,
    );
    h.noNewEffect();
  });
  test('actual owner SSH trust revoke retires pending control; explicit key confirmation permits fresh recovery', () async {
    final h = await Held.create(), s = h.s;
    await h.reconcile(h.client);
    final before = s.store.state.profiles[fixture.profile]!;
    final revoking = s.ownerCall('servers.trust.revoke', {
      'profileId': fixture.profile,
      'expectedRevision': before.revision,
    });
    revoking.ignore();
    expect(
      h.peer.requests.where((command) => command.kind == 'status'),
      isEmpty,
    );
    await h.session.finish();
    await revoking;
    await until(
      s,
      () => s.store.snapshot.automation.jobs[h.job]!.state == 'unknown',
    );
    final trust = await s.ownerCall('servers.trust.get', {
      'profileId': fixture.profile,
    });
    expect((trust['trust'] as Map)['status'], 'revoked');
    expect(
      h.peer.requests.where((command) => command.kind == 'status'),
      isEmpty,
    );
    final blocked = await s.client(h.client.grantId);
    fences.toolError(
      await s.tool(blocked, 'server_connect', {'serverId': fixture.profile}),
      'TRUST_REQUIRED',
    );
    final current = s.store.state.profiles[fixture.profile]!;
    var probe = await s.ownerCall('servers.trust.probe', {
      'profileId': fixture.profile,
      'expectedRevision': current.revision,
    });
    while (probe['state'] == 'running') {
      await Future<void>.delayed(Duration.zero);
      probe = await s.ownerCall('servers.trust.probeStatus', {
        'operationId': probe['operationId'],
      });
    }
    expect(probe['state'], 'succeeded');
    final challenge = probe['challenge'] as Map;
    await s.ownerCall('servers.trust.confirm', {
      'profileId': fixture.profile,
      'expectedRevision': current.revision,
      'challengeId': challenge['challengeId'],
      'key': challenge['key'],
    });
    final fresh = await s.client(h.client.grantId);
    success(
      await s.tool(fresh, 'server_connect', {'serverId': fixture.profile}),
    );
    success(
      await s.tool(fresh, 'jobs_reconcile', {
        'requestId': repository.id(3604),
        'jobId': h.job,
      }),
    );
    await positive.waitJob(s, fresh, h.job, 'cancelled');
    expect(
      h.peer.requests.where((command) => command.kind == 'status'),
      hasLength(1),
    );
    expect(await s.store.readExecutorEnrollments(), isEmpty);
    h.noNewEffect();
  });
  for (final fault in ['children', 'correlation', 'status']) {
    test(
      'actual physical handoff rejects $fault proof and retains occupancy',
      () async {
        final h = await Held.create(), s = h.s, peer = h.peer;
        await h.reconcile(h.client);
        peer.alterReply = (command, rows) {
          if (command.kind == 'step-status') {
            if (fault == 'children')
              return {...rows, 'cgroup': 'populated 1\nfrozen 0'};
            if (fault == 'correlation')
              return {
                ...rows,
                'result': rows['result']!.replaceFirst(
                  s.store.snapshot.automation.jobs[h.job]!.hostAttemptId,
                  repository.id(3608),
                ),
              };
          }
          if (fault == 'status' && command.kind == 'status')
            return {
              ...rows,
              'admission': rows['admission']!.replaceFirst(
                s.store.snapshot.automation.jobs[h.job]!.hostAttemptId,
                repository.id(3608),
              ),
            };
          return rows;
        };
        await h.session.finish();
        await until(
          s,
          () =>
              peer.requests
                      .where((command) => command.kind == 'status')
                      .length ==
                  1 &&
              s.store.snapshot.automation.jobs[h.job]!.state == 'unknown',
        );
        final plan = await positive.plan(s, h.client, h.profile, 3610);
        await positive.approve(s, h.client, plan, 3611);
        fences.toolError(
          await s.tool(h.client, 'apply', {
            'requestId': repository.id(3612),
            'planId': plan['planId'],
          }),
          'HOST_BUSY',
        );
        expect(
          peer.requests.where((command) => command.kind == 'status').length,
          1,
        );
        h.noNewEffect();
      },
    );
  }
  test('accepted pending controls are pruned after terminal proof and before physical drain', () async {
    final h = await Held.create(), s = h.s, peer = h.peer;
    final physicalTerminal = Completer<void>();
    final statusReady = Completer<void>(), allowTerminal = Completer<void>();
    peer.beforeReply = (command, session) async {
      if (command.kind == 'terminal' && !statusReady.isCompleted) {
        statusReady.complete();
        await allowTerminal.future;
      }
    };
    s.repository.provider.afterCommit = () {
      final row = MemoryWorkspaceProvider.decode(
        s.repository.provider.readBytes(),
      )['StoredAutomationJob']!.single;
      if ((jsonDecode(row.payload) as Map)['state'] == 'cancelled') {
        s.repository.provider.afterCommit = null;
        for (final lease in s.runtime.gate.leases) {
          lease.pause = physicalTerminal;
        }
      }
    };
    addTearDown(() {
      s.repository.provider.afterCommit = null;
      if (!allowTerminal.isCompleted) allowTerminal.complete();
      if (!physicalTerminal.isCompleted) physicalTerminal.complete();
    });
    await h.reconcile(h.client);
    await h.session.finish();
    await statusReady.future.timeout(const Duration(seconds: 3));
    await h.reconcile(h.client, id: 3604);
    success(
      await s.tool(h.client, 'jobs_cancel', {
        'requestId': repository.id(3605),
        'jobId': h.job,
      }),
    );
    expect(s.store.snapshot.automation.jobs[h.job]!.state, 'reconciling');
    expect(
      peer.requests.where((command) => command.kind == 'status').length,
      1,
    );
    expect(peer.requests.where((command) => command.kind == 'stop').length, 0);
    allowTerminal.complete();
    await positive.waitJob(s, h.client, h.job, 'cancelled');
    final terminal = s.store.snapshot.automation.jobs[h.job]!.toJson();
    final before = peer.requests.length;
    success(
      await s.tool(h.client, 'jobs_reconcile', {
        'requestId': repository.id(3603),
        'jobId': h.job,
      }),
    );
    success(
      await s.tool(h.client, 'jobs_cancel', {
        'requestId': repository.id(3606),
        'jobId': h.job,
      }),
    );
    physicalTerminal.complete();
    await Future<void>.delayed(Duration.zero);
    expect(peer.requests.length, before);
    expect(s.store.snapshot.automation.jobs[h.job]!.toJson(), terminal);
    for (final id in [3603, 3604, 3605, 3606]) {
      expect(
        s.store.snapshot.automation.receipts.values.where(
          (r) => r.requestId == repository.id(id),
        ),
        hasLength(1),
      );
    }
    expect(
      peer.requests.where((command) => command.kind == 'status').length,
      1,
    );
    expect(peer.requests.where((command) => command.kind == 'stop').length, 0);
    h.noNewEffect();
  });
  test('same-ID replay rearms unknown after a previous control drains without creating a receipt', () async {
    final h = await Held.create(), s = h.s, peer = h.peer;
    bytes.Session? firstCycle;
    addTearDown(() async {
      await firstCycle?.finish();
    });
    var rearmed = false;
    peer.beforeReply = (command, session) async {
      if (command.kind != 'step-status') return;
      if (peer.requests
              .where((command) => command.kind == 'step-status')
              .length ==
          1) {
        session.autoClose = false;
        firstCycle = session;
        session.output.addError(StateError('RAM_CONTROL_RESPONSE_LOST'));
      } else {
        rearmed =
            s.store.snapshot.automation.jobs[h.job]!.state == 'reconciling';
      }
    };
    await h.reconcile(h.client);
    await h.session.finish();
    await until(
      s,
      () =>
          peer.requests.where((command) => command.kind == 'status').length ==
              1 &&
          s.store.snapshot.automation.jobs[h.job]!.state == 'unknown',
    );
    final previous = s.store.snapshot.automation.jobs[h.job]!;
    final receipts = s.store.snapshot.automation.receipts.length;
    success(
      await s.tool(h.client, 'jobs_reconcile', {
        'requestId': repository.id(3603),
        'jobId': h.job,
      }),
    );
    expect(
      peer.requests.where((command) => command.kind == 'status').length,
      1,
    );
    expect(s.store.snapshot.automation.receipts.length, receipts);
    expect(
      s.store.snapshot.automation.jobs[h.job]!.toJson(),
      previous.toJson(),
    );
    await firstCycle!.finish();
    await positive.waitJob(s, h.client, h.job, 'cancelled');
    final retained = s.store.snapshot.automation.jobs[h.job]!;
    expect(rearmed, isTrue);
    expect(
      peer.requests.where((command) => command.kind == 'status').length,
      2,
    );
    expect(s.store.snapshot.automation.receipts.length, receipts);
    expect(retained.nextSequence, previous.nextSequence + 2);
    expect(retained.hostAttemptId, previous.hostAttemptId);
    expect(retained.authority.toJson(), previous.authority.toJson());
    h.noNewEffect();
  });
  test('logical response cancellation preserves an accepted native control continuation', () async {
    final h = await Held.create(), s = h.s;
    final storage = s.repository.provider.lastOpened!;
    final put = Completer<void>();
    addTearDown(() {
      if (!put.isCompleted) put.complete();
    });
    final before = storage.putCalls;
    storage.holdPut = put;
    final operation = await s.ownerCall('jobs.reconcile', {
      'requestId': repository.id(3603),
      'jobId': h.job,
    });
    await until(s, () => storage.putCalls > before);
    final cancellation = await s.ownerCall('automation.cancel', {
      'operationId': operation['operationId'],
    });
    expect(cancellation['cancelled'], isTrue);
    storage.holdPut = null;
    put.complete();
    await until(
      s,
      () => s.store.snapshot.automation.jobs[h.job]!.state == 'reconciling',
    );
    expect(s.store.snapshot.automation.jobs[h.job]!.cancelRequested, isFalse);
    expect(
      h.peer.requests.where((command) => command.kind == 'status').length,
      0,
    );
    expect(
      h.peer.requests.where((command) => command.kind == 'stop').length,
      0,
    );
    await h.session.finish();
    await until(
      s,
      () => s.store.snapshot.automation.jobs[h.job]!.state == 'cancelled',
    );
    final result = await s.ownerCall('automation.status', {
      'operationId': operation['operationId'],
    });
    final content = (result['result'] as Map)['structuredContent'] as Map;
    expect(content['ok'], isFalse);
    expect((content['error'] as Map)['code'], 'CANCELLED');
    expect(
      s.store.snapshot.automation.receipts.values.where(
        (r) => r.requestId == repository.id(3603),
      ),
      hasLength(1),
    );
    expect(
      h.peer.requests.where((command) => command.kind == 'status').length,
      1,
    );
    expect(
      h.peer.requests.where((command) => command.kind == 'stop').length,
      0,
    );
    h.noNewEffect();
  });
  for (final close in [false, true]) {
    test(
      'actual native control write remains owned through ${close ? 'exit' : 'suspend'} seal',
      () async {
        final h = await Held.create(), s = h.s;
        final storage = s.repository.provider.lastOpened!;
        final put = Completer<void>();
        addTearDown(() {
          if (!put.isCompleted) put.complete();
        });
        final before = storage.putCalls;
        storage.holdPut = put;
        final operation = await s.ownerCall('jobs.reconcile', {
          'requestId': repository.id(3603),
          'jobId': h.job,
        });
        expect(operation['state'], 'running');
        await until(s, () => storage.putCalls > before);
        final drain = close
            ? s.services.jobs.close()
            : s.services.jobs.suspend();
        var settled = false;
        drain.then((_) => settled = true).ignore();
        await Future<void>.delayed(Duration.zero);
        expect(settled, isFalse);
        expect(
          h.peer.requests.where((command) => command.kind == 'status').length,
          0,
        );
        storage.holdPut = null;
        put.complete();
        await h.session.finish();
        await drain;
        expect(s.store.snapshot.automation.jobs[h.job]!.state, 'unknown');
        expect(
          s.store.snapshot.automation.receipts.values.where(
            (r) => r.requestId == repository.id(3603),
          ),
          hasLength(1),
        );
        expect(
          h.peer.requests.where((command) => command.kind == 'status').length,
          0,
        );
        expect(
          h.peer.requests.where((command) => command.kind == 'stop').length,
          0,
        );
        final result = await s.ownerCall('automation.status', {
          'operationId': operation['operationId'],
        });
        expect(
          ((result['result'] as Map)['structuredContent'] as Map)['ok'],
          isFalse,
        );
        if (!close) {
          s.services.jobs.resume();
          await Future<void>.delayed(Duration.zero);
          expect(
            h.peer.requests.where((command) => command.kind == 'status').length,
            0,
          );
          await ownerControl(s, 'jobs.reconcile', h.job, 3604);
          await until(
            s,
            () => s.store.snapshot.automation.jobs[h.job]!.state == 'cancelled',
          );
          expect(
            h.peer.requests.where((command) => command.kind == 'status').length,
            1,
          );
        }
        h.noNewEffect();
      },
    );
  }
  test('failed physical driver completion cannot activate accepted control or prove a successful pause', () async {
    final h = await Held.create(), s = h.s;
    await h.reconcile(h.client);
    h.session.completed.completeError(StateError('PRIVATE_UNIT_CHANNEL_CLOSE'));
    await h.session.finish();
    await expectLater(
      s.services.jobs.suspend(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'close code',
          'SERVICE_UNAVAILABLE',
        ),
      ),
    );
    expect(() => s.services.jobs.resume(), throwsStateError);
    expect(
      h.peer.requests.where((command) => command.kind == 'status').length,
      0,
    );
    expect(
      h.peer.requests.where((command) => command.kind == 'stop').length,
      0,
    );
    expect(
      {
        'succeeded',
        'failed',
        'cancelled',
      }.contains(s.store.snapshot.automation.jobs[h.job]!.state),
      isFalse,
    );
    await expectLater(
      s.close(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'service close',
          'SERVICE_UNAVAILABLE',
        ),
      ),
    );
    expect(s.repository.source.lease.closes, 0);
    h.noNewEffect();
  });
}
