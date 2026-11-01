import 'package:serverdeck_engine/storage/state_store.dart';
import 'package:test/test.dart';

import 'actual_state_store_test.dart' as actual;

void main() {
  // This unit file deliberately leaves the process-wide reservation retained.
  // No reset/force-release is introduced into StateStore for subsequent tests.
  test('throwing open without attributable handle retains actual store reservation', () async {
    final setup = await actual.Setup.create();
    setup.provider.openFailure = StateError('SYNTHETIC_OWNERSHIP_UNCERTAIN');
    setup.provider.openFailureUncertain = true;
    final before = List<int>.of(setup.source.files.data[setup.database]!);
    await expectLater(setup.open(), actual.failure('STORAGE_BLOCKED'));
    expect(setup.provider.lastOpened, isNull);
    expect(setup.provider.hasOpenInstance, isFalse);
    expect(setup.provider.cleanups, 1);
    expect(StateStore.hasOpenReservation, isTrue);
    setup.provider.openFailure = null;
    await expectLater(setup.open(), actual.failure('STORAGE_BLOCKED'));
    expect(setup.runtime.initializes, 1);
    expect(setup.provider.preflights, 1);
    expect(setup.provider.cleanups, 1);
    expect(setup.source.files.data[setup.database], before);
    expect(setup.source.lease.isHeld, isTrue);
    expect(setup.source.lease.closes, 0);
    expect(
      setup.source.custody.receiptDigestSync(setup.source.key, {
        'purpose': 'unit-custody-still-live',
      }),
      isNotEmpty,
    );
  });
}
