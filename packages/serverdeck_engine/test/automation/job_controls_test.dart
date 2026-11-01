import 'dart:async';

import 'package:serverdeck_engine/automation/job_controls.dart';
import 'package:serverdeck_engine/platform/ports.dart';
import 'package:test/test.dart';

final class Clock implements EngineClock {
  @override
  Duration elapsed = Duration.zero;
  @override
  DateTime utcNow = DateTime.utc(2026);
}

final class ManualTimer implements Timer {
  ManualTimer(this.fire);
  final void Function() fire;
  @override
  bool isActive = true;
  @override
  int get tick => 0;
  @override
  void cancel() => isActive = false;
}

final class Setup {
  final clock = Clock();
  final timers = <ManualTimer>[];
  int wakes = 0;
  late final controls = JobControlContinuations<Object>(
    clock: clock,
    wake: () => wakes++,
    schedule: (_, fire) {
      final t = ManualTimer(fire);
      timers.add(t);
      return t;
    },
  );
  JobControlAdmission admission({bool pump = false}) => controls.reserve(
    deadline: pump ? null : clock.elapsed + const Duration(seconds: 30),
    valid: () => true,
    pump: pump,
  );
  void register(
    JobControlAdmission a,
    JobControlKind kind,
    Object actor, {
    String job = 'job',
    Duration? end,
  }) {
    controls.reserveJob(a, job, 'attempt', serverId: 'server');
    controls.register(
      a,
      jobId: job,
      attemptId: 'attempt',
      kind: kind,
      value: actor,
      deadline: end ?? clock.elapsed + const Duration(seconds: 30),
    );
  }
}

