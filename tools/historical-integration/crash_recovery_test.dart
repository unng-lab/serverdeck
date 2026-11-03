import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/storage/migrations.dart';
import 'package:serverdeck/storage/workspace_store.dart';

void main() {
  for (final mode in ['committed', 'uncommitted']) {
    test('process termination preserves $mode transaction outcome', () async {
      final root = await Directory.systemTemp.createTemp('serverdeck-crash-');
      final config = jsonDecode(
        await File('.dart_tool/package_config.json').readAsString(),
      ) as Map<String, dynamic>;
      final packages = (config['packages'] as List)
          .cast<Map<String, dynamic>>();
      final native = packages.singleWhere(
        (p) => p['name'] == 'isar_community_flutter_libs',
      );
      final flutter = packages.singleWhere((p) => p['name'] == 'flutter');
      final library = File.fromUri(
        Uri.parse('${native['rootUri']}/').resolve('windows/libisar.dll'),
      ).absolute.path;
      final flutterPath = Directory.fromUri(
        Uri.parse('${flutter['rootUri']}/'),
      );
      final dart =
          '${flutterPath.parent.parent.path}/bin/cache/dart-sdk/bin/dart.exe';
      final store = WorkspaceStore(
        dataRoot: root.path,
        libraryPath: library,
        flushAtomic: (path, bytes) async {
          final id = path.substring('data/publish/'.length);
          await Directory('${root.path}/data/stores').create(recursive: true);
          await Directory('${root.path}/data/staging-$id')
              .rename('${root.path}/data/stores/$id');
          await File('${root.path}/data/CURRENT.json')
              .writeAsBytes(bytes, flush: true);
        },
      );
      addTearDown(() async {
        await store.close();
        await root.delete(recursive: true);
      });
      await store.open();
      await store.close();
      final manifest = (await preflightStore(Directory('${root.path}/data')))!;
      final child = await Process.start(dart, [
        'run',
        'test/fixtures/isar_crash_writer.dart',
        '${root.path}/data/${manifest.relativeDirectory}',
        library,
        mode,
      ]);
      final errors = child.stderr.transform(utf8.decoder).join();
      try {
        final marker = mode == 'committed' ? 'COMMITTED' : 'DURING';
        await child.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .firstWhere((line) => line == marker)
            .timeout(const Duration(seconds: 30));
      } catch (_) {
        child.kill();
        await child.exitCode;
        fail(
          'Crash fixture did not reach transaction barrier: ${await errors}',
        );
      }
      expect(child.kill(), isTrue);
      await child.exitCode;
      await store.open();
      expect(store.theme, mode == 'committed' ? 'light' : 'dark');
    });
  }
}
