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
      'serverdeck-mcp-bundle-trusted-runtime-',
    );
    b.ownRoot(root.path);
    executable = p.join(root.path, 'actor.exe');
    await b.compilePeer(
      executable,
      source: 'test/support/trusted_runtime_actor.dart',
    );
  });
  tearDownAll(() {
    b.ownRoot(root.path);
    root.deleteSync(recursive: true);
  });
  for (final mode in [
    'good',
    'role-owner',
    'role-mcp',
    'legacy-refusal',
    'format2-refusal',
    'format3-to2',
    'format1-to3',
    'format3-to1',
    'build-conflict',
    'test-selection',
    'load-failure',
  ]) {
    test(
      'actual format3 native runtime $mode',
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
          final action = mode.startsWith('role-') ? 'role' : mode;
          final child = await Process.start(p.join(fixture.path, name), [
            fixture.path,
            action,
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
          expect((await output).trim().endsWith('PASS:$action'), isTrue);
        } finally {
          await fixture.close();
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(seconds: 90)),
    );
  }
}
