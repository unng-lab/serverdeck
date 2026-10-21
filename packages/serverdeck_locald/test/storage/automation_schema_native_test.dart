import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/native_artifact.dart';

void main() {
  test('actual Isar staged registry2 preserves raw rows and leaves source untouched', () async {
    final root = Directory.systemTemp.createTempSync(
      'serverdeck-automation-schema-',
    );
    final path = p.normalize(p.absolute(root.path));
    if (!p.isWithin(p.normalize(p.absolute(Directory.systemTemp.path)), path))
      throw StateError('UNSAFE_FIXTURE');
    Process? child;
    try {
      child = await Process.start(Platform.resolvedExecutable, [
        'test/support/automation_schema_child.dart',
        path,
        nativeArtifactForTest(),
      ]);
      final output = child.stdout.transform(utf8.decoder).join();
      final errors = child.stderr.transform(utf8.decoder).join();
      expect(await child.exitCode.timeout(const Duration(seconds: 45)), 0);
      expect(
        await output,
        contains(
          'ACTUAL_STAGED_NATIVE_V1_V2_REGISTRY_AND_RAW_ROW_PRESERVATION_PROVED',
        ),
      );
      expect(await errors, isEmpty);
    } finally {
      if (child != null) {
        child.kill();
        await child.exitCode;
      }
      if (!p.isWithin(
            p.normalize(p.absolute(Directory.systemTemp.path)),
            path,
          ) ||
          !p.basename(path).startsWith('serverdeck-automation-schema-'))
        throw StateError('UNSAFE_FIXTURE');
      root.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
