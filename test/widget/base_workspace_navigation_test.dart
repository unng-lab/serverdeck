import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/profiles/recovery_view.dart';
import 'package:serverdeck/settings/settings_view.dart';
import 'package:serverdeck/software/software_panel.dart';
import 'package:serverdeck/shell/base_workspace.dart';
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck/ui/deck_page.dart';
import 'package:serverdeck_protocol/models.dart' show ReadinessState;
import 'package:serverdeck_protocol/models.dart' as protocol show SettingsView;
import 'package:serverdeck/bootstrap/local_api_client.dart'
    show ClientSnapshot, ApiReply;

import '../support/design_host.dart' show loadDesignFonts;
import '../support/design_scenarios.dart';
import '../contract/profile_controller_test.dart' as profileFixture;

void main() {
  testWidgets(
    'T222 plan review chrome preserves actual owner and retires leases',
    (tester) async {
      final harness = await DesignScenarioHarness.create();
      var epoch = 0;
      var readiness = ReadinessState.ready;
      Widget app() => MaterialApp(
        theme: Motion.theme(BrandTheme.dark, true),
        home: BaseWorkspace(
          profiles: harness.profiles,
          recovery: harness.recovery,
          client: null,
          state: readiness,
          privateEpoch: epoch,
        ),
      );
      FoundationSection? selected() =>
          tester.widget<FoundationShell>(find.byType(FoundationShell)).section;
      try {
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('foundation-navigation-software')),
        );
        await tester.pumpAndSettle();
        final software = find.byType(SoftwarePanel);
        final owner = tester.state(software);
        final reads = harness.client.reads.length;
        final refreshes = harness.client.refreshes;
        VoidCallback begin() =>
            tester.widget<SoftwarePanel>(software).onPlanReview!.call();
        final first = begin();
        await tester.pumpAndSettle();
        expect(selected(), FoundationSection.jobs);
        expect(tester.state(software), same(owner));
        final second = begin();
        await tester.pumpAndSettle();
        first();
        await tester.pumpAndSettle();
        expect(selected(), FoundationSection.jobs);
        expect(tester.state(software), same(owner));
        second();
        await tester.pumpAndSettle();
        expect(selected(), FoundationSection.software);
        const otherId = '33333333-3333-4333-8333-333333333333';
        var revision = 2;
        void defaultTarget(String? id) {
          final source = profileFixture.snapshot(revision: '${revision++}');
          final row = Map<String, Object?>.from(
            (source.profiles.result['profiles'] as List).single as Map,
          );
          harness.client.events.add(
            ClientSnapshot(
              ApiReply(profileFixture.fixtureGeneration, {
                'storeRevision': source.storeRevision,
                'profiles': [
                  row,
                  {...row, 'id': otherId, 'name': 'Other server'},
                ],
              }),
              ApiReply(profileFixture.fixtureGeneration, {
                'storeRevision': source.storeRevision,
                'settings': protocol.SettingsView(
                  revision: source.storeRevision,
                  selectedProfileId: id,
                ).toJson(),
              }),
            ),
          );
        }

        for (final changedTarget in [otherId, null]) {
          final beforeDefaultChange = begin();
          await tester.pumpAndSettle();
          defaultTarget(changedTarget);
          if (changedTarget == null) {
            await tester.pumpAndSettle();
            expect(harness.profiles.selected, isNull);
            expect(selected(), FoundationSection.software);
          }
          // Also cover A→B→A notifications coalesced into one rendered frame.
          defaultTarget(harness.initialProfile.id);
          await tester.pumpAndSettle();
          expect(selected(), FoundationSection.software);
          expect(tester.state(software), same(owner));
          final afterDefaultChange = begin();
          await tester.pumpAndSettle();
          beforeDefaultChange();
          await tester.pumpAndSettle();
          expect(selected(), FoundationSection.jobs);
          afterDefaultChange();
          await tester.pumpAndSettle();
          expect(selected(), FoundationSection.software);
        }
        final beforeTargetChange = begin();
        await tester.pumpAndSettle();
        tester.widget<SoftwarePanel>(software).onServerSelected!(
          harness.initialProfile.id,
        );
        await tester.pumpAndSettle();
        expect(selected(), FoundationSection.software);
        final afterTargetChange = begin();
        await tester.pumpAndSettle();
        beforeTargetChange();
        await tester.pumpAndSettle();
        expect(selected(), FoundationSection.jobs);
        afterTargetChange();
        await tester.pumpAndSettle();
        final beforeNavigation = begin();
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('foundation-navigation-settings')),
        );
        await tester.pumpAndSettle();
        beforeNavigation();
        await tester.pumpAndSettle();
        expect(selected(), FoundationSection.settings);
        expect(find.byType(SettingsView), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('foundation-navigation-software')),
        );
        await tester.pumpAndSettle();
        final beforeEpoch = begin();
        await tester.pumpAndSettle();
        epoch++;
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        expect(selected(), FoundationSection.software);
        final current = begin();
        await tester.pumpAndSettle();
        beforeEpoch();
        await tester.pumpAndSettle();
        expect(selected(), FoundationSection.jobs);
        current();
        final beforeReadinessLoss = begin();
        await tester.pumpAndSettle();
        readiness = ReadinessState.unavailable;
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        expect(selected(), FoundationSection.software);
        readiness = ReadinessState.ready;
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        beforeReadinessLoss();
        await tester.pumpAndSettle();
        expect(selected(), FoundationSection.software);
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
