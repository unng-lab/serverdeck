import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:serverdeck_engine/storage/state_store.dart';
import 'package:serverdeck_engine/storage/workspace_rows.dart';
import 'package:serverdeck_engine/storage/workspace_storage.dart';
import 'package:test/test.dart';

import '../mcp/actual_router_authority_test.dart' as authority;
import '../mcp/actual_router_executor_test.dart' as positive;
import '../support/actual_mcp_setup.dart';
import '../support/executor_byte_peer.dart';
import '../support/direct_host_byte_peer.dart';
import '../support/schema3_fixture.dart' as fixture;
import '../automation/portable_program_test.dart' show motdBody;
import '../support/memory_workspace_provider.dart';
import 'actual_state_store_test.dart' as actual;

/// All domain rows come from actual services/writers. Only platform protection,
/// storage bytes and the framed remote peer are declared RAM dependencies.
final class Populated {
  Populated(this.old, this.peer, this.direct, this.client, this.plan, this.job);
  final Setup old;
  final ExecutorBytePeer peer;
  final DirectHostBytePeer direct;
  final Client client;
  final Map<String, Object?> plan;
  final String job;

  static Future<Populated> create() async {
    final direct = DirectHostBytePeer();
    // Retain a genuine legacy enrollment as historical protected data, while
    // every new plan/job uses the production direct SSH path independently.
    final (s, peer) = await positive.enrolled(direct: direct.attach);
    final client = await s.client(await s.grant(lifetimeSeconds: 3600));
    success(
      await s.tool(client, 'server_connect', {'serverId': fixture.profile}),
    );
    final profile =
        success(
              await s.tool(client, 'profiles_create', {
                'requestId': actual.id(3400),
                'name': 'direct retention profile',
                'body': motdBody(),
              }),
            )['profileId']
            as String;
    final plan = await positive.plan(s, client, profile, 3650);
    await positive.approve(s, client, plan, 3651);
    final applied = success(
      await s.tool(client, 'apply', {
        'requestId': actual.id(3652),
        'planId': plan['planId'],
      }),
    );
    final job = applied['jobId'] as String;
    await positive.waitJob(s, client, job, 'succeeded');
    // Create this after apply so the one-time approval really was consumed.
    await s.ownerCall(
      'delegations.create',
      authority.delegation(s, client, profile),
    );
    expect(s.store.snapshot.rows, hasLength(16));
    for (final family in WorkspaceCollection.values) {
      expect(
        s.store.snapshot.rows[family.persistedName],
        isNotEmpty,
        reason: 'T325 requires nonempty ${family.persistedName}',
      );
    }
    expect(
      s.store.snapshot.automation.approvals.values.single.state,
      'consumed',
    );
    expect((peer.permits, peer.effects), (0, 0));
    expect((direct.launches, direct.effects), (1, 1));
    expect(peer.errors, isEmpty);
    return Populated(s, peer, direct, client, plan, job);
  }

  Map<String, List<int>> files() => {
    for (final entry in old.repository.source.files.data.entries)
      entry.key: List<int>.of(entry.value),
  };
}

