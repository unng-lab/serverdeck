import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/process.dart';
import 'package:test/test.dart';

import '../../../serverdeck_windows/test/mcp_build_bundle_test.dart' as b;
import '../support/native_artifact.dart';

void main() {
  late Directory root;
  late String executable, ordinaryExecutable, dll;
  setUpAll(() async {
    dll = nativeArtifactForTest();
    root = Directory.systemTemp.createTempSync(
      'serverdeck-mcp-bundle-trusted-automation-',
    );
    executable = p.join(root.path, 'actor.exe');
    ordinaryExecutable = p.join(root.path, 'actor-normal.exe');
    for (final target in [executable, ordinaryExecutable]) {
      final compiling = await Process.start(Platform.resolvedExecutable, [
        'compile',
        'exe',
        if (target == executable) '-DSERVERDECK_TEST_GRANT_WRITE_PROBES=true',
        'test/support/trusted_migration_actor.dart',
        '-o',
        target,
      ]);
      final output = b.boundedOutput(compiling.stdout),
          errors = b.boundedOutput(compiling.stderr);
      try {
        expect(
          await compiling.exitCode.timeout(const Duration(seconds: 90)),
          0,
          reason: '${await output}\n${await errors}',
        );
      } finally {
        compiling.kill();
        await compiling.exitCode;
      }
    }
  });
  tearDownAll(() {
    b.ownRoot(root.path);
    root.deleteSync(recursive: true);
  });
  for (final scenario in [
    'writer-automation',
    'writer-automation-normal',
    'writer-automation-closing',
    'writer-automation-queue',
    'writer-automation-listener',
    'writer-automation-corrupt',
    'writer-automation-key-race',
    'writer-automation-keyloss',
    'writer-automation-capacity-grant',
    'writer-automation-capacity-profile',
    'writer-automation-overflow-grants',
    'writer-automation-overflow-receipts',
    'writer-automation-overflow-profiles',
    'writer-automation-overflow-revisions',
    for (final b in [
      'beforeStage',
      'afterStage',
      'beforeTransaction',
      'afterGrantWrite',
      'afterReceiptWrite',
      'afterCommit',
      'beforePublication',
      'afterPublication',
      'beforeAcknowledgement',
    ])
      'writer-automation-fault-' + b,
  ]) {
    test(
      'actual schema3 automation writer ' + scenario,
      () async {
        final f = b.Fixture(
          scenario == 'writer-automation-normal'
              ? ordinaryExecutable
              : executable,
        );
        try {
          File(dll).copySync(p.join(f.path, 'libisar.dll'));
          (f.document['sha256'] as Map)['libisar.dll'] = fileSha256(
            p.join(f.path, 'libisar.dll'),
          );
          f.document['format'] = 3;
          f.document['workspaceSchema'] = 3;
          f.write();
          for (final mode in ['prepare2', scenario]) {
            final child = await Process.start(p.join(f.path, 'locald.exe'), [
              f.path,
              mode,
            ]);
            f.children.add(child);
            final output = b.boundedOutput(child.stdout),
                errors = b.boundedOutput(child.stderr);
            expect(
              await child.exitCode.timeout(const Duration(seconds: 60)),
              0,
              reason: '${await output}\n${await errors}',
            );
            expect(await output, contains('PASS:$mode'));
            expect(await errors, isEmpty);
          }
        } finally {
          await f.close();
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(seconds: 120)),
    );
  }
}
