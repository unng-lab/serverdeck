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
      'serverdeck-mcp-bundle-channel-',
    );
    b.ownRoot(compiled.path);
    exe = p.join(compiled.path, 'channel.exe');
    await b.compilePeer(exe, source: 'test/support/trusted_channel_actor.dart');
  });
  tearDownAll(() {
    b.ownRoot(compiled.path);
    compiled.deleteSync(recursive: true);
  });
  for (final mode in [
    'basic',
    'pending',
    'owner',
    'codes',
    'catalog',
    'foundation',
    'trust-probes',
    'trust-writes',
    'readiness-bad',
    'owner-blocked',
    'mcp-builtin-errors',
    'owner-builtin-errors',
    'badproof',
    'store-blocked',
    'second-open',
    'malformed',
    'duplicate',
    'oversize',
    'partial',
    'wrong-session',
    'native-failure',
    'policy-revoke',
    'policy-replace',
    'policy-expiry',
    'eof',
    'reentrant-close',
    'backpressure',
    'rpc-timeout',
    'output-error',
    'writer-revoke',
    'bootstrap-timeout',
    'client-disconnect',
    'worker-loss',
    'depth-inline',
    'depth-pending',
    'depth-over-inline',
    'depth-over-pending',
  ]) {
    test(
      'actual trusted wire $mode',
      () async {
        final fixture = b.Fixture(exe);
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
          expect(
            await child.exitCode.timeout(const Duration(seconds: 70)),
            0,
            reason: '${await output}\n${await errors}',
          );
          expect((await output).trim().endsWith('PASS:$mode'), true);
          if (mode == 'codes') {
            final reports = (await output)
                .split('\n')
                .where(
                  (line) =>
                      RegExp(r'^CODES_VERIFIED:28;ELAPSED_MS:[0-9]+$')
                          .hasMatch(line.trim()),
                )
                .toList();
            expect(reports.length, 1);
            stdout.writeln(reports.single.trim());
          }
        } finally {
          await fixture.close();
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(seconds: 100)),
    );
  }
}
