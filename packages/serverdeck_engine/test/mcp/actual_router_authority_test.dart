import 'package:serverdeck_engine/automation/authority_commands.dart';
import 'package:serverdeck_engine/storage/state_store.dart';
import 'package:test/test.dart';

import '../automation/portable_program_test.dart' show motdBody;
import '../storage/actual_state_store_test.dart' as repository;
import '../support/actual_mcp_setup.dart';
import '../support/direct_host_byte_peer.dart';
import '../support/actual_direct_setup.dart';
import '../support/schema3_fixture.dart' as fixture;
import 'actual_router_executor_test.dart' as positive;
import 'actual_router_fences_test.dart' show toolError;

Future<(Setup, DirectHostBytePeer, Client, String)> ready() =>
    directReady(profileRequest: 3400, lifetimeSeconds: 3600);

Map<String, Object?> delegation(
  Setup s,
  Client client,
  String profile, {
  String allowed = 'executor unit',
}) => {
  'requestId': repository.id(3402),
  'grantId': client.grantId,
  'serverIds': [fixture.profile],
  'profileRevisions': [
    s.store.snapshot.automation.revisions['$profile:1']!.key.toJson(),
  ],
  'predicates': {
    'message': {
      'type': 'enum',
      'values': [allowed],
    },
  },
  'lifetimeSeconds': 300,
};

Future<void> deniedApply(
  Setup s,
  DirectHostBytePeer peer,
  Client client,
  Map<String, Object?> plan,
  int request,
) async {
  final commits = s.repository.provider.lastOpened!.commits;
  toolError(
    await s.tool(client, 'apply', {
      'requestId': repository.id(request),
      'planId': plan['planId'],
    }),
    'APPROVAL_REQUIRED',
  );
  expect(s.repository.provider.lastOpened!.commits, commits);
  expect(s.store.snapshot.automation.jobs, isEmpty);
  expect(
    s.store.snapshot.automation.receipts.containsKey(repository.id(request)),
    isFalse,
  );
  expect(peer.requests.where((command) => command.kind == 'reserve'), isEmpty);
  expect(peer.records, isEmpty);
  noDirectEffect(peer);
  expect(s.store.isReady, isTrue);
}

