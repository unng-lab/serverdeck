import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_panel.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_page.dart';
import 'package:serverdeck/ui/deck_icon.dart';

import '../support/design_automation_fixtures.dart';
import '../support/design_server_fixtures.dart';

const _available = AutomationActionAvailability(
  read: true,
  mutate: true,
  select: true,
);
void _noop() {}

Widget _host(Widget child, {double scale = 1, bool page = false}) =>
    MaterialApp(
      theme: BrandTheme.dark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 834,
            child: DeckPageInsets(
              padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
              child: page ? child : SingleChildScrollView(child: child),
            ),
          ),
        ),
      ),
    );

void _frame(WidgetTester tester, {double width = 1100}) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

AutomationPlanSection _plan({
  bool invalidated = false,
  bool preflight = false,
}) => AutomationPlanSection(
  plan: DesignAutomationFixtures.plan(),
  sourceRevision: DesignAutomationFixtures.revision(),
  serverProfiles: [DesignServerFixtures.profile(connectionRevision: '2')],
  automationProfile: DesignAutomationFixtures.profile(),
  runnable: true,
  expired: false,
  invalidReason: invalidated ? 'Условия изменились' : null,
  showPreflight: preflight,
  allowApply: false,
  showRefresh: false,
  actions: _available,
  onApprove: _noop,
  onDeny: _noop,
  onApply: _noop,
  onRefresh: _noop,
);

AutomationJobsSection _job(String state) => AutomationJobsSection(
  key: ValueKey(state),
  showHeaderActions: false,
  serverId: DesignAutomationFixtures.serverId,
  jobs: [
    {'job': DesignAutomationFixtures.job(state: state)},
  ],
  job: DesignAutomationFixtures.job(state: state),
  serverProfiles: [DesignServerFixtures.profile(connectionRevision: '2')],
  events: DesignAutomationFixtures.events(),
  loaded: true,
  hasMore: false,
  droppedEvents: 0,
  canCancel: state == 'running',
  canReconcile: state == 'unknown',
  actions: _available,
  onRefresh: _noop,
  onRefreshAuthorities: _noop,
  onSelect: (_) {},
  onMore: _noop,
  onShowPlan: _noop,
  onCancel: _noop,
  onReconcile: _noop,
);

