import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/process.dart';
import 'package:test/test.dart';

import '../../../serverdeck_windows/test/mcp_build_bundle_test.dart' as b;
import '../support/native_artifact.dart';

void main() {
  late Directory root;
  late String executable, dll;
  setUpAll(() async {
    dll = nativeArtifactForTest();
    root = Directory.systemTemp.createTempSync(
      'serverdeck-mcp-bundle-trusted-write-',
    );
    executable = p.join(root.path, 'actor.exe');
    await b.compilePeer(
      executable,
      source: 'test/support/trusted_open_actor.dart',
    );
  });
  tearDownAll(() {
    b.ownRoot(root.path);
    root.deleteSync(recursive: true);
  });
  for (final mode in [
    'write-good',
    'write-race',
    'write-queue',
    'write-corrupt',
    'write-seeded',
    'write-overflow',
    'write-capacity',
  ]) {
    test(
      'actual trusted store write $mode',
      () async {
        final fixture = b.Fixture(executable);
        try {
          File(dll).copySync(p.join(fixture.path, 'libisar.dll'));
          (fixture.document['sha256'] as Map)['libisar.dll'] = fileSha256(
            p.join(fixture.path, 'libisar.dll'),
          );
          fixture.document['format'] = 3;
          fixture.document['workspaceSchema'] = 3;
          fixture.write();
          final name = mode == 'role-owner'
              ? 'serverdeck.exe'
              : mode == 'role-mcp'
              ? 'mcp.exe'
              : 'locald.exe';
          final child = await Process.start(p.join(fixture.path, name), [
            fixture.path,
            mode,
          ]);
          fixture.children.add(child);
          final output = b.boundedOutput(child.stdout),
              errors = b.boundedOutput(child.stderr);
          fixture.errors.add(errors);
          expect(
            await child.exitCode.timeout(const Duration(seconds: 60)),
            0,
            reason: '${await output}\n${await errors}',
          );
          expect((await output).trim().endsWith('PASS:$mode'), isTrue);
        } finally {
          await fixture.close();
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(seconds: 90)),
    );
  }
}
