import 'dart:async';

import 'src/bootstrap.dart';
import 'src/stdio.dart';
import 'stdio_port.dart';

export 'stdio_port.dart';

/// Called only by serverdeck.exe's --mcp-stdio branch, before runApp. A nonzero
/// result requires exiting this owned connector process, never joining the same
/// uncertain cleanup/flush twice. This does not terminate the desktop app.
Future<int> runMcpStdio({required McpStdioPort port, String? grantId}) async {
  McpProcessBootstrap? bootstrap;
  var code = 1;
  try {
    await port.ready.timeout(const Duration(seconds: 5));
    bootstrap = McpProcessBootstrap(grantId: grantId);
    code = await serveMcpStdio(await bootstrap.connect(), port);
  } catch (e) {
    const codes = {
      'PREREQUISITE_UNAVAILABLE',
      'INCOMPATIBLE',
      'FORBIDDEN',
      'STORAGE_BLOCKED',
      'TIMEOUT',
      'SERVICE_UNAVAILABLE',
      'NOT_READY',
      'UNAUTHORIZED',
    };
    final reason = e is StateError && codes.contains(e.message)
        ? e.message
        : 'STARTUP_FAILED';
    try {
      port.diagnostic(reason);
      await port.flushDiagnostics().timeout(const Duration(seconds: 1));
    } catch (_) {
      /* Fixed diagnostics cannot hold process exit. */
    }
  } finally {
    if (code == 0) {
      try {
        await bootstrap?.close().timeout(const Duration(seconds: 5));
        await port.close().timeout(const Duration(seconds: 5));
      } catch (_) {
        code = 1;
      }
    }
  }
  return code;
}
