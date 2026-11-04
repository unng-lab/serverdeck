import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_components.dart';

void main() {
  testWidgets(
    'C21 icon metric exposes public value and reason through tooltip',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.dark,
          home: const Scaffold(
            body: DeckMetric(
              compact: true,
              icon: Icons.memory_outlined,
              label: 'Процессор (CPU)',
              value: '95,0',
              unit: '%',
              contextLabel: 'Порог достигнут',
              tone: DeckTone.error,
            ),
          ),
        ),
      );
      expect(find.text('95,0 %'), findsOneWidget);
      expect(find.text('Процессор (CPU)'), findsNothing);
      expect(
        find.byTooltip('Процессор (CPU): 95,0 %. Порог достигнут'),
        findsOneWidget,
      );
    },
  );
  testWidgets('C10 icon tooltip follows keyboard focus', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.dark,
        home: Scaffold(
          body: Column(
            children: [
              const DeckStatus(
                iconOnly: true,
                icon: Icons.link_off,
                label: 'Связь потеряна',
                tone: DeckTone.error,
              ),
              TextButton(onPressed: () {}, child: const Text('Other')),
            ],
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(find.text('Связь потеряна'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
  });
  for (final compact in [false, true]) {
    testWidgets('C21 compact=$compact preserves value and state inputs', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.dark,
          home: Scaffold(
            body: DeckMetric(
              compact: compact,
              label: 'Synthetic CPU',
              value: '95,0',
              unit: '%',
              contextLabel: 'Порог достигнут',
              tone: DeckTone.error,
            ),
          ),
        ),
      );
      expect(find.text('Synthetic CPU'), findsOneWidget);
      expect(find.text('95,0 %'), findsOneWidget);
      expect(find.text('Порог достигнут'), findsOneWidget);
    });
  }
  testWidgets('C21 compact missing value preserves unknown state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DeckMetric(compact: true, label: 'Synthetic RAM')),
      ),
    );
    expect(find.text('Нет данных'), findsOneWidget);
  });
}
