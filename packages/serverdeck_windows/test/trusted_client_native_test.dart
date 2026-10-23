import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'mcp_build_bundle_test.dart' as b;

void main() {
  late Directory root;
  late String executable;
  setUpAll(() async {
    root = Directory.systemTemp.createTempSync(
      'serverdeck-mcp-bundle-trusted-client-',
    );
    executable = p.join(root.path, 'actor.exe');
    await b.compilePeer(
      executable,
      source: 'test/support/trusted_client_actor.dart',
    );
  });
  tearDownAll(() {
    b.ownRoot(root.path);
    root.deleteSync(recursive: true);
  });
  for (final mode in [
    'owner',
    'cleanup2',
    'cleanup3',
    'mcp',
    'grant',
    'grant-bad-proof',
    'grant-repeat',
    'codes',
    'quota',
    'receipts',
    'connection',
    'bad-connection',
    'bad-connect',
    'bad-connect-status',
    'bad-connect-cancel',
    'bad-disconnect',
    'readiness2',
    'bad-receipt',
    'bad-retry',
    'unknown-code',
    'bad-field',
    'wrong-id',
    'wrong-generation',
    'oversize',
    'invalid-json',
    'timeout',
    'eof',
    'duplicate',
    'single-use',
    'wrong-token',
    'bad-proof',
    'hello-role',
    'hello-generation',
    'hello-build',
    'hello-version',
    'hello-shape',
    'bootstrap-timeout',
  ]) {
    test(
      'actual format3 bootstrap and RPC client $mode',
      () async {
        final fixture = b.Fixture(executable);
        try {
          fixture.document['format'] = mode == 'cleanup2' ? 2 : 3;
          fixture.document['workspaceSchema'] = mode == 'cleanup2' ? 2 : 3;
          fixture.write();
          final name =
              r'\\.\pipe\ServerDeckNext.v1.' +
              List.generate(
                32,
                (_) => Random.secure()
                    .nextInt(256)
                    .toRadixString(16)
                    .padLeft(2, '0'),
              ).join() +
              '.0';
          final child = await Process.start(
            p.join(fixture.path, 'locald.exe'),
            ['server', fixture.path, name, mode],
          );
          fixture.children.add(child);
          final out = b.boundedOutput(child.stdout),
              err = b.boundedOutput(child.stderr);
          expect(
            await child.exitCode.timeout(const Duration(seconds: 35)),
            0,
            reason: '${await out}\n${await err}',
          );
          expect(await out, contains('PASS:$mode'));
          expect(await err, isEmpty);
        } finally {
          await fixture.close();
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(seconds: 50)),
    );
  }
}
