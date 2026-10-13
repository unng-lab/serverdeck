import 'support/runtime_hooks.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:serverdeck/main.dart' as app;
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/profiles/credential_input.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/profiles/profile_list.dart';
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck_protocol/models.dart' show CredentialKind, ApiMethod;
import 'package:serverdeck_windows/client_bootstrap.dart';

import '../packages/serverdeck_locald/test/support/ui_private_file_scan.dart';

const _password = 'synthetic-ui-password-173';
const _pem =
    '-----BEGIN PRIVATE KEY-----\r\nZWZnaGlqa2xtbm9wcXJzdHV2d3h5ent8fX5/gIGCg4Q=\r\n-----END PRIVATE KEY-----\r\n';
const _passphrase = 'synthetic-ui-passphrase-173';

Iterable<String> _strings(Object? value) sync* {
  if (value is String) {
    yield value;
  } else if (value is Map) {
    for (final entry in value.entries) {
      yield* _strings(entry.key);
      yield* _strings(entry.value);
    }
  } else if (value is List) {
    for (final entry in value) {
      yield* _strings(entry);
    }
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final root = Platform.environment['LOCALAPPDATA'] ?? '';
  if (!RegExp(r'[\\/]\.local[\\/]foundation-ui-[a-f0-9]{32}[\\/]profile$')
      .hasMatch(root)) {
    throw StateError('OWNED_ACCEPTANCE_FIXTURE_REQUIRED');
  }
  final step = int.tryParse(
    Platform.environment['SERVERDECK_CREDENTIAL_STEP'] ?? '',
  );
  if (step == null || step < 0 || step > 9) {
    throw StateError('CREDENTIAL_STEP_INVALID');
  }
  final signals = Directory('$root/ui-credentials')..createSync();
  final discovery = File('$root/ServerDeckNext/v1/runtime/default.discovery');
  File proof(int number) => File('${signals.path}/step-$number.json');

  testWidgetsWithRuntimeHooks('actual credential journey step $step', (
    tester,
  ) async {
    Future<void> wait(bool Function() condition, {int seconds = 30}) async {
      final elapsed = Stopwatch()..start();
      while (!condition() && elapsed.elapsed < Duration(seconds: seconds)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(condition(), true, reason: 'credential step $step condition');
    }

    Future<void> click(String text) async {
      final target = find.text(text);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    Future<void> choose(String current, String next) async {
      await click(current);
      await click(next);
    }

    Future<void> saved({bool deleting = false, bool settings = false}) async {
      await click(
        deleting
            ? 'Подтвердить удаление'
            : settings
            ? 'Сохранить настройки'
            : 'Сохранить',
      );
      await wait(
        () =>
            find.text(deleting ? 'Удалено' : 'Сохранено').evaluate().isNotEmpty,
      );
      if (!deleting && find.byType(CredentialInput).evaluate().isNotEmpty) {
        final input = tester.state<CredentialInputState>(
          find.byType(CredentialInput),
        );
        expect(input.password.text, isEmpty);
        expect(input.keyInput.text, isEmpty);
        expect(input.passphrase.text, isEmpty);
        expect(input.revealed, false);
      }
      await click('Закрыть');
    }

    Future<void> edit() async {
      if (find.text('Редактировать профиль').evaluate().isEmpty) {
        final row = find.descendant(
          of: find.byType(ExpansionTile),
          matching: find.text(
            step >= 5 ? 'Credential kept' : 'Credential journey',
          ),
        );
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pumpAndSettle();
      }
      await click('Редактировать профиль');
    }

    ProfileController? model;
    var phase = 'ready';
    try {
      app.main();
      await wait(() => find.text('Создать профиль').evaluate().isNotEmpty);
      model = tester.widget<ProfileList>(find.byType(ProfileList)).controller;
      final current = model;
      final client = current.bootstrap.client;
      expect(current.loaded, true);
      final owner = await Isolate.run(() async {
        final environment = await ClientBootstrapEnvironment.verify();
        final descriptor = await environment.discovery();
        if (descriptor == null) throw StateError('OWNER_MISSING');
        try {
          return {
            'uiPid': pid,
            'generation': descriptor.generation,
            'serverPid': descriptor.serverPid,
          };
        } finally {
          descriptor.close();
        }
      });
      if (step > 0) {
        final previous = jsonDecode(proof(step - 1).readAsStringSync()) as Map;
        expect(previous['format'], 1);
        expect(previous['step'], step - 1);
        expect(previous['scenario'], 'ui-credential-reopen');
        expect(owner['generation'], isNot(previous['generation']));
        expect(current.storeRevision, previous['storeRevision']);
        expect(current.settings!.selectedProfileId, previous['selected']);
        if (step < 7) {
          final profile = current.profiles.single;
          expect(profile.id, previous['profileId']);
          expect(profile.name, previous['name']);
          expect(profile.revision, previous['profileRevision']);
          expect(profile.credentialRevision, previous['credentialRevision']);
          expect(profile.credentialKind.name, previous['credentialKind']);
          expect(profile.credentialConfigured, previous['configured']);
        } else if (step < 9) {
          expect(current.profiles, isEmpty);
          expect(find.text('Локальных профилей пока нет'), findsOneWidget);
        } else {
          expect(current.profiles, hasLength(250));
          final reopened = await client.read(ApiMethod.profilesList);
          final digest = await Sha256().hash(
            utf8.encode(jsonEncode(reopened.result)),
          );
          expect(
            digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
            previous['profilesDigest'],
          );
        }
      } else {
        expect(current.profiles, isEmpty);
        expect(current.storeRevision, '0');
      }
      phase = 'action';
      switch (step) {
        case 0:
          await click('Создать профиль');
          await tester.enterText(
            find.byKey(const ValueKey('profile-name')),
            'Discarded create',
          );
          await click('Отмена');
          expect(current.storeRevision, '0');
          await click('Создать профиль');
          for (final entry in {
            'name': 'Credential journey',
            'address': '192.0.2.173',
            'user': 'fixture',
          }.entries) {
            await tester.enterText(
              find.byKey(ValueKey('profile-${entry.key}')),
              entry.value,
            );
          }
          await saved();
        case 1:
          await edit();
          await choose('Сохранить существующий', 'Новый пароль');
          await tester.enterText(
            find.widgetWithText(TextFormField, 'Пароль'),
            _password,
          );
          await saved();
        case 2:
          await edit();
          await choose('Сохранить существующий', 'Без секрета / удалить');
          await saved();
        case 3:
          await edit();
          await choose('Сохранить существующий', 'Новый приватный ключ');
          await click('Показать введённый секрет');
          await tester.enterText(
            find.widgetWithText(TextFormField, 'Приватный ключ'),
            _pem,
          );
          await tester.enterText(
            find.widgetWithText(TextFormField, 'Passphrase (необязательно)'),
            _passphrase,
          );
          await click('Показать введённый секрет');
          final input = tester.state<CredentialInputState>(
            find.byType(CredentialInput),
          );
          expect(input.keyInput.text, _pem);
          expect(input.passphrase.text, _passphrase);
          expect(input.revealed, false);
          await saved();
        case 4:
          await edit();
          expect(find.text('Сохранить существующий'), findsOneWidget);
          expect(
            find.widgetWithText(TextFormField, 'Приватный ключ'),
            findsNothing,
          );
          await tester.enterText(
            find.byKey(const ValueKey('profile-name')),
            'Credential kept',
          );
          await saved();
        case 5:
          await edit();
          await choose('Сохранить существующий', 'Новый пароль');
          await tester.enterText(
            find.widgetWithText(TextFormField, 'Пароль'),
            'synthetic-cancelled-password-173',
          );
          await click('Отмена');
          expect(current.storeRevision, '5');
          await click('Удалить профиль');
          await click('Отмена');
          expect(current.profiles, hasLength(1));
          expect(current.storeRevision, '5');
          await click('Настройки');
          await click('Изменить настройки');
          await choose('Не выбран', 'Credential kept');
          await click('Отмена');
          expect(current.settings!.selectedProfileId, isNull);
          expect(current.storeRevision, '5');
          await click('Изменить настройки');
          await choose('Не выбран', 'Credential kept');
          await saved(settings: true);
          expect(current.selected!.id, current.profiles.single.id);
        case 6:
          expect(current.selected!.id, current.profiles.single.id);
          await edit();
          await click('Отмена');
          await click('Удалить профиль');
          expect(
            find.text('Удаляется локальный профиль; сервер не меняется'),
            findsOneWidget,
          );
          await saved(deleting: true);
          expect(current.profiles, isEmpty);
          expect(current.settings!.selectedProfileId, isNull);
          expect(current.selected, isNull);
        case 7:
          expect(current.settings!.selectedProfileId, isNull);
        case 8:
          // Populate only this owned fixture through the production client,
          // authenticated locald and repository; no direct DB or mocked model.
          await tester.runAsync(() async {
            for (var index = 0; index < 249; index++) {
              final reply = await client.mutate(
                MutationIntent(ApiMethod.profilesCreate, {
                  'profileId':
                      'd2345678-1234-4234-8234-${index.toRadixString(16).padLeft(12, '0')}',
                  'name': 'Quota fixture $index',
                  'address': 'quota.example.test',
                  'port': 22,
                  'sshUser': 'fixture',
                  'tags': <String>[],
                  'credential': <String, Object?>{'action': 'remove'},
                }),
              );
              expect(reply.result['storeRevision'], '${8 + index}');
            }
            await current.refresh();
          });
          await tester.pumpAndSettle();
          expect(current.profiles, hasLength(249));
          expect(current.storeRevision, '256');
          await click('Создать профиль');
          for (final entry in {
            'name': 'Quota profile 250',
            'address': '192.0.2.250',
            'user': 'fixture',
          }.entries) {
            await tester.enterText(
              find.byKey(ValueKey('profile-${entry.key}')),
              entry.value,
            );
          }
          await saved();
          expect(current.profiles, hasLength(250));
          expect(current.storeRevision, '257');
          final before = await client.read(ApiMethod.profilesList);
          await click('Создать профиль');
          for (final entry in {
            'name': 'Quota rejected 251',
            'address': 'invalid host',
            'port': '0',
            'user': 'invalid user',
          }.entries) {
            await tester.enterText(
              find.byKey(ValueKey('profile-${entry.key}')),
              entry.value,
            );
          }
          await click('Сохранить');
          expect(find.text('Проверьте значение поля'), findsNWidgets(3));
          expect(find.text('Сохранено'), findsNothing);
          expect(current.storeRevision, '257');
          for (final entry in {
            'address': '192.0.2.251',
            'port': '22',
            'user': 'fixture',
          }.entries) {
            await tester.enterText(
              find.byKey(ValueKey('profile-${entry.key}')),
              entry.value,
            );
          }
          await click('Сохранить');
          await wait(
            () => find
                .text('Достигнут лимит локальных ресурсов')
                .evaluate()
                .isNotEmpty,
          );
          expect(find.text('Сохранено'), findsNothing);
          expect(
            tester
                .widget<TextFormField>(
                  find.byKey(const ValueKey('profile-name')),
                )
                .controller!
                .text,
            'Quota rejected 251',
          );
          final after = await client.read(ApiMethod.profilesList);
          expect(jsonEncode(after.result), jsonEncode(before.result));
          await click('Закрыть');
        case 9:
          expect(current.settings!.selectedProfileId, isNull);
      }
      phase = 'verify';
      await current.refresh();
      await tester.pumpAndSettle();
      final expectedStore = step >= 8
          ? '257'
          : step == 7
          ? '7'
          : '${step + 1}';
      expect(current.storeRevision, expectedStore);
      expect(
        current.settings!.revision,
        step < 5
            ? '1'
            : step == 5
            ? '2'
            : '3',
      );
      if (step < 6) {
        final profile = current.profiles.single;
        expect(profile.revision, step < 5 ? '${step + 1}' : '5');
        expect(profile.credentialRevision, step < 4 ? '${step + 1}' : '4');
        expect(profile.connectionRevision, '1');
        expect(profile.trustRevision, '1');
        expect(profile.credentialConfigured, step != 0 && step != 2);
        expect(
          profile.credentialKind,
          step == 0 || step == 2
              ? CredentialKind.none
              : step == 1
              ? CredentialKind.password
              : CredentialKind.privateKey,
        );
      }
      final recent = await client.read(ApiMethod.mutationsRecent, {
        'limit': step >= 8 ? 100 : 20,
      });
      final receipts = (recent.result['receipts'] as List).cast<Map>();
      expect(receipts, hasLength(step >= 8 ? 100 : int.parse(expectedStore)));
      expect(
        receipts.map((r) => r['requestId']).toSet(),
        hasLength(receipts.length),
      );
      for (final method in [
        ApiMethod.profilesList,
        ApiMethod.settingsGet,
        ApiMethod.mutationsRecent,
      ]) {
        final response = await client.read(
          method,
          method == ApiMethod.mutationsRecent ? {'limit': 20} : const {},
        );
        for (final text in _strings(response.result)) {
          for (final marker in [
            _password,
            _pem,
            _passphrase,
            'cancelled-password',
          ]) {
            expect(text.contains(marker), false);
          }
        }
      }
      final profile = current.profiles.length == 1
          ? current.profiles.single
          : null;
      final profilesReply = await client.read(ApiMethod.profilesList);
      final profilesHash = await Sha256().hash(
        utf8.encode(jsonEncode(profilesReply.result)),
      );
      final metadata = {
        'format': 1,
        'scenario': 'ui-credential-reopen',
        'step': step,
        ...owner,
        'storeRevision': current.storeRevision,
        'selected': current.settings!.selectedProfileId,
        'profileId': profile?.id,
        'name': profile?.name,
        'profileRevision': profile?.revision,
        'credentialRevision': profile?.credentialRevision,
        'credentialKind': profile?.credentialKind.name,
        'configured': profile?.credentialConfigured,
        'profileCount': current.profiles.length,
        'profilesDigest': profilesHash.bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(),
      };
      phase = 'close';
      await tester.pumpWidget(const SizedBox.shrink());
      await wait(() => !discovery.existsSync(), seconds: 90);
      phase = 'private-file-scan';
      final fileScan = await scanUiPrivateFilesInIsolate(root, [
        _password,
        _passphrase,
        'synthetic-cancelled-password-173',
      ], _pem);
      metadata.addAll(fileScan);
      final pending = File('${proof(step).path}.pending');
      pending.writeAsStringSync(jsonEncode(metadata), flush: true);
      pending.renameSync(proof(step).path);
      stdout.writeln('COMPILED_UI_PRIVATE_FILES_STEP_${step}_CLEAN_PROVED');
      stdout.writeln(
        'COMPILED_UI_CREDENTIAL_STEP_${step}_REOPEN_COMMIT_PROVED',
      );
    } on Object catch (error) {
      final shell = find.byType(FoundationShell);
      final readiness = shell.evaluate().isEmpty
          ? null
          : tester.widget<FoundationShell>(shell);
      File('${signals.path}/failed-$step.json').writeAsStringSync(
        jsonEncode({
          'phase': phase,
          'errorKind': error.runtimeType.toString(),
          'state': readiness?.state.name,
          'reason': readiness?.reason?.name,
        }),
        flush: true,
      );
      rethrow;
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await model?.bootstrap.close();
      await wait(() => !discovery.existsSync(), seconds: 90);
    }
  });
}
