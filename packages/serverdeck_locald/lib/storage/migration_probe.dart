/// Compile-time instrumentation; no runtime installer in ordinary builds.
const migrationProbesEnabled = bool.fromEnvironment(
  'SERVERDECK_TEST_MIGRATION_PROBES',
);

enum MigrationBoundary {
  sourceValidated,
  journalFlushed,
  backupCopied,
  sourceRowsValidated,
  nativeSchemaOpened,
  uncommittedMarker,
  markerCommitted,
  candidateClosed,
  preparedJournal,
  databasePublished,
  targetVerified,
  manifestPublished,
  cleanupFile,
  journalRemoved,
  stageRemoved,
  nativeCapacityFailure,
}

abstract final class MigrationProbe {
  static Future<void> Function(MigrationBoundary)? _handler;
  static int Function(int)? _minimumFreeBytes;
  static Future<bool> Function(Future<bool> Function())? _closeNative;

  static void install(
    Future<void> Function(MigrationBoundary) handler, {
    int Function(int)? minimumFreeBytes,
    Future<bool> Function(Future<bool> Function())? closeNative,
  }) {
    if (!migrationProbesEnabled || _handler != null)
      throw StateError('MIGRATION_PROBE_UNAVAILABLE');
    _handler = handler;
    _minimumFreeBytes = minimumFreeBytes;
    _closeNative = closeNative;
  }

  static Future<void> reached(MigrationBoundary boundary) {
    if (!migrationProbesEnabled)
      throw StateError('MIGRATION_PROBE_UNAVAILABLE');
    return _handler?.call(boundary) ?? Future<void>.value();
  }

  /// Fault injection only. The ordinary build calls its native space query
  /// directly; a test may demand more actual caller-available bytes to deny it.
  static int minimumFreeBytes(int required) {
    if (!migrationProbesEnabled)
      throw StateError('MIGRATION_PROBE_UNAVAILABLE');
    return _minimumFreeBytes?.call(required) ?? required;
  }

  /// A test may withhold or throw during native close, leaving the actual Isar
  /// instance live. The component must retain reservation/lease until exit.
  static Future<bool> closeNative(Future<bool> Function() actualClose) {
    if (!migrationProbesEnabled)
      throw StateError('MIGRATION_PROBE_UNAVAILABLE');
    return _closeNative?.call(actualClose) ?? actualClose();
  }
}
