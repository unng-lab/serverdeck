import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/storage/migrations.dart';

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
      if (mutation == 'future') value['formatVersion'] = 3;
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
