import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/storage/migrations.dart';
import 'package:serverdeck/storage/records.dart';
import 'package:serverdeck/storage/workspace_store.dart';

import '../fixtures/fake_store_backend.dart';

/// Synthetic files and fake DB state; this does not run Isar or native publication.
class Fixture {
  late Directory root;
  late WorkspaceStore store;
  final backend = FakeStoreBackend();
  final source = StoreManifest(newStoreId(), formatVersion: 1);
  final protectedInputs = <Uint8List>[];
  bool protectionFails = false;
  String? publicationFailure;
  int publications = 0, stageFlushes = 0;
  bool failFlush = false;
  Future<void> Function()? beforeProtect;

  Future<void> initialize() async {
    root = await Directory.systemTemp.createTemp('serverdeck-format2-unit-');
    final folder = Directory('${root.path}/data/${source.relativeDirectory}');
    await Directory('${folder.path}/nested').create(recursive: true);
    await File('${folder.path}/serverdeck.isar').writeAsString('legacy bytes');
    await File('${folder.path}/nested/synthetic.bin').writeAsBytes([3, 4, 5]);
    await File('${root.path}/data/CURRENT.json').writeAsBytes(source.encode());
    final library = await File('${root.path}/synthetic-library')
        .writeAsString('unit');
    backend.databases[source.storeId] = FakeDatabase()
      ..settings.value = (AppSettings()
        ..logicalFormat = 1
        ..theme = 'light'
        ..settingsRevision = 7
        ..dataRevision = 11
        ..createdAt = 42);
    backend.beforeOpen = (path) async {
      if (path.contains('/staging-') &&
          backend.databases.values.last.settings.value?.logicalFormat == 2) {
        expect(
          stageFlushes,
          greaterThan(0),
          reason: 'verification open follows native staging flush',
        );
      }
    };
    store = WorkspaceStore(
      dataRoot: root.path,
      libraryPath: library.path,
      backend: backend,
      protectReceiptKey: (bytes) async {
        protectedInputs.add(bytes);
        expect(bytes.length, 32);
        await beforeProtect?.call();
        if (protectionFails) throw const StoreFailure('PROTECTION_UNAVAILABLE');
        return Uint8List.fromList(List.filled(64, 19));
      },
      flushAtomic: (path, bytes) async {
        if (path.startsWith('data/flush/')) {
          expect(bytes, isEmpty);
          stageFlushes++;
          expect(
            backend.databases.values.last.settings.value!.logicalFormat,
            2,
          );
          expect(backend.databases.values.last.closes, greaterThan(0));
          if (failFlush) throw const StoreFailure('STORAGE_IO');
          return;
        }
        publications++;
        final id = path.substring('data/publish/'.length);
        if (publications == 1 && publicationFailure == 'beforeRename') {
          throw const StoreFailure('STORAGE_IO');
        }
        final stage = Directory('${root.path}/data/staging-$id');
        await Directory('${root.path}/data/stores').create(recursive: true);
        if (await stage.exists())
          await stage.rename('${root.path}/data/stores/$id');
        if (publications == 1 && publicationFailure == 'afterRename') {
          throw const StoreFailure('STORAGE_IO');
        }
        await File('${root.path}/data/CURRENT.json').writeAsBytes(bytes);
        if (publications == 1 && publicationFailure == 'afterCurrent') {
          throw const StoreFailure('STORAGE_IO');
        }
      },
    );
  }

  Future<void> expectSourcePreserved() async {
    expect(backend.databases[source.storeId]!.settings.value!.logicalFormat, 1);
    expect(
      await File(
        '${root.path}/data/${source.relativeDirectory}/serverdeck.isar',
      ).readAsString(),
      'legacy bytes',
    );
    expect(
      backend.openedPaths.any((p) => p.endsWith(source.relativeDirectory)),
      isFalse,
    );
  }

  Future<void> dispose() async {
    await store.close();
    await root.delete(recursive: true);
  }
}

