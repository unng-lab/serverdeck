import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/process.dart';
import 'package:test/test.dart';

import '../../../serverdeck_windows/test/mcp_build_bundle_test.dart' as b;
import '../support/capacity_fixture.dart';
import '../support/native_artifact.dart';

void main() {
  late Directory compiled;
  late String exe, observed, dll;
  setUpAll(() async {
    dll = nativeArtifactForTest();
    compiled = Directory.systemTemp.createTempSync(
      'serverdeck-mcp-bundle-trust-probe-',
    );
    b.ownRoot(compiled.path);
    exe = p.join(compiled.path, 'owner-api.exe');
    await b.compilePeer(exe, source: 'test/support/trusted_owner_actor.dart');
    observed = p.join(compiled.path, 'observed.exe');
    final compiler = await Process.start(Platform.resolvedExecutable, [
      'compile',
      'exe',
      '-DSERVERDECK_TEST_NATIVE_OBSERVATION=true',
      'test/support/trusted_owner_actor.dart',
      '-o',
      observed,
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
    'basic',
    'reservation',
    'quota',
    'role',
    'foreign',
    'cancel',
    'close',
    'retention',
    'gate',
    'success',
    'success-cancel',
    'success-ttl',
    'success-other',
    'success-write-basic',
    'success-write-replay',
    'success-write-cancel',
    'success-write-ttl',
    'success-write-cas',
    'success-write-foreign',
    'success-write-duplicate',
    'success-write-reservation',
    'success-write-role',
    'success-write-quota',
    'success-write-capacity',
    'success-write-blocked',
    'success-write-retired',
    'success-write-drain',
    'success-write-clock',
    'success-write-retired-admission',
    'success-stale',
    'success-deadline',
    'admission-clock',
    'reserved-cancel',
    'physical-cancel',
    'physical-detach',
    'physical-stale',
  ]) {
    test(
      'actual native host trust probes $mode',
      () async {
        final fixture = b.Fixture(
          mode.startsWith('physical-') || mode == 'success-stale'
              ? observed
              : exe,
        );
        Object? firstError;
        StackTrace? firstStack;
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
            [fixture.path, 'probe-$mode'],
            environment: {
              'SERVERDECK_TRUST_FIXTURE_SCRIPT': p.absolute(
                'test/support/ssh_key_probe_server.py',
              ),
            },
          );
          fixture.children.add(child);
          final output = b.boundedOutput(child.stdout),
              errors = b.boundedOutput(child.stderr);
          fixture.errors.add(errors);
          expect(
            await child.exitCode.timeout(
              const Duration(seconds: 55),
              onTimeout: mode == 'success-write-capacity'
                  ? () {
                      final phase = readCapacityFixturePhase(fixture.path);
                      throw TimeoutException(
                        'TRUST_CAPACITY_FIXTURE_TIMEOUT:$phase',
                        const Duration(seconds: 55),
                      );
                    }
                  : null,
            ),
            0,
            reason: '${await output}\n${await errors}',
          );
          expect((await output).trim().endsWith('PASS:probe-$mode'), true);
        } catch (error, stack) {
          firstError = error;
          firstStack = stack;
        } finally {
          try {
            await fixture.close();
          } catch (error, stack) {
            firstError ??= error;
            firstStack ??= stack;
          }
        }
        if (firstError != null)
          Error.throwWithStackTrace(firstError, firstStack!);
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(seconds: 80)),
    );
  }
}
