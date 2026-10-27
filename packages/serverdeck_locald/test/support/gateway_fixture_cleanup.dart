/// Private test diagnostics for a body failure followed by a cleanup failure.
class GatewayFixtureFailure implements Exception {
  const GatewayFixtureFailure({
    required this.primaryError,
    required this.primaryStackTrace,
    required this.cleanupError,
    required this.cleanupStackTrace,
  });

  final Object primaryError;
  final StackTrace primaryStackTrace;
  final Object cleanupError;
  final StackTrace cleanupStackTrace;

  @override
  String toString() =>
      '$primaryError\nGATEWAY_FIXTURE_CLEANUP_FAILURE: $cleanupError\n'
      '$cleanupStackTrace';
}

Future<void> runGatewayFixture({
  required Future<void> Function() body,
  required Future<void> Function() cleanup,
}) async {
  ({Object error, StackTrace stackTrace})? primaryFailure;
  try {
    await body();
  } catch (error, stackTrace) {
    primaryFailure = (error: error, stackTrace: stackTrace);
  }

  try {
    await cleanup();
  } catch (error, stackTrace) {
    final primary = primaryFailure;
    if (primary != null) {
      Error.throwWithStackTrace(
        GatewayFixtureFailure(
          primaryError: primary.error,
          primaryStackTrace: primary.stackTrace,
          cleanupError: error,
          cleanupStackTrace: stackTrace,
        ),
        primary.stackTrace,
      );
    }
    Error.throwWithStackTrace(error, stackTrace);
  }

  final primary = primaryFailure;
  if (primary != null) {
    Error.throwWithStackTrace(primary.error, primary.stackTrace);
  }
}
