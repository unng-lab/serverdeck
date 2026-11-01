import 'dart:async';

import 'package:serverdeck_mcp/entry.dart';

import 'mcp_stdio.dart';

/// Unexpected SDK/library prints cannot become MCP bytes. An uncaught async
/// failure retires only this connector; main physically exits without rejoining
/// possibly blocked output/cleanup. No exception text is forwarded to stdio.
Future<int> runOwnedMcp({
  required McpStdioPort Function() create,
  required Future<int> Function(McpStdioPort port) run,
}) {
  final done = Completer<int>();
  void finish(int code) {
    if (!done.isCompleted) done.complete(code >= 0 && code <= 255 ? code : 1);
  }

  runZonedGuarded(
    () async {
      try {
        final port = create();
        finish(await run(port));
      } catch (_) {
        finish(1);
      }
    },
    (Object _, StackTrace _) => finish(1),
    zoneSpecification: ZoneSpecification(print: (_, _, _, _) {}),
  );
  return done.future;
}

Future<int> runDesktopMcp(String? grantId) => runOwnedMcp(
  create: ChannelMcpStdioPort.new,
  run: (port) => runMcpStdio(port: port, grantId: grantId),
);
