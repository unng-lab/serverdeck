import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/theme/brand_theme.dart';

import '../support/design_fonts.dart';

TextStyle styleOf(WidgetTester tester, String text) =>
    (tester.renderObject<RenderParagraph>(find.text(text)).text as TextSpan)
        .style!;

Finder rowOf(String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(InkWell)).first;

Finder cardOf(String text) => find
    .ancestor(
      of: find.text(text),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).borderRadius ==
                BorderRadius.circular(10),
      ),
    )
    .first;

void main() {
  setUpAll(loadDesignFonts);
  testWidgets('T187 empty table has one separator before footer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final footer in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.dark,
          home: Scaffold(
            body: AutomationRecordTable(
              columns: const ['Empty name'],
              rows: const [],
              showFooter: footer,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final header = find
          .ancestor(
            of: rowOf('Empty name'),
            matching: find.byType(DecoratedBox),
          )
          .first;
      expect(tester.getSize(header).height, 40);
      expect(
        find.text('Получено записей: 0'),
        footer ? findsOneWidget : findsNothing,
      );
      if (footer) {
        expect(
          tester.getTopLeft(find.text('Получено записей: 0')).dy -
              tester.getBottomLeft(header).dy,
          12,
        );
      }
      expect(tester.takeException(), isNull);
    }
  });
  for (final width in [1100.0, 800.0, 390.0, 360.0, 520.0, 521.0]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('T187 row composition $width $dark $scale', (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final calls = <int>[];
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
                  padding: const EdgeInsets.all(16),
                  child: AutomationRecordTable(
                    columns: const ['Имя', 'B', 'C', 'D', 'Версия'],
                    rows: const [
                      [
                        Text('alpha'),
                        Text('B0'),
                        Text('C0'),
                        Text('D0'),
                        Text('v1', style: BrandTypography.log),
                      ],
                      [
                        Text('beta'),
                        Text('B1'),
                        Text('C1'),
                        Text('D1'),
                        Text('v2', style: BrandTypography.log),
                      ],
                    ],
                    selected: 1,
                    onSelect: calls.add,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final phone = width <= 520;
          expect(styleOf(tester, 'alpha').fontSize, phone ? 15 : 13);
          expect(
            styleOf(tester, 'alpha').fontWeight,
            BrandTypography.semiboldWeight,
          );
          expect(styleOf(tester, 'B0').fontSize, 13);
          expect(styleOf(tester, 'B0').height! * 13, 20);
          expect(styleOf(tester, 'B0').fontWeight, FontWeight.w400);
          expect(
            styleOf(tester, 'v1').fontFamily,
            BrandTypography.log.fontFamily,
          );
          expect(styleOf(tester, 'v1').fontWeight, FontWeight.w400);
          expect(find.text('v1'), findsOneWidget);
          expect(find.text('v2'), findsOneWidget);
          if (phone) {
            final a = tester.getRect(cardOf('alpha'));
            final b = tester.getRect(cardOf('beta'));
            final name = tester.getRect(find.text('alpha'));
            final first = tester.getRect(find.text('B0'));
            final second = tester.getRect(find.text('C0'));
            expect(a.left, 16);
            expect(a.width, width - 32);
            expect(name.left - a.left, 17);
            expect(a.height, closeTo(94 * scale + 83, .01));
            expect(b.top - a.bottom, 10);
            expect(second.top, first.top);
            expect(
              second.left - first.left,
              closeTo((a.width - 34 + 12) / 2, .01),
            );
            expect(
              tester.getRect(find.text('D0')).top,
              greaterThan(first.bottom),
            );
            expect(find.text('Имя'), findsNothing);
            final labels = find.text('B');
            expect(labels, findsNWidgets(2));
            expect(
              (tester.renderObject<RenderParagraph>(labels.first).text
                      as TextSpan)
                  .style!
                  .fontSize,
              12,
            );
          } else {
            expect(find.text('Имя'), findsOneWidget);
            final header = tester.getRect(
              find
                  .ancestor(
                    of: rowOf('Имя'),
                    matching: find.byType(DecoratedBox),
                  )
                  .first,
            );
            final headerTextHeight = ['Имя', 'B', 'C', 'D', 'Версия']
                .map((text) => tester.getSize(find.text(text)).height)
                .reduce((a, b) => a > b ? a : b);
            expect(header.height, closeTo(headerTextHeight + 21, .01));
            final a = tester.getRect(find.text('alpha'));
            final b = tester.getRect(find.text('B0'));
            final row = tester.getRect(rowOf('alpha'));
            expect(a.left - row.left, 12);
            expect(b.left - a.left, closeTo(row.width / 5, .01));
            final rowSurface = tester.getRect(
              find
                  .ancestor(
                    of: rowOf('alpha'),
                    matching: find.byType(DecoratedBox),
                  )
                  .first,
            );
            expect(rowSurface.height, closeTo(20 * scale + 25, .01));
          }
          final footer = find.text('Получено записей: 2');
          expect(styleOf(tester, 'Получено записей: 2').fontSize, 12);
          expect(styleOf(tester, 'Получено записей: 2').height! * 12, 16);
          final last = phone
              ? tester.getRect(cardOf('beta'))
              : tester.getRect(rowOf('beta'));
          expect(tester.getTopLeft(footer).dy - last.bottom, 12);
          expect(tester.getTopLeft(footer).dx, phone ? 16 : 33);
          expect(calls, isEmpty);
          await tester.tap(find.text('alpha'));
          await tester.pumpAndSettle();
          expect(calls, [0]);
          Focus.of(tester.element(find.text('alpha'))).requestFocus();
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(calls, [0, 0]);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
  testWidgets('T187 long values and nested width keep every column', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final width in [1100.0, 390.0]) {
      tester.view.physicalSize = Size(width, 1000);
      final values = List.generate(5, (i) => '$i-${'value' * 30}');
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 320,
                  child: AutomationRecordTable(
                    columns: const [
                      'Header0',
                      'Header1',
                      'Header2',
                      'Header3',
                      'Header4',
                    ],
                    rows: [values.map((v) => Text(v)).toList()],
                    caption: 'Полные значения',
                    showFooter: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Header0'), width > 520 ? findsOneWidget : findsNothing);
      for (final value in values) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(value),
        );
        expect(paragraph.maxLines, isNull);
        expect(paragraph.overflow, isNot(TextOverflow.ellipsis));
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.size.height, greaterThan(40));
      }
      expect(find.text('Header4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
