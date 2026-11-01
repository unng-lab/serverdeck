import 'package:serverdeck_engine/mcp/grants.dart';
import 'package:serverdeck_protocol/mcp/catalog.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';
import 'package:test/test.dart';

import '../automation/portable_program_test.dart' show motdBody;
import '../support/actual_mcp_setup.dart';
import '../support/schema3_fixture.dart' as fixture;
import '../storage/actual_state_store_test.dart' as repository;

const readTools = {
  'servers_list',
  'server_get',
  'server_connect',
  'server_disconnect',
  'state_get',
  'configuration_get',
  'jobs_list',
  'jobs_get',
  'jobs_events',
  'jobs_reconcile',
};
const authorTools = {
  'profiles_list',
  'profiles_get',
  'profiles_create',
  'profiles_update',
  'profiles_compare',
  'profiles_validate',
  'profiles_archive',
};

Map<String, Object?> validArguments(String name) {
  final server = <String, Object?>{'serverId': fixture.profile};
  final request = repository.id(3010), object = repository.id(3011);
  return switch (name) {
    'servers_list' || 'profiles_list' || 'jobs_list' => {},
    'server_get' ||
    'server_connect' ||
    'server_disconnect' ||
    'state_get' ||
    'logs_read' ||
    'recipes_list' => server,
    'configuration_get' => {...server, 'resourceId': 'system.motd'},
    'profiles_get' => {'profileId': object},
    'profiles_create' => {
      'requestId': request,
      'name': 'shape check',
      'body': motdBody(),
    },
    'profiles_update' => {
      'requestId': request,
      'profileId': object,
      'expectedRevision': 1,
      'body': motdBody(),
    },
    'profiles_compare' => {
      'profileId': object,
      'fromRevision': 1,
      'toRevision': 2,
    },
    'profiles_validate' => {'body': motdBody()},
    'profiles_archive' => {
      'requestId': request,
      'profileId': object,
      'expectedRevision': 1,
    },
    'plan_create' => {
      ...server,
      'requestId': request,
      'profileId': object,
      'revision': 1,
      'parameters': <String, Object?>{},
    },
    'plans_get' => {'planId': object},
    'approval_request' || 'apply' => {'requestId': request, 'planId': object},
    'jobs_get' || 'jobs_events' => {'jobId': object},
    'jobs_cancel' ||
    'jobs_reconcile' => {'requestId': request, 'jobId': object},
    _ => throw StateError('UNDECLARED_TOOL_SHAPE'),
  };
}

