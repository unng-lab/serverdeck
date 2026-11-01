import 'dart:async';
import 'dart:convert';

import 'package:serverdeck_engine/remote/reads.dart';
import 'package:serverdeck_engine/remote/ssh_transport.dart';
import 'package:serverdeck_engine/storage/workspace_rows.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/connections.dart';
import 'package:test/test.dart';

import '../support/remote_read_setup.dart';
import '../support/schema3_fixture.dart' as fixture;
import 'read_isolation_bounds_test.dart' show read, state;
import 'shared_reads_test.dart' show failure, payload;
import 'ssh_pool_lifecycle_test.dart' show settle;

Future<Map<String, Object?>> terminal(
  Setup s,
  Mcp client,
  Map<String, Object?> input,
) async {
  final first = await s.invoke(client, input);
  if (first['done'] == true) return first;
  await settle();
  return s.invoke(client, {
    'poll': {'operationId': first['operationId']},
  });
}

void main() {
  test('owner recipes and refreshed configuration report real missing enrollment without SSH', () async {
    final s = await Setup.create();
    for (final kind in ['recipes', 'configuration']) {
      final id = kind == 'recipes' ? fixture.request1 : fixture.request2;
      await s.ownerCall('servers.$kind', {
        'profileId': fixture.profile,
        if (kind == 'configuration') 'resourceId': 'system.motd',
        if (kind == 'configuration') 'refresh': true,
      }, id: id);
      await settle();
      final status = await s.ownerCall('servers.readStatus', {
        'operationId': id,
      });
      expect(status['state'], 'failed');
      expect(status['code'], 'EXECUTOR_UNAVAILABLE');
    }
    expect(s.store.enrollmentReads, 2);
    expect(s.store.metadataBlocked, isFalse);
    expect(s.io.attempts.single.client.commands, isEmpty);
  });

  for (final recipes in [false, true]) {
    test(
      'actual MCP ${recipes ? 'plan recipes' : 'read configuration'} returns typed missing executor before opening a channel',
      () async {
        final s = await Setup.create(
          scopes: recipes ? ['read', 'plan'] : ['read'],
        );
        final client = await s.mcp();
        await s.attach(client);
        final result = await terminal(s, client, {
          'request': {
            'name': recipes
                ? 'serverdeck_recipes_list'
                : 'serverdeck_configuration_get',
            'arguments': {
              'serverId': fixture.profile,
              if (!recipes) 'resourceId': 'system.motd',
              if (!recipes) 'refresh': true,
            },
          },
        });
        expect(result['done'], isTrue);
        expect(payload(result)['ok'], isFalse);
        expect(
          (payload(result)['error'] as Map)['code'],
          'EXECUTOR_UNAVAILABLE',
        );
        expect(s.store.enrollmentReads, 1);
        expect(s.io.attempts.single.client.commands, isEmpty);
      },
    );
  }

  test('cached configuration stays unknown and unmanaged across a failed refresh and independent state sample', () async {
    final s = await Setup.create();
    final input = {'serverId': fixture.profile, 'resourceId': 'system.motd'};
    final cold = await read(s, 'serverdeck_configuration_get', input);
    expect((cold['observation'] as Map)['status'], 'unknown');
    expect((cold['observation'] as Map)['value'], isNull);
    expect(cold['desired'], isNull);
    expect(cold['expected'], isNull);
    expect((cold['comparison'] as Map)['status'], 'unmanaged');
    expect(s.store.enrollmentReads, 0);
    final sampled = await state(s, refresh: true);
    expect((sampled['system'] as Map)['quality'], 'known');
    await expectLater(
      read(s, 'serverdeck_configuration_get', {...input, 'refresh': true}),
      failure('EXECUTOR_UNAVAILABLE'),
    );
    final after = await read(s, 'serverdeck_configuration_get', input);
    expect(after, cold);
    expect(s.store.enrollmentReads, 1);
    expect(s.io.attempts.single.client.commands, hasLength(4));
    expect((await state(s))['system'], sampled['system']);
  });

  test(
    'cancelled executor read retains physical metadata work until it settles',
    () async {
      final s = await Setup.create();
      s.store.enrollmentRead = Completer<void>();
      final work = s.reads.startOwner(
        await s.ownerContext(),
        'serverdeck_recipes_list',
        {'serverId': fixture.profile},
      );
      await settle();
      expect(s.store.enrollmentReads, 1);
      final stopped = expectLater(work.result, failure('CANCELLED'));
      var drained = false;
      final cancel = work.cancelInterest().then((_) => drained = true);
      await stopped;
      await settle();
      expect(drained, isFalse);
      final closing = s.reads.close();
      await settle();
      expect(drained, isFalse);
      expect(s.io.attempts.single.client.commands, isEmpty);
      s.store.enrollmentRead!.complete();
      await cancel;
      await closing;
      expect(drained, isTrue);
      expect(s.store.enrollmentReads, 1);
      expect(s.io.attempts.single.client.commands, isEmpty);
      expect(s.pool.activeTransports, 1);
    },
  );
  test('last waiter cancellation keeps its stopped sampler charged through suspend and physical drain', () async {
    final s = await Setup.create();
    s.holdSystem = true;
    final RemoteReadWork work = s.reads.startOwner(
      await s.ownerContext(),
      'serverdeck_state_get',
      {'serverId': fixture.profile, 'refresh': true},
    );
    final stopped = expectLater(work.result, failure('CANCELLED'));
    await settle();
    final old = s.held.single;
    await work.cancelInterest();
    await stopped;
    expect(old.finishing, isFalse);
    final replacement = s.reads.startOwner(
      await s.ownerContext(),
      'serverdeck_state_get',
      {'serverId': fixture.profile, 'refresh': true},
    );
    await expectLater(replacement.result, failure('RESOURCE_LIMIT'));
    await replacement.done;
    expect(s.io.attempts.single.client.commands, hasLength(1));
    final context = await s.ownerContext();
    var paused = false;
    final pause = s.reads.suspend().then((_) => paused = true);
    await settle();
    expect(paused, isFalse);
    expect(
      () => s.reads.startOwner(context, 'serverdeck_state_get', {
        'serverId': fixture.profile,
      }),
      failure('SERVICE_UNAVAILABLE'),
    );
    s.holdSystem = false;
    s.respond(old, SshReadSource.system);
    await pause;
    expect(paused, isTrue);
    s.reads.resume();
    final cold = await state(s);
    expect((cold['system'] as Map)['quality'], 'unknown');
    final fresh = await state(s, refresh: true);
    expect((fresh['system'] as Map)['quality'], 'known');
    expect(s.io.attempts.single.client.commands, hasLength(5));
    expect(s.io.attempts, hasLength(1));
    expect(s.pool.activeTransports, 1);
  });
  test('typed owner cancel is principal-bound, stable and suppresses the late result', () async {
    final s = await Setup.create(), other = await s.newOwner();
    s.holdSystem = true;
    final input = {'profileId': fixture.profile, 'refresh': true};
    await s.ownerCall('servers.state', input);
    await settle();
    final old = s.held.single;
    expect(
      (await s.ownerCall('servers.readCancel', {
        'operationId': fixture.request1,
      }, asOwner: other))['cancelled'],
      isFalse,
    );
    expect(
      (await s.ownerCall('servers.readStatus', {
        'operationId': fixture.request1,
      }))['state'],
      'running',
    );
    expect(
      (await s.ownerCall('servers.readCancel', {
        'operationId': fixture.request1,
      }))['cancelled'],
      isTrue,
    );
    expect(
      (await s.ownerCall('servers.readCancel', {
        'operationId': fixture.request1,
      }))['cancelled'],
      isFalse,
    );
    await s.ownerCall('servers.state', input);
    expect(s.io.attempts.single.client.commands, hasLength(1));
    s.holdSystem = false;
    s.respond(old, SshReadSource.system);
    await settle();
    final status = await s.ownerCall('servers.readStatus', {
      'operationId': fixture.request1,
    });
    expect(status['state'], 'failed');
    expect(status['code'], 'CANCELLED');
    await s.ownerCall('servers.state', input, id: fixture.request2);
    await settle();
    expect(
      (await s.ownerCall('servers.readStatus', {
        'operationId': fixture.request2,
      }))['state'],
      'succeeded',
    );
    expect(s.io.attempts.single.client.commands, hasLength(5));
  });

  test('read and plan contexts cannot acquire apply authority or invoke any writer', () async {
    for (final scopes in [
      <String>['read'],
      <String>['read', 'plan'],
    ]) {
      final s = await Setup.create(scopes: scopes), client = await s.mcp();
      await expectLater(
        s.invoke(client, {
          'request': {
            'name': 'serverdeck_apply',
            'arguments': {
              'requestId': fixture.request2,
              'planId': fixture.grantRequest,
            },
          },
        }),
        failure('FORBIDDEN'),
      );
      expect(s.store.enrollmentReads, 0);
      expect(s.io.attempts.single.client.commands, isEmpty);
    }
  });

  test('session detach retires its collector interest without revoking the remaining owner', () async {
    final s = await Setup.create(), client = await s.mcp();
    await s.attach(client);
    s.holdSystem = true;
    final pending = await s.invoke(client, {
      'request': {
        'name': 'serverdeck_state_get',
        'arguments': {'serverId': fixture.profile, 'refresh': true},
      },
    });
    await s.ownerCall('servers.state', {
      'profileId': fixture.profile,
      'refresh': true,
    });
    await settle();
    final old = s.held.single;
    s.holdSystem = false;
    s.sessions.disconnect(client.channel);
    await settle();
    expect(s.store.grants.current.revision, 1);
    expect(s.store.grants.current.revokedAt, isNull);
    await expectLater(
      s.invoke(client, {
        'poll': {'operationId': pending['operationId']},
      }),
      failure('UNAUTHORIZED'),
    );
    expect(
      (await s.ownerCall('servers.readStatus', {
        'operationId': fixture.request1,
      }))['state'],
      'succeeded',
    );
    expect(old.finishing, isFalse);
    expect(s.io.attempts.single.client.commands, hasLength(5));
    await old.finish();
    expect(s.pool.activeTransports, 1);
  });
  test('grant revision alone retires an authenticated context while key and permission stay current', () async {
    final s = await Setup.create(), client = await s.mcp();
    final original = s.store.grants.current;
    s.store.grants.current = ClientGrantRecord.fromJson({
      ...original.toJson(),
      'revision': 2,
    });
    expect(s.store.grants.current.revokedAt, isNull);
    expect(
      s.store.grants.current.isCurrentAt(DateTime.parse(fixture.second)),
      isTrue,
    );
    expect(s.store.grants.current.secretRef, original.secretRef);
    expect(s.store.grants.current.policy.allowsScope(McpScope.read), isTrue);
    expect(s.store.grants.current.policy.allowsServer(fixture.profile), isTrue);
    expect(
      () => client.context.authorize(
        scope: McpScope.read,
        serverId: fixture.profile,
      ),
      failure('UNAUTHORIZED'),
    );
    await expectLater(
      s.invoke(client, {'catalog': <String, Object?>{}}),
      failure('UNAUTHORIZED'),
    );
    expect(s.io.attempts.single.client.commands, isEmpty);
  });

  for (final credential in [false, true]) {
    test(
      'current connection identity rejects isolated ${credential ? 'credential' : 'trust'} revision change',
      () async {
        final s = await Setup.create(), context = await s.ownerContext();
        final captured = ConnectionIdentity.fromJson(
          Map<String, Object?>.from(
            s.connections.snapshot(
                  fixture.profile,
                  context.connectionInterest,
                )['identity']
                as Map,
          ),
        );
        final lease = await s.sessions.beginReconciledTargetChange();
        addTearDown(lease.close);
        final before = s.store.snapshot.foundation, source = s.data.source;
        const rotated = '63456789-1234-4234-9234-123456789abc';
        try {
          final old = source.data['StoredProfile']!.single;
          source.data['StoredProfile'] = [
            StoredRow(
              old.nativeId,
              jsonEncode({
                ...jsonDecode(old.payload) as Map<String, dynamic>,
                'revision': '3',
                if (credential) 'credentialRef': rotated,
                if (credential)
                  'credentialRevision': '2'
                else
                  'trustRevision': '3',
                'updatedAt': '2026-10-30T10:00:02.000Z',
              }),
              entityId: fixture.profile,
            ),
          ];
          if (credential) {
            final old = source.data['StoredCredential']!.single;
            source.data['StoredCredential'] = [
              StoredRow(
                old.nativeId + 1,
                jsonEncode({
                  ...jsonDecode(old.payload) as Map<String, dynamic>,
                  'id': rotated,
                  'revision': '2',
                  'protectedBlob': await s.data.custody.wrapCredential(
                    fixture.workspace,
                    fixture.profile,
                    rotated,
                    {
                      'action': 'replace',
                      'kind': 'password',
                      'password': 'unit-only-rotated',
                    },
                  ),
                  'createdAt': '2026-10-30T10:00:02.000Z',
                  'updatedAt': '2026-10-30T10:00:02.000Z',
                }),
                entityId: rotated,
              ),
            ];
          } else {
            final old = source.data['StoredHostTrust']!.single;
            source.data['StoredHostTrust'] = [
              StoredRow(
                old.nativeId,
                jsonEncode({
                  ...jsonDecode(old.payload) as Map<String, dynamic>,
                  'revision': '3',
                  'updatedAt': '2026-10-30T10:00:02.000Z',
                }),
                entityId: fixture.profile,
              ),
            ];
          }
          final workspace = source.data['StoredWorkspace']!.single;
          source.data['StoredWorkspace'] = [
            StoredRow(
              workspace.nativeId,
              jsonEncode({
                ...jsonDecode(workspace.payload) as Map<String, dynamic>,
                'storeRevision': '3',
              }),
            ),
          ];
          source.data['StoredReceipt']!.add(
            StoredRow(
              103,
              jsonEncode({
                ...fixture.receipt(
                  fixture.grantRequest,
                  credential ? 'profiles.update' : 'servers.trust.confirm',
                  '3',
                ),
                'committedAt': '2026-10-30T10:00:02.000Z',
              }),
              entityId: fixture.grantRequest,
            ),
          );
          s.store.value = await s.data.load();
          final current = s.store.snapshot.foundation;
          expect(
            current.foundation.profiles[fixture.profile]!.connectionRevision,
            captured.connectionRevision,
          );
          expect(current.trust[fixture.profile]!.key, captured.key);
          if (credential)
            expect(
              current.foundation.profiles[fixture.profile]!.trustRevision,
              captured.trustRevision,
            );
          else
            expect(
              current.foundation.profiles[fixture.profile]!.credentialRevision,
              captured.credentialRevision,
            );
          expect(
            () => s.connections.requireCurrentIdentity(captured),
            failure('TRUST_CHANGED'),
          );
          expect(s.io.attempts.single.client.commands, isEmpty);
        } finally {
          await s.connections.reconcile(before, lease);
          await lease.close();
        }
      },
    );
  }
}
