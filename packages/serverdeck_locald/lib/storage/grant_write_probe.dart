/// Test builds can stop/fail at actual native/publication boundaries. No runtime
/// setting enables this, and the hook receives no mutable input or credential.
const grantWriteProbesEnabled = bool.fromEnvironment(
  'SERVERDECK_TEST_GRANT_WRITE_PROBES',
);

enum GrantWriteBoundary {
  beforeStage,
  afterStage,
  beforeTransaction,
  afterGrantWrite,
  afterReceiptWrite,
  afterCommit,
  beforePublication,
  afterPublication,
  beforeAcknowledgement,
}

abstract final class GrantWriteProbe {
  static Future<void> Function(GrantWriteBoundary)? _handler;
  static void install(Future<void> Function(GrantWriteBoundary) handler) {
    if (!grantWriteProbesEnabled || _handler != null)
      throw StateError('GRANT_PROBE_UNAVAILABLE');
    _handler = handler;
  }

  static Future<void> hit(GrantWriteBoundary boundary) async {
    if (!grantWriteProbesEnabled) throw StateError('GRANT_PROBE_UNAVAILABLE');
    await _handler?.call(boundary);
  }
}
