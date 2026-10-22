import 'dart:async';
import 'dart:convert';
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
      'serverdeck-mcp-bundle-recovery-',
    );
    b.ownRoot(compiled.path);
    exe = p.join(compiled.path, 'recovery.exe');
    await b.compilePeer(exe, source: 'test/support/trust_recovery_actor.dart');
  });
  tearDownAll(() {
    b.ownRoot(compiled.path);
    compiled.deleteSync(recursive: true);
  });
  for (final mode in [
    'normal',
    'uncertain',
    'crash',
    'busy-running',
    'busy-unknown',
  ]) {
    test(
      'actual trust fullgraph recovery $mode',
      () async {
        final fixture = b.Fixture(exe);
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
          final phases = [
            'prepare2',
            'upgrade',
            'write',
            if (!mode.startsWith('busy-')) 'verify',
          ];
          for (final phase in phases) {
            final child = await Process.start(
              p.join(fixture.path, 'locald.exe'),
              [fixture.path, phase, mode],
            );
            fixture.children.add(child);
            final errors = b.boundedOutput(child.stderr);
            errors.ignore();
            if (phase == 'write' && mode == 'crash') {
              final reached = Completer<void>();
              var bytes = 0;
              Object? outputFailure;
              final output = child.stdout
                  .map((chunk) {
                    bytes += chunk.length;
                    if (bytes > 64 * 1024)
                      throw StateError('FIXTURE_OUTPUT_LIMIT');
                    return chunk;
                  })
                  .transform(utf8.decoder)
                  .transform(const LineSplitter())
                  .listen(
                    (line) {
                      if (line == 'BOUNDARY:trust-committed' &&
                          !reached.isCompleted)
                        reached.complete();
                    },
                    onError: (Object error, StackTrace stack) {
                      outputFailure = error;
                      if (!reached.isCompleted)
                        reached.completeError(error, stack);
                    },
                  );
              try {
                await reached.future.timeout(const Duration(seconds: 40));
                expect(child.kill(), true);
                await child.exitCode.timeout(const Duration(seconds: 10));
                expect(await errors, isEmpty);
                expect(outputFailure, isNull);
                expect(
                  File(p.join(fixture.path, 'trust-recovery.fixture.json'))
                      .existsSync(),
                  true,
                );
              } finally {
                await output.cancel();
              }
            } else {
              final output = b.boundedOutput(child.stdout);
              final code = await child.exitCode.timeout(
                const Duration(seconds: 60),
              );
              expect(code, 0, reason: '${await output}\n${await errors}');
              expect(
                (await output).trim().endsWith(
                  phase == 'prepare2' || phase == 'upgrade'
                      ? 'PASS:$phase'
                      : 'PASS:$phase:$mode',
                ),
                true,
              );
              expect(await errors, isEmpty);
            }
          }
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
