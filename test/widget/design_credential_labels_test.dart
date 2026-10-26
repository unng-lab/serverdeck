import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/profiles/credential_input.dart';
import 'package:serverdeck/profiles/profile_form.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck_protocol/models.dart';

import '../support/design_host.dart' show loadDesignFonts;
import '../support/design_scenario_harness.dart';

const _passphraseLabel = 'Passphrase (необязательно)';
const _keyInstruction = 'Для ввода ключа включите показ или выберите файл';

Widget _app(
  Widget child, {
  bool dark = false,
  double scale = 2,
  bool reduced = true,
  double keyboard = 0,
}) => MaterialApp(
  theme: Motion.theme(dark ? BrandTheme.dark : BrandTheme.light, reduced),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      disableAnimations: reduced,
      viewInsets: EdgeInsets.only(bottom: keyboard),
    ),
    child: child!,
  ),
  home: child,
);

void _frame(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: .4);
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String current, String next) async {
  await _show(tester, find.text(current));
  await tester.tap(find.text(current));
  await tester.pumpAndSettle();
  await _show(tester, find.text(next).last);
  await tester.tap(find.text(next).last);
  await tester.pumpAndSettle();
}

void _expectGlyphs(WidgetTester tester, String text) {
  final finder = find.text(text).last;
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: 'Required credential text must render completely: $text',
  );
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: text.length - 1, extentOffset: text.length),
  );
  expect(boxes, isNotEmpty, reason: 'Last credential glyph is clipped: $text');
  final transform = paragraph.getTransformTo(null);
  final bounds = MatrixUtils.transformRect(
    transform,
    Offset.zero & paragraph.size,
  );
  final glyph = MatrixUtils.transformRect(transform, boxes.last.toRect());
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  final keyboard = MediaQuery.viewInsetsOf(tester.element(finder)).bottom;
  expect(glyph.left, greaterThanOrEqualTo(0));
  expect(glyph.right, lessThanOrEqualTo(size.width));
  expect(glyph.top, greaterThanOrEqualTo(0));
  expect(glyph.bottom, lessThanOrEqualTo(size.height - keyboard));
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

Finder _field(String id) => find.byKey(ValueKey('credential-$id'));

EditableText _editor(WidgetTester tester, String id) => tester.widget(
  find.descendant(of: _field(id), matching: find.byType(EditableText)),
);

Future<void> _expectInstruction(
  WidgetTester tester, {
  required bool enabled,
}) async {
  final helper = find.descendant(
    of: _field('private-key'),
    matching: find.text(_keyInstruction),
  );
  expect(helper, findsOneWidget);
  await _show(tester, helper);
  _expectGlyphs(tester, _keyInstruction);
  expect(tester.getSemantics(helper).label, _keyInstruction);
  final theme = Theme.of(tester.element(helper));
  final rendered = tester.widget<Text>(helper).style!;
  final caption = theme.textTheme.bodySmall!;
  expect(rendered.fontFamily, caption.fontFamily);
  expect(rendered.fontFamilyFallback, caption.fontFamilyFallback);
  expect(rendered.fontSize, caption.fontSize);
  expect(rendered.height, caption.height);
  expect(rendered.fontWeight, caption.fontWeight);
  final material = tester.widget<Material>(
    find.ancestor(of: helper, matching: find.byType(Material)).first,
  );
  final background = material.color ?? theme.canvasColor;
  final foreground = Color.alphaBlend(rendered.color!, background);
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;
  final contrast = (lighter + .05) / (darker + .05);
  expect(
    contrast,
    greaterThanOrEqualTo(4.5),
    reason:
        'Credential helper must remain readable enabled=$enabled; actual contrast=$contrast:1',
  );
  expect(rendered.color!.toARGB32() >>> 24, 255);
  expect(rendered.color, theme.colorScheme.onSurfaceVariant);
  expect(
    tester.getSemantics(_field('private-key')).label,
    contains('Приватный ключ'),
  );
}

Future<void> _expectField(
  WidgetTester tester,
  String id,
  String label, {
  required String value,
  required bool enabled,
  required bool masked,
}) async {
  await _show(tester, find.text(label));
  _expectGlyphs(tester, label);
  final field = tester.widget<TextFormField>(_field(id));
  final editor = _editor(tester, id);
  expect(field.controller!.text, value);
  expect(field.enabled, enabled);
  expect(editor.obscureText, masked);
  expect(tester.getSemantics(_field(id)).label, contains(label));
  expect(tester.getSize(_field(id)).height, greaterThanOrEqualTo(44));
  if (id == 'private-key') {
    if (masked) {
      await _expectInstruction(tester, enabled: enabled);
    } else {
      expect(find.text(_keyInstruction), findsNothing);
    }
  }
}

