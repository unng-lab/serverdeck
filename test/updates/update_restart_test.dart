import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/runtime/runtime_coordinator.dart';
import 'package:serverdeck/runtime/runtime_view.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_components.dart';
import 'package:serverdeck/updates/update_owner.dart';
import 'package:serverdeck/updates/update_view.dart';

import '../runtime/fakes.dart';

class Port implements UpdatePort {
  UpdateSnapshot value = const UpdateSnapshot(
    currentVersion: '0.1.0+3',
    enabled: false,
    state: UpdateState.idle,
    preparedVersion: '0.1.0+4',
  );
  bool readFails = false;
  @override
  Future<UpdateSnapshot> snapshot() async {
    if (readFails) throw StateError('read');
    return value;
  }

  @override
  Future<bool> check() async => true;
  @override
  Future<bool> download(String version) async => true;
  @override
  Future<void> cancel() async {}
  @override
  Future<void> defer() async {}
  @override
  Future<void> setEnabled(bool enabled) async {}
}

void main() {
  test('retained prepared survives failed replacement, but not prepared/read errors or stop', () async {
    final port = Port();
    final owner = UpdateOwner(port: port, currentVersion: '0.1.0+3');
    addTearDown(owner.dispose);
    for (final code in ['NETWORK_UNAVAILABLE', 'CANCELLED']) {
      port.value = UpdateSnapshot(
        currentVersion: '0.1.0+3',
        enabled: false,
        state: UpdateState.failed,
        code: code,
        preparedVersion: '0.1.0+4',
      );
      await owner.start();
      await owner.refresh();
      expect(owner.canRestart, isTrue);
    }
    port.value = const UpdateSnapshot(
      currentVersion: '0.1.0+3',
      enabled: false,
      state: UpdateState.failed,
      preparedVersion: '0.1.0+4',
      preparedCode: 'RELEASE_REVOKED',
    );
    await owner.refresh();
    expect(owner.canRestart, isFalse);
    port.value = const UpdateSnapshot(
      currentVersion: '0.1.0+3',
      enabled: false,
      state: UpdateState.checking,
      preparedVersion: '0.1.0+4',
    );
    await owner.refresh();
    expect(owner.canRestart, isFalse);
    port.readFails = true;
    await owner.refresh();
    expect(owner.canRestart, isFalse);
    port.readFails = false;
    await owner.refresh();
    await owner.stopAdmission();
    expect(owner.canRestart, isFalse);
  });
  test('rejected restart leaves runtime operating; accepted uses complete cleanup and retry', () async {
    final platform = FakePlatform()..acceptRestart = false;
    final store = FakeStore();
    final capability = FakeCapability();
    final runtime = RuntimeCoordinator(
      platform: platform,
      store: store,
      epoch: 'owner',
    );
    runtime.register(capability);
    addTearDown(runtime.dispose);
    addTearDown(platform.controller.close);
    await runtime.start();
    expect(await runtime.requestUpdateRestart('0.1.0+4'), isFalse);
    expect(runtime.acceptsOperations, isTrue);
    expect(store.closed, isFalse);
    platform.acceptRestart = true;
    store.failWrites = true;
    expect(await runtime.requestUpdateRestart('0.1.0+4'), isTrue);
    expect(runtime.state, RuntimeState.shutdownBlocked);
    expect(platform.exits, 0);
    expect(
      capability.calls,
      containsAll(['stop', 'cancel', 'sessions', 'drain']),
    );
    store.failWrites = false;
    await runtime.requestExit();
    expect(store.closed, isTrue);
    expect(platform.activationClosed, isTrue);
    expect(platform.exits, 1);
    expect(platform.restartRequests, 2);
  });
  test(
    'concurrent restart requests share one acceptance and shutdown',
    () async {
      final platform = FakePlatform(), store = FakeStore();
      store.write = Completer<void>();
      final runtime = RuntimeCoordinator(
        platform: platform,
        store: store,
        epoch: 'owner',
      );
      addTearDown(runtime.dispose);
      addTearDown(platform.controller.close);
      await runtime.start();
      final a = runtime.requestUpdateRestart('0.1.0+4');
      final b = runtime.requestUpdateRestart('0.1.0+4');
      await Future<void>.delayed(Duration.zero);
      expect(platform.restartRequests, 1);
      expect(platform.exits, 0);
      store.write!.complete();
      expect(await a, isTrue);
      expect(await b, isTrue);
      expect(platform.exits, 1);
    },
  );
  test('lost restart event is reconciled before shutdown retry', () async {
    final platform = FakePlatform(), store = FakeStore();
    final runtime = RuntimeCoordinator(
      platform: platform,
      store: store,
      epoch: 'owner',
    );
    addTearDown(runtime.dispose);
    addTearDown(platform.controller.close);
    await runtime.start();
    store.failWrites = true;
    platform.exitLatch = true;
    platform.restartIntent = true;
    platform.emit('activationRequested', sequence: 3);
    await Future<void>.delayed(Duration.zero);
    expect(runtime.state, RuntimeState.shutdownBlocked);
    expect(runtime.updateRestartRequested, isTrue);
    expect(platform.exits, 0);
    platform.restartIntent = false;
    platform.emit('trayExit');
    await Future<void>.delayed(Duration.zero);
    expect(runtime.updateRestartRequested, isFalse);
  });
  testWidgets(
    'main entry opens updates directly, preserves version, retires on shutdown',
    (tester) async {
      final platform = FakePlatform()..release.value = '0.1.0+3';
      final store = FakeStore();
      final runtime = RuntimeCoordinator(
        platform: platform,
        store: store,
        epoch: 'owner',
      );
      final owner = UpdateOwner(port: Port(), currentVersion: '0.1.0+3');
      addTearDown(owner.dispose);
      addTearDown(runtime.dispose);
      addTearDown(platform.controller.close);
      await runtime.start();
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.light,
          home: RuntimeView(runtime: runtime, updates: owner),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Приложение готово'), findsNothing);
      expect(find.text('0.1.0+3'), findsOneWidget);
      await tester.tap(find.text('Обновление готово'));
      await tester.pumpAndSettle();
      expect(find.byType(UpdateView), findsOneWidget);
      await tester.ensureVisible(find.text('Обновить и перезапустить'));
      await tester.tap(find.text('Обновить и перезапустить'));
      await tester.pumpAndSettle();
      expect(find.text('Обновить до 0.1.0+4 и перезапустить?'), findsOneWidget);
      store.failWrites = true;
      final exit = runtime.requestExit();
      await tester.pumpAndSettle();
      await exit;
      await tester.pumpAndSettle();
      expect(find.byType(UpdateView), findsNothing);
      expect(platform.restartRequests, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'restart confirmation cancel, stale prepared version, and accepted callback',
    (tester) async {
      final port = Port();
      final owner = UpdateOwner(port: port, currentVersion: '0.1.0+3');
      addTearDown(owner.dispose);
      await owner.start();
      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.light,
          home: Scaffold(
            body: UpdateView(
              owner: owner,
              onRestart: (version) async {
                calls.add(version);
                return true;
              },
            ),
          ),
        ),
      );
      Future<void> open() async {
        await tester.ensureVisible(find.text('Обновить и перезапустить').first);
        await tester.tap(find.text('Обновить и перезапустить').first);
        await tester.pumpAndSettle();
      }

      await open();
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await open();
      port.value = const UpdateSnapshot(
        currentVersion: '0.1.0+3',
        enabled: false,
        state: UpdateState.idle,
        preparedVersion: '0.1.0+5',
      );
      await owner.refresh();
      await tester.pump();
      await tester.tap(
        find.widgetWithText(DeckButton, 'Обновить и перезапустить').last,
      );
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await open();
      await tester.tap(
        find.widgetWithText(DeckButton, 'Обновить и перезапустить').last,
      );
      await tester.pumpAndSettle();
      expect(calls, ['0.1.0+5']);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
