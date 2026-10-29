import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/automation/automation_panel.dart';
import 'package:serverdeck/software/software_panel.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck_protocol/models.dart';

import '../support/design_automation_fixtures.dart';
import '../support/design_server_fixtures.dart';

const enabled = AutomationActionAvailability(
  read: true,
  mutate: true,
  select: true,
);
const disabled = AutomationActionAvailability(
  read: false,
  mutate: false,
  select: false,
);
void noop() {}

Widget host(
  Widget child, {
  bool dark = false,
  double scale = 1,
  bool dialog = false,
}) => MaterialApp(
  theme: Motion.theme(dark ? BrandTheme.dark : BrandTheme.light, true),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(disableAnimations: true, textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: dialog
        ? child
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
  ),
);

AutomationPlanSection plan({
  bool expired = false,
  String? invalidReason,
  VoidCallback onApply = noop,
  VoidCallback onApprove = noop,
}) => AutomationPlanSection(
  plan: DesignAutomationFixtures.plan(expired: expired),
  serverProfiles: [DesignServerFixtures.profile(connectionRevision: '2')],
  automationProfile: DesignAutomationFixtures.profile(),
  runnable: true,
  expired: expired,
  invalidReason: invalidReason,
  actions: enabled,
  onApprove: onApprove,
  onDeny: noop,
  onApply: onApply,
  onRefresh: noop,
);

AutomationJobsSection jobs({
  String state = 'running',
  int dropped = 0,
  bool canCancel = true,
  VoidCallback onCancel = noop,
  VoidCallback onReconcile = noop,
}) => AutomationJobsSection(
  serverId: DesignAutomationFixtures.serverId,
  jobs: [
    {'job': DesignAutomationFixtures.job(state: state)},
  ],
  job: DesignAutomationFixtures.job(state: state),
  events: DesignAutomationFixtures.events(dropped: dropped),
  loaded: true,
  hasMore: false,
  droppedEvents: dropped,
  canCancel: canCancel,
  canReconcile: state == 'unknown',
  actions: enabled,
  onRefresh: noop,
  onRefreshAuthorities: noop,
  onSelect: (_) {},
  onMore: noop,
  onShowPlan: noop,
  onCancel: onCancel,
  onReconcile: onReconcile,
);

AutomationGrantsSection grants({
  bool current = true,
  bool revoked = false,
  bool configuration = false,
  VoidCallback onRevoke = noop,
}) => AutomationGrantsSection(
  serverProfiles: [DesignServerFixtures.profile(connectionRevision: '2')],
  grants: [
    AutomationGrantPresentation(
      value: DesignAutomationFixtures.grant(revoked: revoked),
      current: current,
    ),
  ],
  loaded: true,
  actions: enabled,
  launchConfiguration: configuration
      ? DesignAutomationFixtures.launchConfiguration()
      : null,
  onRefresh: noop,
  onCreate: noop,
  onConfigure: (_) {},
  onEdit: (_) {},
  onRevoke: (_) => onRevoke(),
  onCopyConfiguration: noop,
);

Finder button(String text) => find.ancestor(
  of: find.text(text),
  matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
);

