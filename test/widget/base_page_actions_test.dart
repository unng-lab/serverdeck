import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:serverdeck/automation/automation_panel.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/settings/settings_view.dart';
import 'package:serverdeck/shell/base_workspace.dart';
import 'package:serverdeck/shell/deck_navigation.dart';
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck_protocol/models.dart' show ReadinessState;

import '../support/design_fonts.dart';
import '../support/design_scenarios.dart';
import 'deck_components_test.dart' show pixels;

void main() {
  setUpAll(loadDesignFonts);
  test('T180 grants belongs to settings, other automation stays in jobs', () {
    expect(DeckView.grants.section, FoundationSection.settings);
    for (final view in [
      DeckView.jobs,
      DeckView.automationProfiles,
      DeckView.recentOperations,
    ]) {
      expect(view.section, FoundationSection.jobs);
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
        testWidgets(
          'T179 source action widths and neutral fill $frame $dark $scale',
          (tester) async {
            tester.view.physicalSize = frame;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final theme = dark ? BrandTheme.dark : BrandTheme.light;
            final boundary = GlobalKey();
            var effects = 0;
            const available = AutomationActionAvailability(
              read: true,
              mutate: true,
              select: true,
            );
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        RepaintBoundary(
                          key: boundary,
                          child: OutlinedButton(
                            onPressed: () => effects++,
                            child: const Text('Нейтральное действие'),
                          ),
                        ),
                        AutomationProfilesSection(
                          profiles: [DesignAutomationFixtures.profile()],
                          loaded: true,
                          hasMore: false,
                          actions: available,
                          onSelect: (_) => effects++,
                          onMore: () => effects++,
                          onSelectVersion: () => effects++,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final fill = await pixels(tester, boundary, const [Offset(9, 12)]);
            expect(fill.single, theme.extension<BrandColors>()!['surface']);
            final searchImage = find.descendant(
              of: find.byType(TextField),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is SvgPicture &&
                    widget.bytesLoader is SvgAssetLoader &&
                    (widget.bytesLoader as SvgAssetLoader).assetName.endsWith(
                      '/search.svg',
                    ),
              ),
            );
            expect(searchImage, findsOneWidget);
            expect(tester.getSize(searchImage), const Size(15, 15));
            expect(
              tester.widget<SvgPicture>(searchImage).colorFilter,
              ColorFilter.mode(
                theme.extension<BrandColors>()!['muted'],
                BlendMode.srcIn,
              ),
            );
            final tags = find.text('Теги');
            expect(tags, findsOneWidget);
            final disabledTags = find.ancestor(
              of: tags,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics && widget.properties.enabled == false,
              ),
            );
            expect(disabledTags, findsOneWidget);
            final chevron = find.descendant(
              of: disabledTags,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is SvgPicture &&
                    widget.bytesLoader is SvgAssetLoader &&
                    (widget.bytesLoader as SvgAssetLoader).assetName.endsWith(
                      '/chevron.svg',
                    ),
              ),
            );
            expect(tester.getSize(chevron), const Size(12, 12));
            final version = find.widgetWithText(
              OutlinedButton,
              'Выбрать версию',
            );
            final width = tester.getSize(version).width;
            if (frame.width <= 520) {
              expect(width, closeTo(frame.width - 32, 1));
            } else {
              expect(width, lessThan((frame.width - 32) / 2));
            }
            for (final section in ['profiles', 'grants']) {
              final actions = automationPageActions(
                section: section,
                availability: available,
                onRefresh: () => effects++,
                onCreate: () => effects++,
                onLoadRecipes: () => effects++,
              );
              expect(actions.first, isA<OutlinedButton>());
              final denied = automationPageActions(
                section: section,
                availability: const AutomationActionAvailability(
                  read: false,
                  mutate: false,
                  select: false,
                ),
                onRefresh: () => effects++,
                onCreate: () => effects++,
                onLoadRecipes: () => effects++,
              );
              expect((denied.first as OutlinedButton).onPressed, isNull);
            }
            expect(effects, 0);
            await tester.ensureVisible(version);
            await tester.tap(version);
            await tester.pumpAndSettle();
            expect(effects, 1);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );

        testWidgets('T180 actual workspace grants route $frame $dark $scale', (
          tester,
        ) async {
          tester.view.physicalSize = frame;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final harness = await DesignScenarioHarness.create();
          try {
            await tester.pumpWidget(
              MaterialApp(
                theme: dark ? BrandTheme.dark : BrandTheme.light,
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
            final reads = harness.client.reads.length,
                refreshes = harness.client.refreshes;
            final ai = find.text('ИИ-доступ');
            await tester.ensureVisible(ai);
            await tester.tap(ai);
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<FoundationShell>(find.byType(FoundationShell))
                  .section,
              FoundationSection.settings,
            );
            expect(find.byType(SettingsView), findsNothing);
            expect(find.text('Доступ ИИ'), findsOneWidget);
            final jobs = find.byKey(
              const ValueKey('foundation-navigation-jobs'),
            );
            await tester.ensureVisible(jobs);
            await tester.tap(jobs);
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<FoundationShell>(find.byType(FoundationShell))
                  .section,
              FoundationSection.jobs,
            );
            final jobsAi = find.widgetWithText(OutlinedButton, 'ИИ-доступ');
            expect(jobsAi, findsOneWidget);
            await tester.ensureVisible(jobsAi);
            await tester.tap(jobsAi);
            await tester.pumpAndSettle();
            expect(find.text('Доступ ИИ'), findsOneWidget);
            expect(
              tester
                  .widget<FoundationShell>(find.byType(FoundationShell))
                  .section,
              FoundationSection.settings,
            );
            final settings = find.byKey(
              const ValueKey('foundation-navigation-settings'),
            );
            await tester.ensureVisible(settings);
            await tester.tap(settings);
            await tester.pumpAndSettle();
            expect(find.byType(SettingsView), findsOneWidget);
            await tester.ensureVisible(find.text('ИИ-доступ'));
            await tester.tap(find.text('ИИ-доступ'));
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<FoundationShell>(find.byType(FoundationShell))
                  .section,
              FoundationSection.settings,
            );
            expect(find.text('Доступ ИИ'), findsOneWidget);
            expect(harness.client.reads.length, reads);
            expect(harness.client.refreshes, refreshes);
            expect(harness.client.mutations, isEmpty);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await harness.close();
          }
        });
      }
    }
  }
}
