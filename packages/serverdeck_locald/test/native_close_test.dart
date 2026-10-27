import 'package:serverdeck_locald/storage/native_close.dart';
import 'package:test/test.dart';

import 'state_store_test.dart' show registerRepositoryTest;

void main() {
  registerRepositoryTest(mode: 'open-close-failure');
  test(
    'failed-open native close needs affirmative completion, not false/error',
    () async {
      expect(await confirmNativeClose(() async => true), true);
      expect(await confirmNativeClose(() async => false), false);
      expect(
        await confirmNativeClose(
          () async => throw StateError('synthetic-close-failure'),
        ),
        false,
      );
    },
  );
}
