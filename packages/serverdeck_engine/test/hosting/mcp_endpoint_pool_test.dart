import 'dart:async';
import 'dart:typed_data';

import 'package:serverdeck_engine/api/mcp_server.dart';
import 'package:serverdeck_engine/hosting/mcp_endpoint_pool.dart';
import 'package:serverdeck_engine/platform/ports.dart';
import 'package:serverdeck_protocol/discovery.dart';
import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:test/test.dart';

import 'sessions_test.dart' as session;

const workspace = '12345678-1234-4234-9234-123456789abe';

final class Peer implements VerifiedMcpChannel {
  Peer(session.Setup setup) : this.fromRuntime(setup.runtime);
  Peer.fromRuntime(this.runtime) {
    reading.future.ignore();
  }
  final VerifiedRuntime runtime;
  final reading = Completer<Uint8List>();
  Completer<void>? closing;
  Future<void>? closed;
  bool failClose = false;
  int writes = 0, disconnects = 0;
  @override
  String get ownerIdentity => runtime.ownerIdentity;
  @override
  String get appRoot => runtime.appRoot;
  @override
  String get buildId => runtime.buildId;
  @override
  Future<void> revalidate({
    void Function(Future<void>)? observeNativeCompletion,
  }) {
    final actual = Future<void>.value();
    observeNativeCompletion?.call(actual);
    return actual;
  }

  @override
  Future<Uint8List> read({required int count, required Duration deadline}) {
    reading.future.ignore();
    return reading.future;
  }

  @override
  Future<void> write(List<int> bytes, {required Duration deadline}) async {
    writes++;
  }

  @override
  Future<void> drainOutput({required Duration deadline}) async {}
  @override
  Future<void> disconnect() {
    if (closed != null) return closed!;
    final done = Completer<void>();
    closed = done.future;
    done.future.ignore();
    disconnects++;
    if (!reading.isCompleted)
      reading.completeError(StateError('SERVICE_UNAVAILABLE'));
    () async {
      await closing?.future;
      if (failClose) throw StateError('private native close');
    }().then<void>(
      done.complete,
      onError: (Object e, StackTrace s) => done.completeError(e),
    );
    return done.future;
  }
}

final class Listener implements McpListener {
  final accepting = Completer<VerifiedMcpChannel>();
  Completer<void>? opening, closing;
  Peer? given;
  int accepts = 0, closes = 0;
  bool failClose = false, holdAccept = false;
  Future<void>? closed;
  Listener() {
    accepting.future.ignore();
  }
  @override
  Future<void> get ready => opening?.future ?? Future.value();
  @override
  Future<VerifiedMcpChannel> accept() {
    accepts++;
    return accepting.future;
  }

  void deliver(Peer peer) {
    given = peer;
    accepting.complete(peer);
  }

  @override
  Future<void> close() {
    if (closed != null) return closed!;
    final done = Completer<void>();
    closed = done.future;
    done.future.ignore();
    closes++;
    if (!holdAccept && !accepting.isCompleted)
      accepting.completeError(StateError('SERVICE_UNAVAILABLE'));
    () async {
      await closing?.future;
      await given?.disconnect();
      if (failClose) throw StateError('private close');
    }().then<void>(
      done.complete,
      onError: (Object e, StackTrace s) => done.completeError(e),
    );
    return done.future;
  }
}

final class Discovery implements McpDiscoveryStore {
  Completer<void>? publishing;
  final events = <String>[];
  Object? error;
  @override
  Future<void> publish(DiscoveryDescriptor descriptor) async {
    events.add('publish.begin');
    await publishing?.future;
    expect(descriptor.isClosed, isFalse);
    events.add('publish.done');
    if (error != null) throw error!;
  }

  @override
  Future<void> removeOwned(DiscoveryDescriptor descriptor) async {
    events.add('remove');
    expect(descriptor.isClosed, isFalse);
  }
}

