import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/runtime/runtime_coordinator.dart';

import 'fakes.dart';

void main() {
  test(
    'store error blocks operations and explicit retry opens same owner',
    () async {
      final platform = FakePlatform();
      final store = FakeStore()..failOpen = true;
      final runtime = RuntimeCoordinator(
        platform: platform,
        store: store,
        epoch: 'owner',
      );
      addTearDown(runtime.dispose);
      addTearDown(platform.controller.close);
      await runtime.start();
      expect(runtime.state, RuntimeState.storageBlocked);
      expect(runtime.acceptsOperations, isFalse);
      expect(runtime.error, isNotNull);
      store.failOpen = false;
      await runtime.retryOpen();
      expect(runtime.state, RuntimeState.running);
      expect(store.opens, 2);
    },
  );
}
