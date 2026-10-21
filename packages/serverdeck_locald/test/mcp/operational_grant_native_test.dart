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
      'serverdeck-mcp-bundle-grant-',
    );
    b.ownRoot(compiled.path);
    exe = p.join(compiled.path, 'grant.exe');
    await b.compilePeer(
      exe,
      source: 'test/support/operational_grant_actor.dart',
    );
  });
  tearDownAll(() {
    b.ownRoot(compiled.path);
    compiled.deleteSync(recursive: true);
  });
  for (final mode in [
    'current',
    'grant-expiry',
    'replay',
    'replace',
    'revoke',
    'retired',
    'retired2',
    'retired3',
    'badproof',
    'permit-completed',
    'permit-stopped',
    'permit-expired',
    'permit-lease',
    'permit-native',
    'permit-replaced',
    'permit-outer',
    'missing',
    'expired',
    'revoked',
    'keyloss',
    'closed',
    'repeat',
    'serverrepeat',
    'clientproof',
    'clientcorrelation',
    'pool',
    'late-replace',
    'late-close',
    'late-repeat',
    'late-timeout',
  ]) {
    test(
      'actual protected native grant open $mode',
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
