import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_page.dart';

import '../support/design_fonts.dart';

void main() {
  setUpAll(loadDesignFonts);
  for (final width in [390.0, 520.0, 521.0, 700.0, 701.0, 1100.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final withAction in [false, true]) {
        testWidgets('T198 page origin $width scale=$scale action=$withAction', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: BrandTheme.dark,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: DeckPageInsets(
                  padding: EdgeInsets.zero,
                  child: DeckPage(
                    title: 'Страница',
                    actions: [
                      if (withAction)
                        FilledButton(
                          onPressed: () {},
                          child: const Text('Сохранить'),
                        ),
                    ],
                    child: const SizedBox(
                      key: ValueKey('body-start'),
                      height: 20,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final phone = width <= 520;
          final heading = 32 * scale;
          final button = scale == 1
              ? (phone ? 44.0 : 36.0)
              : (phone ? 64.0 : 56.0);
          final expected = width <= 700
              ? heading +
                    (phone ? 14 : 12) +
                    (withAction ? button : 0) +
                    (phone ? 20 : 24)
              : (withAction ? math.max(heading, button + 2) : heading) + 24;
          expect(
            tester.getTopLeft(find.byKey(const ValueKey('body-start'))).dy,
            closeTo(expected, .01),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
  for (final width in [390.0, 520.0, 521.0, 1100.0]) {
    testWidgets('T198 form post-tabs margin $width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.dark,
          home: Scaffold(
            body: DeckPageInsets(
              padding: const EdgeInsets.all(16),
              child: AutomationFormPageFrame(
                asPage: true,
                title: 'Редактор',
                actions: const [],
                tabs: DeckTabs(
                  labels: const ['Назначение'],
                  selected: 0,
                  onSelected: (_) {},
                ),
                child: const Text('Содержимое формы'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final panel = find.ancestor(
        of: find.text('Содержимое формы'),
        matching: find.byType(DeckPanel),
      );
      expect(
        tester.getRect(panel).top -
            tester.getRect(find.byType(DeckTabs)).bottom,
        width <= 520 ? 16 : 20,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('T198 header reflow retains native action focus and body draft', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final input = TextEditingController(text: 'Несохранённый текст');
    final focus = FocusNode();
    var calls = 0;
    Widget app() => MaterialApp(
      theme: BrandTheme.dark,
      home: Scaffold(
        body: DeckPageInsets(
          padding: const EdgeInsets.all(16),
          child: DeckPage(
            title: 'Страница',
            actions: [
              FilledButton(
                focusNode: focus,
                onPressed: () => calls++,
                child: const Text('Сохранить'),
              ),
            ],
            child: TextField(controller: input),
          ),
        ),
      ),
    );
    try {
      tester.view.physicalSize = const Size(1100, 800);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final button = find.widgetWithText(FilledButton, 'Сохранить');
      final actionState = tester.state(button);
      final editorState = tester.state(find.byType(EditableText));
      focus.requestFocus();
      input.selection = const TextSelection(baseOffset: 1, extentOffset: 5);
      for (final width in [700.0, 701.0, 521.0, 520.0, 1100.0]) {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        expect(tester.state(button), same(actionState));
        expect(tester.state(find.byType(EditableText)), same(editorState));
        expect(focus.hasFocus, isTrue);
        expect(input.text, 'Несохранённый текст');
        expect(
          input.selection,
          const TextSelection(baseOffset: 1, extentOffset: 5),
        );
      }
      expect(calls, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      input.dispose();
      focus.dispose();
    }
  });
}