void main() {
  test('actual author-only HMAC in empty workspace runs all7profile tools without server scope', () async {
    final s = await Setup.create(populated: false);
    expect(s.store.state.profiles, isEmpty);
    expect(s.store.state.credentials, isEmpty);
    final client = await s.client(
      await s.grant(scopes: ['author'], targets: []),
    );
    final validated = success(
      await s.tool(client, 'profiles_validate', {'body': motdBody()}),
    );
    expect(validated['valid'], isTrue);
    final created = success(
      await s.tool(client, 'profiles_create', {
        'requestId': repository.id(3400),
        'name': 'empty workspace author',
        'body': motdBody(),
      }),
    );
    final id = created['profileId'] as String;
    final fetched = success(
      await s.tool(client, 'profiles_get', {'profileId': id}),
    );
    expect((fetched['revision'] as Map)['digest'], validated['digest']);
    final changed = motdBody();
    (changed['parameters'] as Map)['message'] = {
      'type': 'string',
      'maxLength': 64,
      'default': 'changed',
    };
    final updated = success(
      await s.tool(client, 'profiles_update', {
        'requestId': repository.id(3401),
        'profileId': id,
        'expectedRevision': 1,
        'body': changed,
      }),
    );
    expect(updated['revision'], 2);
    expect(
      success(
        await s.tool(client, 'profiles_compare', {
          'profileId': id,
          'fromRevision': 1,
          'toRevision': 2,
        }),
      )['changes'],
      isNotEmpty,
    );
    expect(
      (success(await s.tool(client, 'profiles_list', {}))['items'] as List).map(
        (r) => (r as Map)['id'],
      ),
      [id],
    );
    expect(
      success(
        await s.tool(client, 'profiles_archive', {
          'requestId': repository.id(3402),
          'profileId': id,
          'expectedRevision': 2,
        }),
      )['archived'],
      isTrue,
    );
    expect(s.store.snapshot.automation.revisions, hasLength(2));
    expect(s.store.snapshot.automation.profiles[id]!.archived, isTrue);
    expect(
      s.store.snapshot.automation.receipts[repository.id(3400)]!.originGrantId,
      client.grantId,
    );
    await expectLater(
      s.tool(client, 'servers_list', {}),
      repository.failure('FORBIDDEN'),
    );
    await expectLater(
      s.tool(client, 'apply', {
        'requestId': repository.id(3403),
        'planId': repository.id(3404),
      }),
      repository.failure('FORBIDDEN'),
    );
    expect(s.successful, {
      'profiles_validate',
      'profiles_create',
      'profiles_get',
      'profiles_update',
      'profiles_compare',
      'profiles_list',
      'profiles_archive',
    });
    expect(s.store.state.profiles, isEmpty);
    expect(s.store.state.credentials, isEmpty);
    expect(s.io.attempts, isEmpty);
  });

  test('actual runnable apply requires authority both absent and pending owner approval', () async {
    final (s, peer, client, profile) = await ready();
    final plan = await positive.plan(s, client, profile, 3401);
    expect(
      s.store.snapshot.automation.plans[plan['planId']]!.status,
      'runnable',
    );
    await deniedApply(s, peer, client, plan, 3404);
    final asked = success(
      await s.tool(client, 'approval_request', {
        'requestId': repository.id(3405),
        'planId': plan['planId'],
      }),
    );
    expect(
      s.store.snapshot.automation.approvals[asked['approvalId']]!.state,
      'pending',
    );
    await deniedApply(s, peer, client, plan, 3406);
  });

  test('actual matching owner delegation applies without approval and retains exact authorityRef', () async {
    final (s, peer, client, profile) = await ready();
    final granted = await s.ownerCall(
      'delegations.create',
      delegation(s, client, profile),
    );
    final plan = await positive.plan(s, client, profile, 3401);
    final admitted = success(
      await s.tool(client, 'apply', {
        'requestId': repository.id(3404),
        'planId': plan['planId'],
      }),
    );
    final expected = {
      'kind': 'delegation',
      'id': granted['delegationId'],
      'revision': 1,
    };
    expect(admitted['authorityRef'], expected);
    await positive.waitJob(s, client, admitted['jobId'] as String, 'succeeded');
    final job = s.store.snapshot.automation.jobs[admitted['jobId']]!;
    expect(job.toJson()['authorityRef'], expected);
    expect(s.store.snapshot.automation.approvals, isEmpty);
    expect(peer.launches, 1);
    expect(peer.effects, 1);
    expect(peer.reads.files['system.motd'], 'executor unit\n');
    expect(
      peer.requests.where((command) => command.kind == 'reserve'),
      hasLength(1),
    );
  });

  for (final fault in ['revision', 'body', 'parameters', 'revoked']) {
    test('actual $fault delegation cannot admit runnable apply', () async {
      final (s, peer, client, profile) = await ready();
      final input = delegation(
        s,
        client,
        profile,
        allowed: fault == 'parameters' ? 'another value' : 'executor unit',
      );
      if (fault == 'body') {
        ((input['profileRevisions'] as List).single as Map)['bodyDigest'] =
            '0' * 64;
        await expectLater(
          s.ownerCall('delegations.create', input),
          repository.failure('REVISION_CONFLICT'),
        );
        expect(s.store.snapshot.automation.delegations, isEmpty);
      } else {
        final granted = await s.ownerCall('delegations.create', input);
        if (fault == 'revoked') {
          await s.ownerCall('delegations.revoke', {
            'requestId': repository.id(3403),
            'delegationId': granted['delegationId'],
            'expectedRevision': 1,
          });
          expect(
            s
                .store
                .snapshot
                .automation
                .delegations[granted['delegationId']]!
                .revokedAt,
            isNotNull,
          );
        }
      }
      if (fault == 'revision') {
        success(
          await s.tool(client, 'profiles_update', {
            'requestId': repository.id(3403),
            'profileId': profile,
            'expectedRevision': 1,
            'body': motdBody(),
          }),
        );
      }
      final plan = await positive.plan(
        s,
        client,
        profile,
        3401,
        revision: fault == 'revision' ? 2 : 1,
      );
      expect(
        s.store.snapshot.automation.plans[plan['planId']]!.status,
        'runnable',
      );
      await deniedApply(s, peer, client, plan, 3404);
    });
  }

  test('actual expired retained delegation cannot admit while its HMAC grant stays current', () async {
    final peer = DirectHostBytePeer();
    final s = await Setup.create(direct: peer.attach);
    final past = utcNow().subtract(const Duration(minutes: 10));
    final grant = await s.grant(clock: () => past, lifetimeSeconds: 3600);
    final profile =
        (await s.store.mutateAutomationProfile(
              repository.createProfile(3400),
              originGrantId: null,
              expectedGrantRevision: null,
              clock: () => past,
            ))['profileId']
            as String;
    final key = s.store.snapshot.automation.revisions['$profile:1']!.key
        .toJson();
    // Historical owner metadata is seeded through unchanged validated trusted
    // RAM writes. Current apply/auth/factory/driver are not replaced or clocked.
    final granted = await s.store.mutateTrustedAuthority(
      AutomationAuthorityCommand.parse('delegation.create', {
        'requestId': repository.id(3402),
        'grantId': grant,
        'serverIds': [fixture.profile],
        'profileRevisions': [key],
        'predicates': {
          'message': {
            'type': 'enum',
            'values': ['executor unit'],
          },
        },
        'lifetimeSeconds': 300,
      }),
      originGrantId: null,
      expectedGrantRevision: null,
      clock: () => past.add(const Duration(seconds: 1)),
    );
    expect(
      s
          .store
          .snapshot
          .automation
          .delegations[granted['delegationId']]!
          .expiresAt
          .isBefore(utcNow()),
      isTrue,
    );
    final client = await s.client(grant);
    success(
      await s.tool(client, 'server_connect', {'serverId': fixture.profile}),
    );
    final plan = await positive.plan(s, client, profile, 3401);
    expect(
      s.store.snapshot.automation.plans[plan['planId']]!.status,
      'runnable',
    );
    await deniedApply(s, peer, client, plan, 3404);
  });
}
