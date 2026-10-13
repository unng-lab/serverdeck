import 'dart:ffi';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/storage/native_failure.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:test/test.dart';

import 'support/native_artifact.dart';

void main() {
  test('only exact pinned native capacity errors qualify for rollback proof', () {
    expect(isNativeCapacityFailure(IsarError('The database is full.')), true);
    expect(
      isNativeCapacityFailure(
        IsarError(
          'Auto increment id cannot be generated because the limit is reached.',
        ),
      ),
      true,
    );
    for (final error in <Object>[
      StateError('The database is full.'),
      IsarError('The database is full. extra'),
      IsarError('Unique index violated.'),
      IsarError('Transaction closed.'),
    ]) {
      expect(isNativeCapacityFailure(error), false);
    }
  });

  test(
    'real pinned map-full aborts every earlier write and allows recovery',
    () async {
      final nativeLibrary = nativeArtifactForTest();
      await Isar.initializeIsarCore(
        libraries: {Abi.windowsX64: nativeLibrary},
        download: false,
      );
      final parent = Directory.systemTemp.createTempSync(
        'serverdeck-map-full-fixture-',
      );
      final root = p.normalize(p.absolute(parent.path));
      if (!p.isWithin(
        p.normalize(p.absolute(Directory.systemTemp.path)),
        root,
      )) {
        throw StateError('UNSAFE_TEST_DIRECTORY');
      }
      Isar? database;
      Future<Isar> open() => Isar.open(
        workspaceSchemas,
        directory: root,
        name: 'capacity',
        maxSizeMiB: 10,
        relaxedDurability: false,
        inspector: false,
      );
      var committed = 0, exhausted = false;
      try {
        database = await open();
        final active = database;
        for (var i = 0; i < 128; i++) {
          try {
            await active.writeTxn(() async {
              await active.storedWorkspaces.put(
                StoredWorkspace()..payload = 'commit-$i',
              );
              await active.storedReceipts.put(
                StoredReceipt()
                  ..entityId = 'receipt-$i'
                  ..payload = 'receipt-$i',
              );
              await active.storedProfiles.put(
                StoredProfile()
                  ..entityId = 'profile-$i'
                  ..payload = 'x' * (256 * 1024),
              );
            });
            committed++;
          } on IsarError catch (error) {
            expect(isNativeCapacityFailure(error), true);
            expect(error.message, 'The database is full.');
            exhausted = true;
            expect(await active.storedProfiles.count(), committed);
            expect(await active.storedReceipts.count(), committed);
            expect(
              (await active.storedWorkspaces.get(1))!.payload,
              'commit-${committed - 1}',
            );
            expect(
              await active.storedProfiles
                  .where()
                  .entityIdEqualTo('profile-$i')
                  .findFirst(),
              null,
            );
            expect(
              await active.storedReceipts
                  .where()
                  .entityIdEqualTo('receipt-$i')
                  .findFirst(),
              null,
            );
            break;
          }
        }
        expect(exhausted, true);
        expect(committed, greaterThan(3));
        await active.writeTxn(() async {
          final rows = await active.storedProfiles.where().limit(3).findAll();
          await active.storedProfiles.deleteAll(rows.map((r) => r.id).toList());
          await active.storedWorkspaces.put(
            StoredWorkspace()..payload = 'recovered',
          );
        });
        expect(await active.close(), true);
        database = null;
        database = await open();
        expect((await database.storedWorkspaces.get(1))!.payload, 'recovered');
        expect(await database.storedProfiles.count(), committed - 3);
        expect(await database.storedReceipts.count(), committed);
      } finally {
        await database?.close();
        parent.deleteSync(recursive: true);
      }
    },
    testOn: 'windows',
  );
}
