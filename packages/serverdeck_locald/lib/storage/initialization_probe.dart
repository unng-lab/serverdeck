/// Compile-time instrumentation for the separate acceptance executable.
/// The normal build removes all guarded calls and cannot install a handler.
const initializationProbesEnabled = bool.fromEnvironment(
  'SERVERDECK_TEST_INITIALIZATION_PROBES',
);

enum InitializationBoundary {
  stagingCreated,
  keyFlushed,
  manifestFlushed,
  nativeFilesCreated,
  uncommittedInitialRows,
  initialTransactionDurable,
  beforePromotion,
  afterPromotion,
  activeOpened,
}

abstract final class InitializationProbe {
  static Future<void> Function(InitializationBoundary)? _handler;

  static void install(Future<void> Function(InitializationBoundary) handler) {
    if (!initializationProbesEnabled || _handler != null) {
      throw StateError('INITIALIZATION_PROBE_UNAVAILABLE');
    }
    _handler = handler;
  }

  static Future<void> reached(InitializationBoundary boundary) {
    if (!initializationProbesEnabled) {
      throw StateError('INITIALIZATION_PROBE_UNAVAILABLE');
    }
    return _handler?.call(boundary) ?? Future<void>.value();
  }
}
