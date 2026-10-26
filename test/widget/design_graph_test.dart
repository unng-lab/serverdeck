import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/servers/metrics_history.dart';
import 'package:serverdeck/servers/server_sections.dart';
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck_protocol/models.dart' show ReadinessState;

import '../support/design_server_fixtures.dart';

void main() {
  // These tests mount the same shell, overview and history widgets as the app.
  // Protocol fixtures establish presentation evidence, not native authority.
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
        testWidgets('production overview geometry and strokes $scenario', (
          tester,
        ) async {
          _setFrame(tester, frame);
          var calls = 0;
          for (final stale in [false, true]) {
            await _pumpOverview(
              tester,
              theme,
              scale: scale,
              stale: stale,
              onAction: () => calls++,
            );
            await tester.ensureVisible(
              find.byKey(const ValueKey('metrics-history-plots')),
            );
            await tester.pumpAndSettle();
            final history = find.byType(MetricsHistory);
            final plots = tester.getRect(
              find.byKey(const ValueKey('metrics-history-plots')),
            );
            final actions = tester.getRect(
              find.byKey(const ValueKey('server-overview-actions')),
            );
            final error = tester.getRect(
              find.byKey(const ValueKey('server-overview-error')),
            );
            final available = tester.getSize(history).width;
            final expectedWidth = frame.width > 1060 ? 300.0 : 270.0;
            expect(
              plots.width,
              closeTo(
                available < expectedWidth ? available : expectedWidth,
                .01,
              ),
            );
            expect(error.bottom, lessThan(plots.top));
            expect(error.bottom, lessThan(actions.top));
            expect(actions.overlaps(plots), isFalse);
            final historyBounds = tester.getRect(history);
            expect(plots.right, closeTo(historyBounds.right, .01));
            if (frame.width <= 520) {
              expect(plots.bottom, lessThan(actions.top));
            } else if (available >= plots.width + 24 + 280 * scale) {
              expect(actions.bottom, closeTo(plots.bottom, .01));
              expect(actions.right, lessThan(plots.left));
            } else {
              expect(actions.bottom, lessThan(plots.top));
            }
            final palette = theme.extension<BrandColors>()!;
            for (final series in _seriesExpectations) {
              final plot = find.byKey(
                ValueKey('metrics-history-plot-${series.id}'),
              );
              final rect = tester.getRect(plot);
              expect(rect.height, 25);
              expect(rect.bottom, closeTo(plots.bottom, .01));
              expect(plots.contains(rect.topLeft), isTrue);
              expect(
                plots.contains(rect.bottomRight - const Offset(.01, .01)),
                isTrue,
              );
              final label = find.text('${series.label} · %');
              final text = tester.widget<Text>(label);
              expect(
                MediaQuery.textScalerOf(tester.element(label))
                    .scale(text.style!.fontSize!),
                12 * scale,
              );
              expect(
                tester.getSize(label).height,
                greaterThanOrEqualTo(16 * scale),
              );
              expect(tester.getRect(label).bottom, lessThan(rect.top));
              final color = palette[series.role];
              expect(
                _contrast(color, palette['surface']),
                greaterThanOrEqualTo(3),
              );
              _expectSymbols(tester, plot, series.id, color, count: 3);
              final curve = _strokePath(tester, plot, color);
              _expectPattern(curve, stale ? 6 : series.dash);
              final legend = find.byKey(
                ValueKey('metrics-history-legend-${series.id}'),
              );
              _expectSymbols(tester, legend, series.id, color, count: 1);
              _expectPattern(
                _strokePath(tester, legend, color),
                stale ? 6 : series.dash,
              );
              expect(
                find.bySemanticsLabel(
                  RegExp(
                    RegExp.escape(
                      '${series.label}: ${stale || series.dash == 6
                          ? 'пунктир 6/4'
                          : series.dash == 2
                          ? 'пунктир 2/4'
                          : 'сплошная линия'}, ${series.symbol}',
                    ),
                  ),
                ),
                findsOneWidget,
              );
            }
            final plotRects = [
              for (final series in _seriesExpectations)
                tester.getRect(
                  find.byKey(ValueKey('metrics-history-plot-${series.id}')),
                ),
            ];
            expect(plotRects[0].right, lessThan(plotRects[1].left));
            expect(plotRects[1].right, lessThan(plotRects[2].left));
            if (stale) {
              expect(
                find.descendant(
                  of: history,
                  matching: find.text('Устаревшие данные'),
                ),
                findsOneWidget,
              );
            } else {
              expect(
                find.descendant(
                  of: history,
                  matching: find.text('Данные получены'),
                ),
                findsOneWidget,
              );
            }
            final observedPoints = _circleCenters(
              tester,
              find.byKey(const ValueKey('metrics-history-plot-cpu')),
            );
            await tester.pump(const Duration(seconds: 30));
            expect(
              _circleCenters(
                tester,
                find.byKey(const ValueKey('metrics-history-plot-cpu')),
              ),
              observedPoints,
            );
            expect(calls, 0);
            expect(tester.takeException(), isNull);
          }
        });
        testWidgets('keyboard and touch reveal actual history $scenario', (
          tester,
        ) async {
          _setFrame(tester, frame);
          var calls = 0;
          await _pumpOverview(
            tester,
            theme,
            scale: scale,
            stale: true,
            points: [
              DesignServerFixtures.point(
                time: '2026-10-25T09:00:00.000Z',
                cpuPercent: 0,
                memoryUsedPercent: null,
                rootDiskUsedPercent: 100,
              ),
              DesignServerFixtures.point(time: '2026-10-25T09:00:15.001Z'),
              DesignServerFixtures.point(time: '2026-10-25T09:00:15.001Z'),
            ],
            onAction: () => calls++,
          );
          final button = find.widgetWithText(TextButton, 'Значения истории');
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          expect(tester.getSize(button).width, greaterThanOrEqualTo(44));
          expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
          for (
            var tabs = 0;
            !Focus.of(tester.element(find.text('Значения истории'))).hasFocus &&
                tabs < 40;
            tabs++
          ) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pumpAndSettle();
          }
          expect(
            Focus.of(tester.element(find.text('Значения истории'))).hasFocus,
            isTrue,
            reason: 'Disclosure must be reachable through Tab traversal',
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          final values = find.byKey(const ValueKey('metrics-history-values'));
          expect(values, findsOneWidget);
          expect(tester.getSize(values).height, lessThanOrEqualTo(280));
          final first = find.text(
            '2026-10-25T09:00:00.000Z UTC · CPU: 0% · RAM: нет данных · Диск /: 100%',
          );
          expect(first, findsOneWidget);
          final valueStyle = tester.widget<EditableText>(first).style;
          expect(
            MediaQuery.textScalerOf(tester.element(first))
                .scale(valueStyle.fontSize!),
            13 * scale,
          );
          await tester.ensureVisible(values);
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.textContaining('больше 15 секунд'),
            100,
            scrollable: find
                .descendant(of: values, matching: find.byType(Scrollable))
                .first,
          );
          expect(find.textContaining('больше 15 секунд'), findsOneWidget);
          // Revealing a row can also scroll the surrounding overview. Bring
          // the bounded list into its clipped viewport before the next drag.
          await tester.ensureVisible(values);
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.textContaining('время наблюдения повторилось'),
            100,
            scrollable: find
                .descendant(of: values, matching: find.byType(Scrollable))
                .first,
          );
          expect(
            find.textContaining('время наблюдения повторилось'),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('metrics-history-values-quality')),
              matching: find.text('Устаревшие данные'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byType(MetricsHistory),
              matching: find.textContaining('ssh:proc/stat+meminfo+net/dev+df'),
            ),
            findsOneWidget,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pumpAndSettle();
          expect(values, findsNothing);
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          expect(button.hitTestable(), findsOneWidget);
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(first, findsOneWidget);
          expect(calls, 0);
          expect(tester.takeException(), isNull);
        });
        testWidgets('bounded samples and gaps remain honest $scenario', (
          tester,
        ) async {
          _setFrame(tester, frame);
          for (final count in [0, 1, 120]) {
            await _pumpHistory(
              tester,
              theme,
              scale: scale,
              points: DesignServerFixtures.history(count: count),
            );
            final cpu = find.byKey(const ValueKey('metrics-history-plot-cpu'));
            expect(_circleCenters(tester, cpu), hasLength(count));
            final paths = _strokePaths(
              tester,
              cpu,
              theme.extension<BrandColors>()!['accent'],
            ).expand((path) => path.computeMetrics());
            expect(paths.length, count < 2 ? 0 : 1);
            if (count == 0)
              expect(find.text('Истории пока нет.'), findsOneWidget);
          }
          for (final invalid in <Object?>[null, -1, 101, 1.5, '10']) {
            await _pumpHistory(
              tester,
              theme,
              scale: scale,
              points: DesignServerFixtures.history(
                count: 3,
                overrides: {
                  1: {'cpuPercent': invalid},
                },
              ),
            );
            final palette = theme.extension<BrandColors>()!;
            final cpu = find.byKey(const ValueKey('metrics-history-plot-cpu'));
            expect(_circleCenters(tester, cpu), hasLength(2));
            expect(
              _strokePath(tester, cpu, palette['accent']).computeMetrics(),
              isEmpty,
            );
            expect(
              _strokePath(
                tester,
                find.byKey(const ValueKey('metrics-history-plot-memory')),
                palette['chart2'],
              ).computeMetrics(),
              isNotEmpty,
            );
            final disclosure = find.text('Значения истории');
            if (find
                .byKey(const ValueKey('metrics-history-values'))
                .evaluate()
                .isEmpty) {
              await tester.ensureVisible(disclosure);
              await tester.tap(disclosure);
              await tester.pumpAndSettle();
            }
            final missing = find.textContaining('CPU: нет данных');
            await _revealHistoryText(tester, missing);
            expect(missing, findsOneWidget);
            expect(
              find.text(
                'В истории есть пропуски значений; они не заменены нулями.',
              ),
              findsOneWidget,
            );
          }
          final missingField = Map<String, Object?>.of(
            DesignServerFixtures.point(),
          )..remove('cpuPercent');
          await _pumpHistory(
            tester,
            theme,
            scale: scale,
            points: [missingField],
          );
          await _revealHistoryText(
            tester,
            find.textContaining('CPU: нет данных'),
          );
          expect(find.textContaining('CPU: нет данных'), findsOneWidget);
          expect(
            _circleCenters(
              tester,
              find.byKey(const ValueKey('metrics-history-plot-cpu')),
            ),
            isEmpty,
          );
          final start = DateTime.parse(DesignServerFixtures.observedAt);
          for (final milliseconds in [15000, 15001, 0, -1]) {
            await _pumpHistory(
              tester,
              theme,
              scale: scale,
              points: [
                DesignServerFixtures.point(cpuPercent: 0),
                DesignServerFixtures.point(
                  time: start
                      .add(Duration(milliseconds: milliseconds))
                      .toIso8601String(),
                  cpuPercent: 100,
                ),
              ],
            );
            final cpu = find.byKey(const ValueKey('metrics-history-plot-cpu'));
            final points = _circleCenters(tester, cpu);
            expect(points, hasLength(2));
            expect(points[0].dy, 22);
            expect(points[1].dy, 3);
            expect(
              _strokePath(
                tester,
                cpu,
                theme.extension<BrandColors>()!['accent'],
              ).computeMetrics().length,
              milliseconds == 15000 ? 1 : 0,
            );
            await _revealHistoryText(tester, find.textContaining('CPU: 0%'));
            expect(find.textContaining('CPU: 0%'), findsOneWidget);
            await _revealHistoryText(tester, find.textContaining('CPU: 100%'));
            expect(find.textContaining('CPU: 100%'), findsOneWidget);
            final gap = switch (milliseconds) {
              15001 => 'больше 15 секунд',
              0 => 'время наблюдения повторилось',
              -1 => 'в обратном порядке',
              _ => null,
            };
            if (gap == null) {
              expect(
                find.textContaining('Разрыв перед наблюдением'),
                findsNothing,
              );
            } else {
              expect(find.textContaining(gap), findsOneWidget);
            }
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
  testWidgets(
    'expanded production history survives theme resize and text growth',
    (tester) async {
      _setFrame(tester, const Size(1100, 760));
      var calls = 0;
      void action() => calls++;
      await _pumpOverview(
        tester,
        BrandTheme.light,
        scale: 1,
        stale: false,
        onAction: action,
      );
      final button = find.text('Значения истории');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(MetricsHistory));
      for (final frame in const [
        Size(1100, 760),
        Size(800, 600),
        Size(390, 800),
        Size(360, 800),
      ]) {
        tester.view.physicalSize = frame;
        for (final theme in [BrandTheme.dark, BrandTheme.light]) {
          for (final scale in [2.0, 1.0]) {
            await _pumpOverview(
              tester,
              theme,
              scale: scale,
              stale: false,
              onAction: action,
            );
            expect(tester.state(find.byType(MetricsHistory)), same(state));
            final values = find.byKey(const ValueKey('metrics-history-values'));
            expect(values, findsOneWidget);
            expect(tester.getSize(values).height, lessThanOrEqualTo(280));
            expect(
              find.textContaining('2026-10-25T09:00:00.000Z UTC · CPU: 0%'),
              findsOneWidget,
            );
            expect(calls, 0);
            expect(tester.takeException(), isNull);
          }
        }
      }
    },
  );
  testWidgets('metric samples have keyboard-accessible text values', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: MetricsHistory(points: DesignServerFixtures.history()),
          ),
        ),
      ),
    );
    expect(find.text('Значения истории'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.textContaining('UTC'), findsWidgets);
    expect(find.textContaining('0%'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final frame in const [(1100.0, 300.0), (800.0, 270.0)]) {
    testWidgets('three 25px plots share a ${frame.$2}px block at ${frame.$1}', (
      tester,
    ) async {
      tester.view.physicalSize = Size(frame.$1, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpHistory(tester, BrandTheme.dark);

      final block = find.byKey(const ValueKey('metrics-history-plots'));
      expect(block, findsOneWidget);
      expect(tester.getSize(block).width, frame.$2);
      final bounds = [
        for (final series in ['cpu', 'memory', 'disk'])
          tester.getRect(find.byKey(ValueKey('metrics-history-plot-$series'))),
      ];
      for (final plot in bounds) {
        expect(plot.height, 25);
        expect(plot.bottom, bounds.first.bottom);
      }
      expect(bounds[0].right, lessThan(bounds[1].left));
      expect(bounds[1].right, lessThan(bounds[2].left));
      expect(tester.takeException(), isNull);
    });
  }

  for (final theme in [BrandTheme.light, BrandTheme.dark]) {
    testWidgets(
      '${theme.brightness.name} plots have exact colors and symbols',
      (tester) async {
        await _pumpHistory(tester, theme);
        final palette = theme.extension<BrandColors>()!;
        final cpu = find.byKey(const ValueKey('metrics-history-plot-cpu'));
        final memory = find.byKey(
          const ValueKey('metrics-history-plot-memory'),
        );
        final disk = find.byKey(const ValueKey('metrics-history-plot-disk'));
        expect(cpu, findsOneWidget);
        expect(memory, findsOneWidget);
        expect(disk, findsOneWidget);
        expect(
          tester.renderObject(cpu),
          paints
            ..path(color: palette['accent'], strokeWidth: 2)
            ..circle(color: palette['accent']),
        );
        expect(
          tester.renderObject(memory),
          paints
            ..path(color: palette['chart2'], strokeWidth: 2)
            ..rect(color: palette['chart2']),
        );
        expect(
          tester.renderObject(disk),
          paints
            ..path(color: palette['chart3'], strokeWidth: 2)
            ..path(color: palette['chart3'], style: PaintingStyle.fill),
        );
        for (final role in ['accent', 'chart2', 'chart3']) {
          final contrast = _contrast(palette[role], palette['surface']);
          expect(contrast, greaterThanOrEqualTo(3), reason: role);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'an inherited stale observation labels the history and its source',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ServerSystemSection(
                state: DesignServerFixtures.state(stale: true),
              ),
            ),
          ),
        ),
      );
      final history = find.byType(MetricsHistory);
      expect(
        find.descendant(of: history, matching: find.text('Устаревшие данные')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: history,
          matching: find.textContaining('ssh:proc/stat+meminfo+net/dev+df'),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: history,
          matching: find.textContaining(DesignServerFixtures.observedAt),
        ),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('current and stale legend strokes retain their patterns', (
    tester,
  ) async {
    for (final stale in [false, true]) {
      await _pumpHistory(tester, BrandTheme.dark, stale: stale);
      final palette = BrandTheme.dark.extension<BrandColors>()!;
      for (final entry in const {
        'cpu': 'accent',
        'memory': 'chart2',
        'disk': 'chart3',
      }.entries) {
        final path = _strokePath(
          tester,
          find.byKey(ValueKey('metrics-history-legend-${entry.key}')),
          palette[entry.value],
        );
        final lengths = path
            .computeMetrics()
            .map((metric) => metric.length)
            .toList();
        expect(
          lengths,
          stale || entry.key == 'memory'
              ? [6, 6, 6, 2]
              : entry.key == 'cpu'
              ? [32]
              : [2, 2, 2, 2, 2, 2],
        );
      }
      for (final label in ['CPU · %', 'RAM · %', 'Диск / · %']) {
        expect(find.text(label), findsOneWidget);
      }
      if (stale) expect(find.text('Устаревшие данные'), findsOneWidget);
    }
  });

  testWidgets(
    'all stale curves use 6/4 while current curves keep their patterns',
    (tester) async {
      for (final stale in [false, true]) {
        await _pumpHistory(
          tester,
          BrandTheme.dark,
          stale: stale,
          points: [
            DesignServerFixtures.point(),
            DesignServerFixtures.point(time: '2026-10-25T09:00:05.000Z'),
          ],
        );
        for (final entry in const {
          'cpu': 'accent',
          'memory': 'chart2',
          'disk': 'chart3',
        }.entries) {
          final metrics = _strokePath(
            tester,
            find.byKey(ValueKey('metrics-history-plot-${entry.key}')),
            BrandColors.dark[entry.value],
          ).computeMetrics().toList();
          if (!stale && entry.key == 'cpu') {
            expect(metrics, hasLength(1));
            continue;
          }
          final dash = !stale && entry.key == 'disk' ? 2.0 : 6.0;
          expect(metrics.length, greaterThan(2));
          for (var index = 0; index < metrics.length; index++) {
            expect(metrics[index].length, lessThanOrEqualTo(dash + 0.001));
            if (index + 1 < metrics.length) {
              expect(metrics[index].length, closeTo(dash, 0.001));
              final end = metrics[index]
                  .getTangentForOffset(metrics[index].length)!
                  .position;
              final next = metrics[index + 1].getTangentForOffset(0)!.position;
              expect((next - end).distance, closeTo(4, 0.001));
            }
          }
        }
      }
    },
  );

  testWidgets('text disclosure reports actual UTC values and time gaps', (
    tester,
  ) async {
    await _pumpHistory(
      tester,
      BrandTheme.dark,
      points: [
        DesignServerFixtures.point(cpuPercent: null),
        DesignServerFixtures.point(time: '2026-10-25T09:00:15.001Z'),
        DesignServerFixtures.point(time: DesignServerFixtures.observedAt),
      ],
    );
    await tester.tap(find.text('Значения истории'));
    await tester.pumpAndSettle();
    expect(find.textContaining('CPU: нет данных'), findsOneWidget);
    expect(find.textContaining('больше 15 секунд'), findsOneWidget);
    expect(find.textContaining('в обратном порядке'), findsOneWidget);
    expect(find.textContaining('2026-10-25T09:00:15.001Z UTC'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('metrics-history-values')))
          .height,
      lessThanOrEqualTo(280),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'zero and one samples never invent a line or another observation',
    (tester) async {
      for (final count in [0, 1]) {
        await _pumpHistory(
          tester,
          BrandTheme.light,
          points: DesignServerFixtures.history(count: count),
        );
        final cpu = find.byKey(const ValueKey('metrics-history-plot-cpu'));
        expect(_circleCenters(tester, cpu).length, count);
        final paths = _strokePaths(tester, cpu, BrandColors.light['accent']);
        expect(paths.expand((path) => path.computeMetrics()), isEmpty);
        if (count == 0) expect(find.text('Истории пока нет.'), findsOneWidget);
        if (count == 1) {
          await tester.tap(find.text('Значения истории'));
          await tester.pumpAndSettle();
          expect(find.textContaining('CPU: 0%'), findsOneWidget);
          expect(
            find.textContaining('2026-10-25T09:00:00.000Z UTC'),
            findsOneWidget,
          );
        }
        expect(find.textContaining('два наблюдения'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('missing and invalid percentages break only their own series', (
    tester,
  ) async {
    for (final invalid in <Object?>[null, -1, 101, 1.5, '10']) {
      await _pumpHistory(
        tester,
        BrandTheme.dark,
        points: DesignServerFixtures.history(
          count: 3,
          overrides: {
            1: {'cpuPercent': invalid},
          },
        ),
      );
      final cpu = find.byKey(const ValueKey('metrics-history-plot-cpu'));
      expect(
        _strokePath(tester, cpu, BrandColors.dark['accent']).computeMetrics(),
        isEmpty,
        reason: '$invalid',
      );
      expect(_circleCenters(tester, cpu), hasLength(2), reason: '$invalid');
      expect(
        _strokePath(
          tester,
          find.byKey(const ValueKey('metrics-history-plot-memory')),
          BrandColors.dark['chart2'],
        ).computeMetrics(),
        isNotEmpty,
      );
      if (find.textContaining('CPU: нет данных').evaluate().isEmpty) {
        await tester.tap(find.text('Значения истории'));
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('CPU: нет данных'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('15000ms joins but 15001ms duplicate and reversed times break', (
    tester,
  ) async {
    final start = DateTime.parse(DesignServerFixtures.observedAt);
    for (final duration in [15000, 15001, 0, -1]) {
      await _pumpHistory(
        tester,
        BrandTheme.dark,
        points: [
          DesignServerFixtures.point(cpuPercent: 20),
          DesignServerFixtures.point(
            time: start.add(Duration(milliseconds: duration)).toIso8601String(),
            cpuPercent: 20,
          ),
        ],
      );
      final cpu = find.byKey(const ValueKey('metrics-history-plot-cpu'));
      expect(
        _strokePath(
          tester,
          cpu,
          BrandColors.dark['accent'],
        ).computeMetrics().length,
        duration == 15000 ? 1 : 0,
      );
      expect(_circleCenters(tester, cpu), hasLength(2));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('source order and the 120 sample bound are preserved in painting', (
    tester,
  ) async {
    final start = DateTime.parse(DesignServerFixtures.observedAt);
    await _pumpHistory(
      tester,
      BrandTheme.dark,
      points: [
        for (final seconds in [0, 10, 5])
          DesignServerFixtures.point(
            time: start.add(Duration(seconds: seconds)).toIso8601String(),
          ),
      ],
    );
    final cpu = find.byKey(const ValueKey('metrics-history-plot-cpu'));
    final points = _circleCenters(tester, cpu);
    expect(points, hasLength(3));
    expect(points[0].dx, lessThan(points[2].dx));
    expect(points[2].dx, lessThan(points[1].dx));
    expect(points[0].dx, 3);
    expect(points[1].dx, tester.getSize(cpu).width - 3);
    await tester.tap(find.text('Значения истории'));
    await tester.pumpAndSettle();
    final textRows = tester
        .widgetList<SelectableText>(
          find.descendant(
            of: find.byKey(const ValueKey('metrics-history-values')),
            matching: find.byType(SelectableText),
          ),
        )
        .map((text) => text.data)
        .toList();
    expect(textRows, [
      for (final seconds in [0, 10, 5])
        '${start.add(Duration(seconds: seconds)).toIso8601String()} UTC · CPU: 25% · RAM: 50% · Диск /: 75%',
    ]);
    await _pumpHistory(
      tester,
      BrandTheme.dark,
      points: [
        ...DesignServerFixtures.history(count: 120),
        DesignServerFixtures.point(),
      ],
    );
    expect(_circleCenters(tester, cpu), hasLength(120));
    final values = tester.widget<ListView>(
      find.byKey(const ValueKey('metrics-history-values')),
    );
    expect(values.childrenDelegate.estimatedChildCount, 120);
  });

  testWidgets(
    'invalid time stays missing and offset text is normalized to UTC',
    (tester) async {
      await _pumpHistory(
        tester,
        BrandTheme.dark,
        points: [
          DesignServerFixtures.point(time: '2026-10-25T12:00:00.000+03:00'),
          DesignServerFixtures.point(time: 'invalid-time'),
          DesignServerFixtures.point(time: '2026-10-25T09:00:05.000Z'),
        ],
      );
      final cpu = find.byKey(const ValueKey('metrics-history-plot-cpu'));
      expect(_circleCenters(tester, cpu), hasLength(2));
      expect(
        _strokePath(tester, cpu, BrandColors.dark['accent']).computeMetrics(),
        isEmpty,
      );
      await tester.tap(find.text('Значения истории'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('2026-10-25T09:00:00.000Z UTC'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Время не указано · CPU: 25%'),
        findsOneWidget,
      );
      expect(find.textContaining('время не указано'), findsNWidgets(2));
      expect(find.textContaining('+03:00'), findsNothing);
      expect(find.textContaining('invalid-time'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [1100.0, 800.0, 390.0, 360.0]) {
    testWidgets(
      'overview action and graph placement follows the ${width}px frame',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var calls = 0;
        void action() => calls++;
        await tester.pumpWidget(
          MaterialApp(
            theme: BrandTheme.dark,
            home: Scaffold(
              body: SingleChildScrollView(
                child: ServerOverviewSection(
                  state: DesignServerFixtures.state(),
                  connection: ServerConnectionSection(
                    connection: DesignServerFixtures.connection(),
                    trust: DesignServerFixtures.trust(),
                    busy: false,
                    error: 'TRUST_CHANGED',
                    hasTrustChallenge: true,
                    onRefresh: action,
                    onProbeTrust: action,
                    onConfirmTrust: action,
                    onConnect: action,
                    onDisconnect: action,
                    onRevokeTrust: action,
                    onCancel: action,
                  ),
                ),
              ),
            ),
          ),
        );
        final plots = tester.getRect(
          find.byKey(const ValueKey('metrics-history-plots')),
        );
        final actions = tester.getRect(
          find.byKey(const ValueKey('server-overview-actions')),
        );
        final error = tester.getRect(
          find.byKey(const ValueKey('server-overview-error')),
        );
        expect(error.bottom, lessThan(plots.top));
        expect(error.bottom, lessThan(actions.top));
        if (width > 520) {
          expect(actions.bottom, closeTo(plots.bottom, 0.01));
          expect(actions.right, lessThan(plots.left));
        } else {
          expect(plots.bottom, lessThan(actions.top));
        }
        expect(calls, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _pumpHistory(
  WidgetTester tester,
  ThemeData theme, {
  List<Object?>? points,
  bool stale = false,
  double scale = 1,
}) => tester.pumpWidget(
  MaterialApp(
    theme: theme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: MetricsHistory(
          points: points ?? DesignServerFixtures.history(),
          stale: stale,
        ),
      ),
    ),
  ),
);

Future<void> _revealHistoryText(WidgetTester tester, Finder text) async {
  final values = find.byKey(const ValueKey('metrics-history-values'));
  await tester.ensureVisible(values);
  await tester.pumpAndSettle();
  final scroll = find
      .descendant(of: values, matching: find.byType(Scrollable))
      .first;
  // A new projection can retain the previous bounded list's scroll position.
  // Return to its beginning before seeking a sample that may not be built yet.
  await tester.drag(scroll, const Offset(0, 2000));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(text, 100, scrollable: scroll);
}

const _seriesExpectations =
    <({String id, String label, String role, String symbol, double? dash})>[
      (id: 'cpu', label: 'CPU', role: 'accent', symbol: 'круг', dash: null),
      (id: 'memory', label: 'RAM', role: 'chart2', symbol: 'квадрат', dash: 6),
      (
        id: 'disk',
        label: 'Диск /',
        role: 'chart3',
        symbol: 'треугольник',
        dash: 2,
      ),
    ];

void _setFrame(WidgetTester tester, Size frame) {
  tester.view.physicalSize = frame;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpOverview(
  WidgetTester tester,
  ThemeData theme, {
  required double scale,
  required bool stale,
  required VoidCallback onAction,
  List<Object?>? points,
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
      servers: SingleChildScrollView(
        child: ServerOverviewSection(
          state: DesignServerFixtures.state(stale: stale, points: points),
          connection: ServerConnectionSection(
            connection: DesignServerFixtures.connection(),
            trust: DesignServerFixtures.trust(),
            busy: false,
            error: 'TRUST_CHANGED',
            hasTrustChallenge: true,
            onRefresh: onAction,
            onProbeTrust: onAction,
            onConfirmTrust: onAction,
            onConnect: onAction,
            onDisconnect: onAction,
            onRevokeTrust: onAction,
            onCancel: onAction,
          ),
        ),
      ),
    ),
  ),
);

void _expectSymbols(
  WidgetTester tester,
  Finder finder,
  String series,
  Color color, {
  required int count,
}) {
  var symbols = 0;
  expect(
    tester.renderObject(finder),
    paints..everything((method, arguments) {
      final isSymbol = switch (series) {
        'cpu' => method == #drawCircle,
        'memory' => method == #drawRect,
        _ =>
          method == #drawPath &&
              (arguments[1] as Paint).style == PaintingStyle.fill,
      };
      if (isSymbol) {
        symbols++;
        final paint = arguments.last as Paint;
        expect(paint.color.toARGB32(), color.toARGB32());
      }
      return true;
    }),
  );
  expect(symbols, count);
}

void _expectPattern(Path path, double? dash) {
  final metrics = path.computeMetrics().toList();
  expect(metrics, isNotEmpty);
  if (dash == null) {
    expect(metrics, hasLength(1));
    return;
  }
  for (var index = 0; index < metrics.length; index++) {
    expect(metrics[index].length, lessThanOrEqualTo(dash + .001));
    if (index + 1 < metrics.length) {
      expect(metrics[index].length, closeTo(dash, .001));
      final end = metrics[index]
          .getTangentForOffset(metrics[index].length)!
          .position;
      final next = metrics[index + 1].getTangentForOffset(0)!.position;
      expect((next - end).distance, closeTo(4, .001));
    }
  }
}

List<Path> _strokePaths(WidgetTester tester, Finder finder, Color color) {
  final paths = <Path>[];
  expect(
    tester.renderObject(finder),
    paints..everything((method, arguments) {
      if (method == #drawPath &&
          (arguments[1] as Paint).style == PaintingStyle.stroke &&
          (arguments[1] as Paint).color.toARGB32() == color.toARGB32()) {
        expect((arguments[1] as Paint).strokeWidth, 2);
        paths.add(arguments[0] as Path);
      }
      return true;
    }),
  );
  return paths;
}

Path _strokePath(WidgetTester tester, Finder finder, Color color) =>
    _strokePaths(tester, finder, color).single;

List<Offset> _circleCenters(WidgetTester tester, Finder finder) {
  final centers = <Offset>[];
  expect(
    tester.renderObject(finder),
    paints..everything((method, arguments) {
      if (method == #drawCircle) centers.add(arguments[0] as Offset);
      return true;
    }),
  );
  return centers;
}

double _contrast(Color a, Color b) {
  final first = a.computeLuminance(), second = b.computeLuminance();
  return first > second
      ? (first + 0.05) / (second + 0.05)
      : (second + 0.05) / (first + 0.05);
}