void main() {
  testWidgets('only catalog list owns catalog tabs and scope ordering', (
    tester,
  ) async {
    _frame(tester);
    Widget page(String id) => AutomationPageFrame(
      screenId: id,
      title: id == '16-install-catalog' ? 'Каталог установки' : 'Ход задания',
      catalog: id.startsWith('16'),
      section: id.startsWith('16') ? 'catalog' : 'jobs',
      onSelected: (_) {},
      contextBar: const Text('Actual scope'),
      child: const Text('Actual content'),
    );
    await tester.pumpWidget(_host(page('16-install-catalog'), page: true));
    expect(find.text('Каталог'), findsOneWidget);
    expect(find.text('Планы установки'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Actual scope')).dy,
      greaterThan(tester.getTopLeft(find.text('Каталог')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Actual content')).dy,
      greaterThan(tester.getTopLeft(find.text('Actual scope')).dy),
    );
    for (final id in [
      '27-job-list',
      '28-job-detail',
      '29-job-unknown',
      '30-job-cancel',
      '32-automation-profiles',
      '34-profile-revisions',
      '36-ai-grants',
      '38-mcp-client-config',
      '93-protected-effect-blocked',
      '94-plan-invalidated',
    ]) {
      await tester.pumpWidget(_host(page(id), page: true));
      expect(find.byType(DeckTabs), findsNothing, reason: id);
      expect(find.text('Actual scope'), findsNothing, reason: id);
      expect(find.text('Actual content'), findsOneWidget, reason: id);
    }
  });

  testWidgets('header recipe selection is local and does not create a plan', (
    tester,
  ) async {
    _frame(tester);
    final key = GlobalKey<AutomationRecipesSectionState>();
    var created = 0;
    await tester.pumpWidget(
      _host(
        AutomationPageFrame(
          title: 'Каталог установки',
          screenId: '16-install-catalog',
          catalog: true,
          section: 'catalog',
          onSelected: (_) {},
          actions: automationPageActions(
            section: 'catalog',
            availability: _available,
            onRefresh: _noop,
            onCreate: _noop,
            onLoadRecipes: _noop,
            onSelectRecipe: () => key.currentState?.selectFirst(),
          ),
          child: AutomationRecipesSection(
            key: key,
            catalog: DesignAutomationFixtures.catalog(),
            canMutate: true,
            onCreatePlan: (_) => created++,
          ),
        ),
        page: true,
      ),
    );
    expect(find.text('Выбрать программу'), findsOneWidget);
    await tester.tap(find.text('Выбрать программу'));
    await tester.pumpAndSettle();
    expect(find.text('Сведения'), findsOneWidget);
    expect(find.text('Рецепт установки'), findsNothing);
    expect(created, 0);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('form regions use viewport and text scale $scale', (
      tester,
    ) async {
      _frame(tester);
      await tester.pumpWidget(
        _host(
          AutomationFormPageFrame(
            asPage: true,
            title: 'Параметры плана',
            child: const SizedBox(height: 50, child: Text('Actual field')),
            helper: const DeckPanel(child: Text('Actual helper')),
          ),
          page: true,
          scale: scale,
        ),
      );
      final field = tester.getRect(find.text('Actual field'));
      final helper = tester.getRect(find.text('Actual helper'));
      // FA05 stacks .form-grid fields, not the wide .form-layout aside.
      expect(helper.left, greaterThan(field.right));
      expect(helper.top, lessThan(field.bottom));
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'invalidated plan uses fullwidth conditions before consequences',
    (tester) async {
      _frame(tester);
      await tester.pumpWidget(_host(_plan(invalidated: true)));
      final conditions = find.ancestor(
        of: find.text('Параметры и условия'),
        matching: find.byType(DeckPanel),
      );
      final consequences = find.ancestor(
        of: find.text('Последствия'),
        matching: find.byType(DeckPanel),
      );
      expect(tester.getSize(conditions).width, closeTo(834, 1));
      expect(tester.getSize(consequences).width, closeTo(834, 1));
      expect(
        tester.getTopLeft(consequences).dy,
        greaterThan(tester.getBottomLeft(conditions).dy),
      );
      expect(find.byType(AutomationPlanSteps), findsNothing);
      expect(find.text('Запустить'), findsNothing);
    },
  );

  testWidgets('preflight stays readonly and pending approval has no Apply', (
    tester,
  ) async {
    _frame(tester);
    await tester.pumpWidget(_host(_plan(preflight: true)));
    expect(find.byType(AutomationPlanSteps), findsOneWidget);
    final refresh = find.widgetWithText(OutlinedButton, 'Обновить проверку');
    expect(tester.widget<OutlinedButton>(refresh).onPressed, isNull);
    await tester.ensureVisible(find.text('Просмотреть план'));
    await tester.tap(find.text('Просмотреть план'));
    await tester.pumpAndSettle();
    expect(find.text('Подтвердить план'), findsOneWidget);
    expect(find.text('Запустить'), findsNothing);
  });

  testWidgets('unknown and cancellation retain fullwidth context regions', (
    tester,
  ) async {
    _frame(tester);
    for (final state in ['unknown', 'cancel-requested']) {
      await tester.pumpWidget(_host(_job(state)));
      final panel = find.ancestor(
        of: find.text('Контекст и проверка результата'),
        matching: find.byType(DeckPanel),
      );
      expect(tester.getSize(panel).width, closeTo(834, 1));
      expect(find.text('Параметры плана'), findsNothing);
      expect(
        find.text(state == 'unknown' ? 'Показать события' : 'Открыть события'),
        findsOneWidget,
      );
      expect(
        find.text('Текущий шаг'),
        state == 'unknown' ? findsNothing : findsOneWidget,
      );
      expect(find.text('Запустить'), findsNothing);
    }
  });

  testWidgets(
    'hero icons carry actual informational running and warning tones',
    (tester) async {
      _frame(tester);
      for (final entry in <String, Widget>{
        'Проверка готовности к установке': _plan(preflight: true),
        'Ход задания': _job('running'),
        'Остановка задания': _job('cancel-requested'),
      }.entries) {
        await tester.pumpWidget(_host(entry.value));
        final hero = find.ancestor(
          of: find.text(entry.key),
          matching: find.byType(DeckPanel),
        );
        final icon = tester.widget<DeckIcon>(
          find.descendant(of: hero, matching: find.byType(DeckIcon)).first,
        );
        final role = entry.key == 'Ход задания'
            ? 'running'
            : entry.key == 'Остановка задания'
            ? 'warning'
            : 'accent';
        expect(
          icon.name,
          entry.key == 'Ход задания'
              ? 'clock'
              : entry.key == 'Остановка задания'
              ? 'warning'
              : 'info',
        );
        expect(icon.color, deckColors(tester.element(hero))[role]);
      }
    },
  );

  testWidgets('profile detail presents facts comparison and exact values', (
    tester,
  ) async {
    _frame(tester);
    await tester.pumpWidget(
      _host(
        AutomationProfileDetailSection(
          profile: DesignAutomationFixtures.profile(),
          revision: DesignAutomationFixtures.revision(),
          comparison: DesignAutomationFixtures.comparison(),
          hasServer: true,
          actions: _available,
          onSelectVersion: _noop,
          onValidate: _noop,
          onCompare: _noop,
          onEdit: _noop,
          onCreatePlan: _noop,
          onDelegate: _noop,
          onArchive: _noop,
        ),
      ),
    );
    expect(find.byType(AutomationFacts), findsOneWidget);
    expect(find.byType(AutomationRecordTable), findsOneWidget);
    expect(find.text('Было'), findsOneWidget);
    expect(find.text('Стало'), findsOneWidget);
    expect(find.byType(AutomationExactValue), findsNWidgets(2));
    final table = tester.getRect(find.byType(AutomationRecordTable));
    expect(
      table.top,
      greaterThan(tester.getRect(find.byType(AutomationFacts)).bottom),
    );
    expect(
      tester.getRect(find.text('Точные значения')).top,
      greaterThan(table.bottom),
    );
    final exact = tester.widgetList<AutomationExactValue>(
      find.byType(AutomationExactValue),
    );
    expect(exact.last.value, DesignAutomationFixtures.revision()['digest']);
    expect(exact.first.value, 'Не предоставлено');
  });

  testWidgets(
    'MCP configuration is exclusive and Close returns to grant list',
    (tester) async {
      _frame(tester);
      var copied = 0, closed = 0;
      await tester.pumpWidget(
        _host(
          AutomationGrantsSection(
            showHeaderActions: false,
            grants: [
              AutomationGrantPresentation(
                value: DesignAutomationFixtures.grant(),
                current: true,
              ),
            ],
            loaded: true,
            actions: _available,
            serverProfiles: [
              DesignServerFixtures.profile(connectionRevision: '2'),
            ],
            launchConfiguration: DesignAutomationFixtures.launchConfiguration(),
            onRefresh: _noop,
            onCreate: _noop,
            onConfigure: (_) {},
            onEdit: (_) {},
            onRevoke: (_) {},
            onCopyConfiguration: () => copied++,
            onConfigurationChanged: (configured) {
              if (!configured) closed++;
            },
          ),
        ),
      );
      expect(find.byType(AutomationMcpConfigurationSection), findsOneWidget);
      expect(find.byType(AutomationLoadedTable), findsNothing);
      expect(find.text('Область просмотра'), findsNothing);
      expect(find.text('Сведения'), findsOneWidget);
      expect(find.text('Точные значения'), findsOneWidget);
      await tester.ensureVisible(find.text('Скопировать конфигурацию'));
      await tester.tap(find.text('Скопировать конфигурацию'));
      await tester.pumpAndSettle();
      expect(copied, 1);
      await tester.ensureVisible(find.text('Закрыть'));
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
      expect(closed, 1);
      expect(find.byType(AutomationLoadedTable), findsOneWidget);
      expect(find.text('Истёкший grant'), findsOneWidget);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets('phone cards use title then labelled remaining fields $scale', (
      tester,
    ) async {
      _frame(tester, width: 390);
      await tester.pumpWidget(
        _host(
          const AutomationRecordTable(
            columns: ['Клиент', 'Права', 'Цели', 'Срок'],
            rows: [
              [
                Text('Actual client'),
                Text('Read'),
                Text('Actual server'),
                Text('Finite'),
              ],
            ],
          ),
          scale: scale,
        ),
      );
      expect(find.text('Клиент'), findsNothing);
      final rights = tester.getRect(find.text('Права'));
      final targets = tester.getRect(find.text('Цели'));
      expect(
        rights.top,
        greaterThan(tester.getRect(find.text('Actual client')).bottom),
      );
      expect(targets.top, closeTo(rights.top, 1));
      expect(targets.left, greaterThan(rights.left));
      final titleStyle = DefaultTextStyle.of(
        tester.element(find.text('Actual client')),
      ).style;
      expect(titleStyle.fontSize, 15);
      expect(titleStyle.fontWeight, BrandTypography.semiboldWeight);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'asPage structured grant retains schema and opaque disabled fields',
    (tester) async {
      _frame(tester);
      final input = TextEditingController(
        text: jsonEncode({
          'label': 'Actual client',
          'scopes': ['author'],
          'serverIds': <String>[],
          'lifetimeSeconds': 28800,
        }),
      );
      var effects = 0;
      await tester.pumpWidget(
        _host(
          AutomationJsonEditorDialog(
            asPage: true,
            title: 'Выдать доступ',
            input: input,
            saving: true,
            preview: const {
              'scopes': ['author'],
              'serverIds': <String>[],
            },
            onClose: _noop,
            onContinue: () => effects++,
          ),
          page: true,
        ),
      );
      expect(find.byType(Dialog), findsNothing);
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(fields, isNotEmpty);
      for (final field in fields) {
        if (field.readOnly) {
          expect(field.onChanged, isNull);
          expect(field.onSubmitted, isNull);
        } else {
          expect(field.enabled, isFalse);
        }
        expect(field.style?.color?.a, 1);
      }
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Продолжить'),
            )
            .onPressed,
        isNull,
      );
      expect(effects, 0);
      expect((jsonDecode(input.text) as Map).keys.toSet(), {
        'label',
        'scopes',
        'serverIds',
        'lifetimeSeconds',
      });
      await tester.pumpWidget(const SizedBox());
      input.dispose();
    },
  );
}
