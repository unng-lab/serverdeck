import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_forms.dart';
import 'package:serverdeck/profiles/credential_input.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_control_target.dart';

import '../support/design_fonts.dart';
import 'deck_components_test.dart' show pixels;

void main() {
  setUpAll(loadDesignFonts);
  for (final width in [1100.0, 800.0, 390.0, 360.0]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('T217 actual readonly form value $width $dark $scale', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
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
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: width <= 520 ? width - 32 : 225,
                      child: const AutomationFormValue(
                        label: 'Среда',
                        value: 'Ubuntu 24.04 · amd64 · systemd',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final target = find.byType(DeckControlTarget);
          if (scale == 1)
            expect(
              tester.getSize(target).height,
              closeTo(width <= 520 ? 44 : 42, .1),
            );
          final field = find.byType(TextField);
          expect(field, findsOneWidget);
          final editable = tester.widget<EditableText>(
            find.byType(EditableText),
          );
          expect(editable.controller.text, 'Ubuntu 24.04 · amd64 · systemd');
          expect(editable.readOnly, isTrue);
          expect(editable.selectionEnabled, isTrue);
          expect(editable.maxLines, scale == 1 ? 1 : isNull);
          if (scale > 1) expect(tester.getSize(target).height, greaterThan(44));
          await tester.tap(field);
          await tester.pumpAndSettle();
          expect(editable.focusNode.hasFocus, isTrue);
          expect(tester.testTextInput.isVisible, isFalse);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets(
    'T217 readonly value updates without stale data and clears on disposal',
    (tester) async {
      var value = 'Ubuntu 24.04 · amd64 · systemd';
      var shown = true;
      var dark = true;
      late StateSetter update;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MaterialApp(
              theme: dark ? BrandTheme.dark : BrandTheme.light,
              home: Scaffold(
                body: shown
                    ? AutomationFormValue(label: 'Среда', value: value)
                    : const SizedBox(),
              ),
            );
          },
        ),
      );
      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      final controller = editable.controller;
      final focus = editable.focusNode;
      focus.requestFocus();
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 5,
      );
      await tester.pumpAndSettle();
      update(() => dark = false);
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller,
        same(controller),
      );
      expect(
        controller.selection,
        const TextSelection(baseOffset: 1, extentOffset: 5),
      );
      expect(focus.hasFocus, isTrue);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final width in [390.0, 1100.0]) {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpAndSettle();
        expect(
          tester.widget<EditableText>(find.byType(EditableText)).controller,
          same(controller),
        );
        expect(
          controller.selection,
          const TextSelection(baseOffset: 1, extentOffset: 5),
        );
        expect(focus.hasFocus, isTrue);
      }
      update(() => value = 'Новая среда');
      await tester.pumpAndSettle();
      expect(controller.text, value);
      expect(controller.selection.isValid, isTrue);
      expect(
        controller.selection.extentOffset,
        lessThanOrEqualTo(value.length),
      );
      expect(focus.hasFocus, isTrue);
      update(() => value = '');
      await tester.pumpAndSettle();
      expect(controller.text, isEmpty);
      expect(controller.selection.extentOffset, 0);
      update(() => value = 'Частное значение');
      await tester.pumpAndSettle();
      expect(controller.text, value);
      update(() => shown = false);
      await tester.pumpAndSettle();
      expect(controller.text, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'T217 credential file status has the source multiline minimum without selecting a file',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var picks = 0;
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.dark,
          home: Scaffold(
            body: RepaintBoundary(
              key: boundary,
              child: SingleChildScrollView(
                child: SizedBox(
                  width: 464,
                  child: CredentialInput(
                    creating: false,
                    enabled: true,
                    pageTarget: 'Actual target · 192.0.2.1:22',
                    pickKey: () async {
                      picks++;
                      return null;
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final file = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.controller?.text.startsWith('Файл не выбран') ?? false),
      );
      expect(file, findsOneWidget);
      expect(tester.getSize(file).height, closeTo(60, .1));
      final rect = tester.getRect(file);
      expect(
        await pixels(tester, boundary, [
          Offset(rect.center.dx, rect.top),
          Offset(rect.center.dx, rect.bottom - 1),
        ]),
        [BrandColors.dark['control'], BrandColors.dark['control']],
      );
      final storage = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.controller?.text == 'Защита ОС текущего пользователя',
      );
      expect(storage, findsOneWidget);
      expect(tester.widget<TextField>(storage).readOnly, isTrue);
      expect(picks, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
