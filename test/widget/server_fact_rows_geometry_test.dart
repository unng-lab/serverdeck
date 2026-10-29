import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/servers/server_compositions.dart';
import 'package:serverdeck/theme/brand_theme.dart';

import '../support/design_fonts.dart';

void main() {
  setUpAll(loadDesignFonts);
  for (final frame in const [
    Size(1100, 760),
    Size(800, 600),
    Size(390, 800),
    Size(360, 800),
  ]) {
    for (final dark in [false, true]) {
      for (final tableContext in [false, true]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets(
            'T177 fact column boundaries $frame dark=$dark scale=$scale table=$tableContext',
            (tester) async {
              tester.view.physicalSize = frame;
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              const facts = {
                'Код': 'Готово',
                'Источник наблюдений': 'Длинное полное значение источника: пример Unicode αβγ и дополнительные сведения без сокращения.',
                'Сведения':
                    'Исходное значение заменено пользовательским виджетом',
              };
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
                      padding: const EdgeInsets.all(20),
                      child: ServerFactRows(
                        facts: facts,
                        tableContext: tableContext,
                        valueStyles: const {
                          'Источник наблюдений': TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        },
                        valueWidgets: const {
                          'Сведения': SelectableText(
                            'Пользовательское значение',
                          ),
                        },
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final bounds = tester.getRect(find.byType(ServerFactRows));
              expect(bounds.width, closeTo(frame.width - 40, 1));
              for (final entry in facts.entries) {
                final row = tester.getRect(
                  find.byKey(ServerFactRowKey(entry.key)),
                );
                final label = tester.getRect(find.text(entry.key));
                final value = tester.getRect(
                  find.text(
                    entry.key == 'Сведения'
                        ? 'Пользовательское значение'
                        : entry.value,
                  ),
                );
                expect(row.left, closeTo(bounds.left, 1));
                expect(row.width, closeTo(bounds.width, 1));
                expect(label.left, closeTo(bounds.left, 1));
                if (frame.width > 520) {
                  final labelWidth = tableContext
                      ? ((bounds.width - 12) * 7 / 27).clamp(
                          110.0,
                          bounds.width - 12,
                        )
                      : (bounds.width - 12) * 10 / 23;
                  expect(label.width, closeTo(labelWidth, 1));
                  expect(value.left, closeTo(bounds.left + labelWidth + 12, 1));
                  expect(value.right, closeTo(bounds.right, 1));
                } else {
                  expect(value.left, closeTo(bounds.left, 1));
                  expect(value.top, greaterThanOrEqualTo(label.bottom));
                  expect(value.right, lessThanOrEqualTo(bounds.right + 1));
                }
              }
              expect(find.text(facts['Сведения']!), findsNothing);
              expect(
                tester
                    .widget<SelectableText>(
                      find.byWidgetPredicate(
                        (widget) =>
                            widget is SelectableText &&
                            widget.data == facts['Источник наблюдений'],
                      ),
                    )
                    .style!
                    .fontWeight,
                FontWeight.w600,
              );
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox.shrink());
            },
          );
        }
      }
    }
  }
  for (final scale in [1.0, 2.0]) {
    for (final dark in [false, true]) {
      testWidgets('T177 table context minimum label dark=$dark scale=$scale', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? BrandTheme.dark : BrandTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 220,
                    child: ServerFactRows(
                      tableContext: true,
                      facts: {'Код': 'Полное значение доступно без сокращения'},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final bounds = tester.getRect(find.byType(ServerFactRows));
        final label = tester.getRect(find.text('Код'));
        final value = tester.getRect(
          find.text('Полное значение доступно без сокращения'),
        );
        expect(bounds.width, 220);
        expect(label.width, closeTo(110, 1));
        expect(value.left, closeTo(bounds.left + 122, 1));
        expect(value.right, closeTo(bounds.right, 1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
