import 'dart:async';

import 'package:serverdeck_engine/hosting/target_changes.dart';
import 'package:serverdeck_engine/platform/ports.dart';
import 'package:test/test.dart';

const budget = Duration(seconds: 5);
const profile = '12345678-1234-4234-9234-123456789abc';
Matcher failure(String code) =>
    throwsA(isA<StateError>().having((e) => e.message, 'safe code', code));
Future<void> settle() async {
  for (var i = 0; i < 8; i++) await Future<void>.delayed(Duration.zero);
}

final class Clock implements EngineClock {
  @override
  Duration elapsed = Duration.zero;
  @override
  DateTime get utcNow => DateTime.utc(2026).add(elapsed);
}

final class Attempt implements PublicationAcquisition {
  Attempt() {
    result.ignore();
    settled.ignore();
  }
  final reply = Completer<PublicationLease>(), physical = Completer<void>();
  @override
  Future<PublicationLease> get result => reply.future;
  @override
  Future<void> get settled => physical.future;
  void fail(String code, {bool settle = true}) {
    reply.completeError(StateError(code));
    if (settle) physical.complete();
  }
}

final class Lease implements PublicationLease {
  Lease(this.gate);
  final Gate gate;
  final completed = Completer<void>();
  Completer<void>? pause;
  bool fail = false;
  Future<void>? closing;
  int closes = 0;
  @override
  Future<void> get done => completed.future;
  @override
  Future<void> close() => closing ??= () async {
    closes++;
    await pause?.future;
    gate.leases.remove(this);
    completed.complete();
    if (fail) throw StateError('private provider details');
  }();
}

final class Gate implements PublicationGate {
  Gate({this.generation = profile});
  @override
  final String generation;
  @override
  bool isClosed = false;
  final attempts = <Attempt>[];
  final leases = <Lease>{};
  bool automatic = true, earlyClose = false;
  int closes = 0;
  Future<void>? closing;
  @override
  int get activeAcquisitions =>
      attempts.where((a) => !a.physical.isCompleted).length;
  @override
  int get activeLeases => leases.length;
  Lease deliver(Attempt attempt) {
    final lease = Lease(this);
    leases.add(lease);
    attempt.reply.complete(lease);
    attempt.physical.complete();
    return lease;
  }

  @override
  PublicationAcquisition beginAcquire({Duration deadline = budget}) {
    final attempt = Attempt();
    attempts.add(attempt);
    if (isClosed) {
      attempt.fail('SERVICE_UNAVAILABLE');
    } else if (automatic) {
      scheduleMicrotask(() {
        if (isClosed) {
          if (!attempt.reply.isCompleted)
            attempt.reply.completeError(StateError('SERVICE_UNAVAILABLE'));
          attempt.physical.complete();
        } else {
          deliver(attempt);
        }
      });
    }
    return attempt;
  }

  @override
  Future<PublicationLease> acquire({Duration deadline = budget}) =>
      beginAcquire(deadline: deadline).result;
  @override
  Future<void> close() => closing ??= () async {
    closes++;
    isClosed = true;
    for (final attempt in attempts) {
      if (!attempt.reply.isCompleted)
        attempt.reply.completeError(StateError('SERVICE_UNAVAILABLE'));
    }
    if (!earlyClose) {
      await Future.wait<void>([
        for (final a in attempts) a.settled,
        for (final lease in leases.toList()) lease.done,
      ]);
    }
  }();
}

final class Setup {
  final gate = Gate(), clock = Clock();
  final retired = <Set<String>?>[];
  bool stopping = false, failRetirement = false;
  int failures = 0;
  late final changes = TargetChanges(
    gate: gate,
    clock: clock,
    isStopping: () => stopping,
    retireMcp: (affected) {
      retired.add(affected);
      if (failRetirement) throw StateError('private registry details');
    },
    onFailure: () {
      failures++;
      stopping = true;
    },
  );
}