final class Setup {
  Setup(this.sessions, this.descriptor);
  final session.Setup sessions;
  final DiscoveryDescriptor descriptor;
  final discovery = Discovery(), listeners = <Listener>[], names = <String>[];
  ReadinessState state = ReadinessState.ready;
  void Function(int)? onCreate;
  late final server = McpApiServer.starting(
    sessions: sessions.sessions,
    readiness: () => TrustedReadiness(
      state: state,
      generation: sessions.sessions.generation,
      workspaceId: state == ReadinessState.ready ? workspace : null,
      features: state == ReadinessState.ready
          ? const OperationalFeatures(profiles: true)
          : const OperationalFeatures(),
    ),
  );
  late final pool = McpEndpointPool(
    descriptor: descriptor,
    server: server,
    discovery: discovery,
    createListener: (name) {
      final listener = Listener();
      listeners.add(listener);
      names.add(name);
      onCreate?.call(listeners.length);
      return listener;
    },
    checkLive: () {},
    elapsed: () => sessions.elapsed,
  );
  static Future<Setup> create() async {
    final registry = await session.Setup.create();
    final descriptor = await DiscoveryDescriptor.create(
      ownerSid: registry.runtime.ownerIdentity,
      buildId: registry.runtime.buildId,
      serverPid: 42,
      generation: registry.sessions.generation,
      workspaceId: workspace,
    );
    return Setup(registry, descriptor);
  }

  Future<void> close() async {
    await pool.close();
    await sessions.close();
  }
}

