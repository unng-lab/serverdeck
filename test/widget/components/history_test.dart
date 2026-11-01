import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/ui/deck_components.dart';

import '../../support/component_cases.dart';

void main() {
  Map<String, Object?> point(int milliseconds, {Object? cpu = 0}) => {
    'receivedAt': DateTime.utc(
      2026,
      11,
      1,
    ).add(Duration(milliseconds: milliseconds)).toIso8601String(),
    'cpuPercent': cpu,
    'memoryUsedPercent': 40,
    'rootDiskUsedPercent': 50,
  };
  for (final boundary in [15000, 15001, 0, -1]) {
    testWidgets('history preserves source order and gap boundary $boundary', (
      tester,
    ) async {
      await tester.pumpWidget(
        componentHarness(
          DeckHistory(
            points: [point(0), point(boundary, cpu: null)],
            quality: 'known',
          ),
        ),
      );
      await tester.tap(find.textContaining('Значения истории'));
      await tester.pumpAndSettle();
      expect(find.textContaining('CPU: 0%'), findsOneWidget);
      expect(find.textContaining('CPU: нет данных'), findsOneWidget);
      expect(
        find.textContaining('Разрыв перед наблюдением'),
        boundary == 15000 ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), null);
    });
  }
  testWidgets(
    'history bounds 121 samples at 120 and keeps unknown separate from zero',
    (tester) async {
      await tester.pumpWidget(
        componentHarness(
          DeckHistory(
            points: List.generate(121, (i) => point(i * 1000)),
            quality: 'incomplete',
          ),
        ),
      );
      await tester.tap(find.textContaining('Значения истории'));
      await tester.pumpAndSettle();
      final list = tester.widget<ListView>(
        find.byKey(const ValueKey('metrics-history-values')),
      );
      expect(
        (list.childrenDelegate as SliverChildBuilderDelegate).childCount,
        120,
      );
      expect(find.text('Неполные данные'), findsWidgets);
      expect(tester.takeException(), null);
    },
  );
}
