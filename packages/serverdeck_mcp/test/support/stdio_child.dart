import 'dart:io';

import 'package:serverdeck_mcp/src/server.dart';

// Synthetic unconfigured adapter for OS-pipe transport tests only. This is not
// the product executable, a locald adapter, or authenticated acceptance evidence.
final class UnconfiguredGateway implements McpGateway {
  @override
  McpInvocation start(String method, Map<String, Object?> params) =>
      McpInvocation(
        Future.value(
          method == 'tools/list'
              ? <String, Object?>{'tools': []}
              : <String, Object?>{
                  'content': [
                    {
                      'type': 'text',
                      'text': '{"ok":false,"error":{"code":"FORBIDDEN","boundary":"local","retry":"none"}}',
                    },
                  ],
                  'structuredContent': {
                    'ok': false,
                    'error': {
                      'code': 'FORBIDDEN',
                      'boundary': 'local',
                      'retry': 'none',
                    },
                  },
                  'isError': true,
                },
        ),
        () async {},
      );
  @override
  Future<void> close() async {}
}

Future<void> main() async {
  exit(
    await McpServer(
      input: stdin,
      gateway: UnconfiguredGateway(),
      write: (bytes) async {
        stdout.add(bytes);
        await stdout.flush();
      },
      diagnostic: stderr.writeln,
    ).run(),
  );
}
