import 'package:serverdeck_engine/hosting/capability_snapshot.dart';

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:serverdeck_engine/hosting/engine_host.dart';
import 'package:serverdeck_engine/hosting/worker_root.dart';
import 'package:serverdeck_engine/platform/ports.dart';
import 'package:test/test.dart';

import 'authority_test.dart' as ram;
import 'engine_host_test.dart' as host;

final class Bootstrap implements EngineBootstrap {
  @override
  EnginePlatformKind platformKind = EnginePlatformKind.windows;
  final setup = host.Setup()..externallyManagedShutdown = true;
  Completer<void>? creating, closing;
  int creates = 0, closes = 0;
  Future<void>? _closed;
  Bootstrap() {
    setup.disposeRuntime = close;
  }
  @override
  Future<EngineHost> create(EngineClock clock) async {
    creates++;
    await creating?.future;
    setup.runtime.gate.generation = setup.host.generation;
    return setup.host;
  }

  @override
  Future<void> close() => _closed ??= () async {
    closes++;
    await closing?.future;
  }();
}

final class Replies implements WorkerReplyPorts {
  final frames = <Object, List<Map<String, Object?>>>{};
  @override
  bool accepts(Object? address) =>
      address != null && frames.containsKey(address);
  @override
  void send(Object address, Map<String, Object?> frame) =>
      frames[address]!.add(frame);
  Object address() {
    final value = Object();
    frames[value] = [];
    return value;
  }
}

final class Setup {
  final bootstrap = Bootstrap(), control = Capability(), replies = Replies();
  final frames = <Map<String, Object?>>[];
  int sequence = 0, acknowledgements = 0;
  final timers = <({int at, void Function() fire, bool Function() active})>[];
  void Function() schedule(Duration duration, void Function() action) {
    var active = true;
    timers.add((
      at:
          bootstrap.setup.clock.elapsed.inMicroseconds +
          duration.inMicroseconds,
      fire: action,
      active: () => active,
    ));
    return () => active = false;
  }

  void advance(Duration duration) {
    bootstrap.setup.clock.elapsed += duration;
    for (final timer in timers.toList()) {
      if (timer.active() &&
          timer.at <= bootstrap.setup.clock.elapsed.inMicroseconds)
        timer.fire();
    }
  }

  late final root = EngineWorkerRoot(
    control: control,
    bootstrap: bootstrap,
    replies: replies,
    clock: bootstrap.setup.clock,
    schedule: schedule,
    sendControl: frames.add,
    closedAcknowledged: () => acknowledgements++,
  );
  Future<Map<String, Object?>> start() => root.start(30000000);
  void power(int epoch, bool suspended, {int expiresAt = 30000000}) {
    root.handle([
      control,
      {
        'kind': 'power',
        'epoch': epoch,
        'suspended': suspended,
        'expiresAt': expiresAt,
      },
    ]);
  }

  int send(String kind, [Map<String, Object?> fields = const {}]) {
    final seq = ++sequence;
    root.handle([
      control,
      {'kind': kind, 'sequence': seq, ...fields},
    ]);
    return seq;
  }

  Map<String, Object?> reply(int seq) =>
      frames.singleWhere((f) => f['sequence'] == seq);
  Future<Capability> attach() async {
    final cap = Capability();
    final seq = send('attach', {
      'binding': cap,
      'replies': replies.address(),
      'expiresAt': 5000000,
    });
    await ram.settle();
    expect(reply(seq).containsKey('error'), isFalse);
    return cap;
  }

  Future<void> close() async {
    expect(await root.shutdown(10000000), HostCloseResult.closed);
  }
}

