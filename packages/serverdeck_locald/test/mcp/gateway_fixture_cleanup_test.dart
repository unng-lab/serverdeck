import 'dart:async';

import 'package:test/test.dart';

import '../support/gateway_fixture_cleanup.dart';

Future<({Object error, StackTrace stackTrace})?> captureFailure(
  Future<void> operation,
) async {
  try {
    await operation;
    return null;
  } catch (error, stackTrace) {
    return (error: error, stackTrace: stackTrace);
  }
}

void main() {
  test('success runs the body and cleanup exactly once', () async {
    final events = <String>[];
    final failure = await captureFailure(
      runGatewayFixture(
        body: () async => events.add('body'),
        cleanup: () async => events.add('cleanup'),
      ),
    );

    expect(failure, isNull);
    expect(events, ['body', 'cleanup']);
  });

  test('body-only failure keeps the error object and original stack', () async {
    final primary = StateError('private body failure');
    final primaryStack = StackTrace.fromString('original body stack');
    var cleanupCalls = 0;
    final failure = await captureFailure(
      runGatewayFixture(
        body: () async => Error.throwWithStackTrace(primary, primaryStack),
        cleanup: () async => cleanupCalls++,
      ),
    );

    expect(failure, isNotNull);
    expect(failure!.error, same(primary));
    expect(failure.stackTrace.toString(), primaryStack.toString());
    expect(cleanupCalls, 1);
  });

  test(
    'cleanup-only failure keeps the error object and original stack',
    () async {
      final secondary = StateError('private cleanup failure');
      final cleanupStack = StackTrace.fromString('original cleanup stack');
      var cleanupCalls = 0;
      final failure = await captureFailure(
        runGatewayFixture(
          body: () async {},
          cleanup: () async {
            cleanupCalls++;
            Error.throwWithStackTrace(secondary, cleanupStack);
          },
        ),
      );

      expect(failure, isNotNull);
      expect(failure!.error, same(secondary));
      expect(failure.stackTrace.toString(), cleanupStack.toString());
      expect(cleanupCalls, 1);
    },
  );

  test(
    'both failures retain both causes and throw with the primary stack',
    () async {
      final primary = TestFailure(
        'Expected: <0>\n  Actual: <41>\nprivate body',
      );
      final secondary = StateError('private cleanup failure');
      final primaryStack = StackTrace.fromString('original body stack');
      final cleanupStack = StackTrace.fromString('original cleanup stack');
      var cleanupCalls = 0;
      final failure = await captureFailure(
        runGatewayFixture(
          body: () async => Error.throwWithStackTrace(primary, primaryStack),
          cleanup: () async {
            cleanupCalls++;
            Error.throwWithStackTrace(secondary, cleanupStack);
          },
        ),
      );

      expect(failure, isNotNull);
      expect(failure!.error, isA<GatewayFixtureFailure>());
      final combined = failure.error as GatewayFixtureFailure;
      expect(combined.primaryError, same(primary));
      expect(combined.primaryStackTrace.toString(), primaryStack.toString());
      expect(combined.cleanupError, same(secondary));
      expect(combined.cleanupStackTrace.toString(), cleanupStack.toString());
      expect(combined.toString(), startsWith(primary.toString()));
      expect(combined.toString(), contains('GATEWAY_FIXTURE_CLEANUP_FAILURE:'));
      expect(combined.toString(), contains(secondary.toString()));
      expect(combined.toString(), contains(cleanupStack.toString()));
      expect(failure.stackTrace.toString(), primaryStack.toString());
      expect(cleanupCalls, 1);
    },
  );

  for (final bodyFails in [false, true]) {
    test('cleanup waits for body settlement and caller waits for cleanup '
        '(body ${bodyFails ? 'fails' : 'succeeds'})', () async {
      final bodyGate = Completer<void>();
      final cleanupStarted = Completer<void>();
      final cleanupGate = Completer<void>();
      final events = <String>[];
      final primary = StateError('private body failure');
      var cleanupCalls = 0;
      var callerSettled = false;
      final result =
          captureFailure(
            runGatewayFixture(
              body: () async {
                events.add('body-start');
                await bodyGate.future;
                events.add('body-settled');
                if (bodyFails) throw primary;
              },
              cleanup: () async {
                cleanupCalls++;
                events.add('cleanup-start');
                cleanupStarted.complete();
                await cleanupGate.future;
                events.add('cleanup-settled');
              },
            ),
          ).then((failure) {
            callerSettled = true;
            return failure;
          });

      expect(events, ['body-start']);
      expect(cleanupCalls, 0);
      expect(callerSettled, isFalse);
      bodyGate.complete();
      await cleanupStarted.future;
      expect(events, ['body-start', 'body-settled', 'cleanup-start']);
      expect(cleanupCalls, 1);
      expect(callerSettled, isFalse);
      cleanupGate.complete();
      final failure = await result;

      expect(callerSettled, isTrue);
      expect(cleanupCalls, 1);
      expect(events, [
        'body-start',
        'body-settled',
        'cleanup-start',
        'cleanup-settled',
      ]);
      if (bodyFails) {
        expect(failure, isNotNull);
        expect(failure!.error, same(primary));
      } else {
        expect(failure, isNull);
      }
    });
  }
}
