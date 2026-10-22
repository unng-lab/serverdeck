import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/process.dart';
import 'package:test/test.dart';

import '../../../serverdeck_windows/test/mcp_build_bundle_test.dart' as b;
import '../support/native_artifact.dart';

void main() {
  late Directory compiled;
  late String exe, dll;
  setUpAll(() async {
    dll = nativeArtifactForTest();
    compiled = Directory.systemTemp.createTempSync(
      'serverdeck-mcp-bundle-catalog-',
    );
    b.ownRoot(compiled.path);
    exe = p.join(compiled.path, 'catalog.exe');
    final compiler = await Process.start(Platform.resolvedExecutable, [
      'compile',
      'exe',
      '-DSERVERDECK_TEST_GRANT_WRITE_PROBES=true',
      '-DSERVERDECK_TEST_OWNER_SERVICE_PROBES=true',
      '-DSERVERDECK_TEST_NATIVE_OBSERVATION=true',
      'test/support/profile_catalog_actor.dart',
      '-o',
      exe,
    ]);
    final output = b.boundedOutput(compiler.stdout),
        errors = b.boundedOutput(compiler.stderr);
    try {
      expect(
        await compiler.exitCode.timeout(const Duration(seconds: 90)),
        0,
        reason: '${await output}\n${await errors}',
      );
    } finally {
      compiler.kill();
      await compiler.exitCode.timeout(const Duration(seconds: 10));
    }
  });
  tearDownAll(() {
    b.ownRoot(compiled.path);
    compiled.deleteSync(recursive: true);
  });
  for (final mode in [
    'wire',
    'unicode',
    'key-boundary',
    'foreign-binding',
    'authors',
    'cursor',
    'permissions',
    'gate',
    'close',
    'admitted-disconnect',
    'overlap-current',
    'overlap-expiry',
    'overlap-timeout',
    'overlap-close',
    'overlap-authority-close',
    'grant-replace',
    'grant-revoke',
    'grant-unrelated',
    'grant-blocked',
    'entry-race',
    'retention-timeout',
    'retention-scheduler-first',
    'snapshot-conflict',
    'snapshot-revoke',
    'physical-gate',
    'physical-gate-failure',
    'physical-proof',
    'physical-proof-failure',
    'physical-observer',
    'physical-release-failure',
  ]) {
    test(
      'actual native shared profile catalog $mode',
      () async {
        final fixture = b.Fixture(exe);
        try {
          File(dll).copySync(p.join(fixture.path, 'libisar.dll'));
          (fixture.document['sha256'] as Map)['libisar.dll'] = fileSha256(
            p.join(fixture.path, 'libisar.dll'),
          );
          fixture.write();
          final child = await Process.start(
            p.join(fixture.path, 'locald.exe'),
            [fixture.path, mode],
          );
          fixture.children.add(child);
          final output = b.boundedOutput(child.stdout),
              errors = b.boundedOutput(child.stderr);
          expect(
            await child.exitCode.timeout(const Duration(seconds: 90)),
            0,
            reason: '${await output}\n${await errors}',
          );
          expect((await output).trim().endsWith('PASS:$mode'), true);
          if (mode == 'physical-release-failure')
            expect(
              await output,
              contains(
                'ACTUAL_WRONG_THREAD_MUTEX_RELEASE_DENIED_OWNER_CLEANUP_PROVED',
              ),
            );
        } finally {
          await fixture.close();
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(seconds: 120)),
    );
  }
}
