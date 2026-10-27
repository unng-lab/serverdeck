import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/app.dart';
import 'package:serverdeck/shell/foundation_shell.dart';

import '../contract/profile_controller_test.dart' as fixture;

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'Russian framework labels and phone navigation on English OS reduced=$reduced',
      (tester) async {
        tester.view.physicalSize = const Size(390, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: reduced);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearLocaleTestValue);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        final client = fixture.ModelClient();
        final bootstrap = fixture.ModelBootstrap(client);
        await tester.pumpWidget(FoundationApp(bootstrap: bootstrap));
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(FoundationShell));
        expect(Localizations.localeOf(context), const Locale('ru', 'RU'));
        expect(MaterialLocalizations.of(context).closeButtonLabel, 'Закрыть');
        expect(
          MaterialLocalizations.of(context).openAppDrawerTooltip,
          'Открыть меню навигации',
        );
        expect(MediaQuery.disableAnimationsOf(context), reduced);
        expect(
          find.byKey(const ValueKey('foundation-phone-navigation')),
          findsOneWidget,
        );
        final settings = find.byKey(
          const ValueKey('foundation-navigation-settings'),
        );
        expect(
          find.descendant(of: settings, matching: find.text('Настройки')),
          findsOneWidget,
        );
        final route = ModalRoute.of(tester.element(settings));
        await tester.ensureVisible(settings);
        await tester.pumpAndSettle();
        expect(settings.hitTestable(), findsOneWidget);
        await tester.tap(settings);
        await tester.pumpAndSettle();
        expect(ModalRoute.of(tester.element(settings)), same(route));
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('foundation-page-title')))
              .data,
          'Настройки',
        );
        expect(
          Localizations.localeOf(tester.element(settings)),
          const Locale('ru', 'RU'),
        );
        expect(
          MaterialLocalizations.of(tester.element(settings)).closeButtonLabel,
          'Закрыть',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await client.events.close();
        await client.readErrors.close();
      },
    );
  }
}
