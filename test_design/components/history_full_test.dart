import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/ui/deck_components.dart';

import '../support/component_cases.dart';

final _end = DateTime.utc(2026, 11, 4, 12);
Map<String, Object?> _row(
  int seconds, {
  Object? cpu = 25,
  Object? memory = 50,
  bool gap = false,
}) => {
  'receivedAt': _end.subtract(Duration(seconds: seconds)).toIso8601String(),
  'cpuPercent': cpu,
  'memoryUsedPercent': memory,
  'rootDiskUsedPercent': 75,
  'breakBefore': gap,
};
Widget _charts(List<Object?> points, {String? quality}) => componentHarness(
  DeckHistory(
    points: points,
    fullSize: true,
    windowEnd: _end,
    maxPoints: 720,
    periodLabel: 'Последний час',
    quality: quality,
  ),
);

class _ChartCanvas extends Fake implements Canvas {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
  final strokes = <Path>[];
  int dots = 0;
  @override
  void drawPath(Path path, Paint paint) {
    if (paint.style == PaintingStyle.stroke && paint.strokeWidth == 2)
      strokes.add(Path.from(path));
  }

  @override
  void drawCircle(Offset center, double radius, Paint paint) {
    dots++;
  }
}

void main() {
  testWidgets(
    'C22 full charts use available width and readable height with fixed hour range',
    (tester) async {
      await tester.pumpWidget(_charts([_row(30), _row(0)]));
      for (final id in ['cpu', 'memory', 'disk']) {
        final plot = find.byKey(ValueKey('resource-plot-$id'));
        expect(tester.getSize(plot).width, greaterThan(600));
        expect(tester.getSize(plot).height, greaterThanOrEqualTo(220));
        final dynamic painter = tester.widget<CustomPaint>(plot).painter;
        expect(
          painter.end - painter.start,
          const Duration(hours: 1).inMilliseconds,
        );
        expect(painter.end, _end.millisecondsSinceEpoch);
      }
      expect(find.text('Время, UTC'), findsNWidgets(3));
      expect(find.text('Порог 90%'), findsNWidgets(3));
      expect(find.text('Качество истории не указано'), findsNothing);
    },
  );

  testWidgets(
    'C22 hover and keyboard select real UTC measurements across three series',
    (tester) async {
      await tester.pumpWidget(
        _charts([_row(5, cpu: 12.5, memory: null), _row(0, cpu: 89.95)]),
      );
      final plot = find.byKey(const ValueKey('resource-plot-cpu'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      await mouse.moveTo(
        tester.getTopLeft(plot) + Offset(tester.getSize(plot).width - 12, 80),
      );
      await tester.pump();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('resource-reading-cpu')))
            .data,
        contains('Выбранный замер: 12:00:00 UTC · 89,95%'),
      );
      await tester.tap(plot);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('resource-value-cpu')))
            .data,
        '12,5%',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('resource-value-memory')))
            .data,
        'Нет данных',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('resource-reading-disk')))
            .data,
        contains('11:59:55 UTC · 75%'),
      );
      await mouse.removePointer();
    },
  );

  testWidgets(
    'C22 line and fill stop at session gaps, nulls and invalid time',
    (tester) async {
      await tester.pumpWidget(
        _charts([_row(20), _row(15), _row(10, gap: true), _row(5)]),
      );
      var canvas = _ChartCanvas();
      tester
          .widget<CustomPaint>(find.byKey(const ValueKey('resource-plot-cpu')))
          .painter!
          .paint(canvas, const Size(700, 250));
      expect(canvas.strokes, hasLength(2));
      expect(
        canvas.strokes[0].getBounds().right,
        lessThan(canvas.strokes[1].getBounds().left),
      );
      await tester.pumpWidget(
        _charts([
          _row(20),
          _row(15),
          _row(10, cpu: null),
          _row(5),
          {..._row(0), 'receivedAt': 'invalid'},
        ]),
      );
      canvas = _ChartCanvas();
      tester
          .widget<CustomPaint>(find.byKey(const ValueKey('resource-plot-cpu')))
          .painter!
          .paint(canvas, const Size(700, 250));
      expect(canvas.strokes, hasLength(1));
      expect(
        canvas.dots,
        1,
      ); // Isolated observation remains a dot, not a fabricated line.
    },
  );

  for (final dark in [true, false]) {
    testWidgets('C22 full empty and quality states use shared theme ($dark)', (
      tester,
    ) async {
      await tester.pumpWidget(
        componentHarness(
          DeckHistory(
            points: const [],
            fullSize: true,
            windowEnd: _end,
            periodLabel: 'Последний час',
          ),
          dark: dark,
        ),
      );
      expect(find.text('Истории пока нет.'), findsOneWidget);
      expect(find.text('Нет данных за последний час'), findsNWidgets(3));
      await tester.pumpWidget(
        componentHarness(
          DeckHistory(
            points: const [],
            fullSize: true,
            windowEnd: _end,
            quality: 'denied',
          ),
          dark: dark,
        ),
      );
      expect(find.text('Недостаточно прав'), findsOneWidget);
    });
  }
}