void main() {
  test('superseded barrier waits current intent instead of failing recovering pool', () async {
    final s = await Setup.create(), permit = Completer<void>();
    var epoch = 0, barriers = 0;
    final activation = s.pool.activate(
      beforePublish: () async {
        final captured = epoch;
        barriers++;
        if (barriers == 1) {
          scheduleMicrotask(() {
            epoch++;
            s.state = ReadinessState.recovering;
          });
        } else {
          await permit.future;
        }
        return () => captured == epoch;
      },
    );
    await session.settle();
    expect(barriers, 2);
    expect(s.discovery.events, isEmpty);
    expect(s.pool.isPublished, isFalse);
    s.state = ReadinessState.ready;
    permit.complete();
    await activation;
    expect(s.pool.isPublished, isTrue);
    await s.close();
  });

  test(
    'activation owns Host admission barrier before readiness and publication',
    () async {
      final s = await Setup.create();
      s.state = ReadinessState.recovering;
      final permit = Completer<void>();
      var waiting = false;
      final activation = s.pool.activate(
        beforePublish: () async {
          waiting = true;
          await permit.future;
          return () => true;
        },
      );
      await session.settle();
      expect(waiting, isTrue);
      expect(s.discovery.events, isEmpty);
      expect(s.pool.isPublished, isFalse);
      s.state = ReadinessState.ready;
      permit.complete();
      await activation;
      expect(s.pool.isPublished, isTrue);
      await s.close();
    },
  );

  test('eight owned endpoints bind before discovery and only activate with Host ready', () async {
    final s = await Setup.create();
    await s.pool.bind();
    expect(s.listeners.length, 8);
    expect(s.names, s.descriptor.pipeNames);
    expect(s.discovery.events, isEmpty);
    expect(s.listeners.every((l) => l.accepts == 0), isTrue);
    await s.pool.activate(
      beforePublish: () async =>
          () => true,
    );
    await session.settle();
    expect(s.pool.isPublished, isTrue);
    expect(s.listeners.every((l) => l.accepts == 1), isTrue);
    await s.close();
    expect(s.discovery.events.last, 'remove');
    expect(s.descriptor.isClosed, isTrue);
  });
  test('recovering Host cannot advertise endpoint discovery', () async {
    final s = await Setup.create();
    s.state = ReadinessState.recovering;
    await expectLater(
      s.pool.activate(
        beforePublish: () async =>
            () => true,
      ),
      session.failure('NOT_READY'),
    );
    expect(s.discovery.events, isEmpty);
    await s.close();
  });
  test(
    'pending listener construction is owned before reentrant stop',
    () async {
      final s = await Setup.create();
      Future<void>? close;
      s.onCreate = (_) {
        close ??= s.pool.close();
      };
      await expectLater(s.pool.bind(), session.failure('SERVICE_UNAVAILABLE'));
      await close;
      expect(s.listeners.length, 1);
      expect(s.listeners.single.closes, 1);
      expect(s.discovery.events, ['remove']);
      await s.sessions.close();
    },
  );
  test(
    'stop cancels partial bind; physical ready and close remain owned',
    () async {
      final s = await Setup.create(),
          ready = Completer<void>(),
          nativeClose = Completer<void>();
      s.onCreate = (n) {
        if (n == 1) {
          s.listeners.first.opening = ready;
          s.listeners.first.closing = nativeClose;
        }
      };
      final bind = s.pool.bind();
      bind.ignore();
      await session.settle();
      var finished = false;
      final close = s.pool.close().then((_) => finished = true);
      await session.settle();
      expect(s.listeners.first.closes, 1);
      expect(finished, isFalse);
      ready.complete();
      await expectLater(bind, session.failure('SERVICE_UNAVAILABLE'));
      expect(finished, isFalse);
      nativeClose.complete();
      await close;
      await s.sessions.close();
    },
  );
  test(
    'late publication cannot resurrect discovery after close or wipe key early',
    () async {
      final s = await Setup.create();
      s.discovery.publishing = Completer();
      final activation = s.pool.activate(
        beforePublish: () async =>
            () => true,
      );
      activation.ignore();
      await session.settle();
      expect(s.discovery.events, ['publish.begin']);
      final close = s.pool.close();
      await session.settle();
      expect(s.descriptor.isClosed, isFalse);
      expect(s.discovery.events, isNot(contains('remove')));
      s.discovery.publishing!.complete();
      await expectLater(activation, session.failure('SERVICE_UNAVAILABLE'));
      await close;
      expect(s.discovery.events, ['publish.begin', 'publish.done', 'remove']);
      expect(s.pool.isPublished, isFalse);
      expect(s.descriptor.isClosed, isTrue);
      await s.sessions.close();
    },
  );
  test('bad peer closes its slot; no rebinding until physical disconnect proves safe', () async {
    final s = await Setup.create();
    await s.pool.activate(
      beforePublish: () async =>
          () => true,
    );
    await session.settle();
    final peer = Peer(s.sessions)..closing = Completer();
    s.listeners.first.deliver(peer);
    await session.settle();
    expect(peer.writes, 1);
    peer.reading.completeError(StateError('bad frame'));
    await session.settle();
    expect(s.listeners.length, 8);
    expect(peer.disconnects, 1);
    peer.closing!.complete();
    await session.settle();
    expect(s.listeners.length, 9);
    expect(s.names.last, s.names.first);
    await s.close();
  });
  test(
    'unconfirmed physical close fails pool, never rebinds and retains failure',
    () async {
      final s = await Setup.create();
      await s.pool.activate(
        beforePublish: () async =>
            () => true,
      );
      await session.settle();
      final peer = Peer(s.sessions)..failClose = true;
      s.listeners.first.deliver(peer);
      await session.settle();
      peer.reading.completeError(StateError('bad frame'));
      await session.settle();
      expect(s.listeners.length, 8);
      expect(s.pool.isPublished, isFalse);
      await expectLater(s.pool.failure, session.failure('SERVICE_UNAVAILABLE'));
      await expectLater(s.pool.close(), session.failure('SERVICE_UNAVAILABLE'));
      await s.sessions.close();
    },
  );
  test(
    'stop while accept settles closes late peer without handshake or effects',
    () async {
      final s = await Setup.create();
      await s.pool.activate(
        beforePublish: () async =>
            () => true,
      );
      await session.settle();
      final first = s.listeners.first;
      first.holdAccept = true;
      first.closing = Completer();
      final close = s.pool.close();
      await session.settle();
      final peer = Peer(s.sessions);
      first.deliver(peer);
      await session.settle();
      expect(peer.writes, 0);
      first.closing!.complete();
      await close;
      expect(peer.disconnects, 1);
      await s.sessions.close();
    },
  );
  test('failed late peer disconnect remains fatal after listener closed successfully', () async {
    final s = await Setup.create();
    await s.pool.activate(
      beforePublish: () async =>
          () => true,
    );
    await session.settle();
    final first = s.listeners.first..holdAccept = true;
    final close = s.pool.close();
    close.ignore();
    await session.settle();
    await first.closed;
    final peer = Peer(s.sessions)..failClose = true;
    first.deliver(peer);
    await expectLater(close, session.failure('SERVICE_UNAVAILABLE'));
    await expectLater(s.pool.failure, session.failure('SERVICE_UNAVAILABLE'));
    expect(peer.writes, 0);
    expect(peer.disconnects, 1);
    expect(s.listeners.length, 8);
    await s.sessions.close();
  });
  test('incompatible discovery failure is preserved and only owned attempt removed', () async {
    final s = await Setup.create();
    s.discovery.error = StateError('INCOMPATIBLE');
    await expectLater(
      s.pool.activate(
        beforePublish: () async =>
            () => true,
      ),
      session.failure('INCOMPATIBLE'),
    );
    await s.close();
    expect(s.discovery.events.last, 'remove');
    expect(s.listeners.every((l) => l.closes == 1), isTrue);
  });
}
