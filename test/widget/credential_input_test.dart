import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/profiles/credential_input.dart';
import 'package:serverdeck/profiles/profile_presentation.dart';
import 'package:serverdeck/theme/brand_theme.dart';

void main() {
  testWidgets(
    'canonical access fields retain the secret owner across resize and opaque picker input',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey<CredentialInputState>();
      final gate = Completer<String?>();
      final pending = <bool>[];
      int? readyEpoch = 1;
      Widget app(bool dark) => MaterialApp(
        theme: dark ? BrandTheme.dark : BrandTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: CredentialInput(
              key: key,
              creating: false,
              enabled: true,
              compact: true,
              pageTarget: 'Actual target · server.example:22',
              readReadyEpoch: () => readyEpoch,
              pickKey: () => gate.future,
              onPickingChanged: pending.add,
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(false));
      final owner = key.currentState!;
      expect(
        tester.widget<ProfileFieldGrid>(find.byType(ProfileFieldGrid)).children,
        hasLength(6),
      );
      expect(find.text('Actual target · server.example:22'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      await tester.tap(find.text('Сохранить существующий'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Новый приватный ключ').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Выбрать файл ключа'));
      await tester.tap(find.text('Выбрать файл ключа'));
      await tester.pump();
      expect(pending, [true]);
      expect(owner.picking, isTrue);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Показать введённый секрет'),
            )
            .onPressed,
        isNull,
      );
      const secret = ' PRIVATE selected key\r\n ';
      gate.complete(secret);
      await tester.pumpAndSettle();
      expect(pending, [true, false]);
      expect(owner.keyInput.text, secret);
      expect(
        find.text('Имя файла не возвращается: загружено содержимое'),
        findsOneWidget,
      );
      expect(find.textContaining('atlas-demo.key'), findsNothing);
      tester.view.physicalSize = const Size(360, 800);
      await tester.pumpWidget(app(true));
      await tester.pumpAndSettle();
      expect(key.currentState, same(owner));
      expect(owner.keyInput.text, secret);
      final input = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('credential-private-key')),
          matching: find.byType(TextField),
        ),
      );
      expect(input.obscureText, isTrue);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Новый приватный ключ'));
      await tester.tap(find.text('Новый приватный ключ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Новый пароль').last);
      await tester.pumpAndSettle();
      expect(owner.keyInput.text, isEmpty);
      expect(owner.passphrase.text, isEmpty);
      expect(owner.revealed, isFalse);
      expect(
        find.text('Файл не выбран; имя и путь не сохраняются в форме'),
        findsOneWidget,
      );
      readyEpoch = null;
      await tester.pumpWidget(const SizedBox.shrink());
      expect(owner.password.text, isEmpty);
    },
  );

  for (final unavailable in [false, true]) {
    testWidgets(
      'authoritative readiness retires picker without a widget rebuild unavailable=$unavailable',
      (tester) async {
        final key = GlobalKey<CredentialInputState>();
        final gate = Completer<String?>();
        int? readyEpoch = 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: BrandTheme.light,
            home: Scaffold(
              body: CredentialInput(
                key: key,
                creating: true,
                enabled: true,
                readReadyEpoch: () => readyEpoch,
                pickKey: () => gate.future,
              ),
            ),
          ),
        );
        await tester.tap(find.text('Без секрета / удалить'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Новый приватный ключ').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Выбрать файл ключа'));
        await tester.tap(find.text('Выбрать файл ключа'));
        await tester.pump();
        readyEpoch = unavailable ? null : 3;
        gate.complete('PRIVATE KEY MARKER');
        await tester.pumpAndSettle();
        expect(key.currentState!.keyInput.text, isEmpty);
        expect(key.currentState!.picking, false);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'current picker failure is safe and explicit retry preserves selected text verbatim',
    (tester) async {
      final key = GlobalKey<CredentialInputState>();
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.light,
          home: Scaffold(
            body: CredentialInput(
              key: key,
              creating: true,
              enabled: true,
              pickKey: () async {
                attempts++;
                if (attempts == 1) throw StateError('synthetic private path');
                return ' synthetic selected key\r\n ';
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Без секрета / удалить'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Новый приватный ключ').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Выбрать файл ключа'));
      await tester.tap(find.text('Выбрать файл ключа'));
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(key.currentState!.error, startsWith('Не удалось прочитать ключ'));
      expect(find.textContaining('synthetic private path'), findsNothing);
      await tester.ensureVisible(find.text('Выбрать файл ключа'));
      await tester.tap(find.text('Выбрать файл ключа'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(key.currentState!.error, isNull);
      expect(key.currentState!.keyInput.text, ' synthetic selected key\r\n ');
      final owned = key.currentState!.keyInput;
      await tester.pumpWidget(const SizedBox.shrink());
      expect(owned.text, isEmpty);
    },
  );
  for (final fails in [false, true]) {
    testWidgets('retired picker cannot publish after reenable fails=$fails', (
      tester,
    ) async {
      final key = GlobalKey<CredentialInputState>();
      final gate = Completer<String?>();
      Widget view(bool enabled) => MaterialApp(
        theme: BrandTheme.light,
        home: Scaffold(
          body: CredentialInput(
            key: key,
            creating: true,
            enabled: enabled,
            pickKey: () => gate.future,
          ),
        ),
      );
      await tester.pumpWidget(view(true));
      await tester.tap(find.text('Без секрета / удалить'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Новый приватный ключ').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Выбрать файл ключа'));
      await tester.tap(find.text('Выбрать файл ключа'));
      await tester.pump();
      await tester.pumpWidget(view(false));
      await tester.pumpWidget(view(true));
      if (fails) {
        gate.completeError(StateError('synthetic private path'));
      } else {
        gate.complete('PRIVATE KEY MARKER');
      }
      await tester.pumpAndSettle();
      expect(key.currentState!.keyInput.text, isEmpty);
      expect(key.currentState!.error, isNull);
      expect(key.currentState!.picking, false);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Выбрать файл ключа'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'revealed multiline key Enter does not submit and platform newline is retained',
    (tester) async {
      final key = GlobalKey<CredentialInputState>();
      var submissions = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.light,
          home: Scaffold(
            body: CredentialInput(
              key: key,
              creating: true,
              enabled: true,
              onSubmit: () => submissions++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Без секрета / удалить'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Новый приватный ключ').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Показать введённый секрет'));
      await tester.tap(find.text('Показать введённый секрет'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('credential-private-key')),
        'synthetic key',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(submissions, 0);
      // Windows Enter is forwarded to the platform text input. Synthetic
      // key events alone do not generate its editing update in widget tests.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'synthetic key\n',
          selection: TextSelection.collapsed(offset: 14),
        ),
      );
      await tester.pump();
      expect(key.currentState!.keyInput.text, 'synthetic key\n');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'secret text is verbatim, hidden; mode change and disposal clear',
    (tester) async {
      final key = GlobalKey<CredentialInputState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.light,
          home: Scaffold(
            body: CredentialInput(key: key, creating: false, enabled: true),
          ),
        ),
      );
      expect(key.currentState!.action(), {'action': 'keep'});
      await tester.tap(find.text('Сохранить существующий'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Новый пароль').last);
      await tester.pumpAndSettle();
      const secret = ' e\u0301 password ';
      key.currentState!.password.text = secret;
      expect(key.currentState!.action()['password'], secret);
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue,
      );
      final password = key.currentState!.password;
      await tester.tap(find.text('Новый пароль'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Без секрета / удалить').last);
      await tester.pumpAndSettle();
      expect(password.text, isEmpty);
      expect(key.currentState!.action(), {'action': 'remove'});
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'picker result is discarded after disabled form; safe read failure',
    (tester) async {
      final key = GlobalKey<CredentialInputState>();
      final gate = Completer<String?>();
      Widget view(bool enabled) => MaterialApp(
        theme: BrandTheme.light,
        home: Scaffold(
          body: CredentialInput(
            key: key,
            creating: true,
            enabled: enabled,
            pickKey: () => gate.future,
          ),
        ),
      );
      await tester.pumpWidget(view(true));
      await tester.tap(find.text('Без секрета / удалить'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Новый приватный ключ').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Выбрать файл ключа'));
      await tester.tap(find.text('Выбрать файл ключа'));
      await tester.pump();
      expect(key.currentState!.picking, isTrue);
      await tester.pumpWidget(view(false));
      gate.complete('PRIVATE KEY MARKER');
      await tester.pumpAndSettle();
      expect(key.currentState!.keyInput.text, isEmpty);
      expect(key.currentState!.picking, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
