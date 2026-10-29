import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/main.dart';
import 'package:serverdeck/profiles/profile_list.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck_protocol/models.dart';

import '../contract/profile_controller_test.dart' as fixtures;

void main() {
  testWidgets(
    'real app retains profile data and privacy across adaptive settings navigation',
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
      expect(find.text('192.0.2.1:22'), findsOneWidget);
      expect(find.text('Состояние подключения не получено'), findsOneWidget);
      expect(find.text('Нет данных'), findsNWidgets(3));
      expect(find.textContaining('Не подключён'), findsNothing);
      final context = tester.element(find.text('Saved profile'));
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(MediaQuery.disableAnimationsOf(context), isTrue);
      client.readErrors.add(ErrorCode.timeout);
      await tester.pumpAndSettle();
      expect(find.text('Локальная служба не ответила вовремя'), findsWidgets);
      expect(find.textContaining('Saved profile'), findsNothing);
      var before = client.refreshes;
      await tester.ensureVisible(find.text('Повторить чтение'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Повторить чтение'));
      await tester.pump();
      expect(client.refreshes, before + 1);
      client.events.add(fixtures.snapshot());
      await tester.pumpAndSettle();
      final settings = find.byKey(
        const ValueKey('foundation-navigation-settings'),
      );
      final route = ModalRoute.of(tester.element(settings));
      await tester.ensureVisible(settings);
      await tester.pumpAndSettle();
      expect(settings.hitTestable(), findsOneWidget);
      await tester.tap(settings);
      await tester.pumpAndSettle();
      expect(ModalRoute.of(tester.element(settings)), same(route));
      expect(find.text('Тёмная'), findsOneWidget);
      expect(find.text('Включено'), findsOneWidget);
      client.readErrors.add(ErrorCode.internal);
      await tester.pumpAndSettle();
      expect(find.text('Ошибка локальной службы'), findsWidgets);
      expect(find.text('Тёмная'), findsNothing);
      before = client.refreshes;
      await tester.ensureVisible(find.text('Повторить чтение'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Повторить чтение'));
      await tester.pump();
      expect(client.refreshes, before + 1);
      client.events.add(fixtures.snapshot());
      await tester.pumpAndSettle();
      expect(find.text('Тёмная'), findsOneWidget);
      bootstrap.show(ReadinessState.unavailable);
      await tester.pumpAndSettle();
      expect(find.textContaining('Saved profile'), findsNothing);
      expect(find.textContaining('192.0.2.1'), findsNothing);
      expect(find.text('Локальная служба недоступна'), findsWidgets);
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
          final scrollable = find
              .descendant(
                of: find.byType(ProfileList),
                matching: find.byType(Scrollable),
              )
              .first;
          final tile = find.byKey(const ValueKey(fixtures.profileId));
          await tester.scrollUntilVisible(tile, 200, scrollable: scrollable);
          final edit = find.descendant(
            of: tile,
            matching: find.text('Изменить'),
          );
          await tester.ensureVisible(edit);
          await tester.pumpAndSettle();
          await tester.tap(edit);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Сохранить'));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await client.events.close();
        },
      );
    }
  }
}
