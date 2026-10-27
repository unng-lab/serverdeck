import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/profiles/profile_form.dart';
import 'package:serverdeck/profiles/credential_input.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck_protocol/models.dart';

import '../contract/profile_controller_test.dart' as fixture;
import '../contract/mutation_controller_test.dart' show MutationClient;

void main() {
  test('input converts IDN and keeps secret Unicode/whitespace verbatim', () {
    final result = buildProfileInput(
      name: ' Name ',
      address: 'пример.рф',
      port: '22',
      user: ' root ',
      tags: ' a\n b ',
    );
    expect(result['address'], 'xn--e1afmkfd.xn--p1ai');
    expect(result['name'], 'Name');
    expect(result['tags'], ['a', 'b']);
    expect(
      buildProfileInput(
        name: 'n',
        address: '2001:db8::1',
        port: '65535',
        user: 'u',
        tags: '',
      )['address'],
      '2001:db8::1',
    );
    expect(
      () => buildProfileInput(
        name: 'n',
        address: 'host',
        port: '0',
        user: 'u',
        tags: '',
      ),
      throwsFormatException,
    );
  });

  testWidgets(
    'edit draft survives snapshots and timeout; explicit result check',
    (tester) async {
      final client = MutationClient();
      final bootstrap = fixture.ModelBootstrap(client)
        ..show(ReadinessState.ready);
      final model = ProfileController(bootstrap: bootstrap);
      client.events.add(fixture.snapshot());
      final profile = model.profiles.single;
      client.send = () async =>
          throw const LocalApiException(ErrorCode.timeout);
      client.status = () async => ApiReply(fixture.fixtureGeneration, {
        'state': 'not-found',
        'result': null,
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.light,
          home: ProfileForm(model: model, initial: profile),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('profile-name')),
        'Draft stays',
      );
      client.events.add(fixture.snapshot(revision: '2'));
      await tester.pumpAndSettle();
      expect(find.text('Draft stays'), findsOneWidget);
      await tester.ensureVisible(find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(client.sent, hasLength(1));
      expect(find.text('Сохранение не подтверждено'), findsOneWidget);
      expect(find.text('Draft stays'), findsOneWidget);
      await tester.ensureVisible(find.text('Проверить результат'));
      await tester.tap(find.text('Проверить результат'));
      await tester.pumpAndSettle();
      expect(client.queried, hasLength(1));
      expect(find.text('Повторить тот же запрос'), findsOneWidget);
      bootstrap.show(ReadinessState.unavailable);
      await tester.pumpAndSettle();
      expect(find.text('Draft stays'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      await bootstrap.close();
      await client.events.close();
      await client.readErrors.close();
    },
  );

  testWidgets('invalid create fields do not send, cancel does not save', (
    tester,
  ) async {
    final client = MutationClient();
    final bootstrap = fixture.ModelBootstrap(client)
      ..show(ReadinessState.ready);
    final model = ProfileController(bootstrap: bootstrap);
    client.events.add(fixture.snapshot());
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => ProfileForm(model: model),
              ),
              child: const Text('Create'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(client.sent, isEmpty);
    expect(find.text('Проверьте значение поля'), findsWidgets);
    await tester.ensureVisible(find.text('Отмена'));
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileForm), findsNothing);
    expect(client.sent, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
    await bootstrap.close();
    await client.events.close();
    await client.readErrors.close();
  });

  testWidgets('readiness loss removes private form and clears secret editors', (
    tester,
  ) async {
    final client = MutationClient();
    final bootstrap = fixture.ModelBootstrap(client)
      ..show(ReadinessState.ready);
    final model = ProfileController(bootstrap: bootstrap);
    client.events.add(fixture.snapshot());
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.light,
        home: ProfileForm(model: model, initial: model.profiles.single),
      ),
    );
    await tester.ensureVisible(find.text('Сохранить существующий'));
    await tester.tap(find.text('Сохранить существующий'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новый пароль').last);
    await tester.pumpAndSettle();
    final credential = tester.state<CredentialInputState>(
      find.byType(CredentialInput),
    );
    credential.password.text = 'synthetic private marker';
    final password = credential.password;
    bootstrap.show(ReadinessState.unavailable);
    await tester.pumpAndSettle();
    expect(find.byType(CredentialInput), findsNothing);
    expect(find.byType(Form), findsNothing);
    expect(find.textContaining('Saved profile'), findsNothing);
    expect(find.textContaining('synthetic private marker'), findsNothing);
    expect(password.text, isEmpty);
    bootstrap.show(ReadinessState.ready);
    client.events.add(fixture.snapshot());
    await tester.pumpAndSettle();
    expect(
      tester
          .state<CredentialInputState>(find.byType(CredentialInput))
          .password
          .text,
      isEmpty,
    );
    expect(client.sent, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
    await bootstrap.close();
    await client.events.close();
    await client.readErrors.close();
  });

  for (final dark in [false, true]) {
    for (final size in const [
      Size(1100, 760),
      Size(800, 600),
      Size(360, 800),
      Size(390, 800),
    ]) {
      testWidgets('form actions scroll at200 $size dark=$dark', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final client = MutationClient();
        final bootstrap = fixture.ModelBootstrap(client)
          ..show(ReadinessState.ready);
        final model = ProfileController(bootstrap: bootstrap);
        client.events.add(fixture.snapshot());
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? BrandTheme.dark : BrandTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: ProfileForm(model: model, initial: model.profiles.single),
          ),
        );
        await tester.ensureVisible(find.text('Сохранить'));
        await tester.pumpAndSettle();
        final button = find.widgetWithText(FilledButton, 'Сохранить');
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Отмена'));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        model.dispose();
        await bootstrap.close();
        await client.events.close();
        await client.readErrors.close();
      });
    }
  }
}
