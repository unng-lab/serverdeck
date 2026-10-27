import 'dart:async';
import 'dart:io';

import 'package:serverdeck_locald/api/native_control_queue.dart';
import 'package:test/test.dart';

const _budget = Duration(seconds: 5);

Future<void> _turn() => Future<void>.delayed(Duration.zero);

Matcher _state(String code) =>
    isA<StateError>().having((error) => error.message, 'code', code);

Matcher _local(String code) => isA<NativeControlLocalFailure>().having(
  (error) => error.cause,
  'cause',
  _state(code),
);

final class _Proof {
  final actual = Completer<void>();
  final raw = Completer<void>();

  void release() {
    if (!actual.isCompleted) actual.complete();
    if (!raw.isCompleted) raw.complete();
  }
}

final class _Harness {
  _Harness() {
    queue = NativeControlQueue(
      revalidate: ({observeNativeCompletion}) {
        final proof = _Proof();
        proofs.add(proof);
        events.add('proof');
        observeNativeCompletion?.call(proof.actual.future);
        return proof.raw.future;
      },
      verifiedBundleRoot: () {
        final root = Completer<String>();
        roots.add(root);
        events.add('metadata');
        return root.future;
      },
    );
    addTearDown(() async {
      queue.retire();
      for (final proof in proofs) {
        proof.release();
      }
      for (final root in roots) {
        if (!root.isCompleted) root.complete('retired');
      }
      await queue.settled;
    });
  }

  late final NativeControlQueue queue;
  final proofs = <_Proof>[];
  final roots = <Completer<String>>[];
  final events = <String>[];

  NativeControlTicket<void> proof({
    Duration Function()? remaining,
    List<NativeControlScope> scopes = const [],
    void Function(Future<void>)? observer,
  }) => queue.proof(
    remaining: remaining ?? () => _budget,
    scopes: scopes,
    observeNativeCompletion: observer,
  );
}

