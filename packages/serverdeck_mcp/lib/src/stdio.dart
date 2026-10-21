import 'dart:io';

import 'local_gateway.dart';
import 'server.dart';

/// Process stdio composition. Stdout's default sink is synchronous; using it
/// would block the isolate and prevent writer/cancellation deadlines firing.
/// On nonzero return the executable must terminate its owned process instead
/// of awaiting a still-live flush/lease a second time.
Future<int> serveMcpStdio(LocalMcpGateway gateway) async {
  final output = stdout.nonBlocking;
  final diagnostics = stderr.nonBlocking;
  output.done.ignore();
  diagnostics.done.ignore();
  var messages = 0;
  final code = await McpServer(
    input: stdin,
    write: (bytes) {
      output.add(bytes);
      return output.flush();
    },
    gateway: gateway,
    diagnostic: (value) {
      // Fixed engine codes only, with bounded queueing even if stderr stalls.
      if (messages < 32) {
        messages++;
        diagnostics.writeln('MCP:$value');
      }
    },
  ).run();
  try {
    await diagnostics.flush().timeout(const Duration(seconds: 1));
  } catch (_) {
    // Diagnostics cannot block terminal shutdown or contain raw I/O errors.
  }
  return code;
}
