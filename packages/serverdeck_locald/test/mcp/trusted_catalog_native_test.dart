import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/process.dart';
import 'package:test/test.dart';

import '../../../serverdeck_windows/test/mcp_build_bundle_test.dart' as b;
import '../support/native_artifact.dart';

void main() {
  late Directory compiled;
  late String exe, observedExe, dll;
  setUpAll(() async {
    dll = nativeArtifactForTest();
    compiled = Directory.systemTemp.createTempSync(
      'serverdeck-mcp-bundle-trusted-catalog-',
    );
    b.ownRoot(compiled.path);
    exe = p.join(compiled.path, 'catalog.exe');
    await b.compilePeer(exe, source: 'test/support/trusted_catalog_actor.dart');
    observedExe = p.join(compiled.path, 'observed.exe');
    final child = await Process.start(Platform.resolvedExecutable, [
      'compile',
      'exe',
      '-DSERVERDECK_TEST_NATIVE_OBSERVATION=true',
      'test/support/trusted_catalog_actor.dart',
      '-o',
      observedExe,
    ]);
    final output = b.boundedOutput(child.stdout),
        errors = b.boundedOutput(child.stderr);
    try {
      expect(
        await child.exitCode.timeout(const Duration(seconds: 90)),
        0,
        reason: '${await output}\n${await errors}',
      );
    } finally {
      child.kill();
      await child.exitCode.timeout(const Duration(seconds: 10));
    }
  });
  tearDownAll(() {
    b.ownRoot(compiled.path);
    compiled.deleteSync(recursive: true);
  });
  for (final mode in [
    'basic',
    'cursor',
    'revoke',
    'replace',
    'foreign',
    'close',
    'gate',
    'custody',
    'physical-proof',
    'physical-proof-failure',
    'physical-gate',
    'physical-gate-failure',
  ]) {
    test(
      'actual trusted shared profile catalog $mode',
      () async {
        final fixture = b.Fixture(
          mode.startsWith('physical-') ? observedExe : exe,
        );
        try {
          File(dll).copySync(p.join(fixture.path, 'libisar.dll'));
          (fixture.document['sha256'] as Map)['libisar.dll'] = fileSha256(
            p.join(fixture.path, 'libisar.dll'),
          );
          fixture.document['format'] = 3;
          fixture.document['workspaceSchema'] = 3;
          fixture.write();
          final child = await Process.start(
            p.join(fixture.path, 'locald.exe'),
            [fixture.path, mode],
          );
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
