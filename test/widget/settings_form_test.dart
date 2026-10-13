import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/settings/settings_form.dart';
import 'package:serverdeck/settings/settings_view.dart' as presentation;
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck_protocol/models.dart';

import '../contract/profile_controller_test.dart' as fixture;
import '../contract/mutation_controller_test.dart' show MutationClient;

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

  testWidgets('loss-ready hides selection without losing the RAM draft', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.light,
        home: SettingsForm(model: model),
      ),
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      false,
    );
    bootstrap.show(ReadinessState.unavailable);
    await tester.pumpAndSettle();
    expect(find.text('Saved profile'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(client.sent, isEmpty);
    bootstrap.show(ReadinessState.ready);
    client.events.add(fixture.snapshot());
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      false,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Esc cancels before send and restores launcher focus', (
    tester,
  ) async {
    final launcher = FocusNode();
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
                builder: (_) => SettingsForm(model: model),
              ),
              child: const Text('Открыть настройки'),
            ),
          ),
        ),
      ),
    );
    launcher.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsForm), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsForm), findsNothing);
    expect(client.sent, isEmpty);
    expect(launcher.hasFocus, true);
    await tester.pumpWidget(const SizedBox.shrink());
    launcher.dispose();
  });

  for (final lossReady in [true, false]) {
    testWidgets('launcher snapshot race recovers safely lossReady=$lossReady', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.light,
          home: Scaffold(body: presentation.SettingsView(controller: model)),
        ),
      );
      await tester.tap(find.text('Изменить настройки'));
      if (lossReady) {
        bootstrap.show(ReadinessState.unavailable);
      } else {
        client.readErrors.add(ErrorCode.timeout);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Saved profile'), findsNothing);
      expect(find.text('Сохранить настройки'), findsNothing);
      if (lossReady) bootstrap.show(ReadinessState.ready);
      client.events.add(fixture.snapshot());
      await tester.pumpAndSettle();
      expect(find.text('Сохранить настройки'), findsOneWidget);
      expect(find.text('Saved profile'), findsOneWidget);
      expect(client.sent, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final dark in [false, true]) {
    for (final size in const [
      Size(1100, 760),
      Size(800, 600),
      Size(360, 800),
      Size(390, 800),
    ]) {
      testWidgets('settings controls reachable at200 $size dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? BrandTheme.dark : BrandTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: SettingsForm(model: model),
          ),
        );
        await tester.ensureVisible(find.text('Сохранить настройки'));
        await tester.pumpAndSettle();
        expect(
          tester
              .getSize(find.widgetWithText(FilledButton, 'Сохранить настройки'))
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