void main() {
  test(
    'normal target lease retires before delivery and releases exactly once',
    () async {
      final s = Setup();
      final lease = await s.changes.begin(budget);
      expect(s.retired, [null]);
      expect(s.changes.interests, 1);
      expect(s.gate.activeLeases, 1);
      final closing = lease.close();
      expect(identical(closing, lease.close()), isTrue);
      await closing;
      expect(s.changes.interests, 0);
      await s.changes.close();
      expect(s.gate.closes, 1);
    },
  );

  test(
    'reconciled retirement captures only validated affected IDs until release',
    () async {
      final s = Setup();
      final lease = await s.changes.beginReconciled(budget);
      expect(s.retired, isEmpty);
      lease.retireAffected({});
      final ids = {profile};
      lease.retireAffected(ids);
      ids.clear();
      expect(s.retired.single, {profile});
      expect(() => s.retired.single!.clear(), throwsUnsupportedError);
      expect(() => lease.retireAffected({'invalid'}), throwsFormatException);
      expect(s.retired.length, 1);
      lease.retireAll();
      expect(s.retired.last, isNull);
      await lease.close();
      expect(() => lease.retireAll(), failure('SERVICE_UNAVAILABLE'));
      await s.changes.close();
    },
  );

  test(
    'logical acquire timeout keeps all16 slots charged until actual cleanup',
    () async {
      final s = Setup()..gate.automatic = false;
      final replies = [for (var i = 0; i < 16; i++) s.changes.begin(budget)];
      final expectations = [
        for (final reply in replies) expectLater(reply, failure('TIMEOUT')),
      ];
      for (final attempt in s.gate.attempts)
        attempt.fail('TIMEOUT', settle: false);
      await Future.wait(expectations);
      expect(s.changes.interests, 16);
      expect(s.retired, isEmpty);
      await expectLater(s.changes.begin(budget), failure('RESOURCE_LIMIT'));
      await expectLater(
        s.changes.runAuthority(() async => 1, budget),
        failure('RESOURCE_LIMIT'),
      );
      for (final attempt in s.gate.attempts) attempt.physical.complete();
      await settle();
      expect(s.changes.interests, 0);
      expect(s.retired.length, 16);
      await s.changes.close();
    },
  );

  test('failed acquisition cleanup waits its own handle rather than unrelated work', () async {
    final s = Setup()..gate.automatic = false;
    final first = s.changes.begin(budget),
        second = s.changes.beginReconciled(budget);
    final failed = expectLater(first, failure('TIMEOUT'));
    s.gate.attempts.first.fail('TIMEOUT', settle: false);
    await failed;
    s.gate.attempts.first.physical.complete();
    await settle();
    expect(s.changes.interests, 1);
    expect(s.retired, [null]);
    s.gate.deliver(s.gate.attempts.last);
    await (await second).close();
    await s.changes.close();
  });

  test(
    'authority timeout replies before physical drain and cannot execute effect',
    () async {
      final s = Setup()..gate.automatic = false;
      var effects = 0, closed = false;
      final reply = s.changes.runAuthority(() async => effects++, budget);
      final failed = expectLater(reply, failure('TIMEOUT'));
      s.gate.attempts.single.fail('TIMEOUT', settle: false);
      await failed;
      final closing = s.changes.close().then((_) => closed = true);
      await settle();
      expect(closed, isFalse);
      expect(effects, 0);
      s.gate.attempts.single.physical.complete();
      await closing;
    },
  );

  test('close drains admitted effect and release even with an early-closing provider', () async {
    final s = Setup()..gate.earlyClose = true;
    final effect = Completer<int>(), release = Completer<void>();
    var entered = false, closed = false;
    final reply = s.changes.runAuthority(() {
      entered = true;
      return effect.future;
    }, budget);
    await settle();
    expect(entered, isTrue);
    s.gate.leases.single.pause = release;
    final closing = s.changes.close().then((_) => closed = true);
    await expectLater(s.changes.begin(budget), failure('SERVICE_UNAVAILABLE'));
    effect.complete(7);
    await settle();
    expect(closed, isFalse);
    release.complete();
    expect(await reply, 7);
    await closing;
    expect(s.retired, isEmpty);
  });

  test(
    'observer failure never starts the effect and still releases physical work',
    () async {
      final s = Setup();
      var effects = 0;
      await expectLater(
        s.changes.runAuthority(
          () async => effects++,
          budget,
          observeNativeCompletion: (_) =>
              throw StateError('private observer details'),
        ),
        failure('SERVICE_UNAVAILABLE'),
      );
      await s.changes.close();
      expect(effects, 0);
      expect(s.gate.leases, isEmpty);
    },
  );

  test(
    'late native success after deadline releases without mutation ownership',
    () async {
      final s = Setup()..gate.automatic = false;
      final result = s.changes.beginReconciled(budget);
      final failed = expectLater(result, failure('TIMEOUT'));
      s.clock.elapsed = budget;
      final lease = s.gate.deliver(s.gate.attempts.single);
      await failed;
      await settle();
      expect(lease.closes, 1);
      expect(s.changes.interests, 0);
      expect(s.retired, isEmpty);
      await s.changes.close();
    },
  );

  test('retirement failure closes intake synchronously and cannot become clean close', () async {
    final s = Setup()..failRetirement = true;
    await expectLater(s.changes.begin(budget), failure('SERVICE_UNAVAILABLE'));
    expect(s.stopping, isTrue);
    expect(s.failures, 1);
    await expectLater(s.changes.begin(budget), failure('SERVICE_UNAVAILABLE'));
    await expectLater(s.changes.close(), failure('SERVICE_UNAVAILABLE'));
    expect(s.retired.length, 1);
  });

  test('release failure retires intake and keeps close unsuccessful', () async {
    final s = Setup();
    final lease = await s.changes.beginReconciled(budget);
    s.gate.leases.single.fail = true;
    await expectLater(lease.close(), failure('SERVICE_UNAVAILABLE'));
    expect(s.failures, 1);
    await expectLater(s.changes.close(), failure('SERVICE_UNAVAILABLE'));
  });
}