void main() {
  test('production composition exposes exactly24 tools after actual two-stage HMAC', () async {
    final s = await Setup.create(), client = await s.client(await s.grant());
    final catalog = await s.invoke(client, {'catalog': <String, Object?>{}});
    expect(
      (catalog['tools'] as List).map((t) => (t as Map)['name']).toSet(),
      allToolNames.map(fullName).toSet(),
    );
    expect(s.io.attempts, isEmpty);
  });

  test(
    'empty valid grant denies each24 tool before argument parsing or effects',
    () async {
      final s = await Setup.create(),
          client = await s.client(await s.grant(scopes: [], targets: []));
      final commits = s.repository.provider.lastOpened!.commits,
          before = repository.rawRows(s.store);
      for (final name in allToolNames) {
        await expectLater(
          s.tool(client, name, {}),
          repository.failure('FORBIDDEN'),
          reason: name,
        );
      }
      expect(repository.rawRows(s.store), before);
      expect(s.repository.provider.lastOpened!.commits, commits);
      expect(s.io.attempts, isEmpty);
      expect(s.services.router.chargedOperations, 0);
    },
  );

  test('actual policy lattice filters catalog and denies every missing required scope', () async {
    final s = await Setup.create();
    final policies = <List<String>, Set<String>>{
      []: {},
      ['author']: authorTools,
      ['read']: readTools,
      ['read', 'logs']: {...readTools, 'logs_read'},
      ['read', 'plan']: {
        ...readTools,
        'recipes_list',
        'plan_create',
        'plans_get',
      },
      ['read', 'plan', 'apply']: {
        ...readTools,
        'recipes_list',
        'plan_create',
        'plans_get',
        'approval_request',
        'apply',
        'jobs_cancel',
      },
    };
    for (final entry in policies.entries) {
      final client = await s.client(await s.grant(scopes: entry.key));
      final catalog = await s.invoke(client, {'catalog': <String, Object?>{}});
      expect(
        (catalog['tools'] as List).map((t) => (t as Map)['name']).toSet(),
        entry.value.map(fullName).toSet(),
      );
      for (final tool in mcpTools) {
        if (tool.requiredScopes.every(
          (scope) => entry.key.contains(scope.name),
        ))
          continue;
        await expectLater(
          s.tool(client, tool.name.substring('serverdeck_'.length), {}),
          repository.failure('FORBIDDEN'),
          reason: '${entry.key}: ${tool.name}',
        );
      }
      s.sessions.disconnect(client.channel);
    }
    expect(s.io.attempts, isEmpty);
  });

  test(
    'all24 schemas reject owner forgery field before starting domain work',
    () async {
      final s = await Setup.create(), client = await s.client(await s.grant());
      final commits = s.repository.provider.lastOpened!.commits;
      for (final name in allToolNames) {
        final args = validArguments(name);
        expect(
          () => validateMcpArguments(mcpTool(fullName(name))!, args),
          returnsNormally,
          reason: name,
        );
        final reply = await s.tool(client, name, {...args, 'owner': true});
        expect(reply, {
          'done': true,
          'protocolError': {'code': -32602},
        }, reason: name);
      }
      expect(s.repository.provider.lastOpened!.commits, commits);
      expect(s.io.attempts, isEmpty);
      expect(s.services.router.chargedOperations, 0);
    },
  );

  test(
    'allowlist denial precedes missing-target lookup and any SSH/write',
    () async {
      final s = await Setup.create(), client = await s.client(await s.grant());
      for (final name in [
        'server_get',
        'server_connect',
        'server_disconnect',
        'state_get',
        'configuration_get',
        'logs_read',
        'recipes_list',
        'plan_create',
        'jobs_list',
      ]) {
        final args = <String, Object?>{
          'serverId': repository.id(3000),
          if (name == 'configuration_get') 'resourceId': 'system.motd',
          if (name == 'plan_create') ...{
            'requestId': repository.id(3001),
            'profileId': repository.id(3002),
            'revision': 1,
            'parameters': <String, Object?>{},
          },
        };
        await expectLater(
          s.tool(client, name, args),
          repository.failure('FORBIDDEN'),
          reason: name,
        );
      }
      expect(s.io.attempts, isEmpty);
      expect(s.repository.provider.lastOpened!.commits, 1);
    },
  );

  test('MCP session cannot be used as private owner invocation', () async {
    final s = await Setup.create(), client = await s.client(await s.grant());
    final request = await s.sessions.begin(
      client.channel,
      client.authenticated.sessionId,
      'mcp.invoke',
    );
    try {
      expect(
        () => s.services.prepare(request, 'grants.create', {
          'grantId': repository.id(3003),
          'label': 'forgery',
          'scopes': ['read'],
          'serverIds': [fixture.profile],
        }, requestId: repository.id(3004)),
        repository.failure('FORBIDDEN'),
      );
    } finally {
      request.complete();
      await request.settled;
    }
    expect(s.repository.provider.lastOpened!.commits, 1);
    expect(s.io.attempts, isEmpty);
  });

  test('actual grant revocation retires existing authenticated client before effects', () async {
    final s = await Setup.create(),
        grant = await s.grant(),
        client = await s.client(grant);
    await s.store.mutateOwnerGrant(
      OwnerGrantCommand.parse('grant.revoke', {
        'requestId': repository.id(3005),
        'grantId': grant,
        'expectedRevision': 1,
      }),
      clock: utcNow,
    );
    final before = repository.rawRows(s.store);
    await expectLater(
      s.tool(client, 'profiles_create', {
        'requestId': repository.id(3006),
        'name': 'not admitted',
        'body': <String, Object?>{},
      }),
      repository.failure('UNAUTHORIZED'),
    );
    expect(repository.rawRows(s.store), before);
    expect(s.io.attempts, isEmpty);
  });

  test(
    'expired retained grant cannot open even with its valid protected-key MAC',
    () async {
      final s = await Setup.create();
      final grant = await s.grant(
        clock: () => utcNow().subtract(const Duration(hours: 2)),
      );
      expect(
        s.store.snapshot.automation.grants[grant]!.expiresAt.isBefore(utcNow()),
        isTrue,
      );
      await expectLater(s.client(grant), repository.failure('UNAUTHORIZED'));
      await s.services.authority.closeAndDrain();
      expect(s.services.authority.pendingOpens, 0);
      expect(s.io.attempts, isEmpty);
    },
  );
}
