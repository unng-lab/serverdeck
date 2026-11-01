import 'dart:async';

import 'package:serverdeck_engine/hosting/authority.dart';
import 'package:serverdeck_engine/hosting/sessions.dart';
import 'package:serverdeck_engine/remote/connections.dart';
import 'package:serverdeck_engine/remote/reads.dart';
import 'package:serverdeck_engine/remote/ssh_transport.dart';
import 'package:test/test.dart';

import '../hosting/control_services_lifecycle_test.dart' as host;
import '../hosting/target_changes_test.dart' as publication;
import '../storage/workspace_snapshot_test.dart' as snapshot;
import '../support/schema3_fixture.dart' as fixture;
import 'ssh_io_policy_test.dart' as bytes;
import 'ssh_pool_lifecycle_test.dart' show settle;

Matcher failed() => throwsA(
  isA<StateError>().having(
    (e) => e.message,
    'safe code',
    'SERVICE_UNAVAILABLE',
  ),
);

final class Setup {
  Setup(this.data, this.store);
  final snapshot.Setup data;
  final host.Store store;
  final runtime = host.Runtime();
  final io = bytes.Io();
  late final pool = SshTransportPool(io: io);
  late final authority = HostAuthority.prepare(
    runtime: runtime,
    lease: data.lease,
    generation: publication.profile,
  );
  late final EngineSessions sessions;
  late final TrustedConnectionService connections;
  late final OwnerSession owner;

  static Future<Setup> create() async {
    final data = await snapshot.Setup.create(populated: true);
    final graph = await data.load();
    final s = Setup(data, host.Store(graph, data.custody, data.key));
    s.io.observed = graph.foundation.trust[fixture.profile]!.key;
    await s.authority.initialize();
    s.sessions = EngineSessions.withAuthority(
      authority: s.authority,
      admissionBlocked: () => false,
    );
    s.connections = TrustedConnectionService(
      store: s.store,
      custody: data.custody,
      sessions: s.sessions,
      authority: TrustedMcpAuthority(s.store),
      transports: s.pool,
    );
    s.owner = await s.sessions.openOwner(await s.authority.bindOwner(Object()));
    final request = s.owner.reserve('servers.connect');
    final reservation = s.connections.reserve(request, {
      'profileId': fixture.profile,
    }, fixture.request1);
    await s.owner.admit(request);
    s.connections.startOwner(request, reservation);
    s.connections.release(reservation);
    request.complete();
    await settle();
    final status = s.owner.reserve('servers.connectStatus');
    await s.owner.admit(status);
    expect(
      (await s.connections.ownerStatus(status, fixture.request1))['state'],
      'succeeded',
    );
    status.complete();
    addTearDown(() async {
      s.runtime.proof?.complete();
      for (final actual in s.io.attempts) {
        for (final session in actual.client.sessions) {
          if (session.stdinPause case final pause? when !pause.isCompleted)
            pause.complete();
          session.throwClose = false;
        }
        await actual.client.finish().then<void>(
          (_) {},
          onError: (Object _, StackTrace __) {},
        );
        actual.drain();
      }
      await s.connections.close().then<void>(
        (_) {},
        onError: (Object _, StackTrace __) {},
      );
      await s.pool.close().then<void>(
        (_) {},
        onError: (Object _, StackTrace __) {},
      );
      s.owner.close();
      await s.authority.close();
    });
    return s;
  }

  Future<TrustedOwnerReadContext> context() async {
    final request = owner.reserve('servers.state');
    await owner.admit(request);
    final context = request.ownerReadContext();
    request.complete();
    return context;
  }
}

void main() {
  for (final executor in [false, true]) {
    test(
      'connection drain fails safely instead of hanging: executor=$executor',
      () async {
        final s = await Setup.create();
        final context = await s.context();
        Future<void> done;
        if (executor) {
          final work = s.connections.openExecutorOwner(
            context,
            fixture.profile,
          );
          await work.ready;
          done = work.done;
        } else {
          final work = s.connections.readOwner(
            context,
            fixture.profile,
            const SshReadRequest.system(),
          );
          work.result.ignore();
          done = work.done;
        }
        await settle();
        final completion = expectLater(done, failed());
        final session = s.io.attempts.single.client.sessions.single;
        session.completed.completeError(StateError('PRIVATE_PROVIDER_FAILURE'));
        await completion;
        await expectLater(s.connections.suspend(), failed());
        await expectLater(s.connections.close(), failed());
        expect(
          () => s.connections.readOwner(
            context,
            fixture.profile,
            const SshReadRequest.system(),
          ),
          failed(),
        );
        expect(s.pool.activeTransports, 1);
      },
    );
  }

  test(
    'shared refresh failure remains observable by read service shutdown',
    () async {
      final s = await Setup.create();
      final reads = RemoteReadService(s.connections);
      final work = reads.startOwner(await s.context(), 'serverdeck_state_get', {
        'serverId': fixture.profile,
        'refresh': true,
      });
      work.result.ignore();
      await settle();
      expect(s.io.attempts.single.client.sessions, hasLength(1));
      s.io.attempts.single.client.sessions.single.completed.completeError(
        StateError('PRIVATE_REFRESH_FAILURE'),
      );
      await settle();
      await expectLater(reads.close(), failed());
      await expectLater(s.connections.close(), failed());
      expect(s.pool.activeTransports, 1);
    },
  );
}
