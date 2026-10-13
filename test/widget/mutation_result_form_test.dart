import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/profiles/credential_input.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/profiles/profile_delete.dart';
import 'package:serverdeck/profiles/profile_form.dart';
import 'package:serverdeck/settings/settings_form.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck_protocol/models.dart';

import '../contract/mutation_controller_test.dart' show MutationClient;
import '../contract/profile_controller_test.dart' as fixture;

enum _Form { profile, settings, delete }

ClientSnapshot baseline() {
  // Create the profile at1, then select it via settings.update at2.
  final source = fixture.snapshot(revision: '2');
  final settings = Map<String, Object?>.from(source.settings.result);
  settings['settings'] = Map<String, Object?>.from(settings['settings'] as Map)
    ..['revision'] = '2';
  return ClientSnapshot(
    source.profiles,
    ApiReply(fixture.fixtureGeneration, settings),
  );
}

void main() {
  late MutationClient client;
  late fixture.ModelBootstrap bootstrap;
  late ProfileController model;
  setUp(() {
    client = MutationClient();
    bootstrap = fixture.ModelBootstrap(client)..show(ReadinessState.ready);
    model = ProfileController(bootstrap: bootstrap);
    client.events.add(baseline());
    client.send = () async => throw const LocalApiException(ErrorCode.timeout);
  });
  tearDown(() async {
    model.dispose();
    await bootstrap.close();
    await client.events.close();
    await client.readErrors.close();
  });

  String save(_Form form) => switch (form) {
    _Form.profile => 'Сохранить',
    _Form.settings => 'Сохранить настройки',
    _Form.delete => 'Подтвердить удаление',
  };
  Map<String, Object?> receipt(_Form form) => {
    'entityId': form == _Form.settings ? null : fixture.profileId,
    'entityRevision': form == _Form.delete
        ? '1'
        : form == _Form.settings
        ? '3'
        : '2',
    'storeRevision': '3',
    'deleted': form == _Form.delete,
  };
  Future<void> click(WidgetTester tester, String label) async {
    final target = find.text(label);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, _Form form) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: OutlinedButton(
              onPressed: () => showDialog<void>(
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
              child: const Text('Открыть форму'),
            ),
          ),
        ),
      ),
    );
    await click(tester, 'Открыть форму');
    if (form == _Form.profile) {
      await tester.enterText(
        find.byKey(const ValueKey('profile-name')),
        'Retained draft',
      );
    } else if (form == _Form.settings) {
      await click(tester, 'Уменьшение анимации');
    }
  }

  void draft(WidgetTester tester, _Form form) {
    if (form == _Form.profile) {
      expect(find.text('Retained draft'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('profile-name')))
            .enabled,
        false,
      );
    } else if (form == _Form.settings) {
      final checkbox = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(checkbox.value, false);
      expect(checkbox.onChanged, isNull);
    } else {
      expect(find.text('Saved profile'), findsOneWidget);
    }
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, save(form)))
          .onPressed,
      isNull,
    );
  }

  void current(
    _Form form, {
    bool externalUpdate = false,
    CredentialKind? credential,
  }) {
    // The explicit action commits at storeRevision3. A later ordinary edit
    // optionally commits at4 to prove current reads cannot replace a RAM draft.
    final later = externalUpdate && form != _Form.delete;
    final source = fixture.snapshot(revision: later ? '4' : '3');
    final profiles = Map<String, Object?>.from(source.profiles.result);
    final settings = Map<String, Object?>.from(source.settings.result);
    settings['settings'] = Map<String, Object?>.from(
      settings['settings'] as Map,
    )..['revision'] = '2';
    if (form == _Form.delete) {
      profiles['profiles'] = <Object?>[];
      settings['settings'] =
          Map<String, Object?>.from(settings['settings'] as Map)
            ..['selectedProfileId'] = null
            ..['revision'] = '3';
    } else if (form == _Form.settings) {
      settings['settings'] =
          Map<String, Object?>.from(settings['settings'] as Map)
            ..['revision'] = later ? '4' : '3'
            ..['reduceMotion'] = later;
    } else {
      profiles['profiles'] = [
        Map<String, Object?>.from((profiles['profiles'] as List).single as Map)
          ..['name'] = later ? 'Current server value' : 'Retained draft'
          ..['revision'] = later ? '3' : '2'
          ..['credentialRevision'] = credential == null ? '1' : '2'
          ..['credential'] = {
            'kind': (credential ?? CredentialKind.password).name,
            'configured': true,
          },
      ];
    }
    client.events.add(
      ClientSnapshot(
        ApiReply(fixture.fixtureGeneration, profiles),
        ApiReply(fixture.fixtureGeneration, settings),
      ),
    );
  }

  for (final form in _Form.values) {
    testWidgets(
      'lost reply queued/running/commit requires current readback $form',
      (tester) async {
        await open(tester, form);
        await click(tester, save(form));
        expect(
          find.text(
            form == _Form.delete
                ? 'Удаление не подтверждено'
                : 'Сохранение не подтверждено',
          ),
          findsOneWidget,
        );
        final original = client.sent.single;
        for (final state in ['queued', 'running']) {
          client.status = () async => ApiReply(fixture.fixtureGeneration, {
            'state': state,
            'result': null,
          });
          await click(tester, 'Проверить результат');
          expect(client.queried.last, same(original));
          expect(find.text('Операция ещё выполняется'), findsOneWidget);
          expect(find.text('Повторить тот же запрос'), findsNothing);
          draft(tester, form);
        }
        client.status = () async => ApiReply(fixture.fixtureGeneration, {
          'state': 'committed',
          'result': receipt(form),
        });
        await click(tester, 'Проверить результат');
        final success = form == _Form.delete ? 'Удалено' : 'Сохранено';
        expect(find.text(success), findsNothing);
        expect(find.text('Перечитать состояние'), findsOneWidget);
        client.events.add(baseline());
        await tester.pumpAndSettle();
        expect(find.text(success), findsNothing);
        client.readErrors.add(ErrorCode.timeout);
        await tester.pumpAndSettle();
        final before = client.refreshes;
        await click(tester, 'Перечитать состояние');
        expect(client.refreshes, before + 1);
        expect(client.sent, hasLength(1));
        expect(find.text(success), findsNothing);
        expect(find.text('Повторить тот же запрос'), findsNothing);
        current(form, externalUpdate: true);
        await tester.pumpAndSettle();
        expect(find.text(success), findsOneWidget);
        draft(tester, form);
        expect(client.sent.single, same(original));
        await click(tester, 'Закрыть');
        expect(find.byType(Dialog), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'not-found retry revoked by readiness loss; explicit identical retry $form',
      (tester) async {
        await open(tester, form);
        await click(tester, save(form));
        final original = client.sent.single;
        client.status = () async => ApiReply(fixture.fixtureGeneration, {
          'state': 'not-found',
          'result': null,
        });
        await click(tester, 'Проверить результат');
        expect(find.text('Повторить тот же запрос'), findsOneWidget);
        bootstrap.show(ReadinessState.unavailable);
        await tester.pumpAndSettle();
        expect(find.text('Повторить тот же запрос'), findsNothing);
        expect(find.text('Retained draft'), findsNothing);
        bootstrap.show(ReadinessState.ready);
        client.events.add(baseline());
        await tester.pumpAndSettle();
        expect(find.text('Повторить тот же запрос'), findsNothing);
        draft(tester, form);
        expect(client.sent, hasLength(1));
        await click(tester, 'Проверить результат');
        final pending = Completer<ApiReply>();
        client.send = () => pending.future;
        await click(tester, 'Повторить тот же запрос');
        expect(client.sent, hasLength(2));
        expect(client.sent.last, same(original));
        expect(client.sent.last.id, original.id);
        expect(find.text('Повторить тот же запрос'), findsNothing);
        draft(tester, form);
        pending.complete(ApiReply(fixture.fixtureGeneration, receipt(form)));
        await tester.pumpAndSettle();
        expect(
          find.text(form == _Form.delete ? 'Удалено' : 'Сохранено'),
          findsNothing,
        );
        current(form);
        await tester.pumpAndSettle();
        expect(
          find.text(form == _Form.delete ? 'Удалено' : 'Сохранено'),
          findsOneWidget,
        );
        expect(client.sent, hasLength(2));
        await click(tester, 'Закрыть');
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'close pending status ignores late receipt and never recreates intent $form',
      (tester) async {
        await open(tester, form);
        await click(tester, save(form));
        final original = client.sent.single;
        final status = Completer<ApiReply>();
        client.status = () => status.future;
        await click(tester, 'Проверить результат');
        expect(client.queried.single, same(original));
        await click(tester, 'Закрыть');
        expect(find.byType(Dialog), findsNothing);
        status.complete(
          ApiReply(fixture.fixtureGeneration, {
            'state': 'committed',
            'result': receipt(form),
          }),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(client.sent, hasLength(1));
        await click(tester, 'Открыть форму');
        expect(find.text('Проверить результат'), findsNothing);
        expect(find.text('Повторить тот же запрос'), findsNothing);
        expect(find.text('Retained draft'), findsNothing);
        expect(client.sent, hasLength(1));
        await click(tester, 'Отмена');
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final privateKey in [false, true]) {
    for (final cancel in [false, true]) {
      testWidgets(
        'secret survives unknown result and clears on resolved close key=$privateKey cancel=$cancel',
        (tester) async {
          await open(tester, _Form.profile);
          await click(tester, 'Сохранить существующий');
          await tester.tap(
            find
                .text(privateKey ? 'Новый приватный ключ' : 'Новый пароль')
                .last,
          );
          await tester.pumpAndSettle();
          if (privateKey) await click(tester, 'Показать введённый секрет');
          final credential = tester.state<CredentialInputState>(
            find.byType(CredentialInput),
          );
          final secret = privateKey ? credential.keyInput : credential.password;
          final input = privateKey
              ? '-----BEGIN PRIVATE KEY-----\r\nAQID\r\n-----END PRIVATE KEY-----\r\n'
              : ' synthetic access secret ';
          Finder field(TextEditingController controller) =>
              find.byWidgetPredicate(
                (widget) =>
                    widget is TextFormField && widget.controller == controller,
              );
          await tester.ensureVisible(field(secret));
          await tester.enterText(field(secret), input);
          if (privateKey) {
            await tester.ensureVisible(field(credential.passphrase));
            await tester.enterText(
              field(credential.passphrase),
              ' synthetic passphrase ',
            );
            await click(tester, 'Показать введённый секрет');
            expect(
              tester
                  .widget<TextField>(
                    find.descendant(
                      of: field(secret),
                      matching: find.byType(TextField),
                    ),
                  )
                  .readOnly,
              true,
            );
          }
          await click(tester, 'Сохранить');
          expect(secret.text, input);
          final original = client.sent.single;
          // A closed real client still decodes a live intent before checking
          // transport state; a disposed payload is rejected before transport.
          final probe = LocalApiClient(
            connect: () => throw StateError('UNUSED'),
          );
          await probe.close();
          Future<void> expectPayload(bool retained) => expectLater(
            probe.mutate(original),
            throwsA(
              isA<LocalApiException>().having(
                (error) => error.code,
                'safe code',
                retained ? ErrorCode.serviceUnavailable : ErrorCode.validation,
              ),
            ),
          );
          await expectPayload(true);
          if (cancel) {
            await click(tester, 'Закрыть');
          } else {
            client.status = () async => ApiReply(fixture.fixtureGeneration, {
              'state': 'committed',
              'result': receipt(_Form.profile),
            });
            await click(tester, 'Проверить результат');
            expect(secret.text, input);
            current(
              _Form.profile,
              credential: privateKey
                  ? CredentialKind.privateKey
                  : CredentialKind.password,
            );
            await tester.pumpAndSettle();
            expect(find.text('Сохранено'), findsOneWidget);
            expect(secret.text, isEmpty);
            expect(credential.passphrase.text, isEmpty);
            expect(find.byType(ProfileForm), findsOneWidget);
            await expectPayload(false);
            await click(tester, 'Закрыть');
          }
          expect(secret.text, isEmpty);
          expect(credential.passphrase.text, isEmpty);
          expect(client.sent, hasLength(1));
          await expectPayload(false);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
