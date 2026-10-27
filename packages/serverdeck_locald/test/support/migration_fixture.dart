import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/process.dart';

import 'native_artifact.dart';

/// Owns only fresh synthetic migration fixtures and child processes.
final class MigrationFixture {
  MigrationFixture._(this.root, this.bundle, this.migrationExecutable);
  static MigrationFixture create({String? migrationExecutable}) {
    final root = Directory.systemTemp.createTempSync(
      'serverdeck-migration-fixture-',
    );
    final path = p.normalize(p.absolute(root.path));
    if (!p.isWithin(p.normalize(p.absolute(Directory.systemTemp.path)), path))
      throw StateError('UNSAFE_FIXTURE');
    final bundle = Directory(p.join(path, 'bundle'))..createSync();
    File(p.join(bundle.path, 'serverdeck.exe')).writeAsBytesSync([1, 2, 3]);
    File(p.join(bundle.path, 'locald.exe')).writeAsBytesSync([4, 5, 6]);
    File(nativeArtifactForTest()).copySync(p.join(bundle.path, 'libisar.dll'));
    File(p.join(bundle.path, 'foundation.manifest.json')).writeAsStringSync(
      jsonEncode({
        'format': 1,
        'buildId': '${'a' * 40}+Debug+${'b' * 64}',
        'configuration': 'Debug',
        'testOnly': false,
        'appRoot': bundle.path,
        'sha256': {
          for (final name in ['serverdeck.exe', 'locald.exe', 'libisar.dll'])
            name: fileSha256(p.join(bundle.path, name)),
        },
      }),
    );
    return MigrationFixture._(path, bundle.path, migrationExecutable);
  }

  final String root, bundle;
  final String? migrationExecutable;
  final _children = <Process>[];
  Future<Process> startMigration(String mode, [String? boundary]) async {
    final child = await Process.start(
      migrationExecutable ??
          p.join(p.dirname(Platform.resolvedExecutable), 'dartvm.exe'),
      [
        if (migrationExecutable == null) ...[
          '-DSERVERDECK_TEST_MIGRATION_PROBES=true',
          'test/support/migration_orchestrator_child.dart',
        ],
        root,
        bundle,
        mode,
        if (boundary != null) boundary,
      ],
    );
    _children.add(child);
    return child;
  }

  Future<Process> start(String mode) async {
    final child = await Process.start(Platform.resolvedExecutable, [
      'test/support/migration_child.dart',
      root,
      bundle,
      mode,
    ]);
    _children.add(child);
    return child;
  }

  Future<void> close() async {
    for (final child in _children) {
      child.kill();
      await child.exitCode;
    }
    if (!p.isWithin(p.normalize(p.absolute(Directory.systemTemp.path)), root) ||
        !p.basename(root).startsWith('serverdeck-migration-fixture-'))
      throw StateError('UNSAFE_FIXTURE');
    Directory(root).deleteSync(recursive: true);
  }
}
