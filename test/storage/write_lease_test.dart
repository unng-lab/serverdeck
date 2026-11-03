import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/storage/records.dart';
import 'package:serverdeck/storage/migrations.dart';
import 'package:serverdeck/storage/domain_repository.dart';
import 'package:serverdeck/storage/workspace_store.dart';

import '../fixtures/fake_store_backend.dart';

void main() {
  late Directory root;
  late WorkspaceStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('serverdeck-isar-');
    final library = await File('${root.path}/synthetic-library')
        .writeAsString('unit');
    store = WorkspaceStore(
      dataRoot: root.path,
      libraryPath: library.path,
      backend: FakeStoreBackend(),
      protectReceiptKey: fakeProtectReceiptKey,
      flushAtomic: (path, bytes) async {
        if (path.startsWith('data/flush/')) {
          expect(bytes, isEmpty);
          return;
        }
        final id = path.substring('data/publish/'.length);
        await Directory('${root.path}/data/stores').create(recursive: true);
        await Directory('${root.path}/data/staging-$id')
            .rename('${root.path}/data/stores/$id');
        await File('${root.path}/data/CURRENT.json')
            .writeAsBytes(bytes, flush: true);
      },
    );
    await store.open();
  });
  tearDown(() async {
    await store.close();
    await root.delete(recursive: true);
  });

  test('domain repository uses store transaction and rolls back the complete write', () async {
    final repository = WorkspaceDomainRepository(store);
    final backend = store.backend as FakeStoreBackend;
    final database = backend.databases.values.single;
    final original = repository.read(
      (r) => (r.settings.dataRevision, r.security.authorizationEpoch),
    );
    database.failNextTransaction = true;
    await expectLater(
      repository.write((records) {
        records.putSettings(records.settings..dataRevision = 2);
        records.putSecurity(records.security..authorizationEpoch = 2);
        expect(repository.read((r) => r.settings.dataRevision), 2);
        return 2;
      }),
      throwsStateError,
    );
    expect(
      repository.read(
        (r) => (r.settings.dataRevision, r.security.authorizationEpoch),
      ),
      original,
    );
    await repository.write((records) {
      records.putSettings(records.settings..dataRevision = 2);
    });
    expect(repository.read((r) => r.settings.dataRevision), 2);
    final detached = repository.read((r) => r.settings)..dataRevision = 99;
    expect(detached.dataRevision, 99);
    expect(repository.read((r) => r.settings.dataRevision), 2);
  });

  test(
    'owner reads reuse ambient transaction and see current write values',
    () async {
      final backend = store.backend as FakeStoreBackend;
      final database = backend.databases.values.single;
      expect(
        store.readSync((db) => db.appSettings.getSync(1)!.dataRevision),
        1,
      );
      expect(database.readTransactions, 1);
      await store.write((db) {
        final value = db.appSettings.getSync(1)!..dataRevision = 2;
        db.appSettings.putSync(value);
        expect(
          store.readSync((db) => db.appSettings.getSync(1)!.dataRevision),
          2,
        );
        expect(database.readTransactions, 1);
      });
      expect(
        store.readSync(
          (db) =>
              store.readSync((db) => db.appSettings.getSync(1)!.dataRevision),
        ),
        2,
      );
      expect(database.readTransactions, 2);
    },
  );

  test(
    'failed read or write releases ambient read reuse and closed reads fail',
    () async {
      expect(
        () => store.readSync<void>((_) => throw StateError('synthetic')),
        throwsStateError,
      );
      expect(
        store.readSync((db) => db.appSettings.getSync(1)!.dataRevision),
        1,
      );
      await expectLater(
        store.write<void>((_) => throw StateError('synthetic')),
        throwsStateError,
      );
      expect(
        store.readSync((db) => db.appSettings.getSync(1)!.dataRevision),
        1,
      );
      await store.close();
      expect(() => store.readSync((_) => 1), throwsA(isA<StoreFailure>()));
    },
  );

  test(
    'accepted lease commits before close and new writes are rejected',
    () async {
      final saved = store.write((db) {
        final settings = db.appSettings.getSync(1)!..theme = 'light';
        db.appSettings.putSync(settings);
        return settings.settingsRevision;
      });
      store.stopAdmission();
      await expectLater(store.write((db) => 0), throwsException);
      final closing = store.close();
      expect(await saved, 1);
      await closing;
      await store.open();
      expect(store.theme, 'light');
    },
  );

  test(
    'failed transaction rolls back all changes and does not poison next lease',
    () async {
      final failed = store.write<void>((db) {
        final settings = db.appSettings.getSync(1)!..theme = 'light';
        db.appSettings.putSync(settings);
        throw StateError('rollback');
      });
      await expectLater(failed, throwsStateError);
      expect(
        await store.write((db) => db.appSettings.getSync(1)!.theme),
        'dark',
      );
      await store.close();
      await store.open();
      expect(store.theme, 'dark');
    },
  );
}