void main() {
  test(
    'current schema set is complete and secrets have only protected fields',
    () {
      expect(workspaceSchemas.map((s) => s.name).toSet(), {
        'AppSettings',
        'Profile',
        'Credential',
        'EndpointTrust',
        'McpGrant',
        'MutationReceipt',
        'SecurityState',
      });
      expect(ProfileSchema.indexes['profileId']!.unique, isTrue);
      expect(CredentialSchema.indexes['profileId']!.unique, isTrue);
      expect(CredentialSchema.properties.keys, contains('protectedBytes'));
      expect(CredentialSchema.properties.keys, isNot(contains('password')));
      expect(
        SecurityStateSchema.properties.keys,
        contains('protectedReceiptHmacKey'),
      );
    },
  );

  late Fixture fixture;
  setUp(() async {
    fixture = Fixture();
    await fixture.initialize();
  });
  tearDown(() => fixture.dispose());

  test('migrates a verified copy, preserves settings and original directory', () async {
    await fixture.store.open();
    final selected = (await preflightStore(
      Directory('${fixture.root.path}/data'),
    ))!;
    expect(selected.formatVersion, 2);
    expect(selected.storeId, isNot(fixture.source.storeId));
    expect(fixture.store.theme, 'light');
    final db = fixture.backend.databases[selected.storeId]!;
    expect(db.settings.value!.settingsRevision, 7);
    expect(db.settings.value!.dataRevision, 11);
    expect(db.settings.value!.createdAt, 42);
    expect(db.security.value!.authorizationEpoch, 1);
    expect(
      await File(
        '${fixture.root.path}/data/${selected.relativeDirectory}/nested/synthetic.bin',
      ).readAsBytes(),
      [3, 4, 5],
    );
    expect(fixture.protectedInputs.single, everyElement(0));
    expect(fixture.backend.copies, 1);
    await fixture.expectSourcePreserved();
  });

  for (final failure in ['beforeRename', 'afterRename', 'afterCurrent']) {
    test(
      'migration publication retry after $failure reuses the same copy and key',
      () async {
        fixture.publicationFailure = failure;
        await expectLater(fixture.store.open(), throwsA(isA<StoreFailure>()));
        expect(fixture.store.isOpen, isFalse);
        if (failure != 'afterCurrent') {
          expect(
            await File('${fixture.root.path}/data/CURRENT.json').readAsBytes(),
            fixture.source.encode(),
          );
        }
        await fixture.expectSourcePreserved();
        final copiedId = fixture.backend.databases.keys.singleWhere(
          (id) => id != fixture.source.storeId,
        );
        await fixture.store.open();
        final selected = (await preflightStore(
          Directory('${fixture.root.path}/data'),
        ))!;
        expect(selected.storeId, copiedId);
        expect(fixture.protectedInputs.length, 1);
        expect(fixture.backend.copies, 1);
        await fixture.expectSourcePreserved();
      },
    );
  }

  test(
    'protection failure leaves CURRENT and source intact, retry is explicit',
    () async {
      fixture.protectionFails = true;
      await expectLater(fixture.store.open(), throwsA(isA<StoreFailure>()));
      expect(
        await File('${fixture.root.path}/data/CURRENT.json').readAsBytes(),
        fixture.source.encode(),
      );
      expect(fixture.publications, 0);
      expect(fixture.protectedInputs.single, everyElement(0));
      await fixture.expectSourcePreserved();
      fixture.protectionFails = false;
      await fixture.store.open();
      expect(fixture.store.isOpen, isTrue);
      expect(fixture.backend.copies, 1);
    },
  );

  test(
    'failed copy validation never publishes or mutates selected source',
    () async {
      var opens = 0;
      fixture.backend.beforeOpen = (path) async {
        if (++opens == 2) {
          fixture.backend.databases.values.last.settings.value!.logicalFormat =
              99;
        }
      };
      await expectLater(fixture.store.open(), throwsA(isA<StoreFailure>()));
      expect(fixture.publications, 0);
      expect(
        await File('${fixture.root.path}/data/CURRENT.json').readAsBytes(),
        fixture.source.encode(),
      );
      await fixture.expectSourcePreserved();
    },
  );

  test(
    'unconfirmed close is retained and blocks further migration work',
    () async {
      fixture.backend.beforeOpen = (path) async {
        if (fixture.backend.openedPaths.length == 1) {
          fixture.backend.databases.values.last.failingCloses = 2;
        }
      };
      await expectLater(fixture.store.open(), throwsA(isA<StoreFailure>()));
      await expectLater(fixture.store.open(), throwsA(isA<StoreFailure>()));
      expect(fixture.backend.openedPaths.length, 1);
      expect(fixture.publications, 0);
      await fixture.store.open();
      expect(fixture.backend.copies, 1);
      expect(fixture.protectedInputs.length, 1);
      await fixture.expectSourcePreserved();
    },
  );

  test(
    'failed format conversion transaction keeps the copied format1 for retry',
    () async {
      fixture.backend.beforeOpen = (path) async {
        if (fixture.backend.openedPaths.length == 1) {
          fixture.backend.databases.values.last.failNextTransaction = true;
        }
      };
      await expectLater(fixture.store.open(), throwsStateError);
      expect(
        fixture.backend.databases.values.last.settings.value!.logicalFormat,
        1,
      );
      expect(fixture.backend.databases.values.last.security.value, isNull);
      expect(fixture.publications, 0);
      await fixture.store.open();
      expect(fixture.store.isOpen, isTrue);
      await fixture.expectSourcePreserved();
    },
  );

  test('shutdown during opening drains it without admitting a write', () async {
    final entered = Completer<void>(), release = Completer<void>();
    fixture.beforeProtect = () {
      entered.complete();
      return release.future;
    };
    final opening = fixture.store.open();
    await entered.future;
    final closing = fixture.store.close();
    await expectLater(fixture.store.open(), throwsA(isA<StoreFailure>()));
    release.complete();
    await opening;
    await closing;
    expect(fixture.store.isOpen, isFalse);
    await expectLater(
      fixture.store.write((_) => 1),
      throwsA(isA<StoreFailure>()),
    );
  });

  test(
    'partial copy failure retries only its own target without changing CURRENT',
    () async {
      final targets = <String>[];
      fixture.backend.beforeCopy = (source, target) async {
        targets.add(target);
        if (targets.length == 1) {
          await Directory(target).create(recursive: true);
          throw const StoreFailure('STORAGE_IO');
        }
      };
      await expectLater(fixture.store.open(), throwsA(isA<StoreFailure>()));
      expect(
        await File('${fixture.root.path}/data/CURRENT.json').readAsBytes(),
        fixture.source.encode(),
      );
      await fixture.store.open();
      expect(targets.length, 2);
      expect(targets[0], targets[1]);
      await fixture.expectSourcePreserved();
    },
  );

  test(
    'future format is refused before initializing any database backend',
    () async {
      await File('${fixture.root.path}/data/CURRENT.json').writeAsBytes(
        StoreManifest(fixture.source.storeId, formatVersion: 3).encode(),
      );
      await expectLater(fixture.store.open(), throwsA(isA<StoreFailure>()));
      expect(fixture.backend.initialized, isEmpty);
      expect(fixture.backend.openedPaths, isEmpty);
      expect(fixture.protectedInputs, isEmpty);
    },
  );

  test(
    'format2 missing security key blocks instead of creating a replacement',
    () async {
      await File('${fixture.root.path}/data/CURRENT.json')
          .writeAsBytes(StoreManifest(fixture.source.storeId).encode());
      fixture
              .backend
              .databases[fixture.source.storeId]!
              .settings
              .value!
              .logicalFormat =
          2;
      await expectLater(fixture.store.open(), throwsA(isA<StoreFailure>()));
      expect(fixture.backend.copies, 0);
      expect(fixture.protectedInputs, isEmpty);
      expect(
        fixture.backend.databases[fixture.source.storeId]!.security.value,
        isNull,
      );
    },
  );

  test(
    'existing format2 preserves its key and enabled MCP setting on open',
    () async {
      await File('${fixture.root.path}/data/CURRENT.json')
          .writeAsBytes(StoreManifest(fixture.source.storeId).encode());
      final db = fixture.backend.databases[fixture.source.storeId]!;
      db.settings.value!
        ..logicalFormat = 2
        ..mcpEnabled = true;
      db.security.value = SecurityState()
        ..protectedReceiptHmacKey = List.filled(64, 27);
      await fixture.store.open();
      expect(fixture.protectedInputs, isEmpty);
      expect(fixture.backend.copies, 0);
      expect(db.security.value!.protectedReceiptHmacKey, everyElement(27));
      expect(db.settings.value!.mcpEnabled, isTrue);
    },
  );

  test(
    'staging flush failure keeps old CURRENT and retry does not regenerate key',
    () async {
      fixture.failFlush = true;
      await expectLater(fixture.store.open(), throwsA(isA<StoreFailure>()));
      expect(fixture.stageFlushes, 1);
      expect(fixture.publications, 0);
      expect(
        await File('${fixture.root.path}/data/CURRENT.json').readAsBytes(),
        fixture.source.encode(),
      );
      fixture.failFlush = false;
      await fixture.store.open();
      expect(fixture.stageFlushes, 2);
      expect(fixture.backend.copies, 1);
      expect(fixture.protectedInputs.length, 1);
      await fixture.expectSourcePreserved();
    },
  );
}