Future<void> tapVisible(WidgetTester tester, String text) async {
  final finder = button(text);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    '16 recipe loading stays explicit and pending mutations are disabled',
    (tester) async {
      var connected = 0, created = 0;
      Widget actions(String section) => Wrap(
        children: automationPageActions(
          section: section,
          availability: disabled,
          onRefresh: noop,
          onCreate: () => created++,
          onLoadRecipes: () => connected++,
        ),
      );
      await tester.pumpWidget(host(actions('catalog')));
      await tester.pumpWidget(host(actions('catalog'), dark: true, scale: 2));
      expect(connected + created, 0);
      expect(
        tester
            .widget<OutlinedButton>(button('Подключиться и открыть рецепты'))
            .onPressed,
        isNull,
      );
      expect(
        button('Новый профиль'),
        findsNothing,
        reason: 'Catalog header only exposes catalog actions',
      );
      await tester.pumpWidget(host(actions('profiles'), dark: true, scale: 2));
      expect(
        tester.widget<OutlinedButton>(button('Новый профиль')).onPressed,
        isNull,
      );
      expect(connected + created, 0);
      await tester.pumpWidget(
        host(
          AutomationRecipesSection(
            catalog: DesignAutomationFixtures.catalog(enabled: false),
            canMutate: true,
            onCreatePlan: (_) => created++,
          ),
        ),
      );
      expect(button('План установки PostgreSQL 16'), findsNothing);
      expect(find.text('Установка недоступна'), findsOneWidget);
      expect(created, 0);
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      '16-19 exact recipes and plain plan contract ${dark ? 'dark' : 'light'}',
      (tester) async {
        String? digest;
        final recipes = GlobalKey<AutomationRecipesSectionState>();
        await tester.pumpWidget(
          host(
            AutomationRecipesSection(
              key: recipes,
              catalog: DesignAutomationFixtures.catalog(),
              canMutate: true,
              onCreatePlan: (value) => digest = value,
            ),
            dark: dark,
          ),
        );
        expect(digest, isNull);
        recipes.currentState!.selectFirst();
        await tester.pumpAndSettle();
        expect(digest, isNull);
        expect(find.textContaining('Только чистая установка;'), findsOneWidget);
        await tester.ensureVisible(
          find.text('Лицензии, начальные настройки и точные условия'),
        );
        await tester.tap(
          find.text('Лицензии, начальные настройки и точные условия'),
        );
        await tester.pumpAndSettle();
        final recipe = tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .singleWhere(
              (widget) => widget.data?.contains('"licenseNotices"') == true,
            );
        expect(recipe.data, contains('PostgreSQL License'));
        expect(recipe.data, contains('"max_connections": 100'));
        await tapVisible(tester, 'Создать план');
        expect(digest, DesignAutomationFixtures.recipe()['digest']);

        var applied = 0, approved = 0;
        await tester.pumpWidget(
          host(
            plan(onApply: () => applied++, onApprove: () => approved++),
            dark: dark,
          ),
        );
        expect(find.text('Цель'), findsOneWidget);
        expect(
          find.text('Синтетический сервер · 192.0.2.44:2222'),
          findsOneWidget,
        );
        expect(find.text('Привет'), findsNWidgets(2));
        expect(
          find.text('Изменить конфигурацию: Приветствие сервера'),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(AutomationPlanSteps),
            matching: find.text('Проверить содержимое файла'),
          ),
          findsOneWidget,
        );
        expect(
          find.text('${DesignAutomationFixtures.expiresAt} (UTC)'),
          findsOneWidget,
        );
        expect(applied + approved, 0);
        await tapVisible(tester, 'Подтвердить план');
        expect(approved, 1);
        expect(applied, 0);
        await tapVisible(tester, 'Запустить');
        expect(applied, 1);
      },
    );
  }

  testWidgets(
    '94 expired and invalidated plans expose reason without previous apply',
    (tester) async {
      for (final invalidReason in [
        null,
        'Состояние сервера изменилось. Создайте новый план.',
      ]) {
        await tester.pumpWidget(
          host(
            plan(expired: invalidReason == null, invalidReason: invalidReason),
          ),
        );
        expect(button('Запустить'), findsNothing);
        expect(button('Подтвердить план'), findsNothing);
        expect(button('Создать новый план'), findsOneWidget);
        expect(
          tester
              .widgetList<AutomationFacts>(find.byType(AutomationFacts))
              .first
              .values['Причина'],
          invalidReason ?? 'Срок плана истёк',
        );
      }
    },
  );

  testWidgets(
    '19 decision dialog displays exact effects and needs explicit consent',
    (tester) async {
      var confirmed = 0;
      await tester.pumpWidget(
        host(
          AutomationPlanDecisionDialog(
            now: DesignAutomationFixtures.presentationNow,
            plan: DesignAutomationFixtures.plan(),
            serverProfiles: [
              DesignServerFixtures.profile(connectionRevision: '2'),
            ],
            automationProfile: DesignAutomationFixtures.profile(),
            approve: true,
            onBack: noop,
            onConfirm: () => confirmed++,
          ),
          dialog: true,
        ),
      );
      expect(
        find.text('Синтетический сервер · 192.0.2.44:2222'),
        findsOneWidget,
      );
      expect(
        find.text('Изменить конфигурацию: Приветствие сервера'),
        findsOneWidget,
      );
      expect(confirmed, 0);
      await tapVisible(tester, 'Подтвердить план');
      expect(confirmed, 1);
    },
  );

  testWidgets(
    '27-30 unknown outcome, source drops, reconciliation and safe cancellation are distinct',
    (tester) async {
      var reconciled = 0, cancelled = 0, stoppedWaiting = 0;
      await tester.pumpWidget(
        host(
          jobs(
            state: 'unknown',
            dropped: 7,
            canCancel: false,
            onReconcile: () => reconciled++,
          ),
        ),
      );
      expect(find.text('Исход не подтверждён'), findsWidgets);
      expect(find.text('Возможны неподтверждённые изменения'), findsOneWidget);
      expect(button('Показать события'), findsOneWidget);
      await tapVisible(tester, 'Показать события');
      expect(
        find.text('Получено событий: 3. Пропущено в источнике: 7'),
        findsOneWidget,
      );
      expect(button('Остановить после текущего шага'), findsNothing);
      await tapVisible(tester, 'Уточнить результат');
      expect(reconciled, 1);
      await tester.pumpWidget(host(jobs(onCancel: () => cancelled++)));
      await tapVisible(tester, 'Остановить после текущего шага');
      expect(cancelled, 1);
      await tester.pumpWidget(
        host(
          AutomationStatusSection(
            busy: true,
            openingRecipes: false,
            canRetry: false,
            onRetry: noop,
            onDismiss: noop,
            onStopWaiting: () => stoppedWaiting++,
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.text(
          'Остановка ожидания ответа не означает остановку задания на сервере.',
        ),
        findsOneWidget,
      );
      await tapVisible(tester, 'Перестать ждать ответ');
      expect(stoppedWaiting, 1);
      expect(cancelled, 1);
    },
  );

  testWidgets(
    '28 postchecks and requested cancellation retain factual outcomes',
    (tester) async {
      await tester.pumpWidget(host(jobs(state: 'succeeded', canCancel: false)));
      expect(find.text('Изменения подтверждены'), findsOneWidget);
      expect(find.text('motd · written: Проверка пройдена'), findsOneWidget);
      await tester.pumpWidget(
        host(jobs(state: 'cancel-requested', canCancel: false)),
      );
      expect(find.text('Состояние: Остановка запрошена'), findsOneWidget);
      expect(find.text('Автоматический откат не обещается'), findsOneWidget);
      expect(button('Обновить состояние'), findsOneWidget);
      expect(button('Остановить после текущего шага'), findsNothing);
    },
  );

  testWidgets(
    '36-38 grants display scopes targets deadline and real command before details',
    (tester) async {
      var revoked = 0;
      await tester.pumpWidget(host(grants(onRevoke: () => revoked++)));
      expect(
        find.text(
          'Чтение состояния · Чтение журналов · Создание и изменение профилей · Создание планов · Запуск заданий',
        ),
        findsWidgets,
      );
      expect(
        find.text('Синтетический сервер · 192.0.2.44:2222'),
        findsOneWidget,
      );
      expect(find.text('2026-10-25T17:00:00.000Z (UTC)'), findsWidgets);
      await tapVisible(tester, 'Отозвать');
      expect(revoked, 1);
      await tester.pumpWidget(host(grants(configuration: true)));
      expect(find.byType(AutomationLoadedTable), findsNothing);
      expect(find.byType(AutomationMcpConfigurationSection), findsOneWidget);
      expect(find.text(r'C:\Synthetic\ServerDeck\mcp.exe'), findsWidgets);
    },
  );

  testWidgets(
    '36 expired and revoked grants do not offer configuration or renewed rights',
    (tester) async {
      for (final revoked in [false, true]) {
        await tester.pumpWidget(
          host(grants(current: false, revoked: revoked), dark: revoked),
        );
        expect(
          tester.widget<OutlinedButton>(button('Конфигурация MCP')).onPressed,
          isNull,
        );
        expect(find.text(revoked ? 'Отозван' : 'Истёк'), findsOneWidget);
        if (revoked) {
          expect(
            tester.widget<OutlinedButton>(button('Отозвать')).onPressed,
            isNull,
          );
          expect(
            tester.widget<OutlinedButton>(button('Изменить права')).onPressed,
            isNull,
          );
        }
      }
    },
  );

  testWidgets(
    '32-34 author-only revision retains compare and omits server actions',
    (tester) async {
      await tester.pumpWidget(
        host(
          AutomationProfileDetailSection(
            profile: DesignAutomationFixtures.profile(),
            revision: DesignAutomationFixtures.revision(),
            hasServer: false,
            comparison: DesignAutomationFixtures.comparison(),
            validation: DesignAutomationFixtures.validation(),
            actions: enabled,
            onSelectVersion: noop,
            onValidate: noop,
            onCompare: noop,
            onEdit: noop,
            onCreatePlan: noop,
            onDelegate: noop,
            onArchive: noop,
          ),
        ),
      );
      expect(button('Создать план'), findsNothing);
      expect(button('Делегировать версию'), findsNothing);
      expect(button('Изменить профиль'), findsOneWidget);
      expect(find.text('Сравнение версий 1 и 2'), findsOneWidget);
      expect(find.text('/parameters/greeting/default'), findsWidgets);
      expect(find.text('Было'), findsOneWidget);
      expect(find.text('Стало'), findsOneWidget);
      expect(find.text('Здравствуйте'), findsOneWidget);
      expect(find.text('Привет'), findsOneWidget);
      expect(find.text('Содержимое профиля проверено'), findsOneWidget);
      expect(
        find.textContaining('Для новой версии потребуется отдельное согласие'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '37 JSON editor shows the actual grant preview outside its source field',
    (tester) async {
      final input = TextEditingController(text: '{draft}');
      await tester.pumpWidget(
        host(
          AutomationJsonEditorDialog(
            title: 'Выдать ИИ доступ через MCP',
            input: input,
            preview: const {
              'scopes': ['author'],
              'serverIds': <String>[],
              'lifetimeSeconds': 3600,
            },
            error: 'Проверьте JSON и типы значений',
            onClose: noop,
            onContinue: noop,
          ),
          dialog: true,
        ),
      );
      expect(find.text('Создание и изменение профилей'), findsOneWidget);
      expect(find.text('Без доступа к серверам'), findsOneWidget);
      expect(find.text('3600 секунд'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration!.errorText,
        'Проверьте JSON и типы значений',
      );
      await tester.pumpWidget(const SizedBox());
      input.dispose();
    },
  );

  testWidgets(
    '33 authoring keeps field controllers and draft across theme and narrow 200 percent layout',
    (tester) async {
      final name = TextEditingController(text: 'Черновик');
      final description = TextEditingController(text: 'Описание');
      final body = TextEditingController(text: '{changed draft}');
      var saved = 0;
      Widget editor() => AutomationProfileEditorDialog(
        name: name,
        description: description,
        body: body,
        validating: false,
        canValidate: true,
        onBodyChanged: (_) {},
        onClose: noop,
        onSave: () => saved++,
        onValidate: noop,
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(host(editor(), dialog: true));
      await tester.pumpWidget(
        host(editor(), dialog: true, dark: true, scale: 2),
      );
      expect(tester.takeException(), isNull);
      expect(body.text, '{changed draft}');
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller,
        same(body),
      );
      expect(saved, 0);
      await tapVisible(tester, 'Сохранить версию');
      expect(saved, 1);
      await tester.pumpWidget(const SizedBox());
      name.dispose();
      description.dispose();
      body.dispose();
    },
  );

  testWidgets(
    '16 server selector wraps the full target at 200 percent and only invokes local selection',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final profile = ProfileView(
        id: DesignAutomationFixtures.serverId,
        revision: '1',
        name: 'Длинное имя синтетического сервера для установки',
        address: 'very-long-synthetic-server-name.internal.example',
        port: 22,
        sshUser: 'synthetic',
        tags: const [],
        credentialRevision: '1',
        connectionRevision: '1',
        trustRevision: '1',
        createdAt: DesignAutomationFixtures.createdAt,
        updatedAt: DesignAutomationFixtures.createdAt,
        credentialKind: CredentialKind.password,
        credentialConfigured: false,
      );
      var chosen = 0;
      await tester.pumpWidget(
        host(
          SoftwareServerSelector(
            profiles: [profile],
            selectedId: profile.id,
            onChoose: () => chosen++,
          ),
          scale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.text('${profile.name} · ${profile.address}:${profile.port}'),
        findsOneWidget,
      );
      expect(chosen, 0);
      await tapVisible(tester, 'Изменить сервер');
      expect(chosen, 1);
    },
  );

  testWidgets(
    '39 delegation exposes exact scope predicates and expiry before technical details',
    (tester) async {
      await tester.pumpWidget(
        host(
          AutomationAuthoritiesSection(
            now: DesignAutomationFixtures.presentationNow,
            approvals: const [],
            delegations: [DesignAutomationFixtures.delegation()],
            loaded: true,
            hasMoreApprovals: false,
            hasMoreDelegations: false,
            actions: enabled,
            onOpenPlan: (_) {},
            onRevokeDelegation: (_) {},
            onMoreApprovals: noop,
            onMoreDelegations: noop,
          ),
        ),
      );
      await tester.tap(find.text('Делегированные версии'));
      await tester.pumpAndSettle();
      expect(find.text('Делегирование версии'), findsOneWidget);
      expect(find.text(DesignAutomationFixtures.serverId), findsOneWidget);
      expect(find.text('2026-10-25T10:00:00.000Z (UTC)'), findsOneWidget);
      expect(find.text('Одно из значений: Привет'), findsOneWidget);
      expect(
        find.text('${DesignAutomationFixtures.profileId} · версия 2'),
        findsOneWidget,
      );
      expect(button('Отозвать делегирование'), findsOneWidget);
    },
  );
}
