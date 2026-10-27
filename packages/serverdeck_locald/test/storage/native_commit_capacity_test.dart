import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../serverdeck_windows/test/mcp_build_bundle_test.dart' as b;
import '../support/native_artifact.dart';

void main() {
  late Directory compiled;
  late String exe, dll;
  setUpAll(() async {
    dll = nativeArtifactForTest();
    compiled = Directory.systemTemp.createTempSync(
      'serverdeck-mcp-bundle-commit-build-',
    );
    b.ownRoot(compiled.path);
    exe = p.join(compiled.path, 'commit.exe');
    await b.compilePeer(
      exe,
      source: 'test/support/native_commit_capacity_child.dart',
    );
  });
  tearDownAll(() {
    b.ownRoot(compiled.path);
    compiled.deleteSync(recursive: true);
  });
  for (final mode in ['async', 'sync']) {
    test(
      'actual native commit-time capacity preserves process and recovery $mode',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'serverdeck-mcp-bundle-commit-$mode-',
        );
        b.ownRoot(root.path);
        Process? child;
        try {
          File(dll).copySync(p.join(root.path, 'libisar.dll'));
          child = await Process.start(exe, [root.path, mode]);
          final output = b.boundedOutput(child.stdout),
              errors = b.boundedOutput(child.stderr);
          expect(
            await child.exitCode.timeout(const Duration(seconds: 60)),
            0,
            reason: '${await output}\n${await errors}',
          );
          expect(
            (await output).trim().endsWith('PASS:commit-capacity:$mode'),
            true,
          );
        } finally {
          if (child != null) {
            child.kill();
            await child.exitCode.timeout(const Duration(seconds: 10));
          }
          b.ownRoot(root.path);
          root.deleteSync(recursive: true);
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(seconds: 80)),
    );
  }
}
