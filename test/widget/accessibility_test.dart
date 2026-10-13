import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/profiles/profile_delete.dart';
import 'package:serverdeck/profiles/profile_form.dart';
import 'package:serverdeck/settings/settings_form.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck_protocol/models.dart';

import '../contract/mutation_controller_test.dart' show MutationClient;
import '../contract/profile_controller_test.dart' as fixture;

enum _Form { profile, settings, delete }

void main() {
  for (final dark in [false, true]) {
    for (final size in const [
      Size(1100, 760),
      Size(800, 600),
      Size(360, 800),
      Size(390, 800),
    ]) {
      for (final form in _Form.values) {
        for (final conflict in [false, true]) {
          testWidgets(
            'error actions/draft/focus at200 $size dark=$dark form=$form conflict=$conflict',
            (tester) async {
              tester.view.physicalSize = size;
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              final client = MutationClient();
              final bootstrap = fixture.ModelBootstrap(client)
                ..show(ReadinessState.ready);
              final model = ProfileController(bootstrap: bootstrap);
              client.events.add(fixture.snapshot());
              final launcher = FocusNode();
              client.send = () async => throw LocalApiException(
                conflict ? ErrorCode.revisionConflict : ErrorCode.timeout,
              );
              client.status = () async => ApiReply(fixture.fixtureGeneration, {
                'state': 'not-found',
                'result': null,
              });
              await tester.pumpWidget(
                MaterialApp(
                  theme: dark ? BrandTheme.dark : BrandTheme.light,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: const TextScaler.linear(2),
                      disableAnimations: true,
                    ),
                    child: child!,
                  ),
                  home: Builder(
                    builder: (context) => Scaffold(
                      body: OutlinedButton(
                        focusNode: launcher,
                        onPressed: () => showMotionDialog<void>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => switch (form) {
                            _Form.profile => ProfileForm(
                              model: model,
                              initial: model.profiles.single,
                            ),
                            _Form.settings => SettingsForm(model: model),
                            _Form.delete => ProfileDelete(
                              model: model,
                              initial: model.profiles.single,
                            ),
                          },
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
              if (form == _Form.profile) {
                await tester.enterText(
                  find.byKey(const ValueKey('profile-name')),
                  'RAM draft',
                );
                await tester.pumpAndSettle();
              } else if (form == _Form.settings) {
                await tester.ensureVisible(find.byType(CheckboxListTile));
                await tester.tap(find.byType(CheckboxListTile));
                await tester.pump();
              }
              Future<void> action(String label) async {
                final button = find.byWidgetPredicate(
                  (widget) =>
                      (widget is OutlinedButton || widget is FilledButton) &&
                      find
                          .descendant(
                            of: find.byWidget(widget),
                            matching: find.text(label),
                          )
                          .evaluate()
                          .isNotEmpty,
                );
                expect(button, findsOneWidget);
                bool focused() {
                  final context = FocusManager.instance.primaryFocus?.context;
                  if (context == null) return false;
                  final target = tester.element(button);
                  var inside = identical(context, target);
                  (context as Element).visitAncestorElements((ancestor) {
                    if (identical(ancestor, target)) inside = true;
                    return !inside;
                  });
                  return inside;
                }

                for (var steps = 0; !focused() && steps < 60; steps++) {
                  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
                  await tester.pumpAndSettle();
                }
                expect(
                  focused(),
                  true,
                  reason: '$label must be reachable by Tab',
                );
                final targetFocus = FocusManager.instance.primaryFocus;
                await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
                await tester.sendKeyEvent(LogicalKeyboardKey.tab);
                await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
                await tester.pumpAndSettle();
                expect(
                  FocusManager.instance.primaryFocus,
                  isNot(same(targetFocus)),
                  reason: 'ShiftTab must move away from $label',
                );
                await tester.sendKeyEvent(LogicalKeyboardKey.tab);
                await tester.pumpAndSettle();
                expect(focused(), true, reason: 'Tab must return to $label');
                await tester.ensureVisible(button);
                await tester.pumpAndSettle();
                final dimensions = tester.getSize(button);
                expect(dimensions.width, greaterThanOrEqualTo(48));
                expect(dimensions.height, greaterThanOrEqualTo(48));
                expect(button.hitTestable(), findsOneWidget);
                expect(tester.takeException(), isNull);
                await tester.sendKeyEvent(LogicalKeyboardKey.enter);
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull);
              }

              void expectDraft() {
                if (form == _Form.profile)
                  expect(find.text('RAM draft'), findsOneWidget);
                if (form == _Form.settings)
                  expect(
                    tester
                        .widget<CheckboxListTile>(find.byType(CheckboxListTile))
                        .value,
                    false,
                  );
              }

              await action(switch (form) {
                _Form.profile => 'Сохранить',
                _Form.settings => 'Сохранить настройки',
                _Form.delete => 'Подтвердить удаление',
              });
              expect(client.sent, hasLength(1));
              expect(find.text('Сохранено'), findsNothing);
              expect(find.text('Удалено'), findsNothing);
              expectDraft();
              final external = fixture.snapshot(revision: '2');
              final profiles = Map<String, Object?>.from(
                external.profiles.result as Map,
              );
              final profile =
                  Map<String, Object?>.from(
                      (profiles['profiles']! as List).single as Map,
                    )
                    ..['name'] = 'Changed externally'
                    ..['revision'] = '2';
              profiles['profiles'] = [profile];
              client.events.add(
                ClientSnapshot(
                  ApiReply(fixture.fixtureGeneration, profiles),
                  external.settings,
                ),
              );
              await tester.pumpAndSettle();
              expectDraft();
              if (conflict) {
                expect(
                  find.textContaining('изменён другим окном'),
                  form == _Form.settings ? findsNothing : findsOneWidget,
                );
                await action(
                  form == _Form.settings
                      ? 'Перечитать настройки'
                      : 'Перечитать профиль',
                );
                expect(client.sent, hasLength(1));
                if (form == _Form.profile)
                  expect(find.text('Changed externally'), findsOneWidget);
                if (form == _Form.settings)
                  expect(
                    tester
                        .widget<CheckboxListTile>(find.byType(CheckboxListTile))
                        .value,
                    true,
                  );
                if (form == _Form.delete)
                  expect(find.text('Changed externally'), findsOneWidget);
              } else {
                await action('Проверить результат');
                expect(client.queried, hasLength(1));
                expect(client.sent, hasLength(1));
                await action('Повторить тот же запрос');
                expect(client.sent, hasLength(2));
                expect(identical(client.sent[0], client.sent[1]), true);
                expectDraft();
                bootstrap.show(ReadinessState.unavailable);
                await tester.pumpAndSettle();
                expect(find.text('RAM draft'), findsNothing);
                expect(find.text('Changed externally'), findsNothing);
                final close = find.widgetWithText(OutlinedButton, 'Закрыть');
                await tester.ensureVisible(close);
                await tester.pumpAndSettle();
                expect(tester.getSize(close).height, greaterThanOrEqualTo(48));
                expect(close.hitTestable(), findsOneWidget);
              }
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
              await tester.pumpAndSettle();
              expect(find.byType(Dialog), findsNothing);
              expect(launcher.hasFocus, true);
              expect(client.sent, hasLength(conflict ? 1 : 2));
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox.shrink());
              launcher.dispose();
              model.dispose();
              await bootstrap.close();
              await client.events.close();
              await client.readErrors.close();
            },
          );
        }
      }
    }
  }
}
