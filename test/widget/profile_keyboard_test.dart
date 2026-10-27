import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/profiles/profile_form.dart';
import 'package:serverdeck/profiles/credential_input.dart';
import 'package:serverdeck/profiles/profile_delete.dart';
import 'package:serverdeck/settings/settings_form.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck_protocol/models.dart';

import '../contract/profile_controller_test.dart' as fixture;
import '../contract/mutation_controller_test.dart' show MutationClient;

void main() {
  late MutationClient client;
  late fixture.ModelBootstrap bootstrap;
  late ProfileController model;
  late FocusNode launcher;
  setUp(() {
    client = MutationClient();
    bootstrap = fixture.ModelBootstrap(client)..show(ReadinessState.ready);
    model = ProfileController(bootstrap: bootstrap);
    client.events.add(fixture.snapshot());
    launcher = FocusNode();
    client.send = () async => throw const LocalApiException(ErrorCode.timeout);
  });
  tearDown(() async {
    launcher.dispose();
    model.dispose();
    await bootstrap.close();
    await client.events.close();
    await client.readErrors.close();
  });
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: OutlinedButton(
              focusNode: launcher,
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) =>
                    ProfileForm(model: model, initial: model.profiles.single),
              ),
              child: const Text('Открыть профиль'),
            ),
          ),
        ),
      ),
    );
    launcher.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
  }

  Finder field(String name) => find.byKey(ValueKey('profile-$name'));
  bool focused(String name, WidgetTester tester) => tester
      .widget<EditableText>(
        find.descendant(of: field(name), matching: find.byType(EditableText)),
      )
      .focusNode
      .hasFocus;

  testWidgets(
    'Enter in valid single-line field submits once; Esc closes unknown outcome',
    (tester) async {
      await open(tester);
      await tester.enterText(field('name'), 'Keyboard draft');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(client.sent, hasLength(1));
      expect(find.text('Сохранение не подтверждено'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(client.sent, hasLength(1));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ProfileForm), findsNothing);
      expect(launcher.hasFocus, true);
      expect(client.sent, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'invalid Enter and multiline Enter never save; Tab and ShiftTab traverse fields',
    (tester) async {
      await open(tester);
      await tester.enterText(field('name'), '');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(client.sent, isEmpty);
      expect(find.text('Проверьте значение поля'), findsWidgets);
      await tester.enterText(field('name'), 'Valid');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focused('address', tester), true);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(focused('name', tester), true);
      await tester.enterText(field('tags'), 'one\ntwo');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(client.sent, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(launcher.hasFocus, true);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('Space activates save once and Escape keeps form cleanup', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(field('name'), 'Space draft');
    final save = find.widgetWithText(FilledButton, 'Сохранить');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    Focus.of(tester.element(find.text('Сохранить'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(client.sent, hasLength(1));
    expect(find.text('Сохранение не подтверждено'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(client.sent, hasLength(1));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ProfileForm), findsNothing);
    expect(launcher.hasFocus, isTrue);
    expect(client.sent, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'Esc cancels transient secret and clears owned buffer before disposal',
    (tester) async {
      await open(tester);
      await tester.ensureVisible(find.text('Сохранить существующий'));
      await tester.tap(find.text('Сохранить существующий'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Новый пароль').last);
      await tester.pumpAndSettle();
      final credentials = tester.state<CredentialInputState>(
        find.byType(CredentialInput),
      );
      final owned = credentials.password;
      await tester.enterText(
        find.byKey(const ValueKey('credential-password')),
        ' synthetic secret ',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ProfileForm), findsNothing);
      expect(owned.text, isEmpty);
      expect(client.sent, isEmpty);
      expect(launcher.hasFocus, true);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'numpad Enter and IME done each submit only their explicit action',
    (tester) async {
      await open(tester);
      await tester.enterText(field('name'), 'Numpad');
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pumpAndSettle();
      expect(client.sent, hasLength(1));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Открыть профиль'));
      await tester.pumpAndSettle();
      await tester.enterText(field('name'), 'IME');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(client.sent, hasLength(2));
      expect(client.sent[0].id, isNot(client.sent[1].id));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Enter in password submits; loss-ready Esc still clears draft and restores focus',
    (tester) async {
      await open(tester);
      await tester.ensureVisible(find.text('Сохранить существующий'));
      await tester.tap(find.text('Сохранить существующий'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Новый пароль').last);
      await tester.pumpAndSettle();
      final credentials = tester.state<CredentialInputState>(
        find.byType(CredentialInput),
      );
      final owned = credentials.password;
      await tester.enterText(
        find.byKey(const ValueKey('credential-password')),
        ' synthetic password ',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(client.sent, hasLength(1));
      bootstrap.show(ReadinessState.storageBlocked);
      await tester.pumpAndSettle();
      expect(find.text(' synthetic password '), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ProfileForm), findsNothing);
      expect(owned.text, isEmpty);
      expect(launcher.hasFocus, true);
      expect(client.sent, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final deleting in [false, true]) {
    testWidgets(
      'button Enter sends once and Esc closes unknown deleting=$deleting',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: BrandTheme.light,
            home: Builder(
              builder: (context) => Scaffold(
                body: OutlinedButton(
                  focusNode: launcher,
                  onPressed: () => showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => deleting
                        ? ProfileDelete(
                            model: model,
                            initial: model.profiles.single,
                          )
                        : SettingsForm(model: model),
                  ),
                  child: const Text('Открыть'),
                ),
              ),
            ),
          ),
        );
        launcher.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(client.sent, hasLength(1));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(client.sent, hasLength(1));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          find.byType(deleting ? ProfileDelete : SettingsForm),
          findsNothing,
        );
        expect(launcher.hasFocus, true);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
