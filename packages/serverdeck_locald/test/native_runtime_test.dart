import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/bootstrap/native_runtime.dart';
import 'package:serverdeck_windows/process.dart';
import 'package:test/test.dart';

import 'support/native_artifact.dart';

void main() {
  test('runtime verifies all bundled files before absolute pinned native load', () async {
    final nativeLibrary = nativeArtifactForTest();
    final parent = Directory.systemTemp.createTempSync(
      'serverdeck-bundle-fixture-',
    );
    final root = p.normalize(p.absolute(parent.path));
    if (!p.isWithin(p.normalize(p.absolute(Directory.systemTemp.path)), root)) {
      throw StateError('UNSAFE_TEST_DIRECTORY');
    }
    try {
      File(p.join(root, 'serverdeck.exe')).writeAsBytesSync([1, 2, 3]);
      File(p.join(root, 'locald.exe')).writeAsBytesSync([4, 5, 6]);
      File(nativeLibrary).copySync(p.join(root, 'libisar.dll'));
      final document = {
        'format': 1,
        'buildId': '${'a' * 40}+Debug+${'b' * 64}',
        'configuration': 'Debug',
        'testOnly': false,
        'appRoot': root,
        'sha256': {
          for (final name in ['serverdeck.exe', 'locald.exe', 'libisar.dll'])
            name: fileSha256(p.join(root, name)),
        },
      };
      final manifestFile = File(p.join(root, 'foundation.manifest.json'));
      manifestFile.writeAsStringSync(jsonEncode(document));
      File(p.join(root, 'locald.exe')).writeAsBytesSync([7]);
      await expectLater(
        initializeNativeRuntime(root),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'safe code',
            'INCOMPATIBLE',
          ),
        ),
      );
      File(p.join(root, 'locald.exe')).writeAsBytesSync([4, 5, 6]);
      // DLL lifetime is the service process lifetime. Child exit releases the
      // mapped fixture DLL before the parent deletes its own temporary bundle.
      final child = await Process.run(Platform.resolvedExecutable, [
        'test/support/native_runtime_child.dart',
        root,
      ]);
      expect(child.exitCode, 0, reason: '${child.stdout}\n${child.stderr}');
    } finally {
      parent.deleteSync(recursive: true);
    }
  }, testOn: 'windows');
}
