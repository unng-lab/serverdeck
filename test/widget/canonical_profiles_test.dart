import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/profiles/profile_form.dart';
import 'package:serverdeck/profiles/profile_list.dart';
import 'package:serverdeck/profiles/profile_presentation.dart';
import 'package:serverdeck/servers/server_compositions.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck_protocol/models.dart';

import '../contract/profile_controller_test.dart' as fixtures;
import '../contract/mutation_controller_test.dart' show MutationClient;
import '../support/design_server_fixtures.dart';

void main() {
  testWidgets(
    'canonical local filters keep unknown honest and never send a request',
    (tester) async {
      final client = MutationClient();
      final bootstrap = fixtures.ModelBootstrap(client)
        ..show(ReadinessState.ready);
      final model = ProfileController(bootstrap: bootstrap);
      client.events.add(fixtures.snapshot());
      var opened = '';
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.dark,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: ListenableBuilder(
                listenable: model,
                builder: (context, _) => ProfileList(
                  controller: model,
                  onOpenProfile: (profile) => opened = profile.id,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('1 неизвестно'), findsOneWidget);
      expect(find.text('Состояние подключения не получено'), findsOneWidget);
      expect(find.text('Нет данных'), findsNWidgets(3));
      expect(find.text('Все серверы'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('profile-filter-state')),
      );
      await tester.tap(find.byKey(const ValueKey('profile-filter-state')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Подключены').last);
      await tester.pumpAndSettle();
      expect(find.text('Серверы не найдены'), findsOneWidget);
      expect(find.text('Saved profile'), findsNothing);
      await tester.ensureVisible(find.text('Сбросить фильтры'));
      await tester.tap(find.text('Сбросить фильтры'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '192.0.2.1');
      await tester.pumpAndSettle();
      expect(find.text('Saved profile'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'absent');
      await tester.pumpAndSettle();
      expect(find.text('Серверы не найдены'), findsOneWidget);
      await tester.ensureVisible(find.text('Сбросить фильтры'));
      await tester.tap(find.text('Сбросить фильтры'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Открыть сервер'));
      await tester.tap(find.text('Открыть сервер'));
      expect(opened, fixtures.profileId);
      expect(client.sent, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      await bootstrap.close();
      await client.events.close();
      await client.readErrors.close();
    },
  );

  testWidgets(
    'known card observations require the matching identity and share defensive history plots',
    (tester) async {
      final client = MutationClient();
      final bootstrap = fixtures.ModelBootstrap(client)
        ..show(ReadinessState.ready);
      final model = ProfileController(bootstrap: bootstrap);
      final profile = DesignServerFixtures.profile();
      client.events.add(
        ClientSnapshot(
          ApiReply(fixtures.fixtureGeneration, {
            'storeRevision': '1',
            'profiles': [profile.toJson()],
          }),
          ApiReply(fixtures.fixtureGeneration, {
            'storeRevision': '1',
            'settings': SettingsView(
              revision: '1',
              selectedProfileId: profile.id,
            ).toJson(),
          }),
        ),
      );
      Widget app({
        bool mismatch = false,
        bool truncated = false,
        bool withoutConnection = false,
        String connectionState = 'connected',
      }) => MaterialApp(
        theme: BrandTheme.light,
        home: Scaffold(
          body: ProfileList(
            controller: model,
            observations: [
              ProfileListObservation(
                profileId: profile.id,
                connectionRevision: profile.connectionRevision,
                credentialRevision: profile.credentialRevision,
                trustRevision: mismatch ? '999' : profile.trustRevision,
                connection: withoutConnection
                    ? null
                    : DesignServerFixtures.connection(state: connectionState),
                state: DesignServerFixtures.state(truncated: truncated),
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('1 подключены'), findsOneWidget);
      expect(find.text('0 неизвестно'), findsOneWidget);
      expect(find.byType(ServerObservationChart), findsNWidgets(3));
      expect(find.text('Все серверы'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('profile-filter-state')),
      );
      await tester.tap(find.byKey(const ValueKey('profile-filter-state')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Подключены').last);
      await tester.pumpAndSettle();
      expect(find.text(profile.name), findsOneWidget);
      await tester.pumpWidget(app(mismatch: true));
      await tester.pumpAndSettle();
      expect(find.text('1 неизвестно'), findsOneWidget);
      expect(find.text('Серверы не найдены'), findsOneWidget);
      expect(find.byType(ServerObservationChart), findsNothing);
      await tester.pumpWidget(app(truncated: true));
      await tester.pumpAndSettle();
      expect(find.text('1 требуют внимания'), findsOneWidget);
      expect(find.text(profile.name), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('profile-filter-state')),
      );
      await tester.tap(find.byKey(const ValueKey('profile-filter-state')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Требуют внимания').last);
      await tester.pumpAndSettle();
      expect(find.text(profile.name), findsOneWidget);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('Серверы не найдены'), findsOneWidget);
      await tester.pumpWidget(app(truncated: true));
      await tester.pumpAndSettle();
      expect(find.text(profile.name), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('profile-filter-state')),
      );
      await tester.tap(find.byKey(const ValueKey('profile-filter-state')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Подключены').last);
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(withoutConnection: true));
      await tester.pumpAndSettle();
      expect(find.text('1 неизвестно'), findsOneWidget);
      expect(find.text('0 подключены'), findsOneWidget);
      expect(find.text('Серверы не найдены'), findsOneWidget);
      final statusMenu = find.byKey(const ValueKey('profile-filter-state'));
      await tester.ensureVisible(statusMenu);
      await tester.tap(statusMenu);
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<PopupMenuItem<String>>(
              find.byType(PopupMenuItem<String>),
            )
            .map((item) => item.value),
        ['', 'connected', 'attention', 'unknown'],
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('profile-filter-all')),
      );
      await tester.tap(find.byKey(const ValueKey('profile-filter-all')));
      await tester.pumpAndSettle();
      expect(find.text(profile.name), findsOneWidget);
      expect(find.text('Не подключён'), findsNothing);
      await tester.pumpWidget(app(connectionState: 'connecting'));
      await tester.pumpAndSettle();
      final connectingMenu = find.byKey(const ValueKey('profile-filter-state'));
      await tester.ensureVisible(connectingMenu);
      await tester.tap(connectingMenu);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(PopupMenuItem<String>, 'Подключение'),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(withoutConnection: true));
      await tester.pumpAndSettle();
      expect(find.text('Серверы не найдены'), findsOneWidget);
      expect(
        tester.widget<PopupMenuButton<String>>(connectingMenu).initialValue,
        'connecting',
      );
      await tester.ensureVisible(connectingMenu);
      await tester.tap(connectingMenu);
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(PopupMenuItem<String>, 'Нет текущих наблюдений'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Состояние'));
      await tester.pumpAndSettle();
      expect(find.text(profile.name), findsOneWidget);

      expect(find.byType(ServerObservationChart), findsNWidgets(3));
      expect(client.sent, isEmpty);
      expect(client.refreshes, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      await bootstrap.close();
      await client.events.close();
      await client.readErrors.close();
    },
  );

  testWidgets(
    'closing the inline profile editor restores the safe search focus and query',
    (tester) async {
      final client = MutationClient();
      final bootstrap = fixtures.ModelBootstrap(client)
        ..show(ReadinessState.ready);
      final model = ProfileController(bootstrap: bootstrap);
      client.events.add(fixtures.snapshot());
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.light,
          home: Scaffold(body: ProfileList(controller: model)),
        ),
      );
      final state = tester.state(find.byType(ProfileList));
      await tester.enterText(find.byType(TextField), 'Saved');
      await tester.tap(find.text('Добавить сервер'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileForm), findsOneWidget);
      await tester.ensureVisible(find.text('Отмена'));
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(ProfileList)), same(state));
      expect(find.byType(ProfileForm), findsNothing);
      final search = tester.widget<TextField>(find.byType(TextField));
      expect(search.controller!.text, 'Saved');
      expect(search.focusNode!.hasFocus, isTrue);
      expect(client.sent, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      await bootstrap.close();
      await client.events.close();
      await client.readErrors.close();
    },
  );

  testWidgets(
    'new page retains save-only and explains unavailable save-and-connect',
    (tester) async {
      final client = MutationClient();
      final bootstrap = fixtures.ModelBootstrap(client)
        ..show(ReadinessState.ready);
      final model = ProfileController(bootstrap: bootstrap);
      client.events.add(fixtures.snapshot());
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.light,
          home: Scaffold(
            body: ProfileForm(model: model, asPage: true, onClose: () {}),
          ),
        ),
      );
      final connect = find.widgetWithText(
        FilledButton,
        'Сохранить и подключить',
      );
      expect(tester.widget<FilledButton>(connect).onPressed, isNull);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Сохранить без подключения'),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        find.textContaining('будет доступно в пакете 004'),
        findsOneWidget,
      );
      expect(client.sent, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      await bootstrap.close();
      await client.events.close();
      await client.readErrors.close();
    },
  );

  testWidgets(
    'access editor saves the whole profile with the existing mutation',
    (tester) async {
      final client = MutationClient();
      final bootstrap = fixtures.ModelBootstrap(client)
        ..show(ReadinessState.ready);
      final model = ProfileController(bootstrap: bootstrap);
      client.events.add(fixtures.snapshot());
      client.send = () async =>
          throw const LocalApiException(ErrorCode.timeout);
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.light,
          home: ProfileForm(
            model: model,
            initial: model.profiles.single,
            credentialOnly: true,
            asPage: true,
          ),
        ),
      );
      expect(find.text('Настройка доступа'), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-name')), findsNothing);
      expect(
        tester.widget<ProfileFieldGrid>(find.byType(ProfileFieldGrid)).children,
        hasLength(6),
      );
      for (final label in [
        'Цель *',
        'Доступ *',
        'Файл ключа',
        'Приватный ключ',
        'Passphrase',
        'Хранение',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(
        find.text(
          '${model.profiles.single.name} · ${model.profiles.single.address}:22',
        ),
        findsOneWidget,
      );
      expect(find.byType(TextFormField), findsNothing);
      await tester.ensureVisible(find.text('Сохранить доступ'));
      await tester.tap(find.text('Сохранить доступ'));
      await tester.pumpAndSettle();
      expect(client.sent.single.method, ApiMethod.profilesUpdate);
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      await bootstrap.close();
      await client.events.close();
      await client.readErrors.close();
    },
  );
}
