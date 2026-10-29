import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/servers/server_sections.dart';
import 'package:serverdeck/theme/brand_theme.dart';

import '../support/design_fonts.dart' show loadDesignFonts;
import '../support/design_server_fixtures.dart';

void main() {
  setUpAll(loadDesignFonts);
  for (final phone in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      for (final dark in [false, true]) {
        testWidgets(
          'canonical raw letter advance phone$phone scale$scale dark$dark',
          (tester) async {
            tester.view.physicalSize = phone
                ? const Size(390, 800)
                : const Size(1100, 760);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            const message = 'ABCDEFGH';
            final record = DesignServerFixtures.record(message: message);
            final profile = DesignServerFixtures.profile();
            final logs = DesignServerFixtures.logs(records: [record]);
            await tester.pumpWidget(
              MaterialApp(
                theme: dark ? BrandTheme.dark : BrandTheme.light,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: ServerLogRecordDialog(
                    recordContext: ServerLogRecordContext.capture(
                      profile,
                      logs,
                    ),
                    record: record,
                    asPage: true,
                    onClose: () {},
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final editor = find.byWidgetPredicate(
              (widget) =>
                  widget is EditableText && widget.controller.text == message,
            );
            expect(editor, findsOneWidget);
            await tester.ensureVisible(editor);
            await tester.pumpAndSettle();
            final editable = tester.widget<EditableText>(editor);
            final render = tester
                .state<EditableTextState>(editor)
                .renderEditable;
            final box = render
                .getBoxesForSelection(
                  const TextSelection(baseOffset: 0, extentOffset: 8),
                )
                .single;

            // Independent source CSS metrics: .code-block is 12/20, or 13/22
            // on phone, with normal spacing. Do not derive this from the app's
            // TextTheme, which Material may merge with its own letter spacing.
            final source = TextPainter(
              text: TextSpan(
                text: message,
                style: TextStyle(
                  fontFamily: 'Noto Sans Mono',
                  fontFamilyFallback: const ['Noto Sans SC'],
                  fontSize: phone ? 13 : 12,
                  height: phone ? 22 / 13 : 20 / 12,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0,
                ),
              ),
              textDirection: TextDirection.ltr,
              textScaler: TextScaler.linear(scale),
            )..layout();
            expect(
              box.right - box.left,
              closeTo(source.width, .001),
              reason:
                  'Actual raw glyph advance must match source normal spacing; '
                  'resolved style is ${editable.style}',
            );
            source.dispose();
            expect(editable.readOnly, isTrue);
            expect(editable.controller.text, message);
            expect(editable.style.letterSpacing, 0);
            expect(editable.style.fontFamily, 'Noto Sans Mono');
            expect(editable.style.fontSize, phone ? 13 : 12);
            expect(editable.style.height, phone ? 22 / 13 : 20 / 12);
            expect(editable.style.fontWeight, FontWeight.w400);

            // Local source tracking remains deliberate after the base reset.
            expect(
              tester
                  .widget<Text>(find.text('Детали записи журнала'))
                  .style!
                  .letterSpacing,
              phone ? -.6 : -.5,
            );
            expect(
              tester
                  .widget<Text>(find.text('ЖУРНАЛЫ / РАБОЧЕЕ ПРОСТРАНСТВО'))
                  .style!
                  .letterSpacing,
              phone ? 1.4 : 1.6,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
