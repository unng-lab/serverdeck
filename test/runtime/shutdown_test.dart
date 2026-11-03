import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/runtime/runtime_coordinator.dart';

import 'fakes.dart';

void main() {
  for (final failure in ['writes', 'store', 'activation', 'exit']) {
    test(
      'failure at $failure keeps admission closed and retries unfinished resources',
      () async {
        final platform = FakePlatform()
          ..failActivation = failure == 'activation'
          ..failExit = failure == 'exit';
        final store = FakeStore()
          ..failWrites = failure == 'writes'
          ..failClose = failure == 'store';
        final capability = FakeCapability();
        final runtime = RuntimeCoordinator(
          platform: platform,
          store: store,
          epoch: 'owner',
        )..register(capability);
        addTearDown(runtime.dispose);
        addTearDown(platform.controller.close);
        await runtime.start();
        await runtime.requestExit();
        expect(runtime.state, RuntimeState.shutdownBlocked);
        expect(runtime.acceptsOperations, isFalse);
        expect(platform.exited, isFalse);
        store
          ..failWrites = false
          ..failClose = false;
        platform
          ..failActivation = false
          ..failExit = false;
        await runtime.requestExit();
        expect(runtime.state, RuntimeState.terminated);
        expect(store.closes, failure == 'store' ? 2 : 1);
        expect(capability.calls.where((c) => c == 'dispose').length, 1);
      },
    );
  }
  test(
    'exit latch retained in startup snapshot does not open a new store',
    () async {
      final platform = FakePlatform()
        ..exitLatch = true
        ..seq = 40;
      final store = FakeStore();
      final runtime = RuntimeCoordinator(
        platform: platform,
        store: store,
        epoch: 'owner',
      );
      addTearDown(runtime.dispose);
      addTearDown(platform.controller.close);
      await runtime.start();
      expect(runtime.state, RuntimeState.terminated);
      expect(store.opens, 0);
    },
  );
  for (final failure in ['stop', 'cancel', 'sessions', 'drain', 'dispose']) {
    test(
      'failure in first owner $failure does not skip independent owner cleanup',
      () async {
        final platform = FakePlatform();
        final store = FakeStore();
        final first = FakeCapability(id: 'first')..failure = failure;
        final second = FakeCapability(id: 'second');
        final runtime =
            RuntimeCoordinator(platform: platform, store: store, epoch: 'owner')
              ..register(first)
              ..register(second);
        addTearDown(runtime.dispose);
        addTearDown(platform.controller.close);
        await runtime.start();
        await runtime.requestExit();
        expect(runtime.state, RuntimeState.shutdownBlocked);
        expect(store.closed, isFalse);
        expect(
          second.calls,
          containsAll(['stop', 'cancel', 'sessions', 'drain']),
        );
        final completed = List.of(second.calls);
        first.failure = null;
        await runtime.requestExit();
        expect(runtime.state, RuntimeState.terminated);
        for (final stage in completed) {
          expect(second.calls.where((c) => c == stage).length, 1);
        }
      },
    );
  }
  test(
    'timeout stopping one owner still cancels and closes other sessions',
    () async {
      final platform = FakePlatform();
      final store = FakeStore();
      final first = FakeCapability(id: 'first')
        ..pendingStage = 'stop'
        ..pending = Completer<void>();
      final second = FakeCapability(id: 'second');
      final runtime =
          RuntimeCoordinator(
              platform: platform,
              store: store,
              epoch: 'owner',
              shutdownTimeout: const Duration(milliseconds: 10),
            )
            ..register(first)
            ..register(second);
      addTearDown(runtime.dispose);
      addTearDown(platform.controller.close);
      await runtime.start();
      await runtime.requestExit();
      expect(runtime.state, RuntimeState.shutdownBlocked);
      expect(
        second.calls,
        containsAll(['stop', 'cancel', 'sessions', 'drain']),
      );
      expect(store.closed, isFalse);
      first.pending!.complete();
      await settleEvents();
      await runtime.requestExit();
      expect(runtime.state, RuntimeState.terminated);
      expect(first.calls.where((c) => c == 'stop').length, 1);
    },
  );
  test(
    'exit closes admission immediately, waits accepted write and runs once',
    () async {
      final platform = FakePlatform();
      final store = FakeStore()..write = Completer<void>();
      final capability = FakeCapability();
      final runtime = RuntimeCoordinator(
        platform: platform,
        store: store,
        epoch: 'owner',
      )..register(capability);
      addTearDown(runtime.dispose);
      addTearDown(platform.controller.close);
      await runtime.start();
      final exit = runtime.requestExit();
      expect(store.admitted, isFalse);
      expect(runtime.acceptsOperations, isFalse);
      final second = runtime.requestExit();
      await settleEvents();
      expect(store.closed, isFalse);
      expect(platform.exited, isFalse);
      store.write!.complete();
      await Future.wait([exit, second]);
      expect(runtime.state, RuntimeState.terminated);
      expect(store.closes, 1);
      expect(capability.calls, [
        'stop',
        'cancel',
        'sessions',
        'drain',
        'dispose',
      ]);
      expect(platform.activationClosed, isTrue);
    },
  );
  for (final stage in ['stop', 'cancel', 'sessions', 'drain', 'dispose']) {
    test('failure at $stage retries only unfinished stages', () async {
      final platform = FakePlatform();
      final store = FakeStore();
      final capability = FakeCapability()..failure = stage;
      final runtime = RuntimeCoordinator(
        platform: platform,
        store: store,
        epoch: 'owner',
      )..register(capability);
      addTearDown(runtime.dispose);
      addTearDown(platform.controller.close);
      await runtime.start();
      await runtime.requestExit();
      expect(runtime.state, RuntimeState.shutdownBlocked);
      expect(runtime.acceptsOperations, isFalse);
      expect(store.closed, isFalse);
      expect(platform.visible, isTrue);
      final calls = List.of(capability.calls);
      capability.failure = null;
      await runtime.requestExit();
      expect(runtime.state, RuntimeState.terminated);
      for (final completed in calls.where((c) => c != stage)) {
        expect(capability.calls.where((c) => c == completed).length, 1);
      }
      expect(capability.calls.where((c) => c == stage).length, 2);
    });
  }
  test('deadline keeps store open; late drain does not continue exit without retry', () async {
    final platform = FakePlatform();
    final store = FakeStore();
    final capability = FakeCapability()..pending = Completer<void>();
    final runtime = RuntimeCoordinator(
      platform: platform,
      store: store,
      epoch: 'owner',
      shutdownTimeout: const Duration(milliseconds: 10),
    )..register(capability);
    addTearDown(runtime.dispose);
    addTearDown(platform.controller.close);
    await runtime.start();
    await runtime.requestExit();
    expect(runtime.state, RuntimeState.shutdownBlocked);
    capability.pending!.complete();
    await settleEvents();
    expect(store.closed, isFalse);
    expect(platform.exited, isFalse);
    await runtime.requestExit();
    expect(runtime.state, RuntimeState.terminated);
    expect(capability.calls.where((c) => c == 'drain').length, 1);
  });
  test('open in flight cannot reopen admission after exit', () async {
    final platform = FakePlatform();
    final store = FakeStore()..opening = Completer<void>();
    final runtime = RuntimeCoordinator(
      platform: platform,
      store: store,
      epoch: 'owner',
    );
    addTearDown(runtime.dispose);
    addTearDown(platform.controller.close);
    final startup = runtime.start();
    await settleEvents();
    final exit = runtime.requestExit();
    store.opening!.complete();
    await Future.wait([startup, exit]);
    expect(store.admitted, isFalse);
    expect(store.closed, isTrue);
  });
}
