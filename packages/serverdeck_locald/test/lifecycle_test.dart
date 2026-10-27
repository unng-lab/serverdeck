import 'dart:async';
import 'dart:convert';

import 'package:serverdeck_locald/bootstrap/lifecycle.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:test/test.dart';

import 'auth_test.dart' show generation, code;

class ManualDeadlines {
  Duration now = Duration.zero;
  final tasks = <_Task>[];
  void Function() schedule(Duration delay, void Function() wake) {
    final task = _Task(now + delay, wake);
    tasks.add(task);
    return () => task.cancelled = true;
  }

  void advance(Duration target) {
    now = target;
    while (true) {
      final due = tasks.where((t) => !t.cancelled && t.at <= now).toList();
      if (due.isEmpty) break;
      final task = due.first;
      task.cancelled = true;
      task.wake();
    }
  }
}

class _Task {
  _Task(this.at, this.wake);
  final Duration at;
  final void Function() wake;
  bool cancelled = false;
}

String sessionId(int n) =>
    base64Url.encode(List.filled(32, n)).replaceAll('=', '');
ShutdownResources resources(
  List<String> calls, {
  Future<void> Function()? drain,
  Future<void> Function()? storage,
}) => ShutdownResources(
  cancelStartup: () async {
    calls.add('cancel-startup');
  },
  drainMutations: () async {
    calls.add('drain');
    await drain?.call();
  },
  closeStorage: () async {
    calls.add('storage');
    await storage?.call();
  },
  closePipes: () async {
    calls.add('pipes');
  },
  removeDiscovery: () async {
    calls.add('discovery');
  },
  clearKeys: () async {
    calls.add('keys');
  },
  releaseMutex: () async {
    calls.add('mutex');
  },
);
ServiceLifecycle lifetime(
  ManualDeadlines clock,
  ShutdownResources owned, {
  void Function(String)? detached,
}) => ServiceLifecycle(
  generation: generation,
  resources: owned,
  elapsed: () => clock.now,
  schedule: clock.schedule,
  onDetached: detached,
);

