import 'package:serverdeck_engine/platform/ports.dart';
import 'package:serverdeck_engine/hosting/capability_snapshot.dart';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck_engine/hosting/engine_host.dart';
import 'package:serverdeck_engine/hosting/worker_controller.dart';
import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/models.dart';

import '../lib/platform/desktop_lifecycle.dart';

WorkerStatus status([String phase = 'ready']) => WorkerStatus.fromJson({
  'phase': phase,
  'capabilities':
      (phase == 'ready'
              ? EngineCapabilities(
                  platform: EnginePlatformKind.windows,
                  storageReady: true,
                  vaultStatus: VaultAccess.available,
                  directSsh: false,
                  localMcpBridge: false,
                  trayAvailable: false,
                  backgroundPolicy: EngineBackgroundPolicy.desktopWhileRunning,
                  reasonCodes: const [],
                )
              : EngineCapabilities.unavailable(EnginePlatformKind.windows))
          .toJson(),
  'reason': const {'suspending', 'suspended', 'resuming'}.contains(phase)
      ? 'NOT_READY'
      : null,
  'readiness': phase == 'ready'
      ? {
          'state': 'ready',
          'reason': null,
          'product': 'serverdeck-next',
          'apiMajor': 1,
          'apiMinor': 1,
          'workspaceSlot': 'default',
          'workspaceId': '12345678-1234-4234-9234-123456789abc',
          'generation': '12345678-1234-4234-9234-123456789abd',
          'storageSchema': 3,
          'features': {
            'profiles': true,
            'ssh': false,
            'jobs': false,
            'backend': false,
            'mcp': false,
          },
          'clientPlatform': 'windows-x64',
        }
      : null,
});

final class Engine implements DesktopEngineControl {
  @override
  EnginePlatformKind get platformKind => EnginePlatformKind.windows;
  bool tray = false;
  @override
  void setTrayAvailable(bool available) {
    tray = available;
    current = current.withTray(available);
  }

  @override
  void setSuspended(bool suspended) {
    powerIntents.add(suspended);
    current = status(suspended ? 'suspending' : 'resuming').withTray(tray);
  }

  final powerIntents = <bool>[];
  int starts = 0, closes = 0, waits = 0;
  int? jobs = 0;
  HostCloseResult outcome = HostCloseResult.closed;
  WorkerStatus? startResult;
  WorkerStatus current = status();
  Completer<DesktopEngineStatus>? sampling;
  int samples = 0, activeSamples = 0, maxActiveSamples = 0;
  Completer<WorkerStatus>? starting;
  final waiting = Completer<HostCloseResult>();
  @override
  Future<WorkerStatus> start() async {
    starts++;
    return await (starting?.future ?? Future.value(startResult ?? status()));
  }

  @override
  Future<DesktopEngineStatus> refreshDesktopStatus() async {
    samples++;
    activeSamples++;
    if (activeSamples > maxActiveSamples) maxActiveSamples = activeSamples;
    try {
      return await (sampling?.future ??
          Future.value(DesktopEngineStatus(current, 0, jobs)));
    } finally {
      activeSamples--;
    }
  }

  @override
  Future<HostCloseResult> shutdown() async {
    closes++;
    return outcome;
  }

  @override
  Future<HostCloseResult> waitForClose() {
    waits++;
    return waiting.future;
  }
}

final class Platform implements DesktopPlatform {
  final stream = StreamController<DesktopAction>.broadcast(sync: true);
  final calls = <String>[];
  final warnings = <int?>[];
  bool tray = true, hideWorks = true, fallbackExit = false, allowExit = true;
  Completer<bool>? initializing, hiding;
  Completer<BlockedChoice>? blockedPause;
  BlockedChoice blocked = BlockedChoice.stay;
  int finishes = 0, forces = 0;
  @override
  Stream<DesktopAction> get events => stream.stream;
  @override
  Future<bool> initialize() {
    calls.add('initialize');
    return initializing?.future ?? Future.value(tray);
  }

