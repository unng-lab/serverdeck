import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/profiles/profile_delete.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck_protocol/models.dart';

import '../contract/profile_controller_test.dart' as fixture;
import '../contract/mutation_controller_test.dart' show MutationClient;

ClientSnapshot emptySnapshot() => ClientSnapshot(
  ApiReply(fixture.fixtureGeneration, {
    'storeRevision': '2',
    'profiles': <Object?>[],
  }),
  ApiReply(fixture.fixtureGeneration, {
    'storeRevision': '2',
    'settings': const SettingsView(revision: '2').toJson(),
  }),
);

void main() {
  late MutationClient client;
  late fixture.ModelBootstrap bootstrap;
  late ProfileController model;
  setUp(() {
    client = MutationClient();
    bootstrap = fixture.ModelBootstrap(client)..show(ReadinessState.ready);
    model = ProfileController(bootstrap: bootstrap);
    client.events.add(fixture.snapshot());
  });
  tearDown(() async {
    model.dispose();
    await bootstrap.close();
    await client.events.close();
    await client.readErrors.close();
  });
  Future<void> show(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: BrandTheme.light,
      home: ProfileDelete(model: model, initial: model.profiles.single),
    ),
  );

  testWidgets('confirmation precedes send; delete success needs readback', (
    tester,
  ) async {
    client.send = () async => ApiReply(fixture.fixtureGeneration, {
      'entityId': fixture.profileId,
      'entityRevision': '1',
      'storeRevision': '2',
      'deleted': true,
    });
    await show(tester);
    expect(client.sent, isEmpty);
    expect(find.text('Saved profile'), findsOneWidget);
    expect(find.text('192.0.2.1:22'), findsOneWidget);
    expect(
      find.text('Удаляется локальный профиль; сервер не меняется'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Подтвердить удаление'));
    await tester.tap(find.text('Подтвердить удаление'));
    await tester.pumpAndSettle();
    expect(client.sent.single.method, ApiMethod.profilesDelete);
    expect(find.text('Удалено'), findsNothing);
    client.events.add(emptySnapshot());
    await tester.pumpAndSettle();
    expect(find.text('Удалено'), findsOneWidget);
    expect(model.profiles, isEmpty);
    expect(model.selected, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'lost reply preserves original intent and hides private target outside ready',
    (tester) async {
      client.send = () async =>
          throw const LocalApiException(ErrorCode.timeout);
      client.status = () async => ApiReply(fixture.fixtureGeneration, {
        'state': 'not-found',
        'result': null,
      });
      await show(tester);
      await tester.tap(find.text('Подтвердить удаление'));
      await tester.pumpAndSettle();
      expect(find.text('Удаление не подтверждено'), findsOneWidget);
      await tester.ensureVisible(find.text('Проверить результат'));
      await tester.tap(find.text('Проверить результат'));
      await tester.pumpAndSettle();
      expect(identical(client.sent.single, client.queried.single), isTrue);
      bootstrap.show(ReadinessState.unavailable);
      await tester.pumpAndSettle();
      expect(find.text('Saved profile'), findsNothing);
      expect(find.text('192.0.2.1:22'), findsNothing);
      expect(client.sent, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('CAS conflict requires explicit reload and fresh confirmation', (
    tester,
  ) async {
    client.send = () async =>
        throw const LocalApiException(ErrorCode.revisionConflict);
    await show(tester);
    final original = fixture.snapshot(revision: '2');
    final profile = Map<String, Object?>.from(
      (original.profiles.result['profiles'] as List).single as Map,
    );
    profile['name'] = 'Changed by another window';
    profile['revision'] = '2';
    client.events.add(
      ClientSnapshot(
        ApiReply(fixture.fixtureGeneration, {
          'storeRevision': '2',
          'profiles': [profile],
        }),
        original.settings,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Saved profile'), findsOneWidget);
    expect(find.text('Changed by another window'), findsNothing);
    await tester.tap(find.text('Подтвердить удаление'));
    await tester.pumpAndSettle();
    expect(client.sent, hasLength(1));
    await tester.ensureVisible(find.text('Перечитать профиль'));
    await tester.tap(find.text('Перечитать профиль'));
    await tester.pumpAndSettle();
    expect(find.text('Changed by another window'), findsOneWidget);
    expect(client.sent, hasLength(1));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Подтвердить удаление'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Escape cancels without request and returns focus to launcher', (
    tester,
  ) async {
    final initial = model.profiles.single;
    final launcher = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => OutlinedButton(
              focusNode: launcher,
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => ProfileDelete(model: model, initial: initial),
              ),
              child: const Text('Open delete'),
            ),
          ),
        ),
      ),
    );
    launcher.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(ProfileDelete), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ProfileDelete), findsNothing);
    expect(client.sent, isEmpty);
    expect(launcher.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    launcher.dispose();
  });

  for (final dark in [false, true]) {
    for (final size in const [
      Size(1100, 760),
      Size(800, 600),
      Size(360, 800),
      Size(390, 800),
    ]) {
      testWidgets('delete dialog reachable at200 $size dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final initial = model.profiles.single;
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? BrandTheme.dark : BrandTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: ProfileDelete(model: model, initial: initial),
          ),
        );
        await tester.ensureVisible(find.text('Подтвердить удаление'));
        await tester.pumpAndSettle();
        expect(
          tester
              .getSize(
                find.widgetWithText(FilledButton, 'Подтвердить удаление'),
              )
              .height,
          greaterThanOrEqualTo(48),
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Отмена'));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
