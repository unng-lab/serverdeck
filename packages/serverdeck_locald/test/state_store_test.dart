import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/process.dart';
import 'package:test/test.dart';

import 'support/native_artifact.dart';

void main() {
  for (final mode in [null, 'before', 'after', 'failure', 'dpapi']) {
    registerRepositoryTest(mode: mode);
  }
}

void registerRepositoryTest({String? mode}) {
  // This finite workload fills the real 64 MiB map and validates 10,000
  // receipts. Its harness budget is separate from runtime RPC/startup limits.
  final childBudget = Duration(seconds: mode == 'mutation-limits' ? 360 : 180);
  final directRepository =
      mode == null ||
      mode == 'lifecycle' ||
      mode == 'mutations' ||
      mode == 'api' ||
      mode == 'channel' ||
      mode == 'open-close-failure' ||
      mode == 'service-lifecycle' ||
      mode == 'mutation-limits' ||
      mode == 'mutation-allocation' ||
      mode == 'mutation-native-failure';
  test(
    mode == null
        ? 'owned repository validates, commits, updates IDs, reopens and blocks unsafe input'
        : mode == 'lifecycle'
        ? 'native credential snapshots survive replace/remove/keep and selected-profile deletion'
        : mode == 'mutations'
        ? 'actual coordinator preserves CAS, receipts and atomic credential effects'
        : mode == 'api'
        ? 'router serves every method through actual durable storage and DPAPI'
        : mode == 'channel'
        ? 'native channel authenticates and routes durable DPAPI mutations'
        : mode == 'service-lifecycle'
        ? 'service shutdown drains durable commit before key and mutex release'
        : mode == 'mutation-limits'
        ? 'coordinator preserves logical/native quotas and drains shutdown'
        : mode == 'mutation-allocation'
        ? 'coordinator rejects exhausted native IDs without a partial effect'
        : mode == 'mutation-native-failure'
        ? 'coordinator blocks uncertain native failure until fresh-process verification'
        : mode == 'dpapi'
        ? 'DPAPI availability loss blocks until verified reopen'
        : mode == 'failure'
        ? 'unknown native error blocks subsequent repository use'
        : mode == 'open-close-failure'
        ? 'nested failed open retains ownership after unconfirmed native close'
        : 'hard crash $mode commit preserves exactly durable state',
    () async {
      final nativeLibrary = nativeArtifactForTest();
      final parent = Directory.systemTemp.createTempSync(
        'serverdeck-repository-fixture-',
      );
      final root = p.normalize(p.absolute(parent.path));
      if (!p.isWithin(p.normalize(p.absolute(Directory.systemTemp.path)), root))
        throw StateError('UNSAFE_TEST_DIRECTORY');
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
          directRepository
              ? 'test/support/state_store_child.dart'
              : 'test/support/state_store_crash_child.dart',
          root,
          bundle.path,
          if (mode != null) mode,
        ]);
        final boundary = Completer<void>();
        final output = child.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              stdout.writeln(line);
              if (line == 'CRASH_BOUNDARY' && !boundary.isCompleted)
                boundary.complete();
            });
        final errors = child.stderr
            .transform(utf8.decoder)
            .listen(stderr.write);
        try {
          if (directRepository || mode == 'failure' || mode == 'dpapi') {
            expect(await child.exitCode.timeout(childBudget), 0);
          } else {
            await Future.any([
              boundary.future,
              child.exitCode.then(
                (_) => throw StateError('MISSING_CRASH_BOUNDARY'),
              ),
            ]).timeout(const Duration(seconds: 30));
            expect(child.kill(), true);
            expect(await child.exitCode, isNot(0));
          }
        } finally {
          child.kill();
          await child.exitCode;
          await output.cancel();
          await errors.cancel();
        }
        if (!directRepository || mode == 'mutation-native-failure') {
          final verifier = await Process.start(vm, [
            'test/support/state_store_crash_child.dart',
            root,
            bundle.path,
            'verify-${mode == 'failure' || mode == 'mutation-native-failure'
                ? 'before'
                : mode == 'dpapi'
                ? 'after'
                : mode}',
          ]);
          final resultOutput = verifier.stdout
              .transform(utf8.decoder)
              .listen(stdout.write);
          final resultErrors = verifier.stderr
              .transform(utf8.decoder)
              .listen(stderr.write);
          try {
            expect(
              await verifier.exitCode.timeout(const Duration(seconds: 30)),
              0,
            );
          } finally {
            verifier.kill();
            await verifier.exitCode;
            await resultOutput.cancel();
            await resultErrors.cancel();
          }
        }
      } finally {
        parent.deleteSync(recursive: true);
      }
    },
    testOn: 'windows',
    timeout: Timeout(childBudget + const Duration(seconds: 30)),
  );
}
