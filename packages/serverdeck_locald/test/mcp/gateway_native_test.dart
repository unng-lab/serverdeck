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
      'serverdeck-mcp-bundle-gateway-',
    );
    b.ownRoot(compiled.path);
    exe = p.join(compiled.path, 'gateway.exe');
    await b.compilePeer(exe, source: 'test/support/gateway_actor.dart');
  });
  tearDownAll(() {
    b.ownRoot(compiled.path);
    compiled.deleteSync(recursive: true);
  });
  for (final mode in [
    'basic',
    'quota',
    'queued-cancel',
    'heartbeat',
    'heartbeat-remote-limit',
    'wrong-catalog',
    'wrong-poll',
    'wrong-cancel',
    'rpc-timeout',
    'rpc-remote',
    'overall',
    'cancel-timeout',
    'missing-grant',
    'owner-deny',
    'pending',
    'cancel-ack',
    'native-loss',
    'expiry',
    'revoke',
    'stdout-revoke',
    'stdout-target-change',
    'stdout-target-failure',
    'stdout-stop',
    'writer-cancel',
    'publish-order',
    'publish-expiry',
    'eof',
  ]) {
    test(
      'actual native MCP gateway $mode',
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
            await child.exitCode.timeout(
              const Duration(seconds: 70),
              onTimeout: () {
                final phase = File(
                  p.join(fixture.path, 'gateway-fixture-phase'),
                );
                final value = phase.existsSync()
                    ? phase.readAsStringSync()
                    : '';
                final safe = RegExp(r'^[a-z-]{1,40}$').hasMatch(value)
                    ? value
                    : 'unknown';
                throw StateError('GATEWAY_NATIVE_TIMEOUT:$safe');
              },
            ),
            0,
            reason: '${await output}\n${await errors}',
          );
          expect((await output).trim().endsWith('PASS:$mode'), true);
        } finally {
          await fixture.close();
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(seconds: 100)),
    );
  }
}
