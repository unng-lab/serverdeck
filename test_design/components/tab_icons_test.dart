import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_components.dart';

void main() {
  testWidgets('C16 icons retain labels, tooltips and selected action', (
    tester,
  ) async {
    int? requested;
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.dark,
        home: Scaffold(
          body: DeckTabs(
            labels: const ['Обзор', 'Журнал'],
            icons: const [Icons.apps_outlined, Icons.description_outlined],
            selected: 0,
            onSelected: (value) => requested = value,
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.apps_outlined), findsOneWidget);
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    expect(find.text('Обзор'), findsOneWidget);
    expect(find.byTooltip('Журнал'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Обзор'),
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.selected == true,
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Журнал'));
    await tester.pumpAndSettle();
    expect(requested, 1);
  });

  testWidgets('C16 disabled icon tabs retain description without dispatch', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.dark,
        home: const Scaffold(
          body: DeckTabs(
            labels: ['Обзор'],
            icons: [Icons.apps_outlined],
            selected: 0,
            onSelected: null,
          ),
        ),
      ),
    );
    expect(find.byTooltip('Обзор'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });
}
