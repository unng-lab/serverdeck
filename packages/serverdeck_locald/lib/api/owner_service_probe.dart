/// Compile-time-only scheduling/failure hooks around real native proof/effects.
/// The hook sees a method name, never credentials, input, roles or native peers.
const ownerServiceProbesEnabled = bool.fromEnvironment(
  'SERVERDECK_TEST_OWNER_SERVICE_PROBES',
);

enum OwnerServiceBoundary { beforeInitialProof, afterFoundationCommit }

abstract final class OwnerServiceProbe {
  static Future<void> Function(OwnerServiceBoundary, String)? _handler;
  static void install(
    Future<void> Function(OwnerServiceBoundary, String) handler,
  ) {
    if (!ownerServiceProbesEnabled || _handler != null)
      throw StateError('OWNER_PROBE_UNAVAILABLE');
    _handler = handler;
  }

  static Future<void> hit(OwnerServiceBoundary boundary, String method) async {
    if (!ownerServiceProbesEnabled) throw StateError('OWNER_PROBE_UNAVAILABLE');
    await _handler?.call(boundary, method);
  }
}
