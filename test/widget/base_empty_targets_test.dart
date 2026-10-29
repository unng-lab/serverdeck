import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/servers/server_sections.dart';
import 'package:serverdeck/shell/base_workspace.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck/ui/deck_icon.dart';
import 'package:serverdeck_protocol/models.dart' show ReadinessState;

import '../support/design_fonts.dart';
import '../support/design_scenarios.dart';

void main() {
  setUpAll(loadDesignFonts);
  for (final reduced in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'workspace empty selector keeps input content $reduced $scale',
        (tester) async {
          final harness = await DesignScenarioHarness.create(
            options: const DesignFixtureOptions(empty: true),
          );
          try {
            await tester.pumpWidget(
              MaterialApp(
                theme: Motion.theme(BrandTheme.dark, reduced),
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
            await tester.tap(
              find.byKey(const ValueKey('foundation-navigation-logs')),
            );
            await tester.pumpAndSettle();
            final field = find.byType(MotionDropdown<String>);
            expect(field, findsOneWidget);
            expect(tester.getSize(field).height, greaterThanOrEqualTo(44));
            final icon = find
                .descendant(of: field, matching: find.byType(DeckIcon))
                .last;
            final container = InputDecorator.containerOf(tester.element(icon));
            expect(container, isNotNull);
            expect(container!.size.height, greaterThanOrEqualTo(42));
            if (!reduced) {
              final button = find.descendant(
                of: field,
                matching: find.byType(DropdownButton<String>),
              );
              expect(
                tester.getSize(button).height,
                greaterThanOrEqualTo(20 * scale),
              );
            }
            expect(
              find.text('Выбор цели не подключает сервер'),
              findsOneWidget,
            );
            final reads = harness.client.reads.length;
            await tester.tap(field);
            await tester.pumpAndSettle();
            expect(find.byType(Dialog), findsNothing);
            expect(harness.client.reads.length, reads);
            expect(harness.client.mutations, isEmpty);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await harness.close();
          }
        },
      );
      testWidgets('empty log selector remains readable $reduced $scale', (
        tester,
      ) async {
        var selections = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: Motion.theme(BrandTheme.dark, reduced),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: ServerLogTargetSelector(
                profiles: const [],
                selectedId: null,
                onSelected: (_) => selections++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final field = find.byType(MotionDropdown<String>);
        final decoration = find.descendant(
          of: field,
          matching: find.byType(InputDecorator),
        );
        expect(tester.getSize(field).height, greaterThanOrEqualTo(44));
        expect(tester.getSize(decoration).height, greaterThanOrEqualTo(36));
        expect(find.text('Выберите сервер'), findsWidgets);
        await tester.tap(field);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(find.byType(DropdownMenuItem<String>), findsNothing);
        expect(selections, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final empty in [false, true]) {
    testWidgets('jobs without target keeps scope and next step empty=$empty', (
      tester,
    ) async {
      var navigations = 0;
      var effects = 0;
      String? target;
      final profile = DesignServerFixtures.profile();
      Widget section() => AutomationJobsSection(
        jobs: const [],
        events: const [],
        loaded: true,
        hasMore: false,
        droppedEvents: 0,
        canCancel: false,
        canReconcile: false,
        serverId: target,
        scopeSelector: ServerLogTargetSelector(
          profiles: [if (!empty) profile],
          selectedId: target,
          onSelected: (id) => target = id,
        ),
        onOpenServers: () => navigations++,
        showHeaderActions: false,
        actions: const AutomationActionAvailability(
          read: false,
          mutate: false,
          select: true,
        ),
        onRefresh: () => effects++,
        onRefreshAuthorities: () => effects++,
        onSelect: (_) => effects++,
        onMore: () => effects++,
        onShowPlan: () => effects++,
        onCancel: () => effects++,
        onReconcile: () => effects++,
      );
      Widget app() => MaterialApp(
        theme: Motion.theme(BrandTheme.dark, true),
        home: Scaffold(body: SingleChildScrollView(child: section())),
      );
      await tester.pumpWidget(app());
      expect(find.text('Все'), findsOneWidget);
      expect(find.text('Область просмотра'), findsOneWidget);
      expect(find.text('Выберите сервер'), findsOneWidget);
      expect(find.text('Заданий на этом сервере пока нет'), findsNothing);
      final next = find.widgetWithText(FilledButton, 'К серверам');
      await tester.ensureVisible(next);
      await tester.tap(next);
      expect(navigations, 1);
      expect(effects, 0);
      final scope = find.widgetWithText(TextButton, 'Выбрать сервер');
      await tester.ensureVisible(scope);
      await tester.tap(scope);
      await tester.pumpAndSettle();
      final selector = find.byType(ServerLogTargetSelector);
      expect(selector, findsOneWidget);
      if (!empty) {
        tester.widget<ServerLogTargetSelector>(selector).onSelected!(
          profile.id,
        );
      }
      Navigator.of(tester.element(find.byType(Dialog))).pop();
      await tester.pumpAndSettle();
      await tester.pumpWidget(app());
      if (!empty) {
        expect(target, profile.id);
        expect(find.text('Выберите сервер'), findsNothing);
        expect(find.text('Заданий на этом сервере пока нет'), findsOneWidget);
      } else {
        expect(target, isNull);
        expect(find.text('Выберите сервер'), findsOneWidget);
        expect(find.text('Заданий на этом сервере пока нет'), findsNothing);
      }
      expect(effects, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
