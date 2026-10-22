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
      source: 'test/support/trusted_migration_actor.dart',
    );
  });
  tearDownAll(() {
    b.ownRoot(root.path);
    root.deleteSync(recursive: true);
  });
  for (final mode in [
    'writer-coordinator-basic',
    'writer-coordinator-create',
    'writer-coordinator-reservation',
    'writer-coordinator-running',
    'writer-coordinator-trust',
    'writer-coordinator-key',
  ]) {
    test(
      'actual trusted foundation coordinator $mode',
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
          for (final phase in ['prepare2', mode]) {
            final child = await Process.start(
              p.join(fixture.path, 'locald.exe'),
              [fixture.path, phase],
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
            expect((await output).trim().endsWith('PASS:$phase'), isTrue);
          }
        } finally {
          await fixture.close();
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(seconds: 90)),
    );
  }
}
