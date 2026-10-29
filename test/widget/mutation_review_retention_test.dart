import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/profiles/credential_input.dart';
import 'package:serverdeck/profiles/mutation_status.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/profiles/profile_delete.dart';
import 'package:serverdeck/profiles/profile_form.dart';
import 'package:serverdeck/settings/settings_form.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck_protocol/models.dart';

import '../contract/mutation_controller_test.dart' show MutationClient;
import '../contract/profile_controller_test.dart' as fixture;

const _syntheticKey =
    '-----BEGIN PRIVATE KEY-----\nc3ludGhldGlj\n-----END PRIVATE KEY-----\n';

void main() {
  for (final theme in [BrandTheme.light, BrandTheme.dark]) {
    for (final scale in [1.0, 2.0]) {
      final variant = '${theme.brightness.name} ${scale * 100}%';
      testWidgets(
        'profile review preserves actual draft and secret owner $variant',
        (tester) async {
          final h = _Owners();
          final capturedTarget = h.model.profiles.single;
          final gate = Completer<ApiReply>();
          h.client.send = () => gate.future;
          try {
            await _mount(
              tester,
              theme,
              scale,
              ProfileForm(
                model: h.model,
                initial: capturedTarget,
                asPage: true,
              ),
            );
            final formState = tester.state(find.byType(ProfileForm));
            final name = find.byKey(const ValueKey('profile-name'));
            await tester.enterText(name, 'Сохранённый черновик');
            final nameController = tester
                .widget<TextFormField>(name)
                .controller!;
            await _choose<CredentialChoice>(
              tester,
              CredentialChoice.privateKey,
              'Новый приватный ключ',
            );
            await _tap(tester, 'Показать введённый секрет');
            final secret = find.byKey(const ValueKey('credential-private-key'));
            await tester.enterText(secret, _syntheticKey);
            final secretState = tester.state<CredentialInputState>(
              find.byType(CredentialInput),
            );
            final secretController = tester
                .widget<TextFormField>(secret)
                .controller!;
            final secretFocus = tester
                .widget<EditableText>(
                  find.descendant(
                    of: secret,
                    matching: find.byType(EditableText),
                  ),
                )
                .focusNode;
            expect(secretFocus.hasFocus, isTrue);
            await _tap(tester, 'Сохранить');
            expect(h.client.sent, hasLength(1));
            final request = h.client.sent.single;
            _expectReviewHeading();
            expect(
              find.text(
                '${capturedTarget.name} · ${capturedTarget.address}:${capturedTarget.port}',
              ),
              findsOneWidget,
            );
            expect(tester.state(find.byType(ProfileForm)), same(formState));
            expect(find.byKey(const ValueKey('profile-name')), findsNothing);
            expect(
              tester
                  .widget<TextFormField>(
                    find.byKey(
                      const ValueKey('profile-name'),
                      skipOffstage: false,
                    ),
                  )
                  .controller,
              same(nameController),
            );
            expect(
              tester.state<CredentialInputState>(
                find.byType(CredentialInput, skipOffstage: false),
              ),
              same(secretState),
            );
            expect(secretState.widget.enabled, isFalse);
            expect(secretFocus.hasFocus, isFalse);
            expect(nameController.text, 'Сохранённый черновик');
            expect(secretController.text, _syntheticKey);
            for (var i = 0; i < 4; i++) {
              await tester.sendKeyEvent(LogicalKeyboardKey.tab);
              await tester.pumpAndSettle();
              expect(secretFocus.hasFocus, isFalse);
            }
            gate.completeError(const LocalApiException(ErrorCode.validation));
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<MutationStatus>(find.byType(MutationStatus))
                  .controller
                  .requestId,
              request.id,
            );
            await _tap(tester, 'Исправить ввод');
            expect(tester.state(find.byType(ProfileForm)), same(formState));
            expect(
              tester.state<CredentialInputState>(find.byType(CredentialInput)),
              same(secretState),
            );
            expect(
              tester.widget<TextFormField>(name).controller,
              same(nameController),
            );
            expect(secretController.text, _syntheticKey);
            expect(nameController.text, 'Сохранённый черновик');
            expect(h.client.sent, hasLength(1));
            h.client.send = () async =>
                throw const LocalApiException(ErrorCode.validation);
            await _tap(tester, 'Сохранить');
            _expectReviewHeading();
            h.bootstrap.show(ReadinessState.unavailable);
            await tester.pumpAndSettle();
            expect(
              find.byType(CredentialInput, skipOffstage: false),
              findsNothing,
            );
            expect(secretState.mounted, isFalse);
            expect(secretController.text, isEmpty);
            expect(find.byType(MutationStatus), findsNothing);
            expect(h.client.sent, hasLength(2));
            expect(h.client.queried, isEmpty);
            expect(tester.takeException(), isNull);
          } finally {
            if (!gate.isCompleted)
              if (h.client.sent.isNotEmpty) {
                gate.completeError(
                  const LocalApiException(ErrorCode.validation),
                );
              } else {
                gate.complete(ApiReply(fixture.fixtureGeneration, const {}));
              }
            await tester.pumpAndSettle();
            await h.close(tester);
          }
        },
      );

      testWidgets(
        'settings conflict review keeps draft until explicit reload $variant',
        (tester) async {
          final h = _Owners();
          h.client.send = () async =>
              throw const LocalApiException(ErrorCode.revisionConflict);
          try {
            await _mount(
              tester,
              theme,
              scale,
              SettingsForm(model: h.model, asPage: true),
            );
            final form = tester.state(find.byType(SettingsForm));
            await _choose<ThemePreference>(
              tester,
              ThemePreference.light,
              'Светлая',
            );
            await _tap(tester, 'Сохранить настройки');
            _expectReviewHeading();
            expect(tester.state(find.byType(SettingsForm)), same(form));
            final hiddenTheme = tester.widget<MotionDropdown<ThemePreference>>(
              find.byType(MotionDropdown<ThemePreference>, skipOffstage: false),
            );
            expect(hiddenTheme.initialValue, ThemePreference.light);
            expect(find.byType(MotionDropdown<ThemePreference>), findsNothing);
            for (final value in const [
              'Изменение настроек',
              'Конфликт ревизии',
              'Черновик сохранён',
              'Перечитайте данные и проверьте изменения',
              'Подтверждённый конфликт не является неизвестным исходом записи',
            ]) {
              expect(find.text(value), findsWidgets);
            }
            final request = h.client.sent.single;
            expect(
              tester
                  .widget<MutationStatus>(find.byType(MutationStatus))
                  .controller
                  .requestId,
              request.id,
            );
            final before = h.client.refreshes;
            await tester.pump(const Duration(seconds: 1));
            expect(h.client.refreshes, before);
            expect(h.client.sent, hasLength(1));
            await _tap(tester, 'Перечитать настройки');
            expect(h.client.refreshes, before + 1);
            expect(tester.state(find.byType(SettingsForm)), same(form));
            expect(
              tester
                  .widget<MotionDropdown<ThemePreference>>(
                    find.byType(MotionDropdown<ThemePreference>),
                  )
                  .initialValue,
              ThemePreference.dark,
            );
            expect(h.client.sent, hasLength(1));
            expect(h.client.queried, isEmpty);
            expect(tester.takeException(), isNull);
          } finally {
            await h.close(tester);
          }
        },
      );

      testWidgets(
        'delete review returns to same confirmation without dispatch $variant',
        (tester) async {
          final h = _Owners();
          h.client.send = () async =>
              throw const LocalApiException(ErrorCode.validation);
          try {
            await _mount(
              tester,
              theme,
              scale,
              ProfileDelete(
                model: h.model,
                initial: h.model.profiles.single,
                asPage: true,
              ),
            );
            final form = tester.state(find.byType(ProfileDelete));
            await _tap(tester, 'Цель и последствия проверены');
            await _tap(tester, 'Удалить профиль');
            _expectReviewHeading();
            expect(tester.state(find.byType(ProfileDelete)), same(form));
            expect(find.byType(CheckboxListTile), findsNothing);
            expect(
              tester
                  .widget<CheckboxListTile>(
                    find.byType(CheckboxListTile, skipOffstage: false),
                  )
                  .value,
              isTrue,
            );
            expect(h.client.sent, hasLength(1));
            await _tap(tester, 'Вернуться к подтверждению');
            expect(tester.state(find.byType(ProfileDelete)), same(form));
            expect(
              tester
                  .widget<CheckboxListTile>(find.byType(CheckboxListTile))
                  .value,
              isTrue,
            );
            expect(h.client.sent, hasLength(1));
            h.bootstrap.show(ReadinessState.unavailable);
            await tester.pumpAndSettle();
            expect(
              find.byType(CheckboxListTile, skipOffstage: false),
              findsNothing,
            );
            expect(find.byType(MutationStatus), findsNothing);
            expect(tester.takeException(), isNull);
          } finally {
            await h.close(tester);
          }
        },
      );
    }
  }
}

void _expectReviewHeading() => expect(
  find.byWidgetPredicate(
    (w) =>
        w is Semantics &&
        w.properties.header == true &&
        w.child is Text &&
        (w.child! as Text).data == 'Сохранение требует проверки',
  ),
  findsOneWidget,
);

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _choose<T>(WidgetTester tester, T choice, String label) async {
  final input = find.byType(MotionDropdown<T>);
  await tester.ensureVisible(input);
  await tester.tap(input);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _mount(
  WidgetTester tester,
  ThemeData theme,
  double scale,
  Widget child,
) async {
  tester.view.physicalSize = const Size(390, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

class _Owners {
  _Owners() {
    bootstrap = fixture.ModelBootstrap(client)..show(ReadinessState.ready);
    model = ProfileController(bootstrap: bootstrap);
    client.events.add(fixture.snapshot());
  }
  final client = MutationClient();
  late final fixture.ModelBootstrap bootstrap;
  late final ProfileController model;
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
    await bootstrap.close();
    await client.events.close();
    await client.readErrors.close();
  }
}
