import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/app.dart';
import 'package:serverdeck/shell/foundation_shell.dart';

import '../contract/profile_controller_test.dart' as fixture;

void main() {
  for (final reduced in [false, true]) {
    testWidgets('Russian framework labels on English OS reduced=$reduced', (
      tester,
    ) async {
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
      expect(find.byTooltip('Открыть меню навигации'), findsOneWidget);
      expect(find.byTooltip('Open navigation menu'), findsNothing);
      await tester.tap(find.byTooltip('Открыть меню навигации'));
      await tester.pumpAndSettle();
      expect(find.text('Серверы'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await client.events.close();
      await client.readErrors.close();
    });
  }
}