void main() {
  test(
    'Root rejects a Bootstrap and Host platform mismatch before Host startup',
    () async {
      final s = Setup();
      s.bootstrap.platformKind = EnginePlatformKind.linux;
      final result = await s.start();
      expect(result['phase'], 'failed');
      expect(result['reason'], 'INCOMPATIBLE');
      final caps = EngineCapabilities.fromJson(result['capabilities']);
      expect(caps.platform, EnginePlatformKind.linux);
      expect(caps.coreUsable, isFalse);
      expect(s.bootstrap.setup.acquisitions, 0);
      expect(s.bootstrap.setup.vault.probes, 0);
      await s.close();
    },
  );
  test(
    'resume deadline closes while physical suspension still owns the lease',
    () async {
      final s = Setup();
      await s.start();
      final physical = s.bootstrap.setup.resources.servicesSuspending =
          Completer<void>();
      s.power(1, true);
      await ram.settle();
      s.power(2, false);
      await ram.settle();
      expect(s.root.status['phase'], 'resuming');
      s.advance(const Duration(seconds: 30));
      await ram.settle();
      expect(s.root.status['phase'], 'stopping');
      expect(s.root.status['reason'], 'TIMEOUT');
      expect(s.bootstrap.setup.lease.isHeld, isTrue);
      expect(s.bootstrap.creates, 1);
      physical.complete();
      expect(await s.root.waitForClose(), HostCloseResult.closed);
      expect(s.bootstrap.setup.lease.isHeld, isFalse);
    },
  );
  test(
    'early power does not erase confirmed secondary-instance busy outcome',
    () async {
      final s = Setup();
      s.bootstrap.setup.lease.acquired = false;
      s.bootstrap.setup.lease.isHeld = false;
      s.power(1, true);
      expect((await s.start())['phase'], 'busy');
      await ram.settle();
      expect(
        s.bootstrap.setup.resources.events,
        isNot(contains('workspace.open')),
      );
      await s.close();
    },
  );
  test(
    'expired early resume retires startup without waiting for its pause',
    () async {
      final s = Setup();
      s.power(1, true);
      final starting = s.start();
      await ram.settle();
      s.power(2, false, expiresAt: 1);
      s.bootstrap.setup.clock.elapsed = const Duration(microseconds: 2);
      await ram.settle();
      expect((await starting)['phase'], isNot('ready'));
      expect(
        s.root.status['phase'],
        anyOf('stopping', 'close-blocked', 'closed'),
      );
      expect(await s.root.waitForClose(), HostCloseResult.closed);
    },
  );
  test(
    'power intent fences admission even with16 ordinary controls in flight',
    () async {
      final s = Setup();
      await s.start();
      for (var i = 0; i < 16; i++) {
        s.send('readiness');
      }
      s.power(1, true);
      expect(s.bootstrap.setup.host.isSuspended, isTrue);
      expect(s.root.status['phase'], 'suspending');
      final seq = s.send('attach', {
        'binding': Capability(),
        'replies': s.replies.address(),
        'expiresAt': 5000000,
      });
      await ram.settle();
      expect(s.reply(seq)['error'], anyOf('NOT_READY', 'RESOURCE_LIMIT'));
      expect(s.root.status['phase'], 'suspended');
      s.power(2, false);
      await ram.settle();
      expect(s.root.status['phase'], 'ready');
      expect(s.bootstrap.creates, 1);
      await s.close();
    },
  );
  test('early intent pauses same initial Host and resume works without second startup', () async {
    final s = Setup();
    s.power(1, true);
    expect(s.bootstrap.creates, 0);
    var acknowledged = false;
    final starting = s.start().then((value) {
      acknowledged = true;
      return value;
    });
    await ram.settle();
    expect(acknowledged, isFalse);
    expect(s.root.status['phase'], 'suspended');
    s.power(2, false);
    await starting;
    await ram.settle();
    expect(s.root.status['phase'], 'ready');
    expect(s.bootstrap.creates, 1);
    expect(s.bootstrap.setup.acquisitions, 1);
    await s.close();
  });
  test(
    'resume alone fences missed suspend and stale epoch cannot undo it',
    () async {
      final s = Setup();
      await s.start();
      s.bootstrap.setup.vault.paused = Completer<void>();
      s.power(2, false);
      expect(s.bootstrap.setup.host.isSuspended, isTrue);
      s.power(1, true);
      await ram.settle();
      s.bootstrap.setup.vault.paused!.complete();
      s.bootstrap.setup.vault.paused = null;
      await ram.settle();
      expect(s.root.status['phase'], 'ready');
      expect(s.bootstrap.setup.vault.probes, 2);
      await s.close();
    },
  );
  test(
    'shutdown wakes an early suspended startup and owns actual close',
    () async {
      final s = Setup();
      s.power(1, true);
      final starting = s.start();
      await ram.settle();
      expect(s.root.status['phase'], 'suspended');
      expect(await s.root.shutdown(10000000), HostCloseResult.closed);
      expect((await starting)['phase'], isNot('ready'));
      expect(s.bootstrap.setup.lease.closes, 1);
    },
  );
  test('busy Host cannot attach an owner or open services', () async {
    final s = Setup();
    s.bootstrap.setup.lease.acquired = false;
    s.bootstrap.setup.lease.isHeld = false;
    final result = await s.start();
    expect(result['phase'], 'busy');
    expect(result['reason'], 'STORAGE_BLOCKED');
    final seq = s.send('attach', {
      'binding': Capability(),
      'replies': s.replies.address(),
      'expiresAt': 5000000,
    });
    await ram.settle();
    expect(s.reply(seq)['error'], 'NOT_READY');
    expect(
      s.bootstrap.setup.resources.events,
      isNot(contains('workspace.open')),
    );
    expect(
      s.bootstrap.setup.resources.events,
      isNot(contains('services.open')),
    );
    await s.close();
  });

  test('startup is shared and ready follows recovered services', () async {
    final s = Setup();
    s.bootstrap.setup.resources.servicesOpening = Completer();
    final starting = s.start();
    expect(identical(starting, s.start()), isTrue);
    await ram.settle();
    expect(s.root.status['phase'], 'starting');
    s.bootstrap.setup.resources.servicesOpening!.complete();
    expect((await starting)['phase'], 'ready');
    expect(s.bootstrap.creates, 1);
    await s.close();
  });

  test(
    'unknown VM capability cannot attach and discarded bytes are wiped',
    () async {
      final s = Setup();
      await s.start();
      final bytes = Uint8List.fromList([1, 2, 3]);
      s.root.handle([
        Capability(),
        {'kind': 'attach', 'body': bytes},
      ]);
      expect(bytes, [0, 0, 0]);
      expect(s.frames, isEmpty);
      expect(s.bootstrap.setup.runtime.proofs, greaterThan(0));
      await s.close();
    },
  );

  test('window capability cannot issue root lifecycle commands', () async {
    final s = Setup();
    await s.start();
    final cap = await s.attach();
    s.root.handle([
      cap,
      {'kind': 'shutdown', 'sequence': 1, 'expiresAt': 10000000},
    ]);
    await ram.settle();
    expect(s.bootstrap.setup.host.isClosed, isFalse);
    expect(s.bootstrap.setup.lease.closes, 0);
    await s.close();
  });

  test(
    'eight windows bounded and normal close frees a slot without stopping Host',
    () async {
      final s = Setup();
      await s.start();
      final caps = <Capability>[];
      for (var i = 0; i < 8; i++) {
        caps.add(await s.attach());
      }
      final ninth = s.send('attach', {
        'binding': Capability(),
        'replies': s.replies.address(),
        'expiresAt': 5000000,
      });
      await ram.settle();
      expect(s.reply(ninth)['error'], 'RESOURCE_LIMIT');
      s.root.handle([
        caps.first,
        {'kind': 'close', 'generation': s.bootstrap.setup.host.generation},
      ]);
      await ram.settle();
      expect(s.root.status['phase'], 'ready');
      await s.attach();
      expect(s.bootstrap.setup.lease.closes, 0);
      await s.close();
    },
  );

  test(
    'same pending binding shares open; different reply route is rejected',
    () async {
      final s = Setup();
      await s.start();
      s.bootstrap.setup.runtime.paused = Completer();
      final cap = Capability(), route = s.replies.address();
      final first = s.send('attach', {
        'binding': cap,
        'replies': route,
        'expiresAt': 5000000,
      });
      final second = s.send('attach', {
        'binding': cap,
        'replies': route,
        'expiresAt': 5000000,
      });
      final wrong = s.send('attach', {
        'binding': cap,
        'replies': s.replies.address(),
        'expiresAt': 5000000,
      });
      await ram.settle();
      expect(s.reply(wrong)['error'], 'UNAUTHORIZED');
      s.bootstrap.setup.runtime.paused!.complete();
      await ram.settle();
      expect(s.reply(first).containsKey('error'), isFalse);
      expect(s.reply(second).containsKey('error'), isFalse);
      await s.close();
    },
  );

  test(
    'detach cancels pending attachment and retains physical cleanup',
    () async {
      final s = Setup();
      await s.start();
      s.bootstrap.setup.runtime.paused = Completer();
      final cap = Capability();
      final attach = s.send('attach', {
        'binding': cap,
        'replies': s.replies.address(),
        'expiresAt': 5000000,
      });
      await ram.settle();
      final detach = s.send('detach', {'binding': cap});
      await ram.settle();
      expect(s.reply(detach)['result'], isTrue);
      expect(s.bootstrap.setup.lease.closes, 0);
      s.bootstrap.setup.runtime.paused!.complete();
      await ram.settle();
      expect(s.reply(attach).containsKey('error'), isTrue);
      expect(s.reply(detach)['result'], isTrue);
      expect(s.root.status['phase'], 'ready');
      await s.close();
    },
  );

  test('startup original deadline includes delayed bootstrap', () async {
    final s = Setup();
    s.bootstrap.creating = Completer();
    final start = s.start();
    s.bootstrap.setup.clock.elapsed = const Duration(seconds: 31);
    s.bootstrap.creating!.complete();
    expect((await start)['reason'], 'TIMEOUT');
    expect(
      s.bootstrap.setup.resources.events,
      isNot(contains('workspace.open')),
    );
    expect(await s.root.shutdown(41000000), HostCloseResult.closed);
  });

  test(
    'shutdown waits partial bootstrap; original expired deadline retains lease',
    () async {
      final s = Setup();
      s.bootstrap.setup.resources.servicesOpening = Completer();
      final start = s.start();
      await ram.settle();
      s.bootstrap.setup.clock.elapsed = const Duration(seconds: 11);
      final close = s.root.shutdown(10000000);
      expect((await start)['phase'], 'stopping');
      expect(await close, HostCloseResult.closeBlocked);
      expect(s.bootstrap.setup.lease.closes, 0);
      s.bootstrap.setup.resources.servicesOpening!.complete();
      await ram.settle();
      expect(s.bootstrap.setup.lease.closes, 0);
      expect(await s.root.waitForClose(), HostCloseResult.closed);
      expect(s.bootstrap.setup.lease.closes, 1);
    },
  );

  test(
    'runtime metadata drains before lease; closed needs parent acknowledgement',
    () async {
      final s = Setup();
      s.bootstrap.closing = Completer();
      await s.start();
      final seq = s.send('shutdown', {'expiresAt': 10000000});
      await ram.settle();
      expect(s.bootstrap.closes, 1);
      expect(s.bootstrap.setup.lease.closes, 0);
      expect(s.frames, isEmpty);
      s.bootstrap.closing!.complete();
      await ram.settle();
      expect(s.reply(seq)['result'], 'closed');
      expect(s.acknowledgements, 0);
      s.root.handle([
        Capability(),
        {'kind': 'ackClosed', 'sequence': seq},
      ]);
      expect(s.acknowledgements, 0);
      s.root.handle([
        s.control,
        {'kind': 'ackClosed', 'sequence': seq},
      ]);
      expect(s.acknowledgements, 1);
      s.root.handle([
        s.control,
        {'kind': 'ackClosed', 'sequence': seq},
      ]);
      expect(s.acknowledgements, 1);
    },
  );

  test('replayed control cannot create a second binding', () async {
    final s = Setup();
    await s.start();
    final cap = await s.attach();
    final before = s.bootstrap.setup.runtime.proofs;
    s.root.handle([
      s.control,
      {
        'kind': 'attach',
        'sequence': 1,
        'binding': cap,
        'replies': s.replies.address(),
        'expiresAt': 5000000,
      },
    ]);
    await ram.settle();
    expect(s.frames.last['error'], 'VALIDATION');
    expect(s.bootstrap.setup.runtime.proofs, before);
    await s.close();
  });
}
