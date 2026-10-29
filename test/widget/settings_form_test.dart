import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/settings/settings_form.dart';
import 'package:serverdeck/settings/settings_view.dart' as presentation;
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
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

  for (final reduced in [false, true]) {
    testWidgets('active profile full value is readable at200 reduced=$reduced', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const longName =
          'Сервер управления инфраструктурой 日本語 例 — длинное полное название профиля';
      final snapshot = fixture.snapshot(revision: '2');
      final profiles = Map<String, Object?>.from(
        snapshot.profiles.result as Map,
      );
      final profile = Map<String, Object?>.from(
        (profiles['profiles']! as List).single as Map,
      )..['name'] = longName;
      profiles['profiles'] = [profile];
      client.events.add(
        ClientSnapshot(
          ApiReply(fixture.fixtureGeneration, profiles),
          snapshot.settings,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: reduced,
            ),
            child: child!,
          ),
          home: Scaffold(body: presentation.SettingsView(controller: model)),
        ),
      );
      await tester.ensureVisible(find.text('Изменить настройки'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Изменить настройки'));
      await tester.pumpAndSettle();
      final selector = find.byWidgetPredicate(
        (widget) => widget is MotionDropdown<String>,
      );
      await tester.ensureVisible(selector);
      await tester.pumpAndSettle();
      final selected = find.descendant(
        of: selector,
        matching: find.text(longName),
      );
      expect(selected, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(selected).didExceedMaxLines,
        isFalse,
        reason: 'Selected target must expose its full value',
      );
      final paragraph = tester.renderObject<RenderParagraph>(selected);
      final textBounds = paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: longName.length),
      );
      expect(
        textBounds.last.bottom,
        lessThanOrEqualTo(paragraph.size.height),
        reason: 'All selected text lines must fit the painted value',
      );
      await tester.tap(selector);
      await tester.pumpAndSettle();
      final choice = find.text(longName).last;
      await tester.ensureVisible(choice);
      await tester.pumpAndSettle();
      expect(
        tester.renderObject<RenderParagraph>(choice).didExceedMaxLines,
        isFalse,
        reason: 'Keyboard/touch choice must expose its full value',
      );
      final option = tester.renderObject<RenderParagraph>(choice);
      final choiceBounds = option.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: longName.length),
      );
      expect(
        choiceBounds.last.bottom,
        lessThanOrEqualTo(option.size.height),
        reason: 'All choice text lines must fit the painted item',
      );
      expect(choice.hitTestable(), findsOneWidget);
      expect(client.sent, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsForm), findsNothing);
      expect(client.sent, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'current settings stay separate from draft and hide outside ready',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.light,
          home: Scaffold(
            body: ListenableBuilder(
              listenable: model,
              builder: (_, _) => presentation.SettingsView(controller: model),
            ),
          ),
        ),
      );
      expect(find.text('Тёмная'), findsOneWidget);
      expect(find.text('Включено'), findsOneWidget);
      expect(find.text('Saved profile · 192.0.2.1:22'), findsOneWidget);
      await tester.tap(find.text('Изменить настройки'));
      await tester.pumpAndSettle();
      final motion = find.byWidgetPredicate(
        (widget) => widget is MotionDropdown<bool>,
      );
      await tester.ensureVisible(motion);
      await tester.tap(motion);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Выключено').last);
      await tester.pumpAndSettle();
      expect(tester.widget<MotionDropdown<bool>>(motion).initialValue, isFalse);
      expect(model.settings!.reduceMotion, isTrue);
      expect(client.sent, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      bootstrap.show(ReadinessState.unavailable);
      // The root replaces this private section with ReadinessView. This isolated
      // section has an unfinished load, so inspect a frame without settling it.
      await tester.pump();
      expect(find.textContaining('Saved profile'), findsNothing);
      expect(find.text('Тёмная'), findsNothing);
      expect(client.sent, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

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
