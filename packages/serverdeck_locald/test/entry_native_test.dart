import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/process.dart';
import 'package:test/test.dart';

import 'support/native_artifact.dart';

void main() {
  test(
    'entry rejects unapproved process despite a valid bundle manifest',
    () async {
      final nativeLibrary = nativeArtifactForTest();
      final fixture = Directory.systemTemp.createTempSync(
        'serverdeck-entry-fixture-',
      );
      final root = p.normalize(p.absolute(fixture.path));
      if (!p.isWithin(
        p.normalize(p.absolute(Directory.systemTemp.path)),
        root,
      )) {
        throw StateError('UNSAFE_TEST_DIRECTORY');
      }
      try {
        File(p.join(root, 'serverdeck.exe')).writeAsBytesSync([1, 2, 3]);
        File(p.join(root, 'locald.exe')).writeAsBytesSync([4, 5, 6]);
        File(nativeLibrary).copySync(p.join(root, 'libisar.dll'));
        File(p.join(root, 'foundation.manifest.json')).writeAsStringSync(
          jsonEncode({
            'format': 1,
            'buildId': '${'a' * 40}+Debug+${'b' * 64}',
            'configuration': 'Debug',
            'testOnly': false,
            'appRoot': root,
            'sha256': {
              for (final name in [
                'serverdeck.exe',
                'locald.exe',
                'libisar.dll',
              ])
                name: fileSha256(p.join(root, name)),
            },
          }),
        );
        final child = await Process.run(Platform.resolvedExecutable, [
          'bin/locald.dart',
          '--workspace',
          'default',
          '--app-root',
          root,
        ]);
        expect(child.exitCode, 1);
        expect(child.stderr.toString().trim(), 'INCOMPATIBLE');
        expect(child.stdout, isEmpty);
        expect(Directory(p.join(root, 'ServerDeckNext')).existsSync(), false);
      } finally {
        fixture.deleteSync(recursive: true);
      }
    },
    testOn: 'windows',
  );
  test(
    'entry errors never echo private argv or accept missing options',
    () async {
      for (final args in <List<String>>[
        [],
        [
          '--token',
          'synthetic-private-argument',
          '--app-root',
          p.absolute('.'),
        ],
      ]) {
        final child = await Process.run(Platform.resolvedExecutable, [
          'bin/locald.dart',
          ...args,
        ]);
        expect(child.exitCode, 1);
        expect(child.stderr.toString().trim(), 'PREREQUISITE_UNAVAILABLE');
        expect(child.stdout, isEmpty);
      }
    },
    testOn: 'windows',
  );
}
