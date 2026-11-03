import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/storage/workspace_store.dart';

import '../fixtures/fake_store_backend.dart';

import 'package:serverdeck/storage/migrations.dart';

void main() {
  for (final failure in ['beforeRename', 'afterRename', 'afterCurrent']) {
    test(
      'first publication resumes after $failure without resetting data',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'serverdeck-publication-',
        );
        final library = await File('${root.path}/synthetic-library')
            .writeAsString('unit');
        var calls = 0;
        String? publication;
        final store = WorkspaceStore(
          dataRoot: root.path,
          libraryPath: library.path,
          backend: FakeStoreBackend(),
          protectReceiptKey: fakeProtectReceiptKey,
          flushAtomic: (path, bytes) async {
            if (path.startsWith('data/flush/')) {
              expect(bytes, isEmpty);
              return;
            }
            calls++;
            final id = path.substring('data/publish/'.length);
            publication ??= id;
            expect(id, publication);
            if (calls == 1 && failure == 'beforeRename')
              throw const StoreFailure('STORAGE_IO');
            final stage = Directory('${root.path}/data/staging-$id');
            await Directory('${root.path}/data/stores').create(recursive: true);
            if (await stage.exists())
              await stage.rename('${root.path}/data/stores/$id');
            if (calls == 1 && failure == 'afterRename')
              throw const StoreFailure('STORAGE_IO');
            await File('${root.path}/data/CURRENT.json')
                .writeAsBytes(bytes, flush: true);
            if (calls == 1 && failure == 'afterCurrent')
              throw const StoreFailure('STORAGE_IO');
          },
        );
        addTearDown(() async {
          await store.close();
          await root.delete(recursive: true);
        });
        await expectLater(store.open(), throwsA(isA<StoreFailure>()));
        expect(store.isOpen, isFalse);
        await store.open();
        expect(store.isOpen, isTrue);
        final selected = await preflightStore(Directory('${root.path}/data'));
        expect(selected!.storeId, publication);
        expect(await Directory('${root.path}/data/stores').list().length, 1);
        expect(calls, failure == 'afterCurrent' ? 1 : 2);
      },
    );
  }
  test('pending publication never adopts an unrelated orphan', () async {
    final root = await Directory.systemTemp.createTemp('serverdeck-orphan-');
    addTearDown(() => root.delete(recursive: true));
    final pending = StoreManifest(newStoreId());
    await Directory('${root.path}/stores/${newStoreId()}')
        .create(recursive: true);
    await expectLater(
      validatePendingPublication(root, pending),
      throwsA(isA<StoreFailure>()),
    );
  });
}
