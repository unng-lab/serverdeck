import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/main.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck_protocol/models.dart';

import '../contract/profile_controller_test.dart' as fixtures;

void main() {
  testWidgets(
    'real app projects service profiles, target and settings without secret input',
    (tester) async {
      final client = fixtures.ModelClient();
      final bootstrap = fixtures.ModelBootstrap(client)
        ..show(ReadinessState.ready);
      await tester.pumpWidget(FoundationApp(bootstrap: bootstrap));
      expect(find.text('Загрузка локальных профилей'), findsOneWidget);
      expect(find.text('Локальных профилей пока нет'), findsNothing);
      client.events.add(fixtures.snapshot());
      await tester.pumpAndSettle();
      expect(find.text('Saved profile'), findsOneWidget);
      expect(
        find.text('Saved profile · 192.0.2.1:22\nНе подключён'),
        findsOneWidget,
      );
      await tester.tap(find.text('Saved profile'));
      await tester.pumpAndSettle();
      expect(find.text('Пользователь SSH: admin'), findsOneWidget);
      expect(
        find.text('Секрет доступа сохранён; содержимое не отображается'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      final context = tester.element(find.text('Saved profile'));
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(MediaQuery.disableAnimationsOf(context), isTrue);
      client.readErrors.add(ErrorCode.timeout);
      await tester.pumpAndSettle();
      expect(find.text('Локальная служба не ответила вовремя'), findsOneWidget);
      expect(find.textContaining('Saved profile'), findsNothing);
      var before = client.refreshes;
      await tester.tap(find.text('Повторить чтение'));
      await tester.pump();
      expect(client.refreshes, before + 1);
      client.events.add(fixtures.snapshot());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Открыть меню навигации'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Настройки'));
      await tester.pumpAndSettle();
      expect(find.text('Тема: тёмная'), findsOneWidget);
      expect(find.text('Уменьшение анимации: включено'), findsOneWidget);
      client.readErrors.add(ErrorCode.internal);
      await tester.pumpAndSettle();
      expect(find.text('Ошибка локальной службы'), findsOneWidget);
      expect(find.text('Тема: тёмная'), findsNothing);
      before = client.refreshes;
      await tester.tap(find.text('Повторить чтение'));
      await tester.pump();
      expect(client.refreshes, before + 1);
      client.events.add(fixtures.snapshot());
      await tester.pumpAndSettle();
      expect(find.text('Тема: тёмная'), findsOneWidget);
      bootstrap.show(ReadinessState.unavailable);
      await tester.pumpAndSettle();
      expect(find.textContaining('Saved profile'), findsNothing);
      expect(find.textContaining('192.0.2.1'), findsNothing);
      expect(find.text('Локальная служба недоступна'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await client.events.close();
    },
  );

  for (final dark in [false, true]) {
    for (final size in const [
      Size(1100, 760),
      Size(800, 600),
      Size(360, 800),
      Size(390, 800),
    ]) {
      testWidgets(
        'profile/target with maximum text can scroll $size dark=$dark',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final client = fixtures.ModelClient();
          final bootstrap = fixtures.ModelBootstrap(client)
            ..show(ReadinessState.ready);
          await tester.pumpWidget(FoundationApp(bootstrap: bootstrap));
          final source = fixtures.snapshot();
          final raw = Map<String, Object?>.from(
            (source.profiles.result['profiles'] as List).single as Map,
          );
          raw['name'] = 'Я' * 128;
          raw['address'] = List.filled(4, 'a' * 62).join('.');
          raw['sshUser'] = 'u' * 64;
          raw['tags'] = List.generate(16, (i) => '$i${'t' * 60}');
          final settings = Map<String, Object?>.from(
            source.settings.result['settings'] as Map,
          );
          settings['theme'] = dark ? 'dark' : 'light';
          client.events.add(
            ClientSnapshot(
              ApiReply(fixtures.fixtureGeneration, {
                'storeRevision': '1',
                'profiles': [raw],
              }),
              ApiReply(fixtures.fixtureGeneration, {
                'storeRevision': '1',
                'settings': settings,
              }),
            ),
          );
          await tester.pumpAndSettle();
          final context = tester.element(find.text(raw['name'] as String));
          // Root builder retains the OS scaler; here exercise Windows 200%.
          final media = MediaQuery.of(context);
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpAndSettle();
          expect(media.size.width, size.width);
          await tester.ensureVisible(find.text(raw['name'] as String));
          await tester.tap(find.text(raw['name'] as String));
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.text('Подключение к серверу пока недоступно'),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await client.events.close();
        },
      );
    }
  }
}
