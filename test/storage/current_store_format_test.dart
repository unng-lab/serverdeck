import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/storage/store_manifest.dart';
import 'package:serverdeck/storage/workspace_store.dart';

import '../fixtures/fake_store_backend.dart';

void main() {
  test(
    'fresh manifest has current format3 and independent publicationVersion1',
    () {
      final manifest = StoreManifest(newStoreId());
      final json = jsonDecode(utf8.decode(manifest.encode())) as Map;
      expect(json['publicationVersion'], 1);
      expect(json['formatVersion'], 3);
      expect(StoreManifest.decode(manifest.encode()).storeId, manifest.storeId);
    },
  );
  for (final version in [1, 2, 4, 2147483647]) {
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
}
