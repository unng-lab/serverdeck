import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/servers/server_compositions.dart';
import 'package:serverdeck/servers/server_sections.dart';
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck/ui/deck_page.dart';
import 'package:serverdeck/ui/deck_table_controls.dart';
import 'package:serverdeck_protocol/models.dart';

import '../support/design_fonts.dart' show loadDesignFonts;
import '../support/design_server_fixtures.dart';

void main() {
  setUpAll(loadDesignFonts);
  final profile = DesignServerFixtures.profile();
  final record = <String, Object?>{
    ...DesignServerFixtures.record(message: 'Exact source message 日本語'),
    'unit': 'observed.service',
    'priority': 6,
  };

  Future<void> mount(
    WidgetTester tester, {
    required Size frame,
    required bool dark,
    required double scale,
    required Widget child,
    required GlobalKey<ServerLogsSectionState> owner,
  }) async {
    tester.view.physicalSize = frame;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: Motion.theme(dark ? BrandTheme.dark : BrandTheme.light, true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: FoundationShell(
          state: ReadinessState.ready,
          section: FoundationSection.logs,
          contentBuilder: (_, _) => ServerPageFrame(
            profile: profile,
            title: 'Журнал сервера',
            eyebrow: 'Журналы / Рабочее пространство',
            showIdentity: false,
            showServerTabs: false,
            onTabSelected: (_) {},
            actions: serverPageHeaderActions(
              busy: false,
              logs: true,
              onSearch: () => owner.currentState?.focusSearch(),
              onFilters: () => owner.currentState?.toggleFilters(),
            ),
            child: child,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final frame in const [
    Size(1100, 760),
    Size(800, 600),
    Size(390, 800),
    Size(360, 800),
  ]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '22 source regions and actual row frame=${frame.width} dark=$dark scale=$scale',
          (tester) async {
            final query = TextEditingController();
            final owner = GlobalKey<ServerLogsSectionState>();
            final logs = DesignServerFixtures.logs(
              records: [record],
              nextCursor: 'exact-cursor',
            );
            var reads = 0, previous = 0, targetChanges = 0;
            Map<String, Object?>? opened;
            await mount(
              tester,
              frame: frame,
              dark: dark,
              scale: scale,
              owner: owner,
              child: ServerLogsSection(
                key: owner,
                showHeaderActions: false,
                profile: profile,
                targetSelector: ServerLogTargetSelector(
                  profiles: [profile],
                  selectedId: profile.id,
                  onSelected: (_) => targetChanges++,
                ),
                logs: logs,
                filterController: query,
                busy: false,
                onLoad: () => reads++,
                onPrevious: () => previous++,
                onOpenRecord: (row) => opened = row,
              ),
            );
            final regions = <Finder>[
              find.byType(DeckTabs),
              find.text('Источник и качество данных'),
              find.byKey(const ValueKey('server-log-search')),
              find.byKey(const ValueKey('server-log-toolbar')),
              find.byKey(const ValueKey('server-log-row-0')),
              find.byKey(const ValueKey('server-log-footer')),
              find.widgetWithText(FilledButton, 'Получить журнал'),
              find.text('Безопасное отображение журнала'),
              find.text(
                'Последняя запись: ${DesignServerFixtures.observedAt} UTC',
              ),
            ];
            for (var index = 1; index < regions.length; index++) {
              expect(
                tester.getTopLeft(regions[index]).dy,
                greaterThan(tester.getTopLeft(regions[index - 1]).dy),
              );
            }
            for (final label in ['Пауза', 'Приоритет', 'Период']) {
              final button = find.widgetWithText(OutlinedButton, label);
              expect(button, findsOneWidget);
              expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
            }
            final search = tester.widget<TextField>(
              find.byKey(const ValueKey('server-log-search')),
            );
            expect(search.maxLength, 256);
            expect(search.style!.fontSize, frame.width <= 520 ? 14 : 13);
            expect(search.style!.height, 20 / (frame.width <= 520 ? 14 : 13));
            final contextRows = tester.widget<ServerFactRows>(
              find.byType(ServerFactRows),
            );
            expect(
              contextRows.valueStyles['Источник']!.fontFamily,
              BrandTypography.caption.fontFamily,
            );
            expect(
              contextRows.valueStyles['Источник']!.fontSize,
              frame.width <= 520 ? 13 : 12,
            );
            expect(search.decoration!.counterText, '');
            expect(search.decoration!.labelText, isNull);
            expect(search.decoration!.hintText, 'Поиск в сообщениях');
            final time = tester.getTopLeft(find.text('09:00:00'));
            final priority = tester.getTopLeft(find.text('Информация'));
            final message = tester.getTopLeft(
              find.text('observed.service Exact source message 日本語'),
            );
            expect(priority.dy, closeTo(time.dy, 1));
            if (frame.width > 520 && scale == 1) {
              expect(message.dy, closeTo(time.dy, 1));
              expect(message.dx, greaterThan(priority.dx));
              expect(find.text('0001'), findsOneWidget);
            } else {
              expect(message.dy, greaterThan(time.dy));
              expect(find.text('0001'), findsNothing);
            }
            expect(
              tester
                  .getSize(find.byKey(const ValueKey('server-log-viewport')))
                  .height,
              lessThan(240),
            );
            expect(reads + previous + targetChanges, 0);
            final row = find.byKey(const ValueKey('server-log-row-0'));
            await tester.ensureVisible(row);
            await tester.pumpAndSettle();
            await tester.tap(row);
            expect(opened, same((logs['records'] as List).single));
            final read = find.widgetWithText(FilledButton, 'Получить журнал');
            await tester.ensureVisible(read);
            await tester.tap(read);
            await tester.pumpAndSettle();
            expect(reads, 1);
            expect(previous + targetChanges, 0);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
            query.dispose();
          },
        );
      }
    }
  }

  testWidgets(
    '22 query focus and bounded inner list keep their owners through resize and theme',
    (tester) async {
      final owner = GlobalKey<ServerLogsSectionState>();
      final query = TextEditingController();
      final logs = DesignServerFixtures.logs(
        records: [
          for (var index = 0; index < 100; index++)
            DesignServerFixtures.record(
              message: 'Row $index 日本語',
              cursor: 'cursor-$index',
            ),
        ],
      );
      var reads = 0;
      Widget section() => ServerLogsSection(
        key: owner,
        showHeaderActions: false,
        profile: profile,
        logs: logs,
        filterController: query,
        busy: false,
        onLoad: () => reads++,
        onPrevious: () => reads++,
        onOpenRecord: (_) {},
      );
      await mount(
        tester,
        frame: const Size(1100, 760),
        dark: false,
        scale: 1,
        owner: owner,
        child: section(),
      );
      final search = find.byKey(const ValueKey('server-log-search'));
      expect(
        find.ancestor(of: search, matching: find.byType(DeckSearchField)),
        findsOneWidget,
      );
      await tester.enterText(search, 'captured query 日本語');
      final field = tester.widget<TextField>(search);
      final editable = find.descendant(
        of: search,
        matching: find.byType(EditableText),
      );
      final editState = tester.state(editable);
      final list = find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      );
      final listState = tester.state<ScrollableState>(list);
      listState.position.jumpTo(200);
      await tester.pumpAndSettle();
      final offset = listState.position.pixels;
      for (final frame in const [
        Size(800, 600),
        Size(390, 800),
        Size(360, 800),
        Size(1100, 760),
      ]) {
        await mount(
          tester,
          frame: frame,
          dark: true,
          scale: 1,
          owner: owner,
          child: section(),
        );
        expect(tester.state(editable), same(editState));
        expect(
          tester.widget<TextField>(search).focusNode,
          same(field.focusNode),
        );
        expect(query.text, 'captured query 日本語');
        expect(tester.state<ScrollableState>(list), same(listState));
        expect(listState.position.pixels, offset);
        expect(reads, 0);
        expect(tester.takeException(), isNull);
      }
      owner.currentState!.focusSearch();
      await tester.pumpAndSettle();
      await tester.enterText(search, 'a' * 300);
      expect(query.text, 'a' * 256);
      expect(reads, 0);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(reads, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      query.dispose();
    },
  );

  for (final quality in ['known', 'denied', 'unsupported', 'incomplete']) {
    testWidgets('22 empty quality stays typed quality=$quality', (
      tester,
    ) async {
      final query = TextEditingController();
      final owner = GlobalKey<ServerLogsSectionState>();
      var reads = 0;
      await mount(
        tester,
        frame: const Size(360, 800),
        dark: true,
        scale: 2,
        owner: owner,
        child: ServerLogsSection(
          key: owner,
          showHeaderActions: false,
          profile: profile,
          logs: DesignServerFixtures.logs(quality: quality, records: []),
          filterController: query,
          busy: false,
          onLoad: () => reads++,
          onPrevious: () => reads++,
          onOpenRecord: (_) {},
        ),
      );
      expect(
        find.text('Записей по выбранному фильтру нет.'),
        quality == 'known' ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Подтверждённые записи журнала не получены.'),
        quality == 'known' ? findsNothing : findsOneWidget,
      );
      expect(reads, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      query.dispose();
    });
  }

  testWidgets(
    '22 incomplete counters and exact raw row remain visible without implicit reads',
    (tester) async {
      final query = TextEditingController();
      final owner = GlobalKey<ServerLogsSectionState>();
      var reads = 0;
      final logs = DesignServerFixtures.logs(
        records: [record],
        dropped: 3,
        duplicates: 2,
        parseErrors: 1,
        truncated: true,
        gaps: true,
      );
      await mount(
        tester,
        frame: const Size(1100, 760),
        dark: true,
        scale: 1,
        owner: owner,
        child: ServerLogsSection(
          key: owner,
          showHeaderActions: false,
          profile: profile,
          logs: logs,
          filterController: query,
          busy: false,
          onLoad: () => reads++,
          onPrevious: () => reads++,
          onOpenRecord: (_) {},
        ),
      );
      for (final value in [
        'Пропущено: 3',
        'Дубликатов: 2',
        'Ошибок разбора: 1',
        'Источник сообщил о разрыве',
        'Буфер ограничен; остальные записи не получены',
      ]) {
        expect(find.text(value), findsOneWidget);
      }
      expect(
        find.text('Журнал неполный: часть записей пропущена или ограничена.'),
        findsOneWidget,
      );
      expect(
        tester.widget<ServerLogsSection>(find.byType(ServerLogsSection)).logs,
        same(logs),
      );
      expect(reads, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      query.dispose();
    },
  );
}