void main() {
  test('W plus R plus V preserves quota3 for a later fresh proof', () async {
    // The RED switch selects only the old direct adapter in this pure model.
    // The healthy oracle and native3 refusal stay identical for RED/GREEN.
    final direct = Platform.environment['SERVERDECK_NATIVE_CONTROL_RED'] == '1';
    var pending = 2; // The source-reachable unfinished W and standing R.
    var maximum = pending;
    final actuals = <Completer<void>>[];
    Future<void> raw({void Function(Future<void>)? observeNativeCompletion}) {
      if (pending == 3) return Future.error(StateError('RESOURCE_LIMIT'));
      pending++;
      if (pending > maximum) maximum = pending;
      final actual = Completer<void>();
      actuals.add(actual);
      observeNativeCompletion?.call(actual.future);
      return actual.future.whenComplete(() => pending--);
    }

    final queue = NativeControlQueue(
      revalidate: raw,
      verifiedBundleRoot: () async => 'unused',
    );
    addTearDown(() async {
      queue.retire();
      for (final actual in actuals) {
        if (!actual.isCompleted) actual.complete();
      }
      await queue.settled;
    });
    Future<void> request() =>
        direct ? raw() : queue.proof(remaining: () => _budget).result;
    final first = request();
    first.ignore();
    await _turn();
    expect(pending, 3);
    final second = request();
    second.ignore();
    final both = Future.wait([first, second]);
    both.ignore();
    expect(actuals, hasLength(1));
    actuals.first.complete();
    await _turn();
    if (actuals.length == 2) actuals.last.complete();
    await both; // Old direct adapter fails here with real RESOURCE_LIMIT.
    expect(actuals, hasLength(2));
    expect(maximum, 3);
    expect(pending, 2);
  });

  test(
    'preissue burst shares once and completed proof is never cached',
    () async {
      final h = _Harness();
      final first = h.proof();
      final second = h.proof();
      expect(h.proofs, isEmpty);
      await _turn();
      expect(h.proofs, hasLength(1));
      h.proofs.single.release();
      await Future.wait([first.result, second.result]);
      final later = h.proof();
      await _turn();
      expect(h.proofs, hasLength(2));
      h.proofs.last.release();
      await later.result;
    },
  );

  test(
    'actual and raw workflow independently retain the physical gate',
    () async {
      final h = _Harness();
      final first = h.proof();
      await _turn();
      final next = h.proof();
      h.proofs.first.actual.complete();
      await _turn();
      expect(h.proofs, hasLength(1));
      h.proofs.first.raw.complete();
      await first.settled;
      await _turn();
      expect(h.proofs, hasLength(2));
      final third = h.proof();
      h.proofs.last.raw.complete();
      await _turn();
      expect(h.proofs, hasLength(2));
      h.proofs.last.actual.complete();
      await next.settled;
      await _turn();
      expect(h.proofs, hasLength(3));
      h.proofs.last.release();
      await third.result;
    },
  );

  test(
    'issued timeout settles logically while physical ownership remains',
    () async {
      final h = _Harness();
      final timed = h.proof(remaining: () => const Duration(milliseconds: 20));
      var physicallySettled = false;
      timed.settled.then((_) => physicallySettled = true).ignore();
      await expectLater(timed.result, throwsA(isA<TimeoutException>()));
      final later = h.proof();
      await _turn();
      expect(physicallySettled, isFalse);
      expect(h.proofs, hasLength(1));
      h.proofs.first.raw.complete();
      await _turn();
      expect(physicallySettled, isFalse);
      expect(h.proofs, hasLength(1));
      h.proofs.first.actual.complete();
      await timed.settled;
      await _turn();
      expect(physicallySettled, isTrue);
      expect(h.proofs, hasLength(2));
      h.proofs.last.release();
      await later.result;
    },
  );

  test('queued expiry never issues or observes native work', () async {
    final h = _Harness();
    final active = h.proof();
    await _turn();
    var observed = false;
    final expired = h.proof(
      remaining: () => const Duration(milliseconds: 20),
      observer: (_) => observed = true,
    );
    await expectLater(expired.result, throwsA(isA<TimeoutException>()));
    await expired.settled;
    expect(observed, isFalse);
    h.proofs.first.release();
    await active.settled;
    await _turn();
    expect(h.proofs, hasLength(1));
  });

  test(
    'remaining getter is checked again without renewing the attempt',
    () async {
      final h = _Harness();
      var remaining = _budget;
      var observed = false;
      final expired = h.proof(
        remaining: () => remaining,
        observer: (_) => observed = true,
      );
      remaining = Duration.zero;
      await expectLater(expired.result, throwsA(isA<TimeoutException>()));
      await expired.settled;
      expect(h.proofs, isEmpty);
      expect(observed, isFalse);
      final denied = h.proof(remaining: () => throw StateError('TIMEOUT'));
      await expectLater(denied.result, throwsA(isA<TimeoutException>()));
    },
  );

  test('local getter failure unwraps without poisoning the peer', () async {
    final h = _Harness();
    var failures = 0;
    h.queue.bindFailureHandler(() => failures++);
    final denied = h.proof(remaining: () => throw StateError('UNAUTHORIZED'));
    await expectLater(denied.result, throwsA(_local('UNAUTHORIZED')));
    try {
      await denied.result;
    } on NativeControlLocalFailure catch (error) {
      expect(error.rethrowCause, throwsA(_state('UNAUTHORIZED')));
    }
    final valid = h.proof();
    await _turn();
    h.proofs.single.release();
    await valid.result;
    expect(failures, 0);
  });

  test('session and request scopes detach independently', () async {
    final h = _Harness();
    final session = NativeControlScope();
    final request = NativeControlScope();
    final rpc = h.proof(scopes: [session, request]);
    final independent = h.proof(scopes: [session]);
    request.retire();
    await expectLater(rpc.result, throwsA(_local('UNAUTHORIZED')));
    await rpc.settled;
    await _turn();
    expect(h.proofs, hasLength(1));
    final terminal = h.proof(scopes: [NativeControlScope()]);
    session.retire();
    await expectLater(independent.result, throwsA(_local('UNAUTHORIZED')));
    h.proofs.first.release();
    await independent.settled;
    await _turn();
    expect(h.proofs, hasLength(2));
    h.proofs.last.release();
    await terminal.result;
    final removed = h.proof(scopes: [session]);
    await expectLater(removed.result, throwsA(_local('UNAUTHORIZED')));
  });

  test('cap1024 refuses1025 and withdrawal reclaims queued members', () async {
    final h = _Harness();
    var observers = 0;
    final tickets = [
      for (var i = 0; i < NativeControlQueue.maximumTickets; i++)
        h.proof(observer: (_) => observers++),
    ];
    final excess = h.proof(observer: (_) => fail('refusal was observed'));
    final refused = expectLater(
      excess.result,
      throwsA(_local('RESOURCE_LIMIT')),
    );
    for (final ticket in tickets) {
      ticket.withdraw();
    }
    await refused;
    await Future.wait(tickets.map((ticket) => ticket.settled));
    // Every canceled node/member was removed, even while the pump was queued.
    expect(h.proofs, isEmpty);
    final replacement = [
      for (var i = 0; i < NativeControlQueue.maximumTickets; i++) h.proof(),
    ];
    await _turn();
    expect(h.proofs, hasLength(1));
    expect(observers, 0);
    h.proofs.single.release();
    await Future.wait(replacement.map((ticket) => ticket.result));
  });

  test('reentrant getters cannot overfill the reserved ticket bound', () async {
    final h = _Harness();
    final nested = <NativeControlTicket<void>>[];
    final outer = h.proof(
      remaining: () {
        if (nested.isEmpty) {
          for (var i = 0; i < NativeControlQueue.maximumTickets; i++) {
            nested.add(h.proof());
          }
        }
        return _budget;
      },
    );
    await expectLater(nested.last.result, throwsA(_local('RESOURCE_LIMIT')));
    await _turn();
    // Getter reentrancy seals the old member before nested arrivals issue.
    expect(h.proofs, hasLength(1));
    h.proofs.first.release();
    await _turn();
    if (h.proofs.length == 2) h.proofs.last.release();
    await outer.result;
    await Future.wait(nested.take(nested.length - 1).map((t) => t.result));
  });

  test(
    'all observers get the same actual despite reentrant retirement',
    () async {
      final h = _Harness();
      final secondScope = NativeControlScope();
      final observed = <Future<void>>[];
      final first = h.proof(
        observer: (actual) {
          observed.add(actual);
          secondScope.retire();
        },
      );
      final second = h.proof(scopes: [secondScope], observer: observed.add);
      var secondSettled = false;
      second.settled.then((_) => secondSettled = true).ignore();
      await _turn();
      await expectLater(second.result, throwsA(_local('UNAUTHORIZED')));
      expect(observed, hasLength(2));
      expect(identical(observed.first, h.proofs.single.actual.future), isTrue);
      expect(identical(observed.first, observed.last), isTrue);
      expect(secondSettled, isFalse);
      h.proofs.single.release();
      await Future.wait([first.result, second.settled]);
    },
  );

  test('observer throw affects only its member after physical drain', () async {
    final h = _Harness();
    var failures = 0;
    h.queue.bindFailureHandler(() => failures++);
    final observed = <Future<void>>[];
    final broken = h.proof(observer: (_) => throw StateError('observer'));
    final healthy = h.proof(observer: observed.add);
    var logicallyDone = false;
    broken.result
        .then<void>(
          (_) {},
          onError: (Object _, StackTrace __) {
            logicallyDone = true;
          },
        )
        .ignore();
    await _turn();
    h.proofs.single.actual.complete();
    await _turn();
    expect(logicallyDone, isFalse);
    h.proofs.single.raw.complete();
    await expectLater(broken.result, throwsA(_local('SERVICE_UNAVAILABLE')));
    await healthy.result;
    expect(observed, hasLength(1));
    expect(failures, 0);
    final later = h.proof();
    await _turn();
    h.proofs.last.release();
    await later.result;
  });

  test('observer reentrant arrival gets the next fresh generation', () async {
    final h = _Harness();
    NativeControlTicket<void>? reentrant;
    final first = h.proof(observer: (_) => reentrant = h.proof());
    await _turn();
    expect(h.proofs, hasLength(1));
    h.proofs.first.release();
    await first.result;
    await _turn();
    expect(h.proofs, hasLength(2));
    h.proofs.last.release();
    await reentrant!.result;
  });

  test('pre-admission RESOURCE_LIMIT is local and never retried', () async {
    var calls = 0;
    var observed = 0;
    var failures = 0;
    final queue = NativeControlQueue(
      revalidate: ({observeNativeCompletion}) {
        calls++;
        if (calls == 1) throw StateError('RESOURCE_LIMIT');
        final actual = Future<void>.value();
        observeNativeCompletion?.call(actual);
        return actual;
      },
      verifiedBundleRoot: () async => 'root',
    );
    queue.bindFailureHandler(() => failures++);
    final first = queue.proof(
      remaining: () => _budget,
      observeNativeCompletion: (_) => observed++,
    );
    await expectLater(first.result, throwsA(_local('RESOURCE_LIMIT')));
    await first.settled;
    expect(calls, 1);
    expect(observed, 0);
    final later = queue.proof(remaining: () => _budget);
    await later.result;
    expect(calls, 2);
    expect(failures, 0);
    queue.retire();
  });

  test(
    'actual failure poisons queued work even after logical expiry',
    () async {
      final h = _Harness();
      var failures = 0;
      h.queue.bindFailureHandler(() {
        failures++;
        throw StateError('hook cannot mask failure');
      });
      final expired = h.proof(
        remaining: () => const Duration(milliseconds: 20),
      );
      await expectLater(expired.result, throwsA(isA<TimeoutException>()));
      final queued = h.proof();
      h.proofs.first.actual.completeError(StateError('UNAUTHORIZED'));
      await expectLater(queued.result, throwsA(_state('UNAUTHORIZED')));
      expect(failures, 1);
      final future = h.proof();
      await expectLater(future.result, throwsA(_local('UNAUTHORIZED')));
      h.proofs.first.raw.completeError(StateError('UNAUTHORIZED'));
      await expired.settled;
      expect(h.proofs, hasLength(1));
      expect(failures, 1);
    },
  );

  test('raw failure waits actual and cannot release a next command', () async {
    final h = _Harness();
    final first = h.proof();
    await _turn();
    final later = h.proof();
    h.proofs.first.raw.completeError(StateError('SERVICE_UNAVAILABLE'));
    await expectLater(later.result, throwsA(_state('UNAUTHORIZED')));
    var settled = false;
    first.settled.then((_) => settled = true).ignore();
    await _turn();
    expect(settled, isFalse);
    h.proofs.first.actual.complete();
    await expectLater(first.result, throwsA(_state('SERVICE_UNAVAILABLE')));
    await first.settled;
    expect(h.proofs, hasLength(1));
  });

  test('successful delegate without actual observation fails closed', () async {
    var failures = 0;
    final queue = NativeControlQueue(
      revalidate: ({observeNativeCompletion}) async {},
      verifiedBundleRoot: () async => 'root',
    );
    final invalid = queue.proof(remaining: () => _budget);
    await expectLater(invalid.result, throwsA(_state('SERVICE_UNAVAILABLE')));
    queue.bindFailureHandler(() => failures++);
    expect(failures, 1);
    expect(() => queue.bindFailureHandler(() {}), throwsA(isA<StateError>()));
    await invalid.settled;
  });

  test('FIFO metadata and proof jobs never overlap or cache root', () async {
    final h = _Harness();
    final first = h.queue.bundleRoot(remaining: () => _budget);
    final proof = h.proof();
    final second = h.queue.bundleRoot(remaining: () => _budget);
    final joined = h.proof();
    await _turn();
    expect(h.events, ['metadata']);
    h.roots.first.complete('genuine-first');
    expect(await first.result, 'genuine-first');
    await _turn();
    expect(h.events, ['metadata', 'proof']);
    h.proofs.single.release();
    await Future.wait([proof.result, joined.result]);
    await _turn();
    expect(h.events, ['metadata', 'proof', 'metadata']);
    h.roots.last.complete('genuine-second');
    expect(await second.result, 'genuine-second');
  });

  test('metadata timeout and cancellation retain actual gate', () async {
    final h = _Harness();
    final expired = h.queue.bundleRoot(
      remaining: () => const Duration(milliseconds: 20),
    );
    await expectLater(expired.result, throwsA(isA<TimeoutException>()));
    final queued = h.proof();
    await _turn();
    expect(h.proofs, isEmpty);
    h.roots.single.complete('late-root');
    await expired.settled;
    await _turn();
    expect(h.proofs, hasLength(1));
    h.proofs.single.release();
    await queued.result;
  });

  test(
    'explicit retirement is local, preserves issued drain and no hook',
    () async {
      final h = _Harness();
      var failures = 0;
      h.queue.bindFailureHandler(() => failures++);
      final active = h.proof();
      await _turn();
      final pending = h.proof();
      h.queue.retire();
      await expectLater(active.result, throwsA(_local('UNAUTHORIZED')));
      await expectLater(pending.result, throwsA(_local('UNAUTHORIZED')));
      await pending.settled;
      var closed = false;
      h.queue.settled.then((_) => closed = true).ignore();
      await _turn();
      expect(closed, isFalse);
      expect(failures, 0);
      h.proofs.single.release();
      await Future.wait([active.settled, h.queue.settled]);
      expect(h.proofs, hasLength(1));
      expect(failures, 0);
    },
  );

  test('independent accepted peers never serialize one another', () async {
    final first = _Harness();
    final second = _Harness();
    final a = first.proof();
    final b = second.proof();
    await _turn();
    expect(first.proofs, hasLength(1));
    expect(second.proofs, hasLength(1));
    first.queue.retire();
    await expectLater(a.result, throwsA(_local('UNAUTHORIZED')));
    second.proofs.single.release();
    await b.result;
    first.proofs.single.release();
    await a.settled;
  });
}
