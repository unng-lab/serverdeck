import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/native_artifact.dart';

void main() {
  for (final mode in [
    'good',
    'empty',
    'stale',
    'revoked',
    'second-missing',
    'second-corrupt',
    'second-lookup',
    'second-foreign',
    'empty-inventory',
    'bad-foundation',
    'bad-graph',
    'bad-native-id',
    'wrong-schema',
    'wrong-key',
    'wrong-owner',
    'wrong-directory',
    'wrong-name',
    'closed-lease',
  ]) {
    test(
      'actual native operational composition $mode',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'serverdeck-operational-snapshot-',
        );
        final path = p.normalize(p.absolute(root.path));
        if (!p.isWithin(
          p.normalize(p.absolute(Directory.systemTemp.path)),
          path,
        ))
          throw StateError('UNSAFE_FIXTURE');
        Process? child;
        try {
          child = await Process.start(
            p.join(p.dirname(Platform.resolvedExecutable), 'dartvm.exe'),
            [
              'test/support/operational_snapshot_child.dart',
              path,
              nativeArtifactForTest(),
              mode,
            ],
          );
          final output = child.stdout.transform(utf8.decoder).join();
          final errors = child.stderr.transform(utf8.decoder).join();
          final code = await child.exitCode.timeout(
            const Duration(seconds: 60),
          );
          final stderr = await errors.timeout(const Duration(seconds: 5));
          expect(code, 0, reason: stderr);
          expect(
            await output.timeout(const Duration(seconds: 5)),
            contains(
              {'good', 'empty', 'stale', 'revoked'}.contains(mode)
                  ? 'NATIVE_OPERATIONAL_LOAD_REOPEN_PROVED'
                  : 'NATIVE_PREFLIGHT_REFUSAL_NO_FIRST_PUBLICATION_PROVED',
            ),
          );
        } finally {
          if (child != null) {
            child.kill();
            await child.exitCode.timeout(const Duration(seconds: 10));
          }
          if (!p.isWithin(
                p.normalize(p.absolute(Directory.systemTemp.path)),
                path,
              ) ||
              !p.basename(path).startsWith('serverdeck-operational-snapshot-'))
            throw StateError('UNSAFE_FIXTURE');
          root.deleteSync(recursive: true);
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(seconds: 80)),
    );
  }
}
