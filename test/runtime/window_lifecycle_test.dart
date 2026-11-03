import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:serverdeck/runtime/runtime_coordinator.dart';
import 'package:serverdeck/runtime/native_platform.dart';

import 'fakes.dart';

void main() {
  test('duplicate and gapped events cannot undo a newer native snapshot', () async {
    final platform = FakePlatform();
    final runtime = RuntimeCoordinator(
      platform: platform,
      store: FakeStore(),
      epoch: 'owner',
    );
    addTearDown(runtime.dispose);
    addTearDown(platform.controller.close);
    await runtime.start();
    platform.emit('closeRequested', sequence: 1);
    await settleEvents();
    platform.emit('trayOpen', sequence: 1);
    await settleEvents();
    expect(platform.visible, isFalse);
    platform.emit('closeRequested', sequence: 3);
    // A later restore has already happened natively before snapshot is queried.
    platform
      ..visible = true
      ..seq = 4;
    await settleEvents();
    expect(runtime.window, WindowState.visible);
    expect(platform.visible, isTrue);
    platform.emit('closeRequested', sequence: 2);
    await settleEvents();
    expect(platform.visible, isTrue);
  });
  test('close and restore retain synthetic capability and store', () async {
    final platform = FakePlatform();
    final store = FakeStore();
    final draft = TextEditingController(text: 'Несохранённый черновик');
    addTearDown(draft.dispose);
    final capability = FakeCapability(onDispose: draft.dispose);
    final runtime = RuntimeCoordinator(
      platform: platform,
      store: store,
      epoch: 'owner',
    )..register(capability);
    addTearDown(runtime.dispose);
    addTearDown(platform.controller.close);
    await runtime.start();
    platform.emit('closeRequested');
    await settleEvents();
    expect(platform.visible, isFalse);
    expect(store.admitted, isTrue);
    expect(capability.calls, isEmpty);
    expect(draft.text, 'Несохранённый черновик');
    platform.emit('trayOpen');
    await settleEvents();
    expect(platform.visible, isTrue);
    expect(store.opens, 1);
    expect(capability.calls, isEmpty);
    draft.text = 'Изменён после восстановления';
    expect(draft.text, 'Изменён после восстановления');
  });
  test(
    'tray failure prevents hiding and stale epoch cannot close owner',
    () async {
      final platform = FakePlatform()..tray = false;
      final runtime = RuntimeCoordinator(
        platform: platform,
        store: FakeStore(),
        epoch: 'owner',
      );
      addTearDown(runtime.dispose);
      addTearDown(platform.controller.close);
      await runtime.start();
      platform.emit('closeRequested');
      await settleEvents();
      expect(platform.visible, isTrue);
      platform.emit('trayExit', epoch: 'old-owner');
      await settleEvents();
      expect(runtime.state, RuntimeState.running);
      platform.tray = true;
      await runtime.retryTray();
      expect(runtime.trayAvailable, isTrue);
    },
  );
}
