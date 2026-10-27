import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_mcp/src/bootstrap.dart';
import 'package:serverdeck_mcp/src/local_gateway.dart';
import 'package:serverdeck_mcp/src/stdio.dart';

Future<void> main(List<String> arguments) async {
  McpProcessBootstrap? bootstrap;
  var code = 1;
  try {
    if (arguments.isEmpty) {
      code = await serveMcpStdio(LocalMcpGateway.unconfigured());
    } else {
      if (arguments.length != 4 ||
          arguments[0] != '--app-root' ||
          arguments[2] != '--grant-id' ||
          !p.isAbsolute(arguments[1]))
        throw const FormatException('ARGUMENTS');
      requireUuid(arguments[3]);
      bootstrap = await McpProcessBootstrap.prepare(arguments[1], arguments[3]);
      code = await serveMcpStdio(await bootstrap.connect());
    }
  } on Object catch (error) {
    // No paths, credential contents, raw native errors or protocol text on stdout.
    final diagnostics = stderr.nonBlocking;
    diagnostics.done.ignore();
    const safeStartupCodes = {
      'PREREQUISITE_UNAVAILABLE',
      'INCOMPATIBLE',
      'FORBIDDEN',
      'STORAGE_BLOCKED',
      'TIMEOUT',
      'SERVICE_UNAVAILABLE',
    };
    final reason =
        error is StateError && safeStartupCodes.contains(error.message)
        ? error.message
        : 'STARTUP_FAILED';
    diagnostics.writeln('MCP:$reason');
    try {
      await diagnostics.flush().timeout(const Duration(seconds: 1));
    } on Object {
      /* Bounded diagnostics cannot hold process termination. */
    }
  } finally {
    // A nonzero stdio result denotes a terminal outstanding native/write owner;
    // process exit must not join the same hung settlement a second time.
    if (code == 0) {
      try {
        await bootstrap?.close();
      } on Object {
        code = 1;
      }
    }
  }
  exit(code);
}
