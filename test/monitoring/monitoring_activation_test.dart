import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/runtime/native_platform.dart';
import 'package:serverdeck/runtime/runtime_coordinator.dart';
import 'package:serverdeck/runtime/runtime_view.dart';
import 'package:serverdeck/theme/brand_theme.dart';

import '../fixtures/monitoring_harness.dart';
import '../runtime/fakes.dart';

void main() {
  testWidgets(
    'runtime binds monitoring only to servers and visible/tray state',
    (tester) async {
      final h = MonitoringHarness();
      addTearDown(h.dispose);
      h.add(1, connected: true);
      final platform = FakePlatform(), store = FakeStore();
      final runtime = RuntimeCoordinator(
        platform: platform,
        store: store,
        epoch: 'owner',
      );
      addTearDown(runtime.dispose);
      addTearDown(platform.controller.close);
      await runtime.start();
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.dark,
          home: RuntimeView(runtime: runtime, monitoring: h.owner),
        ),
      );
      await tester.pumpAndSettle();
      expect(h.owner.active, isTrue);
      await tester.tap(
        find.byKey(const ValueKey('foundation-navigation-settings')),
      );
      await tester.pumpAndSettle();
      expect(h.owner.active, isFalse);
      await tester.tap(
        find.byKey(const ValueKey('foundation-navigation-servers')),
      );
      await tester.pumpAndSettle();
      expect(h.owner.active, isTrue);
      platform.emit('closeRequested');
      await tester.pumpAndSettle();
      expect(runtime.window, WindowState.trayHidden);
      expect(h.owner.active, isFalse);
      final count = h.port.collected.length;
      h.clock.advance(const Duration(seconds: 10));
      await tester.pump();
      expect(h.port.collected, hasLength(count));
      platform.emit('trayOpen');
      await tester.pumpAndSettle();
      expect(h.owner.active, isTrue);
      runtime.window = WindowState.minimized;
      runtime.notifyListeners();
      await tester.pump();
      expect(h.owner.active, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(h.owner.active, isFalse);
    },
  );
  testWidgets(
    'storage-blocked runtime cannot start automatic connections until retry',
    (tester) async {
      final h = MonitoringHarness();
      addTearDown(h.dispose);
      h.add(1);
      final platform = FakePlatform(), store = FakeStore()..failOpen = true;
      final runtime = RuntimeCoordinator(
        platform: platform,
        store: store,
        epoch: 'owner',
      );
      addTearDown(runtime.dispose);
      addTearDown(platform.controller.close);
      await runtime.start();
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.dark,
          home: RuntimeView(runtime: runtime, monitoring: h.owner),
        ),
      );
      await tester.pump();
      expect(h.owner.active, isFalse);
      expect(h.port.attempts, isEmpty);
      store.failOpen = false;
      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle();
      expect(h.owner.active, isTrue);
      expect(h.port.admitted, [mid(1)]);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
  testWidgets('replacing injected owner deactivates the previous owner', (
    tester,
  ) async {
    final first = MonitoringHarness(), second = MonitoringHarness();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final platform = FakePlatform(), store = FakeStore();
    final runtime = RuntimeCoordinator(
      platform: platform,
      store: store,
      epoch: 'owner',
    );
    addTearDown(runtime.dispose);
    addTearDown(platform.controller.close);
    await runtime.start();
    Widget view(MonitoringHarness h) => MaterialApp(
      theme: BrandTheme.dark,
      home: RuntimeView(runtime: runtime, monitoring: h.owner),
    );
    await tester.pumpWidget(view(first));
    await tester.pump();
    expect(first.owner.active, isTrue);
    await tester.pumpWidget(view(second));
    await tester.pump();
    expect(first.owner.active, isFalse);
    expect(second.owner.active, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(second.owner.active, isFalse);
  });
}
