import 'package:serverdeck_engine/hosting/capability_snapshot.dart';

import 'dart:async';
import 'dart:isolate';

import 'package:serverdeck_engine/hosting/engine_host.dart';
import 'package:serverdeck_engine/hosting/in_process_gateway.dart';
import 'package:serverdeck_engine/hosting/worker_connection.dart';
import 'package:serverdeck_engine/hosting/worker_controller.dart';
import 'package:serverdeck_engine/hosting/worker_root.dart';
import 'package:test/test.dart';

import 'authority_test.dart' as ram;
import 'in_process_gateway_test.dart' as core;
import 'worker_gateway_test.dart' show copyMessage;
import 'worker_root_test.dart' show Bootstrap;

final class Link implements WorkerWindowLink, GatewayChannel {
  Link(this.connection, this.binding);
  final Connection connection;
  final Capability binding;
  final stream = StreamController<Object?>(sync: true);
  bool disposed = false;
  @override
  Object get replyAddress => this;
  @override
  GatewayChannel get channel => this;
  @override
  Stream<Object?> get messages => stream.stream;
  @override
  void send(Map<String, Object?> frame) {
    if (disposed) throw StateError('private channel failure');
    connection.root.handle([binding, copyMessage(frame)]);
  }

  void receive(Map<String, Object?> frame) {
    if (!disposed) stream.add(copyMessage(frame));
  }

  @override
  void workerLost() {
    if (!disposed) stream.addError(EngineCallFailure('SERVICE_UNAVAILABLE'));
    dispose();
  }

  @override
  void dispose() {
    if (disposed) return;
    disposed = true;
    stream.close().ignore();
  }
}

final class Connection implements WorkerConnection {
  final bootstrap = Bootstrap(), capability = Capability();
  final stream = StreamController<Object?>(sync: true);
  final sent = <Map<String, Object?>>[],
      queued = <Map<String, Object?>>[],
      held = <Map<String, Object?>>[];
  final links = <Link>[];
  int starts = 0, acks = 0, ackAttempts = 0;
  bool expectedExit = false, closeStreamOnAck = false;
  bool holdControls = false, holdReplies = false, failSend = false;
  late final root = EngineWorkerRoot(
    control: capability,
    bootstrap: bootstrap,
    clock: bootstrap.setup.clock,
    replies: ReplyPorts(this),
    sendControl: reply,
    closedAcknowledged: () => acks++,
  );
  @override
  Stream<Object?> get messages => stream.stream;
  void reply(Map<String, Object?> frame) {
    if (holdReplies)
      held.add(frame);
    else
      stream.add(frame);
  }

  @override
  Future<void> start(int expiresAt) async {
    starts++;
    root
        .start(expiresAt)
        .then<void>((status) => reply({'kind': 'started', 'status': status}))
        .ignore();
  }

  @override
  void send(Map<String, Object?> frame) {
    sent.add(Map.of(frame));
    if (holdControls)
      queued.add(frame);
    else
      root.handle([capability, frame]);
    if (failSend) throw StateError('uncertain private send');
  }

  void flushControls() {
    final values = queued.toList();
    queued.clear();
    for (final value in values) {
      root.handle([capability, value]);
    }
  }

  void flushReplies() {
    final values = held.toList();
    held.clear();
    for (final value in values) {
      stream.add(value);
    }
  }

  @override
  WorkerWindowLink openWindow(Capability binding) {
    final link = Link(this, binding);
    links.add(link);
    return link;
  }

  @override
  void acknowledgeClosed(int sequence) {
    ackAttempts++;
    if (expectedExit) throw StateError('duplicate private close ACK');
    expectedExit = true;
    root.handle([
      capability,
      {'kind': 'ackClosed', 'sequence': sequence},
    ]);
    if (closeStreamOnAck)
      scheduleMicrotask(() {
        stream.close().ignore();
      });
  }
}

final class ReplyPorts implements WorkerReplyPorts {
  ReplyPorts(this.connection);
  final Connection connection;
  @override
  bool accepts(Object? address) =>
      address is Link && connection.links.contains(address);
  @override
  void send(Object address, Map<String, Object?> frame) =>
      (address as Link).receive(frame);
}

