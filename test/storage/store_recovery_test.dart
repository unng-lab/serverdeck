import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/storage/store_manifest.dart';

void main() {
  late Directory root;
  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('serverdeck-store-'),
  );
  tearDown(() async => root.delete(recursive: true));
  test('empty root permits first publication', () async {
    expect(await preflightStore(root), isNull);
  });
  for (final state in ['running', 'clean']) {
    test(
      '$state monitoring marker permits first database publication',
      () async {
        final marker = File('${root.path}/monitoring-run-v1.json');
        final bytes = utf8.encode('{"version":1,"state":"$state"}');
        await marker.writeAsBytes(bytes);
        expect(await preflightStore(root), isNull);
        expect(await marker.readAsBytes(), bytes);
        await Directory('${root.path}/stores/${newStoreId()}')
            .create(recursive: true);
        await expectLater(preflightStore(root), throwsA(isA<StoreFailure>()));
        expect(await marker.readAsBytes(), bytes);
      },
    );
  }
  for (final value in [
    '{}',
    '{"version":2,"state":"running"}',
    'x' * 129,
    '\ufeff{"version":1,"state":"running"}',
    '\ufeff{"version":1,"state":"clean"}',
  ]) {
    test(
      'invalid monitoring marker remains an explicit failure: $value',
      () async {
        final marker = File('${root.path}/monitoring-run-v1.json');
        final bytes = utf8.encode(value);
        await marker.writeAsBytes(bytes);
        await expectLater(preflightStore(root), throwsA(isA<StoreFailure>()));
        await expectLater(
          validatePendingPublication(root, StoreManifest(newStoreId())),
          throwsA(isA<StoreFailure>()),
        );
        expect(await marker.readAsBytes(), bytes);
      },
    );
  }
  test('marker name cannot disguise a directory or unknown file', () async {
    await Directory('${root.path}/monitoring-run-v1.json').create();
    await expectLater(preflightStore(root), throwsA(isA<StoreFailure>()));
    await Directory('${root.path}/monitoring-run-v1.json').delete();
    await File('${root.path}/unknown.json')
        .writeAsString('{"version":1,"state":"running"}');
    await expectLater(preflightStore(root), throwsA(isA<StoreFailure>()));
  });
  test(
    'missing CURRENT with existing store never creates replacement',
    () async {
      await Directory('${root.path}/stores/${newStoreId()}')
          .create(recursive: true);
      await expectLater(preflightStore(root), throwsA(isA<StoreFailure>()));
    },
  );
  test('missing selected database blocks before Isar can create it', () async {
    final manifest = StoreManifest(newStoreId());
    await File('${root.path}/CURRENT.json').writeAsBytes(manifest.encode());
    await Directory('${root.path}/${manifest.relativeDirectory}')
        .create(recursive: true);
    await expectLater(preflightStore(root), throwsA(isA<StoreFailure>()));
  });
  for (final mutation in ['future', 'traversal', 'corrupt']) {
    test('$mutation CURRENT blocks without replacing metadata', () async {
      final value = jsonDecode(
        utf8.decode(StoreManifest(newStoreId()).encode()),
      ) as Map<String, dynamic>;
      if (mutation == 'future') value['formatVersion'] = 4;
      if (mutation == 'traversal') value['relativeDirectory'] = '../outside';
      final bytes = mutation == 'corrupt'
          ? [255, 0]
          : utf8.encode(jsonEncode(value));
      final current = File('${root.path}/CURRENT.json');
      await current.writeAsBytes(bytes);
      await expectLater(preflightStore(root), throwsA(isA<StoreFailure>()));
      expect(await current.readAsBytes(), bytes);
    });
  }
}
