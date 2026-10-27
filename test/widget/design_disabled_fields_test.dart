import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/profiles/credential_input.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/profiles/profile_form.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck_protocol/models.dart';

import '../contract/mutation_controller_test.dart' show MutationClient;
import '../contract/profile_controller_test.dart' as fixture;
import '../support/design_automation_fixtures.dart';
import '../support/design_host.dart' show loadDesignFonts;

void main() {
  for (final dark in [false, true]) {
    final theme = dark ? BrandTheme.dark : BrandTheme.light;

    testWidgets('disabled password stays opaque and masked dark=$dark', (
      tester,
    ) async {
      final key = GlobalKey<CredentialInputState>();
      var submissions = 0;
      Widget view(bool enabled) => MaterialApp(
        theme: theme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: CredentialInput(
              key: key,
              creating: true,
              enabled: enabled,
              onSubmit: () => submissions++,
            ),
          ),
        ),
      );
      await tester.pumpWidget(view(true));
      await _chooseCredential(tester, 'Без секрета / удалить', 'Новый пароль');
      final field = find.byKey(const ValueKey('credential-password'));
      const secret = ' synthetic password ';
      await tester.enterText(field, secret);

      await tester.pumpWidget(view(false));
      _expectDisabledField(tester, field, secret, masked: true);
      await tester.tap(field, warnIfMissed: false);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(submissions, 0);
      expect(key.currentState!.password.text, secret);
      final owned = key.currentState!.password;
      await tester.pumpWidget(const SizedBox.shrink());
      expect(owned.text, isEmpty);
    });

    testWidgets(
      'pending picker keeps opaque masked key and passphrase dark=$dark',
      (tester) async {
        final key = GlobalKey<CredentialInputState>();
        final picker = Completer<String?>();
        var submissions = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: SingleChildScrollView(
                child: CredentialInput(
                  key: key,
                  creating: true,
                  enabled: true,
                  pickKey: () => picker.future,
                  onSubmit: () => submissions++,
                ),
              ),
            ),
          ),
        );
        await _chooseCredential(
          tester,
          'Без секрета / удалить',
          'Новый приватный ключ',
        );
        const syntheticKey = ' synthetic key\r\n ';
        const syntheticPassphrase = ' synthetic passphrase ';
        key.currentState!.keyInput.text = syntheticKey;
        await tester.enterText(
          find.byKey(const ValueKey('credential-passphrase')),
          syntheticPassphrase,
        );
        await tester.ensureVisible(find.text('Выбрать файл ключа'));
        await tester.tap(find.text('Выбрать файл ключа'));
        await tester.pump();
        expect(key.currentState!.picking, isTrue);
        _expectDisabledField(
          tester,
          find.byKey(const ValueKey('credential-private-key')),
          syntheticKey,
          masked: true,
        );
        _expectDisabledField(
          tester,
          find.byKey(const ValueKey('credential-passphrase')),
          syntheticPassphrase,
          masked: true,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Чтение ключа'),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<CheckboxListTile>(find.byType(CheckboxListTile))
              .onChanged,
          isNull,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(submissions, 0);
        expect(key.currentState!.keyInput.text, syntheticKey);
        expect(key.currentState!.passphrase.text, syntheticPassphrase);
        picker.complete(null);
        await tester.pumpAndSettle();
        expect(key.currentState!.picking, isFalse);
        expect(key.currentState!.keyInput.text, syntheticKey);
        expect(key.currentState!.passphrase.text, syntheticPassphrase);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    for (final reloading in [false, true]) {
      testWidgets(
        'profile disabled fields retain opaque draft and block submit dark=$dark reloading=$reloading',
        (tester) async {
          final client = MutationClient();
          final bootstrap = fixture.ModelBootstrap(client)
            ..show(ReadinessState.ready);
          final model = ProfileController(bootstrap: bootstrap);
          client.events.add(fixture.snapshot());
          final save = Completer<ApiReply>();
          client.send = () => save.future;
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: ProfileForm(model: model, initial: model.profiles.single),
            ),
          );
          await tester.enterText(_profileField('name'), 'Synthetic draft');
          await _chooseCredential(
            tester,
            'Сохранить существующий',
            'Новый пароль',
          );
          const secret = ' synthetic profile password ';
          await tester.enterText(
            find.byKey(const ValueKey('credential-password')),
            secret,
          );
          await tester.ensureVisible(find.text('Сохранить'));
          await tester.tap(find.text('Сохранить'));
          await tester.pump();
          expect(client.sent, hasLength(1));
          if (reloading) {
            save.completeError(
              const LocalApiException(ErrorCode.revisionConflict),
            );
            await tester.pumpAndSettle();
            client.refreshGate = Completer<void>();
            await tester.ensureVisible(find.text('Перечитать профиль'));
            await tester.tap(find.text('Перечитать профиль'));
            await tester.pump();
          } else {
            expect(find.text('Сохранение'), findsOneWidget);
          }
          for (final entry in const {
            'name': 'Synthetic draft',
            'address': '192.0.2.1',
            'port': '22',
            'user': 'admin',
            'tags': 'production',
          }.entries) {
            _expectDisabledField(tester, _profileField(entry.key), entry.value);
          }
          _expectDisabledField(
            tester,
            find.byKey(const ValueKey('credential-password')),
            secret,
            masked: true,
          );
          final saveButton = find.widgetWithText(FilledButton, 'Сохранить');
          expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(client.sent, hasLength(1));
          if (reloading) {
            client.refreshGate!.complete();
          } else {
            save.completeError(const LocalApiException(ErrorCode.timeout));
          }
          await tester.pumpAndSettle();
          expect(client.sent, hasLength(1));
          await tester.pumpWidget(const SizedBox.shrink());
          model.dispose();
          await bootstrap.close();
          await client.events.close();
          await client.readErrors.close();
        },
      );
    }
  }

  group('locked automation editor values', () {
    setUpAll(loadDesignFonts);
    for (final frame in const [
      Size(360, 800),
      Size(390, 800),
      Size(800, 600),
      Size(1100, 760),
    ]) {
      for (final dark in [false, true]) {
        for (final scale in [1.0, 2.0]) {
          for (final saving in [false, true]) {
            testWidgets(
              'opaque exact draft ${saving ? 'saving' : 'requestRetained'} dark=$dark ${frame.width.toInt()}x${frame.height.toInt()} scale=$scale',
              (tester) async {
                final name = TextEditingController(
                  text: '  Сохранённое имя 日本語  ',
                );
                final description = TextEditingController(
                  text: 'Точное описание 日本語\nВторая строка без потери draft.',
                );
                final body = TextEditingController(
                  text: jsonEncode(DesignAutomationFixtures.body()),
                );
                final controllers = {
                  'name': name,
                  'description': description,
                  'body': body,
                };
                final values = {
                  for (final entry in controllers.entries)
                    entry.key: entry.value.text,
                };
                final callbacks = {
                  'save': 0,
                  'validate': 0,
                  'close': 0,
                  'bodyChanged': 0,
                };
                tester.view.devicePixelRatio = 1;
                tester.view.physicalSize = frame;
                try {
                  await tester.pumpWidget(
                    MaterialApp(
                      debugShowCheckedModeBanner: false,
                      theme: Motion.theme(
                        dark ? BrandTheme.dark : BrandTheme.light,
                        true,
                      ),
                      builder: (context, child) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          disableAnimations: true,
                          textScaler: TextScaler.linear(scale),
                        ),
                        child: child!,
                      ),
                      home: Scaffold(
                        body: AutomationProfileEditorDialog(
                          name: name,
                          description: description,
                          body: body,
                          saving: saving,
                          requestRetained: !saving,
                          validating: false,
                          canSave: true,
                          canValidate: !saving,
                          onSave: () =>
                              callbacks['save'] = callbacks['save']! + 1,
                          onValidate: () => callbacks['validate'] =
                              callbacks['validate']! + 1,
                          onClose: () =>
                              callbacks['close'] = callbacks['close']! + 1,
                          onBodyChanged: (_) => callbacks['bodyChanged'] =
                              callbacks['bodyChanged']! + 1,
                        ),
                      ),
                    ),
                  );
                  await tester.pumpAndSettle();
                  expect(tester.takeException(), isNull);
                  expect(
                    tester
                        .widget<FilledButton>(
                          find.widgetWithText(FilledButton, 'Сохранить версию'),
                        )
                        .onPressed,
                    isNull,
                  );
                  // Retaining a request keeps the existing explicit read
                  // capability; saving excludes it. Neither is invoked here.
                  expect(
                    tester
                            .widget<OutlinedButton>(
                              find.widgetWithText(
                                OutlinedButton,
                                'Проверить без сохранения',
                              ),
                            )
                            .onPressed ==
                        null,
                    saving,
                  );
                  for (final entry in controllers.entries) {
                    final field = find.byWidgetPredicate(
                      (widget) =>
                          widget is TextField &&
                          identical(widget.controller, entry.value),
                    );
                    expect(field, findsOneWidget);
                    await tester.ensureVisible(field);
                    await tester.pumpAndSettle();
                    _expectDisabledField(
                      tester,
                      field,
                      values[entry.key]!,
                      typography: entry.key == 'body'
                          ? BrandTypography.log
                          : BrandTypography.body,
                    );
                    final editor = tester.widget<EditableText>(
                      find.descendant(
                        of: field,
                        matching: find.byType(EditableText),
                      ),
                    );
                    expect(
                      editor.style.color,
                      Theme.of(tester.element(field)).colorScheme.onSurface,
                    );
                    await tester.tap(field, warnIfMissed: false);
                    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
                    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
                    await tester.pump();
                    expect(editor.focusNode.hasFocus, isFalse);
                    expect(entry.value.text, values[entry.key]);
                  }
                  expect(callbacks.values, everyElement(0));
                  expect(tester.takeException(), isNull);
                } finally {
                  await tester.pumpWidget(const SizedBox.shrink());
                  name.dispose();
                  description.dispose();
                  body.dispose();
                  tester.view.resetPhysicalSize();
                  tester.view.resetDevicePixelRatio();
                }
              },
            );
          }
        }
      }
    }
  });

  group('locked generic JSON editor values', () {
    setUpAll(loadDesignFonts);
    for (final frame in const [
      Size(360, 800),
      Size(390, 800),
      Size(800, 600),
      Size(1100, 760),
    ]) {
      for (final dark in [false, true]) {
        for (final scale in [1.0, 2.0]) {
          for (final saving in [false, true]) {
            testWidgets(
              'opaque exact JSON ${saving ? 'saving' : 'requestRetained'} dark=$dark ${frame.width.toInt()}x${frame.height.toInt()} scale=$scale',
              (tester) async {
                const text =
                    '  {"lifetimeSeconds":0,"note":"日本語 exact draft"}\n ';
                final input = TextEditingController(text: text);
                var continues = 0, changes = 0, closes = 0;
                tester.view.devicePixelRatio = 1;
                tester.view.physicalSize = frame;
                try {
                  await tester.pumpWidget(
                    MaterialApp(
                      theme: Motion.theme(
                        dark ? BrandTheme.dark : BrandTheme.light,
                        true,
                      ),
                      builder: (context, child) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          disableAnimations: true,
                          textScaler: TextScaler.linear(scale),
                        ),
                        child: child!,
                      ),
                      home: Scaffold(
                        body: AutomationJsonEditorDialog(
                          title: 'Точный JSON',
                          input: input,
                          saving: saving,
                          requestRetained: !saving,
                          onContinue: () => continues++,
                          onChanged: (_) => changes++,
                          onClose: () => closes++,
                        ),
                      ),
                    ),
                  );
                  await tester.pumpAndSettle();
                  final field = find.byWidgetPredicate(
                    (widget) =>
                        widget is TextField &&
                        identical(widget.controller, input),
                  );
                  await tester.ensureVisible(field);
                  await tester.pumpAndSettle();
                  _expectDisabledField(
                    tester,
                    field,
                    text,
                    typography: BrandTypography.log,
                  );
                  expect(
                    tester.widget<TextField>(field).controller,
                    same(input),
                  );
                  expect(
                    tester
                        .widget<FilledButton>(
                          find.widgetWithText(FilledButton, 'Продолжить'),
                        )
                        .onPressed,
                    isNull,
                  );
                  await tester.tap(field, warnIfMissed: false);
                  await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
                  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
                  await tester.pump();
                  expect(input.text, text);
                  expect([continues, changes, closes], everyElement(0));
                  expect(tester.takeException(), isNull);
                } finally {
                  await tester.pumpWidget(const SizedBox.shrink());
                  input.dispose();
                  tester.view.resetPhysicalSize();
                  tester.view.resetDevicePixelRatio();
                }
              },
            );
          }
        }
      }
    }
  });
}

