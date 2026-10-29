import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/app.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/profiles/recovery_view.dart';
import 'package:serverdeck_protocol/models.dart';

import '../contract/startup_recovery_test.dart' show RecentClient, recent;
import '../contract/profile_controller_test.dart' as fixture;

void main() {
  testWidgets(
    'recent receipts retain request identities and content on refresh',
    (tester) async {
      final client = RecentClient();
      final bootstrap = fixture.ModelBootstrap(client)
        ..show(ReadinessState.ready);
      await tester.pumpWidget(FoundationApp(bootstrap: bootstrap));
      client.events.add(fixture.snapshot(revision: '3'));
      Map<String, Object?> receipt(int index, String operation) => {
        'requestId':
            '33333333-3333-4333-8333-${index.toString().padLeft(12, '0')}',
        'operation': operation,
        'profileId': operation == 'settings.update' ? null : fixture.profileId,
        'result': {
          'entityId': operation == 'settings.update' ? null : fixture.profileId,
          'entityRevision': '$index',
          'storeRevision': '$index',
          'deleted': false,
        },
        'committedAt': '2026-10-11T00:00:0$index.000Z',
      };
      final receipts = [
        receipt(3, 'settings.update'),
        receipt(2, 'profiles.update'),
        receipt(1, 'profiles.create'),
      ];
      client.replies.single.complete(
        ApiReply(fixture.fixtureGeneration, {
          'receipts': receipts,
          'truncated': false,
        }),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Недавние подтверждённые операции'));
      await tester.pumpAndSettle();

      final history = find.byType(RecentOperationsView);
      Finder receiptRows() => find.descendant(
        of: history,
        matching: find.byWidgetPredicate(
          (widget) => widget.key is RecentOperationReceiptKey,
        ),
      );
      void expectReceipt(Map<String, Object?> receipt, String label) {
        final row = find.byKey(
          RecentOperationReceiptKey(receipt['requestId']! as String),
        );
        expect(row, findsOneWidget);
        expect(tester.widget(row), isA<Container>());
        for (final value in [
          label,
          receipt['requestId'],
          if (receipt['profileId'] != null) receipt['profileId'],
          (receipt['result']! as Map)['storeRevision'],
          receipt['committedAt'],
        ]) {
          expect(
            find.descendant(of: row, matching: find.text(value! as String)),
            findsOneWidget,
          );
        }
      }

      expect(receiptRows(), findsNWidgets(3));
      expectReceipt(receipts[0], 'Изменение настроек подтверждено');
      expectReceipt(receipts[1], 'Изменение профиля подтверждено');
      expectReceipt(receipts[2], 'Создание профиля подтверждено');
      expect(
        find.descendant(of: history, matching: find.byType(Card)),
        findsNothing,
      );
      expect(find.text('Saved profile'), findsNothing);
      expect(client.reads, 1);

      await tester.ensureVisible(find.text('Обновить список'));
      await tester.tap(find.text('Обновить список'));
      await tester.pump();
      expect(client.reads, 2);
      client.replies.last.complete(
        ApiReply(fixture.fixtureGeneration, {
          'receipts': [receipts[1], receipts[2]],
          'truncated': false,
        }),
      );
      await tester.pumpAndSettle();
      expect(receiptRows(), findsNWidgets(2));
      expectReceipt(receipts[1], 'Изменение профиля подтверждено');
      expectReceipt(receipts[2], 'Создание профиля подтверждено');
      expect(
        find.byKey(
          RecentOperationReceiptKey(receipts[0]['requestId']! as String),
        ),
        findsNothing,
      );
      expect(find.text('Изменение настроек подтверждено'), findsNothing);
      expect(find.text('Saved profile'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await client.events.close();
      await client.readErrors.close();
    },
  );

  testWidgets(
    'startup gates new actions until recent; open history hides after readiness loss',
    (tester) async {
      final client = RecentClient();
      final bootstrap = fixture.ModelBootstrap(client)
        ..show(ReadinessState.ready);
      await tester.pumpWidget(FoundationApp(bootstrap: bootstrap));
      client.events.add(fixture.snapshot());
      await tester.pumpAndSettle();
      expect(find.text('Добавить сервер'), findsNothing);
      expect(
        find.text('Проверка текущих данных и недавних операций'),
        findsOneWidget,
      );
      client.replies.single.complete(
        ApiReply(fixture.fixtureGeneration, recent()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Добавить сервер'), findsOneWidget);
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
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Локальная служба недоступна'), findsWidgets);
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
