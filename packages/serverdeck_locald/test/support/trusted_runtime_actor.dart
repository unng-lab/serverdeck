import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/bootstrap/native_runtime.dart';
import 'package:serverdeck_locald/storage/host_trust_records.dart';
import 'package:serverdeck_windows/process.dart';

import '../../../serverdeck_windows/test/support/native_fixture_job.dart';
import 'mcp_runtime_actor.dart' show check, ownRoot, refusal, manifest, legacy;

Future<void> main(List<String> args) async {
  try {
    final root = p.normalize(p.absolute(args[0])), mode = args[1];
    ownRoot(root);
    containCurrentFixtureTree();
    final original = File(p.join(root, 'foundation.manifest.json'))
        .readAsStringSync();
    void restore() =>
        File(p.join(root, 'foundation.manifest.json'))
            .writeAsStringSync(original);
    void format2() => manifest(root, (d) {
      d['format'] = 2;
      d['workspaceSchema'] = 2;
    });
    switch (mode) {
      case 'good':
        final bundles = await Future.wait([
          initializeTrustedNativeRuntime(root),
          initializeTrustedNativeRuntime(root),
        ]);
        check(bundles.every((b) => b.manifest.workspaceSchema == 3));
        await initializeTrustedNativeRuntime(root);
        final directory = Directory(p.join(root, 'runtime-probe'))
          ..createSync();
        final db = await Isar.open(
          trustedWorkspaceSchemas,
          directory: directory.path,
          name: 'probe',
          maxSizeMiB: 64,
          relaxedDurability: false,
          inspector: false,
        );
        try {
          await db.writeTxn(() async {
            await db.storedHostTrusts.put(
              StoredHostTrust()
                ..entityId = 'runtime-probe'
                ..payload = '{}',
            );
          });
          check(await db.storedHostTrusts.count() == 1);
        } finally {
          check(await db.close());
        }
      case 'role':
        await refusal(
          () => initializeTrustedNativeRuntime(root),
          'UNAUTHORIZED',
        );
      case 'legacy-refusal':
        await refusal(() => initializeNativeRuntime(root), 'INCOMPATIBLE');
        await initializeTrustedNativeRuntime(root);
      case 'format2-refusal':
        format2();
        await refusal(
          () => initializeTrustedNativeRuntime(root),
          'INCOMPATIBLE',
        );
        await initializeMcpNativeRuntime(root);
        restore();
        await refusal(
          () => initializeTrustedNativeRuntime(root),
          'INCOMPATIBLE',
        );
      case 'format3-to2':
        await initializeTrustedNativeRuntime(root);
        format2();
        await refusal(() => initializeMcpNativeRuntime(root), 'INCOMPATIBLE');
        restore();
        await initializeTrustedNativeRuntime(root);
      case 'format1-to3':
        legacy(root);
        await initializeNativeRuntime(root);
        restore();
        await refusal(
          () => initializeTrustedNativeRuntime(root),
          'INCOMPATIBLE',
        );
      case 'format3-to1':
        await initializeTrustedNativeRuntime(root);
        legacy(root);
        await refusal(() => initializeNativeRuntime(root), 'INCOMPATIBLE');
      case 'build-conflict':
        await initializeTrustedNativeRuntime(root);
        manifest(root, (d) {
          d['configuration'] = 'Release';
          d['buildId'] = (d['buildId'] as String).replaceFirst(
            'Debug',
            'Release',
          );
        });
        await refusal(
          () => initializeTrustedNativeRuntime(root),
          'INCOMPATIBLE',
        );
      case 'test-selection':
        manifest(root, (d) => d['testOnly'] = true);
        await refusal(
          () => initializeTrustedNativeRuntime(root),
          'INCOMPATIBLE',
        );
        check(
          (await initializeTrustedNativeRuntime(
            root,
            testOnly: true,
          )).manifest.testOnly,
        );
        restore();
        await refusal(
          () => initializeTrustedNativeRuntime(root),
          'INCOMPATIBLE',
        );
      case 'load-failure':
        final dll = File(p.join(root, 'libisar.dll')),
            bytes = File(p.join(root, 'libisar.dll')).readAsBytesSync();
        dll.writeAsBytesSync([1, 2, 3]);
        manifest(
          root,
          (d) => (d['sha256'] as Map)['libisar.dll'] = fileSha256(dll.path),
        );
        await refusal(
          () => initializeTrustedNativeRuntime(root),
          'PREREQUISITE_UNAVAILABLE',
        );
        await refusal(
          () => initializeTrustedNativeRuntime(root),
          'PREREQUISITE_UNAVAILABLE',
        );
        dll.writeAsBytesSync(bytes);
        restore();
        await refusal(
          () => initializeTrustedNativeRuntime(root),
          'INCOMPATIBLE',
        );
      default:
        throw StateError('UNKNOWN_MODE');
    }
    check(!Directory(p.join(root, 'ServerDeckNext')).existsSync());
    stdout.writeln('PASS:$mode');
  } catch (error, stack) {
    stderr.writeln(error);
    stderr.writeln(stack);
    exitCode = 1;
  }
}
