import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck_engine/api/owner_api.dart';
import 'package:serverdeck_engine/api/trusted_owner_foundation.dart';
import 'package:serverdeck_engine/hosting/in_process_gateway.dart';
import 'package:serverdeck_engine/remote/ssh_transport.dart';
import 'package:serverdeck_engine/profiles/mutation_coordinator.dart';
import 'package:serverdeck_engine/storage/workspace_rows.dart';
import 'package:serverdeck_engine/storage/workspace_snapshot.dart';
import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/models.dart';

import '../lib/bootstrap/engine_client.dart';
import '../packages/serverdeck_engine/test/support/remote_read_setup.dart'
    as domain;
import '../packages/serverdeck_engine/test/support/schema3_fixture.dart'
    as fixture;
import '../packages/serverdeck_engine/test/remote/ssh_pool_lifecycle_test.dart'
    show settle;

final class Tick {
  Tick(this.delay, this.due, this.action);
  final Duration delay, due;
  final void Function() action;
  bool active = true;
}

final class Scheduler {
  Duration now = Duration.zero;
  final tasks = <Tick>[];
  CancelDeadline schedule(Duration delay, void Function() action) {
    final tick = Tick(delay, now + delay, action);
    tasks.add(tick);
    return () => tick.active = false;
  }

  Tick get poll => tasks.singleWhere(
    (t) => t.active && t.delay == const Duration(seconds: 2),
  );
  Future<void> firePoll(domain.Setup data) async {
    final tick = poll;
    tick.active = false;
    now = tick.due;
    data.clock.elapsed = now;
    tick.action();
    await settle();
  }
}

/// Records actual dispatch and can delay already captured real replies. Never
/// supplies a successful DTO, owner role, native proof or alternative dispatcher.
final class TraceGateway implements EngineGateway {
  TraceGateway(this.actual);
  final InProcessGateway actual;
  final calls = <({String method, String id})>[];
  FutureOr<void> Function(String, Map<String, Object?>)? afterReply;
  final blockers = <Completer<void>>[];
  bool ambiguousMutation = false;
  @override
  String get generation => actual.generation;
  @override
  bool get isClosed => actual.isClosed;
  @override
  Future<void> get retired => actual.retired;
  @override
  Future<Map<String, Object?>> call(
    String method,
    Map<String, Object?> params, {
    required String requestId,
  }) async {
    calls.add((method: method, id: requestId));
    // Declared controller-boundary failure: no writer is admitted in this RAM
    // read composition and no simulated committed result is manufactured.
    if (ambiguousMutation && method == 'settings.update')
      throw EngineCallFailure('TIMEOUT');
    final result = await actual.call(method, params, requestId: requestId);
    await afterReply?.call(method, result);
    return result;
  }

  int count(String method) => calls.where((c) => c.method == method).length;
  @override
  Future<void> close() => actual.close();
}

final class Setup {
  Setup(this.data, this.foundation, this.trace);
  final domain.Setup data;
  final TrustedFoundationOwnerApi foundation;
  final TraceGateway trace;
  final schedule = Scheduler();
  final snapshots = <ClientSnapshot>[], errors = <ErrorCode>[];
  late EngineApiClient client;
  late StreamSubscription<ClientSnapshot> seen;
  late StreamSubscription<ErrorCode> failed;
  late TraceGateway next;
  TraceGateway? owned;
  int attachments = 0;
  static Future<Setup> create({
    String generation = '12345678-1234-4234-9234-123456789abc',
  }) async {
    final data = await domain.Setup.create(generation: generation);
    final coordinator = MutationCoordinator(
      data.store,
      data.data.custody,
      data.data.key,
    );
    final foundation = TrustedFoundationOwnerApi.withConnections(
      store: data.store,
      coordinator: coordinator,
      sessions: data.sessions,
      connections: data.connections,
    );
    final actual = InProcessGateway(
      owner: data.owner,
      services: TrustedOwnerApiGroup([foundation, data.ownerApi]),
      readiness: () => TrustedReadiness(
        state: ReadinessState.ready,
        generation: data.sessions.generation,
        workspaceId: fixture.workspace,
        features: const OperationalFeatures(profiles: true, ssh: true),
      ),
    );
    final s = Setup(data, foundation, TraceGateway(actual));
    s.next = s.trace;
    s.client = EngineApiClient(
      attach: () async {
        s.attachments++;
        return s.owned = s.next;
      },
      detach: () async {
        final actual = s.owned;
        s.owned = null;
        await actual?.close();
      },
      schedule: s.schedule.schedule,
    );
    s.seen = s.client.snapshots.listen(s.snapshots.add);
    s.failed = s.client.snapshotErrors.listen(s.errors.add);
    addTearDown(s.close);
    return s;
  }

