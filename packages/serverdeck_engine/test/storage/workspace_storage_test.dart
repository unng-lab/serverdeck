import 'dart:async';

import 'package:serverdeck_engine/storage/workspace_rows.dart';
import 'package:serverdeck_engine/storage/workspace_storage.dart';
import 'package:test/test.dart';

import '../support/memory_workspace_storage.dart';

const family = WorkspaceCollection.profiles;
const first = StoredRow(41, '{"v":1}', entityId: 'CaseKey');
const second = StoredRow(42, '{"v":2}', entityId: 'casekey');

void main() {
  late MemoryWorkspaceStorage storage;
  setUp(() {
    storage = MemoryWorkspaceStorage(directory: '/synthetic/workspace');
  });
  tearDown(() async {
    if (storage.closeFailure case final Object failure) {
      await expectLater(storage.close(), throwsA(same(failure)));
    } else {
      await storage.close();
    }
  });

  test(
    'all16 families retain exact identity and payload through commit',
    () async {
      expect(WorkspaceCollection.values, hasLength(16));
      await storage.writeTransaction((tx) async {
        for (final collection in WorkspaceCollection.values) {
          final row = collection.singleton
              ? const StoredRow(1, '{ "retained" : true }')
              : first;
          expect(await tx.put(collection, row), row.nativeId);
          expect(await tx.get(collection, row.nativeId), same(row));
          if (!collection.singleton) {
            expect(
              await tx.getByEntityId(collection, row.entityId!),
              same(row),
            );
          }
        }
      });
      await storage.readTransaction(() async {
        for (final collection in WorkspaceCollection.values) {
          expect(await storage.count(collection.persistedName), 1);
          final rows = await storage.read(collection.persistedName, limit: 1);
          expect(
            rows.single.payload,
            collection.singleton ? '{ "retained" : true }' : first.payload,
          );
          expect(() => rows.clear(), throwsUnsupportedError);
        }
      });
    },
  );

  test(
    'callback error rolls back every changed family and preserves error',
    () async {
      final failure = StateError('FORBIDDEN');
      await expectLater(
        storage.writeTransaction((tx) async {
          await tx.put(family, first);
          await tx.put(WorkspaceCollection.receipts, second);
          throw failure;
        }),
        throwsA(same(failure)),
      );
      expect(
        storage.committedRows.values.every((rows) => rows.isEmpty),
        isTrue,
      );
    },
  );

  test('unique keys are case sensitive; collision aborts even when caught', () async {
    await storage.writeTransaction((tx) async {
      await tx.put(family, first);
      await tx.put(family, second);
    });
    await expectLater(
      storage.writeTransaction((tx) async {
        await tx.delete(family, second.nativeId);
        try {
          await tx.put(family, const StoredRow(99, '{}', entityId: 'CaseKey'));
        } on StateError {
          // Catching row failure must not allow the earlier deletion to commit.
        }
      }),
      throwsStateError,
    );
    expect(storage.committedRows[family.persistedName], [first, second]);
  });

  test(
    'explicit max ID and replacement retain identity; deletion is exact',
    () async {
      const maxRow = StoredRow(9223372036854775807, 'old', entityId: 'max');
      await storage.writeTransaction((tx) async {
        await tx.put(family, maxRow);
        expect(await tx.delete(family, 123), isFalse);
      });
      await storage.writeTransaction((tx) async {
        await tx.put(
          family,
          const StoredRow(9223372036854775807, 'new', entityId: 'max'),
        );
        expect(
          (await tx.getByEntityId(family, 'max'))!.nativeId,
          maxRow.nativeId,
        );
        expect(await tx.get(family, 123), isNull);
      });
      expect(
        storage.committedRows[family.persistedName]!.single.payload,
        'new',
      );
    },
  );

  test('invalid IDs and singleton/entity shape never commit', () async {
    for (final entry in [
      (family, const StoredRow(0, '{}', entityId: 'key')),
      (family, const StoredRow(-1, '{}', entityId: 'key')),
      (family, const StoredRow(1, '{}')),
      (WorkspaceCollection.settings, const StoredRow(2, '{}')),
      (WorkspaceCollection.workspace, first),
    ]) {
      await expectLater(
        storage.writeTransaction((tx) async {
          await tx.put(entry.$1, entry.$2);
        }),
        throwsStateError,
      );
    }
    expect(storage.committedRows.values.every((rows) => rows.isEmpty), isTrue);
  });

  test('escaped write scope and read zone expire with callback', () async {
    late WorkspaceWriteTransaction escaped;
    late Future<int> Function() lateRead;
    await storage.writeTransaction((tx) async {
      escaped = tx;
    });
    await expectLater(escaped.put(family, first), throwsStateError);
    await storage.readTransaction(() async {
      final zone = Zone.current;
      lateRead = () => zone.run(() => storage.count(family.persistedName));
    });
    expect(lateRead, throwsStateError);
  });

  test('nested read/write transactions fail before their callback', () async {
    var nested = false;
    await storage.writeTransaction((tx) async {
      await expectLater(
        storage.readTransaction(() async {
          nested = true;
        }),
        throwsStateError,
      );
      await expectLater(
        storage.writeTransaction((_) async {
          nested = true;
        }),
        throwsStateError,
      );
    });
    expect(nested, isFalse);
  });

  test(
    'unawaited pending write drains then aborts; no partial commit',
    () async {
      final hold = storage.holdPut = Completer<void>();
      late Future<int> rowWork;
      late Zone callbackZone;
      final callbackSettled = Completer<void>();
      final writing = storage.writeTransaction((tx) async {
        callbackZone = Zone.current;
        rowWork = tx.put(family, first);
        callbackSettled.complete();
      });
      final rejected = expectLater(writing, throwsStateError);
      await callbackSettled.future;
      await Future<void>.delayed(Duration.zero);
      expect(storage.committedRows[family.persistedName], isEmpty);
      final reads = (storage.countCalls, storage.rowReads);
      expect(
        () => callbackZone.run(() => storage.count(family.persistedName)),
        throwsStateError,
      );
      expect(
        () => callbackZone.run(
          () => storage.read(family.persistedName, limit: 1),
        ),
        throwsStateError,
      );
      expect((storage.countCalls, storage.rowReads), reads);
      hold.complete();
      await rowWork;
      await rejected;
      expect(storage.committedRows[family.persistedName], isEmpty);
    },
  );

  test(
    'parallel read retains committed snapshot across atomic write',
    () async {
      final hold = storage.holdPut = Completer<void>();
      final entered = Completer<void>();
      final writing = storage.writeTransaction((tx) async {
        entered.complete();
        await tx.put(family, first);
        await tx.put(WorkspaceCollection.receipts, second);
      });
      await entered.future;
      final readEntered = Completer<void>();
      final releaseRead = Completer<void>();
      final reading = storage.readTransaction(() async {
        expect(await storage.count(family.persistedName), 0);
        readEntered.complete();
        await releaseRead.future;
        expect(await storage.count(family.persistedName), 0);
        expect(
          await storage.count(WorkspaceCollection.receipts.persistedName),
          0,
        );
      });
      await readEntered.future;
      hold.complete();
      await writing;
      releaseRead.complete();
      await reading;
      await storage.readTransaction(() async {
        expect(await storage.count(family.persistedName), 1);
        expect(
          await storage.count(WorkspaceCollection.receipts.persistedName),
          1,
        );
      });
    },
  );

  test(
    'active write scope rejects a different concurrent read context',
    () async {
      late WorkspaceWriteTransaction escaped;
      final entered = Completer<void>();
      final releaseWrite = Completer<void>();
      final writing = storage.writeTransaction((tx) async {
        escaped = tx;
        await tx.put(family, first);
        entered.complete();
        await releaseWrite.future;
      });
      final rejected = expectLater(writing, throwsStateError);
      await entered.future;
      await storage.readTransaction(() async {
        expect(await storage.count(family.persistedName), 0);
        await expectLater(
          escaped.get(family, first.nativeId),
          throwsStateError,
        );
      });
      releaseWrite.complete();
      await rejected;
      expect(storage.committedRows[family.persistedName], isEmpty);
    },
  );

  test(
    'unawaited late failing public read aborts without uncaught errors',
    () async {
      final hold = storage.holdRead = Completer<void>();
      storage.nextReadFailure = StateError('SYNTHETIC_READ_FAILURE');
      final uncaught = <Object>[];
      await runZonedGuarded<Future<void>>(() async {
        final callbackSettled = Completer<void>();
        final reading = storage.readTransaction(() async {
          unawaited(storage.read(family.persistedName, limit: 1));
          callbackSettled.complete();
        });
        final rejected = expectLater(reading, throwsStateError);
        await callbackSettled.future;
        await Future<void>.delayed(Duration.zero);
        hold.complete();
        await rejected;
        await Future<void>.delayed(Duration.zero);
      }, (error, _) => uncaught.add(error))!;
      expect(uncaught, isEmpty);
      expect(storage.committedRows[family.persistedName], isEmpty);
    },
  );

  test(
    'close seals admission and waits for physical row work exactly once',
    () async {
      final hold = storage.holdPut = Completer<void>();
      final entered = Completer<void>();
      final writing = storage.writeTransaction((tx) async {
        entered.complete();
        await tx.put(family, first);
      });
      await entered.future;
      final close = storage.close();
      expect(storage.close(), same(close));
      expect(storage.closeCalls, 0);
      await expectLater(
        storage.writeTransaction((_) async => fail('sealed')),
        throwsStateError,
      );
      await expectLater(
        storage.readTransaction(() async => fail('sealed')),
        throwsStateError,
      );
      hold.complete();
      await writing;
      expect(await close, isTrue);
      expect(storage.closeCalls, 1);
    },
  );

  test(
    'negative close stays negative without a second backend close',
    () async {
      storage.closeResult = false;
      expect(await storage.close(), isFalse);
      expect(await storage.close(), isFalse);
      expect(storage.closeCalls, 1);
    },
  );

  test('close exception stays memoized, no false drain or retry', () async {
    final failure = storage.closeFailure = StateError('STORAGE_BLOCKED');
    final closing = storage.close();
    await expectLater(closing, throwsA(same(failure)));
    expect(storage.close(), same(closing));
    expect(storage.closeCalls, 1);
    // tearDown must not retry the failed close; it observes the same failure.
    await expectLater(storage.close(), throwsA(same(failure)));
  });

  test(
    'capacity candidate preserves error, requires domain readback elsewhere',
    () async {
      final failure = storage.nextPutFailure = MemoryCapacityFailure();
      await expectLater(
        storage.writeTransaction((tx) async {
          await tx.put(family, first);
        }),
        throwsA(same(failure)),
      );
      expect(storage.isCapacityFailure(failure), isTrue);
      expect(
        storage.isCapacityFailure(StateError('The database is full.')),
        isFalse,
      );
      expect(storage.committedRows[family.persistedName], isEmpty);
    },
  );

  test(
    'read bounds and foreign collection reject without a backend read',
    () async {
      for (final limit in [0, 51252]) {
        await expectLater(
          storage.readTransaction(() async {
            await storage.read(family.persistedName, limit: limit);
          }),
          throwsStateError,
        );
      }
      await expectLater(
        storage.readTransaction(() async {
          await storage.count('foreign');
        }),
        throwsStateError,
      );
      expect(() => storage.count(family.persistedName), throwsStateError);
    },
  );
}
