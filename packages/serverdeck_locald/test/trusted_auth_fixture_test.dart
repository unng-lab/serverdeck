import 'dart:async';

import 'package:test/test.dart';

import '../../serverdeck_windows/test/support/trusted_client_fixture.dart';
import 'support/trusted_auth_fixture.dart';

Future<(Object, StackTrace)> failure<T>(Future<T> future) async {
  try {
    await future;
  } catch (error, stack) {
    return (error, stack);
  }
  throw StateError('EXPECTED_FAILURE');
}

void expectBoth(
  (Object, StackTrace) outcome,
  Object primary,
  StackTrace primaryStack,
  Object secondary,
  StackTrace secondaryStack,
) {
  expect(outcome.$1, isA<OwnedFixtureFailure>());
  final aggregate = outcome.$1 as OwnedFixtureFailure;
  expect(aggregate.primary, same(primary));
  expect(aggregate.primaryStack, same(primaryStack));
  expect(aggregate.secondary, same(secondary));
  expect(aggregate.secondaryStack, same(secondaryStack));
  expect(outcome.$2, same(primaryStack));
  expect(
    aggregate.toString(),
    '$primary\nOWNED_FIXTURE_CLEANUP_FAILURE:\n$secondary\n$secondaryStack',
  );
}

void main() {
  group('reused owned lifecycle', () {
    test(
      'body settles, cleanup runs once and caller awaits its completion',
      () async {
        final body = Completer<void>(), cleanup = Completer<void>();
        final order = <String>[];
        var cleanupCalls = 0, failureCalls = 0, finished = false;
        final result = runOwnedFixtureLifecycle(
          body: () async {
            order.add('body');
            await body.future;
            order.add('settled');
          },
          cleanup: () async {
            cleanupCalls++;
            order.add('cleanup');
            await cleanup.future;
            order.add('cleaned');
          },
          onFirstFailure: (_, _) => failureCalls++,
        ).then((_) => finished = true);
        await Future<void>.value();
        expect(order, ['body']);
        expect(cleanupCalls, 0);
        body.complete();
        await Future<void>.value();
        expect(order, ['body', 'settled', 'cleanup']);
        expect(cleanupCalls, 1);
        expect(finished, isFalse);
        cleanup.complete();
        await result;
        expect(order, ['body', 'settled', 'cleanup', 'cleaned']);
        expect(cleanupCalls, 1);
        expect(finished, isTrue);
        expect(failureCalls, 0);
      },
    );

    for (final bodyFails in [true, false]) {
      test('single body=$bodyFails failure retains object and stack', () async {
        final error = StateError('PRIVATE_SINGLE');
        final stack = StackTrace.fromString('PRIVATE_SINGLE_STACK');
        var cleanupCalls = 0;
        final observed = <(Object, StackTrace)>[];
        final outcome = await failure(
          runOwnedFixtureLifecycle(
            body: () async {
              if (bodyFails) Error.throwWithStackTrace(error, stack);
            },
            cleanup: () async {
              cleanupCalls++;
              if (!bodyFails) Error.throwWithStackTrace(error, stack);
            },
            onFirstFailure: (first, firstStack) {
              observed.add((first, firstStack));
              throw StateError('PRIVATE_OBSERVER_REFUSED');
            },
          ),
        );
        expect(outcome.$1, same(error));
        expect(outcome.$2, same(stack));
        expect(cleanupCalls, 1);
        expect(observed.length, 1);
        expect(observed.single.$1, same(error));
        expect(observed.single.$2, same(stack));
      });
    }

    test(
      'both failures retain primary stack and exact private secondary suffix',
      () async {
        final primary = StateError('PRIVATE_BODY');
        final secondary = StateError('PRIVATE_CLEANUP');
        final primaryStack = StackTrace.fromString('PRIVATE_BODY_STACK');
        final secondaryStack = StackTrace.fromString('PRIVATE_CLEANUP_STACK');
        var cleanupCalls = 0;
        final observed = <(Object, StackTrace)>[];
        final outcome = await failure(
          runOwnedFixtureLifecycle(
            body: () async => Error.throwWithStackTrace(primary, primaryStack),
            cleanup: () async {
              cleanupCalls++;
              expect(observed.length, 1);
              Error.throwWithStackTrace(secondary, secondaryStack);
            },
            onFirstFailure: (error, stack) {
              observed.add((error, stack));
              throw StateError('PRIVATE_OBSERVER_REFUSED');
            },
          ),
        );
        expectBoth(outcome, primary, primaryStack, secondary, secondaryStack);
        expect(cleanupCalls, 1);
        expect(observed.length, 1);
        expect(observed.single.$1, same(primary));
        expect(observed.single.$2, same(primaryStack));
      },
    );
  });

  group('actual trusted-auth startup adapter', () {
    test(
      'successful pair-like result stays open and preserves identity',
      () async {
        final pair = _PairLike();
        var cleanupCalls = 0;
        final result = await runTrustedAuthStartup(
          start: () async => pair,
          cleanup: () async {
            cleanupCalls++;
            pair.closed = true;
          },
        );
        expect(result, same(pair));
        expect(pair.closed, isFalse);
        expect(cleanupCalls, 0);
      },
    );

    test(
      'nullable null is successful and leaves failed-start resources alone',
      () async {
        var cleanupCalls = 0;
        final result = await runTrustedAuthStartup<_PairLike?>(
          start: () async => null,
          cleanup: () async => cleanupCalls++,
        );
        expect(result, isNull);
        expect(cleanupCalls, 0);
      },
    );

    test('failed startup awaits cleanup once after settlement and retains original', () async {
      final start = Completer<_PairLike>(), cleanup = Completer<void>();
      final primary = StateError('PRIVATE_STARTUP');
      final stack = StackTrace.fromString('PRIVATE_STARTUP_STACK');
      var cleanupCalls = 0, finished = false;
      final outcomeFuture =
          failure(
            runTrustedAuthStartup(
              start: () => start.future,
              cleanup: () async {
                cleanupCalls++;
                await cleanup.future;
              },
            ),
          ).then((outcome) {
            finished = true;
            return outcome;
          });
      await Future<void>.value();
      expect(cleanupCalls, 0);
      start.completeError(primary, stack);
      await Future<void>.value();
      expect(cleanupCalls, 1);
      expect(finished, isFalse);
      cleanup.complete();
      final outcome = await outcomeFuture;
      expect(outcome.$1, same(primary));
      expect(outcome.$2, same(stack));
      expect(cleanupCalls, 1);
      expect(finished, isTrue);
    });

    test('failed startup and cleanup retain both causes and primary throwing stack', () async {
      final primary = StateError('PRIVATE_STARTUP');
      final secondary = StateError('PRIVATE_FAILED_START_CLEANUP');
      final primaryStack = StackTrace.fromString('PRIVATE_STARTUP_STACK');
      final secondaryStack = StackTrace.fromString(
        'PRIVATE_FAILED_START_CLEANUP_STACK',
      );
      var cleanupCalls = 0;
      final outcome = await failure(
        runTrustedAuthStartup<_PairLike>(
          start: () async => Error.throwWithStackTrace(primary, primaryStack),
          cleanup: () async {
            cleanupCalls++;
            Error.throwWithStackTrace(secondary, secondaryStack);
          },
        ),
      );
      expectBoth(outcome, primary, primaryStack, secondary, secondaryStack);
      expect(cleanupCalls, 1);
    });
  });
}

final class _PairLike {
  bool closed = false;
}
