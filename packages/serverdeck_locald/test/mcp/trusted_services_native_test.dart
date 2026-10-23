import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/process.dart';
import 'package:test/test.dart';

import '../../../serverdeck_windows/test/mcp_build_bundle_test.dart' as b;
import '../support/native_artifact.dart';

void main() {
  late Directory compiled;
  late String exe, observedExe, dll;
  setUpAll(() async {
    dll = nativeArtifactForTest();
    compiled = Directory.systemTemp.createTempSync(
      'serverdeck-mcp-bundle-services-',
    );
    b.ownRoot(compiled.path);
    exe = p.join(compiled.path, 'services.exe');
    await b.compilePeer(
      exe,
      source: 'test/support/trusted_services_actor.dart',
    );
    observedExe = p.join(compiled.path, 'observed.exe');
    final child = await Process.start(Platform.resolvedExecutable, [
      'compile',
      'exe',
      '-DSERVERDECK_TEST_NATIVE_OBSERVATION=true',
      '-DSERVERDECK_TEST_OWNER_SERVICE_PROBES=true',
      'test/support/trusted_services_actor.dart',
      '-o',
      observedExe,
    ]);
    final output = b.boundedOutput(child.stdout),
        errors = b.boundedOutput(child.stderr);
    try {
      expect(
        await child.exitCode.timeout(const Duration(seconds: 90)),
        0,
        reason: '${await output}\n${await errors}',
      );
    } finally {
      child.kill();
      await child.exitCode;
    }
  });
  tearDownAll(() {
    b.ownRoot(compiled.path);
    compiled.deleteSync(recursive: true);
  });
  for (final mode in [
    'basic',
    'ordinary',
    'prerequisites',
    'prepared-close',
    'grant-drain',
    'write-drain',
    'proof-drain',
    'native-drain',
    'native-failure',
    'probe-drain',
  ]) {
    test(
      'actual trusted control services $mode',
      () async {
        final fixture = b.Fixture(
          mode.endsWith('-drain') && mode != 'grant-drain' ||
                  mode == 'native-failure'
              ? observedExe
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
            [fixture.path, mode],
          );
          fixture.children.add(child);
          final output = b.boundedOutput(child.stdout),
              errors = b.boundedOutput(child.stderr);
          expect(
            await child.exitCode.timeout(const Duration(seconds: 60)),
            0,
            reason: '${await output}\n${await errors}',
          );
          expect((await output).trim().endsWith('PASS:$mode'), true);
          if (mode == 'native-failure') {
            expect(
              await output,
              contains(
                'ACTUAL_WRONG_THREAD_MUTEX_RELEASE_DENIED_OWNER_CLEANUP_PROVED',
              ),
            );
          }
          expect(await errors, isEmpty);
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
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
