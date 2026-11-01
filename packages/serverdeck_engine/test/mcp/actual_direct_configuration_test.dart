import 'package:test/test.dart';

import '../support/actual_mcp_setup.dart';
import '../support/direct_ssh_byte_peer.dart';
import '../support/schema3_fixture.dart' as fixture;
import '../remote/ssh_pool_lifecycle_test.dart' show settle;
import '../remote/read_clock_test.dart' show Clock;

void main() {
  test('read routes ignore unrelated tools and refuse their own missing prerequisites', () async {
    final peer = DirectSshBytePeer();
    peer.missingExecutables.addAll({
      '/usr/bin/systemd-run',
      '/usr/bin/flock',
      '/usr/bin/sync',
      '/usr/bin/awk',
    });
    final s = await Setup.create(direct: peer.attach);
    final client = await s.client(await s.grant(scopes: ['read']));
    success(
      await s.tool(client, 'server_connect', {'serverId': fixture.profile}),
    );
    Future<String> status(String resource) async {
      final value = success(
        await s.tool(client, 'configuration_get', {
          'serverId': fixture.profile,
          'resourceId': resource,
          'refresh': true,
        }),
      );
      return (value['observation'] as Map)['status'] as String;
    }

    for (final resource in [
      'system.motd',
      'postgresql.settings',
      'clickhouse.settings',
      'postgresql.service',
      'clickhouse.service',
    ]) {
      expect(await status(resource), 'known', reason: resource);
    }
    peer.missingExecutables.add('/usr/bin/sha256sum');
    expect(await status('postgresql.service'), 'known');
    expect(await status('system.motd'), 'unsupported');
    peer.missingExecutables.remove('/usr/bin/sha256sum');
    peer.missingExecutables.add('/usr/bin/systemctl');
    expect(await status('system.motd'), 'known');
    expect(await status('clickhouse.service'), 'unsupported');
    peer.missingExecutables.add('/usr/bin/base64');
    expect(await status('system.motd'), 'unsupported');
  });

  test('direct cached facts become stale on SSH retirement without erasing the observation', () async {
    final peer = DirectSshBytePeer(), clock = Clock();
    final s = await Setup.create(direct: peer.attach, readClock: clock);
    final client = await s.client(await s.grant(scopes: ['read']));
    success(
      await s.tool(client, 'server_connect', {'serverId': fixture.profile}),
    );
    final first = success(
      await s.tool(client, 'configuration_get', {
        'serverId': fixture.profile,
        'resourceId': 'system.motd',
        'refresh': true,
      }),
    );
    success(
      await s.tool(client, 'server_disconnect', {'serverId': fixture.profile}),
    );
    final cached = success(
      await s.tool(client, 'configuration_get', {
        'serverId': fixture.profile,
        'resourceId': 'system.motd',
      }),
    );
    expect((cached['observation'] as Map)['status'], 'stale');
    expect(
      (cached['observation'] as Map)['value'],
      (first['observation'] as Map)['value'],
    );
    expect(peer.requests, hasLength(2));
  });

  test(
    'aged non-known observations stay typed and never acquire stale values',
    () async {
      final peer = DirectSshBytePeer()..error = 'FORBIDDEN', clock = Clock();
      final s = await Setup.create(direct: peer.attach, readClock: clock);
      final client = await s.client(await s.grant(scopes: ['read']));
      success(
        await s.tool(client, 'server_connect', {'serverId': fixture.profile}),
      );
      final first = success(
        await s.tool(client, 'configuration_get', {
          'serverId': fixture.profile,
          'resourceId': 'system.motd',
          'refresh': true,
        }),
      );
      clock.elapsed = const Duration(seconds: 20);
      final cached = success(
        await s.tool(client, 'configuration_get', {
          'serverId': fixture.profile,
          'resourceId': 'system.motd',
        }),
      );
      expect((cached['observation'] as Map)['status'], 'denied');
      expect(cached['observation'], first['observation']);
      expect(peer.requests, hasLength(1));
    },
  );
  test('actual owner and MCP configuration read all resources directly without enrollment', () async {
    final peer = DirectSshBytePeer(),
        s = await Setup.create(direct: peer.attach);
    final client = await s.client(await s.grant(scopes: ['read']));
    success(
      await s.tool(client, 'server_connect', {'serverId': fixture.profile}),
    );
    final commits = s.repository.provider.lastOpened!.commits,
        fileWrites = s.repository.source.files.writes;
    for (final resource in [
      'system.motd',
      'postgresql.settings',
      'clickhouse.settings',
      'postgresql.service',
      'clickhouse.service',
    ]) {
      final view = success(
        await s.tool(client, 'configuration_get', {
          'serverId': fixture.profile,
          'resourceId': resource,
          'refresh': true,
        }),
      );
      expect((view['observation'] as Map)['status'], 'known');
      expect((view['observation'] as Map)['hostId'], peer.hostId);
      expect(
        view['desired'],
        isNull,
      ); // Read facts never adopt an installation.
      expect((view['comparison'] as Map)['status'], 'unmanaged');
    }
    final connecting = await s.ownerCall('servers.connect', {
      'profileId': fixture.profile,
    });
    await settle();
    expect(
      (await s.ownerCall('servers.connectStatus', {
        'operationId': connecting['operationId'],
      }))['state'],
      'succeeded',
    );
    final owner = await s.ownerRead('servers.configuration', {
      'profileId': fixture.profile,
      'resourceId': 'system.motd',
      'refresh': true,
    });
    expect((owner['observation'] as Map)['status'], 'known');
    expect(
      s.io.attempts.single.client.commands.every(
        (command) => command.operation != null,
      ),
      isTrue,
    );
    expect(s.repository.source.files.writes, fileWrites);
    expect(s.repository.provider.lastOpened!.commits, commits);
  });

  test('actual direct permission refusal is cached as denied with no invented baseline', () async {
    final peer = DirectSshBytePeer()..error = 'FORBIDDEN';
    final s = await Setup.create(direct: peer.attach);
    final client = await s.client(await s.grant(scopes: ['read']));
    success(
      await s.tool(client, 'server_connect', {'serverId': fixture.profile}),
    );
    final view = success(
      await s.tool(client, 'configuration_get', {
        'serverId': fixture.profile,
        'resourceId': 'system.motd',
        'refresh': true,
      }),
    );
    expect((view['observation'] as Map)['status'], 'denied');
    expect((view['observation'] as Map)['value'], isNull);
    final cached = success(
      await s.tool(client, 'configuration_get', {
        'serverId': fixture.profile,
        'resourceId': 'system.motd',
      }),
    );
    expect(cached['observation'], view['observation']);
    expect(
      peer.requests,
      hasLength(1),
    ); // No resource read after denied inspect.
  });
}
