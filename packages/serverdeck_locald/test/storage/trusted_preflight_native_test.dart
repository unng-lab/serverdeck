import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/process.dart';
import 'package:test/test.dart';

import '../../../serverdeck_windows/test/mcp_build_bundle_test.dart' as b;
import '../support/native_artifact.dart';

void main() {
  late Directory root;
  final executables = <bool, String>{};
  late String dll;
  setUpAll(() async {
    dll = nativeArtifactForTest();
    root = Directory.systemTemp.createTempSync(
      'serverdeck-mcp-bundle-preflight-',
    );
    for (final probes in [false, true]) {
      final executable = p.join(root.path, 'actor-$probes.exe');
      final child = await Process.start(Platform.resolvedExecutable, [
        'compile',
        'exe',
        if (probes) '-DSERVERDECK_TEST_MIGRATION_PROBES=true',
        'test/support/trusted_preflight_actor.dart',
        '-o',
        executable,
      ]);
      final out = b.boundedOutput(child.stdout),
          err = b.boundedOutput(child.stderr);
      try {
        expect(
          await child.exitCode.timeout(const Duration(seconds: 90)),
          0,
          reason: '${await out}\n${await err}',
        );
      } finally {
        child.kill();
        await child.exitCode;
      }
      executables[probes] = executable;
    }
  });
  tearDownAll(() {
    b.ownRoot(root.path);
    root.deleteSync(recursive: true);
  });
  for (final mode in [
    'good',
    'empty',
    'occupied',
    'concurrent',
    'role-owner',
    'role-mcp',
    'manifest3',
    'manifest-foreign',
    'wrapper',
    'native1',
    'native3',
    'marker3',
    'bad-credential',
    'bad-client',
    'missing-lock',
    'acl-db',
    'closed-key',
    'closed-lease',
    'stage-creating',
    'stage-1-2',
    'stage-2-3',
    'empty-stage',
    'probe-disabled',
    'close-false',
    'close-throw',
  ]) {
    test(
      'actual owned trusted preflight $mode',
      () async {
        final fixture = b.Fixture(executables[mode.startsWith('close-')]!);
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
          final out = b.boundedOutput(child.stdout),
              err = b.boundedOutput(child.stderr);
          fixture.errors.add(err);
          expect(
            await child.exitCode.timeout(const Duration(seconds: 60)),
            0,
            reason: '${await out}\n${await err}',
          );
          expect((await out).trim().endsWith('PASS:$mode'), isTrue);
        } finally {
          await fixture.close();
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(seconds: 90)),
    );
  }
}
