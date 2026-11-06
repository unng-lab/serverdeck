import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/console/console_models.dart';
import 'package:serverdeck/console/console_settings.dart';
import 'package:serverdeck/console/console_settings_view.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_components.dart';

import '../fixtures/feature_harness.dart';

void main() {
  late FeatureHarness h;
  late ConsoleSettingsOwner owner;
  setUp(() async {
    h = FeatureHarness();
    owner = ConsoleSettingsOwner(
      actors: h.actors,
      gate: h.gate,
      repository: h.repository,
    );
    await owner.save(
      h.actors.ui,
      ConsoleConfiguration(
        profiles: [
          ConsoleShellProfile(
            id: featureId(7),
            name: 'Bash',
            path: '/bin/bash',
          ),
        ],
      ),
      expectedRevision: 1,
    );
  });
  tearDown(() async {
    await owner.dispose();
    await h.dispose();
  });
  testWidgets(
    'default profile save is explicit and failed save preserves draft',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ConsoleSettingsView(owner: owner, newId: h.newId),
            ),
          ),
        ),
      );
      final select = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>).first,
      );
      select.onChanged!(featureId(7));
      await tester.pump();
      expect(owner.snapshot.defaultId, 'login');
      h.repository.failCommit = true;
      final button = tester.widget<DeckButton>(
        find
            .ancestor(
              of: find.text('Сохранить'),
              matching: find.byType(DeckButton),
            )
            .first,
      );
      await tester.runAsync(() async {
        await button.onPressed!();
      });
      await tester.pump();
      expect(owner.snapshot.defaultId, 'login');
      expect(
        find.text('Не удалось прочитать или сохранить локальные данные.'),
        findsOneWidget,
      );
      final retry = tester.widget<DeckButton>(
        find
            .ancestor(
              of: find.text('Сохранить'),
              matching: find.byType(DeckButton),
            )
            .first,
      );
      await tester.runAsync(() async {
        await retry.onPressed!();
      });
      await tester.pump();
      expect(owner.snapshot.defaultId, featureId(7));
    },
  );
}
