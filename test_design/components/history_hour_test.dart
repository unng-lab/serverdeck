import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/ui/deck_components.dart';

import '../support/component_cases.dart';

void main() {
  testWidgets(
    'C22 hour variant retains fractional values and explicit segment gap',
    (tester) async {
      await tester.pumpWidget(
        componentHarness(
          DeckHistory(
            maxPoints: 720,
            periodLabel: 'Последний час',
            points: [
              {
                'receivedAt': '2026-11-04T10:00:00Z',
                'cpuPercent': 89.95,
                'memoryUsedPercent': 0,
                'rootDiskUsedPercent': 100,
              },
              {
                'receivedAt': '2026-11-04T10:00:05Z',
                'cpuPercent': 0,
                'memoryUsedPercent': null,
                'rootDiskUsedPercent': 100,
                'breakBefore': true,
              },
            ],
          ),
        ),
      );
      await tester.tap(find.text('Значения истории'));
      await tester.pumpAndSettle();
      expect(find.textContaining('CPU: 89.95%'), findsOneWidget);
      expect(find.textContaining('новый период наблюдения'), findsOneWidget);
      expect(find.textContaining('RAM: нет данных'), findsOneWidget);
    },
  );
  for (final count in [0, 1, 720, 721]) {
    testWidgets('C22 bounds $count input points to720', (tester) async {
      await tester.pumpWidget(
        componentHarness(
          DeckHistory(
            maxPoints: 720,
            periodLabel: 'Последний час',
            points: [
              for (var i = 0; i < count; i++)
                {
                  'receivedAt': DateTime.utc(
                    2026,
                    11,
                    4,
                  ).add(Duration(seconds: i * 5)).toIso8601String(),
                  'cpuPercent': 12.5,
                  'memoryUsedPercent': 50,
                  'rootDiskUsedPercent': 0,
                },
            ],
          ),
        ),
      );
      if (count == 0) expect(find.text('Истории пока нет.'), findsOneWidget);
      await tester.tap(find.text('Значения истории'));
      await tester.pumpAndSettle();
      final values = tester.widget<ListView>(
        find.byKey(const ValueKey('metrics-history-values')),
      );
      expect(
        values.childrenDelegate.estimatedChildCount,
        count > 720 ? 720 : count,
      );
    });
  }
}
