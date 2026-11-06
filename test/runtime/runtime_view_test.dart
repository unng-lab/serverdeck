import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/app.dart';
import 'package:serverdeck/runtime/runtime_coordinator.dart';
import 'package:serverdeck/runtime/native_platform.dart';

import 'fakes.dart';

void main() {
  testWidgets(
    'native release becomes visible before a delayed store finishes opening',
    (tester) async {
      const channel = MethodChannel('serverdeck/pending-open-version-unit');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'runtime.snapshot') {
              return {
                'ownerEpoch': 'owner',
                'seq': 0,
                'windowState': 'visible',
                'trayAvailable': true,
                'osEnding': false,
              };
            }
            expect(call.method, 'initialize');
            return {
              'ownerEpoch': 'owner',
              'dataRoot': 'synthetic-data',
              'runtimeRoot': 'synthetic-runtime',
              'exePath': 'synthetic-program',
              'userSid': 'synthetic-user',
              'logonSid': 'synthetic-logon',
              'release': '3.2.987',
            };
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final platform = NativePlatform(epoch: 'owner', channel: channel);
      final opening = Completer<void>();
      final store = FakeStore()..opening = opening;
      final runtime = RuntimeCoordinator(
        platform: platform,
        store: store,
        epoch: 'owner',
      );
      addTearDown(runtime.dispose);
      await tester.pumpWidget(ServerDeckApp(runtime: runtime, store: store));
      expect(find.text('Не определена'), findsOneWidget);
      final started = runtime.start();
      await tester.pump();
      expect(store.opens, 1);
      expect(runtime.state, RuntimeState.starting);
      await platform.initialize();
      await tester.pump();
      expect(find.text('3.2.987'), findsOneWidget);
      expect(find.text('Не определена'), findsNothing);
      expect(runtime.state, RuntimeState.starting);
      expect(opening.isCompleted, isFalse);
      expect(calls.where((m) => m == 'initialize'), hasLength(1));
      opening.complete();
      await started;
      await tester.pumpAndSettle();
      expect(store.opens, 1);
    },
  );
  testWidgets('storage error and retry expose actual owner readiness', (
    tester,
  ) async {
    final platform = FakePlatform()..release.value = '7.6.4325';
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
    expect(find.text('Версия ServerDeck'), findsOneWidget);
    expect(find.text('7.6.4325'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
    store.failOpen = false;
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(runtime.acceptsOperations, isTrue);
    expect(runtime.acceptsOperations, isTrue);
    expect(find.text('Приложение готово'), findsNothing);
    expect(find.text('7.6.4325'), findsOneWidget);
    expect(store.opens, 2);
  });
  testWidgets(
    'unknown release becomes the full running version without extra opens',
    (tester) async {
      final platform = FakePlatform()..release.value = null;
      final store = FakeStore();
      final runtime = RuntimeCoordinator(
        platform: platform,
        store: store,
        epoch: 'owner',
      );
      addTearDown(runtime.dispose);
      addTearDown(platform.controller.close);
      await tester.pumpWidget(ServerDeckApp(runtime: runtime, store: store));
      expect(find.text('Не определена'), findsOneWidget);
      expect(store.opens, 0);
      platform.release.value = '3.2.987';
      await runtime.start();
      await tester.pumpAndSettle();
      expect(find.text('3.2.987'), findsOneWidget);
      expect(find.text('Не определена'), findsNothing);
      expect(store.opens, 1);
      await tester.pumpWidget(ServerDeckApp(runtime: runtime, store: store));
      expect(store.opens, 1);
    },
  );
  testWidgets('runtime rebinding retires the previous version projection', (
    tester,
  ) async {
    final first = FakePlatform()..release.value = '1.2.6';
    final second = FakePlatform()..release.value = '5.6.14';
    final firstStore = FakeStore(), secondStore = FakeStore();
    final firstRuntime = RuntimeCoordinator(
      platform: first,
      store: firstStore,
      epoch: 'owner',
    );
    final secondRuntime = RuntimeCoordinator(
      platform: second,
      store: secondStore,
      epoch: 'owner',
    );
    addTearDown(firstRuntime.dispose);
    addTearDown(secondRuntime.dispose);
    addTearDown(first.controller.close);
    addTearDown(second.controller.close);
    await firstRuntime.start();
    await secondRuntime.start();
    await tester.pumpWidget(
      ServerDeckApp(runtime: firstRuntime, store: firstStore),
    );
    expect(find.text('1.2.6'), findsOneWidget);
    await tester.pumpWidget(
      ServerDeckApp(runtime: secondRuntime, store: secondStore),
    );
    expect(find.text('5.6.14'), findsOneWidget);
    expect(find.text('1.2.6'), findsNothing);
    first.release.value = '9.9.17';
    await tester.pump();
    expect(find.text('5.6.14'), findsOneWidget);
    expect(find.text('9.9.17'), findsNothing);
    expect(firstStore.opens, 1);
    expect(secondStore.opens, 1);
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