  Future<void> close() async {
    for (final gateway in {trace, next}) {
      for (final blocker in gateway.blockers)
        if (!blocker.isCompleted) blocker.complete();
    }
    await client.close();
    await seen.cancel();
    await failed.cancel();
    await foundation.close();
  }

  Future<WorkspaceSnapshot> settingsRevision() async {
    final source = data.data.source;
    final old = source.data['StoredSettings']!.single;
    source.data['StoredSettings'] = [
      StoredRow(
        old.nativeId,
        jsonEncode({
          ...jsonDecode(old.payload) as Map<String, dynamic>,
          'revision': '2',
          'theme': 'light',
        }),
      ),
    ];
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
          'requestId': fixture.grantRequest,
          'inputDigest': fixture.digest,
          'operation': 'settings.update',
          'profileId': null,
          'result': {
            'entityId': null,
            'entityRevision': '2',
            'storeRevision': '3',
            'deleted': false,
          },
          'committedAt': '2026-10-30T10:00:02.000Z',
        }),
        entityId: fixture.grantRequest,
      ),
    );
    return data.data.load();
  }
}

void main() {
  test('actual owner snapshot polling uses2s and one coherent coordinator state without collector starts', () async {
    final s = await Setup.create();
    await s.client.connect();
    s.client.startPolling();
    await settle();
    expect(s.snapshots, hasLength(1));
    expect(s.snapshots.single.storeRevision, '2');
    expect(
      s.snapshots.single.profiles.result['storeRevision'],
      s.snapshots.single.settings.result['storeRevision'],
    );
    expect(s.snapshots.single.profiles.result['profiles'], hasLength(1));
    expect(
      (s.snapshots.single.settings.result['settings'] as Map)['theme'],
      'dark',
    );
    expect(
      s.schedule.tasks.where((t) => t.active).map((t) => t.delay),
      containsAll([const Duration(seconds: 2), const Duration(seconds: 20)]),
    );
    for (var i = 0; i < 3; i++) await s.schedule.firePoll(s.data);
    expect(s.trace.count('profiles.list'), 4);
    expect(s.trace.count('settings.get'), 4);
    expect(s.snapshots, hasLength(1));
    expect(s.attachments, 1);
    expect(s.data.io.attempts.single.client.commands, isEmpty);
    expect(s.errors, isEmpty);
  });

  test(
    'repeated start and refresh share the actual in-flight owner snapshot',
    () async {
      final s = await Setup.create();
      final held = Completer<void>();
      s.trace.blockers.add(held);
      s.trace.afterReply = (method, result) {
        if (method == 'profiles.list') return held.future;
      };
      await s.client.connect();
      s.client.startPolling();
      s.client.startPolling();
      final a = s.client.refreshSnapshot(), b = s.client.refreshSnapshot();
      expect(identical(a, b), isTrue);
      await settle();
      expect(s.trace.count('profiles.list'), 1);
      expect(s.trace.count('settings.get'), 0);
      expect(
        s.schedule.tasks.where(
          (t) => t.active && t.delay == const Duration(seconds: 2),
        ),
        hasLength(1),
      );
      held.complete();
      await a;
      await settle();
      expect(s.snapshots, hasLength(1));
      expect(s.trace.count('settings.get'), 1);
      expect(s.attachments, 1);
    },
  );

  test('real revision change between list and settings suppresses a torn snapshot until the next poll', () async {
    final s = await Setup.create();
    final next = await s.settingsRevision();
    var published = false;
    s.trace.afterReply = (method, result) {
      if (method == 'profiles.list' && !published) {
        published = true;
        s.data.store.value = next;
      }
    };
    await s.client.connect();
    s.client.startPolling();
    await settle();
    expect(s.snapshots, isEmpty);
    expect(s.errors, isEmpty);
    await s.schedule.firePoll(s.data);
    expect(s.snapshots, hasLength(1));
    expect(s.snapshots.single.storeRevision, '3');
    expect(
      (s.snapshots.single.settings.result['settings'] as Map)['theme'],
      'light',
    );
    expect(s.trace.count('profiles.list'), 2);
    expect(s.trace.count('settings.get'), 2);
    expect(s.data.io.attempts.single.client.commands, isEmpty);
  });

  test('2s snapshots coexist with actual owner/MCP5s shared target sampling without replay', () async {
    final s = await Setup.create(), mcp = await s.data.mcp();
    await s.data.attach(mcp);
    await s.client.connect();
    s.data.holdSystem = true;
    await s.client.controlClient!.call('servers.state', {
      'profileId': fixture.profile,
      'refresh': true,
    }, requestId: fixture.request1);
    final pending = await s.data.invoke(mcp, {
      'request': {
        'name': 'serverdeck_state_get',
        'arguments': {'serverId': fixture.profile, 'refresh': true},
      },
    });
    s.client.startPolling();
    await settle();
    for (var i = 0; i < 3; i++) await s.schedule.firePoll(s.data);
    expect(s.data.held, hasLength(1));
    expect(s.data.io.attempts.single.client.commands, hasLength(1));
    s.data.holdSystem = false;
    s.data.respond(s.data.held.single, SshReadSource.system);
    await settle();
    expect(
      (await s.data.invoke(mcp, {
        'poll': {'operationId': pending['operationId']},
      }))['done'],
      isTrue,
    );
    final owner = await s.client.controlClient!.call('servers.readStatus', {
      'operationId': fixture.request1,
    });
    expect(owner['state'], 'succeeded');
    expect(s.data.io.attempts.single.client.commands, hasLength(4));
    await s.client.controlClient!.call('servers.state', {
      'profileId': fixture.profile,
      'refresh': true,
    }, requestId: fixture.request2);
    await settle();
    expect(
      s.data.io.attempts.single.client.commands,
      hasLength(4),
    ); // just received; minimum5s remains distinct
    s.data.clock.elapsed += const Duration(seconds: 5);
    await s.client.controlClient!.call('servers.state', {
      'profileId': fixture.profile,
      'refresh': true,
    }, requestId: fixture.grantRequest);
    await settle();
    expect(s.data.io.attempts.single.client.commands, hasLength(6));
    expect(s.trace.count('profiles.list'), 4);
    expect(s.trace.count('settings.get'), 4);
    expect(s.attachments, 1);
    expect(s.data.io.attempts, hasLength(1));
  });

  test('stopped poll epoch rejects already captured real snapshot and stale timer callback', () async {
    final s = await Setup.create();
    final held = Completer<void>();
    s.trace.blockers.add(held);
    s.trace.afterReply = (method, result) {
      if (method == 'profiles.list') return held.future;
    };
    await s.client.connect();
    s.client.startPolling();
    await settle();
    final old = s.schedule.poll;
    s.client.stopPolling();
    held.complete();
    await settle();
    old.action();
    await settle();
    expect(s.snapshots, isEmpty);
    expect(s.errors, isEmpty);
    expect(s.trace.count('profiles.list'), 1);
    expect(s.trace.count('settings.get'), 0);
    expect(s.attachments, 1);
  });

  test('new actual host generation cannot receive a delayed old generation snapshot or error', () async {
    final s = await Setup.create();
    final held = Completer<void>();
    s.trace.blockers.add(held);
    s.trace.afterReply = (method, result) {
      if (method == 'profiles.list') return held.future;
    };
    await s.client.connect();
    s.client.startPolling();
    await settle();
    await s.trace.actual.close();
    await s.foundation.close();
    await s.data.close();
    await settle();
    final newer = await Setup.create(generation: fixture.request2);
    s.next = newer.trace;
    await s.client.connect();
    s.client.startPolling();
    held.complete();
    await settle();
    expect(s.snapshots, isEmpty);
    expect(s.errors, isEmpty);
    await s.schedule.firePoll(newer.data);
    expect(s.snapshots, hasLength(1));
    expect(s.snapshots.single.generation, fixture.request2);
    expect(s.errors, isEmpty);
    expect(s.attachments, 2);
    expect(s.trace.count('settings.get'), 0);
    expect(newer.trace.count('profiles.list'), 1);
    await s.client.close();
  });

  test('ambiguous gateway mutation failure never resubmits caller intent during real read polling', () async {
    final s = await Setup.create();
    await s.client.connect();
    s.client.startPolling();
    await settle();
    s.trace.ambiguousMutation = true;
    final intent = MutationIntent(ApiMethod.settingsUpdate, {
      'expectedRevision': '1',
      'theme': 'light',
    }, requestId: fixture.grantRequest);
    addTearDown(intent.dispose);
    await expectLater(
      s.client.mutate(intent),
      throwsA(
        isA<EngineApiException>().having(
          (e) => e.code,
          'code',
          ErrorCode.timeout,
        ),
      ),
    );
    for (var i = 0; i < 3; i++) await s.schedule.firePoll(s.data);
    expect(s.trace.count('settings.update'), 1);
    expect(
      s.trace.calls.singleWhere((c) => c.method == 'settings.update').id,
      intent.id,
    );
    expect(s.data.store.snapshot.foundation.foundation.storeRevision, '2');
    expect(s.trace.count('profiles.list'), 4);
    expect(s.trace.count('settings.get'), 4);
    expect(s.attachments, 1);
    expect(s.data.io.attempts.single.client.commands, isEmpty);
  });
}