final class Setup {
  final connection = Connection();
  final timers = <({int at, void Function() fire, bool Function() active})>[];
  late final controller = EngineWorkerController(
    platformKind: EnginePlatformKind.windows,
    connection: connection,
    nowMicros: () => connection.bootstrap.setup.clock.elapsed.inMicroseconds,
    schedule: schedule,
  );
  void Function() schedule(Duration duration, void Function() action) {
    var active = true;
    timers.add((
      at:
          connection.bootstrap.setup.clock.elapsed.inMicroseconds +
          duration.inMicroseconds,
      fire: action,
      active: () => active,
    ));
    return () => active = false;
  }

  void advance(Duration amount, {bool fire = true}) {
    connection.bootstrap.setup.clock.elapsed += amount;
    if (fire) {
      for (final timer in timers.toList()) {
        if (timer.active() &&
            timer.at <= connection.bootstrap.setup.clock.elapsed.inMicroseconds)
          timer.fire();
      }
    }
  }

  Future<void> close() async {
    expect(await controller.shutdown(), HostCloseResult.closed);
    expect(connection.acks, 1);
  }
}

void main() {
  test('local tray overlay survives metadata and power masks without worker control', () async {
    final s = Setup();
    s.controller.setTrayAvailable(true);
    await s.controller.start();
    expect(s.controller.status.capabilities.coreUsable, isTrue);
    expect(s.controller.status.capabilities.trayAvailable, isTrue);
    expect(
      EngineCapabilities.fromJson(s.connection.root.status['capabilities'])
          .trayAvailable,
      isFalse,
    );
    s.controller.setSuspended(true);
    expect(s.controller.status.capabilities.coreUsable, isFalse);
    expect(s.controller.status.capabilities.trayAvailable, isTrue);
    await ram.settle();
    s.controller.setSuspended(false);
    await ram.settle();
    expect(s.controller.status.capabilities.coreUsable, isTrue);
    s.controller.setTrayAvailable(false);
    expect(
      (await s.controller.refreshReadiness()).capabilities.trayAvailable,
      isFalse,
    );
    expect(s.connection.sent.any((f) => f['kind'] == 'tray'), isFalse);
    await s.close();
    expect(s.controller.status.capabilities.coreUsable, isFalse);
  });
  test('current private status cannot switch the expected platform', () async {
    final s = Setup();
    await s.controller.start();
    s.connection.holdControls = true;
    s.controller.setSuspended(false);
    await ram.settle();
    s.connection.stream.add({
      'kind': 'power',
      'epoch': 1,
      'status': {
        'phase': 'resuming',
        'reason': 'NOT_READY',
        'readiness': null,
        'capabilities': EngineCapabilities.unavailable(EnginePlatformKind.linux)
            .toJson(),
      },
    });
    expect(s.controller.isLost, isTrue);
    expect(s.controller.status.capabilities.coreUsable, isFalse);
    expect(await s.connection.root.shutdown(10000000), HostCloseResult.closed);
  });
  test(
    'required availability cannot replace readiness or metadata authority',
    () async {
      final s = Setup();
      await s.controller.start();
      final good = s.connection.root.status;
      expect(
        () => WorkerStatus.fromJson(
          Map<String, Object?>.of(good)..remove('capabilities'),
        ),
        throwsA(anything),
      );
      expect(
        () => WorkerStatus.fromJson({
          ...good,
          'phase': 'suspended',
          'reason': 'NOT_READY',
        }),
        throwsA(anything),
      );
      s.controller.setSuspended(true);
      await expectLater(
        s.controller.openOwner(Object()),
        throwsA(isA<EngineCallFailure>()),
      );
      expect(s.controller.status.capabilities.coreUsable, isFalse);
      await ram.settle();
      await s.close();
    },
  );
  test(
    'all metadata projections wait actual parent detach before Ready',
    () async {
      final s = Setup();
      await s.controller.start();
      await s.controller.openOwner(Object());
      s.connection.holdReplies = true;
      s.controller.setSuspended(true);
      await ram.settle();
      s.controller.setSuspended(false);
      await ram.settle();
      final ready = s.connection.held.lastWhere(
        (frame) =>
            frame['kind'] == 'power' &&
            frame['epoch'] == 2 &&
            (frame['status'] as Map)['phase'] == 'ready',
      );
      s.connection.stream.add(ready);
      final reading = s.controller.refreshReadiness();
      final desktop = s.controller.refreshDesktopStatus();
      await ram.settle();
      for (final operation in ['readiness', 'desktopStatus']) {
        s.connection.stream.add(
          s.connection.held.singleWhere(
            (frame) => frame['operation'] == operation,
          ),
        );
      }
      expect((await reading).phase, 'resuming');
      expect((await desktop).status.phase, 'resuming');
      expect(s.controller.status.phase, 'resuming');
      s.connection.stream.add(
        s.connection.held.singleWhere(
          (frame) => frame['operation'] == 'detach',
        ),
      );
      await ram.settle();
      expect(s.controller.status.phase, 'ready');
      s.connection.held.clear();
      s.connection.holdReplies = false;
      expect((await s.controller.refreshReadiness()).phase, 'ready');
      expect((await s.controller.refreshDesktopStatus()).status.phase, 'ready');
      await s.close();
    },
  );
  for (final desktop in [false, true]) {
    test(
      'metadata public continuation masks a newer power intent: desktop=$desktop',
      () async {
        final s = Setup();
        await s.controller.start();
        s.connection.holdReplies = true;
        final result = desktop
            ? s.controller.refreshDesktopStatus().then((value) => value.status)
            : s.controller.refreshReadiness();
        await ram.settle();
        s.connection.stream.add(
          s.connection.held.singleWhere(
            (frame) =>
                frame['operation'] == (desktop ? 'desktopStatus' : 'readiness'),
          ),
        );
        s.controller.setSuspended(true);
        expect((await result).phase, isNot('ready'));
        await ram.settle();
        s.connection.held.clear();
        s.connection.holdReplies = false;
        await s.close();
      },
    );
  }
  test(
    'deferred power Ready cannot revive a newer current metadata failure',
    () async {
      final s = Setup();
      await s.controller.start();
      await s.controller.openOwner(Object());
      s.connection.holdReplies = true;
      s.controller.setSuspended(true);
      await ram.settle();
      s.controller.setSuspended(false);
      await ram.settle();
      final ready = s.connection.held.lastWhere(
        (frame) =>
            frame['kind'] == 'power' &&
            frame['epoch'] == 2 &&
            (frame['status'] as Map)['phase'] == 'ready',
      );
      s.connection.stream.add(ready);
      final reading = s.controller.refreshReadiness();
      await ram.settle();
      final metadata = s.connection.held.singleWhere(
        (frame) => frame['operation'] == 'readiness',
      );
      s.connection.stream.add({
        ...metadata,
        'result': {
          'phase': 'failed',
          'capabilities': EngineCapabilities.unavailable(
            EnginePlatformKind.windows,
          ).toJson(),
          'reason': 'UNAUTHORIZED',
          'readiness': null,
        },
      });
      expect((await reading).phase, 'failed');
      final detach = s.connection.held.singleWhere(
        (frame) => frame['operation'] == 'detach',
      );
      s.connection.stream.add(detach);
      await ram.settle();
      expect(s.controller.status.phase, 'failed');
      expect(s.controller.isLost, isFalse);
      s.connection.held.clear();
      s.connection.holdReplies = false;
      await s.close();
    },
  );
  test(
    'power Ready with foreign generation fails closed synchronously',
    () async {
      final s = Setup();
      await s.controller.start();
      s.connection.holdControls = true;
      s.controller.setSuspended(false);
      await ram.settle();
      final status = Map<String, Object?>.of(s.connection.root.status);
      status['readiness'] = {
        ...status['readiness'] as Map<String, Object?>,
        'generation': '12345678-1234-4234-9234-123456789abc',
      };
      s.connection.stream.add({'kind': 'power', 'epoch': 1, 'status': status});
      expect(s.controller.isLost, isTrue);
      expect(s.controller.status.phase, 'close-blocked');
      await ram.settle();
      expect(s.connection.starts, 1);
      expect(
        await s.connection.root.shutdown(10000000),
        HostCloseResult.closed,
      );
    },
  );
  test('same-turn power burst sends only the latest bounded intent', () async {
    final s = Setup();
    await s.controller.start();
    for (var i = 1; i <= 1000; i++) s.controller.setSuspended(i.isOdd);
    expect(s.controller.status.phase, 'resuming');
    await ram.settle();
    final frames = s.connection.sent
        .where((f) => f['kind'] == 'power')
        .toList();
    expect(frames.length, 1);
    expect(frames.single['epoch'], 1000);
    expect(frames.single['suspended'], isFalse);
    expect(s.controller.status.phase, 'ready');
    expect(s.connection.starts, 1);
    await s.close();
  });
  test(
    'new suspend immediately supersedes a pending physical resume',
    () async {
      final s = Setup();
      await s.controller.start();
      s.controller.setSuspended(true);
      await ram.settle();
      final physical = s.connection.bootstrap.setup.vault.paused =
          Completer<void>();
      s.controller.setSuspended(false);
      await ram.settle();
      s.controller.setSuspended(true);
      expect(s.connection.bootstrap.setup.host.isSuspended, isTrue);
      expect(s.controller.status.phase, 'suspending');
      s.connection.bootstrap.setup.vault.paused = null;
      physical.complete();
      await ram.settle();
      expect(s.controller.status.phase, 'suspended');
      s.controller.setSuspended(false);
      await ram.settle();
      expect(s.controller.status.phase, 'ready');
      expect(s.controller.isLost, isFalse);
      expect(s.connection.starts, 1);
      await s.close();
    },
  );
  test(
    'controller retires owners and resumes fresh owners on the same worker',
    () async {
      final s = Setup();
      await s.controller.start();
      final old = await s.controller.openOwner(Object());
      s.controller.setSuspended(true);
      expect(old.isClosed, isTrue);
      await ram.settle();
      expect(s.controller.status.phase, 'suspended');
      await expectLater(
        s.controller.openOwner(Object()),
        throwsA(isA<EngineCallFailure>()),
      );
      s.controller.setSuspended(false);
      await ram.settle();
      expect(s.controller.status.phase, 'ready');
      final fresh = await s.controller.openOwner(Object());
      expect(fresh.isClosed, isFalse);
      expect(s.connection.starts, 1);
      await s.close();
    },
  );
  test(
    'early parent intent does not spawn worker until ordinary start',
    () async {
      final s = Setup();
      s.controller.setSuspended(true);
      expect(s.connection.starts, 0);
      final starting = s.controller.start();
      await ram.settle();
      expect(s.controller.status.phase, 'suspended');
      s.controller.setSuspended(false);
      await starting;
      await ram.settle();
      expect(s.controller.status.phase, 'ready');
      await s.controller.openOwner(Object());
      expect(s.connection.starts, 1);
      await s.close();
    },
  );
  test('old metadata replies cannot overwrite a newer power epoch', () async {
    final s = Setup();
    await s.controller.start();
    s.connection.holdReplies = true;
    final pending = [
      for (var i = 0; i < 16; i++) s.controller.refreshReadiness(),
    ];
    final errors = [
      for (final future in pending)
        expectLater(
          future,
          throwsA(
            isA<EngineCallFailure>().having(
              (e) => e.code,
              'safe code',
              'NOT_READY',
            ),
          ),
        ),
    ];
    s.controller.setSuspended(true);
    expect(s.controller.status.phase, 'suspending');
    await ram.settle();
    s.connection.holdReplies = false;
    s.connection.flushReplies();
    await Future.wait(errors);
    await ram.settle();
    expect(s.controller.isLost, isFalse);
    expect(s.controller.status.phase, 'suspended');
    s.controller.setSuspended(false);
    await ram.settle();
    expect(s.controller.status.phase, 'ready');
    await s.close();
  });
  test(
    'busy startup survives cleanup without becoming a current ready status',
    () async {
      final s = Setup();
      s.connection.bootstrap.setup.lease.acquired = false;
      s.connection.bootstrap.setup.lease.isHeld = false;
      final starting = s.controller.start();
      expect((await starting).phase, 'busy');
      await ram.settle();
      expect(identical(s.controller.start(), starting), isTrue);
      expect((await s.controller.start()).phase, 'busy');
      expect(s.controller.status.phase, isNot('ready'));
      await expectLater(
        s.controller.openOwner(Object()),
        throwsA(isA<EngineCallFailure>()),
      );
      if (!s.controller.isClosed) {
        expect(await s.controller.waitForClose(), HostCloseResult.closed);
      }
      expect(s.controller.isClosed, isTrue);
      expect(s.controller.status.phase, 'closed');
      expect((await s.controller.start()).phase, 'busy');
      expect(s.connection.starts, 1);
      expect(s.connection.links, isEmpty);
    },
  );

  test(
    'invalid busy status is rejected rather than granting contender policy',
    () {
      for (final reason in [null, 'SERVICE_UNAVAILABLE', 'STORAGE_BLOCKED']) {
        expect(
          () => WorkerStatus.fromJson({
            'phase': 'busy',
            'capabilities': EngineCapabilities.unavailable(
              EnginePlatformKind.windows,
            ).toJson(),
            'reason': reason,
            'readiness': null,
          }),
          throwsA(isA<EngineCallFailure>()),
        );
      }
    },
  );

  for (final firstKind in ['shutdown', 'waitClose']) {
    for (final streamExits in [false, true]) {
      test(
        'concurrent close observers: $firstKind first, exit=$streamExits, one ACK',
        () async {
          final s = Setup();
          await s.controller.start();
          s.connection.bootstrap.closing = Completer();
          s.connection.holdReplies = true;
          s.connection.closeStreamOnAck = streamExits;
          final shutting = s.controller.shutdown();
          final waiting = s.controller.waitForClose();
          await ram.settle();
          s.connection.bootstrap.closing!.complete();
          await ram.settle();
          expect(s.connection.held.length, 2);
          final first = s.connection.held.singleWhere(
            (f) => f['operation'] == firstKind,
          );
          final second = s.connection.held.singleWhere(
            (f) => f['operation'] != firstKind,
          );
          s.connection.stream.add(first);
          expect(
            await Future.wait([shutting, waiting])
                .timeout(const Duration(seconds: 1)),
            [HostCloseResult.closed, HostCloseResult.closed],
          );
          if (!streamExits) s.connection.stream.add(second);
          await ram.settle();
          expect(s.connection.ackAttempts, 1);
          expect(s.connection.acks, 1);
          expect(s.controller.status.phase, 'closed');
          expect(s.controller.isLost, isFalse);
        },
      );
    }
  }

  test(
    'late bootstrap failure preserves an earlier UI exit deadline',
    () async {
      final s = Setup();
      s.connection.bootstrap.creating = Completer();
      final start = s.controller.start();
      final close = s.controller.shutdown();
      expect((await start).phase, 'stopping');
      s.advance(const Duration(seconds: 11));
      expect(await close, HostCloseResult.closeBlocked);
      s.connection.bootstrap.creating!.complete();
      await ram.settle();
      expect(s.connection.sent.where((f) => f['kind'] == 'shutdown').length, 1);
      expect(s.connection.sent.first['expiresAt'], 10000000);
      expect(s.connection.starts, 1);
      expect(s.controller.isClosed, isFalse);
      expect(await s.controller.waitForClose(), HostCloseResult.closed);
      expect(s.connection.bootstrap.setup.acquisitions, 0);
    },
  );
  test(
    'bad status generation cannot replace the one Host incarnation',
    () async {
      final s = Setup();
      await s.controller.start();
      s.connection.holdControls = true;
      final read = s.controller.refreshReadiness();
      read.ignore();
      final request = s.connection.sent.last;
      final status = Map<String, Object?>.of(s.connection.root.status);
      final readiness = Map<String, Object?>.of(
        status['readiness'] as Map<String, Object?>,
      );
      readiness['generation'] = '12345678-1234-4234-9234-123456789abc';
      status['readiness'] = readiness;
      s.connection.stream.add({
        'kind': 'reply',
        'sequence': request['sequence'],
        'operation': 'readiness',
        'result': status,
      });
      await expectLater(read, core.failure('SERVICE_UNAVAILABLE'));
      expect(s.controller.isLost, isTrue);
      expect((await s.controller.start()).phase, 'close-blocked');
      expect(s.connection.starts, 1);
      expect(
        await s.connection.root.shutdown(10000000),
        HostCloseResult.closed,
      );
    },
  );

  test(
    'one shared startup and real bound owner call with no owner DTO',
    () async {
      final s = Setup();
      final first = s.controller.start();
      expect(identical(first, s.controller.start()), isTrue);
      expect((await first).phase, 'ready');
      final binding = Object();
      final opening = s.controller.openOwner(binding);
      expect(identical(opening, s.controller.openOwner(binding)), isTrue);
      final gateway = await opening;
      final result = await gateway.call('settings.get', {}, requestId: core.id);
      expect(result, core.settings());
      expect(s.connection.starts, 1);
      expect(s.connection.sent.single['binding'], isA<Capability>());
      expect(s.connection.sent.single.containsKey('role'), isFalse);
      await s.controller.detachOwner(binding);
      expect(s.controller.status.phase, 'ready');
      expect(s.connection.bootstrap.setup.lease.closes, 0);
      await s.close();
    },
  );
  test(
    'eight UI bindings, detached slot reusable with a fresh VM capability',
    () async {
      final s = Setup();
      await s.controller.start();
      final bindings = List.generate(8, (_) => Object());
      for (final b in bindings) {
        await s.controller.openOwner(b);
      }
      await expectLater(
        s.controller.openOwner(Object()),
        core.failure('RESOURCE_LIMIT'),
      );
      final old = s.connection.links.first.binding;
      await s.controller.detachOwner(bindings.first);
      await s.controller.openOwner(bindings.first);
      expect(s.connection.links.last.binding, isNot(old));
      await s.close();
    },
  );
  test(
    'pending attach detach has no proxy-close dependency before binding exists',
    () async {
      final s = Setup();
      await s.controller.start();
      s.connection.bootstrap.setup.runtime.paused = Completer();
      final binding = Object(), opening = s.controller.openOwner(binding);
      opening.ignore();
      await ram.settle();
      await s.controller.detachOwner(binding);
      s.connection.bootstrap.setup.runtime.paused!.complete();
      await expectLater(opening, core.failure('UNAUTHORIZED'));
      expect(s.connection.links.single.disposed, isTrue);
      await s.close();
    },
  );
  test(
    'original attach deadline includes queued delivery and rejects late result',
    () async {
      final s = Setup();
      await s.controller.start();
      s.connection.holdControls = true;
      final opening = s.controller.openOwner(Object());
      opening.ignore();
      await ram.settle();
      s.advance(const Duration(seconds: 6), fire: false);
      s.connection.flushControls();
      await ram.settle();
      await expectLater(opening, core.failure('TIMEOUT'));
      s.connection.holdControls = false;
      s.connection.flushControls();
      await ram.settle();
      expect(s.connection.bootstrap.setup.resources.services.prepared, 0);
      await s.close();
    },
  );
  test(
    'logical readiness timeouts retain16controls; exit has reserved admission',
    () async {
      final s = Setup();
      await s.controller.start();
      s.connection.holdControls = true;
      final reads = List.generate(16, (_) => s.controller.refreshReadiness());
      for (final f in reads) {
        f.ignore();
      }
      s.advance(const Duration(seconds: 6));
      for (final f in reads) {
        await expectLater(f, core.failure('TIMEOUT'));
      }
      await expectLater(
        s.controller.refreshReadiness(),
        core.failure('RESOURCE_LIMIT'),
      );
      final close = s.controller.shutdown();
      expect(s.connection.queued.last['kind'], 'shutdown');
      expect(s.connection.sent.last['expiresAt'], 16000000);
      s.connection.holdControls = false;
      s.connection.flushControls();
      expect(await close, HostCloseResult.closed);
    },
  );
  test(
    'delayed started cannot reset30s startup; shutdown starts once',
    () async {
      final s = Setup();
      s.connection.holdReplies = true;
      final starting = s.controller.start();
      await ram.settle();
      s.advance(const Duration(seconds: 31), fire: false);
      s.connection.holdReplies = false;
      s.connection.flushReplies();
      expect((await starting).reason, 'TIMEOUT');
      expect(await s.controller.shutdown(), HostCloseResult.closed);
      expect(s.connection.starts, 1);
      expect(s.connection.sent.where((f) => f['kind'] == 'shutdown').length, 1);
    },
  );
  test(
    'exit before start still establishes one observed worker lifecycle',
    () async {
      final s = Setup();
      expect(await s.controller.shutdown(), HostCloseResult.closed);
      expect(s.controller.isLost, isFalse);
      expect(s.connection.starts, 1);
      expect((await s.controller.start()).phase, 'closed');
      expect(s.connection.starts, 1);
    },
  );
  test(
    'worker error stops every proxy; no restart or native close inference',
    () async {
      final s = Setup();
      await s.controller.start();
      final gateway = await s.controller.openOwner(Object());
      s.connection.stream.addError(StateError('private worker details'));
      expect(s.controller.isLost, isTrue);
      expect(gateway.isClosed, isTrue);
      expect(await s.controller.shutdown(), HostCloseResult.closeBlocked);
      expect(await s.controller.waitForClose(), HostCloseResult.closeBlocked);
      expect(
        (await s.controller.start()).phase,
        'close-blocked',
      ); // Current failure, no stale Ready or new launch.
      expect(s.controller.status.phase, 'close-blocked');
      expect(s.connection.starts, 1);
      expect(s.connection.bootstrap.setup.lease.closes, 0);
      // RAM fixture teardown uses the original Root, never a replacement.
      expect(
        await s.connection.root.shutdown(10000000),
        HostCloseResult.closed,
      );
    },
  );
  test(
    'expired queued exit keeps lease until explicit same-root wait',
    () async {
      final s = Setup();
      await s.controller.start();
      s.connection.holdControls = true;
      final close = s.controller.shutdown();
      s.advance(const Duration(seconds: 11));
      expect(await close, HostCloseResult.closeBlocked);
      s.connection.holdControls = false;
      s.connection.flushControls();
      await ram.settle();
      expect(s.connection.bootstrap.setup.lease.closes, 0);
      expect(await s.controller.waitForClose(), HostCloseResult.closed);
      expect(s.connection.bootstrap.setup.lease.closes, 1);
      expect(s.connection.starts, 1);
    },
  );
  test('late physical closed reply acknowledged without overwriting timed-out observer', () async {
    final s = Setup();
    await s.controller.start();
    s.connection.holdReplies = true;
    final close = s.controller.shutdown();
    await ram.settle();
    expect(s.connection.bootstrap.setup.lease.closes, 1);
    expect(s.controller.isClosed, isFalse);
    s.advance(const Duration(seconds: 11));
    expect(await close, HostCloseResult.closeBlocked);
    s.connection.holdReplies = false;
    s.connection.flushReplies();
    expect(s.controller.isClosed, isTrue);
    expect(s.connection.acks, 1);
    expect(await s.controller.waitForClose(), HostCloseResult.closed);
  });
  test(
    'uncertain control send is never retried and does not prove physical close',
    () async {
      final s = Setup();
      await s.controller.start();
      s.connection.failSend = true;
      expect(await s.controller.shutdown(), HostCloseResult.closeBlocked);
      expect(s.controller.isLost, isTrue);
      expect(s.connection.sent.where((f) => f['kind'] == 'shutdown').length, 1);
      await ram.settle();
    },
  );
  test('wrong response correlation permanently retires controller', () async {
    final s = Setup();
    await s.controller.start();
    s.connection.stream.add({
      'kind': 'reply',
      'sequence': 999,
      'operation': 'shutdown',
      'result': 'closed',
    });
    expect(s.controller.isLost, isTrue);
    expect(s.controller.isClosed, isFalse);
    expect(await s.controller.shutdown(), HostCloseResult.closeBlocked);
    expect(await s.connection.root.shutdown(10000000), HostCloseResult.closed);
  });
}
