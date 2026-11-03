import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/connections/network_budget.dart';

final class Deadline {
  Deadline(this.at, this.callback);
  final Duration at;
  final void Function() callback;
  bool cancelled = false, delivered = false;
}

final class Clock {
  Duration current = Duration.zero;
  final timers = <Deadline>[];
  Duration now() => current;
  void Function() schedule(Duration duration, void Function() callback) {
    final deadline = Deadline(current + duration, callback);
    timers.add(deadline);
    return () => deadline.cancelled = true;
  }

  void advance(Duration duration) {
    current += duration;
    while (true) {
      final due =
          timers
              .where((t) => !t.cancelled && !t.delivered && t.at <= current)
              .toList()
            ..sort((a, b) => a.at.compareTo(b.at));
      if (due.isEmpty) return;
      due.first.delivered = true;
      due.first.callback();
    }
  }

  int get active => timers.where((t) => !t.cancelled && !t.delivered).length;
}

Future<void> turn() => Future<void>.delayed(Duration.zero);

void main() {
  test('late auth success cannot suppress an expired undelivered deadline', () {
    final clock = Clock(), expired = <BudgetExpiry>[];
    final budget = NetworkBudget(
      onExpired: expired.add,
      now: clock.now,
      schedule: clock.schedule,
    );
    clock.current = const Duration(
      seconds: 30,
    ); // Timer intentionally not delivered.
    var connected = false;
    if (budget.tryComplete()) connected = true;
    expect(connected, isFalse);
    expect(expired, [BudgetExpiry.network]);
    expect(budget.tryComplete(), isFalse);
    for (final timer in clock.timers) {
      timer.callback();
    }
    expect(expired, hasLength(1));
    expect(clock.active, 0);
  });
  test('successful completion checks time, accepts once and fences all late timers', () {
    final clock = Clock(), expired = <BudgetExpiry>[];
    final budget = NetworkBudget(
      onExpired: expired.add,
      now: clock.now,
      schedule: clock.schedule,
    );
    clock.current = const Duration(seconds: 29, milliseconds: 999);
    expect(budget.tryComplete(), isTrue);
    expect(budget.tryComplete(), isFalse);
    clock.current = const Duration(hours: 1);
    for (final timer in clock.timers) {
      timer.callback();
    }
    expect(expired, isEmpty);
    expect(budget.isEnded, isTrue);
    expect(clock.active, 0);
  });
  test('success is refused while a prompt is active, including its expired deadline', () {
    final clock = Clock(), expired = <BudgetExpiry>[];
    final budget = NetworkBudget(
      onExpired: expired.add,
      now: clock.now,
      schedule: clock.schedule,
    );
    budget.pauseForPrompt(PromptKind.trust);
    expect(budget.tryComplete(), isFalse);
    expect(budget.isEnded, isFalse);
    clock.current = const Duration(minutes: 5);
    expect(budget.tryComplete(), isFalse);
    expect(expired, [BudgetExpiry.prompt]);
    expect(budget.tryComplete(), isFalse);
    expect(expired, hasLength(1));
  });
  test(
    'isEnded refreshes elapsed time but cancellation need not emit a timeout',
    () {
      final clock = Clock(), expired = <BudgetExpiry>[];
      final budget = NetworkBudget(
        onExpired: expired.add,
        now: clock.now,
        schedule: clock.schedule,
      );
      clock.current = const Duration(seconds: 30);
      expect(budget.isEnded, isTrue);
      expect(expired, [BudgetExpiry.network]);
      final cancelled = NetworkBudget(
        onExpired: expired.add,
        now: clock.now,
        schedule: clock.schedule,
      );
      clock.current = const Duration(minutes: 1);
      cancelled.finish();
      expect(expired, hasLength(1));
    },
  );
  test('active budget expires once at exactly thirty monotonic seconds', () {
    final clock = Clock(), expired = <BudgetExpiry>[];
    final budget = NetworkBudget(
      onExpired: expired.add,
      now: clock.now,
      schedule: clock.schedule,
    );
    clock.advance(const Duration(seconds: 29, milliseconds: 999));
    expect(budget.remaining, const Duration(milliseconds: 1));
    expect(expired, isEmpty);
    clock.advance(const Duration(milliseconds: 1));
    expect(expired, [BudgetExpiry.network]);
    expect(budget.isEnded, isTrue);
    expect(budget.remaining, Duration.zero);
    expect(clock.active, 0);
    clock.advance(const Duration(hours: 1));
    budget.finish();
    expect(expired, hasLength(1));
  });
  for (final kind in PromptKind.values) {
    test(
      '$kind pauses only the active budget, resume preserves ten remaining seconds',
      () {
        final clock = Clock(), expired = <BudgetExpiry>[];
        final budget = NetworkBudget(
          onExpired: expired.add,
          now: clock.now,
          schedule: clock.schedule,
        );
        clock.advance(const Duration(seconds: 20));
        final prompt = budget.pauseForPrompt(kind)!;
        clock.advance(const Duration(minutes: 4));
        expect(budget.remaining, const Duration(seconds: 10));
        expect(expired, isEmpty);
        expect(budget.resume(prompt), isTrue);
        clock.advance(const Duration(seconds: 9));
        expect(expired, isEmpty);
        clock.advance(const Duration(seconds: 1));
        expect(expired, [BudgetExpiry.network]);
      },
    );
  }
  test('repeated prompt observations do not renew five-minute lease or imply acceptance', () {
    final clock = Clock(), expired = <BudgetExpiry>[];
    final budget = NetworkBudget(
      onExpired: expired.add,
      now: clock.now,
      schedule: clock.schedule,
    );
    final first = budget.pauseForPrompt(PromptKind.trust)!;
    clock.advance(const Duration(minutes: 4));
    expect(budget.pauseForPrompt(PromptKind.trust), same(first));
    expect(
      () => budget.pauseForPrompt(PromptKind.passphrase),
      throwsStateError,
    );
    clock.advance(const Duration(minutes: 1));
    expect(expired, [BudgetExpiry.prompt]);
    expect(budget.resume(first), isFalse);
    expect(budget.pauseForPrompt(PromptKind.trust), isNull);
    expect(clock.active, 0);
  });
  test('stale and foreign prompt leases cannot resume a current prompt', () {
    final clock = Clock(), otherClock = Clock();
    final budget = NetworkBudget(
      onExpired: (_) => fail('unexpected timeout'),
      now: clock.now,
      schedule: clock.schedule,
    );
    final other = NetworkBudget(
      onExpired: (_) => fail('unexpected timeout'),
      now: otherClock.now,
      schedule: otherClock.schedule,
    );
    final first = budget.pauseForPrompt(PromptKind.trust)!;
    final foreign = other.pauseForPrompt(PromptKind.passphrase)!;
    expect(budget.resume(foreign), isFalse);
    expect(budget.resume(first), isTrue);
    expect(budget.resume(first), isFalse);
    final second = budget.pauseForPrompt(PromptKind.passphrase)!;
    expect(budget.resume(first), isFalse);
    clock.advance(const Duration(minutes: 4));
    expect(budget.remaining, const Duration(seconds: 30));
    expect(budget.resume(second), isTrue);
    budget.finish();
    other.finish();
  });
  test('fresh time checks expire before delayed timers and refuse late prompt completion', () {
    for (final prompt in [false, true]) {
      final clock = Clock(), expired = <BudgetExpiry>[];
      final budget = NetworkBudget(
        onExpired: expired.add,
        now: clock.now,
        schedule: clock.schedule,
      );
      final lease = prompt
          ? budget.pauseForPrompt(PromptKind.passphrase)
          : null;
      clock.current = prompt
          ? const Duration(minutes: 5)
          : const Duration(seconds: 30);
      if (lease != null) expect(budget.resume(lease), isFalse);
      expect(budget.remaining, Duration.zero);
      expect(expired, [prompt ? BudgetExpiry.prompt : BudgetExpiry.network]);
      for (final timer in List.of(clock.timers)) {
        timer.callback();
      }
      expect(expired, hasLength(1));
    }
  });
  test(
    'early and cancelled timer callbacks cannot extend or consume the budget',
    () {
      final clock = Clock(), expired = <BudgetExpiry>[];
      final budget = NetworkBudget(
        onExpired: expired.add,
        now: clock.now,
        schedule: clock.schedule,
      );
      final original = clock.timers.single;
      clock.current = const Duration(seconds: 5);
      original.callback();
      expect(budget.remaining, const Duration(seconds: 25));
      expect(clock.timers.last.at, const Duration(seconds: 30));
      final prompt = budget.pauseForPrompt(PromptKind.trust)!;
      clock.current = const Duration(seconds: 30);
      original.callback();
      expect(expired, isEmpty);
      expect(budget.remaining, const Duration(seconds: 25));
      expect(budget.resume(prompt), isTrue);
      clock.advance(const Duration(seconds: 25));
      expect(expired, [BudgetExpiry.network]);
    },
  );
  test('finish cancels deadlines and fences every captured late callback', () {
    final clock = Clock(), expired = <BudgetExpiry>[];
    final budget = NetworkBudget(
      onExpired: expired.add,
      now: clock.now,
      schedule: clock.schedule,
    );
    budget.pauseForPrompt(PromptKind.trust);
    budget.finish();
    budget.finish();
    clock.current = const Duration(hours: 10);
    for (final timer in clock.timers) {
      timer.callback();
    }
    expect(expired, isEmpty);
    expect(clock.active, 0);
    expect(budget.remaining, Duration.zero);
  });
  test('watchdog waits fifteen seconds, permits one ping and starts next interval after completion', () async {
    final clock = Clock(), replies = <Completer<void>>[];
    var failed = 0;
    final watchdog = ConnectionWatchdog(
      ping: () {
        final reply = Completer<void>();
        replies.add(reply);
        return reply.future;
      },
      onFailure: () => failed++,
      now: clock.now,
      schedule: clock.schedule,
    );
    clock.advance(const Duration(seconds: 14));
    expect(replies, isEmpty);
    clock.advance(const Duration(seconds: 1));
    expect(replies, hasLength(1));
    expect(watchdog.pingPending, isTrue);
    clock.advance(const Duration(seconds: 9));
    expect(replies, hasLength(1));
    replies.single.complete();
    await turn();
    expect(watchdog.pingPending, isFalse);
    clock.advance(const Duration(seconds: 14));
    expect(replies, hasLength(1));
    clock.advance(const Duration(seconds: 1));
    expect(replies, hasLength(2));
    expect(failed, 0);
    watchdog.stop();
    replies.last.complete();
    await turn();
    expect(clock.active, 0);
  });
  test('blackhole closes after fifteen plus ten seconds and ignores a late successful reply', () async {
    final clock = Clock(), reply = Completer<void>();
    var failed = 0, pings = 0;
    final watchdog = ConnectionWatchdog(
      ping: () {
        pings++;
        return reply.future;
      },
      onFailure: () => failed++,
      now: clock.now,
      schedule: clock.schedule,
    );
    clock.advance(const Duration(seconds: 15));
    clock.advance(const Duration(seconds: 9));
    expect(failed, 0);
    clock.advance(const Duration(seconds: 1));
    expect(failed, 1);
    expect(watchdog.isStopped, isTrue);
    reply.complete();
    await turn();
    clock.advance(const Duration(hours: 1));
    for (final timer in clock.timers) {
      timer.callback();
    }
    expect(pings, 1);
    expect(failed, 1);
    expect(clock.active, 0);
  });
  for (final synchronous in [false, true]) {
    test(
      'watchdog consumes ${synchronous ? 'synchronous' : 'asynchronous'} ping failure without another ping',
      () async {
        final clock = Clock();
        var failed = 0, pings = 0;
        final watchdog = ConnectionWatchdog(
          ping: () {
            pings++;
            if (synchronous) throw StateError('SYNTHETIC_DETAIL');
            return Future.error(StateError('SYNTHETIC_DETAIL'));
          },
          onFailure: () => failed++,
          now: clock.now,
          schedule: clock.schedule,
        );
        clock.advance(const Duration(seconds: 15));
        await turn();
        expect(failed, 1);
        clock.advance(const Duration(hours: 1));
        expect(pings, 1);
        expect(watchdog.isStopped, isTrue);
      },
    );
  }
  test('stop while waiting or pinging prevents late error from affecting another session', () async {
    for (final pending in [false, true]) {
      final clock = Clock(), reply = Completer<void>();
      var failed = 0, pings = 0;
      final watchdog = ConnectionWatchdog(
        ping: () {
          pings++;
          return reply.future;
        },
        onFailure: () => failed++,
        now: clock.now,
        schedule: clock.schedule,
      );
      if (pending) clock.advance(const Duration(seconds: 15));
      watchdog.stop();
      watchdog.stop();
      if (pending) reply.completeError(StateError('SYNTHETIC_LATE_ERROR'));
      await turn();
      clock.current = const Duration(hours: 1);
      for (final timer in clock.timers) {
        timer.callback();
      }
      expect(failed, 0);
      expect(pings, pending ? 1 : 0);
      expect(clock.active, 0);
    }
  });
  test(
    'early watchdog timers preserve ping generation and original deadlines',
    () async {
      final clock = Clock(), reply = Completer<void>();
      var failed = 0, pings = 0;
      final watchdog = ConnectionWatchdog(
        ping: () {
          pings++;
          return reply.future;
        },
        onFailure: () => failed++,
        now: clock.now,
        schedule: clock.schedule,
      );
      clock.current = const Duration(seconds: 1);
      clock.timers.last.callback();
      expect(clock.timers.last.at, const Duration(seconds: 15));
      expect(pings, 0);
      clock.advance(const Duration(seconds: 14));
      expect(pings, 1);
      clock.current = const Duration(seconds: 18);
      clock.timers.last.callback();
      expect(clock.timers.last.at, const Duration(seconds: 25));
      clock.current = const Duration(seconds: 20);
      reply.complete();
      await turn();
      expect(watchdog.pingPending, isFalse);
      expect(clock.timers.last.at, const Duration(seconds: 35));
      expect(failed, 0);
      watchdog.stop();
    },
  );
  test(
    'reply at deadline fails even if its timer callback has not yet run',
    () async {
      final clock = Clock(), reply = Completer<void>();
      var failed = 0;
      final watchdog = ConnectionWatchdog(
        ping: () => reply.future,
        onFailure: () => failed++,
        now: clock.now,
        schedule: clock.schedule,
      );
      clock.advance(const Duration(seconds: 15));
      clock.current = const Duration(seconds: 25);
      reply.complete();
      await turn();
      expect(failed, 1);
      expect(watchdog.isStopped, isTrue);
      expect(clock.active, 0);
    },
  );
}