void main() {
  test(
    'fatal listener teardown preserves process failure, cleanup failure wins',
    () async {
      for (final storageFails in [false, true]) {
        final clock = ManualDeadlines(), calls = <String>[];
        final service = lifetime(
          clock,
          resources(
            calls,
            storage: () async {
              if (storageFails) throw StateError('synthetic-cleanup-failure');
            },
          ),
        );
        service.bootstrapComplete();
        service.sessions.register('listener', sessionId(1), {});
        final exit = service.waitForExit();
        final expected = expectLater(
          exit,
          code(storageFails ? 'STORAGE_BLOCKED' : 'SERVICE_UNAVAILABLE'),
        );
        final close = service.close(reason: ErrorCode.serviceUnavailable);
        expect(identical(close, service.close()), true);
        if (storageFails) {
          await expectLater(close, code('STORAGE_BLOCKED'));
          expect(calls, ['cancel-startup', 'drain', 'storage']);
        } else {
          await close;
          expect(calls, [
            'cancel-startup',
            'drain',
            'storage',
            'pipes',
            'discovery',
            'keys',
            'mutex',
          ]);
        }
        await expected;
        expect(
          service.reason,
          storageFails
              ? ErrorCode.storageBlocked
              : ErrorCode.serviceUnavailable,
        );
      }
    },
  );
  test('ordinary grace shutdown has successful process completion', () async {
    final clock = ManualDeadlines(), calls = <String>[];
    final service = lifetime(clock, resources(calls));
    service.bootstrapComplete();
    service.sessions.register('normal', sessionId(1), {});
    service.sessions.disconnect('normal');
    clock.advance(const Duration(seconds: 2));
    await service.waitForExit();
    expect(service.reason, isNull);
    expect(calls.last, 'mutex');
  });
  test('cooperative deadline before delayed timer retains TIMEOUT and ordered teardown', () async {
    final clock = ManualDeadlines(), calls = <String>[];
    final service = lifetime(clock, resources(calls));
    service.sessions.register('active', sessionId(1), {});
    clock.now = const Duration(seconds: 30); // Timer has not been advanced.
    expect(service.checkStartupDeadline, code('TIMEOUT'));
    expect(service.reason, ErrorCode.timeout);
    expect(service.stopping, true);
    expect(service.sessions.count, 0);
    await service.finished;
    expect(calls, [
      'cancel-startup',
      'drain',
      'storage',
      'pipes',
      'discovery',
      'keys',
      'mutex',
    ]);
    clock.advance(const Duration(seconds: 31));
    expect(service.reason, ErrorCode.timeout);
    expect(calls, hasLength(7));
  });
  test('entry deadline includes work before lifecycle construction', () async {
    final clock = ManualDeadlines()..now = const Duration(seconds: 29);
    final calls = <String>[];
    final service = ServiceLifecycle(
      generation: generation,
      resources: resources(calls),
      elapsed: () => clock.now,
      schedule: clock.schedule,
      startupDeadlineAt: const Duration(seconds: 30),
    );
    service.bootstrapComplete();
    clock.advance(const Duration(milliseconds: 29999));
    expect(service.stopping, false);
    clock.advance(const Duration(seconds: 30));
    await service.finished;
    expect(service.reason, ErrorCode.timeout);
    expect(calls.last, 'mutex');
  });
  test('expired entry deadline rejects readiness and authentication', () async {
    final clock = ManualDeadlines()..now = const Duration(seconds: 31);
    final calls = <String>[];
    final service = ServiceLifecycle(
      generation: generation,
      resources: resources(calls),
      elapsed: () => clock.now,
      schedule: clock.schedule,
      startupDeadlineAt: const Duration(seconds: 30),
    );
    expect(service.bootstrapComplete, code('NOT_READY'));
    expect(
      () => service.sessions.register('late', sessionId(1), {}),
      code('NOT_READY'),
    );
    await service.finished;
    expect(service.reason, ErrorCode.timeout);
    expect(calls, hasLength(7));
  });
  test('entry deadline cannot extend the startup budget', () {
    final clock = ManualDeadlines()..now = const Duration(seconds: 10);
    for (final deadline in [
      const Duration(seconds: -1),
      const Duration(milliseconds: 40001),
    ]) {
      expect(
        () => ServiceLifecycle(
          generation: generation,
          resources: resources([]),
          elapsed: () => clock.now,
          schedule: clock.schedule,
          startupDeadlineAt: deadline,
        ),
        throwsArgumentError,
      );
      expect(clock.tasks, isEmpty);
    }
  });
  test(
    'explicit disconnect grace rejects a late grant despite delayed timer',
    () async {
      for (final milliseconds in [1999, 2000, 2001]) {
        final clock = ManualDeadlines(), calls = <String>[];
        final service = lifetime(clock, resources(calls));
        try {
          service.bootstrapComplete();
          service.sessions.register('a', sessionId(1), {});
          service.sessions.disconnect('a');
          clock.now = Duration(milliseconds: milliseconds);
          if (milliseconds < 2000) {
            service.sessions.register('b', sessionId(2), {});
            expect(service.stopping, false);
            expect(service.sessions.count, 1);
          } else {
            expect(
              () => service.sessions.register('b', sessionId(2), {}),
              code('NOT_READY'),
            );
            expect(service.stopping, true);
            expect(service.sessions.count, 0);
          }
        } finally {
          await service.close();
        }
      }
    },
  );
  test('default Timer wakes expiry and grace without polling', () async {
    final watch = Stopwatch()..start();
    var offset = Duration.zero;
    final calls = <String>[];
    final service = ServiceLifecycle(
      generation: generation,
      resources: resources(calls),
      elapsed: () => offset + watch.elapsed,
    );
    service.bootstrapComplete();
    service.sessions.register('timer', sessionId(1), {});
    offset = const Duration(milliseconds: 59980);
    service.bootstrapComplete(); // Re-evaluates the original lease deadline.
    await service.finished.timeout(const Duration(seconds: 5));
    expect(service.sessions.count, 0);
    expect(service.stopping, true);
    expect(calls.last, 'mutex');
    watch.stop();
  });
  test(
    'no first session retains owner until startup watchdog, then ordered close',
    () async {
      final clock = ManualDeadlines(), calls = <String>[];
      final service = lifetime(clock, resources(calls));
      service.bootstrapComplete();
      clock.advance(const Duration(seconds: 29));
      expect(service.stopping, false);
      expect(calls, isEmpty);
      clock.advance(const Duration(seconds: 30));
      expect(service.stopping, true);
      await service.finished;
      expect(calls, [
        'cancel-startup',
        'drain',
        'storage',
        'pipes',
        'discovery',
        'keys',
        'mutex',
      ]);
    },
  );
  test(
    'expiry scheduler renews lease and new authenticated client cancels grace',
    () async {
      final clock = ManualDeadlines(), calls = <String>[], revoked = <String>[];
      final service = lifetime(clock, resources(calls), detached: revoked.add);
      service.bootstrapComplete();
      service.sessions.register('a', sessionId(1), {Capability.readinessRead});
      clock.advance(const Duration(seconds: 59));
      service.sessions.begin('a', sessionId(1), null).complete();
      clock.advance(const Duration(seconds: 60));
      expect(service.sessions.count, 1);
      clock.advance(const Duration(seconds: 119));
      expect(revoked, [sessionId(1)]);
      expect(service.stopping, false);
      clock.advance(const Duration(milliseconds: 120999));
      service.sessions.register('b', sessionId(2), {});
      clock.advance(const Duration(seconds: 121));
      expect(service.stopping, false);
      service.sessions.disconnect('b');
      clock.advance(const Duration(seconds: 123));
      expect(service.stopping, true);
      await service.finished;
    },
  );
  test(
    'authenticated bootstrap still has total startup deadline until complete',
    () async {
      final clock = ManualDeadlines(), calls = <String>[];
      final service = lifetime(clock, resources(calls));
      service.sessions.register('a', sessionId(1), {});
      clock.advance(const Duration(seconds: 30));
      expect(service.stopping, true);
      await service.finished;
    },
  );
  test('stopping rejects grants immediately and awaits running commit before storage/mutex', () async {
    final clock = ManualDeadlines(), calls = <String>[];
    final gate = Completer<void>();
    final service = lifetime(clock, resources(calls, drain: () => gate.future));
    service.bootstrapComplete();
    service.sessions.register('a', sessionId(1), {});
    final close = service.close();
    expect(identical(close, service.close()), true);
    expect(
      () => service.sessions.register('b', sessionId(2), {}),
      code('NOT_READY'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['cancel-startup', 'drain']);
    gate.complete();
    await close;
    expect(calls.last, 'mutex');
    clock.advance(const Duration(days: 1));
    expect(calls, hasLength(7));
  });
  test('storage close failure retains downstream resources and cannot claim clean shutdown', () async {
    final clock = ManualDeadlines(), calls = <String>[];
    final service = lifetime(
      clock,
      resources(
        calls,
        storage: () async {
          throw StateError('synthetic-private-detail');
        },
      ),
    );
    await expectLater(service.close(), code('STORAGE_BLOCKED'));
    expect(calls, ['cancel-startup', 'drain', 'storage']);
    expect(service.stopping, true);
    await expectLater(service.finished, code('STORAGE_BLOCKED'));
  });
  test(
    'late first grant cannot erase watchdog while its timer is delayed',
    () async {
      final clock = ManualDeadlines(), calls = <String>[];
      final service = lifetime(clock, resources(calls));
      service.bootstrapComplete();
      clock.now = const Duration(seconds: 31);
      expect(
        () => service.sessions.register('late', sessionId(1), {}),
        code('NOT_READY'),
      );
      expect(service.sessions.count, 0);
      expect(service.reason, ErrorCode.timeout);
      await service.finished;
    },
  );
  test('late bootstrap completion cannot erase the startup watchdog', () async {
    final clock = ManualDeadlines(), calls = <String>[];
    final service = lifetime(clock, resources(calls));
    service.sessions.register('a', sessionId(1), {});
    clock.now = const Duration(seconds: 31);
    expect(service.bootstrapComplete, code('NOT_READY'));
    expect(service.reason, ErrorCode.timeout);
    expect(service.sessions.count, 0);
    await service.finished;
  });
  test('delayed expiry wake preserves the original grace deadline', () async {
    final clock = ManualDeadlines(), calls = <String>[];
    final service = lifetime(clock, resources(calls));
    service.bootstrapComplete();
    service.sessions.register('a', sessionId(1), {});
    clock.now = const Duration(seconds: 63);
    expect(
      () => service.sessions.register('late', sessionId(2), {}),
      code('NOT_READY'),
    );
    expect(service.sessions.count, 0);
    await service.finished;
  });
}