Future<void> _chooseCredential(
  WidgetTester tester,
  String current,
  String next,
) async {
  await tester.ensureVisible(find.text(current));
  await tester.tap(find.text(current));
  await tester.pumpAndSettle();
  await tester.tap(find.text(next).last);
  await tester.pumpAndSettle();
}

Finder _profileField(String field) => find.byKey(ValueKey('profile-$field'));

void _expectDisabledField(
  WidgetTester tester,
  Finder field,
  String value, {
  bool masked = false,
  TextStyle typography = BrandTypography.body,
}) {
  final enabled = switch (tester.widget(field)) {
    TextFormField(:final enabled) => enabled,
    TextField(:final enabled) => enabled,
    _ => throw StateError('Expected a text field'),
  };
  expect(enabled, isFalse);
  final editor = tester.widget<EditableText>(
    find.descendant(of: field, matching: find.byType(EditableText)),
  );
  final decorator = tester.widget<InputDecorator>(
    find.descendant(of: field, matching: find.byType(InputDecorator)),
  );
  expect(editor.controller.text, value);
  expect(editor.readOnly, isTrue);
  expect(editor.focusNode.canRequestFocus, isFalse);
  expect(editor.focusNode.hasFocus, isFalse);
  expect(editor.obscureText, masked);
  final color = editor.style.color!;
  final surface = decorator.decoration.fillColor!;
  final contrast = _contrast(Color.alphaBlend(color, surface), surface);
  expect(surface.a, 1);
  expect(
    color.toARGB32() >>> 24,
    255,
    reason: 'Disabled value must be opaque; actual contrast is $contrast:1',
  );
  expect(contrast, greaterThanOrEqualTo(4.5));
  expect(editor.style.fontFamily, typography.fontFamily);
  expect(editor.style.fontFamilyFallback, typography.fontFamilyFallback);
  expect(editor.style.fontSize, typography.fontSize);
  expect(editor.style.fontWeight, typography.fontWeight);
  expect(editor.style.height, typography.height);
}

double _contrast(Color a, Color b) {
  final aLuminance = a.computeLuminance();
  final bLuminance = b.computeLuminance();
  final lighter = aLuminance > bLuminance ? aLuminance : bLuminance;
  final darker = aLuminance > bLuminance ? bLuminance : aLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
