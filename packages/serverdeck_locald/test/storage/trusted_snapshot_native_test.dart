import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/native_artifact.dart';

void main() {
  for (final mode in [
    'good',
    'empty',
    'migrated',
    'bad-credential',
    'bad-key',
    'missing-key',
    'bad-lookup',
    'bad-graph',
    'foreign-trust',
    'bad-epoch',
    'missing-trust',
    'orphan-trust',
    'extra-metadata',
    'wrong-schema',
    'wrong-key',
    'wrong-directory',
    'closed-lease',
    'closed-key',
    'wrong-owner',
    'wrong-name',
    'bad-trust-native-id',
  ]) {
    test(
      'actual native schema3 composition $mode',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'serverdeck-trusted-snapshot-',
        );
        final path = p.normalize(p.absolute(root.path));
        void requireOwned() {
          if (!p.isWithin(
                p.normalize(p.absolute(Directory.systemTemp.path)),
                path,
              ) ||
              !p.basename(path).startsWith('serverdeck-trusted-snapshot-'))
            throw StateError('UNSAFE_FIXTURE');
        }

        requireOwned();
        Process? child;
        try {
          child = await Process.start(Platform.resolvedExecutable, [
            'test/support/trusted_snapshot_child.dart',
            path,
            nativeArtifactForTest(),
            mode,
          ]);
          final output = child.stdout.transform(utf8.decoder).join(),
              errors = child.stderr.transform(utf8.decoder).join();
          final code = await child.exitCode.timeout(
            const Duration(seconds: 60),
          );
          final stderr = await errors;
          expect(code, 0, reason: stderr);
          expect(
            await output,
            contains(
              {'good', 'empty', 'migrated'}.contains(mode)
                  ? 'ACTUAL_SCHEMA3_FULL_GRAPH_DPAPI_ALL16_REOPEN_RAW_PRESERVATION_PROVED'
                  : 'ACTUAL_SCHEMA3_REFUSAL_BEFORE_FIRST_PUBLICATION_PROVED',
            ),
          );
          expect(stderr, isEmpty);
        } finally {
          if (child != null) {
            child.kill();
            await child.exitCode;
          }
          requireOwned();
          root.deleteSync(recursive: true);
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(seconds: 80)),
    );
  }
}
