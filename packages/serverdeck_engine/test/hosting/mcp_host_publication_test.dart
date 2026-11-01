import 'dart:async';

import 'package:serverdeck_engine/api/mcp_server.dart';
import 'package:serverdeck_engine/hosting/engine_host.dart';
import 'package:serverdeck_engine/hosting/mcp_endpoint_pool.dart';
import 'package:serverdeck_engine/hosting/sessions.dart';
import 'package:serverdeck_engine/mcp/router.dart';
import 'package:serverdeck_engine/storage/state_store.dart';
import 'package:serverdeck_protocol/discovery.dart';
import 'package:serverdeck_protocol/mcp/catalog.dart';
import 'package:test/test.dart';

import 'engine_host_test.dart' as host;
import 'mcp_endpoint_pool_test.dart' as pool;
import 'authority_test.dart' show settle;

// No file/native/database call is permitted by this RAM authority listener port.
final class Store implements StateStore {
  @override
  void Function() onMcpGrantPublished(void Function(String, int) listener) =>
      () {};
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('NO_STORE_IO_IN_UNIT');
}

final class Tools implements TrustedMcpToolServices {
  @override
  McpServiceOperation start(
    TrustedMcpContext context,
    McpToolDefinition tool,
    Map<String, Object?> args,
  ) => throw StateError('NO_DOMAIN_EFFECT_IN_UNIT');
}

final class Setup {
  final hostFixture = host.Setup(),
      discovery = pool.Discovery(),
      listeners = <pool.Listener>[];
  TrustedMcpAuthority? authority;
  TrustedMcpRouter? router;
  McpEndpointPool? publication;
  Setup() {
    hostFixture.resources.createMcp = (sessions, readiness) {
      authority = TrustedMcpAuthority(Store());
      router = TrustedMcpRouter(
        sessions: sessions,
        authority: authority!,
        services: Tools(),
      );
      return McpApiServer(
        sessions: sessions,
        authority: authority!,
        router: router!,
        readiness: readiness,
      );
    };
    hostFixture.mcpPublication = (server, workspace) async {
      final descriptor = await DiscoveryDescriptor.create(
        ownerSid: hostFixture.runtime.ownerIdentity,
        buildId: hostFixture.runtime.buildId,
        serverPid: 42,
        generation: server.sessions.generation,
        workspaceId: workspace,
      );
      return publication = McpEndpointPool(
        descriptor: descriptor,
        server: server,
        discovery: discovery,
        createListener: (_) {
          final listener = pool.Listener();
          listeners.add(listener);
          return listener;
        },
        checkLive: () {},
        elapsed: () => hostFixture.clock.elapsed,
      );
    };
  }
  Future<void> finish() async {
    router?.close();
    await authority?.closeAndDrain();
  }
}

void main() {
  test(
    'late accepted peer close failure keeps Host lease after listener close',
    () async {
      final s = Setup();
      expect(await s.hostFixture.start(), HostStartResult.ready);
      await settle();
      final first = s.listeners.first..holdAccept = true;
      expect(
        await s.hostFixture.host.shutdown(
          'exit',
          deadline: const Duration(milliseconds: 10),
        ),
        HostCloseResult.closeBlocked,
      );
      await first.closed;
      final peer = pool.Peer.fromRuntime(s.hostFixture.runtime)
        ..failClose = true;
      first.deliver(peer);
      await settle();
      expect(
        await s.hostFixture.host.waitForClose(),
        HostCloseResult.closeBlocked,
      );
      expect(s.hostFixture.lease.closes, 0);
      expect(peer.writes, 0);
      await s.finish();
    },
  );
  test('Host acknowledgement waits publication; endpoint services are same registry', () async {
    final s = Setup();
    s.discovery.publishing = Completer();
    var ready = false;
    final start = s.hostFixture.start().then((value) {
      ready = true;
      return value;
    });
    await settle();
    expect(s.listeners.length, 8);
    expect(s.discovery.events, ['publish.begin']);
    expect(ready, isFalse);
    expect(s.hostFixture.host.readiness.features.mcp, isFalse);
    expect(s.hostFixture.resources.events, contains('services.open'));
    s.discovery.publishing!.complete();
    expect(await start, HostStartResult.ready);
    expect(s.hostFixture.host.readiness.features.mcp, isTrue);
    expect(
      identical(
        s.publication!.server.sessions,
        s.hostFixture.resources.sessions,
      ),
      isTrue,
    );
    expect(await s.hostFixture.host.shutdown('exit'), HostCloseResult.closed);
    expect(s.discovery.events.last, 'remove');
    expect(s.hostFixture.lease.closes, 1);
    await s.finish();
  });
  test(
    'exit during late publication cannot release lease or resurrect discovery',
    () async {
      final s = Setup();
      s.discovery.publishing = Completer();
      final start = s.hostFixture.start();
      await settle();
      expect(
        await s.hostFixture.host.shutdown(
          'exit',
          deadline: const Duration(milliseconds: 10),
        ),
        HostCloseResult.closeBlocked,
      );
      expect(await start, HostStartResult.startingFailure);
      expect(s.hostFixture.lease.closes, 0);
      expect(s.publication!.descriptor.isClosed, isFalse);
      s.discovery.publishing!.complete();
      await settle();
      expect(s.hostFixture.lease.closes, 0);
      expect(await s.hostFixture.host.waitForClose(), HostCloseResult.closed);
      expect(s.discovery.events, ['publish.begin', 'publish.done', 'remove']);
      expect(s.hostFixture.lease.closes, 1);
      await s.finish();
    },
  );
  test(
    'Host refuses unactivated MCP services before invoking publication factory',
    () async {
      final s = host.Setup();
      var factories = 0;
      s.resources.createMcp = (sessions, readiness) =>
          McpApiServer.starting(sessions: sessions, readiness: readiness);
      s.mcpPublication = (_, __) async {
        factories++;
        throw StateError('NO_FACTORY_ALLOWED');
      };
      expect(await s.start(), HostStartResult.startingFailure);
      expect(s.host.failureCode, 'SERVICE_UNAVAILABLE');
      expect(factories, 0);
      expect(await s.host.shutdown('exit'), HostCloseResult.closed);
    },
  );
  test(
    'Host rejects another server object returned by publication factory',
    () async {
      final s = Setup();
      final good = s.hostFixture.mcpPublication!;
      s.hostFixture.mcpPublication = (server, workspace) async {
        final other = McpApiServer(
          sessions: server.sessions,
          authority: server.authority,
          router: server.router,
          readiness: server.readiness,
        );
        return good(other, workspace);
      };
      expect(await s.hostFixture.start(), HostStartResult.startingFailure);
      expect(s.hostFixture.host.failureCode, 'UNAUTHORIZED');
      expect(s.listeners, isEmpty);
      expect(await s.hostFixture.host.shutdown('exit'), HostCloseResult.closed);
      expect(s.publication!.descriptor.isClosed, isTrue);
      await s.finish();
    },
  );
}
