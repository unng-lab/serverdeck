import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/app.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck_protocol/models.dart';

import '../contract/startup_recovery_test.dart' show RecentClient, recent;
import '../contract/profile_controller_test.dart' as fixture;

void main() {
  testWidgets(
    'startup gates new actions until recent; open history hides after readiness loss',
    (tester) async {
      final client = RecentClient();
      final bootstrap = fixture.ModelBootstrap(client)
        ..show(ReadinessState.ready);
      await tester.pumpWidget(FoundationApp(bootstrap: bootstrap));
      client.events.add(fixture.snapshot());
      await tester.pumpAndSettle();
      expect(find.text('Создать профиль'), findsNothing);
      expect(
        find.text('Проверка текущих данных и недавних операций'),
        findsOneWidget,
      );
      client.replies.single.complete(
        ApiReply(fixture.fixtureGeneration, recent()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Создать профиль'), findsOneWidget);
      await tester.tap(find.byTooltip('Недавние подтверждённые операции'));
      await tester.pumpAndSettle();
      expect(find.text('Изменение настроек подтверждено'), findsOneWidget);
      expect(
        find.textContaining('Автоматический повтор не выполняется'),
        findsOneWidget,
      );
      bootstrap.show(ReadinessState.unavailable);
      await tester.pumpAndSettle();
      expect(find.text('Изменение настроек подтверждено'), findsNothing);
      expect(find.textContaining('33333333-3333'), findsNothing);
      expect(
        find.text('Данные недоступны; проверьте локальную службу'),
        findsOneWidget,
      );
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
      expect(client.reads, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await client.events.close();
      await client.readErrors.close();
    },
  );

  for (final dark in [false, true]) {
    for (final size in const [
      Size(1100, 760),
      Size(800, 600),
      Size(360, 800),
      Size(390, 800),
    ]) {
      testWidgets('bounded history scrolls $size dark=$dark at200', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final client = RecentClient();
        final bootstrap = fixture.ModelBootstrap(client)
          ..show(ReadinessState.ready);
        await tester.pumpWidget(FoundationApp(bootstrap: bootstrap));
        final snapshot = fixture.snapshot(revision: '20');
        final settings = Map<String, Object?>.from(
          snapshot.settings.result['settings'] as Map,
        );
        settings['theme'] = dark ? 'dark' : 'light';
        client.events.add(
          ClientSnapshot(
            snapshot.profiles,
            ApiReply(fixture.fixtureGeneration, {
              'storeRevision': '20',
              'settings': settings,
            }),
          ),
        );
        final receipts = List.generate(20, (i) {
          final body = Map<String, Object?>.from(
            (recent(revision: '${20 - i}')['receipts'] as List).single as Map,
          );
          body['requestId'] =
              '33333333-3333-4333-8333-${i.toRadixString(16).padLeft(12, '0')}';
          return body;
        });
        client.replies.single.complete(
          ApiReply(fixture.fixtureGeneration, {
            'receipts': receipts,
            'truncated': true,
          }),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Недавние подтверждённые операции'));
        await tester.pumpAndSettle();
        expect(find.text('Показана часть сохранённых записей'), findsOneWidget);
        await tester.ensureVisible(find.text('Закрыть'));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.widgetWithText(OutlinedButton, 'Закрыть')).height,
          greaterThanOrEqualTo(48),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Закрыть'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await client.events.close();
        await client.readErrors.close();
      });
    }
  }
}
