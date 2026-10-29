import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/main.dart';
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck_protocol/models.dart' show ReadinessState;

import '../contract/profile_controller_test.dart' as fixture;
import '../support/design_host.dart' show loadDesignFonts;

/// These assertions use canonical source geometry/composition and can also run
/// against the pre-port source revision. They do not bless a candidate baseline.
void main() {
  setUpAll(loadDesignFonts);
  testWidgets('canonical800 rail is68 logical pixels', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.dark,
        home: const FoundationShell(
          state: ReadinessState.ready,
          servers: Text('Body'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('foundation-sidebar'))).width,
      68,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('canonical04 welcome exists in the ordinary empty app', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = fixture.ModelClient();
    final bootstrap = fixture.ModelBootstrap(client)
      ..show(ReadinessState.ready);
    try {
      await tester.pumpWidget(FoundationApp(bootstrap: bootstrap));
      final initial = fixture.snapshot();
      client.events.add(
        ClientSnapshot(
          ApiReply(fixture.fixtureGeneration, {
            'storeRevision': '1',
            'profiles': <Object?>[],
          }),
          ApiReply(fixture.fixtureGeneration, {
            ...initial.settings.result,
            'settings': {
              ...(initial.settings.result['settings'] as Map<String, Object?>),
              'selectedProfileId': null,
            },
          }),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Все серверы.\nОдин центр управления.'), findsOneWidget);
      for (final label in [
        'Добавьте подключение',
        'Проверьте доверие',
        'Получите первый снимок',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await client.events.close();
      await client.readErrors.close();
    }
  });
}
