import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/theme/brand_theme.dart';

import '../support/design_fonts.dart';
import 'deck_components_test.dart' show pixels;

void main() {
  setUpAll(loadDesignFonts);
  for (final frame in const [
    Size(1100, 760),
    Size(800, 600),
    Size(390, 800),
    Size(360, 800),
  ]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        for (final tableContext in [false, true]) {
          testWidgets('T182 facts $frame $dark $scale $tableContext', (
            tester,
          ) async {
            tester.view.physicalSize = frame;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final theme = dark ? BrandTheme.dark : BrandTheme.light;
            final colors = theme.extension<BrandColors>()!;
            final boundary = GlobalKey();
            const firstValue =
                'Полное значение сервера и действующего источника';
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: RepaintBoundary(
                      key: boundary,
                      child: ColoredBox(
                        color: colors['surface'],
                        child: AutomationFacts(
                          tableContext: tableContext,
                          values: const {
                            'Источник': firstValue,
                            'Срок': 'Не скрывать остаток значения',
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final label = find.text('Источник'), value = find.text(firstValue);
            final next = find.text('Срок');
            final labelRect = tester.getRect(label),
                valueRect = tester.getRect(value);
            final labelStyle = tester.widget<Text>(label).style!;
            final valueStyle = tester.widget<Text>(value).style!;
            final phone = frame.width <= 520;
            expect(labelStyle.fontSize, 12);
            expect(labelStyle.height, 20 / 12);
            expect(labelStyle.color, colors['muted']);
            expect(valueStyle.fontSize, phone ? 13 : 12);
            expect(valueStyle.height, phone ? 22 / 13 : 20 / 12);
            expect(
              valueStyle.fontFamily,
              tableContext ? 'Noto Sans' : 'Noto Sans Mono',
            );
            if (phone) {
              expect(valueRect.left, labelRect.left);
              expect(valueRect.top - labelRect.bottom, 4);
              expect(tester.getTopLeft(next).dy - valueRect.bottom, 25);
            } else {
              expect(valueRect.top, labelRect.top);
              expect(valueRect.left - labelRect.right, 12);
              final available = frame.width - 32;
              final expectedLabel = tableContext
                  ? math.max(110.0, (available - 12) * .7 / 2.7)
                  : (available - 12) / 2.3;
              expect(labelRect.width, closeTo(expectedLabel, .01));
              final origin = tester.getTopLeft(find.byKey(boundary));
              final borderY = tester.getTopLeft(next).dy - 10 - origin.dy;
              final samples = await pixels(tester, boundary, [
                Offset(2, borderY),
                Offset(labelRect.width + 6, borderY),
              ]);
              expect(samples.first, colors['border']);
              expect(samples.last, colors['surface']);
            }
            await tester.ensureVisible(
              find.text('Не скрывать остаток значения'),
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          });
        }
      }
    }
  }
  testWidgets('T182 table context minimum label and explicit style override', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.light,
        home: const Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 220,
              child: AutomationFacts(
                tableContext: true,
                values: {'Ключ': 'Значение'},
                styles: {
                  'Ключ': TextStyle(
                    fontFamily: 'Noto Sans SemiBold',
                    fontSize: 15,
                    fontWeight: BrandTypography.semiboldWeight,
                  ),
                },
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.text('Ключ')).width, 110);
    final style = tester.widget<Text>(find.text('Значение')).style!;
    expect(style.fontSize, 15);
    expect(style.fontWeight, BrandTypography.semiboldWeight);
    expect(style.fontFamily, 'Noto Sans SemiBold');
    expect(tester.takeException(), isNull);
  });
}
