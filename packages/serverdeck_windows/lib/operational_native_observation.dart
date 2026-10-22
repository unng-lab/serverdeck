part of 'pipe_worker.dart';

/// Scheduling observation only, unavailable in production/runtime settings.
const operationalNativeObservationEnabled = bool.fromEnvironment(
  'SERVERDECK_TEST_NATIVE_OBSERVATION',
);

final class OperationalNativeObservation {
  OperationalNativeObservation._(this.reached, this._release) {
    reached.ignore();
  }
  final Future<void> reached;
  final Future<void> Function() _release;
  Future<void>? _released;
  Future<void> release() => _released ??= Future<void>.sync(_release);
}

final class _NativeObservationPause {
  _NativeObservationPause() {
    reached.future.ignore();
  }
  final reached = Completer<void>(), released = Completer<void>();
  Future<void> hit() async {
    if (!reached.isCompleted) reached.complete();
    await released.future;
  }

  void retire() {
    if (!reached.isCompleted)
      reached.completeError(StateError('SERVICE_UNAVAILABLE'));
    if (!released.isCompleted) released.complete();
  }
}