  @override
  Future<bool> hide() {
    calls.add('hide');
    return hiding?.future ?? Future.value(hideWorks);
  }

  @override
  Future<void> show() async {
    calls.add('show');
  }

  @override
  Future<void> update(DesktopEngineStatus status) async {
    calls.add('status:${status.status.phase}');
  }

  @override
  Future<bool> fallbackClose() async {
    calls.add('fallback');
    return fallbackExit;
  }

  @override
  Future<bool> confirmExit(int? jobs) async {
    warnings.add(jobs);
    return allowExit;
  }

  @override
  Future<BlockedChoice> blockedClose() async {
    calls.add('blocked');
    return await (blockedPause?.future ?? Future.value(blocked));
  }

  @override
  Future<void> finishExit() async {
    finishes++;
  }

  @override
  Future<void> forceExit() async {
    forces++;
  }
}

final class Setup {
  final engine = Engine(), platform = Platform();
  final timers = <void Function()>[];
  late final lifetime = DesktopLifetime(
    engine: engine,
    platform: platform,
    schedule: (_, action) => timers.add(action),
  );
}

Future<void> settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('tray source changes project actual availability and fallback hides nothing', () async {
    final s = Setup();
    await s.lifetime.initialize();
    expect(s.engine.tray, isTrue);
    await s.lifetime.handle(DesktopAction.trayUnavailable);
    expect(s.engine.tray, isFalse);
    expect(s.lifetime.view.visible, isTrue);
    await s.lifetime.handle(DesktopAction.trayAvailable);
    expect(s.engine.tray, isTrue);
    s.platform.hideWorks = false;
    await s.lifetime.closeWindow();
    expect(s.engine.tray, isFalse);
    await s.lifetime.exit();
  });
  test(
    'late initialize failure cannot withdraw a newer real tray recovery',
    () async {
      final s = Setup();
      s.platform.initializing = Completer<bool>();
      final initializing = s.lifetime.initialize();
      await s.lifetime.handle(DesktopAction.trayAvailable);
      s.platform.initializing!.completeError(
        StateError('RAM_INITIALIZE_FAILURE'),
      );
      await initializing;
      expect(s.lifetime.trayAvailable, isTrue);
      expect(s.engine.tray, isTrue);
      await s.lifetime.exit();
    },
  );
  test(
    'power during desktop initialize is recorded before ordinary start',
    () async {
      final s = Setup();
      s.platform.initializing = Completer<bool>();
      final initializing = s.lifetime.initialize();
      s.platform.stream.add(DesktopAction.suspend);
      expect(s.engine.powerIntents, [true]);
      expect(s.engine.starts, 0);
      expect(s.lifetime.view.epoch, 1);
      s.platform.initializing!.complete(true);
      await initializing;
      await settle();
      expect(s.engine.starts, 1);
      expect(s.platform.calls, contains('status:suspending'));
      await s.lifetime.exit();
    },
  );
  for (final hidden in [false, true]) {
    test(
      'restore retires the visible or hidden client once: hidden=$hidden',
      () async {
        final s = Setup();
        await s.lifetime.initialize();
        await settle();
        s.lifetime.rememberSection(DesktopSection.settings);
        if (hidden) await s.lifetime.closeWindow();
        final old = s.lifetime.view.epoch;
        await s.lifetime.handle(DesktopAction.suspend);
        await s.lifetime.handle(DesktopAction.resume);
        await settle();
        expect(s.lifetime.view.epoch, old + 2);
        expect(s.lifetime.view.visible, !hidden);
        s.engine.current = status();
        s.timers.removeAt(0)();
        await settle();
        expect(s.lifetime.view.epoch, old + 3);
        expect(s.lifetime.view.section, DesktopSection.settings);
        expect(s.lifetime.view.visible, !hidden);
        s.timers.removeAt(0)();
        await settle();
        expect(s.lifetime.view.epoch, old + 3);
        expect(s.engine.starts, 1);
        expect(s.engine.closes, 0);
        expect(s.engine.powerIntents, [true, false]);
        await s.lifetime.exit();
      },
    );
  }
  test(
    'stale poll cannot restore UI and power bursts keep one sample owner',
    () async {
      final s = Setup();
      final physical = s.engine.sampling = Completer<DesktopEngineStatus>();
      await s.lifetime.initialize();
      for (var i = 1; i <= 1000; i++) {
        await s.lifetime.handle(
          i.isOdd ? DesktopAction.suspend : DesktopAction.resume,
        );
      }
      expect(s.engine.samples, 1);
      expect(s.lifetime.view.epoch, 1000);
      s.engine.sampling = null;
      physical.complete(DesktopEngineStatus(status(), 0, 0));
      await settle();
      expect(s.engine.samples, 2);
      expect(s.engine.maxActiveSamples, 1);
      expect(s.platform.calls, isNot(contains('status:ready')));
      expect(s.lifetime.view.epoch, 1000);
      expect(s.timers.length, 1);
      s.engine.current = status();
      s.timers.removeAt(0)();
      await settle();
      expect(s.lifetime.view.epoch, 1001);
      await s.lifetime.exit();
    },
  );
  test('power callbacks cannot reopen an exiting or finished app', () async {
    for (final blocked in [false, true]) {
      final s = Setup();
      s.engine.outcome = blocked
          ? HostCloseResult.closeBlocked
          : HostCloseResult.closed;
      await s.lifetime.initialize();
      await settle();
      await s.lifetime.exit();
      final epoch = s.lifetime.view.epoch;
      await s.lifetime.handle(DesktopAction.suspend);
      await s.lifetime.handle(DesktopAction.resume);
      expect(s.engine.powerIntents, isEmpty);
      expect(s.lifetime.view.epoch, epoch);
      expect(s.engine.closes, 1);
      expect(s.engine.starts, 1);
    }
  });
  WorkerStatus busy() => WorkerStatus.fromJson({
    'phase': 'busy',
    'capabilities': EngineCapabilities.unavailable(EnginePlatformKind.windows)
        .toJson(),
    'reason': 'STORAGE_BLOCKED',
    'readiness': TrustedReadiness(
      state: ReadinessState.storageBlocked,
      generation: '12345678-1234-4234-9234-123456789abc',
      features: const OperationalFeatures(),
    ).toJson(),
  });

  test(
    'busy contender close exits itself and preserves cleanup barrier',
    () async {
      final s = Setup();
      s.engine.startResult = busy();
      s.engine.outcome = HostCloseResult.closeBlocked;
      await s.lifetime.initialize();
      await settle();
      await s.lifetime.closeWindow();
      expect(s.engine.closes, 1);
      expect(s.platform.calls, isNot(contains('hide')));
      expect(s.platform.warnings, isEmpty);
      expect(s.platform.calls, contains('blocked'));
      expect(s.platform.finishes, 0);
      expect(s.platform.forces, 0);
      s.platform.blocked = BlockedChoice.wait;
      await s.lifetime.exit();
      s.engine.waiting.complete(HostCloseResult.closed);
      await settle();
      expect(s.platform.finishes, 1);
    },
  );

  test(
    'late busy acquisition restores an early hidden conflict window',
    () async {
      final s = Setup();
      s.engine.starting = Completer<WorkerStatus>();
      await s.lifetime.initialize();
      await s.lifetime.closeWindow();
      expect(s.lifetime.view.visible, isFalse);
      s.engine.starting!.complete(busy());
      await settle();
      expect(s.lifetime.view.visible, isTrue);
      await s.lifetime.closeWindow();
      expect(s.platform.finishes, 1);
      expect(s.platform.warnings, isEmpty);
      expect(s.engine.starts, 1);
    },
  );

  test(
    'physical wait completion never destroys a native modal prompt in flight',
    () async {
      final s = Setup();
      s.engine.outcome = HostCloseResult.closeBlocked;
      s.platform.blocked = BlockedChoice.wait;
      await s.lifetime.exit();
      s.platform.blockedPause = Completer();
      final prompt = s.lifetime.exit();
      await settle();
      s.engine.waiting.complete(HostCloseResult.closed);
      await settle();
      expect(s.platform.finishes, 0);
      s.platform.blockedPause!.complete(BlockedChoice.stay);
      await prompt;
      expect(s.platform.finishes, 1);
      expect(s.platform.forces, 0);
    },
  );

  test(
    'CloseBlocked without tray keeps Force reachable from window close',
    () async {
      final s = Setup();
      s.platform.tray = false;
      s.engine.outcome = HostCloseResult.closeBlocked;
      await s.lifetime.exit();
      expect(s.platform.forces, 0);
      s.platform.blocked = BlockedChoice.force;
      await s.lifetime.closeWindow();
      expect(s.platform.forces, 1);
      expect(s.platform.finishes, 0);
    },
  );

  test('recreated tray restores future hide without replacing engine or auto-hiding', () async {
    final s = Setup();
    s.platform.tray = false;
    await s.lifetime.initialize();
    await s.lifetime.handle(DesktopAction.trayAvailable);
    expect(s.lifetime.trayAvailable, isTrue);
    expect(s.lifetime.view.visible, isTrue);
    await s.lifetime.closeWindow();
    expect(s.lifetime.view.visible, isFalse);
    expect(s.engine.starts, 1);
    expect(s.engine.closes, 0);
  });

  test('close hides only after tray succeeds; engine and accepted work remain alive', () async {
    final s = Setup();
    await s.lifetime.initialize();
    await s.lifetime.closeWindow();
    expect(
      s.platform.calls.indexOf('initialize'),
      lessThan(s.platform.calls.indexOf('hide')),
    );
    expect(s.lifetime.view.visible, isFalse);
    expect(s.engine.closes, 0);
    expect(s.platform.finishes, 0);
    await s.lifetime.handle(DesktopAction.open);
    expect(s.lifetime.view.visible, isTrue);
    expect(s.engine.starts, 1);
  });
  test(
    'servers/settings restore same app/window and navigation requests advance',
    () async {
      final s = Setup();
      await s.lifetime.initialize();
      await s.lifetime.closeWindow();
      await s.lifetime.handle(DesktopAction.settings);
      expect(s.lifetime.view.section, DesktopSection.settings);
      final nav = s.lifetime.view.navigationEpoch;
      s.lifetime.rememberSection(DesktopSection.software);
      await s.lifetime.handle(DesktopAction.open);
      expect(s.lifetime.view.section, DesktopSection.software);
      expect(s.lifetime.view.navigationEpoch, nav);
      await s.lifetime.handle(DesktopAction.servers);
      expect(s.lifetime.view.section, DesktopSection.servers);
      expect(s.lifetime.view.navigationEpoch, greaterThan(nav));
      expect(s.engine.starts, 1);
    },
  );
  test('tray absent leaves usable window and Stay never closes Host', () async {
    final s = Setup();
    s.platform.tray = false;
    await s.lifetime.initialize();
    await s.lifetime.closeWindow();
    expect(s.platform.calls, contains('fallback'));
    expect(s.platform.calls, isNot(contains('hide')));
    expect(s.lifetime.view.visible, isTrue);
    expect(s.engine.closes, 0);
  });
  test(
    'fallback Exit uses common warning and physical Host shutdown',
    () async {
      final s = Setup();
      s.platform.tray = false;
      s.platform.fallbackExit = true;
      s.engine.jobs = 3;
      await s.lifetime.closeWindow();
      expect(s.platform.warnings, [3]);
      expect(s.engine.closes, 1);
      expect(s.platform.finishes, 1);
      expect(s.platform.forces, 0);
    },
  );
  test(
    'failed hide does not strand last window or claim tray availability',
    () async {
      final s = Setup();
      s.platform.hideWorks = false;
      await s.lifetime.closeWindow();
      expect(s.lifetime.view.visible, isTrue);
      expect(s.lifetime.trayAvailable, isFalse);
      expect(s.platform.calls, contains('fallback'));
      expect(s.engine.closes, 0);
    },
  );
  test(
    'late hide cannot defeat queued open or tray recreation failure',
    () async {
      for (final failure in [false, true]) {
        final s = Setup();
        await s.lifetime.initialize();
        s.platform.hiding = Completer();
        final hiding = s.lifetime.closeWindow();
        await settle();
        final showing = s.lifetime.handle(
          failure ? DesktopAction.trayUnavailable : DesktopAction.open,
        );
        s.platform.hiding!.complete(true);
        await Future.wait([hiding, showing]);
        expect(s.lifetime.view.visible, isTrue);
        expect(s.platform.calls.last, 'show');
        expect(s.engine.closes, 0);
      }
    },
  );
  test('late initialize success cannot undo a tray loss event', () async {
    final s = Setup();
    s.platform.initializing = Completer();
    final start = s.lifetime.initialize();
    await s.lifetime.handle(DesktopAction.trayUnavailable);
    s.platform.initializing!.complete(true);
    await start;
    expect(s.lifetime.trayAvailable, isFalse);
    expect(s.lifetime.view.visible, isTrue);
  });
  test(
    'exit confirmation cancellation leaves live Host and visible window',
    () async {
      final s = Setup();
      await s.lifetime.initialize();
      await s.lifetime.closeWindow();
      s.platform.allowExit = false;
      await s.lifetime.exit();
      expect(s.lifetime.view.visible, isTrue);
      expect(s.engine.closes, 0);
      expect(s.lifetime.isExiting, isFalse);
      expect(s.platform.finishes, 0);
    },
  );
  test(
    'CloseBlocked Stay preserves Host ownership and never destroys window',
    () async {
      final s = Setup();
      s.engine.outcome = HostCloseResult.closeBlocked;
      await s.lifetime.exit();
      expect(s.platform.finishes, 0);
      expect(s.platform.forces, 0);
      expect(s.lifetime.view.visible, isTrue);
      expect(s.lifetime.isExiting, isTrue);
      expect(s.engine.waits, 0);
    },
  );
  test(
    'explicit Wait follows same shutdown while Force remains accessible',
    () async {
      final s = Setup();
      s.engine.outcome = HostCloseResult.closeBlocked;
      s.platform.blocked = BlockedChoice.wait;
      await s.lifetime.exit();
      expect(s.engine.waits, 1);
      expect(s.platform.finishes, 0);
      s.platform.blocked = BlockedChoice.force;
      await s.lifetime.exit();
      expect(s.platform.forces, 1);
      expect(s.platform.finishes, 0);
      s.engine.waiting.complete(HostCloseResult.closed);
      await settle();
      expect(s.platform.finishes, 0);
    },
  );
  test(
    'Wait physical acknowledgement alone permits normal finish once',
    () async {
      final s = Setup();
      s.engine.outcome = HostCloseResult.closeBlocked;
      s.platform.blocked = BlockedChoice.wait;
      await s.lifetime.exit();
      await s.lifetime.exit();
      expect(s.engine.waits, 1);
      s.engine.waiting.complete(HostCloseResult.closed);
      await settle();
      expect(s.platform.finishes, 1);
      expect(s.platform.forces, 0);
    },
  );
  test('duplicate Exit shares one in-flight prompt/shutdown/finish', () async {
    final s = Setup();
    final first = s.lifetime.exit(), second = s.lifetime.exit();
    expect(identical(first, second), isTrue);
    await first;
    expect(s.engine.closes, 1);
    expect(s.platform.finishes, 1);
  });
  test(
    'safe tray status samples same Host without private job metadata',
    () async {
      final s = Setup();
      await s.lifetime.initialize();
      await settle();
      expect(s.platform.calls, contains('status:ready'));
      expect(s.timers.length, 1);
      expect(s.engine.starts, 1);
    },
  );
}
