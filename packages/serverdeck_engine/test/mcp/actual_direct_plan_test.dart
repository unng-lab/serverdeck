import 'package:serverdeck_protocol/direct_ssh_runtime.dart';
import 'package:serverdeck_engine/mcp/grants.dart';
import 'package:test/test.dart';

import '../automation/portable_program_test.dart' show motdBody;
import '../storage/actual_state_store_test.dart' as repository;
import '../support/actual_mcp_setup.dart';
import '../support/direct_ssh_byte_peer.dart';
import '../support/schema3_fixture.dart' as fixture;

Future<String> profile(Setup s) async =>
    (await s.ownerCall('automation.profiles.create', {
          'requestId': repository.id(3900),
          'name': 'direct plan',
          'body': motdBody(),
        }))['profileId']
        as String;
Map<String, Object?> arguments(String profile, int request) => {
  'requestId': repository.id(request),
  'serverId': fixture.profile,
  'profileId': profile,
  'revision': 1,
  'parameters': {'message': 'direct plan'},
};

void main() {
  for (final fault in ['proof', 'revoke']) {
    test(
      'actual direct preflight $fault cannot persist or publish a plan',
      () async {
        final peer = DirectSshBytePeer();
        final s = await Setup.create(direct: peer.attach);
        final id = await profile(s),
            client = await s.client(await s.grant(scopes: ['read', 'plan']));
        success(
          await s.tool(client, 'server_connect', {'serverId': fixture.profile}),
        );
        var injected = false;
        peer.beforeOutput = (command) async {
          if (injected || command.kind != 'packages') return;
          injected = true;
          if (fault == 'proof') {
            client.peer.proofError = StateError('PRIVATE_PREFLIGHT_PROOF');
          } else {
            await s.store.mutateOwnerGrant(
              OwnerGrantCommand.parse('grant.revoke', {
                'requestId': repository.id(3911),
                'grantId': client.grantId,
                'expectedRevision': 1,
              }),
              clock: utcNow,
            );
          }
        };
        await expectLater(
          s.tool(client, 'plan_create', arguments(id, 3910)),
          repository.failure('UNAUTHORIZED'),
        );
        expect(injected, isTrue);
        expect(s.store.snapshot.automation.plans, isEmpty);
        expect(
          s.store.snapshot.automation.receipts.containsKey(repository.id(3910)),
          isFalse,
        );
        expect(s.store.snapshot.automation.jobs, isEmpty);
      },
    );
  }
  test('committed direct plan preserves receipt after lost native ACK without rebuilding preflight', () async {
    final peer = DirectSshBytePeer();
    final s = await Setup.create(direct: peer.attach);
    final id = await profile(s),
        client = await s.client(await s.grant(scopes: ['read', 'plan']));
    success(
      await s.tool(client, 'server_connect', {'serverId': fixture.profile}),
    );
    final input = arguments(id, 3912);
    s.repository.provider.afterCommit = () =>
        client.peer.proofError = StateError('PRIVATE_PLAN_ACK');
    await expectLater(
      s.tool(client, 'plan_create', input),
      repository.failure('UNAUTHORIZED'),
    );
    s.repository.provider.afterCommit = null;
    final plan = s.store.snapshot.automation.plans.values.single;
    expect(plan.preflight!.isDirectSsh, isTrue);
    final receipt = s.store.snapshot.automation.receipts[repository.id(3912)]!;
    final requests = peer.requests.length,
        commits = s.repository.provider.lastOpened!.commits;
    final fresh = await s.client(client.grantId);
    expect(success(await s.tool(fresh, 'plan_create', input)), receipt.result);
    expect(peer.requests.length, requests);
    expect(s.repository.provider.lastOpened!.commits, commits);
    expect(
      () => s.services.plans.preflightFor(plan),
      repository.failure('PLAN_STALE'),
    );
  });

  test('actual direct preflight cache has a finite admission quota and retires on disconnect', () async {
    final peer = DirectSshBytePeer();
    final s = await Setup.create(direct: peer.attach);
    final id = await profile(s),
        client = await s.client(await s.grant(scopes: ['read', 'plan']));
    success(
      await s.tool(client, 'server_connect', {'serverId': fixture.profile}),
    );
    for (var i = 0; i < 16; i++) {
      final receipt = success(
        await s.tool(client, 'plan_create', arguments(id, 3950 + i)),
      );
      final plan = s.store.snapshot.automation.plans[receipt['planId']]!;
      expect(plan.status, 'runnable');
      final facts = s.services.plans.preflightFor(plan);
      expect(facts.capsuleDigest, plan.preflight!.digest);
      expect(() => facts.observations.clear(), throwsUnsupportedError);
    }
    final requests = peer.requests.length;
    final receipt = success(
      await s.tool(client, 'plan_create', arguments(id, 3966)),
    );
    final blocked = s.store.snapshot.automation.plans[receipt['planId']]!;
    expect(blocked.status, 'blocked');
    expect(
      (blocked.toJson()['reasons'] as List).single,
      containsPair('code', 'RESOURCE_LIMIT'),
    );
    expect(peer.requests.length, requests);
    final prior = s.store.snapshot.automation.plans.values.first;
    success(
      await s.tool(client, 'server_disconnect', {'serverId': fixture.profile}),
    );
    expect(
      () => s.services.plans.preflightFor(prior),
      repository.failure('PLAN_STALE'),
    );
    await s.close();
    final reopened = await Setup.reopen(s.repository, direct: peer.attach);
    expect(
      reopened.store.snapshot.automation.plans[prior.id]!.toJson(),
      prior.toJson(),
    );
    expect(
      () => reopened.services.plans.preflightFor(prior),
      repository.failure('PLAN_STALE'),
    );
  });

  for (final fault in [
    'package-change',
    'reboot',
    'missing-dpkg',
    'partial-package',
  ]) {
    test(
      'actual direct preflight blocks $fault without remote writes',
      () async {
        final peer = DirectSshBytePeer();
        if (fault == 'missing-dpkg')
          peer.missingExecutables.add('/usr/bin/dpkg-query');
        if (fault == 'partial-package')
          peer.packages = 'base-files\tamd64\t1\thalf-configured';
        var snapshots = 0, inspections = 0;
        final host = await Setup.create(
          direct: (session, command) {
            if (command.kind == 'packages' &&
                ++snapshots == 2 &&
                fault == 'package-change') {
              peer.packages = peer.packages.replaceFirst('0.35.0', '0.36.0');
            }
            if (command.kind == 'inspect' &&
                ++inspections == 2 &&
                fault == 'reboot') {
              peer.inspectRows['boot'] = '22345678-1234-4234-9234-123456789abc';
            }
            peer.attach(session, command);
          },
        );
        final id = await profile(host),
            client = await host.client(
              await host.grant(scopes: ['read', 'plan']),
            );
        success(
          await host.tool(client, 'server_connect', {
            'serverId': fixture.profile,
          }),
        );
        final receipt = success(
          await host.tool(client, 'plan_create', arguments(id, 3902)),
        );
        final plan = host.store.snapshot.automation.plans[receipt['planId']]!;
        expect(plan.status, 'blocked');
        expect(plan.preflight, isNull);
        expect(plan.toJson()['effects'], isEmpty);
        expect(host.store.snapshot.automation.jobs, isEmpty);
        expect(peer.requests.every((command) => !command.mutates), isTrue);
      },
    );
  }

  test(
    'actual owner plan uses the same direct compiler and isolated cache',
    () async {
      final peer = DirectSshBytePeer();
      final host = await Setup.create(direct: peer.attach);
      final id = await profile(host);
      final connecting = await host.ownerCall('servers.connect', {
        'profileId': fixture.profile,
      });
      for (var i = 0; i < 100; i++) {
        final value = await host.ownerCall('servers.connectStatus', {
          'operationId': connecting['operationId'],
        });
        if (value['state'] == 'succeeded') break;
        await Future<void>.delayed(Duration.zero);
      }
      final started = await host.ownerCall('plans.create', arguments(id, 3903));
      Map<String, Object?> value = {};
      for (var i = 0; i < 500; i++) {
        value = await host.ownerCall('automation.status', {
          'operationId': started['operationId'],
        });
        if (value['state'] == 'done') break;
        await Future<void>.delayed(Duration.zero);
      }
      expect(value['state'], 'done');
      final result = value['result'] as Map;
      expect(result['isError'], isFalse);
      expect((result['structuredContent'] as Map)['ok'], isTrue);
      final plan = host.store.snapshot.automation.plans.values.single;
      expect(plan.preflight!.isDirectSsh, isTrue);
      expect(peer.requests.map((c) => c.kind).toList(), [
        'inspect',
        'packages',
        'observation',
        'packages',
        'inspect',
      ]);
    },
  );

  test('actual plan creates a local format2 capsule without executor enrollment or release', () async {
    final peer = DirectSshBytePeer();
    final host = await Setup.create(direct: peer.attach);
    final id = await profile(host),
        client = await host.client(await host.grant(scopes: ['read', 'plan']));
    success(
      await host.tool(client, 'server_connect', {'serverId': fixture.profile}),
    );
    final input = arguments(id, 3901);
    final receipt = success(await host.tool(client, 'plan_create', input));
    final plan = host.store.snapshot.automation.plans[receipt['planId']]!;
    expect(plan.status, 'runnable');
    expect(plan.preflight!.isDirectSsh, isTrue);
    expect(plan.hostId, peer.hostId);
    expect(plan.registryDigest, DirectSshRuntime.registryDigest);
    expect(plan.baseObservations.keys, {'system.motd'});
    expect(
      (plan.toJson()['effects'] as List).single,
      containsPair('kind', 'config_file'),
    );
    expect(await host.store.readExecutorEnrollments(), isEmpty);
    expect(host.store.snapshot.automation.jobs, isEmpty);
    final requests = peer.requests.length;
    expect(success(await host.tool(client, 'plan_create', input)), receipt);
    expect(peer.requests.length, requests);
    final view = success(
      await host.tool(client, 'plans_get', {'planId': plan.id}),
    );
    expect((view['plan'] as Map)['preflight'], plan.preflight!.toJson());
    expect(
      host.io.attempts.single.client.commands.every(
        (command) => command.operation != null,
      ),
      isTrue,
    );
  });
}
