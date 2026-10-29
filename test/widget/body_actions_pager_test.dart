import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/automation/automation_panel.dart';
import 'package:serverdeck/servers/server_sections.dart';
import 'package:serverdeck/software/software_panel.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_components.dart';
import 'package:serverdeck/ui/deck_control_target.dart';
import 'package:serverdeck/ui/deck_page.dart';
import 'package:serverdeck/ui/deck_icon.dart';
import 'package:serverdeck/ui/deck_table_controls.dart';

import '../support/design_automation_fixtures.dart';
import '../support/design_fonts.dart';
import '../support/base_design_bindings.dart';
import '../support/design_host.dart' show mountDesignFixture;
import '../support/design_server_fixtures.dart';
import 'deck_components_test.dart' show pixels;

void main() {
  for (final width in [1100.0, 390.0]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'T234 source selector header and full target $width $dark $scale',
          (tester) async {
            tester.view.physicalSize = Size(width, 800);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            var choices = 0;
            await tester.pumpWidget(
              MaterialApp(
                theme: dark ? BrandTheme.dark : BrandTheme.light,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: SoftwareServerSelector(
                      profiles: const [],
                      selectedId: null,
                      onChoose: () => choices++,
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final title = find.text('Область просмотра');
            final header = find
                .ancestor(
                  of: title,
                  matching: find.byWidgetPredicate(
                    (w) =>
                        w is Container &&
                        w.decoration is BoxDecoration &&
                        (w.decoration! as BoxDecoration).border != null,
                  ),
                )
                .first;
            if (scale == 1)
              expect(
                tester.getSize(header).height,
                closeTo(width <= 520 ? 51 : 53, .01),
              );
            final button = find.widgetWithText(TextButton, 'Выбрать сервер');
            final native = tester.getRect(button);
            expect(native.height, greaterThanOrEqualTo(44));
            expect(native.width, greaterThanOrEqualTo(44));
            expect(choices, 0);
            await tester.tapAt(Offset(native.center.dx, native.top + .25));
            await tester.pumpAndSettle();
            await tester.tapAt(Offset(native.center.dx, native.bottom - .25));
            await tester.pumpAndSettle();
            expect(choices, 2);
            Focus.of(tester.element(find.text('Выбрать сервер')))
                .requestFocus();
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(choices, 3);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
  for (final width in [1100.0, 390.0]) {
    testWidgets('T224 history controls stay local and reset query $width', (
      tester,
    ) async {
      final host = await mountDesignFixture(
        tester,
        currentBaseBindings.singleWhere(
          (entry) => entry.screenId == '31-recent-operations',
        ),
        frame: Size(width, 800),
        theme: ThemeMode.dark,
        textScale: width <= 520 ? 2 : 1,
        currentBase: true,
      );
      try {
        final reads = host.harness.client.reads.length;
        final refreshes = host.harness.client.refreshes;
        final search = find.byType(DeckSearchField);
        await tester.ensureVisible(search);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(of: search, matching: find.byType(TextField)),
          'no matching operation',
        );
        await tester.pumpAndSettle();
        expect(find.text('Операции не найдены'), findsOneWidget);
        final all = find.byWidgetPredicate(
          (w) => w is DeckFilterChip && w.label.startsWith('Все '),
        );
        await tester.ensureVisible(all);
        await tester.tap(all);
        await tester.pumpAndSettle();
        expect(find.text('Изменение настроек подтверждено'), findsOneWidget);
        expect(tester.widget<DeckSearchField>(search).controller.text, isEmpty);
        final sort = find.widgetWithText(OutlinedButton, 'Сначала новые');
        await tester.ensureVisible(sort);
        await tester.tap(sort);
        await tester.pumpAndSettle();
        expect(find.text('Сначала старые'), findsOneWidget);
        for (final label in ['Состояние', 'Теги']) {
          final chip = tester.widget<DeckFilterChip>(
            find.byWidgetPredicate(
              (w) => w is DeckFilterChip && w.label == label,
            ),
          );
          expect(chip.onPressed, isNull);
          expect(chip.tooltip, isNotEmpty);
        }
        expect(find.byType(DeckPagerButton), findsNWidgets(3));
        if (width > 520) {
          final chips = find.byType(DeckFilterChip);
          for (var i = 1; i < 4; i++) {
            expect(
              tester.getRect(chips.at(i)).left -
                  tester.getRect(chips.at(i - 1)).right,
              closeTo(8, .01),
            );
          }
          final pages = find.byType(DeckPagerButton);
          for (var i = 1; i < 3; i++) {
            expect(
              tester.getRect(pages.at(i)).left -
                  tester.getRect(pages.at(i - 1)).right,
              closeTo(4, .01),
            );
          }
        }
        for (final element in find.byType(DeckPagerButton).evaluate()) {
          expect((element.widget as DeckPagerButton).onPressed, isNull);
        }
        expect(host.harness.client.reads.length, reads);
        expect(host.harness.client.refreshes, refreshes);
        expect(host.harness.client.mutations, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await host.close(tester);
      }
    });
  }

  for (final id in ['01-startup', '23-log-record', '40-executor-binding']) {
    for (final width in [1100.0, 390.0]) {
      testWidgets('T220 server body action source origin $id $width', (
        tester,
      ) async {
        final host = await mountDesignFixture(
          tester,
          currentBaseBindings.singleWhere((entry) => entry.screenId == id),
          frame: Size(width, 800),
          theme: ThemeMode.dark,
          textScale: 1,
          currentBase: true,
        );
        try {
          final label = switch (id) {
            '01-startup' => 'Дождаться запуска',
            '23-log-record' => 'Скопировать запись',
            _ => 'Привязать исполнитель',
          };
          final action = find.widgetWithText(FilledButton, label);
          await tester.ensureVisible(action);
          await tester.pumpAndSettle();
          final native = tester.getRect(action);
          final panel = tester.getRect(find.byType(DeckPanel).last);
          final inset = width <= 520 ? 0.0 : 4.0;
          expect(native.height, greaterThanOrEqualTo(44));
          expect(native.left + inset, closeTo(panel.left, .01));
          expect(
            native.top + inset - panel.bottom,
            closeTo(width <= 520 ? 16 : 20, .01),
          );
          if (id == '23-log-record') {
            final icon = find.descendant(
              of: action,
              matching: find.byType(DeckButtonIcon),
            );
            final text = tester.getRect(find.text(label));
            expect(tester.getSize(icon), Size.square(width <= 520 ? 18 : 16));
            expect(text.left - tester.getRect(icon).right, closeTo(7, .01));
          }
          if (id == '40-executor-binding') {
            expect(
              find.text(
                'Проверьте цель, последствия и условия выбранного действия',
              ),
              findsOneWidget,
            );
          }
          expect(host.harness.counters.values, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await host.close(tester);
        }
      });
    }
  }

  for (final width in [1100.0, 800.0, 390.0, 360.0]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'T218 profile version action source flow $width $dark $scale',
          (tester) async {
            tester.view.physicalSize = Size(width, 800);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            var choices = 0;
            var allowed = true;
            Widget page() => MaterialApp(
              theme: dark ? BrandTheme.dark : BrandTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: AutomationProfilesSection(
                    profiles: [DesignAutomationFixtures.profile()],
                    loaded: true,
                    hasMore: false,
                    actions: AutomationActionAvailability(
                      read: allowed,
                      mutate: false,
                      select: false,
                    ),
                    onSelect: (_) {},
                    onMore: () {},
                    onSelectVersion: () => choices++,
                  ),
                ),
              ),
            );
            await tester.pumpWidget(page());
            await tester.pumpAndSettle();
            final action = find.widgetWithText(
              OutlinedButton,
              'Выбрать версию',
            );
            final native = tester.getRect(action);
            final search = tester.getRect(find.byType(DeckSearchField));
            final inset = width <= 520 ? 0.0 : 4.0;
            expect(native.height, greaterThanOrEqualTo(44));
            expect(native.left + inset, closeTo(search.left, .01));
            expect(search.top - (native.bottom - inset), closeTo(18, .01));
            if (width <= 520) {
              expect(native.width, closeTo(search.width, .01));
            } else if (scale == 1) {
              expect(native.height - 2 * inset, closeTo(36, .01));
            }
            expect(choices, 0);
            await tester.tapAt(Offset(native.center.dx, native.top + .2));
            await tester.pumpAndSettle();
            expect(choices, 1);
            final state = tester.state(action);
            final focus = Focus.of(tester.element(find.text('Выбрать версию')));
            focus.requestFocus();
            await tester.pumpAndSettle();
            tester.view.physicalSize = Size(width <= 520 ? 1100 : 390, 800);
            await tester.pumpAndSettle();
            expect(tester.state(action), same(state));
            expect(focus.hasFocus, isTrue);
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(choices, 2);
            allowed = false;
            await tester.pumpWidget(page());
            await tester.pumpAndSettle();
            expect(tester.widget<OutlinedButton>(action).onPressed, isNull);
            expect(choices, 2);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }

  setUpAll(loadDesignFonts);
  for (final width in [1100.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'T204 real header icon-label gap stays7 $width scale=$scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: BrandTheme.dark,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: Wrap(
                  children: automationPageActions(
                    section: 'jobs',
                    availability: const AutomationActionAvailability(
                      read: true,
                      mutate: true,
                      select: true,
                    ),
                    onRefresh: () {},
                    onCreate: () {},
                    onLoadRecipes: () {},
                    onOpenJob: () {},
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final button = find.widgetWithText(OutlinedButton, 'Обновить');
          final icon = tester.getRect(
            find.descendant(of: button, matching: find.byType(DeckButtonIcon)),
          );
          final label = tester.getRect(
            find.descendant(of: button, matching: find.text('Обновить')),
          );
          expect(label.left - icon.right, closeTo(7, .01));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
  testWidgets(
    'T202 standalone log actions keep source text without extra glyphs',
    (tester) async {
      final query = TextEditingController();
      var reads = 0;
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: BrandTheme.dark,
            home: Scaffold(
              body: SingleChildScrollView(
                child: ServerLogsSection(
                  profile: DesignServerFixtures.profile(),
                  filterController: query,
                  logs: DesignServerFixtures.logs(
                    quality: 'known',
                    records: [],
                  ),
                  busy: false,
                  onLoad: () => reads++,
                  onPrevious: () => reads++,
                  onOpenRecord: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final label in ['Поиск', 'Фильтры']) {
          final button = find.widgetWithText(OutlinedButton, label);
          expect(
            find.descendant(of: button, matching: find.byType(DeckIcon)),
            findsNothing,
          );
          await tester.tap(button);
          await tester.pumpAndSettle();
        }
        expect(query.text, '');
        expect(reads, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        query.dispose();
      }
    },
  );
  for (final section in ['jobs', 'profiles']) {
    testWidgets(
      'T202 canonical refresh icon retains its real callback $section',
      (tester) async {
        var reads = 0;
        final label = section == 'jobs' ? 'Обновить' : 'Обновить профили';
        await tester.pumpWidget(
          MaterialApp(
            theme: BrandTheme.dark,
            home: Scaffold(
              body: Wrap(
                children: automationPageActions(
                  section: section,
                  availability: const AutomationActionAvailability(
                    read: true,
                    mutate: true,
                    select: true,
                  ),
                  onRefresh: () => reads++,
                  onCreate: () {},
                  onLoadRecipes: () {},
                  onOpenJob: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final button = find.widgetWithText(OutlinedButton, label);
        expect(
          find.descendant(of: button, matching: find.byType(DeckButtonIcon)),
          findsOneWidget,
        );
        expect(reads, 0);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(reads, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  for (final width in [1100.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('T203 jobs filter-to-search source gap $width scale=$scale', (
        tester,
      ) async {
        final binding = currentBaseBindings.singleWhere(
          (entry) => entry.screenId == '27-job-list',
        );
        final host = await mountDesignFixture(
          tester,
          binding,
          frame: Size(width, 800),
          theme: ThemeMode.dark,
          textScale: scale,
          currentBase: true,
        );
        try {
          await tester.pumpAndSettle();
          final button = tester.getRect(
            find.widgetWithText(OutlinedButton, 'Фильтры'),
          );
          final search = tester.getRect(find.byType(DeckSearchField));
          expect(search.top - (button.bottom - (width <= 520 ? 0 : 4)), 18);
          expect(tester.takeException(), isNull);
        } finally {
          await host.close(tester);
        }
      });
    }
  }
  for (final width in [1100.0, 390.0]) {
    testWidgets(
      'T193 button icons use their source role without scaling standard glyphs $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: BrandTheme.dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: Column(
                children: [
                  OutlinedButton(
                    onPressed: () {},
                    child: const DeckButtonLabel(
                      icon: 'search',
                      label: 'Поиск',
                    ),
                  ),
                  IconButton(onPressed: () {}, icon: const DeckIcon('server')),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final buttonIcon = find.descendant(
          of: find.byType(DeckButtonIcon),
          matching: find.byType(DeckIcon),
        );
        expect(tester.getSize(buttonIcon), Size.square(width <= 520 ? 18 : 16));
        final standard = find.byWidgetPredicate(
          (widget) => widget is DeckIcon && widget.name == 'server',
        );
        expect(tester.getSize(standard), const Size.square(20));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets('T193 multi-digit page grows at200 with its complete value', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: DeckPagerButton(page: 9999, selected: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final target = tester.getRect(find.byType(DeckControlTarget));
    final label = tester.getRect(find.text('9999'));
    expect(target.height, greaterThan(44));
    expect(target.contains(label.topLeft), isTrue);
    expect(target.contains(label.bottomRight - const Offset(.01, .01)), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'T193 ordinary body actions have source36 geometry and native fringe callbacks',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.dark,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  DeckPanel(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DeckActions(
                          children: [
                            OutlinedButton(
                              onPressed: () => calls++,
                              child: const Text('Действие'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(DeckActions)).height, 36);
      final button = find.widgetWithText(OutlinedButton, 'Действие');
      final box = tester.getRect(button);
      expect(box.height, 44);
      await tester.tapAt(Offset(box.center.dx, box.top + .2));
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.tapAt(Offset(box.center.dx, box.bottom - .2));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final width in [1100.0, 390.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'T193 selected pager paint and readonly semantics $width dark=$dark',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final boundary = GlobalKey();
          var reads = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? BrandTheme.dark : BrandTheme.light,
              home: Scaffold(
                body: RepaintBoundary(
                  key: boundary,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: AutomationLoadedTable(
                      columns: const ['Название'],
                      rows: const [
                        [Text('Запись')],
                      ],
                      hasMore: true,
                      onMore: () => reads++,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final current = find.byWidgetPredicate(
            (widget) =>
                widget is Tooltip &&
                widget.message!.startsWith('Это текущая загруженная страница'),
          );
          final native = find.descendant(
            of: current,
            matching: find.byWidgetPredicate(
              (widget) => widget is ButtonStyleButton,
            ),
          );
          expect(native, findsOneWidget);
          expect(tester.widget<ButtonStyleButton>(native).onPressed, isNull);
          expect(
            find.descendant(
              of: current,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics && widget.properties.selected == true,
              ),
            ),
            findsOneWidget,
          );
          final target = find.descendant(
            of: current,
            matching: find.byType(DeckControlTarget),
          );
          expect(target, findsOneWidget);
          final visible = tester.getRect(target);
          expect(visible.height, width <= 520 ? 44 : 30);
          expect(tester.getSize(native).height, greaterThanOrEqualTo(44));
          final origin = tester.getTopLeft(find.byKey(boundary));
          final paint = await pixels(tester, boundary, [
            Offset(visible.left + 4 - origin.dx, visible.center.dy - origin.dy),
          ]);
          expect(
            paint.single,
            (dark ? BrandColors.dark : BrandColors.light)['selected'],
          );
          expect(reads, 0);
          final next = find.byTooltip('Следующая страница');
          final nextNative = find.descendant(
            of: next,
            matching: find.byType(TextButton),
          );
          final nextBounds = tester.getRect(nextNative);
          await tester.tapAt(Offset(nextBounds.center.dx, nextBounds.top + .2));
          await tester.pumpAndSettle();
          expect(reads, 1);
          await tester.tapAt(
            Offset(nextBounds.center.dx, nextBounds.bottom - .2),
          );
          await tester.pumpAndSettle();
          expect(reads, 2);
          Focus.of(
            tester.element(
              find.descendant(of: next, matching: find.byType(DeckIcon)),
            ),
          ).requestFocus();
          await tester.pumpAndSettle();
          final nextVisible = tester.getRect(
            find.descendant(of: next, matching: find.byType(DeckControlTarget)),
          );
          final focusPaint = await pixels(tester, boundary, [
            Offset(
              nextVisible.center.dx - origin.dx,
              nextVisible.top - 3 - origin.dy,
            ),
          ]);
          expect(
            focusPaint.single,
            (dark ? BrandColors.dark : BrandColors.light)['focus'],
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(reads, 3);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
