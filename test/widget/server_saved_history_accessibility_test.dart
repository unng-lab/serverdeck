import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/servers/metrics_history.dart';
import 'package:serverdeck/servers/server_compositions.dart';
import 'package:serverdeck/servers/server_sections.dart';
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_page.dart';
import 'package:serverdeck_protocol/models.dart'
    show ProfileView, ReadinessState;

import '../support/design_server_fixtures.dart';

void main() {
  // Exact production saved-section composition with fake external observations.
  // ServerPanel's saved wiring is independently source-reviewed. Its genuine
  // TrustedApiClient/native bootstrap, transport and owner are not executed.
  for (final frame in const [
    Size(1100, 760),
    Size(800, 600),
    Size(390, 800),
    Size(360, 800),
  ]) {
    for (final theme in [BrandTheme.light, BrandTheme.dark]) {
      for (final scale in [1.0, 2.0]) {
        final scenario =
            '${frame.width}x${frame.height} '
            '${theme.brightness.name} ${scale * 100}%';
        testWidgets('saved retained history keyboard and touch $scenario', (
          tester,
        ) async {
          _setFrame(tester, frame);
          var calls = 0;
          final profile = DesignServerFixtures.profile();
          final state = DesignServerFixtures.state(
            stale: true,
            points: [
              DesignServerFixtures.point(
                cpuPercent: 0,
                memoryUsedPercent: null,
                rootDiskUsedPercent: 100,
              ),
              DesignServerFixtures.point(time: '2026-10-25T09:00:15.001Z'),
              DesignServerFixtures.point(time: '2026-10-25T09:00:15.001Z'),
            ],
          );
          final before = jsonEncode(state);
          await _pumpSaved(
            tester,
            theme,
            scale: scale,
            state: state,
            profile: profile,
            onAction: () => calls++,
          );
          final section = find.byType(ServerSystemSection);
          final sectionElement = tester.element(section);
          final history = find.byType(MetricsHistory);
          expect(history, findsOneWidget);
          expect(tester.widget<MetricsHistory>(history).showPlots, isFalse);
          expect(find.byType(ServerObservationChart), findsNWidgets(3));
          expect(
            find.byKey(const ValueKey('metrics-history-plots')),
            findsNothing,
          );
          expect(
            find.descendant(
              of: history,
              matching: find.text('История ресурсов'),
            ),
            findsOneWidget,
          );
          for (final context in [
            'Источник: ssh:proc/stat+meminfo+net/dev+df',
            'Наблюдение: ${DesignServerFixtures.observedAt} · UTC',
            'Получено: ${DesignServerFixtures.observedAt} · UTC',
            'В истории есть пропуски значений; они не заменены нулями.',
          ]) {
            expect(
              find.descendant(of: history, matching: find.text(context)),
              findsOneWidget,
            );
          }
          final button = find.widgetWithText(TextButton, 'Значения истории');
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          expect(tester.getSize(button).width, greaterThanOrEqualTo(44));
          expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
          for (
            var tabs = 0;
            !_disclosureFocused(tester) && tabs < 160;
            tabs++
          ) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pumpAndSettle();
          }
          expect(_disclosureFocused(tester), isTrue);
          final focus = Focus.of(tester.element(find.text('Значения истории')));
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(_disclosureFocused(tester), isTrue);
          expect(
            Focus.of(tester.element(find.text('Значения истории'))),
            same(focus),
          );
          final values = find.byKey(const ValueKey('metrics-history-values'));
          expect(values, findsOneWidget);
          expect(tester.getSize(values).height, lessThanOrEqualTo(280));
          expect(
            find.text(
              '2026-10-25T09:00:00.000Z UTC · CPU: 0% · RAM: нет данных · Диск /: 100%',
            ),
            findsOneWidget,
          );
          for (final gap in [
            'больше 15 секунд',
            'время наблюдения повторилось',
          ]) {
            await _revealText(tester, find.textContaining(gap));
            expect(find.textContaining(gap), findsOneWidget);
          }
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('metrics-history-values-quality')),
              matching: find.text('Устаревшие данные'),
            ),
            findsOneWidget,
          );
          // Scrolling the bounded values must not replace the disclosure owner.
          expect(_disclosureFocused(tester), isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pumpAndSettle();
          expect(values, findsNothing);
          expect(_disclosureFocused(tester), isTrue);
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          expect(button.hitTestable(), findsOneWidget);
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(values, findsOneWidget);
          expect(tester.element(section), same(sectionElement));
          expect(
            tester.widget<ServerSystemSection>(section).state,
            same(state),
          );
          expect(
            tester
                .widget<ServerPageFrame>(find.byType(ServerPageFrame))
                .profile,
            same(profile),
          );
          expect(jsonEncode(state), before);
          expect(calls, 0);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets(
    'saved values retain integer gaps, source order and the 120 bound',
    (tester) async {
      _setFrame(tester, const Size(390, 800));
      var calls = 0;
      final points = <Object?>[...DesignServerFixtures.history()];
      // Defensive presentation input, not a wire-valid protocol fixture: the
      // codec already rejects fractional and wrongly typed percentage samples.
      points[1] = DesignServerFixtures.point(
        time: '2026-10-25T08:59:59.000Z',
        cpuPercent: 1.5,
        memoryUsedPercent: '10',
        rootDiskUsedPercent: 101,
      );
      points.addAll(DesignServerFixtures.history(count: 120).skip(3));
      points.add(DesignServerFixtures.point(time: '2026-10-25T10:00:00.000Z'));
      final state = <String, Object?>{
        ...DesignServerFixtures.state(),
        'history': points,
      };
      final before = jsonEncode(state);
      await _pumpSaved(
        tester,
        BrandTheme.dark,
        scale: 2,
        state: state,
        profile: DesignServerFixtures.profile(),
        onAction: () => calls++,
      );
      final button = find.widgetWithText(TextButton, 'Значения истории');
      expect(button, findsOneWidget);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      final values = find.byKey(const ValueKey('metrics-history-values'));
      final list = tester.widget<ListView>(values);
      expect(list.childrenDelegate.estimatedChildCount, 120);
      final rows = find.descendant(
        of: values,
        matching: find.byType(EditableText),
      );
      expect(
        tester.widget<EditableText>(rows.first).controller.text,
        '2026-10-25T09:00:00.000Z UTC · CPU: 0% · RAM: 0% · Диск /: 0%',
      );
      final missing = find.text(
        '2026-10-25T08:59:59.000Z UTC · CPU: нет данных · RAM: нет данных · Диск /: нет данных',
      );
      await _revealText(tester, missing);
      expect(missing, findsOneWidget);
      expect(
        find.textContaining('время наблюдения идёт в обратном порядке'),
        findsOneWidget,
      );
      final last = find.text(
        '2026-10-25T09:09:55.000Z UTC · CPU: 25% · RAM: 97% · Диск /: 32%',
      );
      await _revealText(tester, last, maxScrolls: 220);
      expect(last, findsOneWidget);
      expect(find.textContaining('2026-10-25T10:00:00.000Z UTC'), findsNothing);
      expect(jsonEncode(state), before);
      expect(calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('saved empty, unknown and evicted states never invent history', (
    tester,
  ) async {
    for (final state in <Map<String, Object?>?>[
      null,
      DesignServerFixtures.state(points: const []),
      DesignServerFixtures.state(points: const [], cacheDropped: true),
    ]) {
      await _pumpSaved(
        tester,
        BrandTheme.light,
        state: state,
        profile: DesignServerFixtures.profile(),
        onAction: () => fail('Read-only saved data dispatched an action'),
      );
      expect(find.byType(ServerObservationChart), findsNWidgets(3));
      expect(find.byType(MetricsHistory), findsNothing);
      expect(find.text('Значения истории'), findsNothing);
      if (state?['cacheDropped'] == true) {
        expect(find.textContaining('Кэш наблюдений удалён'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }
    // Retained data is not discarded merely because a cache-dropped notice
    // exists; the existing guard specifically excludes only evicted-empty data.
    await _pumpSaved(
      tester,
      BrandTheme.light,
      state: DesignServerFixtures.state(cacheDropped: true),
      profile: DesignServerFixtures.profile(),
      onAction: () => fail('Read-only saved data dispatched an action'),
    );
    expect(find.byType(MetricsHistory), findsOneWidget);
    expect(
      tester.widget<MetricsHistory>(find.byType(MetricsHistory)).showPlots,
      isFalse,
    );
  });

  testWidgets(
    'full system history keeps plots and its empty and eviction guards',
    (tester) async {
      for (final state in [
        DesignServerFixtures.state(),
        DesignServerFixtures.state(points: const []),
        DesignServerFixtures.state(points: const [], cacheDropped: true),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: BrandTheme.dark,
            home: Scaffold(
              body: SingleChildScrollView(
                child: ServerSystemSection(state: state),
              ),
            ),
          ),
        );
        if (state['cacheDropped'] == true) {
          expect(find.byType(MetricsHistory), findsNothing);
        } else {
          expect(
            tester
                .widget<MetricsHistory>(find.byType(MetricsHistory))
                .showPlots,
            isTrue,
          );
          expect(
            find.byKey(const ValueKey('metrics-history-plots')),
            findsOneWidget,
          );
          if ((state['history'] as List).isEmpty) {
            expect(
              find.descendant(
                of: find.byType(MetricsHistory),
                matching: find.text('Истории пока нет.'),
              ),
              findsOneWidget,
            );
          }
        }
        expect(tester.takeException(), isNull);
      }
    },
  );
}

bool _disclosureFocused(WidgetTester tester) =>
    Focus.of(tester.element(find.text('Значения истории'))).hasFocus;

void _setFrame(WidgetTester tester, Size frame) {
  tester.view.physicalSize = frame;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _revealText(
  WidgetTester tester,
  Finder text, {
  int maxScrolls = 50,
}) async {
  final values = find.byKey(const ValueKey('metrics-history-values'));
  await tester.ensureVisible(values);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    text,
    200,
    maxScrolls: maxScrolls,
    scrollable: find
        .descendant(of: values, matching: find.byType(Scrollable))
        .first,
  );
}

Future<void> _pumpSaved(
  WidgetTester tester,
  ThemeData theme, {
  double scale = 1,
  required Map<String, Object?>? state,
  required ProfileView profile,
  required VoidCallback onAction,
}) => tester.pumpWidget(
  MaterialApp(
    theme: theme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: FoundationShell(
      state: ReadinessState.ready,
      servers: ServerPageFrame(
        profile: profile,
        title: 'Сервер',
        selectedTab: 4,
        onTabSelected: (_) => onAction(),
        actions: serverPageHeaderActions(
          busy: false,
          onConnect: onAction,
          onRefresh: onAction,
        ),
        child: DeckPanel(
          title: 'Offline / сохранённые данные',
          child: Column(
            children: [
              const Text(
                'Показаны только удерживаемые текущим владельцем наблюдения. Актуальность нового соединения не подтверждена.',
              ),
              ServerSystemSection(state: state, showHistory: false),
            ],
          ),
        ),
      ),
    ),
  ),
);