void main() {
  test('queued expiry keeps active physical ownership charged', () async {
    final s = Setup(), c = s.controls;
    final active = s.admission();
    await active.entered;
    final waiter = c.reserve(
      deadline: const Duration(seconds: 10),
      valid: () => true,
    );
    final rejection = expectLater(
      waiter.entered,
      throwsA(
        isA<StateError>().having((e) => e.message, 'deadline', 'TIMEOUT'),
      ),
    );
    s.clock.elapsed = const Duration(seconds: 10);
    s.timers.last.fire();
    await rejection;
    expect(c.interestCount, 1);
    expect(c.idle, isFalse);
    active.release();
    expect(c.idle, isTrue);
    c.seal();
  });
  test(
    'old epoch timer cannot wake or erase a resumed service ticket',
    () async {
      final s = Setup(), c = s.controls, old = s.admission();
      await old.entered;
      s.register(old, JobControlKind.reconcile, Object());
      final retired = s.timers.last;
      c.seal();
      old.release();
      c.resume();
      final fresh = s.admission();
      await fresh.entered;
      final actor = Object();
      s.register(fresh, JobControlKind.reconcile, actor);
      final wakes = s.wakes, timer = s.timers.last;
      retired.fire();
      expect(s.wakes, wakes);
      expect(timer.isActive, isTrue);
      final ticket = c.take(fresh, 'job')!;
      expect(identical(ticket.value, actor), isTrue);
      expect(c.current(ticket), isTrue);
      fresh.release();
      c.seal();
    },
  );
  test('retirement is server-specific and late ACK cannot repopulate a retired stop fact', () async {
    final s = Setup(), c = s.controls, a = s.admission();
    await a.entered;
    s.register(a, JobControlKind.cancel, Object());
    final retired = c.stopBinding('job', 'attempt');
    c.acknowledgeStop('job', 'attempt', binding: retired);
    expect(c.pendingCount, 0);
    c.reserveJob(a, 'other', 'other-attempt', serverId: 'another-server');
    final other = c.stopBinding('other', 'other-attempt');
    c.acknowledgeStop('other', 'other-attempt', binding: other);
    c.retireServer('server');
    expect(identical(c.stopBinding('other', 'other-attempt'), other), isTrue);
    s.register(a, JobControlKind.cancel, Object());
    expect(c.pendingCount, 1);
    c.acknowledgeStop('job', 'attempt', binding: retired);
    expect(c.pendingCount, 1);
    c.acknowledgeStop(
      'job',
      'attempt',
      binding: c.stopBinding('job', 'attempt'),
    );
    expect(c.pendingCount, 0);
    a.release();
    c.seal();
  });
  test('FIFO cancellation removes an unstarted waiter while active native interest remains charged', () async {
    final s = Setup(), c = s.controls;
    final first = s.admission(),
        cancelled = s.admission(),
        last = s.admission();
    await first.entered;
    final rejection = expectLater(cancelled.entered, throwsStateError);
    cancelled.cancel();
    await rejection;
    expect(c.interestCount, 2);
    var entered = false;
    last.entered.then((_) => entered = true).ignore();
    await Future<void>.value();
    expect(entered, isFalse);
    first.release();
    await last.entered;
    expect(c.interestCount, 1);
    last.release();
    expect(c.idle, isTrue);
    c.seal();
  });
  test('latest same-kind actor replaces pending only and reconcile receives its turn after one cancel', () async {
    final s = Setup(), c = s.controls, a = s.admission();
    await a.entered;
    final read = Object(), firstStop = Object(), latestStop = Object();
    s.register(a, JobControlKind.reconcile, read);
    s.register(a, JobControlKind.cancel, firstStop);
    s.register(a, JobControlKind.cancel, latestStop);
    expect(c.pendingCount, 2);
    expect(identical(c.take(a, 'job')!.value, latestStop), isTrue);
    s.register(a, JobControlKind.cancel, Object());
    expect(identical(c.take(a, 'job')!.value, read), isTrue);
    expect(c.take(a, 'job')!.kind, JobControlKind.cancel);
    expect(c.take(a, 'job'), isNull);
    a.release();
    c.seal();
  });
  test('original monotonic deadline survives handoff and UTC jumps; retired timer cannot clear a replacement', () async {
    final s = Setup(), c = s.controls, a = s.admission();
    await a.entered;
    s.register(a, JobControlKind.reconcile, Object());
    final retired = s.timers.last;
    s.clock.elapsed = const Duration(seconds: 2);
    final latest = Object();
    s.register(a, JobControlKind.reconcile, latest);
    final current = s.timers.last, wakes = s.wakes;
    retired.fire();
    expect(s.wakes, wakes);
    expect(current.isActive, isTrue);
    s.clock.utcNow = DateTime.utc(2099);
    s.clock.elapsed = const Duration(seconds: 31);
    c.expire(a);
    final ticket = c.take(a, 'job')!;
    expect(identical(ticket.value, latest), isTrue);
    expect(ticket.deadline, const Duration(seconds: 32));
    s.clock.elapsed = const Duration(seconds: 32);
    expect(c.current(ticket), isFalse);
    a.release();
    c.seal();
  });
  test(
    'one timer and bounded 250 jobs/500 actors/32 operations plus one pump',
    () async {
      final s = Setup(), c = s.controls, a = s.admission();
      await a.entered;
      for (var i = 0; i < 250; i++) {
        s.register(a, JobControlKind.cancel, Object(), job: '$i');
        s.register(a, JobControlKind.reconcile, Object(), job: '$i');
      }
      expect(c.entryCount, 250);
      expect(c.pendingCount, 500);
      expect(s.timers.where((t) => t.isActive), hasLength(1));
      expect(
        () => c.reserveJob(a, 'overflow', 'attempt', serverId: 'server'),
        throwsStateError,
      );
      final waiting = List.generate(31, (_) => s.admission());
      final pump = s.admission(pump: true);
      expect(c.interestCount, 33);
      expect(() => s.admission(), throwsStateError);
      expect(() => s.admission(pump: true), throwsStateError);
      final rejected = Future.wait([
        for (final item in [...waiting, pump])
          expectLater(item.entered, throwsStateError),
      ]);
      c.seal();
      await rejected;
      expect(c.pendingCount, 0);
      expect(c.interestCount, 1);
      expect(() => c.resume(), throwsStateError);
      a.release();
      c.resume();
      expect(c.entryCount, 0);
      c.seal();
    },
  );
  test('stop ACK coalesces only matching attempt and terminal pruning prevents late recreation', () async {
    final s = Setup(), c = s.controls, a = s.admission();
    await a.entered;
    s.register(a, JobControlKind.cancel, Object());
    c.acknowledgeStop(
      'job',
      'foreign',
      binding: c.stopBinding('job', 'attempt'),
    );
    expect(c.pendingCount, 1);
    c.acknowledgeStop(
      'job',
      'attempt',
      binding: c.stopBinding('job', 'attempt'),
    );
    expect(c.pendingCount, 0);
    s.register(a, JobControlKind.cancel, Object());
    expect(c.pendingCount, 0);
    c.prune({});
    c.acknowledgeStop(
      'job',
      'attempt',
      binding: c.stopBinding('job', 'attempt'),
    );
    expect(c.entryCount, 0);
    a.release();
    c.seal();
  });
}
