import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/profiles/profile_form.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck_protocol/models.dart';

import '../support/design_host.dart' show loadDesignFonts;
import '../support/design_scenario_harness.dart';

const _labels = {
  'name': 'Название',
  'address': 'Адрес (IP или имя домена)',
  'port': 'Порт SSH',
  'user': 'Пользователь SSH',
  'tags': 'Метки (одна на строку)',
};

Finder _field(String id) => find.byKey(ValueKey('profile-$id'));

Widget _app(
  DesignScenarioHarness harness, {
  required bool dark,
  required bool editing,
  required double scale,
  required double keyboard,
}) => MaterialApp(
  theme: Motion.theme(dark ? BrandTheme.dark : BrandTheme.light, true),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      viewInsets: EdgeInsets.only(bottom: keyboard),
      disableAnimations: true,
    ),
    child: child!,
  ),
  home: ProfileForm(
    model: harness.profiles,
    initial: editing ? harness.profiles.profiles.single : null,
  ),
);

Future<void> _showField(WidgetTester tester, String id) async {
  await Scrollable.ensureVisible(tester.element(_field(id)), alignment: .5);
  await tester.pumpAndSettle();
}

void _expectRenderedLabel(WidgetTester tester, String id, double keyboard) {
  final label = _labels[id]!;
  final finder = find.text(label);
  expect(finder, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  // A matching Text still exists when InputDecorator paints an ellipsis. These
  // checks inspect the laid-out glyphs rather than accepting that widget alone.
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: 'The complete required label must be rendered: $label',
  );
  final lastGlyph = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: label.length - 1, extentOffset: label.length),
  );
  expect(lastGlyph, isNotEmpty, reason: 'Last label glyph is clipped: $label');
  final transform = paragraph.getTransformTo(null);
  final bounds = MatrixUtils.transformRect(
    transform,
    Offset.zero & paragraph.size,
  );
  final glyph = MatrixUtils.transformRect(transform, lastGlyph.last.toRect());
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  // Glyph ink may extend beyond its font's logical line box; the actual
  // viewport, rather than that line box, determines whether it is clipped.
  expect(glyph.left, greaterThanOrEqualTo(0));
  expect(glyph.right, lessThanOrEqualTo(size.width));
  expect(glyph.top, greaterThanOrEqualTo(0));
  expect(glyph.bottom, lessThanOrEqualTo(size.height - keyboard));
  expect(bounds.left, greaterThanOrEqualTo(0));
  expect(bounds.right, lessThanOrEqualTo(size.width));
  expect(bounds.top, greaterThanOrEqualTo(0));
  expect(bounds.bottom, lessThanOrEqualTo(size.height - keyboard));
  tester.element(finder).visitAncestorElements((element) {
    if (element.widget is Scrollable) {
      final viewport = tester.getRect(
        find.byElementPredicate((candidate) => identical(candidate, element)),
      );
      expect(bounds.top, greaterThanOrEqualTo(viewport.top - .1));
      expect(bounds.bottom, lessThanOrEqualTo(viewport.bottom + .1));
    }
    return true;
  });
}

