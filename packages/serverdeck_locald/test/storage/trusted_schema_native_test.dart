import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/native_artifact.dart';

void main() {
  test(
    'actual schema3 native preflight preserves all15 raw collections',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'serverdeck-trusted-schema-',
      );
      final path = p.normalize(p.absolute(root.path));
      void requireOwned() {
        if (!p.isWithin(
              p.normalize(p.absolute(Directory.systemTemp.path)),
              path,
            ) ||
            !p.basename(path).startsWith('serverdeck-trusted-schema-')) {
          throw StateError('UNSAFE_FIXTURE');
        }
      }

      requireOwned();
      Process? child;
      try {
        child = await Process.start(Platform.resolvedExecutable, [
          'test/support/trusted_schema_child.dart',
          path,
          nativeArtifactForTest(),
        ]);
        final output = child.stdout.transform(utf8.decoder).join();
        final errors = child.stderr.transform(utf8.decoder).join();
        expect(await child.exitCode.timeout(const Duration(seconds: 45)), 0);
        expect(
          await output,
          contains(
            'ACTUAL_NATIVE_SCHEMA3_REGISTRY_RAW15_PRESERVATION_LEGACY_REFUSAL_AND_UNIQUE_INDEX_PROVED',
          ),
        );
        expect(await errors, isEmpty);
      } finally {
        if (child != null) {
          child.kill();
          await child.exitCode;
        }
        requireOwned();
        root.deleteSync(recursive: true);
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