void main() {
  tearDown(() => expect(StateStore.hasOpenReservation, isFalse));

  test('all16 nonempty schema3 families and protected files reopen byte-exact without authority restoration', () async {
    final source = await Populated.create(),
        old = source.old,
        peer = source.peer;
    final rows = actual.rawRows(old.store);
    final foundation = old.store.state.toJson();
    final enrollment = await old.store.readExecutorEnrollments();
    final originalJob = old.store.snapshot.automation.jobs[source.job]!
        .toJson();
    await old.close();
    final files = source.files(), calls = peer.requests.length;
    final s = await Setup.reopen(
      old.repository,
      generation: actual.id(3800),
      executorRelease: peer.release,
      executor: peer.attach,
      direct: source.direct.attach,
    );
    expect(s.repository.provider.opens, 2);
    expect(actual.rawRows(s.store), rows);
    expect(s.store.state.toJson(), foundation);
    expect(s.store.snapshot.automation.jobs[source.job]!.toJson(), originalJob);
    expect(
      (await s.store.readExecutorEnrollments()).map(
        (k, v) => MapEntry(k, v.toJson()),
      ),
      enrollment.map((k, v) => MapEntry(k, v.toJson())),
    );
    expect(
      source.files(),
      files,
      reason: 'all RAM files include credentials, signed enrollment, key wrapper, manifest and history',
    );
    expect(s.sessions.generation, isNot(old.sessions.generation));
    expect(s.io.attempts, isEmpty);
    expect(peer.requests.length, calls);
    await expectLater(
      s.tool(source.client, 'jobs_get', {'jobId': source.job}),
      throwsStateError,
    );
    final client = await s.client(source.client.grantId);
    final view = success(
      await s.tool(client, 'jobs_get', {'jobId': source.job}),
    );
    expect((view['observation'] as Map)['state'], 'detached');
    expect((view['observation'] as Map)['generation'], s.sessions.generation);
    final replay = success(
      await s.tool(client, 'apply', {
        'requestId': actual.id(3652),
        'planId': source.plan['planId'],
      }),
    );
    expect(replay['jobId'], source.job);
    expect(actual.rawRows(s.store), rows);
    expect(source.files(), files);
    expect(peer.requests.length, calls);
    expect((peer.permits, peer.effects), (0, 0));
    expect((source.direct.launches, source.direct.effects), (1, 1));
    expect(s.io.attempts, isEmpty);
    expect(peer.errors, isEmpty);
    await s.close();
    expect(source.files(), files);
    expect(old.repository.source.lease.closes, 0);
  });

  for (final family in WorkspaceCollection.values) {
    test(
      'populated ${family.persistedName} invalid native ID refuses before writer and preserves every file',
      () async {
        final source = await Populated.create(), repo = source.old.repository;
        await source.old.close();
        final rows = {
          ...MemoryWorkspaceProvider.decode(repo.provider.readBytes()),
        };
        final previous = rows[family.persistedName]!;
        rows[family.persistedName] = [
          StoredRow(
            0,
            previous.first.payload,
            entityId: previous.first.entityId,
          ),
          ...previous.skip(1),
        ];
        repo.provider.persistBytes(MemoryWorkspaceProvider.encode(rows));
        final before = source.files(), calls = source.peer.requests.length;
        await expectLater(repo.open(), actual.failure('STORAGE_BLOCKED'));
        expect(repo.provider.opens, 1);
        expect(repo.provider.hasOpenInstance, isFalse);
        expect(source.files(), before);
        expect(source.peer.requests.length, calls);
        expect(repo.source.lease.closes, 0);
      },
    );
  }

  for (final fault in [
    'schema1',
    'schema2',
    'schema99',
    'credential',
    'key-wrapper',
  ]) {
    test(
      'full graph $fault refusal leaves incompatible input untouched',
      () async {
        final source = await Populated.create(), repo = source.old.repository;
        await source.old.close();
        if (fault == 'key-wrapper') {
          repo.source.files.data[p.join(
            repo.source.source.directory,
            'receipt-key.dpapi',
          )] = [
            255,
          ];
        } else {
          final rows = {
            ...MemoryWorkspaceProvider.decode(repo.provider.readBytes()),
          };
          final schema = fault.startsWith('schema');
          final family = schema ? 'StoredWorkspace' : 'StoredProfile';
          final previous = rows[family]!.single;
          final payload = jsonDecode(previous.payload) as Map<String, Object?>;
          payload[schema ? 'schemaVersion' : 'credentialRef'] = schema
              ? int.parse(fault.substring(6))
              : actual.id(999);
          rows[family] = [
            StoredRow(
              previous.nativeId,
              jsonEncode(payload),
              entityId: previous.entityId,
            ),
          ];
          repo.provider.persistBytes(MemoryWorkspaceProvider.encode(rows));
        }
        final before = source.files();
        await expectLater(
          repo.open(),
          actual.failure(
            fault.startsWith('schema') ? 'INCOMPATIBLE' : 'STORAGE_BLOCKED',
          ),
        );
        expect(repo.provider.opens, 1);
        expect(repo.provider.hasOpenInstance, isFalse);
        expect(source.files(), before);
        expect(repo.source.lease.closes, 0);
      },
    );
  }
}
