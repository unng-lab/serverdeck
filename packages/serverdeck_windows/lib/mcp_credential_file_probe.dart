/// Compile-time test instrumentation. Never enabled by runtime configuration.
const mcpCredentialFileProbesEnabled = bool.fromEnvironment(
  'SERVERDECK_TEST_MCP_FILE_PROBES',
);

enum McpLookupWriteBoundary { afterPending, afterRename, afterReadback }

abstract final class McpCredentialFileProbe {
  static int? _minimum;
  static Future<void> Function(McpLookupWriteBoundary)? _boundary;

  /// Only test-compiled children may observe actual completed lookup operations.
  /// No data or credential is supplied, and native operations are never replaced.
  static void installBoundary(
    Future<void> Function(McpLookupWriteBoundary) handler,
  ) {
    if (!mcpCredentialFileProbesEnabled || _boundary != null) {
      throw StateError('MCP_FILE_PROBE_UNAVAILABLE');
    }
    _boundary = handler;
  }

  static Future<void> hit(McpLookupWriteBoundary boundary) async {
    if (!mcpCredentialFileProbesEnabled) {
      throw StateError('MCP_FILE_PROBE_UNAVAILABLE');
    }
    await _boundary?.call(boundary);
  }

  /// Tests may only demand MORE actual caller-available disk space, never bypass
  /// the native check. A child process isolates the one-time installation.
  static void installMinimumBytes(int minimum) {
    if (!mcpCredentialFileProbesEnabled ||
        _minimum != null ||
        minimum < 128 * 1024) {
      throw StateError('MCP_FILE_PROBE_UNAVAILABLE');
    }
    _minimum = minimum;
  }

  static int minimumBytes(int normal) {
    if (!mcpCredentialFileProbesEnabled) {
      throw StateError('MCP_FILE_PROBE_UNAVAILABLE');
    }
    final requested = _minimum ?? normal;
    return requested < normal ? normal : requested;
  }
}
