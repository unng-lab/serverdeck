import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/profiles/recovery_view.dart';
import 'package:serverdeck/settings/settings_view.dart';
import 'package:serverdeck/shell/base_workspace.dart';
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck/ui/deck_page.dart';
import 'package:serverdeck_protocol/models.dart' show ReadinessState;

import '../support/design_host.dart' show loadDesignFonts;
import '../support/design_scenarios.dart';

void main() {
  setUpAll(loadDesignFonts);
  testWidgets('recent operations close returns to its actual caller', (
    tester,
  ) async {
    final harness = await DesignScenarioHarness.create();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: Motion.theme(BrandTheme.dark, true),
          home: BaseWorkspace(
            profiles: harness.profiles,
            recovery: harness.recovery,
            client: null,
            state: ReadinessState.ready,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final reads = harness.client.reads.length;
      final refreshes = harness.client.refreshes;
      final settings = find.byKey(
        const ValueKey('foundation-navigation-settings'),
      );
      await tester.ensureVisible(settings);
      await tester.tap(settings);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsView), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(RecentOperationsButton),
          matching: find.byType(IconButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RecentOperationsView), findsOneWidget);
      expect(
        tester.widget<FoundationShell>(find.byType(FoundationShell)).section,
        FoundationSection.jobs,
      );
      final close = find.widgetWithText(OutlinedButton, 'Закрыть');
      await tester.ensureVisible(close);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byType(RecentOperationsView), findsNothing);
      expect(find.byType(SettingsView), findsOneWidget);
      expect(
        tester.widget<FoundationShell>(find.byType(FoundationShell)).section,
        FoundationSection.settings,
      );
      expect(harness.client.reads.length, reads);
      expect(harness.client.refreshes, refreshes);
      expect(harness.client.mutations, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.close();
    }
  });
  for (final frame in const [
    Size(1100, 760),
    Size(800, 600),
    Size(390, 800),
    Size(360, 800),
  ]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        for (final empty in [false, true]) {
          testWidgets(
            'Jobs opens author-only profiles $frame $dark $scale empty=$empty',
            (tester) async {
              tester.view.physicalSize = frame;
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              final harness = await DesignScenarioHarness.create(
                options: DesignFixtureOptions(empty: empty),
              );
              try {
                await tester.pumpWidget(
                  MaterialApp(
                    theme: Motion.theme(
                      dark ? BrandTheme.dark : BrandTheme.light,
                      true,
                    ),
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!,
                    ),
                    home: BaseWorkspace(
                      profiles: harness.profiles,
                      recovery: harness.recovery,
                      client: null,
                      state: ReadinessState.ready,
                    ),
                  ),
                );
                await tester.pumpAndSettle();
                final selected = harness.profiles.selected?.id;
                final reads = harness.client.reads.length,
                    refreshes = harness.client.refreshes;
                final jobs = find.byKey(
                  const ValueKey('foundation-navigation-jobs'),
                );
                await tester.ensureVisible(jobs);
                await tester.tap(jobs);
                await tester.pumpAndSettle();
                final entry = find.widgetWithText(
                  OutlinedButton,
                  'Ansible-профили',
                );
                expect(entry, findsOneWidget);
                await tester.ensureVisible(entry);
                await tester.tap(entry);
                await tester.pumpAndSettle();
                expect(
                  tester.widget<DeckPage>(find.byType(DeckPage)).title,
                  'Ansible-профили',
                );
                expect(
                  tester.widget<DeckPage>(find.byType(DeckPage)).eyebrow,
                  'Задания / Рабочее пространство',
                );
                expect(
                  tester
                      .widget<FoundationShell>(find.byType(FoundationShell))
                      .section,
                  FoundationSection.jobs,
                );
                expect(
                  find.text('Подключение к службе не подтверждено'),
                  findsOneWidget,
                );
                expect(find.text('Выберите сервер'), findsNothing);
                expect(
                  tester
                      .widget<MotionDropdown<String>>(
                        find.byType(MotionDropdown<String>),
                      )
                      .initialValue,
                  selected,
                );
                await tester.tap(
                  find.descendant(
                    of: find.byType(RecentOperationsButton),
                    matching: find.byType(IconButton),
                  ),
                );
                await tester.pumpAndSettle();
                expect(find.byType(RecentOperationsView), findsOneWidget);
                final close = find.widgetWithText(OutlinedButton, 'Закрыть');
                await tester.ensureVisible(close);
                await tester.tap(close);
                await tester.pumpAndSettle();
                expect(
                  tester.widget<DeckPage>(find.byType(DeckPage)).title,
                  'Ansible-профили',
                );
                await tester.ensureVisible(jobs);
                await tester.tap(jobs);
                await tester.pumpAndSettle();
                expect(
                  tester.widget<DeckPage>(find.byType(DeckPage)).title,
                  'Задания',
                );
                expect(
                  find.widgetWithText(OutlinedButton, 'Ansible-профили'),
                  findsOneWidget,
                );
                final grants = find.widgetWithText(OutlinedButton, 'ИИ-доступ');
                await tester.ensureVisible(grants);
                await tester.tap(grants);
                await tester.pumpAndSettle();
                expect(
                  tester.widget<DeckPage>(find.byType(DeckPage)).title,
                  'Доступ ИИ',
                );
                expect(
                  tester.widget<DeckPage>(find.byType(DeckPage)).eyebrow,
                  'Настройки / Рабочее пространство',
                );
                expect(
                  tester
                      .widget<FoundationShell>(find.byType(FoundationShell))
                      .section,
                  FoundationSection.settings,
                );
                expect(
                  tester
                      .widget<MotionDropdown<String>>(
                        find.byType(MotionDropdown<String>),
                      )
                      .initialValue,
                  selected,
                );
                expect(harness.client.reads.length, reads);
                expect(harness.client.refreshes, refreshes);
                expect(harness.client.mutations, isEmpty);
                expect(tester.takeException(), isNull);
              } finally {
                await tester.pumpWidget(const SizedBox.shrink());
                await harness.close();
              }
            },
          );
        }
      }
    }
  }
}
