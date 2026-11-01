import 'package:test/test.dart';

import '../automation/portable_program_test.dart' show motdBody;
import '../support/actual_mcp_setup.dart';
import '../support/schema3_fixture.dart' as fixture;
import '../storage/actual_state_store_test.dart' as repository;

void main() {
  test('all seven profile tools run actual services/store with IDs CAS and receipts', () async {
    final s = await Setup.create(), client = await s.client(await s.grant());
    final validated = success(
      await s.tool(client, 'profiles_validate', {'body': motdBody()}),
    );
    expect(validated['valid'], isTrue);
    final created = success(
      await s.tool(client, 'profiles_create', {
        'requestId': repository.id(3100),
        'name': 'actual MCP catalog',
        'body': motdBody(),
      }),
    );
    final profileId = created['profileId'] as String;
    final commits = s.repository.provider.lastOpened!.commits;
    expect(
      success(
        await s.tool(client, 'profiles_create', {
          'requestId': repository.id(3100),
          'name': 'actual MCP catalog',
          'body': motdBody(),
        }),
      ),
      created,
    );
    expect(s.repository.provider.lastOpened!.commits, commits);
    final conflict = await s.tool(client, 'profiles_create', {
      'requestId': repository.id(3100),
      'name': 'conflicting intent',
      'body': motdBody(),
    });
    expect(
      (((conflict['result'] as Map)['structuredContent'] as Map)['error']
          as Map)['code'],
      'IDEMPOTENCY_CONFLICT',
    );
    expect(created['revision'], 1);
    expect(
      s.store.snapshot.automation.receipts[repository.id(3100)]!.originGrantId,
      client.grantId,
    );
    final fetched = success(
      await s.tool(client, 'profiles_get', {'profileId': profileId}),
    );
    expect((fetched['profile'] as Map)['id'], profileId);
    expect((fetched['revision'] as Map)['digest'], validated['digest']);
    final updated = success(
      await s.tool(client, 'profiles_update', {
        'requestId': repository.id(3101),
        'profileId': profileId,
        'expectedRevision': 1,
        'body': {
          ...motdBody(),
          'parameters': {
            'message': {
              'type': 'string',
              'maxLength': 64,
              'default': 'changed',
            },
          },
        },
      }),
    );
    expect(updated['revision'], 2);
    final diff = success(
      await s.tool(client, 'profiles_compare', {
        'profileId': profileId,
        'fromRevision': 1,
        'toRevision': 2,
      }),
    );
    expect(diff['changes'], isNotEmpty);
    final listed = success(await s.tool(client, 'profiles_list', {}));
    expect(
      (listed['items'] as List).map((p) => (p as Map)['id']),
      contains(profileId),
    );
    final archived = success(
      await s.tool(client, 'profiles_archive', {
        'requestId': repository.id(3102),
        'profileId': profileId,
        'expectedRevision': 2,
      }),
    );
    expect(archived['archived'], isTrue);
    expect(s.store.snapshot.automation.profiles[profileId]!.archived, isTrue);
    expect(s.store.snapshot.automation.revisions, hasLength(2));
    expect(s.successful, {
      'profiles_validate',
      'profiles_create',
      'profiles_get',
      'profiles_update',
      'profiles_compare',
      'profiles_list',
      'profiles_archive',
    });
    expect(s.io.attempts, isEmpty);
  });

  test('lost peer proof after committed mutation suppresses ACK and explicit retry uses receipt', () async {
    final s = await Setup.create(), client = await s.client(await s.grant());
    final args = <String, Object?>{
      'requestId': repository.id(3110),
      'name': 'committed before peer loss',
      'body': motdBody(),
    };
    s.repository.provider.afterCommit = () =>
        client.peer.proofError = StateError('PRIVATE_AFTER_COMMIT');
    await expectLater(
      s.tool(client, 'profiles_create', args),
      repository.failure('UNAUTHORIZED'),
    );
    final receipt = s.store.snapshot.automation.receipts[repository.id(3110)]!;
    expect(receipt.originGrantId, client.grantId);
    expect(s.repository.provider.lastOpened!.commits, 2);
    expect(s.successful, isEmpty);
    s.repository.provider.afterCommit = null;
    final fresh = await s.client(client.grantId);
    expect(
      success(await s.tool(fresh, 'profiles_create', args)),
      receipt.result,
    );
    expect(s.repository.provider.lastOpened!.commits, 2);
    expect(s.store.snapshot.automation.profiles, hasLength(1));
    expect(s.io.attempts, isEmpty);
  });

  test('server inventory connection state and logs route through actual byte ports', () async {
    final s = await Setup.create(), client = await s.client(await s.grant());
    final listed = success(await s.tool(client, 'servers_list', {}));
    expect((listed['items'] as List).map((p) => (p as Map)['id']), [
      fixture.profile,
    ]);
    final fetched = success(
      await s.tool(client, 'server_get', {'serverId': fixture.profile}),
    );
    expect((fetched['profile'] as Map)['id'], fixture.profile);
    expect((fetched['capabilities'] as Map)['executor'], isFalse);
    success(
      await s.tool(client, 'server_connect', {'serverId': fixture.profile}),
    );
    final state = success(
      await s.tool(client, 'state_get', {
        'serverId': fixture.profile,
        'refresh': true,
      }),
    );
    expect(state['serverId'], fixture.profile);
    expect((state['connection'] as Map)['state'], 'connected');
    expect((state['system'] as Map)['quality'], 'known');
    expect(((state['system'] as Map)['value'] as Map)['hostname'], 'unit');
    expect((state['packages'] as Map)['quality'], 'known');
    final logs = success(
      await s.tool(client, 'logs_read', {
        'serverId': fixture.profile,
        'limit': 10,
      }),
    );
    expect(logs['serverId'], fixture.profile);
    expect(logs['source'], 'journald');
    expect(logs['quality'], 'known');
    expect(logs['parseErrors'], 0);
    expect(((logs['records'] as List).single as Map)['message'], 'unit log');
    success(
      await s.tool(client, 'server_disconnect', {'serverId': fixture.profile}),
    );
    expect(s.successful, {
      'servers_list',
      'server_get',
      'server_connect',
      'state_get',
      'logs_read',
      'server_disconnect',
    });
    expect(s.io.attempts, hasLength(1));
    expect(
      s.io.attempts.single.client.commands.every((c) => c.read != null),
      isTrue,
    );
    expect(
      s.io.attempts.single.client.commands
          .map((c) => c.read!.source.name)
          .toSet(),
      {'system', 'metrics', 'packages', 'units', 'journal'},
    );
    expect(s.repository.provider.lastOpened!.commits, 1); // only fixture grant
  });
}
