import '../stdio_port.dart';
import 'local_gateway.dart';
import 'server.dart';

/// Process composition through an owned, asynchronous byte carrier. The Windows
/// entry supplies original handles isolated from Flutter/SDK logging.
/// On nonzero return the executable must terminate its owned process instead
/// of awaiting a still-live flush/lease a second time.
Future<int> serveMcpStdio(LocalMcpGateway gateway, McpStdioPort port) async {
  var messages = 0;
  final code = await McpServer(
    input: port.input,
    write: port.write,
    gateway: gateway,
    diagnostic: (value) {
      // Fixed engine codes only, with bounded queueing even if stderr stalls.
      if (messages < 32) {
        messages++;
        port.diagnostic(value);
      }
    },
  ).run();
  try {
    await port.flushDiagnostics().timeout(const Duration(seconds: 1));
  } catch (_) {
    // Diagnostics cannot block terminal shutdown or contain raw I/O errors.
  }
  return code;
}
