import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/entry_mode.dart';

void main() {
  const grant = '12345678-1234-4234-9234-123456789abc';
  test(
    'normal app and stdio mode are explicit and independent of mutable argv',
    () {
      final app = ServerDeckLaunch.parse([]);
      expect(app.mode, ServerDeckMode.application);
      expect(app.grantId, isNull);
      final unconfigured = ServerDeckLaunch.parse(['--mcp-stdio']);
      expect(unconfigured.mode, ServerDeckMode.mcpStdio);
      expect(unconfigured.grantId, isNull);
      final arguments = ['--mcp-stdio', '--grant-id', grant];
      final bridge = ServerDeckLaunch.parse(arguments);
      arguments.clear();
      expect(bridge.mode, ServerDeckMode.mcpStdio);
      expect(bridge.grantId, grant);
    },
  );

  test(
    'legacy, ambiguous and authority-bearing arguments fail without echo',
    () {
      for (final arguments in <List<String>>[
        ['--app-root', 'private-path', '--grant-id', grant],
        ['--grant-id', grant],
        ['--mcp-stdio', '--owner'],
        ['--mcp-stdio', '--grant-id', 'private-invalid-id'],
        ['--mcp-stdio', '--grant-id', grant.toUpperCase()],
        ['--mcp-stdio', '--grant-id', grant, '--mcp-stdio'],
        ['--mcp-stdio', '--grant-id', grant, '--grant-id', grant],
        ['--mcp-stdio', '--app-root', 'private-path'],
        ['--locald'],
      ]) {
        expect(
          () => ServerDeckLaunch.parse(arguments),
          throwsA(
            isA<FormatException>()
                .having((error) => error.message, 'safe reason', 'ARGUMENTS')
                .having((error) => error.source, 'no private source', isNull),
          ),
        );
      }
    },
  );
}
