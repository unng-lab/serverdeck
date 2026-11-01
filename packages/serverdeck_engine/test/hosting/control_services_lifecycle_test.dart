import 'dart:async';

import 'package:serverdeck_engine/hosting/authority.dart';
import 'package:serverdeck_engine/hosting/control_services.dart';
import 'package:serverdeck_engine/hosting/in_process_gateway.dart';
import 'package:serverdeck_engine/hosting/sessions.dart';
import 'package:serverdeck_engine/platform/ports.dart';
import 'package:serverdeck_engine/remote/ssh_transport.dart';
import 'package:serverdeck_engine/storage/key_custody.dart';
import 'package:serverdeck_engine/storage/state_store.dart';
import 'package:serverdeck_engine/storage/workspace_snapshot.dart';
import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:test/test.dart';

import '../storage/workspace_snapshot_test.dart' as snapshot;
import '../support/schema3_fixture.dart' as fixture;
import 'target_changes_test.dart' as publication;

// Real domain services over a validated schema3 graph and RAM OS boundaries.
// Any unapproved repository/native/file/SSH effect is an immediate failure.
final class Store implements StateStore {
  Store(this.value, this.custody, this.key);
  final WorkspaceSnapshot value;
  final KeyCustody custody;
  final ReceiptKeyMaterial key;
  final listeners = <void Function(String, int)>{};
  bool blocked = false;
  int reads = 0;
  @override
  bool get isReady => !blocked;
  @override
  WorkspaceSnapshot get snapshot {
    reads++;
    if (blocked) throw StateError('PRIVATE_STORE_PROVIDER');
    return value;
  }

  @override
  void assertAutomationCustody(KeyCustody actual, ReceiptKeyMaterial receipt) {
    expect(identical(actual, custody), isTrue);
    expect(identical(receipt, key), isTrue);
  }

  @override
  void Function() onMcpGrantPublished(void Function(String, int) listener) {
    listeners.add(listener);
    return () => listeners.remove(listener);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('NO_REPOSITORY_IO_IN_UNIT');
}

final class Runtime implements VerifiedRuntime {
  Runtime({String generation = publication.profile, this.root = '/ram/app'})
    : gate = publication.Gate(generation: generation);
  final publication.Gate gate;
  final String root;
  Completer<void>? proof;
  @override
  String get ownerIdentity => fixture.owner;
  @override
  String get appRoot => root;
  @override
  String get buildId => '${'a' * 40}+Release+${'b' * 64}';
  @override
  Future<void> revalidate(WorkspaceLease lease) async {
    expect(lease.isHeld, isTrue);
    await proof?.future;
  }

  @override
  Future<PublicationGate> createPublicationGate(
    String generation,
    WorkspaceLease lease,
  ) async {
    expect(generation, gate.generation);
    return gate;
  }
}

final class Setup {
  Setup._(this.data, this.store);
  final snapshot.Setup data;
  final Store store;
  final runtime = Runtime();
  late final authority = HostAuthority.prepare(
    runtime: runtime,
    lease: data.lease,
    generation: publication.profile,
  );
  late EngineSessions sessions;
  late TrustedControlServices services;
  static Future<Setup> create() async {
    final data = await snapshot.Setup.create();
    final graph = await data.load();
    final s = Setup._(data, Store(graph, data.custody, data.key));
    await s.authority.initialize();
    s.sessions = EngineSessions.withAuthority(
      authority: s.authority,
      admissionBlocked: () => false,
    );
    s.services = await TrustedControlServices.create(
      store: s.store,
      custody: data.custody,
      receiptKey: data.key,
      sessions: s.sessions,
    );
    return s;
  }

