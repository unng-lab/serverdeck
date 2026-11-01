import 'package:serverdeck_engine/storage/state_store.dart';
import 'package:test/test.dart';

import 'actual_state_store_test.dart' as actual;

void main() {
  // One terminal RAM case; keep unknown reservation, never add a reset escape.
  test(
    'unconfirmed close stays memoized and retains writer/key/lease ownership',
    () async {
      final setup = await actual.Setup.create();
      final store = await StateStore.open(
        files: setup.source.files,
        runtime: setup.runtime,
        lease: setup.source.lease,
        custody: setup.source.custody,
        receiptKey: setup.source.key,
        storageProvider: setup.provider,
      );
      final storage = setup.provider.lastOpened!;
      storage.closeResult = false;
      final closing = store.close();
      await expectLater(closing, actual.failure('STORAGE_BLOCKED'));
      expect(store.close(), same(closing));
      await expectLater(store.close(), actual.failure('STORAGE_BLOCKED'));
      expect(storage.closeCalls, 1);
      expect(StateStore.hasOpenReservation, isTrue);
      expect(setup.provider.hasOpenInstance, isTrue);
      expect(store.isReady, isFalse);
      await expectLater(setup.open(), actual.failure('STORAGE_BLOCKED'));
      expect(setup.provider.opens, 1);
      expect(setup.source.lease.isHeld, isTrue);
      expect(setup.source.lease.closes, 0);
      expect(
        setup.source.custody.receiptDigestSync(setup.source.key, {
          'purpose': 'unit-custody-still-live',
        }),
        isNotEmpty,
      );
    },
  );
}
