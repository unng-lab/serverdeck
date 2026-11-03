import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/ui/deck_components.dart';

import '../../tool/component_catalog/documentation.dart';
import '../../tool/component_catalog/examples.dart';
import '../../tool/component_catalog/job_example.dart';
import '../../tool/component_catalog/names.dart';
import '../support/component_cases.dart';
import '../support/component_state_driver.dart';

void main() {
  testWidgets(
    'real hover, keyboard focus and held press reach Material states',
    (tester) async {
      final states = WidgetStatesController();
      addTearDown(states.dispose);
      var calls = 0;
      await tester.pumpWidget(
        componentHarness(
          DeckButton(
            statesController: states,
            onPressed: () => calls++,
            child: const Text('Действие'),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Действие')));
      await tester.pumpAndSettle();
      expect(states.value, contains(WidgetState.hovered));
      await mouse.down(tester.getCenter(find.text('Действие')));
      await tester.pump();
      expect(states.value, contains(WidgetState.pressed));
      expect(calls, 0);
      await mouse.cancel();
      await mouse.removePointer();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(states.value, contains(WidgetState.focused));
      expect(calls, 0);
    },
  );

  testWidgets('disabled tab, breadcrumb and back have no activation', (
    tester,
  ) async {
    await tester.pumpWidget(
      componentHarness(const ComponentExample(id: 'C16', state: 'disabled')),
    );
    for (final button in tester.widgetList<ButtonStyleButton>(
      find.byWidgetPredicate((w) => w is ButtonStyleButton),
    )) {
      expect(button.onPressed, null);
    }
    for (final button in tester.widgetList<IconButton>(
      find.byType(IconButton),
    )) {
      expect(button.onPressed, null);
    }
    await tester.tap(find.text('Журнал'));
    await tester.pump();
    expect(tester.widget<DeckTabs>(find.byType(DeckTabs)).selected, 0);
  });

  testWidgets('no-results is not empty and its clear restores server data', (
    tester,
  ) async {
    await tester.pumpWidget(
      componentHarness(const ComponentExample(id: 'C05', state: 'no-results')),
    );
    expect(find.text('Ничего не найдено'), findsOneWidget);
    expect(find.text('Записей пока нет'), findsNothing);
    await tester.tap(find.text('Очистить поиск'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DeckCollection<CatalogRow>>(
            find.byType(DeckCollection<CatalogRow>),
          )
          .rows
          .length,
      4,
    );
  });

  for (final entry in {
    'stale': 'Данные устарели',
    'partial': 'Данные получены не полностью',
    'unknown': 'Состояние данных неизвестно',
    'unavailable': 'Возможность недоступна',
  }.entries) {
    testWidgets('area ${entry.key} preserves its actual meaning', (
      tester,
    ) async {
      await tester.pumpWidget(
        componentHarness(ComponentExample(id: 'C12', state: entry.key)),
      );
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('Записей пока нет'), findsNothing);
    });
  }

  testWidgets(
    'form validation summary is reachable and clears after correction',
    (tester) async {
      await tester.pumpWidget(
        componentHarness(const ComponentExample(id: 'C13')),
      );
      await tester.enterText(find.byType(TextFormField), '');
      await tester.tap(find.text('Сохранить'));
      await tester.pump();
      expect(find.text('Проверьте форму'), findsOneWidget);
      expect(find.text('Введите имя'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'valid-name');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(find.text('Проверьте форму'), findsNothing);
      expect(find.text('Демонстрация: Форма проверена'), findsOneWidget);
    },
  );

  testWidgets(
    'invalid JSON can be validated, corrected and copied without losing draft',
    (tester) async {
      await tester.pumpWidget(
        componentHarness(const ComponentExample(id: 'C26')),
      );
      await tester.enterText(find.byType(TextFormField), '{ invalid');
      await tester.ensureVisible(find.text('Проверить формат'));
      await tester.tap(find.text('Проверить формат'));
      await tester.pumpAndSettle();
      expect(find.text('Некорректный JSON'), findsWidgets);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '{ invalid',
      );
      await tester.enterText(find.byType(TextFormField), '{"valid":true}');
      await tester.tap(find.text('Проверить формат'));
      await tester.pumpAndSettle();
      expect(find.text('Демонстрация: Формат JSON корректен'), findsOneWidget);
    },
  );

  testWidgets('calendar rejects normalized invalid and empty dates', (
    tester,
  ) async {
    await tester.pumpWidget(
      componentHarness(const ComponentExample(id: 'C28')),
    );
    final date = find.byType(TextFormField).first;
    for (final invalid in ['2026-02-31', '']) {
      await tester.enterText(date, invalid);
      await tester.ensureVisible(find.text('Проверить дату и время'));
      await tester.tap(find.text('Проверить дату и время'));
      await tester.pumpAndSettle();
      expect(find.text('Проверьте дату и время'), findsOneWidget);
    }
    await tester.enterText(date, '2026-02-28');
    await tester.tap(find.text('Проверить дату и время'));
    await tester.pumpAndSettle();
    expect(find.text('Демонстрация: Дата и время корректны'), findsOneWidget);
  });

  testWidgets('full shell exposes all five navigation destinations', (
    tester,
  ) async {
    await tester.pumpWidget(
      componentHarness(const ComponentExample(id: 'C17')),
    );
    expect(find.byType(FoundationShell), findsOneWidget);
    for (final section in FoundationSection.values) {
      expect(
        find.text(section.label).evaluate().isNotEmpty ||
            find.byTooltip(section.label).evaluate().isNotEmpty,
        true,
      );
    }
  });

  for (final entry in {
    'success': 'Задание завершено',
    'error': 'Ошибка этапа',
    'cancelled': 'Остановка подтверждена',
    'unknown': 'Исход неизвестен',
  }.entries) {
    testWidgets('progress ${entry.key} is distinct from running', (
      tester,
    ) async {
      await tester.pumpWidget(
        componentHarness(ComponentExample(id: 'C23', state: entry.key)),
      );
      expect(find.text(entry.value), findsOneWidget);
      final progress = tester.widget<DeckProgress>(find.byType(DeckProgress));
      expect(
        progress.tone,
        entry.key == 'success'
            ? DeckTone.success
            : entry.key == 'error'
            ? DeckTone.error
            : entry.key == 'cancelled'
            ? DeckTone.warning
            : DeckTone.unknown,
      );
    });
  }

  for (final id in componentNames.keys) {
    testWidgets('$id has specific card documentation', (tester) async {
      await tester.pumpWidget(componentHarness(ComponentDocumentation(id: id)));
      for (final label in [
        'Анатомия',
        'Варианты',
        'Параметры',
        'События',
        'Ограничения',
        'Критерии приёмки',
        'Пример подключения',
        'Работающий пример',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.takeException(), null);
    });
  }

  testWidgets(
    'server and job owners use distinct schemas and independent journeys',
    (tester) async {
      Widget server() => componentHarness(const ComponentExample(id: 'C05'));
      await tester.pumpWidget(server());
      DeckCollection<CatalogRow> servers() =>
          tester.widget(find.byType(DeckCollection<CatalogRow>));
      expect(servers().rows.map((r) => r.id), [
        'web',
        'db',
        'worker',
        'web-standby',
      ]);
      await tester.tap(find.text('Сервер').first);
      await tester.pump();
      expect(
        servers().rows.where((r) => r.name == 'atlas-web').map((r) => r.id),
        ['web', 'web-standby'],
      );
      await tester.tap(find.text('Адрес').first);
      await tester.pump();
      expect(servers().rows.last.id, 'db');
      await tester.tap(find.text('Адрес ↑').first);
      await tester.pump();
      expect(servers().rows.last.id, 'db');
      final selectedRow = find.byKey(const ValueKey('deck-row-web'));
      final serverScroll = find
          .descendant(
            of: find.byType(DeckCollection<CatalogRow>),
            matching: find.byType(Scrollable),
          )
          .first;
      tester.state<ScrollableState>(serverScroll).position.jumpTo(0);
      await tester.pump();
      await tester.scrollUntilVisible(
        selectedRow,
        150,
        scrollable: serverScroll,
      );
      await tester.tap(
        find.descendant(of: selectedRow, matching: find.byType(Checkbox)),
      );
      await tester.pump();
      expect(servers().selectedIds, {'web'});
      await tester.tap(
        find.descendant(
          of: selectedRow,
          matching: find.text('Удалить из примера'),
        ),
      );
      await tester.pump();
      expect(servers().selectedIds, isEmpty);
      expect(servers().rows.any((r) => r.id == 'web'), false);

      await tester.pumpWidget(componentHarness(const JobCollectionExample()));
      DeckCollection<CatalogJob> jobs() =>
          tester.widget(find.byType(DeckCollection<CatalogJob>));
      expect(jobs().rows.map((r) => r.id), [
        'job-check-1',
        'job-check-2',
        'job-blocked',
      ]);
      await tester.tap(find.text('Задание').first);
      await tester.pump();
      expect(jobs().rows.where((r) => r.title == 'Проверка').map((r) => r.id), [
        'job-check-1',
        'job-check-2',
      ]);
      await tester.tap(find.text('Цель').first);
      await tester.pump();
      expect(jobs().rows.last.id, 'job-blocked');
      await tester.tap(find.text('Цель ↑').first);
      await tester.pump();
      expect(jobs().rows.last.id, 'job-blocked');
      final all = find.byWidgetPredicate(
        (w) =>
            w is Checkbox && w.semanticLabel == 'Выбрать отображаемую порцию',
      );
      await tester.tap(all);
      await tester.pump();
      expect(jobs().selectedIds, {'job-check-1', 'job-check-2'});
      final job = find.byKey(const ValueKey('deck-row-job-check-1'));
      final jobScroll = find
          .descendant(
            of: find.byType(DeckCollection<CatalogJob>),
            matching: find.byType(Scrollable),
          )
          .first;
      tester.state<ScrollableState>(jobScroll).position.jumpTo(0);
      await tester.pump();
      await tester.scrollUntilVisible(job, 150, scrollable: jobScroll);
      await tester.tap(
        find.descendant(of: job, matching: find.text('Удалить из примера')),
      );
      await tester.pump();
      expect(jobs().selectedIds, {'job-check-2'});
      await tester.enterText(find.byType(TextField), 'не существует');
      await tester.pump();
      expect(find.text('Ничего не найдено'), findsOneWidget);
      await tester.tap(find.text('Очистить поиск'));
      await tester.pump();
      expect(jobs().rows.length, 2);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pump();
      expect(tester.takeException(), null);
      expect(jobs().selectedIds, {'job-check-2'});
    },
  );

  testWidgets('capture driver creates actual focus and hover interaction', (
    tester,
  ) async {
    await tester.pumpWidget(
      componentHarness(const ComponentExample(id: 'C02')),
    );
    final release = await driveComponentState(tester, 'hover');
    await release();
    await driveComponentState(tester, 'focus');
    expect(FocusManager.instance.primaryFocus?.hasFocus, true);
  });
}
