import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/storage/grant_write_probe.dart';
import 'package:serverdeck_windows/process.dart';
import 'package:test/test.dart';

import '../support/native_artifact.dart';

void safeRoot(String root) {
  if (!p.isWithin(p.normalize(p.absolute(Directory.systemTemp.path)), root) ||
      !p.basename(root).startsWith('serverdeck-operational-snapshot-'))
    throw StateError('UNSAFE_FIXTURE');
}

void main() {
  for (final point in GrantWriteBoundary.values) {
    test(
      'actual process kill grant boundary ${point.name}',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'serverdeck-operational-snapshot-',
        );
        final path = p.normalize(p.absolute(root.path));
        safeRoot(path);
        Process? child, verifier;
        StreamSubscription<String>? lines;
        try {
          final bundle = Directory(p.join(path, 'bundle'))..createSync();
          File(p.join(bundle.path, 'serverdeck.exe'))
              .writeAsBytesSync([1, 2, 3]);
          File(p.join(bundle.path, 'locald.exe')).writeAsBytesSync([4, 5, 6]);
          final dll = p.join(bundle.path, 'libisar.dll');
          File(nativeArtifactForTest()).copySync(dll);
          File(p.join(bundle.path, 'foundation.manifest.json'))
              .writeAsStringSync(
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
          final vm = p.join(
            p.dirname(Platform.resolvedExecutable),
            'dartvm.exe',
          );
          child = await Process.start(vm, [
            '-DSERVERDECK_TEST_GRANT_WRITE_PROBES=true',
            'test/support/operational_snapshot_child.dart',
            path,
            dll,
            'owned-grant-kill-${point.name}',
            bundle.path,
          ]);
          final marker = Completer<void>();
          lines = child.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((line) {
                if (line == 'GRANT_CRASH_BOUNDARY:${point.name}' &&
                    !marker.isCompleted)
                  marker.complete();
              });
          final errors = child.stderr.transform(utf8.decoder).join();
          await Future.any([
            marker.future,
            child.exitCode.then((_) async {
              throw StateError('GRANT_BOUNDARY_NOT_REACHED: ${await errors}');
            }),
          ]).timeout(const Duration(seconds: 60));
          expect(child.kill(), true);
          expect(
            await child.exitCode.timeout(const Duration(seconds: 10)),
            isNot(0),
          );
          expect(await errors.timeout(const Duration(seconds: 5)), isEmpty);
          await lines.cancel();
          lines = null;
          verifier = await Process.start(vm, [
            'test/support/grant_recovery_child.dart',
            path,
            bundle.path,
            point.index >= GrantWriteBoundary.afterCommit.index
                ? 'committed'
                : 'uncommitted',
          ]);
          final output = verifier.stdout.transform(utf8.decoder).join();
          final failure = verifier.stderr.transform(utf8.decoder).join();
          expect(
            await verifier.exitCode.timeout(const Duration(seconds: 60)),
            0,
            reason: await failure.timeout(const Duration(seconds: 5)),
          );
          expect(
            await output.timeout(const Duration(seconds: 5)),
            contains('ACTUAL_HARD_CRASH_GRANT_ATOMIC_RECOVERY_REPLAY_PROVED'),
          );
        } finally {
          await lines?.cancel();
          for (final process in [child, verifier]) {
            if (process != null) {
              process.kill();
              await process.exitCode.timeout(const Duration(seconds: 10));
            }
          }
          safeRoot(path);
          root.deleteSync(recursive: true);
        }
      },
      testOn: 'windows',
      timeout: const Timeout(Duration(seconds: 150)),
    );
  }
}
