import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../serverdeck_windows/test/mcp_build_bundle_test.dart' as b;

void main() {
  late Directory compiled;
  late String executable;
  setUpAll(() async {
    compiled = Directory.systemTemp.createTempSync(
      'serverdeck-mcp-bundle-server-constructor-',
    );
    executable = p.join(compiled.path, 'actor.exe');
    await b.compilePeer(
      executable,
      source: 'test/support/server_constructor_actor.dart',
    );
  });
  tearDownAll(() {
    b.ownRoot(compiled.path);
    compiled.deleteSync(recursive: true);
  });
  for (final format in [2, 3]) {
    for (final image in ['serverdeck.exe', 'mcp.exe']) {
      test(
        'actual format$format server constructor refuses client-side $image before token copy',
        () async {
          final fixture = b.Fixture(executable);
          try {
            fixture.document['format'] = format;
            fixture.document['workspaceSchema'] = format;
            fixture.write();
            final name =
                r'\\.\pipe\ServerDeckNext.v1.' +
                List.generate(
                  32,
                  (_) => Random.secure()
                      .nextInt(256)
                      .toRadixString(16)
                      .padLeft(2, '0'),
                ).join() +
                '.0';
            final child = await Process.start(
              p.join(fixture.path, 'locald.exe'),
              ['server', fixture.path, name, '$format', image],
            );
            fixture.children.add(child);
            final output = b.boundedOutput(child.stdout),
                errors = b.boundedOutput(child.stderr);
            final code = await child.exitCode.timeout(
              const Duration(seconds: 25),
            );
            expect(code, 0, reason: '${await output}\n${await errors}');
            expect((await output).trim(), 'PASS');
            expect(await errors, isEmpty);
          } finally {
            await fixture.close();
          }
        },
        testOn: 'windows',
        timeout: const Timeout(Duration(seconds: 40)),
      );
    }
  }
}