void main() {
  setUpAll(loadDesignFonts);
  for (final sample in const [
    ('address', 390.0, false, true),
    ('tags', 360.0, true, false),
  ]) {
    testWidgets(
      'visual label regression ${sample.$1} width=${sample.$2} scale=2',
      (tester) async {
        tester.view.physicalSize = Size(sample.$2, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final harness = await DesignScenarioHarness.create();
        try {
          await tester.pumpWidget(
            _app(
              harness,
              dark: sample.$3,
              editing: sample.$4,
              scale: 2,
              keyboard: 0,
            ),
          );
          await tester.pumpAndSettle();
          await _showField(tester, sample.$1);
          _expectRenderedLabel(tester, sample.$1, 0);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await harness.close();
        }
      },
    );
  }
  for (final width in [360.0, 390.0]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        for (final editing in [false, true]) {
          testWidgets(
            'full profile labels width=$width dark=$dark scale=$scale editing=$editing',
            (tester) async {
              tester.view.physicalSize = Size(width, 800);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              final harness = await DesignScenarioHarness.create();
              try {
                await tester.pumpWidget(
                  _app(
                    harness,
                    dark: dark,
                    editing: editing,
                    scale: scale,
                    keyboard: 0,
                  ),
                );
                await tester.pumpAndSettle();
                final state = tester.state(find.byType(ProfileForm));
                final controllers = {
                  for (final id in _labels.keys)
                    id: tester.widget<TextFormField>(_field(id)).controller!,
                };
                final refreshes = harness.client.refreshes;
                for (final keyboard in [0.0, 280.0]) {
                  await tester.pumpWidget(
                    _app(
                      harness,
                      dark: dark,
                      editing: editing,
                      scale: scale,
                      keyboard: keyboard,
                    ),
                  );
                  await tester.pumpAndSettle();
                  expect(tester.state(find.byType(ProfileForm)), same(state));
                  FocusManager.instance.primaryFocus?.unfocus();
                  await tester.pumpAndSettle();
                  for (final id in _labels.keys) {
                    await _showField(tester, id);
                    _expectRenderedLabel(tester, id, keyboard);
                    expect(
                      tester.getSize(_field(id)).height,
                      greaterThanOrEqualTo(44),
                    );
                    expect(
                      tester.getSemantics(_field(id)).label,
                      contains(_labels[id]),
                    );
                    await tester.tap(_field(id));
                    await tester.pumpAndSettle();
                    expect(
                      tester
                          .widget<EditableText>(
                            find.descendant(
                              of: _field(id),
                              matching: find.byType(EditableText),
                            ),
                          )
                          .focusNode
                          .hasFocus,
                      isTrue,
                    );
                    await _showField(tester, id);
                    _expectRenderedLabel(tester, id, keyboard);
                    expect(
                      tester.widget<TextFormField>(_field(id)).controller,
                      same(controllers[id]),
                    );
                  }
                }
                await tester.enterText(_field('address'), 'invalid/address');
                await tester.sendKeyEvent(LogicalKeyboardKey.enter);
                await tester.pumpAndSettle();
                expect(
                  tester
                      .state<FormFieldState<String>>(_field('address'))
                      .errorText,
                  'Проверьте значение поля',
                );
                expect(controllers['address']!.text, 'invalid/address');
                await _showField(tester, 'address');
                _expectRenderedLabel(tester, 'address', 280);
                expect(
                  tester.getSemantics(_field('address')).label,
                  contains('Адрес (IP или имя домена)'),
                );
                expect(harness.client.mutations, isEmpty);
                expect(harness.client.statusRequests, isEmpty);
                expect(harness.client.refreshes, refreshes);
                expect(tester.takeException(), isNull);
              } finally {
                await tester.pumpWidget(const SizedBox.shrink());
                await harness.close();
              }
            },
          );
        }
      }

      testWidgets(
        'pending full labels preserve locked draft width=$width dark=$dark',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final harness = await DesignScenarioHarness.create();
          final pending = Completer<ApiReply>();
          harness.client.mutationGate = pending;
          try {
            await tester.pumpWidget(
              _app(harness, dark: dark, editing: true, scale: 2, keyboard: 0),
            );
            await tester.pumpAndSettle();
            final save = find.widgetWithText(FilledButton, 'Сохранить');
            await tester.ensureVisible(save);
            await tester.pumpAndSettle();
            await tester.tap(save);
            await tester.pump();
            expect(harness.client.mutations, hasLength(1));
            for (final id in _labels.keys) {
              await _showField(tester, id);
              _expectRenderedLabel(tester, id, 0);
              expect(tester.widget<TextFormField>(_field(id)).enabled, isFalse);
            }
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pump();
            expect(harness.client.mutations, hasLength(1));
            expect(
              tester.widget<TextFormField>(_field('address')).controller!.text,
              harness.profiles.profiles.single.address,
            );
            expect(tester.takeException(), isNull);
          } finally {
            if (!pending.isCompleted)
              pending.completeError(const LocalApiException(ErrorCode.timeout));
            await tester.pumpAndSettle();
            await tester.pumpWidget(const SizedBox.shrink());
            await harness.close();
          }
        },
      );
    }
  }
}
