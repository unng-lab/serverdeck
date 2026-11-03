import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/app.dart';
import 'package:serverdeck/runtime/runtime_coordinator.dart';

import 'fakes.dart';

void main() {
  testWidgets('storage error and retry expose actual owner readiness', (
    tester,
  ) async {
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
    await tester.pumpWidget(ServerDeckApp(runtime: runtime, store: store));
    expect(find.text('Данные недоступны'), findsWidgets);
    expect(find.text('Повторить'), findsOneWidget);
    store.failOpen = false;
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(runtime.acceptsOperations, isTrue);
    expect(find.text('Приложение готово'), findsOneWidget);
    expect(store.opens, 2);
  });
  testWidgets(
    'tray failure keeps recovery action and explicit reason available',
    (tester) async {
      final platform = FakePlatform()..tray = false;
      final store = FakeStore();
      final runtime = RuntimeCoordinator(
        platform: platform,
        store: store,
        epoch: 'owner',
      );
      addTearDown(runtime.dispose);
      addTearDown(platform.controller.close);
      await runtime.start();
      await tester.pumpWidget(ServerDeckApp(runtime: runtime, store: store));
      expect(find.text('Значок трея недоступен'), findsOneWidget);
      platform.tray = true;
      await tester.tap(find.text('Повторить создание значка'));
      await tester.pumpAndSettle();
      expect(runtime.trayAvailable, isTrue);
      expect(find.text('Значок трея недоступен'), findsNothing);
    },
  );
}
