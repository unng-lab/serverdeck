import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/app.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck/theme/brand_theme.dart';

import '../contract/profile_controller_test.dart' as fixture;

void main() {
  testWidgets(
    'reduced dropdown reaches selection and revokes private choices',
    (tester) async {
      final changes = ValueNotifier<bool>(true);
      String selected = 'a';
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Scaffold(
            body: MotionDropdown<String>(
              initialValue: 'a',
              decoration: const InputDecoration(labelText: 'Выбор'),
              changes: changes,
              available: () => changes.value,
              items: const [
                DropdownMenuItem(value: 'a', child: Text('Private A')),
                DropdownMenuItem(value: 'b', child: Text('Private B')),
              ],
              onChanged: (value) => selected = value!,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Выбор'));
      await tester.pump();
      final route = ModalRoute.of(
        tester.element(find.text('Private B')),
      ) as TransitionRoute;
      expect(route.transitionDuration, Duration.zero);
      await tester.tap(find.text('Private B'));
      await tester.pump();
      expect(selected, 'b');
      await tester.tap(find.text('Выбор'));
      await tester.pump();
      changes.value = false;
      await tester.pump();
      // The launcher remains in this synthetic host; the popup removes choices.
      expect(find.text('Private B'), findsNothing);
      expect(
        find.text('Выбор недоступен: локальная служба не готова'),
        findsOneWidget,
      );
      await tester.tap(find.text('Отмена'));
      await tester.pump();
      expect(selected, 'b');
      await tester.pumpWidget(const SizedBox.shrink());
      changes.dispose();
    },
  );

  testWidgets('production reduced drawer and profile dialog have zero routes', (
    tester,
  ) async {
    final client = fixture.ModelClient();
    final bootstrap = fixture.ModelBootstrap(client)
      ..show(ReadinessState.ready);
    await tester.pumpWidget(FoundationApp(bootstrap: bootstrap));
    client.events.add(fixture.snapshot());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Создать профиль'));
    await tester.pump();
    expect(
      (ModalRoute.of(
        tester.element(find.text('Сохранить')),
      ) as TransitionRoute).transitionDuration,
      Duration.zero,
    );
    await tester.ensureVisible(find.text('Отмена'));
    await tester.tap(find.text('Отмена'));
    await tester.pump();
    await tester.tap(find.byTooltip('Открыть меню навигации'));
    await tester.pump();
    expect(find.byType(Drawer), findsOneWidget);
    expect(
      (ModalRoute.of(
        tester.element(find.text('Настройки').last),
      ) as TransitionRoute).transitionDuration,
      Duration.zero,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Настройки'));
    await tester.pump();
    expect(find.byType(Drawer), findsNothing);
    expect(find.text('Тема: тёмная'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await client.events.close();
    await client.readErrors.close();
  });

  for (final os in [false, true]) {
    for (final saved in [false, true]) {
      testWidgets(
        'effective motion OS=$os saved=$saved affects theme and expansion',
        (tester) async {
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              FakeAccessibilityFeatures(disableAnimations: os);
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
          final client = fixture.ModelClient();
          final bootstrap = fixture.ModelBootstrap(client)
            ..show(ReadinessState.ready);
          await tester.pumpWidget(FoundationApp(bootstrap: bootstrap));
          final old = fixture.snapshot();
          client.events.add(
            ClientSnapshot(
              old.profiles,
              ApiReply(fixture.fixtureGeneration, {
                'storeRevision': '1',
                'settings': SettingsView(
                  theme: ThemePreference.dark,
                  reduceMotion: saved,
                ).toJson(),
              }),
            ),
          );
          await tester.pumpAndSettle();
          final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
          expect(
            app.themeAnimationStyle,
            os || saved ? AnimationStyle.noAnimation : isNull,
          );
          final context = tester.element(find.byType(ExpansionTile));
          expect(MediaQuery.disableAnimationsOf(context), os || saved);
          expect(
            Theme.of(context).expansionTileTheme.expansionAnimationStyle,
            os || saved ? AnimationStyle.noAnimation : isNull,
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await client.events.close();
          await client.readErrors.close();
        },
      );
    }
  }
}
