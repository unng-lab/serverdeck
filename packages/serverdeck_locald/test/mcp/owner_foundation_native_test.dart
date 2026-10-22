@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/process.dart';
import 'package:test/test.dart';

import '../../../serverdeck_windows/test/mcp_build_bundle_test.dart' as b;
import '../support/native_artifact.dart';

void main() {
  late Directory compiled;
  late String ordinary, probed, dll;
  setUpAll(() async {
    dll = nativeArtifactForTest();
    compiled = Directory.systemTemp.createTempSync(
      'serverdeck-mcp-bundle-owner-foundation-',
    );
    b.ownRoot(compiled.path);
    ordinary = p.join(compiled.path, 'ordinary.exe');
    probed = p.join(compiled.path, 'probed.exe');
    await b.compilePeer(
      ordinary,
      source: 'test/support/owner_foundation_actor.dart',
    );
    final compiler = await Process.start(Platform.resolvedExecutable, [
      'compile',
      'exe',
      '-DSERVERDECK_TEST_OWNER_SERVICE_PROBES=true',
      'test/support/owner_foundation_actor.dart',
      '-o',
      probed,
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
    'probe-disabled',
    'gate',
    'proof',
    'proof-peer-exit',
    'proof-close',
    'cancel',
    'close',
    'wire',
    'wire-mcp',
  ]) {
    test(
      'actual native owner foundation $mode',
      () async {
        final fixture = b.Fixture(
          const {
                'proof',
                'proof-peer-exit',
                'proof-close',
                'cancel',
                'close',
              }.contains(mode)
              ? probed
              : ordinary,
        );
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
          fixture.errors.add(errors);
          expect(
            await child.exitCode.timeout(const Duration(seconds: 65)),
            0,
            reason: '${await output}\n${await errors}',
          );
          expect((await output).trim().endsWith('PASS:$mode'), true);
        } finally {
          await fixture.close();
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(seconds: 90)),
    );
  }
}
