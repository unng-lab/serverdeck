import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_forms.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck_protocol/automation/models.dart';

import '../support/design_automation_fixtures.dart';
import '../support/design_server_fixtures.dart';

const available = AutomationActionAvailability(
  read: true,
  mutate: true,
  select: true,
);
void noop() {}
Widget host(Widget child, {double scale = 1}) => MaterialApp(
  theme: BrandTheme.dark,
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    ),
  ),
);
Future<void> tap(WidgetTester tester, String text) async {
  final target = find.text(text).last;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  Map<String, Object?> blocked({String? stepId}) => {
    ...DesignAutomationFixtures.plan(blocked: true),
    'reasons': [
      {'code': 'QUALIFICATION_REQUIRED', 'field': 'packages', 'stepId': stepId},
    ],
  };
  test(
    '93 only projects blocked records in the matching live display context',
    () {
      final original = blocked();
      final display = BlockedPlanDisplay.tryCreate(
        original,
        targetMatches: true,
        expired: false,
        invalidated: false,
      )!;
      expect(display.reasons.single['code'], 'QUALIFICATION_REQUIRED');
      expect(display.sourceSteps, isEmpty);
      original['reasons'] = [];
      expect(display.reasons, hasLength(1));
      expect(
        () => display.reasons.single['field'] = 'runtime',
        throwsUnsupportedError,
      );
      for (final record in [
        DesignAutomationFixtures.plan(),
        <String, Object?>{'status': 'blocked'},
        {
          ...blocked(),
          'effects': [
            {'kind': 'anything'},
          ],
        },
      ]) {
        expect(
          BlockedPlanDisplay.tryCreate(
            record,
            targetMatches: true,
            expired: false,
            invalidated: false,
          ),
          isNull,
        );
      }
      expect(
        BlockedPlanDisplay.tryCreate(
          blocked(),
          targetMatches: false,
          expired: false,
          invalidated: false,
        ),
        isNull,
      );
      expect(
        BlockedPlanDisplay.tryCreate(
          blocked(),
          targetMatches: true,
          expired: true,
          invalidated: false,
        ),
        isNull,
      );
      expect(
        BlockedPlanDisplay.tryCreate(
          blocked(),
          targetMatches: true,
          expired: false,
          invalidated: true,
        ),
        isNull,
      );
    },
  );
  testWidgets(
    '93 reasons and original step are readonly and effect identity stays unknown',
    (tester) async {
      var effects = 0, edited = 0, closed = 0;
      final record = blocked(stepId: 'motd');
      await tester.pumpWidget(
        host(
          AutomationPlanSection(
            plan: record,
            runnable: false,
            expired: false,
            actions: available,
            serverProfiles: [
              DesignServerFixtures.profile(connectionRevision: '2'),
            ],
            automationProfile: DesignAutomationFixtures.profile(),
            sourceRevision: DesignAutomationFixtures.revision(),
            currentServerId: DesignAutomationFixtures.serverId,
            onApprove: () => effects++,
            onDeny: () => effects++,
            onApply: () => effects++,
            onRefresh: () => effects++,
            onEditSource: () => edited++,
            onClose: () => closed++,
          ),
        ),
      );
      expect(find.text('План заблокирован'), findsWidgets);
      expect(find.textContaining('NetBird'), findsNothing);
      final forbidden = find.widgetWithText(
        FilledButton,
        'Открыть запрещённый эффект',
      );
      expect(tester.widget<FilledButton>(forbidden).onPressed, isNull);
      await tap(tester, 'Просмотреть причины');
      expect(find.text('QUALIFICATION_REQUIRED'), findsOneWidget);
      expect(find.text('packages'), findsOneWidget);
      await tap(tester, 'Открыть исходный шаг');
      expect(
        find.text(
          'Исходный запрос; это не доказанный и не разрешённый эффект.',
        ),
        findsOneWidget,
      );
      expect(effects + edited + closed, 0);
      await tap(tester, 'Изменить исходный запрос');
      expect(edited, 1);
      expect(effects, 0);
      await tap(tester, 'Закрыть план');
      expect(closed, 1);
      expect(effects, 0);
    },
  );
  testWidgets(
    '93 unavailable exact source cannot be substituted by another version',
    (tester) async {
      await tester.pumpWidget(
        host(
          AutomationPlanSection(
            plan: blocked(),
            runnable: false,
            expired: false,
            actions: available,
            serverProfiles: [
              DesignServerFixtures.profile(connectionRevision: '2'),
            ],
            automationProfile: DesignAutomationFixtures.profile(),
            sourceRevision: {
              ...DesignAutomationFixtures.revision(),
              'revision': 3,
            },
            onApprove: noop,
            onDeny: noop,
            onApply: noop,
            onRefresh: noop,
            onEditSource: noop,
          ),
        ),
      );
      final edit = find.widgetWithText(
        OutlinedButton,
        'Изменить исходный запрос',
      );
      expect(tester.widget<OutlinedButton>(edit).onPressed, isNull);
      expect(find.textContaining('нет точной исходной версии'), findsOneWidget);
    },
  );
  testWidgets('recipe selection and readiness cannot create a durable plan', (
    tester,
  ) async {
    var plans = 0;
    final recipes = GlobalKey<AutomationRecipesSectionState>();
    await tester.pumpWidget(
      host(
        AutomationRecipesSection(
          key: recipes,
          catalog: DesignAutomationFixtures.catalog(),
          canMutate: true,
          onCreatePlan: (_) => plans++,
        ),
      ),
    );
    recipes.currentState!.selectFirst();
    await tester.pumpAndSettle();
    final readiness = find.widgetWithText(FilledButton, 'Проверить готовность');
    expect(tester.widget<FilledButton>(readiness).onPressed, isNull);
    expect(plans, 0);
    await tap(tester, 'Назад');
    expect(plans, 0);
    recipes.currentState!.selectFirst();
    await tester.pumpAndSettle();
    await tap(tester, 'Создать план');
    expect(plans, 1);
  });
  testWidgets(
    '18 views the obtained preflight without starting a check or write',
    (tester) async {
      var callbacks = 0;
      await tester.pumpWidget(
        host(
          AutomationPlanSection(
            plan: DesignAutomationFixtures.plan(),
            showPreflight: true,
            runnable: true,
            expired: false,
            actions: available,
            serverProfiles: [
              DesignServerFixtures.profile(connectionRevision: '2'),
            ],
            automationProfile: DesignAutomationFixtures.profile(),
            onApprove: () => callbacks++,
            onDeny: () => callbacks++,
            onApply: () => callbacks++,
            onRefresh: () => callbacks++,
          ),
        ),
      );
      expect(find.text('Проверка готовности к установке'), findsOneWidget);
      final refresh = find.widgetWithText(OutlinedButton, 'Обновить проверку');
      expect(tester.widget<OutlinedButton>(refresh).onPressed, isNull);
      expect(find.text('Запустить'), findsNothing);
      await tap(tester, 'Просмотреть план');
      expect(callbacks, 0);
      expect(find.text('Подтвердить план'), findsOneWidget);
    },
  );
  testWidgets(
    'profile parameter rename preserves the closed schema and exact references',
    (tester) async {
      final body = TextEditingController(
        text: jsonEncode(DesignAutomationFixtures.body()),
      );
      var changed = 0;
      await tester.pumpWidget(
        host(
          AutomationProfileFields(
            body: body,
            enabled: true,
            onChanged: (_) => changed++,
            identityFields: const [],
          ),
        ),
      );
      await tester.tap(find.widgetWithText(TextButton, 'Параметры'));
      await tester.pumpAndSettle();
      await tap(tester, 'Изменить имя параметра');
      final identifier = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.key == const ValueKey('automation-field-Идентификатор'),
      );
      await tester.enterText(identifier, 'message');
      await tap(tester, 'Переименовать');
      final parsed = AutomationBody.fromJson(
        (jsonDecode(body.text) as Map).cast<String, Object?>(),
      );
      expect((parsed.toJson()['parameters'] as Map).keys, ['message']);
      expect(((parsed.toJson()['steps'] as List).single as Map)['values'], {
        'text': {'param': 'message'},
      });
      expect(changed, 1);
      await tester.pumpWidget(const SizedBox());
      body.dispose();
    },
  );
  testWidgets('structured grant edits only the retained closed draft', (
    tester,
  ) async {
    final input = TextEditingController(
      text: jsonEncode({
        'label': 'Клиент',
        'scopes': ['author'],
        'serverIds': [],
        'lifetimeSeconds': 28800,
      }),
    );
    var changed = 0;
    await tester.pumpWidget(
      host(
        AutomationStructuredDraft(
          input: input,
          enabled: true,
          onChanged: (_) => changed++,
          serverProfiles: [
            DesignServerFixtures.profile(connectionRevision: '2'),
          ],
        ),
      ),
    );
    await tap(tester, 'Права');
    final read = find.widgetWithText(CheckboxListTile, 'Чтение состояния');
    await tester.ensureVisible(read);
    await tester.tap(read);
    await tester.pumpAndSettle();
    await tap(tester, 'Выбрать');
    final next = jsonDecode(input.text) as Map;
    expect((next['scopes'] as List), containsAll(['author', 'read']));
    expect(next.keys.toSet(), {
      'label',
      'scopes',
      'serverIds',
      'lifetimeSeconds',
    });
    expect(changed, 1);
    await tester.pumpWidget(const SizedBox());
    input.dispose();
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'T173 jobs retain an absent selected state on refresh at $scale',
      (tester) async {
        tester.view.physicalSize = scale == 1
            ? const Size(1100, 760)
            : const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var jobs = <Map<String, Object?>>[
          {'job': DesignAutomationFixtures.job()},
        ];
        var refreshes = 0, otherCalls = 0;
        late StateSetter update;
        await tester.pumpWidget(
          host(
            StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return AutomationJobsSection(
                  jobs: jobs,
                  events: const [],
                  loaded: true,
                  hasMore: false,
                  canCancel: false,
                  canReconcile: false,
                  droppedEvents: 0,
                  actions: available,
                  serverId: DesignAutomationFixtures.serverId,
                  onRefresh: () {
                    refreshes++;
                    setState(
                      () => jobs = [
                        {
                          'job': DesignAutomationFixtures.job(
                            state: 'succeeded',
                          ),
                        },
                      ],
                    );
                  },
                  onRefreshAuthorities: () => otherCalls++,
                  onSelect: (_) => otherCalls++,
                  onMore: () => otherCalls++,
                  onShowPlan: () => otherCalls++,
                  onCancel: () => otherCalls++,
                  onReconcile: () => otherCalls++,
                );
              },
            ),
            scale: scale,
          ),
        );
        await tester.pumpAndSettle();
        await tap(tester, 'Фильтры');
        final dropdown = find.byType(DropdownButtonFormField<String>);
        await tester.ensureVisible(dropdown);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tap(tester, 'Выполняется');
        expect(tester.state<FormFieldState<String>>(dropdown).value, 'running');
        await tap(tester, 'Обновить задания');
        expect(tester.takeException(), isNull);
        expect(tester.state<FormFieldState<String>>(dropdown).value, 'running');
        expect(find.byType(AutomationLoadedTable), findsNothing);
        expect(
          find.text('Обновите задания или измените локальный фильтр.'),
          findsOneWidget,
        );
        expect(refreshes, 1);
        expect(otherCalls, 0);
        update(
          () => jobs = [
            {'job': DesignAutomationFixtures.job()},
            {'job': DesignAutomationFixtures.job(state: 'succeeded')},
          ],
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final options = tester
            .widget<DropdownButton<String>>(
              find.descendant(
                of: dropdown,
                matching: find.byType(DropdownButton<String>),
              ),
            )
            .items!;
        expect(
          options.where((option) => option.value == 'running'),
          hasLength(1),
        );
        expect(
          tester
              .widget<AutomationLoadedTable>(find.byType(AutomationLoadedTable))
              .rows,
          hasLength(1),
        );
        await tap(tester, 'Обновить задания');
        await tester.ensureVisible(dropdown);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tap(tester, 'Все состояния');
        expect(tester.state<FormFieldState<String>>(dropdown).value, '');
        expect(
          tester
              .widget<AutomationLoadedTable>(find.byType(AutomationLoadedTable))
              .rows,
          hasLength(1),
        );
        expect(find.text('Задание выполнено'), findsWidgets);
        expect(refreshes, 2);
        expect(otherCalls, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('loaded tables filter and page locally at phone 200 percent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selected = -1;
    await tester.pumpWidget(
      host(
        AutomationLoadedTable(
          columns: const ['Задание', 'Состояние'],
          rows: [
            for (var i = 0; i < 24; i++)
              [Text('job-$i'), Text(i.isEven ? 'Выполняется' : 'Завершено')],
          ],
          onSelect: (i) => selected = i,
        ),
        scale: 2,
      ),
    );
    final search = find.byType(TextField).first;
    await tester.enterText(search, 'job-23');
    await tester.pumpAndSettle();
    expect(find.text('job-23', findRichText: false).last, findsOneWidget);
    expect(find.text('job-22'), findsNothing);
    await tap(tester, 'job-23');
    expect(selected, 23);
    expect(tester.takeException(), isNull);
  });
}
