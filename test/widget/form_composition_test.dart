import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/profiles/profile_presentation.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_page.dart';
import 'package:serverdeck/ui/deck_components.dart';

import '../support/design_fonts.dart';
import 'deck_components_test.dart' show pixels;

void main() {
  setUpAll(loadDesignFonts);
  for (final dark in [false, true]) {
    for (final automation in [false, true]) {
      testWidgets(
        'T217 source section and footer each retain their edge $dark $automation',
        (tester) async {
          tester.view.physicalSize = const Size(1100, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final boundary = GlobalKey();
          var calls = 0;
          final actions = [
            TextButton(
              onPressed: () => calls++,
              child: const Text('Сохранить'),
            ),
          ];
          final frame = automation
              ? AutomationFormPageFrame(
                  title: 'Форма',
                  asPage: true,
                  helper: null,
                  actions: actions,
                  child: const SizedBox(height: 20),
                )
              : ProfileEditorFrame(
                  title: 'Форма',
                  asPage: true,
                  showHelper: false,
                  actions: actions,
                  child: const SizedBox(height: 20),
                );
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? BrandTheme.dark : BrandTheme.light,
              home: Scaffold(
                body: RepaintBoundary(
                  key: boundary,
                  child: SingleChildScrollView(child: frame),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final footer = find
              .ancestor(
                of: find.byType(DeckFormActions),
                matching: find.byType(Container),
              )
              .first;
          final rect = tester.getRect(footer);
          final y = rect.top.roundToDouble();
          final colors = dark ? BrandColors.dark : BrandColors.light;
          expect(
            await pixels(tester, boundary, [
              Offset(rect.left + 10, y - 1),
              Offset(rect.left + 10, y),
              Offset(rect.left + 10, y + 1),
            ]),
            [colors['border'], colors['border'], colors['raised']],
          );
          expect(calls, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      'T217 final form section without actions has no extra edge $dark',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Widget host(List<Widget> actions) => MaterialApp(
          theme: dark ? BrandTheme.dark : BrandTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: AutomationFormPageFrame(
                title: 'Форма',
                asPage: true,
                helper: null,
                actions: actions,
                child: const SizedBox(height: 20),
              ),
            ),
          ),
        );
        await tester.pumpWidget(host(const []));
        await tester.pumpAndSettle();
        final noFooterHeight = tester.getSize(find.byType(DeckPanel)).height;
        await tester.pumpWidget(
          host([TextButton(onPressed: () {}, child: const Text('Сохранить'))]),
        );
        await tester.pumpAndSettle();
        final footer = find
            .ancestor(
              of: find.byType(DeckFormActions),
              matching: find.byType(Container),
            )
            .first;
        expect(
          tester.getSize(find.byType(DeckPanel)).height,
          closeTo(noFooterHeight + tester.getSize(footer).height + 1, .1),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'T190 compact footer respects long-label minimum and wrap $scale',
      (tester) async {
        tester.view.physicalSize = const Size(600, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var calls = 0;
        final long = 'Ж' * 35;
        await tester.pumpWidget(
          MaterialApp(
            theme: BrandTheme.dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: DeckFormActions(
                  children: [
                    FilledButton(onPressed: () => calls++, child: Text(long)),
                    OutlinedButton(
                      onPressed: () => calls++,
                      child: const Text('Да'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final first = find.widgetWithText(FilledButton, long);
        final second = find.widgetWithText(OutlinedButton, 'Да');
        final a = tester.getRect(first), b = tester.getRect(second);
        if (scale == 1) {
          expect(a.top, b.top);
          expect(a.width, greaterThan(b.width));
          expect(a.left + 4, closeTo(16, .01));
          expect(b.right - 4, closeTo(584, .01));
        } else {
          expect(b.top, greaterThanOrEqualTo(a.bottom));
          expect(a.width, closeTo(576, .01));
          expect(b.width, closeTo(a.width, .01));
        }
        await tester.tap(first);
        await tester.tap(second);
        expect(calls, 2);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'T190 form draft and action focus survive theme and breakpoint changes',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final input = TextEditingController(text: 'Несохранённое значение');
      final saveFocus = FocusNode();
      var saves = 0;
      Widget app(bool dark, double scale) => MaterialApp(
        theme: dark ? BrandTheme.dark : BrandTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: DeckPageInsets(
            padding: const EdgeInsets.all(16),
            child: AutomationFormPageFrame(
              asPage: true,
              title: 'Редактор',
              actions: [
                FilledButton(
                  focusNode: saveFocus,
                  onPressed: () => saves++,
                  child: const Text('Сохранить'),
                ),
                OutlinedButton(onPressed: () {}, child: const Text('Отмена')),
              ],
              child: TextField(controller: input),
            ),
          ),
        ),
      );
      try {
        await tester.pumpWidget(app(true, 1));
        await tester.pumpAndSettle();
        final fieldState = tester.state(find.byType(EditableText));
        final button = find.widgetWithText(FilledButton, 'Сохранить');
        final buttonState = tester.state(button);
        input.selection = const TextSelection(baseOffset: 1, extentOffset: 5);
        saveFocus.requestFocus();
        await tester.pumpAndSettle();
        for (final (width, dark, scale) in [
          (390.0, false, 2.0),
          (800.0, true, 1.0),
          (700.0, false, 1.0),
          (360.0, true, 2.0),
          (1100.0, false, 1.0),
        ]) {
          tester.view.physicalSize = Size(width, 800);
          await tester.pumpWidget(app(dark, scale));
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(EditableText)), same(fieldState));
          expect(tester.state(button), same(buttonState));
          expect(saveFocus.hasFocus, isTrue);
          expect(input.text, 'Несохранённое значение');
          expect(
            input.selection,
            const TextSelection(baseOffset: 1, extentOffset: 5),
          );
          expect(saves, 0);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(saves, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        saveFocus.dispose();
        input.dispose();
      }
    },
  );
  for (final width in [
    1100.0,
    800.0,
    390.0,
    360.0,
    520.0,
    521.0,
    600.0,
    760.0,
    761.0,
    960.0,
    961.0,
  ]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'T190 form footer and helper $width dark=$dark scale=$scale',
          (tester) async {
            tester.view.physicalSize = Size(width, width == 800 ? 600 : 800);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            var saves = 0, closes = 0;
            await tester.pumpWidget(
              MaterialApp(
                theme: dark ? BrandTheme.dark : BrandTheme.light,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: DeckPageInsets(
                    padding: EdgeInsets.all(width <= 520 ? 16 : 28),
                    child: AutomationFormPageFrame(
                      asPage: true,
                      title: 'Редактор профиля',
                      actions: [
                        FilledButton(
                          onPressed: () => saves++,
                          child: const Text('Сохранить'),
                        ),
                        OutlinedButton(
                          onPressed: () => closes++,
                          child: const Text('Отмена'),
                        ),
                      ],
                      child: const Text('Содержимое формы'),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              find.text('Перед продолжением'),
              width > 960 ? findsOneWidget : findsNothing,
            );
            final save = find.widgetWithText(FilledButton, 'Сохранить');
            final close = find.widgetWithText(OutlinedButton, 'Отмена');
            await tester.ensureVisible(save);
            await tester.pumpAndSettle();
            final footer = find.ancestor(
              of: save,
              matching: find.byWidgetPredicate(
                (w) =>
                    w is Container &&
                    w.decoration is BoxDecoration &&
                    (w.decoration! as BoxDecoration).color ==
                        (dark ? BrandColors.dark : BrandColors.light)['raised'],
              ),
            );
            expect(footer, findsOneWidget);
            final bounds = tester.getRect(footer);
            final saveRect = tester.getRect(save),
                closeRect = tester.getRect(close);
            if (width <= 520) {
              expect(saveRect.left, bounds.left + 14);
              expect(saveRect.width, bounds.width - 28);
              expect(closeRect.width, saveRect.width);
              expect(closeRect.top - saveRect.bottom, 10);
            } else {
              expect(closeRect.right - 4, closeTo(bounds.right - 20, .01));
              if (width <= 760) {
                expect(saveRect.left + 4, closeTo(bounds.left + 20, .01));
                expect(saveRect.width, closeTo(closeRect.width, .01));
                expect(closeRect.left - saveRect.right + 8, closeTo(8, .01));
              }
              await tester.tapAt(Offset(saveRect.center.dx, saveRect.top + .2));
              expect(saves, 1);
              await tester.tapAt(
                Offset(saveRect.center.dx, saveRect.bottom - .2),
              );
              expect(saves, 2);
            }
            if (width > 960) {
              final helper = find.ancestor(
                of: find.text('Перед продолжением'),
                matching: find.byType(DeckPanel),
              );
              final form = find.ancestor(
                of: find.text('Содержимое формы'),
                matching: find.byType(DeckPanel),
              );
              expect(
                tester.getRect(helper).left - tester.getRect(form).right,
                closeTo(20, .01),
              );
              final heading = tester.widget<Text>(
                find.text('Перед продолжением'),
              );
              expect(heading.style!.fontSize, 14);
              expect(heading.style!.height, 22 / 14);
            }
            await tester.tap(save);
            await tester.ensureVisible(close);
            await tester.pumpAndSettle();
            await tester.tap(close);
            expect(saves, width <= 520 ? 1 : 3);
            expect(closes, 1);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
}
