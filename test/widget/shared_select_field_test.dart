import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';

import '../support/design_fonts.dart' show loadDesignFonts;

Widget _app({
  required bool reduced,
  required double scale,
  required String? label,
  String value = 'Значение',
  String otherValue = 'Другое',
}) => MaterialApp(
  theme: Motion.theme(BrandTheme.light, reduced),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      disableAnimations: reduced,
      textScaler: TextScaler.linear(scale),
    ),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300,
          child: MotionDropdown<String>(
            initialValue: 'a',
            items: [
              DropdownMenuItem(value: 'a', child: Text(value)),
              DropdownMenuItem(value: 'b', child: Text(otherValue)),
            ],
            decoration: InputDecoration(labelText: label),
            onChanged: (_) {},
          ),
        ),
      ),
    ),
  ),
);

void main() {
  setUpAll(loadDesignFonts);
  for (final scale in [1.0, 2.0]) {
    for (final label in <String?>[null, 'Способ']) {
      testWidgets(
        'normal and reduced select retain field layout scale$scale label$label',
        (tester) async {
          await tester.pumpWidget(
            _app(reduced: false, scale: scale, label: label),
          );
          await tester.pumpAndSettle();
          final normalField = tester.getRect(find.byType(InputDecorator));
          if (label == null) expect(normalField.height, scale == 1 ? 44 : 64);
          final normalValue = tester.getRect(find.text('Значение'));
          await tester.pumpWidget(
            _app(reduced: true, scale: scale, label: label),
          );
          await tester.pumpAndSettle();
          expect(tester.getRect(find.byType(InputDecorator)), normalField);
          expect(tester.getRect(find.text('Значение')), normalValue);
          expect(find.text(''), findsNothing);
          final decoration = tester
              .widget<InputDecorator>(find.byType(InputDecorator))
              .decoration;
          expect(decoration.fillColor, BrandColors.light['bg']);
          expect(decoration.labelStyle!.fontSize, 12);
          expect(decoration.labelStyle!.height, 20 / 12);
          expect(
            decoration.labelStyle!.fontWeight,
            BrandTypography.semiboldWeight,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('normal popup selection grows only the selected value', (
    tester,
  ) async {
    final text = List.filled(6, 'Длинное другое значение').join(' ');
    await tester.pumpWidget(
      _app(reduced: false, scale: 2, label: null, otherValue: text),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(InputDecorator)).height, 64);
    await tester.tap(find.byType(MotionDropdown<String>));
    await tester.pumpAndSettle();
    final choice = find.text(text).last;
    await tester.ensureVisible(choice);
    await tester.tap(choice);
    await tester.pumpAndSettle();
    expect(find.text(text), findsOneWidget);
    expect(tester.getSize(find.byType(InputDecorator)).height, greaterThan(64));
    expect(
      tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long selected value grows in both modes with equal full text layout',
    (tester) async {
      final text = List.filled(8, 'Длинное выбранное значение').join(' ');
      Rect? normalField;
      Rect? normalValue;
      for (final reduced in [false, true]) {
        await tester.pumpWidget(
          _app(reduced: reduced, scale: 2, label: null, value: text),
        );
        await tester.pumpAndSettle();
        final value = find.text(text);
        final paragraph = tester.renderObject<RenderParagraph>(value);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.size.height, greaterThan(40));
        if (!reduced) {
          normalField = tester.getRect(find.byType(InputDecorator));
          normalValue = tester.getRect(value);
        } else {
          expect(tester.getRect(find.byType(InputDecorator)), normalField);
          expect(tester.getRect(value), normalValue);
        }
        final scroll = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        expect(scroll.maxScrollExtent, greaterThan(0));
        scroll.jumpTo(scroll.maxScrollExtent);
        await tester.pumpAndSettle();
        final lastGlyph = paragraph
            .getBoxesForSelection(
              TextSelection(
                baseOffset: text.length - 1,
                extentOffset: text.length,
              ),
            )
            .single
            .toRect()
            .shift(paragraph.localToGlobal(Offset.zero));
        final viewport = tester.getRect(find.byType(SingleChildScrollView));
        expect(lastGlyph.top, greaterThanOrEqualTo(viewport.top));
        expect(lastGlyph.bottom, lessThanOrEqualTo(viewport.bottom));
        scroll.jumpTo(0);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );
}
