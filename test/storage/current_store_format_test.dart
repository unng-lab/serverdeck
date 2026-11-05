import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/storage/store_manifest.dart';
import 'package:serverdeck/storage/workspace_store.dart';
import 'package:serverdeck/storage/records.dart';

import '../fixtures/fake_store_backend.dart';

void main() {
  test('fresh manifest retains format2 for additive schema and independent publicationVersion1', () {
    final manifest = StoreManifest(newStoreId());
    final json = jsonDecode(utf8.decode(manifest.encode())) as Map;
    expect(json['publicationVersion'], 1);
    expect(json['formatVersion'], 2);
    expect(AppSettings().logicalFormat, 2);
    expect(
      workspaceSchemas.map((schema) => schema.name),
      containsAll(['MonitoringHistoryRecord', 'JournalSource']),
    );
    expect(StoreManifest.decode(manifest.encode()).storeId, manifest.storeId);
  });
  for (final version in [1, currentStorageFormat + 1, 2147483647]) {
    test(
      'format$version is rejected before backend initialize/open or any write',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'current-format-unit-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final manifest = StoreManifest(newStoreId());
        final current = File('${root.path}/data/CURRENT.json');
        current.parent.createSync(recursive: true);
        final fields =
            jsonDecode(utf8.decode(manifest.encode())) as Map<String, dynamic>;
        fields['formatVersion'] = version;
        final original = utf8.encode(jsonEncode(fields));
        current.writeAsBytesSync(original);
        final backend = FakeStoreBackend();
        var writes = 0;
        final store = WorkspaceStore(
          dataRoot: root.path,
          libraryPath: '${root.path}/unused-library',
          backend: backend,
          flushAtomic: (_, _) async {
            writes++;
          },
        );
        await expectLater(
          store.open(),
          throwsA(
            isA<StoreFailure>().having(
              (e) => e.code,
              'code',
              'INCOMPATIBLE_STORE',
            ),
          ),
        );
        expect(backend.openedPaths, isEmpty);
        expect(backend.initialized, isEmpty);
        expect(writes, 0);
        expect(current.readAsBytesSync(), original);
        await store.close();
      },
    );
  }

  test('additive schema opens existing format2 without replacement or metadata rewrite', () async {
    final root = Directory.systemTemp.createTempSync('compatible-format-unit-');
    addTearDown(() => root.deleteSync(recursive: true));
    final manifest = StoreManifest(newStoreId());
    final data = Directory('${root.path}/data/${manifest.relativeDirectory}')
      ..createSync(recursive: true);
    File('${data.path}/serverdeck.isar').writeAsStringSync('synthetic fixture');
    final current = File('${root.path}/data/CURRENT.json')
      ..writeAsBytesSync(manifest.encode());
    final original = current.readAsBytesSync();
    final library = File('${root.path}/synthetic-library')
      ..writeAsStringSync('unit');
    final backend = FakeStoreBackend();
    final database = FakeDatabase();
    database.settings.value = AppSettings()
      ..logicalFormat = currentStorageFormat
      ..theme = 'light'
      ..settingsRevision = 12
      ..dataRevision = 27
      ..profilesListRevision = 9;
    database.security.value = SecurityState()
      ..protectedReceiptHmacKey = [17, 23]
      ..authorizationEpoch = 5;
    backend.databases[manifest.storeId] = database;
    var publications = 0;
    final store = WorkspaceStore(
      dataRoot: root.path,
      libraryPath: library.path,
      backend: backend,
      flushAtomic: (_, _) async {
        publications++;
      },
    );
    await store.open();
    expect(store.isOpen, isTrue);
    expect(backend.openedPaths, [data.path]);
    expect(publications, 0);
    expect(current.readAsBytesSync(), original);
    expect(StoreManifest.decode(original).encode(), original);
    expect(database.settings.value!.logicalFormat, currentStorageFormat);
    expect(database.settings.value!.theme, 'light');
    expect(database.settings.value!.dataRevision, 27);
    expect(database.settings.value!.profilesListRevision, 9);
    expect(database.security.value!.protectedReceiptHmacKey, [17, 23]);
    expect(database.security.value!.authorizationEpoch, 5);
    await store.close();
  });
  test('noninteger and unknown formats remain rejected', () {
    for (final value in [null, '2', 2.0, 0, -1, currentStorageFormat + 1]) {
      expect(isCompatibleStorageFormat(value), isFalse);
    }
  });
}
