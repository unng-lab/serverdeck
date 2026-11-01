import 'dart:async';

import 'package:serverdeck_engine/hosting/sessions.dart';
import 'package:serverdeck_engine/remote/reads.dart';
import 'package:serverdeck_engine/remote/ssh_transport.dart';
import 'package:test/test.dart';

import '../support/remote_read_setup.dart';
import '../support/schema3_fixture.dart' as fixture;
import 'ssh_pool_lifecycle_test.dart' show settle;

Matcher failure(String code) =>
    throwsA(isA<StateError>().having((e) => e.message, 'safe code', code));
const stateRequest = {
  'request': {
    'name': 'serverdeck_state_get',
    'arguments': {'serverId': fixture.profile, 'refresh': true},
  },
};
Map payload(Map reply) => (reply['result'] as Map)['structuredContent'] as Map;
Future<Map<String, Object?>> poll(Setup s, Mcp client, String id) =>
    s.invoke(client, {
      'poll': {'operationId': id},
    });

void main() {
  test(
    'MCP bootstrap and grant open verify real HMAC and dispose the owned key',
    () async {
      final s = await Setup.create(), client = await s.mcp();
      expect(client.context.grantId, fixture.grant);
      expect(client.context.workspaceId, fixture.workspace);
      expect(s.store.grants.opened, hasLength(1));
      final owned = s.store.grants.opened.single;
      expect(owned.closes, 1);
      await expectLater(owned.key.mac([1]), failure('STORAGE_BLOCKED'));
      await s.attach(client);
      expect(s.pool.activeTransports, 1);
    },
  );

  test('owner and MCP share one four-source refresh; repeated polls never start another', () async {
    final s = await Setup.create(), client = await s.mcp();
    await s.attach(client);
    s.holdSystem = true;
    final pending = await s.invoke(client, stateRequest);
    final id = pending['operationId'] as String;
    await s.ownerCall('servers.state', {
      'profileId': fixture.profile,
      'refresh': true,
    });
    await settle();
    expect(s.held, hasLength(1));
    for (var i = 0; i < 3; i++)
      expect((await poll(s, client, id))['done'], isFalse);
    expect(s.io.attempts.single.client.commands, hasLength(1));
    s.holdSystem = false;
    s.respond(s.held.single, SshReadSource.system);
    await settle();
    final mcp = await poll(s, client, id);
    expect(mcp['done'], isTrue);
    expect(payload(mcp)['ok'], isTrue);
    final owner = await s.ownerCall('servers.readStatus', {
      'operationId': fixture.request1,
    });
    expect(owner['state'], 'succeeded');
    expect(owner['result'], payload(mcp)['data']);
    expect(s.io.attempts.single.client.commands.map((c) => c.read!.source), [
      SshReadSource.system,
      SshReadSource.metrics,
      SshReadSource.packages,
      SshReadSource.units,
    ]);
    expect(payload(await s.invoke(client, stateRequest))['ok'], isTrue);
    expect(s.io.attempts.single.client.commands, hasLength(4));
  });

  test('MCP cancellation retires only its interest while owner receives the shared refresh', () async {
    final s = await Setup.create(), client = await s.mcp();
    await s.attach(client);
    s.holdSystem = true;
    final pending = await s.invoke(client, stateRequest),
        id = pending['operationId'] as String;
    await s.ownerCall('servers.state', {
      'profileId': fixture.profile,
      'refresh': true,
    });
    await settle();
    var acknowledged = false;
    final cancel = s
        .invoke(client, {
          'cancel': {'operationId': id},
        })
        .then((reply) {
          acknowledged = true;
          return reply;
        });
    await settle();
    expect(acknowledged, isFalse);
    s.holdSystem = false;
    s.respond(s.held.single, SshReadSource.system);
    expect(await cancel, {'cancelled': true});
    await settle();
    final owner = await s.ownerCall('servers.readStatus', {
      'operationId': fixture.request1,
    });
    expect(owner['state'], 'succeeded');
    await expectLater(poll(s, client, id), failure('FORBIDDEN'));
    expect(s.io.attempts.single.client.commands, hasLength(4));
    expect(s.pool.activeTransports, 1);
  });

  test('revoked collector hands off to owner and retains old physical drain before service close', () async {
    final s = await Setup.create(), client = await s.mcp();
    await s.attach(client);
    s.holdSystem = true;
    await s.invoke(client, stateRequest);
    await s.ownerCall('servers.state', {
      'profileId': fixture.profile,
      'refresh': true,
    });
    await settle();
    final old = s.held.single;
    s.holdSystem = false;
    s.store.revoke();
    await expectLater(client.context.revalidate(), failure('UNAUTHORIZED'));
    await settle();
    final owner = await s.ownerCall('servers.readStatus', {
      'operationId': fixture.request1,
    });
    expect(owner['state'], 'succeeded');
    expect(s.io.attempts.single.client.commands, hasLength(5));
    expect(old.finishing, isFalse);
    var closed = false;
    final closing = s.reads.close().then((_) => closed = true);
    await settle();
    expect(closed, isFalse);
    expect(s.pool.activeTransports, 1);
    await old.finish();
    await closing;
    expect(closed, isTrue);
    expect(s.store.grants.opened.single.closes, 1);
  });

  test(
    'read-only MCP cannot escalate to logs, plans or an unlisted server',
    () async {
      final s = await Setup.create(), client = await s.mcp();
      await s.attach(client);
      for (final input in [
        {
          'request': {
            'name': 'serverdeck_logs_read',
            'arguments': {'serverId': fixture.profile},
          },
        },
        {
          'request': {
            'name': 'serverdeck_recipes_list',
            'arguments': {'serverId': fixture.profile},
          },
        },
        {
          'request': {
            'name': 'serverdeck_state_get',
            'arguments': {'serverId': fixture.request2},
          },
        },
      ]) {
        await expectLater(s.invoke(client, input), failure('FORBIDDEN'));
      }
      expect(s.io.attempts.single.client.commands, isEmpty);
    },
  );

  test('owner read handle is stable, bound to principal and kind, without repeated I/O', () async {
    final s = await Setup.create(), other = await s.newOwner();
    await s.ownerCall('servers.state', {
      'profileId': fixture.profile,
      'refresh': true,
    });
    await settle();
    expect(
      (await s.ownerCall('servers.state', {
        'profileId': fixture.profile,
        'refresh': true,
      }))['operationId'],
      fixture.request1,
    );
    await expectLater(
      s.ownerCall('servers.readStatus', {
        'operationId': fixture.request1,
      }, asOwner: other),
      failure('NOT_FOUND'),
    );
    await expectLater(
      s.ownerCall('servers.logs', {'profileId': fixture.profile}),
      failure('IDEMPOTENCY_CONFLICT'),
    );
    for (var i = 0; i < 3; i++)
      expect(
        (await s.ownerCall('servers.readStatus', {
          'operationId': fixture.request1,
        }))['state'],
        'succeeded',
      );
    expect(s.io.attempts.single.client.commands, hasLength(4));
  });

  test('actual read-work quotas retain sixteen per principal and forty-eight total during proof drain', () async {
    final s = await Setup.create();
    final actors = <TrustedOwnerReadContext>[await s.ownerContext()];
    for (var i = 0; i < 3; i++)
      actors.add(await s.ownerContext(await s.newOwner()));
    s.runtime.proof = Completer<void>();
    final work = <RemoteReadWork>[];
    for (final actor in actors.take(3)) {
      for (var i = 0; i < 16; i++) {
        final read = s.reads.startOwner(actor, 'serverdeck_state_get', {
          'serverId': fixture.profile,
        });
        read.result.ignore();
        work.add(read);
      }
      expect(
        () => s.reads.startOwner(actor, 'serverdeck_state_get', {
          'serverId': fixture.profile,
        }),
        failure('RESOURCE_LIMIT'),
      );
    }
    void requireGlobalRefusal() => expect(
      () => s.reads.startOwner(actors.last, 'serverdeck_state_get', {
        'serverId': fixture.profile,
      }),
      failure('RESOURCE_LIMIT'),
    );
    // The fourth principal has no work: only the global48 bound can refuse it.
    requireGlobalRefusal();
    var drained = false;
    final cancelled = work.first.cancelInterest().then((_) => drained = true);
    await expectLater(work.first.result, failure('CANCELLED'));
    await settle();
    expect(drained, isFalse);
    requireGlobalRefusal(); // Logical cancellation cannot free physical quota.
    s.runtime.proof!.complete();
    await cancelled;
    await Future.wait([for (final read in work) read.done]);
    expect(drained, isTrue);
    final admitted = s.reads.startOwner(actors.last, 'serverdeck_state_get', {
      'serverId': fixture.profile,
    });
    expect((await admitted.result)['serverId'], fixture.profile);
    await admitted.done;
    expect(s.io.attempts.single.client.commands, isEmpty);
  });

  test('four read channels share the actual lease quota and reject the fifth without execution', () async {
    final s = await Setup.create();
    s.holdSystem = true;
    final actor = await s.ownerContext();
    final work = [
      for (var i = 0; i < 5; i++)
        s.connections.readOwner(
          actor,
          fixture.profile,
          const SshReadRequest.system(),
        ),
    ];
    for (final read in work) read.result.ignore();
    await settle();
    expect(s.held, hasLength(4));
    await expectLater(work.last.result, failure('RESOURCE_LIMIT'));
    await work.last.done;
    expect(s.io.attempts.single.client.commands, hasLength(4));
    s.holdSystem = false;
    for (final session in s.held) s.respond(session, SshReadSource.system);
    await Future.wait([for (final read in work.take(4)) read.result]);
    await Future.wait([for (final read in work) read.done]);
    expect(s.pool.activeTransports, 1);
  });
}
