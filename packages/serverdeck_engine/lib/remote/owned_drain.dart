import 'dart:async';

/// Starts and observes every owned cleanup, including synchronous failures.
/// An error is a failed drain, never evidence that the other work has stopped.
Future<void> drainOwned(Iterable<FutureOr<void> Function()> actions) async {
  await Future.wait<void>([
    for (final action in actions) Future<void>.sync(action),
  ], eagerError: true);
}
