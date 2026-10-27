import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/native_artifact.dart';

void main() {
  for (final mode in [
    'good',
    'bad-credential',
    'bad-client',
    'bad-lookup',
    'occupied',
    'stage',
    'wrong-path',
    'nonempty-trust',
    'empty-stage',
    'lookup-existing',
    'job-queued',
    'job-running',
    'job-cancel-requested',
    'job-reconciling',
    'job-failed',
    'job-cancelled',
  ]) {
    test(
      'actual upgrade fullgraph capture $mode',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'serverdeck-upgrade-capture-',
        );
        final path = p.normalize(p.absolute(root.path));
        void owned() {
          if (!p.isWithin(
                p.normalize(p.absolute(Directory.systemTemp.path)),
                path,
              ) ||
              !p.basename(path).startsWith('serverdeck-upgrade-capture-')) {
            throw StateError('UNSAFE_FIXTURE');
          }
        }

        Process? child;
        try {
          child = await Process.start(Platform.resolvedExecutable, [
            'test/support/upgrade_capture_child.dart',
            path,
            nativeArtifactForTest(),
            mode,
          ]);
          final output = child.stdout.transform(utf8.decoder).join(),
              errors = child.stderr.transform(utf8.decoder).join();
          expect(
            await child.exitCode.timeout(const Duration(seconds: 60)),
            0,
            reason: await errors,
          );
          expect(await output, contains('PASS:$mode'));
          expect(await errors, isEmpty);
        } finally {
          if (child != null) {
            child.kill();
            await child.exitCode;
          }
          owned();
          root.deleteSync(recursive: true);
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(seconds: 80)),
    );
  }
}