  Future<InProcessGateway> gateway() async => InProcessGateway(
    owner: await sessions.openOwner(await authority.bindOwner(Object())),
    services: services,
    readiness: () => TrustedReadiness(
      state: ReadinessState.ready,
      generation: publication.profile,
      workspaceId: fixture.workspace,
      features: const OperationalFeatures(profiles: true),
    ),
  );
  Future<void> close() async {
    await services.close();
    await authority.close();
    expect(data.lease.closes, 0);
    expect(store.listeners, isEmpty);
  }
}

const request = '12345678-1234-4234-9234-123456789a70';
Matcher failure([String code = 'SERVICE_UNAVAILABLE']) =>
    throwsA(isA<StateError>().having((e) => e.message, 'safe code', code));

void main() {
  test(
    'provider close during pause seals a partially restored composition',
    () async {
      final s = await Setup.create();
      final pause = s.services.suspend();
      await pause.settled;
      await s.services.reads.executors.close();
      expect(() => s.services.resume(pause), failure());
      await expectLater(s.gateway(), failure());
      await s.close();
    },
  );

  test(
    'superseded registry fence immediately seals even a restored pool',
    () async {
      final s = await Setup.create();
      final pause = s.services.suspend();
      await pause.settled;
      s.sessions.pauseAdmission();
      expect(() => s.services.resume(pause), failure());
      expect(
        () => s.services.connections.transports.reserve(),
        throwsA(
          isA<SshTransportFailure>().having(
            (e) => e.code,
            'safe code',
            SshTransportCode.SERVICE_UNAVAILABLE,
          ),
        ),
      );
      await expectLater(s.gateway(), failure());
      await s.close();
    },
  );

  test('fresh read and job routes work after resume while old handles stay retired', () async {
    final s = await Setup.create();
    final old = await s.gateway();
    final jobs = await old.call('jobs.list', {}, requestId: fixture.request1);
    await old.call('servers.state', {
      'profileId': fixture.profile,
    }, requestId: request);
    await publication.settle();
    final status = await old.call('servers.readStatus', {
      'operationId': request,
    }, requestId: fixture.request2);
    expect(status['state'], 'failed');
    expect(status['code'], 'NOT_FOUND'); // Empty graph: never opens SSH.
    final pause = s.services.suspend();
    await pause.settled;
    s.services.resume(pause);
    final fresh = await s.gateway();
    expect(
      await fresh.call('jobs.list', {}, requestId: fixture.request1),
      jobs,
    );
    await expectLater(
      fresh.call('servers.readStatus', {
        'operationId': request,
      }, requestId: fixture.request2),
      throwsA(
        isA<EngineCallFailure>().having(
          (e) => e.code,
          'safe code',
          'NOT_FOUND',
        ),
      ),
    );
    await fresh.call('servers.state', {
      'profileId': fixture.profile,
    }, requestId: fixture.request2);
    await publication.settle();
    final next = await fresh.call('servers.readStatus', {
      'operationId': fixture.request2,
    }, requestId: request);
    expect(next['state'], 'failed');
    expect(next['code'], 'NOT_FOUND');
    expect(s.services.connections.transports.activeTransports, 0);
    await old.close();
    await fresh.close();
    await s.close();
  });

  test('actual composition resumes same store/services with fresh owner and snapshot', () async {
    final s = await Setup.create();
    final old = await s.gateway();
    final before = await old.call('settings.get', {}, requestId: request);
    final connections = s.services.connections,
        reads = s.services.reads,
        jobs = s.services.jobs,
        pool = connections.transports;
    final pause = s.services.suspend();
    expect(identical(s.services.suspend(), pause), isTrue);
    await pause.settled;
    expect(old.isClosed, isTrue);
    await expectLater(s.gateway(), failure('NOT_READY'));
    expect(pool.activeTransports, 0);
    s.services.resume(pause);
    final fresh = await s.gateway();
    expect(await fresh.call('settings.get', {}, requestId: request), before);
    expect(identical(s.services.connections, connections), isTrue);
    expect(identical(s.services.reads, reads), isTrue);
    expect(identical(s.services.jobs, jobs), isTrue);
    expect(identical(s.services.connections.transports, pool), isTrue);
    expect(identical(s.store.snapshot, s.store.value), isTrue);
    expect(s.runtime.gate.isClosed, isFalse);
    await old.close();
    await fresh.close();
    await s.close();
  });

  test(
    'pause owns late request proof and observer timeout does not permit resume',
    () async {
      final s = await Setup.create();
      final gateway = await s.gateway();
      final physical = s.runtime.proof = Completer<void>();
      final read = gateway.call('settings.get', {}, requestId: request);
      final rejected = expectLater(read, throwsA(isA<EngineCallFailure>()));
      await publication.settle();
      final pause = s.services.suspend();
      await expectLater(
        pause.settled.timeout(Duration.zero),
        throwsA(isA<TimeoutException>()),
      );
      expect(() => s.services.resume(pause), failure());
      expect(identical(s.services.suspend(), pause), isTrue);
      s.runtime.proof = null;
      physical.complete();
      await rejected;
      await pause.settled;
      s.services.resume(pause);
      await gateway.close();
      final fresh = await s.gateway();
      await fresh.call('settings.get', {}, requestId: request);
      await fresh.close();
      await s.close();
    },
  );

  test(
    'pool custody and local cleanup gate remain owned during service pause',
    () async {
      final s = await Setup.create();
      final reservation = s.services.connections.transports.reserve();
      final pause = s.services.suspend();
      var drained = false, cleanup = 0;
      final physical = pause.settled.then((_) => drained = true);
      await s.sessions.runAuthorityMutation(() async {
        cleanup++;
      });
      expect(cleanup, 1);
      expect(drained, isFalse);
      expect(s.services.connections.transports.activeTransports, 1);
      expect(() => s.services.resume(pause), failure());
      reservation.close();
      await physical;
      s.services.resume(pause);
      await s.close();
    },
  );

  test(
    'foreign stale and reused service handles cannot reopen admission',
    () async {
      final s = await Setup.create(), other = await Setup.create();
      final first = s.services.suspend(), foreign = other.services.suspend();
      await Future.wait([first.settled, foreign.settled]);
      expect(() => s.services.resume(foreign), failure());
      s.services.resume(first);
      expect(() => s.services.resume(first), failure());
      final current = s.services.suspend();
      await current.settled;
      expect(() => s.services.resume(first), failure());
      await expectLater(s.gateway(), failure('NOT_READY'));
      s.services.resume(current);
      other.services.resume(foreign);
      await s.close();
      await other.close();
    },
  );

  test(
    'close wins pending service suspend without releasing custody early',
    () async {
      final s = await Setup.create();
      final reservation = s.services.connections.transports.reserve();
      final pause = s.services.suspend();
      var closed = false;
      final closing = s.services.close().then((_) => closed = true);
      await publication.settle();
      expect(closed, isFalse);
      expect(() => s.services.resume(pause), failure());
      expect(s.data.lease.closes, 0);
      reservation.close();
      await Future.wait([pause.settled, closing]);
      expect(() => s.services.resume(pause), failure());
      expect(() => s.services.suspend(), failure());
      await s.close();
    },
  );

  test(
    'failed revision read on resume permanently seals partial restoration',
    () async {
      final s = await Setup.create();
      final pause = s.services.suspend();
      await pause.settled;
      s.store.blocked = true;
      expect(() => s.services.resume(pause), failure());
      s.store.blocked = false;
      expect(() => s.services.resume(pause), failure());
      await expectLater(s.gateway(), failure());
      await s.close();
    },
  );

  test(
    'failed detach cannot be mistaken for a successful service suspend',
    () async {
      final s = await Setup.create();
      final owner = await s.gateway();
      s.sessions.onSessionDetached((_) => throw StateError('PRIVATE_CALLBACK'));
      final pause = s.services.suspend();
      await expectLater(pause.settled, failure());
      expect(() => s.services.resume(pause), failure());
      expect(owner.isClosed, isTrue);
      await expectLater(s.gateway(), failure());
      await owner.close();
      await s.close();
    },
  );
}
