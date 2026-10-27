import 'package:serverdeck_windows/security.dart';
import 'package:test/test.dart';

import 'support/thread_identity_probe.dart';

Matcher observationFailure() => throwsA(
  isA<StateError>().having(
    (error) => error.message,
    'probe failure',
    'THREAD_PROCESS_SID_QUERY_UNAVAILABLE',
  ),
);

void main() {
  test(
    'SID observation failure before operation cannot confirm native refusal',
    () {
      var called = false;
      expect(
        () => observeThreadIdentity(() {
          called = true;
        }, processSidQuery: () => throw StateError('IDENTITY_UNAVAILABLE')),
        observationFailure(),
      );
      expect(called, false);
    },
    testOn: 'windows',
  );

  test(
    'SID observation failure after native refusal overrides its expected code',
    () {
      var queries = 0;
      var called = false;
      expect(
        () => observeThreadIdentity(
          () {
            called = true;
            throw StateError('IDENTITY_UNAVAILABLE');
          },
          processSidQuery: () {
            if (++queries == 1) return currentUserSid();
            throw StateError('IDENTITY_UNAVAILABLE');
          },
        ),
        observationFailure(),
      );
      expect(called, true);
      expect(queries, 2);
    },
    testOn: 'windows',
  );

  test(
    'successful real observations preserve original operation error object',
    () {
      final original = StateError('IDENTITY_UNAVAILABLE');
      expect(
        () => observeThreadIdentity(() => throw original),
        throwsA(same(original)),
      );
    },
    testOn: 'windows',
  );
}
