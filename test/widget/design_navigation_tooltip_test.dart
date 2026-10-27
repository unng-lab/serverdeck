import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck_protocol/models.dart' show ReadinessState;

import '../support/design_host.dart' show loadDesignFonts;
import '../support/design_stock_paint_support.dart' show stockContainsFocus;

Finder _item(FoundationSection section) =>
    find.byKey(ValueKey('foundation-navigation-${section.name}'));

Finder _overlayLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is Text && widget.textSpan?.toPlainText() == label,
);

void _expectLabels(FoundationSection? current) {
  for (final section in FoundationSection.values) {
    expect(
      _overlayLabel(section.label),
      section == current ? findsOneWidget : findsNothing,
      reason: 'Only the current focused/hovered rail label may remain',
    );
  }
}

FoundationSection? _current(WidgetTester tester) {
  for (final section in FoundationSection.values) {
    if (tester
        .widget<OutlinedButton>(_item(section))
        .focusNode!
        .hasPrimaryFocus) {
      return section;
    }
  }
  return null;
}

Future<void> _tab(
  WidgetTester tester, {
  bool reverse = false,
  bool settle = true,
}) async {
  if (reverse) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  if (reverse) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _tabToSection(
  WidgetTester tester,
  FoundationSection target, {
  bool reverse = false,
}) async {
  for (var i = 0; i < 20; i++) {
    await _tab(tester, reverse: reverse);
    _expectLabels(_current(tester));
    if (_current(tester) == target) return;
  }
  fail('Actual Tab journey did not reach ${target.name}');
}

Future<void> _tabToElement(
  WidgetTester tester,
  Finder target, {
  bool reverse = false,
}) async {
  for (var i = 0; i < 20; i++) {
    await _tab(tester, reverse: reverse);
    _expectLabels(_current(tester));
    if (stockContainsFocus(tester, target)) return;
  }
  fail('Actual Tab journey did not reach $target');
}

void main() {
  setUpAll(loadDesignFonts);
  for (final width in [521.0, 800.0, 1060.0]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'rail tooltip lifecycle width=$width dark=$dark scale=$scale',
          (tester) async {
            tester.view.physicalSize = Size(width, 800);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            var effects = 0;
            await tester.pumpWidget(
              MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: Motion.theme(
                  dark ? BrandTheme.dark : BrandTheme.light,
                  true,
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true,
                  ),
                  child: child!,
                ),
                home: FoundationShell(
                  state: ReadinessState.ready,
                  targetName: 'Сервер例',
                  targetAddress: 'example.test:22',
                  servers: TextButton(
                    onPressed: () => effects++,
                    child: const Text('Действие feature'),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final buttonStates = {
              for (final section in FoundationSection.values)
                section: tester.state(_item(section)),
            };
            _expectLabels(null);
            for (final section in FoundationSection.values) {
              await _tabToSection(tester, section);
              expect(_current(tester), section);
              _expectLabels(section);
            }
            await _tabToElement(tester, find.byType(EditableText));
            expect(_current(tester), isNull);
            _expectLabels(null);
            // The new bounded header is the next actual Tab target; feature is
            // next, and neither can retain navigation overlays.
            expect(
              tester
                  .widget<EditableText>(find.byType(EditableText))
                  .focusNode
                  .hasPrimaryFocus,
              isTrue,
            );
            await _tabToElement(tester, find.byType(TextButton));
            expect(_current(tester), isNull);
            _expectLabels(null);
            await _tabToElement(
              tester,
              find.byType(EditableText),
              reverse: true,
            );
            _expectLabels(null);
            for (final section in FoundationSection.values.reversed) {
              await _tabToSection(tester, section, reverse: true);
              expect(_current(tester), section);
              _expectLabels(section);
            }
            for (var i = 0; i < 14; i++) {
              await _tab(tester, reverse: i % 3 == 0, settle: false);
            }
            await tester.pumpAndSettle();
            _expectLabels(_current(tester));
            for (final section in FoundationSection.values) {
              expect(
                tester.state(_item(section)),
                same(buttonStates[section]),
                reason:
                    'Retiring a tooltip must preserve the real button State',
              );
            }
            // Resize before a newly scheduled focus tooltip can be shown.
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            // Leave the rail, return, then dispose with a tooltip potentially
            // showing. A queued focus callback must not revive an old label.
            for (final next in [520.0, 1061.0, width]) {
              tester.view.physicalSize = Size(next, 800);
              await tester.pumpAndSettle();
              _expectLabels(next == width ? _current(tester) : null);
            }
            // Exit by real Tab before pointer journeys. No manual dismissal is
            // used anywhere: native hover exit and long-press timeout own these.
            for (var i = 0; i < 8 && _current(tester) != null; i++) {
              await _tab(tester);
            }
            _expectLabels(null);
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
            );
            await mouse.addPointer(location: Offset.zero);
            await mouse.moveTo(tester.getCenter(_item(FoundationSection.logs)));
            await tester.pumpAndSettle(const Duration(milliseconds: 600));
            _expectLabels(FoundationSection.logs);
            await mouse.moveTo(Offset.zero);
            await tester.pumpAndSettle(const Duration(milliseconds: 200));
            _expectLabels(null);
            await mouse.removePointer();
            await tester.longPress(_item(FoundationSection.settings));
            await tester.pumpAndSettle();
            _expectLabels(FoundationSection.settings);
            await tester.pumpAndSettle(const Duration(seconds: 2));
            _expectLabels(null);
            expect(effects, 0);
            await _tabToSection(tester, FoundationSection.servers);
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            _expectLabels(null);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
