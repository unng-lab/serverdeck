import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/process.dart';
import 'package:test/test.dart';

import 'support/native_artifact.dart';
import 'support/private_child_stderr.dart';

void main() {
  test(
    'workspace creation promotion recovery and ambiguous states fail closed',
    () async {
      final nativeLibrary = nativeArtifactForTest();
      final parent = Directory.systemTemp.createTempSync(
        'serverdeck-workspace-fixture-',
      );
      final root = p.normalize(p.absolute(parent.path));
      if (!p.isWithin(
        p.normalize(p.absolute(Directory.systemTemp.path)),
        root,
      )) {
        throw StateError('UNSAFE_TEST_DIRECTORY');
      }
      final bundle = Directory(p.join(root, 'bundle'))..createSync();
      try {
        File(p.join(bundle.path, 'serverdeck.exe')).writeAsBytesSync([1, 2, 3]);
        File(p.join(bundle.path, 'locald.exe')).writeAsBytesSync([4, 5, 6]);
        File(nativeLibrary).copySync(p.join(bundle.path, 'libisar.dll'));
        File(p.join(bundle.path, 'foundation.manifest.json')).writeAsStringSync(
          jsonEncode({
            'format': 1,
            'buildId': '${'a' * 40}+Debug+${'b' * 64}',
            'configuration': 'Debug',
            'testOnly': false,
            'appRoot': bundle.path,
            'sha256': {
              for (final name in [
                'serverdeck.exe',
                'locald.exe',
                'libisar.dll',
              ])
                name: fileSha256(p.join(bundle.path, name)),
            },
          }),
        );
        final vm = p.join(p.dirname(Platform.resolvedExecutable), 'dartvm.exe');
        expect(File(vm).existsSync(), true);
        final child = await Process.start(vm, [
          'test/support/workspace_child.dart',
          root,
          bundle.path,
        ]);
        final output = child.stdout
            .transform(utf8.decoder)
            .listen(stdout.write);
        // Keep the child stack private, but attach it to the test failure so
        // the qualification projector can identify known source frames.
        final errors = PrivateChildStderr(child.stderr, stderr.add);
        try {
          final result = await child.exitCode.timeout(
            const Duration(seconds: 90),
            onTimeout: () => throw StateError('WORKSPACE_CHILD_TIMEOUT'),
          );
          final failureOutput = await errors.drain();
          if (result != 0) {
            Error.throwWithStackTrace(
              StateError('WORKSPACE_CHILD_FAILED'),
              StackTrace.fromString(
                utf8.decode(failureOutput, allowMalformed: true),
              ),
            );
          }
          expect(result, 0);
        } finally {
          child.kill();
          await child.exitCode;
          await output.cancel();
          await errors.drain().catchError((Object _) => <int>[]);
        }
      } finally {
        parent.deleteSync(recursive: true);
      }
    },
    testOn: 'windows',
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
