import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/servers/server_compositions.dart';
import 'package:serverdeck/servers/server_sections.dart';
import 'package:serverdeck/theme/brand_assets.dart';
import 'package:serverdeck/theme/brand_theme.dart';

import '../support/design_host.dart' show loadDesignFonts;
import '../support/design_server_fixtures.dart';

void main() {
  for (final width in [
    1100.0,
    800.0,
    390.0,
    360.0,
    960.0,
    961.0,
    520.0,
    521.0,
  ]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('T226 resource value faces and units $width $dark $scale', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          for (final mode in ['percent', 'bytes', 'unknown']) {
            final value = <String, Object?>{
              'cpuPercent': 25,
              'memory': <String, Object?>{'usedPercent': 50},
              'rootDisk': <String, Object?>{'usedPercent': 75},
            };
            if (mode == 'bytes') {
              (value['memory'] as Map<String, Object?>).addAll(
                <String, Object?>{
                  'usedBytes': 8 * 1073741824,
                  'totalBytes': 16 * 1073741824,
                },
              );
            }
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
                    child: ServerResourceCards(
                      state: mode == 'unknown'
                          ? null
                          : {
                              'metrics': {'value': value},
                              'history': <Object?>[],
                            },
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final metrics = find.byWidgetPredicate(
              (w) =>
                  w is Text && w.textSpan != null && w.semanticsLabel != null,
            );
            expect(metrics, findsNWidgets(3));
            for (final element in metrics.evaluate()) {
              final text = element.widget as Text;
              final size = width <= 520 || width > 960 ? 26.0 : 24.0;
              final line = width <= 520 ? 34.0 : 32.0;
              expect(text.style!.fontFamily, BrandAssets.semiboldFamily);
              expect(text.style!.fontWeight, BrandTypography.semiboldWeight);
              expect(
                text.style!.fontVariations,
                BrandTypography.semiboldVariations,
              );
              expect(text.style!.fontSize, size);
              expect(text.style!.height, closeTo(line / size, .0001));
              final span = text.textSpan! as TextSpan;
              if (mode == 'unknown') {
                expect(text.semanticsLabel, '—');
                expect(span.children, isEmpty);
              } else {
                final unit = span.children!.last as TextSpan;
                expect(unit.style!.fontFamily, BrandTypography.body.fontFamily);
                expect(unit.style!.fontWeight, FontWeight.w400);
                expect(unit.style!.fontSize, 12);
                expect(unit.style!.height, closeTo(20 / 12, .0001));
                expect(unit.style!.letterSpacing, 0);
                expect(
                  unit.style!.color,
                  (dark ? BrandColors.dark : BrandColors.light)['muted'],
                );
                final gap = find.descendant(
                  of: find.byWidget(text),
                  matching: find.byWidgetPredicate(
                    (w) => w is SizedBox && w.width == 4,
                  ),
                );
                expect(gap, findsOneWidget);
                expect(tester.getSize(gap).width, 4);
              }
            }
            if (mode != 'unknown') {
              expect(
                find.byWidgetPredicate(
                  (w) => w is Text && w.semanticsLabel == '25 %',
                ),
                findsOneWidget,
              );
              expect(
                find.byWidgetPredicate(
                  (w) => w is Text && w.semanticsLabel == '75 %',
                ),
                findsOneWidget,
              );
              expect(
                find.byWidgetPredicate(
                  (w) =>
                      w is Text &&
                      w.semanticsLabel ==
                          (mode == 'bytes' ? '8,0 / 16,0 ГБ' : '50 %'),
                ),
                findsOneWidget,
              );
            }
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  setUpAll(loadDesignFonts);
  for (final height in [166.0, 35.0]) {
    for (final field in [
      'cpuPercent',
      'memoryUsedPercent',
      'rootDiskUsedPercent',
    ]) {
      testWidgets('new chart $field/$height breaks every invalid percentage', (
        tester,
      ) async {
        for (final invalid in <Object?>[
          null,
          -1,
          101,
          1.5,
          1.0,
          '10',
          true,
          const <String, Object?>{},
          const <Object?>[],
        ]) {
          final rows = _rows(field, invalid);
          await _mountChart(tester, rows, field: field, height: height);
          final paint = _paint(tester, field);
          expect(paint.strokes, isEmpty, reason: '$field: $invalid');
          expect(paint.markers, 2, reason: '$field: $invalid');
          expect(tester.takeException(), isNull);
        }
      });

      testWidgets('new chart $field/$height retains valid zero and hundred', (
        tester,
      ) async {
        final rows = _rows(field, 100)..first[field] = 0;
        await _mountChart(tester, rows, field: field, height: height);
        final paint = _paint(tester, field);
        expect(paint.strokes, isNotEmpty);
        expect(paint.markers, height < 100 ? 1 : 0);
        final bounds = paint.strokes
            .map((path) => path.getBounds())
            .reduce((a, b) => a.expandToInclude(b));
        // Dashes may stop just before an extremum. Their full geometry must
        // still cover the valid range and remain within its actual plot.
        expect(bounds.top, inInclusiveRange(0, 6));
        expect(
          bounds.bottom,
          inInclusiveRange(paint.size.height - 6, paint.size.height + .001),
        );
        final before = paint.strokes.map((path) => path.getBounds()).toList();
        await tester.pump(const Duration(seconds: 30));
        expect(
          _paint(
            tester,
            field,
          ).strokes.map((path) => path.getBounds()).toList(),
          before,
        );
      });
    }
  }

  testWidgets('new chart keeps source time gaps and its 120 point bound', (
    tester,
  ) async {
    for (final delta in [15000, 15001, 0, -1]) {
      final rows = _rows('cpuPercent', 15).take(2).toList();
      rows[1]['receivedAt'] = DateTime.utc(
        2026,
        10,
        25,
        9,
      ).add(Duration(milliseconds: delta)).toIso8601String();
      await _mountChart(tester, rows);
      final paint = _paint(tester, 'cpuPercent');
      expect(paint.markers, delta == 15000 ? 0 : 2);
      expect(paint.strokes, delta == 15000 ? isNotEmpty : isEmpty);
    }
    final invalidTime = _rows('cpuPercent', 15);
    invalidTime[1]['receivedAt'] = 'not-a-time';
    await _mountChart(tester, invalidTime);
    expect(_paint(tester, 'cpuPercent').strokes, isEmpty);
    expect(_paint(tester, 'cpuPercent').markers, 2);
    final reversed = _rows('cpuPercent', 15);
    reversed[1]['receivedAt'] = '2026-10-25T09:00:10.000Z';
    reversed[2]['receivedAt'] = '2026-10-25T09:00:05.000Z';
    await _mountChart(tester, reversed);
    final sourceOrder = _paint(tester, 'cpuPercent');
    expect(sourceOrder.strokes, hasLength(1));
    expect(sourceOrder.markers, 1);
    expect(
      sourceOrder.centers.single.dx,
      closeTo(sourceOrder.size.width / 2, .001),
    );
    final rows = [
      for (var index = 0; index < 121; index++)
        {
          'receivedAt': DateTime.utc(
            2026,
            10,
            25,
            9,
          ).add(Duration(seconds: index)).toIso8601String(),
          'cpuPercent': index == 120 ? 100 : 10,
        },
    ];
    await _mountChart(tester, rows);
    expect(_paint(tester, 'cpuPercent').strokes.single.getBounds().height, 0);
  });

  testWidgets('new stale charts retain series roles, dashes and lone markers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final field in [
        'cpuPercent',
        'memoryUsedPercent',
        'rootDiskUsedPercent',
      ]) {
        for (final height in [166.0, 35.0]) {
          await _mountChart(
            tester,
            _rows(field, 15),
            field: field,
            height: height,
            stale: true,
          );
          final painted = _paint(tester, field);
          expect(painted.strokes, isNotEmpty);
          for (final path in painted.strokes) {
            for (final metric in path.computeMetrics()) {
              expect(metric.length, lessThanOrEqualTo(6.001));
            }
          }
          expect(
            find.bySemanticsLabel(
              RegExp('История $field.*Сохранённые устаревшие данные'),
            ),
            findsOneWidget,
          );
          await _mountChart(
            tester,
            _rows(field, 15).take(1).toList(),
            field: field,
            height: height,
            stale: true,
          );
          final lone = _paint(tester, field);
          expect(lone.strokes, isEmpty);
          expect(lone.markers, 1);
        }
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'real overview main and mini charts agree with accessible values',
    (tester) async {
      final points = _rows('cpuPercent', 1.5);
      var effects = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ServerOverviewSection(
                profile: DesignServerFixtures.profile(),
                // Exercise presentation's invalid-value boundary directly; a
                // fractional raw point is deliberately not a valid wire DTO.
                state: {...DesignServerFixtures.state(), 'history': points},
                connection: ServerConnectionSection(
                  connection: DesignServerFixtures.connection(),
                  trust: DesignServerFixtures.trust(),
                  busy: false,
                  error: null,
                  hasTrustChallenge: false,
                  onRefresh: () => effects++,
                  onProbeTrust: () => effects++,
                  onConfirmTrust: () => effects++,
                  onConnect: () => effects++,
                  onDisconnect: () => effects++,
                  onRevokeTrust: () => effects++,
                  onCancel: () => effects++,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final charts = find.byType(ServerObservationChart);
      expect(charts, findsNWidgets(4));
      for (final chart in charts.evaluate()) {
        final widget = chart.widget as ServerObservationChart;
        final paint = _paint(
          tester,
          widget.field,
          chart: find.byWidget(widget),
        );
        if (widget.field == 'cpuPercent') {
          expect(paint.strokes, isEmpty);
          expect(paint.markers, 2);
        } else {
          expect(paint.strokes, isNotEmpty);
        }
      }
      final disclose = find.widgetWithText(TextButton, 'Значения истории');
      await tester.ensureVisible(disclose);
      await tester.tap(disclose);
      await tester.pumpAndSettle();
      expect(
        find.text(
          '2026-10-25T09:00:05.000Z UTC · CPU: нет данных · RAM: 30% · Диск /: 40%',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(effects, 0);
    },
  );
}

List<Map<String, Object?>> _rows(String field, Object? middle) => [
  for (var index = 0; index < 3; index++)
    {
      'receivedAt': DateTime.utc(
        2026,
        10,
        25,
        9,
      ).add(Duration(seconds: index * 5)).toIso8601String(),
      'cpuPercent': 20,
      'memoryUsedPercent': 30,
      'rootDiskUsedPercent': 40,
      field: index == 1 ? middle : (index == 0 ? 10 : 20),
    },
];

Future<void> _mountChart(
  WidgetTester tester,
  List<Map<String, Object?>> rows, {
  String field = 'cpuPercent',
  double height = 166,
  bool stale = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: BrandTheme.dark,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: ServerObservationChart(
              rows: rows,
              field: field,
              height: height,
              role: field == 'cpuPercent'
                  ? 'accent'
                  : field == 'memoryUsedPercent'
                  ? 'chart2'
                  : 'chart3',
              stale: stale,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

({List<Path> strokes, int markers, Size size, List<Offset> centers}) _paint(
  WidgetTester tester,
  String field, {
  Finder? chart,
}) {
  final paths = <Path>[];
  final centers = <Offset>[];
  var markers = 0;
  final chartFinder = chart ?? find.byType(ServerObservationChart);
  final chartWidget = tester.widget<ServerObservationChart>(chartFinder);
  final color = BrandTheme.dark.extension<BrandColors>()![chartWidget.role];
  final finder = find.descendant(
    of: chartFinder,
    matching: find.byType(CustomPaint),
  );
  expect(
    tester.renderObject(finder),
    paints..everything((method, arguments) {
      if (arguments.isNotEmpty && arguments.last is Paint) {
        final paint = arguments.last as Paint;
        if (paint.color.toARGB32() != color.toARGB32()) return true;
        if (method == #drawPath && paint.style == PaintingStyle.stroke) {
          paths.add(arguments.first as Path);
        }
        if ((field == 'cpuPercent' && method == #drawCircle) ||
            (field == 'memoryUsedPercent' && method == #drawRect) ||
            (field == 'rootDiskUsedPercent' &&
                method == #drawPath &&
                paint.style == PaintingStyle.fill)) {
          markers++;
          if (method == #drawCircle) centers.add(arguments.first as Offset);
        }
      }
      return true;
    }),
  );
  return (
    strokes: paths,
    markers: markers,
    size: tester.getSize(finder),
    centers: centers,
  );
}