void main() {
  setUpAll(loadDesignFonts);
  for (final width in [360.0, 390.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'private-key instruction is complete width=$width dark=$dark scale=2',
        (tester) async {
          _frame(tester, width);
          final harness = await DesignScenarioHarness.create();
          final form = ProfileForm(model: harness.profiles);
          try {
            await tester.pumpWidget(_app(form, dark: dark));
            await tester.pumpAndSettle();
            await _choose(
              tester,
              'Без секрета / удалить',
              'Новый приватный ключ',
            );
            await _expectInstruction(tester, enabled: true);
            await _show(tester, _field('private-key'));
            await tester.tap(_field('private-key'));
            await tester.pumpAndSettle();
            expect(_editor(tester, 'private-key').focusNode.hasFocus, isTrue);
            expect(_editor(tester, 'private-key').readOnly, isTrue);
            for (final keyboard in [0.0, 280.0]) {
              await tester.pumpWidget(
                _app(form, dark: dark, keyboard: keyboard),
              );
              await tester.pumpAndSettle();
              await _expectInstruction(tester, enabled: true);
            }
            expect(harness.client.mutations, isEmpty);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await harness.close();
          }
        },
      );
    }
    testWidgets('visual regression private-key label width=$width scale=2', (
      tester,
    ) async {
      _frame(tester, width);
      final harness = await DesignScenarioHarness.create();
      try {
        await tester.pumpWidget(_app(ProfileForm(model: harness.profiles)));
        await tester.pumpAndSettle();
        await _choose(tester, 'Без секрета / удалить', 'Новый приватный ключ');
        await _show(tester, find.text(_passphraseLabel));
        _expectGlyphs(tester, _passphraseLabel);
        expect(harness.client.mutations, isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await harness.close();
      }
    });
  }
  for (final width in [360.0, 390.0]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        for (final reduced in [false, true]) {
          testWidgets(
            'full mode choices width=$width dark=$dark scale=$scale reduced=$reduced',
            (tester) async {
              _frame(tester, width);
              await tester.pumpWidget(
                _app(
                  const Scaffold(
                    body: SingleChildScrollView(
                      padding: EdgeInsets.all(40),
                      child: CredentialInput(creating: false, enabled: true),
                    ),
                  ),
                  dark: dark,
                  scale: scale,
                  reduced: reduced,
                ),
              );
              await tester.pumpAndSettle();
              await _show(tester, find.text('Сохранить существующий'));
              _expectGlyphs(tester, 'Сохранить существующий');
              await tester.tap(find.text('Сохранить существующий'));
              await tester.pumpAndSettle();
              for (final text in [
                'Сохранить существующий',
                'Без секрета / удалить',
                'Новый пароль',
                'Новый приватный ключ',
              ]) {
                await _show(tester, find.text(text).last);
                _expectGlyphs(tester, text);
              }
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox.shrink());
            },
          );
        }

        testWidgets(
          'credential labels and locked form width=$width dark=$dark scale=$scale',
          (tester) async {
            _frame(tester, width);
            final harness = await DesignScenarioHarness.create();
            final pending = Completer<ApiReply>();
            harness.client.mutationGate = pending;
            final form = ProfileForm(
              model: harness.profiles,
              initial: harness.profiles.profiles.single,
            );
            try {
              await tester.pumpWidget(_app(form, dark: dark, scale: scale));
              await tester.pumpAndSettle();
              final refreshes = harness.client.refreshes;
              await _choose(tester, 'Сохранить существующий', 'Новый пароль');
              final credential = tester.state<CredentialInputState>(
                find.byType(CredentialInput),
              );
              await _expectField(
                tester,
                'password',
                'Пароль',
                value: '',
                enabled: true,
                masked: true,
              );
              const password = ' synthetic e\u0301 password ';
              await _show(tester, _field('password'));
              await tester.enterText(_field('password'), password);
              expect(_editor(tester, 'password').focusNode.hasFocus, isTrue);
              await _expectField(
                tester,
                'password',
                'Пароль',
                value: password,
                enabled: true,
                masked: true,
              );
              expect(credential.action()['password'], password);
              expect(harness.client.mutations, isEmpty);
              await _choose(tester, 'Новый пароль', 'Новый приватный ключ');
              expect(credential.password.text, isEmpty);
              for (final entry in {
                'private-key': 'Приватный ключ',
                'passphrase': _passphraseLabel,
              }.entries) {
                await _expectField(
                  tester,
                  entry.key,
                  entry.value,
                  value: '',
                  enabled: true,
                  masked: true,
                );
              }
              expect(_editor(tester, 'private-key').readOnly, isTrue);
              await _show(tester, find.text('Показать введённый секрет'));
              await tester.tap(find.text('Показать введённый секрет'));
              await tester.pumpAndSettle();
              const keyText =
                  '-----BEGIN PRIVATE KEY-----\r\nAQID\r\n-----END PRIVATE KEY-----\r\n';
              const phrase = ' synthetic e\u0301 passphrase ';
              await _show(tester, _field('private-key'));
              await tester.enterText(_field('private-key'), keyText);
              expect(_editor(tester, 'private-key').readOnly, isFalse);
              await tester.sendKeyEvent(LogicalKeyboardKey.enter);
              await tester.pump();
              expect(harness.client.mutations, isEmpty);
              await _show(tester, _field('passphrase'));
              await tester.enterText(_field('passphrase'), phrase);
              expect(_editor(tester, 'passphrase').focusNode.hasFocus, isTrue);
              for (final keyboard in [0.0, 280.0]) {
                await tester.pumpWidget(
                  _app(form, dark: dark, scale: scale, keyboard: keyboard),
                );
                await tester.pumpAndSettle();
                expect(
                  tester.state<CredentialInputState>(
                    find.byType(CredentialInput),
                  ),
                  same(credential),
                );
                await _expectField(
                  tester,
                  'passphrase',
                  _passphraseLabel,
                  value: phrase,
                  enabled: true,
                  masked: false,
                );
                await _expectField(
                  tester,
                  'private-key',
                  'Приватный ключ',
                  value: keyText,
                  enabled: true,
                  masked: false,
                );
              }
              await tester.pumpWidget(_app(form, dark: dark, scale: scale));
              await tester.pumpAndSettle();
              await _show(tester, find.text('Показать введённый секрет'));
              await tester.tap(find.text('Показать введённый секрет'));
              await tester.pumpAndSettle();
              expect(credential.action(), {
                'action': 'replace',
                'kind': 'privateKey',
                'privateKey': keyText,
                'passphrase': phrase,
              });
              await _show(tester, find.text('Сохранить'));
              await tester.tap(find.text('Сохранить'));
              await tester.pump();
              expect(harness.client.mutations, hasLength(1));
              for (final entry in {
                'private-key': ('Приватный ключ', keyText),
                'passphrase': (_passphraseLabel, phrase),
              }.entries) {
                await _expectField(
                  tester,
                  entry.key,
                  entry.value.$1,
                  value: entry.value.$2,
                  enabled: false,
                  masked: true,
                );
                expect(_editor(tester, entry.key).readOnly, isTrue);
              }
              await tester.sendKeyEvent(LogicalKeyboardKey.enter);
              await tester.pump();
              expect(harness.client.mutations, hasLength(1));
              expect(harness.client.statusRequests, isEmpty);
              expect(harness.client.refreshes, refreshes);
              final ownedKey = credential.keyInput;
              final ownedPhrase = credential.passphrase;
              harness.showReadiness(ReadinessState.storageBlocked);
              await tester.pumpAndSettle();
              expect(find.byType(CredentialInput), findsNothing);
              expect(ownedKey.text, isEmpty);
              expect(ownedPhrase.text, isEmpty);
              expect(tester.takeException(), isNull);
            } finally {
              if (!pending.isCompleted) {
                pending.completeError(
                  const LocalApiException(ErrorCode.timeout),
                );
              }
              await tester.pumpAndSettle();
              await tester.pumpWidget(const SizedBox.shrink());
              await harness.close();
            }
          },
        );
      }

      testWidgets(
        'picker locks readable labels and discards retired result width=$width dark=$dark',
        (tester) async {
          _frame(tester, width);
          final key = GlobalKey<CredentialInputState>();
          final picker = Completer<String?>();
          var calls = 0;
          var submissions = 0;
          int? readyEpoch = 1;
          await tester.pumpWidget(
            _app(
              Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(40),
                  child: CredentialInput(
                    key: key,
                    creating: true,
                    enabled: true,
                    readReadyEpoch: () => readyEpoch,
                    pickKey: () {
                      calls++;
                      return picker.future;
                    },
                    onSubmit: () => submissions++,
                  ),
                ),
              ),
              dark: dark,
            ),
          );
          await tester.pumpAndSettle();
          await _choose(
            tester,
            'Без секрета / удалить',
            'Новый приватный ключ',
          );
          const oldKey = ' synthetic previous selected key\r\n ';
          const phrase = ' synthetic passphrase ';
          key.currentState!.keyInput.text = oldKey;
          await _show(tester, _field('passphrase'));
          await tester.enterText(_field('passphrase'), phrase);
          await _show(tester, find.text('Выбрать файл ключа'));
          await tester.tap(find.text('Выбрать файл ключа'));
          await tester.pump();
          expect(calls, 1);
          expect(key.currentState!.picking, isTrue);
          for (final entry in {
            'private-key': ('Приватный ключ', oldKey),
            'passphrase': (_passphraseLabel, phrase),
          }.entries) {
            await _expectField(
              tester,
              entry.key,
              entry.value.$1,
              value: entry.value.$2,
              enabled: false,
              masked: true,
            );
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(submissions, 0);
          expect(calls, 1);
          readyEpoch = null;
          picker.complete('synthetic retired picker result');
          await tester.pumpAndSettle();
          expect(key.currentState!.keyInput.text, oldKey);
          expect(key.currentState!.passphrase.text, phrase);
          expect(key.currentState!.picking, isFalse);
          expect(key.currentState!.error, isNull);
          expect(submissions, 0);
          expect(calls, 1);
          final ownedKey = key.currentState!.keyInput;
          final ownedPhrase = key.currentState!.passphrase;
          await tester.pumpWidget(const SizedBox.shrink());
          expect(ownedKey.text, isEmpty);
          expect(ownedPhrase.text, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
