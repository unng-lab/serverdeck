import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/automation/automation_presentation.dart';
import 'package:serverdeck/software/software_panel.dart';
import 'package:serverdeck/shell/error_view.dart';
import 'package:serverdeck/ui/deck_components.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/automation/job_records.dart';
import 'package:serverdeck_protocol/automation/profile_records.dart';
import 'package:serverdeck_protocol/models.dart' show ErrorCode;

import 'design_automation_fixtures.dart';
import 'design_host.dart' show loadDesignFonts;
import 'design_server_fixtures.dart';
import 'design_state_capture.dart';
import 'design_state_matrix.dart';
import 'design_scenario_harness.dart';

class _Variant {
  const _Variant(this.size, this.scale, this.dark);
  final Size size;
  final double scale;
  final bool dark;
  String get suffix =>
      '${dark ? 'dark' : 'light'}-${size.width.toInt()}-${(scale * 100).toInt()}';
}

Future<void> _mount(WidgetTester tester, Widget child, _Variant variant) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = variant.size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    RepaintBoundary(
      key: designStateCaptureBoundaryKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: Motion.theme(
          variant.dark ? BrandTheme.dark : BrandTheme.light,
          true,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(variant.scale),
          ),
          child: child!,
        ),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _button(String label) => find
    .ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    )
    .first;

Finder _draftField(TextEditingController controller) => find.byWidgetPredicate(
  (widget) => widget is TextField && identical(widget.controller, controller),
);

Future<Finder> _showDraftField(
  WidgetTester tester,
  TextEditingController controller, {
  bool profile = false,
}) async {
  final field = _draftField(controller);
  if (field.evaluate().isEmpty) {
    final title = profile
        ? 'Шаги и параметры профиля (JSON)'
        : 'JSON · дополнительные сведения';
    if (profile && find.text(title).evaluate().isEmpty) {
      await _click(tester, 'Шаги');
    }
    final details = find.text(title);
    await tester.ensureVisible(details);
    await tester.pumpAndSettle();
    await tester.tap(details);
    await tester.pumpAndSettle();
  }
  expect(field, findsOneWidget);
  return field;
}

Finder _comparisonValue(String value) => find.descendant(
  of: find.byType(AutomationRecordTable),
  matching: find.text(value),
);

const _enabled = AutomationActionAvailability(
  read: true,
  mutate: true,
  select: true,
);
const _disabled = AutomationActionAvailability(
  read: false,
  mutate: false,
  select: false,
);

class _Context {
  _Context(this.scenario)
    : body = TextEditingController(
        text: jsonEncode(DesignAutomationFixtures.body()),
      ),
      input = TextEditingController(
        text: jsonEncode(_input(scenario.originId)),
      );
  final DesignStateCase scenario;
  final counters = DesignCallbackCounters();
  final name = TextEditingController(text: 'Retained automation draft');
  final description = TextEditingController(text: 'Retained description');
  final TextEditingController body, input;
  Map<String, Object?>? sent;
  bool current = true;
  late final reviewCurrent = automationReviewGuard(() => current);
  String? inputError;
  final serverProfiles = [
    DesignServerFixtures.profile(connectionRevision: '2'),
  ];
  final operation = AutomationUiOperation();
  final localModels = <DesignScenarioHarness>[];
  String get id => scenario.originId;
  DesignStateCategory get category => scenario.category;
  bool get busy => category == DesignStateCategory.loading;
  bool get empty => category == DesignStateCategory.successfulEmpty;
  bool get postModal => const {
    DesignStateCategory.loading,
    DesignStateCategory.denied,
    DesignStateCategory.unsupported,
    DesignStateCategory.unknown,
  }.contains(category);
  bool get retainedDurable =>
      category == DesignStateCategory.unknown &&
          !const {
            '27-job-list',
            '28-job-detail',
            '29-job-unknown',
            '30-job-cancel',
          }.contains(id) ||
      const {
            DesignStateCategory.denied,
            DesignStateCategory.unsupported,
          }.contains(category) &&
          const {
            '19-plan-approval',
            '33-profile-authoring',
            '35-plan-parameters',
            '37-ai-grant-form',
          }.contains(id) ||
      category == DesignStateCategory.validation &&
          const {
            '34-profile-revisions',
            '36-ai-grants',
            '39-delegations',
          }.contains(id);
  AutomationActionAvailability get actions => busy
      ? _disabled
      : retainedDurable
      ? const AutomationActionAvailability(
          read: true,
          mutate: false,
          select: true,
        )
      : _enabled;
  AutomationUiPhase get phase => switch (id) {
    '16-install-catalog' =>
      category == DesignStateCategory.unknown
          ? AutomationUiPhase.recipePlan
          : AutomationUiPhase.catalog,
    '17-recipe-detail' => AutomationUiPhase.recipePlan,
    '18-install-preflight' =>
      const {
            DesignStateCategory.denied,
            DesignStateCategory.unsupported,
            DesignStateCategory.validation,
          }.contains(category)
          ? AutomationUiPhase.plan
          : AutomationUiPhase.recipePlan,
    '19-plan-approval' => AutomationUiPhase.approve,
    '27-job-list' => AutomationUiPhase.jobs,
    '28-job-detail' => AutomationUiPhase.job,
    '29-job-unknown' => AutomationUiPhase.reconcile,
    '30-job-cancel' => AutomationUiPhase.cancelJob,
    '32-automation-profiles' => AutomationUiPhase.profiles,
    '33-profile-authoring' => AutomationUiPhase.saveProfile,
    '34-profile-revisions' =>
      category == DesignStateCategory.unknown ||
              category == DesignStateCategory.validation
          ? AutomationUiPhase.archive
          : AutomationUiPhase.compare,
    '35-plan-parameters' => AutomationUiPhase.createPlan,
    '36-ai-grants' =>
      category == DesignStateCategory.unknown ||
              category == DesignStateCategory.validation
          ? AutomationUiPhase.revokeGrant
          : AutomationUiPhase.grants,
    '37-ai-grant-form' => AutomationUiPhase.saveGrant,
    '38-mcp-client-config' => AutomationUiPhase.configuration,
    '39-delegations' =>
      category == DesignStateCategory.validation
          ? AutomationUiPhase.revokeDelegation
          : AutomationUiPhase.delegate,
    '94-plan-invalidated' => AutomationUiPhase.plan,
    _ => throw StateError('No T036 phase for $id'),
  };
  VoidCallback callback(String key) => counters.callback(key);

  void submitDraft() {
    if (id == '33-profile-authoring') {
      submitAutomationProfileDraft(
        name: name.text,
        description: description.text,
        source: body.text,
        current: reviewCurrent,
        submit: (capturedName, capturedDescription, value) {
          counters.hit('draftDispatch');
          sent = value;
          return Future<void>.value();
        },
      ).ignore();
      return;
    }
    submitAutomationDraft(
      source: input.text,
      current: (_) => reviewCurrent(),
      targetsAvailable: (value) => automationTargetsAvailable([
        if (id == '35-plan-parameters' || id == '39-delegations')
          DesignAutomationFixtures.serverId,
        if (value['serverIds'] is List)
          ...(value['serverIds'] as List).whereType<String>(),
      ], serverProfiles),
      submit: (value) {
        counters.hit('draftDispatch');
        sent = value;
        return Future<void>.value();
      },
    ).ignore();
  }

  Widget editor() => id == '33-profile-authoring'
      ? AutomationProfileEditorDialog(
          name: name,
          description: description,
          body: body,
          validating: busy,
          canValidate: !busy,
          error: inputError,
          onBodyChanged: (_) => counters.hit('bodyChanged'),
          onSave: submitDraft,
          onValidate: callback('validate'),
          onClose: callback('closeEditor'),
        )
      : AutomationJsonEditorDialog(
          title: switch (id) {
            '35-plan-parameters' => 'Параметры плана',
            '37-ai-grant-form' => 'Выдать ИИ доступ через MCP',
            '39-delegations' => 'Делегирование версии',
            _ => throw StateError('No JSON editor for $id'),
          },
          input: input,
          preview: _input(id),
          error: inputError,
          purpose: 'Проверьте точные параметры и цель перед продолжением.',
          serverProfiles: serverProfiles,
          targetServerIds: id == '37-ai-grant-form'
              ? const []
              : const [DesignAutomationFixtures.serverId],
          contextCurrent: current,
          onClose: callback('closeEditor'),
          onContinue: submitDraft,
        );

  AutomationRecipesSection recipes({bool enabled = true}) =>
      AutomationRecipesSection(
        catalog: DesignAutomationFixtures.catalog(enabled: enabled),
        serverId: DesignAutomationFixtures.serverId,
        serverProfiles: serverProfiles,
        canMutate: actions.mutate,
        onCreatePlan: counters.change('createRecipePlan'),
      );
  AutomationPlanSection plan({String? invalidReason, bool expired = false}) =>
      AutomationPlanSection(
        plan: DesignAutomationFixtures.plan(expired: expired),
        serverProfiles: serverProfiles,
        automationProfile: DesignAutomationFixtures.profile(),
        runnable: !expired && invalidReason == null,
        expired: expired,
        invalidReason: invalidReason,
        showPreflight: id == '18-install-preflight',
        actions: actions,
        onApprove: callback('approve'),
        onDeny: callback('deny'),
        onApply: callback('apply'),
        onRefresh: callback('refreshPlan'),
      );
  AutomationPlanDecisionDialog decision({
    bool expired = false,
    DateTime Function()? clock,
  }) => AutomationPlanDecisionDialog(
    plan: DesignAutomationFixtures.plan(expired: expired),
    serverProfiles: serverProfiles,
    automationProfile: DesignAutomationFixtures.profile(),
    now: clock ?? DesignAutomationFixtures.presentationNow,
    approve: true,
    onBack: callback('back'),
    onConfirm: callback('confirm'),
  );
  AutomationProfilesSection profiles() => AutomationProfilesSection(
    profiles: empty ? const [] : [DesignAutomationFixtures.profile()],
    loaded: !busy,
    hasMore: false,
    actions: actions,
    onSelect: counters.change('selectProfile'),
    onMore: callback('moreProfiles'),
  );
  AutomationProfileDetailSection revision({
    bool noChanges = false,
    bool truncated = false,
  }) {
    final comparison = DesignAutomationFixtures.comparison();
    comparison['result'] = {
      'changes': noChanges
          ? <Object?>[]
          : (comparison['result'] as Map<String, Object?>)['changes'],
      'truncated': truncated,
    };
    return AutomationProfileDetailSection(
      profile: DesignAutomationFixtures.profile(),
      revision: DesignAutomationFixtures.revision(),
      hasServer: true,
      comparison: comparison,
      actions: actions,
      onSelectVersion: callback('selectVersion'),
      onValidate: callback('validate'),
      onCompare: callback('compare'),
      onEdit: callback('editProfile'),
      onCreatePlan: callback('createPlan'),
      onDelegate: callback('delegate'),
      onArchive: callback('archive'),
    );
  }

  AutomationJobsSection jobs({
    String state = 'running',
    int dropped = 0,
    int count = 3,
    bool noChecks = false,
    bool detail = true,
  }) {
    var job = DesignAutomationFixtures.job(state: state);
    if (noChecks) {
      job = AutomationJobRecord.fromJson({
        ...job,
        'outcome': {
          ...(job['outcome'] as Map<String, Object?>),
          'checks': <Object?>[],
        },
      }).toJson();
    }
    final terminal = const {'succeeded', 'failed', 'cancelled'}.contains(state);
    return AutomationJobsSection(
      serverId: DesignAutomationFixtures.serverId,
      jobs: empty
          ? const []
          : [
              {'job': job},
            ],
      job: empty || !detail ? null : job,
      events: DesignAutomationFixtures.events(count: count, dropped: dropped),
      loaded: !busy,
      hasMore: false,
      droppedEvents: dropped,
      canCancel: !terminal && state != 'cancel-requested',
      canReconcile: state == 'unknown',
      actions: actions,
      onRefresh: callback('refreshJobs'),
      onRefreshAuthorities: callback('refreshAuthorities'),
      onSelect: counters.change('selectJob'),
      onMore: callback('moreJobs'),
      onShowPlan: callback('showPlan'),
      onCancel: callback('cancelJob'),
      onReconcile: callback('reconcileJob'),
    );
  }

  AutomationGrantsSection grants({
    bool configuration = false,
    bool expired = false,
    bool revoked = false,
  }) => AutomationGrantsSection(
    serverProfiles: serverProfiles,
    grants: empty
        ? const []
        : [
            for (final value in [
              DesignAutomationFixtures.grant(
                expired: expired,
                revoked: revoked,
              ),
            ])
              AutomationGrantPresentation(
                value: value,
                current: automationGrantCurrent(
                  value,
                  now: DesignAutomationFixtures.presentationNow(),
                ),
              ),
          ],
    loaded: !busy,
    actions: actions,
    launchConfiguration: configuration
        ? DesignAutomationFixtures.launchConfiguration()
        : null,
    onRefresh: callback('refreshGrants'),
    onCreate: callback('createGrant'),
    onConfigure: counters.change('configureGrant'),
    onEdit: counters.change('editGrant'),
    onRevoke: counters.change('revokeGrant'),
    onCopyConfiguration: callback('copyConfiguration'),
  );
  AutomationAuthoritiesSection authorities({
    bool expired = false,
    bool revoked = false,
  }) => AutomationAuthoritiesSection(
    approvals: const [],
    delegations: empty
        ? const []
        : [DesignAutomationFixtures.delegation(revoked: revoked)],
    now: expired
        ? () => DateTime.utc(2026, 10, 26)
        : DesignAutomationFixtures.presentationNow,
    loaded: !busy,
    hasMoreApprovals: false,
    hasMoreDelegations: false,
    actions: actions,
    onOpenPlan: counters.change('openPlan'),
    onRevokeDelegation: counters.change('revokeDelegation'),
    onMoreApprovals: callback('moreApprovals'),
    onMoreDelegations: callback('moreDelegations'),
  );

  Widget section({bool? ownerPhase}) {
    final after = ownerPhase ?? postModal;
    return switch (id) {
      '16-install-catalog' || '17-recipe-detail' => recipes(),
      '18-install-preflight' =>
        after &&
                const {
                  DesignStateCategory.loading,
                  DesignStateCategory.unknown,
                }.contains(category)
            ? recipes()
            : plan(),
      '19-plan-approval' => after ? plan() : decision(),
      '27-job-list' ||
      '28-job-detail' ||
      '29-job-unknown' ||
      '30-job-cancel' => jobs(
        detail: id != '27-job-list',
        state: id == '29-job-unknown'
            ? 'unknown'
            : id == '30-job-cancel'
            ? 'cancel-requested'
            : 'running',
      ),
      '32-automation-profiles' => profiles(),
      '33-profile-authoring' => after ? profiles() : editor(),
      '34-profile-revisions' => revision(),
      '35-plan-parameters' => after ? revision() : editor(),
      '36-ai-grants' => grants(),
      '37-ai-grant-form' => after ? grants() : editor(),
      '38-mcp-client-config' => grants(configuration: true),
      '39-delegations' => authorities(),
      '94-plan-invalidated' => plan(
        invalidReason: automationMessage('PLAN_STALE'),
      ),
      _ => throw StateError('No actual T036 section for $id'),
    };
  }

  void dispose() {
    operation.dispose();
    for (final controller in [name, description, body, input]) {
      controller.dispose();
    }
  }
}

Map<String, Object?> _input(String id) => switch (id) {
  '35-plan-parameters' => {'greeting': 'Привет'},
  '37-ai-grant-form' => {
    'label': 'Fixture client',
    'scopes': ['read', 'plan'],
    'serverIds': [DesignAutomationFixtures.serverId],
    'lifetimeSeconds': 3600,
  },
  '39-delegations' => {
    'lifetimeSeconds': 3600,
    'predicates': {
      'greeting': {
        'type': 'enum',
        'values': ['Привет'],
      },
    },
  },
  _ => <String, Object?>{},
};

Future<void> _click(WidgetTester tester, String label) async {
  final button = _button(label);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  expect(
    tester.widget<ButtonStyleButton>(button).onPressed,
    isNotNull,
    reason: label,
  );
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Widget _scroll(Widget child) =>
    SingleChildScrollView(padding: const EdgeInsets.all(16), child: child);

Future<void> _capture(
  WidgetTester tester,
  _Context context,
  _Variant variant,
  String phase,
  List<String> assertions,
) => captureDesignState(
  tester,
  family: 'automation',
  caseIds: [context.scenario.caseId],
  phase: '${context.scenario.caseId}-$phase'.toLowerCase().replaceAll('_', '-'),
  theme: variant.dark ? 'dark' : 'light',
  scale: variant.scale,
  counters: {...context.counters.values, 'nativeRpcMeasured': false},
  assertions: assertions,
  scope: 'Actual production widget/shared presentation flow with protocol-validated synthetic input and callback counters.',
  limitations: const [
    'No TrustedApiClient mock or native effect/authorization/request-identity proof. Owner callback wiring is source-audited separately. Current-generation privacy is T037.',
  ],
);

Future<void> _passive(
  WidgetTester tester,
  _Context context,
  Widget child,
  _Variant variant,
) async {
  final before = Map<String, int>.of(context.counters.values);
  await _mount(
    tester,
    child,
    _Variant(variant.size, variant.scale, !variant.dark),
  );
  tester.view.physicalSize = variant.size.width == 360
      ? const Size(390, 800)
      : const Size(800, 600);
  await tester.pumpAndSettle();
  expect(
    context.counters.values,
    before,
    reason: 'Theme/resize/render must add no UI-initiated command',
  );
  await _mount(tester, child, variant);
  expect(context.counters.values, before);
}

void _registerRegistry(bool fullAdaptive) {
  for (final scenario in designStateCases.where(
    (item) => item.taskId == 'T036',
  )) {
    for (final dark in [false, true]) {
      final frames = fullAdaptive
          ? [
              for (final size in [
                const Size(1100, 760),
                const Size(800, 600),
                const Size(390, 800),
                const Size(360, 800),
              ])
                for (final scale in [1.0, 2.0]) (size, scale),
            ]
          : [(const Size(360, 800), 2.0), (const Size(1100, 760), 1.0)];
      for (final (size, scale) in frames) {
        final variant = _Variant(size, scale, dark);
        testWidgets('[${scenario.caseId}] actual-${variant.suffix}', (
          tester,
        ) async {
          final context = _Context(scenario);
          try {
            switch (scenario.category) {
              case DesignStateCategory.loading:
                await _loading(tester, context, variant);
              case DesignStateCategory.successfulEmpty:
                await _empty(tester, context, variant);
              case DesignStateCategory.data:
                await _data(tester, context, variant);
              case DesignStateCategory.validation:
                await _validation(tester, context, variant);
              case DesignStateCategory.denied:
                await _failure(tester, context, variant, 'FORBIDDEN');
              case DesignStateCategory.unsupported:
                await _failure(tester, context, variant, 'UNSUPPORTED');
              case DesignStateCategory.stale:
                await _stale(tester, context, variant);
              case DesignStateCategory.dropped:
                await _jobQuality(tester, context, variant, true);
              case DesignStateCategory.incomplete:
                await _incomplete(tester, context, variant);
              case DesignStateCategory.sshUnavailable:
                await _failure(tester, context, variant, 'CONNECTION_FAILED');
              case DesignStateCategory.unknown:
                await _unknown(tester, context, variant);
              case DesignStateCategory.localUnavailable:
                fail('Private epoch case belongs to T037');
            }
            expect(tester.takeException(), isNull, reason: scenario.caseId);
          } finally {
            await tester.pumpWidget(const SizedBox());
            for (final model in context.localModels) {
              await model.close();
            }
            context.dispose();
          }
        });
      }
    }
  }
}

Future<void> _loading(
  WidgetTester tester,
  _Context context,
  _Variant variant,
) async {
  if (context.id == '16-install-catalog') {
    final harness = await DesignScenarioHarness.create(
      options: const DesignFixtureOptions(loaded: false),
    );
    context.localModels.add(harness);
    final reads = harness.client.refreshes;
    await _mount(
      tester,
      SoftwarePanel(profiles: harness.profiles, client: null),
      variant,
    );
    expect(find.text('Ожидание списка серверов'), findsOneWidget);
    expect(find.text('Серверов пока нет'), findsNothing);
    expect(harness.client.mutations, isEmpty);
    expect(harness.client.refreshes, reads);
    await _capture(tester, context, variant, 'local-profiles-pending', [
      'Real ProfileController pending snapshot is not successful empty',
      'No UI-triggered mutation or extra refresh',
    ]);
    await tester.pumpWidget(const SizedBox());
    await harness.close();
  }
  if (context.id == '33-profile-authoring') {
    await _mount(tester, context.editor(), variant);
    expect(find.text('Проверка содержимого профиля'), findsOneWidget);
    expect(
      tester.widget<ButtonStyleButton>(_button('Сохранить версию')).onPressed,
      isNull,
    );
    expect(
      tester.widget<ButtonStyleButton>(_button('Проверка…')).onPressed,
      isNull,
    );
    expect(context.body.text, jsonEncode(DesignAutomationFixtures.body()));
    await _capture(tester, context, variant, 'editor-validating', [
      'Actual validating stage blocks save/validate duplicates',
      'RAM body is retained',
    ]);
  }
  final gate = Completer<void>();
  final pending = context.operation.run(context.phase, () {
    context.counters.hit('phaseDispatch');
    return gate.future;
  });
  // Build the actual owner status beside its owning production section. The
  // helper's one callback is a presentation dispatch, never a fake RPC.
  final composed = _scroll(
    ListenableBuilder(
      listenable: context.operation,
      builder: (_, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AutomationStatusSection(
            busy: context.operation.label != null,
            openingRecipes: false,
            canRetry: false,
            operationLabel: context.operation.label,
            onRetry: context.callback('retry'),
            onDismiss: context.callback('dismiss'),
            onStopWaiting: context.callback('stopWaiting'),
          ),
          context.section(ownerPhase: true),
        ],
      ),
    ),
  );
  await _mount(tester, composed, variant);
  expect(
    find.descendant(
      of: find.byType(AutomationStatusSection),
      matching: find.text(context.phase.label),
    ),
    findsOneWidget,
  );
  expect(find.byType(CircularProgressIndicator), findsNothing);
  expect(context.counters['phaseDispatch'], 1);
  if (const {
    '16-install-catalog',
    '17-recipe-detail',
    '18-install-preflight',
  }.contains(context.id)) {
    // Selecting an already loaded row only changes local presentation. Its
    // actual durable action remains disabled by the existing owner phase.
    final recipe = find.text('PostgreSQL 16');
    await tester.ensureVisible(recipe);
    await tester.tap(recipe);
    await tester.pumpAndSettle();
    expect(
      tester.widget<ButtonStyleButton>(_button('Создать план')).onPressed,
      isNull,
    );
  }
  const ownerActions = {
    'Создать план',
    'Подтвердить план',
    'Отклонить план',
    'Запустить',
    'Обновить план',
    'Обновить',
    'Обновить задания',
    'План задания',
    'Остановить после текущего шага',
    'Уточнить результат',
    'Обновить состояние',
    'Проверить версию',
    'Сравнить версии',
    'Изменить профиль',
    'Делегировать версию',
    'Архивировать',
    'Выдать доступ',
    'Изменить права',
    'Отозвать',
    'Конфигурация MCP',
    'Обновить клиентов',
    'Скопировать конфигурацию',
    'Обновить разрешения',
    'Создать новый план',
    'Выбрать версию',
  };
  for (final label in ownerActions) {
    final buttons = find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    );
    for (final button in buttons.evaluate()) {
      expect(
        (button.widget as ButtonStyleButton).onPressed,
        isNull,
        reason:
            'The actual owner action $label must remain disabled; local view controls may remain available',
      );
    }
  }
  await _passive(tester, context, composed, variant);
  expect(context.counters['phaseDispatch'], 1);
  await _capture(tester, context, variant, 'owner-pending', [
    'Exact existing operation label',
    'Same-action disabled and static reduced-motion indicator',
    'Theme/resize add no presentation dispatch',
  ]);
  gate.complete();
  await tester.pump();
  await pending;
  await tester.pumpAndSettle();
  expect(context.operation.label, isNull);
  expect(context.counters['phaseDispatch'], 1);
}

Future<void> _empty(
  WidgetTester tester,
  _Context context,
  _Variant variant,
) async {
  late Widget child;
  late String label;
  switch (context.id) {
    case '16-install-catalog':
      final harness = await DesignScenarioHarness.create(
        options: const DesignFixtureOptions(empty: true),
      );
      context.localModels.add(harness);
      child = SoftwarePanel(profiles: harness.profiles, client: null);
      label = 'Серверов пока нет';
    case '27-job-list':
      child = _scroll(context.jobs(detail: false));
      label = 'Заданий на этом сервере пока нет';
    case '32-automation-profiles':
      child = _scroll(context.profiles());
      label = 'Ansible-профилей пока нет';
    case '34-profile-revisions':
      child = _scroll(context.revision(noChanges: true));
      label = 'В полученном сравнении изменений нет';
    case '36-ai-grants':
      child = _scroll(context.grants());
      label = 'Клиентов ИИ пока нет';
    case '39-delegations':
      child = _scroll(context.authorities());
      label = 'Делегирований пока нет';
    default:
      throw StateError(
        'No successful-empty production branch for ${context.id}',
      );
  }
  await _mount(tester, child, variant);
  await _expand(tester, context.id);
  expect(find.text(label), findsOneWidget);
  expect(context.counters.values, isEmpty);
  if (context.id == '34-profile-revisions')
    expect(find.textContaining('Сравнение неполное'), findsNothing);
  await _capture(tester, context, variant, 'successful-empty', [
    'Successfully obtained empty branch with explicit context',
    'No fake empty catalog/draft/required singleton',
    'No callback from rendering',
  ]);
  await _passive(tester, context, child, variant);
}

Future<void> _expand(WidgetTester tester, String id) async {
  if (id == '39-delegations') {
    if (find.text('Делегирований пока нет').evaluate().isEmpty &&
        find.text('Действует до').evaluate().isEmpty) {
      await tester.tap(find.text('Делегированные версии'));
      await tester.pumpAndSettle();
    }
  }
}

Future<void> _data(
  WidgetTester tester,
  _Context context,
  _Variant variant,
) async {
  if (context.id == '16-install-catalog') {
    final harness = await DesignScenarioHarness.create();
    context.localModels.add(harness);
    await _mount(
      tester,
      SoftwarePanel(profiles: harness.profiles, client: null),
      variant,
    );
    expect(find.text('Каталог установки'), findsOneWidget);
    final selected = harness.profiles.profiles.single;
    expect(
      find.text('${selected.name} · ${selected.address}:${selected.port}'),
      findsOneWidget,
    );
    expect(harness.client.mutations, isEmpty);
    await _capture(tester, context, variant, 'local-software-selection', [
      'Actual SoftwarePanel current local profile metadata',
      'Selection does not connect automatically',
    ]);
  }
  final modal = const {
    '19-plan-approval',
    '33-profile-authoring',
    '35-plan-parameters',
    '37-ai-grant-form',
  }.contains(context.id);
  final child = modal
      ? context.section(ownerPhase: false)
      : _scroll(context.section(ownerPhase: false));
  await _mount(tester, child, variant);
  await _expand(tester, context.id);
  switch (context.id) {
    case '16-install-catalog' || '17-recipe-detail':
      final row = find.text('PostgreSQL 16');
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.text('PostgreSQL 16'), findsOneWidget);
      expect(find.text('16.10'), findsOneWidget);
      final title = find.text('Лицензии, начальные настройки и точные условия');
      await tester.ensureVisible(title);
      await tester.tap(title);
      await tester.pumpAndSettle();
      final raw = tester.widget<SelectableText>(
        find.descendant(
          of: find.byType(AutomationJsonView),
          matching: find.byType(SelectableText),
        ),
      );
      expect((jsonDecode(raw.data!) as Map)['licenseNotices'], [
        'PostgreSQL License\nСинтетический пример лицензии',
      ]);
    case '18-install-preflight' || '94-plan-invalidated':
      expect(
        find.text('Синтетический сервер · 192.0.2.44:2222'),
        findsOneWidget,
      );
      if (context.id == '18-install-preflight')
        expect(find.text('Привет'), findsWidgets);
      if (context.id == '94-plan-invalidated')
        expect(find.text('План больше не действует'), findsWidgets);
      if (context.id == '94-plan-invalidated') {
        await _click(tester, 'Просмотреть прежний план');
        final title = find.text('Неизменный план и технические детали');
        await tester.ensureVisible(title);
        await tester.tap(title);
        await tester.pumpAndSettle();
        final payload = tester.widget<SelectableText>(
          find.byType(SelectableText),
        );
        final previous = (jsonDecode(payload.data!) as Map)
            .cast<String, Object?>();
        expect(previous['exactParams'], {'greeting': 'Привет'});
        expect(previous, DesignAutomationFixtures.plan());
      }
    case '19-plan-approval':
      expect(
        find.text('Синтетический сервер · 192.0.2.44:2222'),
        findsOneWidget,
      );
      expect(context.counters['confirm'], 0);
    case '27-job-list' ||
        '28-job-detail' ||
        '29-job-unknown' ||
        '30-job-cancel':
      if (context.id != '30-job-cancel')
        expect(find.text(DesignAutomationFixtures.jobId), findsWidgets);
      if (context.id == '27-job-list')
        expect(find.text('Контекст задания'), findsNothing);
      if (context.id == '28-job-detail')
        expect(find.text('Контекст задания'), findsOneWidget);
      if (context.id == '29-job-unknown' || context.id == '30-job-cancel')
        expect(find.text('Контекст и проверка результата'), findsOneWidget);
      if (context.id == '29-job-unknown')
        expect(
          find.text('Возможны неподтверждённые изменения'),
          findsOneWidget,
        );
      if (context.id == '30-job-cancel') {
        expect(find.text('Состояние: Остановка запрошена'), findsOneWidget);
        expect(find.text('Остановить после текущего шага'), findsNothing);
        final title = find.text('Результат и проверки задания');
        await tester.ensureVisible(title);
        await tester.tap(title);
        await tester.pumpAndSettle();
        final payload = tester.widget<SelectableText>(
          find.byType(SelectableText),
        );
        final captured = (jsonDecode(payload.data!) as Map)
            .cast<String, Object?>();
        expect(captured['id'], DesignAutomationFixtures.jobId);
        expect(
          captured,
          DesignAutomationFixtures.job(state: 'cancel-requested'),
        );
      }
    case '32-automation-profiles':
      expect(
        find.text(DesignAutomationFixtures.profile().name),
        findsOneWidget,
      );
    case '33-profile-authoring':
      expect(context.body.text, jsonEncode(DesignAutomationFixtures.body()));
    case '34-profile-revisions':
      expect(_comparisonValue('/parameters/greeting/default'), findsOneWidget);
    case '35-plan-parameters' || '37-ai-grant-form':
      final draft = await _showDraftField(tester, context.input);
      expect(tester.widget<TextField>(draft).controller, same(context.input));
      expect(context.input.text, jsonEncode(_input(context.id)));
    case '36-ai-grants':
      expect(find.text('Действует'), findsOneWidget);
    case '38-mcp-client-config':
      final exact = tester
          .widgetList<AutomationExactValue>(find.byType(AutomationExactValue))
          .toList();
      expect(exact.first.value, r'C:\Synthetic\ServerDeck\mcp.exe');
      expect(
        exact.last.value,
        (DesignAutomationFixtures.launchConfiguration()['args'] as List).join(
          ', ',
        ),
      );
    case '39-delegations':
      expect(find.text('Делегирование версии'), findsOneWidget);
      expect(find.text('Действует до'), findsOneWidget);
    default:
      throw StateError('No actual data oracle for ${context.id}');
  }
  expect(context.counters.values, isEmpty);
  await _capture(tester, context, variant, 'current-data', [
    'Actual origin-specific component and exact DTO values',
    'No command from rendering',
    'Callback effect proof remains presentation-only',
  ]);
  if (context.id == '33-profile-authoring' ||
      context.id == '35-plan-parameters' ||
      context.id == '37-ai-grant-form') {
    await _click(
      tester,
      context.id == '33-profile-authoring' ? 'Сохранить версию' : 'Продолжить',
    );
    expect(context.counters['draftDispatch'], 1);
    expect(
      context.sent,
      context.id == '33-profile-authoring'
          ? DesignAutomationFixtures.body()
          : _input(context.id),
    );
  } else if (context.id == '19-plan-approval') {
    await _click(tester, 'Подтвердить план');
    expect(context.counters['confirm'], 1);
    expect(context.counters['apply'], 0);
  } else if (context.id == '38-mcp-client-config') {
    await _click(tester, 'Скопировать конфигурацию');
    expect(context.counters['copyConfiguration'], 1);
    expect(context.counters['revokeGrant'], 0);
  }
  if (context.id == '36-ai-grants') {
    for (final revoked in [false, true]) {
      await _mount(
        tester,
        _scroll(context.grants(expired: true, revoked: revoked)),
        variant,
      );
      await _expand(tester, context.id);
      expect(find.text(revoked ? 'Отозван' : 'Истёк'), findsOneWidget);
      expect(
        tester.widget<ButtonStyleButton>(_button('Конфигурация MCP')).onPressed,
        isNull,
      );
      if (revoked)
        expect(
          tester.widget<ButtonStyleButton>(_button('Изменить права')).onPressed,
          isNull,
        );
      else
        expect(find.text('Изменить права'), findsOneWidget);
      await _capture(
        tester,
        context,
        variant,
        revoked ? 'grant-revoked' : 'grant-expired',
        [
          'Expired nonrevoked may explicitly replace',
          'Revoked has no renewed authority',
          'Exact scopes/targets/deadline retained',
        ],
      );
    }
  }
  if (context.id == '39-delegations') {
    for (final revoked in [false, true]) {
      await _mount(
        tester,
        _scroll(context.authorities(expired: true, revoked: revoked)),
        variant,
      );
      await _expand(tester, context.id);
      expect(
        find.text(
          revoked ? 'Делегирование отозвано' : 'Срок делегирования истёк',
        ),
        findsOneWidget,
      );
      if (revoked) expect(find.text('Отозвать делегирование'), findsNothing);
      await _capture(
        tester,
        context,
        variant,
        revoked ? 'delegation-revoked' : 'delegation-expired',
        [
          'Explicit expiry/revocation variant with exact deadline and predicates',
        ],
      );
    }
  }
}

Future<void> _failure(
  WidgetTester tester,
  _Context context,
  _Variant variant,
  String code,
) async {
  if (context.id == '16-install-catalog' &&
      const {'FORBIDDEN', 'UNSUPPORTED'}.contains(code)) {
    final harness = await DesignScenarioHarness.create();
    context.localModels.add(harness);
    final typed = code == 'FORBIDDEN'
        ? ErrorCode.forbidden
        : ErrorCode.unsupported;
    harness.showReadError(typed);
    await _mount(
      tester,
      SoftwarePanel(profiles: harness.profiles, client: null),
      variant,
    );
    expect(
      find.text(ReadErrorView.category(typed)),
      findsWidgets,
      reason: 'Actual software profile read failure must not be shown as indefinite loading.',
    );
    expect(find.text('Ожидание списка серверов'), findsNothing);
    expect(harness.client.mutations, isEmpty);
    await _capture(tester, context, variant, 'software-profile-read-error', [
      'Actual ProfileController typed read rejection inside SoftwarePanel',
      'Failure is not loading/successful empty',
      'No automatic mutation/connect',
    ]);
    await tester.pumpWidget(const SizedBox());
    await harness.close();
  }
  final legal = TrustedLocalError.fromJson(TrustedLocalError(code).toJson());
  final child = _scroll(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AutomationStatusSection(
          busy: false,
          openingRecipes: false,
          canRetry: context.retainedDurable,
          errorCode: context.retainedDurable ? null : legal.code,
          writeOutcome: context.retainedDurable
              ? AutomationWriteOutcome(
                  label: context.phase.label,
                  errorCode: legal.code,
                )
              : null,
          pendingLabel: context.retainedDurable ? context.phase.label : null,
          onRetry: context.callback('retry'),
          onDismiss: context.callback('dismiss'),
          onStopWaiting: context.callback('stopWaiting'),
        ),
        context.section(ownerPhase: true),
      ],
    ),
  );
  await _mount(tester, child, variant);
  expect(find.text(automationMessage(code)), findsOneWidget);
  expect(
    find.byWidgetPredicate(
      (widget) =>
          widget is DeckNotice &&
          widget.message == automationMessage(code) &&
          widget.tone ==
              (const {
                    'FORBIDDEN',
                    'UNSUPPORTED',
                    'VALIDATION',
                    'REVISION_CONFLICT',
                  }.contains(code)
                  ? DeckTone.warning
                  : DeckTone.unavailable),
    ),
    findsOneWidget,
  );
  expect(find.text('Исход записи не подтверждён'), findsNothing);
  expect(find.textContaining('Не удалось выполнить запрос:'), findsNothing);
  expect(context.counters.values, isEmpty);
  await _passive(tester, context, child, variant);
  await _capture(tester, context, variant, code.toLowerCase(), [
    'Actual legal typed outer error through shared live Panel formatter/status',
    'Definitive rejection is not unknown despite retained request label',
    'Existing production section keeps actual data/context; no automatic retry/connect',
  ]);
  if (code == 'UNSUPPORTED' &&
      (context.id == '16-install-catalog' ||
          context.id == '17-recipe-detail')) {
    await _mount(tester, _scroll(context.recipes(enabled: false)), variant);
    expect(find.text('Установка недоступна'), findsOneWidget);
    expect(find.text('План установки PostgreSQL 16'), findsNothing);
    expect(context.counters['createRecipePlan'], 0);
    await _capture(tester, context, variant, 'catalog-unqualified', [
      'Actual unsupported qualified-recipe branch is not a successful empty catalog',
      'No active empty install handler',
    ]);
  }
}

Future<void> _validation(
  WidgetTester tester,
  _Context context,
  _Variant variant,
) async {
  if (const {
    '33-profile-authoring',
    '35-plan-parameters',
    '37-ai-grant-form',
    '39-delegations',
  }.contains(context.id)) {
    final source = context.id == '33-profile-authoring'
        ? context.body
        : context.input;
    source.text = '{invalid JSON';
    await _mount(tester, context.editor(), variant);
    final label = context.id == '33-profile-authoring'
        ? 'Сохранить версию'
        : 'Продолжить';
    final callback = tester
        .widget<ButtonStyleButton>(_button(label))
        .onPressed!;
    expect(callback, throwsFormatException);
    expect(context.counters['draftDispatch'], 0);
    expect(source.text, '{invalid JSON');
    context.inputError = automationDraftInputError(
      profileBody: context.id == '33-profile-authoring',
    );
    final child = context.editor();
    await _mount(tester, child, variant);
    expect(find.text(context.inputError!), findsOneWidget);
    await _passive(tester, context, child, variant);
    expect(source.text, '{invalid JSON');
    await _capture(tester, context, variant, 'invalid-draft', [
      'Actual production pre-dispatch parser throws before borrowed submit callback',
      'Draft/field error retained through actual dialog/theme/resize',
      'No copied owner parser or fake TrustedApiClient',
    ]);
    source.text = context.id == '33-profile-authoring'
        ? jsonEncode(DesignAutomationFixtures.body())
        : jsonEncode(_input(context.id));
    context.current = false;
    expect(context.submitDraft, throwsA(isA<AutomationDraftContextChanged>()));
    context.current = true;
    expect(context.submitDraft, throwsA(isA<AutomationDraftContextChanged>()));
    expect(context.counters['draftDispatch'], 0);
    if (context.id == '39-delegations') {
      await _failure(tester, context, variant, 'REVISION_CONFLICT');
    }
    return;
  }
  // Preflight is a received owner validation failure; grants is a revoke CAS
  // conflict. Neither origin invents an editable draft in a read-only section.
  final code =
      context.id == '36-ai-grants' || context.id == '34-profile-revisions'
      ? 'REVISION_CONFLICT'
      : 'VALIDATION';
  await _failure(tester, context, variant, code);
  if (context.id == '36-ai-grants' || context.id == '34-profile-revisions') {
    final label = context.id == '36-ai-grants'
        ? 'Отозвать доступ'
        : 'Архивировать';
    await _mount(
      tester,
      AutomationConfirmationDialog(
        title: label,
        message: 'Текущая версия изменена; перечитайте данные.',
        confirmLabel: label,
        onBack: context.callback('back'),
        onConfirm: context.callback('confirmedMutation'),
      ),
      variant,
    );
    await _click(tester, 'Назад');
    expect(context.counters['confirmedMutation'], 0);
    expect(context.counters['back'], 1);
    await _capture(tester, context, variant, 'cas-confirmation-cancel', [
      'Actual confirmation cancel dispatches no revocation/archive',
      'CAS is validation/conflict, not observation stale or unknown',
    ]);
  }
}

Future<void> _stale(
  WidgetTester tester,
  _Context context,
  _Variant variant,
) async {
  for (final code in ['PLAN_STALE', 'PLAN_EXPIRED', 'TRUST_CHANGED']) {
    final child = _scroll(
      context.plan(
        expired: code == 'PLAN_EXPIRED',
        invalidReason: code == 'PLAN_EXPIRED' ? null : automationMessage(code),
      ),
    );
    await _mount(tester, child, variant);
    expect(find.text('Запустить'), findsNothing);
    expect(find.text('Подтвердить план'), findsNothing);
    expect(find.text('Создать новый план'), findsOneWidget);
    if (find.text('Обновить план').evaluate().isEmpty)
      await _click(tester, 'Просмотреть прежний план');
    expect(find.text('Обновить план'), findsOneWidget);
    expect(context.counters['apply'] + context.counters['approve'], 0);
    await _capture(
      tester,
      context,
      variant,
      code.toLowerCase().replaceAll('_', '-'),
      [
        'Exact domain invalidation reason/deadline',
        'Old apply/approve unavailable',
        'No fake observation stale/CAS equivalence',
      ],
    );
  }
  if (context.id == '19-plan-approval') {
    var now = DesignAutomationFixtures.presentationNow();
    final child = context.decision(clock: () => now);
    await _mount(tester, child, variant);
    final retained = tester
        .widget<ButtonStyleButton>(_button('Подтвердить план'))
        .onPressed!;
    now = now.add(const Duration(minutes: 6));
    retained();
    await tester.pumpAndSettle();
    expect(context.counters['confirm'], 0);
    expect(find.text('Срок плана истёк'), findsWidgets);
    expect(find.text('Подтвердить план'), findsNothing);
    now = DesignAutomationFixtures.presentationNow();
    await _mount(tester, child, variant);
    expect(
      find.text('Подтвердить план'),
      findsNothing,
      reason: 'Observed deadline retirement cannot restore old consent when a synthetic clock rewinds.',
    );
    await _capture(tester, context, variant, 'deadline-retired', [
      'Actual open dialog deadline crossed with explicit clock basis',
      'Retained click rechecks deadline before consent; observed expiry stays retired after synthetic clock rewind',
      'Default live deadline uses real clock, owner final guard remains',
    ]);
  }
}

Future<void> _jobQuality(
  WidgetTester tester,
  _Context context,
  _Variant variant,
  bool dropped,
) async {
  await _mount(
    tester,
    _scroll(
      context.jobs(
        state: 'unknown',
        dropped: dropped ? 7 : 0,
        count: dropped ? 3 : 200,
      ),
    ),
    variant,
  );
  final received =
      'Получено событий: ${dropped ? 3 : 200}. Пропущено в источнике: ${dropped ? 7 : 0}';
  if (find.text(received).evaluate().isEmpty)
    await _click(tester, 'Показать события');
  expect(
    find.text(
      'Получено событий: ${dropped ? 3 : 200}. Пропущено в источнике: ${dropped ? 7 : 0}',
    ),
    findsOneWidget,
  );
  expect(
    find.byWidgetPredicate(
      (widget) =>
          widget is DeckStatus &&
          widget.label.startsWith('Получено событий:') &&
          widget.tone == (dropped ? DeckTone.warning : DeckTone.neutral),
    ),
    findsOneWidget,
  );
  expect(find.text('Возможны неподтверждённые изменения'), findsOneWidget);
  expect(
    tester
        .widget<AutomationJobsSection>(find.byType(AutomationJobsSection))
        .events,
    DesignAutomationFixtures.events(
      count: dropped ? 3 : 200,
      dropped: dropped ? 7 : 0,
    ),
  );
  if (dropped) expect(find.text('Пропущено событий: 7'), findsOneWidget);
  expect(context.counters.values, isEmpty);
  await _capture(
    tester,
    context,
    variant,
    dropped ? 'source-dropped' : 'retained-200',
    [
      'Actual dropped/event count, not inferred from retention cap',
      'Job outcome/effects retained',
      'No automatic recovery callback',
    ],
  );
  if (dropped) await _jobQuality(tester, context, variant, false);
}

Future<void> _incomplete(
  WidgetTester tester,
  _Context context,
  _Variant variant,
) async {
  if (context.id == '34-profile-revisions') {
    await _mount(tester, _scroll(context.revision(truncated: true)), variant);
    expect(
      find.text('Сравнение неполное: часть изменений не получена'),
      findsOneWidget,
    );
    expect(_comparisonValue('/parameters/greeting/default'), findsOneWidget);
  } else {
    await _mount(
      tester,
      _scroll(context.jobs(state: 'succeeded', noChecks: true)),
      variant,
    );
    expect(find.text('Результаты проверок не предоставлены'), findsOneWidget);
    expect(
      find.textContaining('motd · written: Проверка пройдена'),
      findsNothing,
    );
    expect(find.text('Изменения подтверждены'), findsOneWidget);
  }
  expect(context.counters.values, isEmpty);
  await _capture(tester, context, variant, 'explicit-incomplete', [
    'Actual truncation/checks-not-provided branch',
    'No invented passed checks/completeness or automatic retry',
  ]);
}

Future<void> _unknown(
  WidgetTester tester,
  _Context context,
  _Variant variant,
) async {
  if (const {
    '27-job-list',
    '28-job-detail',
    '29-job-unknown',
    '30-job-cancel',
  }.contains(context.id)) {
    if (context.id == '27-job-list') {
      await _mount(
        tester,
        _scroll(context.jobs(state: 'unknown', detail: false)),
        variant,
      );
      expect(find.text('Уточнить результат'), findsNothing);
      final row = find
          .descendant(
            of: find.byType(AutomationLoadedTable),
            matching: find.text(DesignAutomationFixtures.jobId),
          )
          .first;
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(context.counters['selectJob'], 1);
    }
    await _mount(tester, _scroll(context.jobs(state: 'unknown')), variant);
    expect(find.text('Возможны неподтверждённые изменения'), findsOneWidget);
    expect(find.text('Исход не подтверждён'), findsWidgets);
    await _capture(tester, context, variant, 'job-unknown', [
      'Protocol-validated unknown job, effects=uncertain/safeCode=UNKNOWN_OUTCOME',
      'Observational reconcile is an explicit existing action, not receipt lookup or generic retry',
    ]);
    await _click(tester, 'Уточнить результат');
    expect(context.counters['reconcileJob'], 1);
    expect(context.counters['cancelJob'], 0);
    await _mount(
      tester,
      _scroll(
        AutomationStatusSection(
          busy: true,
          openingRecipes: false,
          canRetry: false,
          operationLabel: AutomationUiPhase.reconcile.label,
          onRetry: context.callback('retry'),
          onDismiss: context.callback('dismiss'),
          onStopWaiting: context.callback('stopWaiting'),
        ),
      ),
      variant,
    );
    await _click(tester, 'Перестать ждать ответ');
    expect(context.counters['stopWaiting'], 1);
    expect(context.counters['cancelJob'], 0);
    if (context.id != '30-job-cancel') return;
    // A lost cancellation command is a separate uncertainty from the selected
    // job's unknown result. It uses the retained owner request presentation.
  }
  final child = _scroll(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AutomationStatusSection(
          busy: false,
          openingRecipes: false,
          canRetry: true,
          writeOutcome: AutomationWriteOutcome(
            label: context.phase.label,
            errorCode: TrustedLocalError('TIMEOUT').code,
          ),
          pendingLabel: context.phase.label,
          onRetry: context.callback('retryPending'),
          onDismiss: context.callback('dismiss'),
          onStopWaiting: context.callback('stopWaiting'),
        ),
        context.section(ownerPhase: true),
      ],
    ),
  );
  await _mount(tester, child, variant);
  expect(find.text('Исход записи не подтверждён'), findsOneWidget);
  expect(context.counters['retryPending'], 0);
  await _passive(tester, context, child, variant);
  await _capture(tester, context, variant, 'durable-reply-unconfirmed', [
    'Retained durable request plus actual legal TIMEOUT, not mere pendingLabel',
    'Only existing explicit retry/dismiss callbacks; no request identity/native outcome claim',
    'No automatic retry on render/theme/resize',
  ]);
  await _click(tester, 'Повторить тот же запрос');
  expect(context.counters['retryPending'], 1);
  await _click(tester, 'Закрыть запрос');
  expect(context.counters['dismiss'], 1);
  expect(context.counters['cancelJob'], 0);
}

/// Actual production presentation journeys. No TrustedApiClient is mocked.
void registerDesignAutomationStateCases({bool fullAdaptive = false}) {
  setUpAll(loadDesignFonts);
  _registerSubmissionAndProvenanceBoundaries();
  _registerProfileRecoveryBoundaries();
  test('T036 actual live Panel wiring, closed error vocabulary and complete provider IDs', () {
    final source = File('lib/automation/automation_panel.dart')
        .readAsStringSync();
    expect(source, contains('errorCode: _presentation.readErrorCode'));
    expect(source, contains('writeOutcome: _presentation.writeOutcome'));
    expect(source, contains('_presentation.observeOwner(_result(model))'));
    expect(source, contains('_presentation.dismiss('));
    expect(source, contains('AutomationUiPhase.retry'));
    expect(source, contains('admitted: () => captured.busy'));
    expect(source, contains('phase.durable'));
    expect(source, contains('captured.canRetry'));
    expect(source, contains('captured.canMutate'));
    final editorSource = source.substring(
      source.indexOf('Future<void> _editProfile('),
      source.indexOf('Future<void> _decision('),
    );
    expect(editorSource, contains('final baseRevision = existing == null'));
    expect(editorSource, contains('baseRevision: baseRevision'));
    expect(editorSource, isNot(contains('model.revision!')));
    expect(editorSource, contains('AutomationProfileDraftSubmission('));
    expect(editorSource, contains('initialBasis: existing == null'));
    expect(editorSource, contains('resultError: () => controller.error'));
    expect(editorSource, contains('dialog.mounted'));
    expect(editorSource, contains('submission.dispose()'));
    expect(editorSource, contains('AutomationProfileBasis.fromOwner('));
    expect(editorSource, contains('currentHead: true'));
    expect(editorSource, contains('controller.selectProfile(existing!.id)'));
    expect(editorSource, contains('canRead: () => controller.canMutate'));
    expect(
      editorSource,
      contains('pendingLabel: () => controller.pendingLabel'),
    );
    expect(editorSource, contains('controller.validation'));
    final validationSource = editorSource.substring(
      editorSource.indexOf('onValidate: () async'),
    );
    expect(
      validationSource.indexOf('!current()'),
      lessThan(validationSource.indexOf('final source = body.text')),
    );
    expect(validationSource, isNot(contains('model.validation')));

    expect(source, contains('final result = _result(captured)'));
    expect(source, contains('onCompleted?.call(result)'));
    expect(source, contains('operationLabel: _presentation.label'));
    expect(
      source,
      contains('String message(String code) => automationMessage(code)'),
    );
    expect(source, contains('AutomationJsonDraftSubmission(phase)'));
    expect(source, contains('await submission.submit('));
    expect(
      File('lib/automation/automation_presentation.dart').readAsStringSync(),
      contains('final work = submitAutomationDraft('),
    );
    expect(source, contains('_notifyModalContext();'));
    expect(source, contains('!automationPlanExpired(plan)'));
    expect(source, contains('deadline.isAfter(DateTime.now())'));
    expect(source, isNot(contains('now: DesignAutomationFixtures')));
    const secret = 'untrusted exception PRIVATE payload';
    expect(automationMessage(secret), isNot(contains(secret)));
    expect(() => TrustedLocalError('UNKNOWN_OUTCOME'), throwsFormatException);
    for (final code in ['FORBIDDEN', 'UNSUPPORTED', 'VALIDATION']) {
      expect(
        AutomationWriteOutcome(
          label: 'Retained action',
          errorCode: code,
        ).unconfirmed,
        isFalse,
      );
    }
    expect(
      const AutomationWriteOutcome(
        label: 'Retained action',
        errorCode: 'TIMEOUT',
      ).unconfirmed,
      isTrue,
    );
    final cases = designStateCases
        .where((item) => item.taskId == 'T036')
        .toList();
    expect(cases, hasLength(110));
    expect(cases.map((item) => item.caseId).toSet(), hasLength(110));
  });
  _registerRegistry(fullAdaptive);
  final frames = fullAdaptive
      ? [
          for (final size in [
            const Size(1100, 760),
            const Size(800, 600),
            const Size(390, 800),
            const Size(360, 800),
          ])
            for (final scale in [1.0, 2.0]) (size, scale),
        ]
      : [(const Size(360, 800), 2.0), (const Size(1100, 760), 1.0)];
  for (final dark in [false, true]) {
    for (final (size, scale) in frames) {
      final variant = _Variant(size, scale, dark);
      _registerPreflightRegressions(variant);
      testWidgets(
        'T036 regression default real-clock expired decision rejects old consent ${variant.suffix}',
        (tester) async {
          var confirmed = 0;
          await _mount(
            tester,
            AutomationPlanDecisionDialog(
              plan: DesignAutomationFixtures.plan(expired: true),
              serverProfiles: [
                DesignServerFixtures.profile(connectionRevision: '2'),
              ],
              automationProfile: DesignAutomationFixtures.profile(),
              approve: true,
              onBack: () {},
              onConfirm: () => confirmed++,
            ),
            variant,
          );
          expect(
            find.text('Подтвердить план'),
            findsNothing,
            reason: 'An expired exact plan must not keep an active old consent callback.',
          );
          expect(confirmed, 0);
        },
      );
      for (final code in ['UNSUPPORTED', 'SERVICE_UNAVAILABLE', 'TIMEOUT']) {
        testWidgets('T036 regression raw owner error $code ${variant.suffix}', (
          tester,
        ) async {
          final legal = TrustedLocalError.fromJson(
            TrustedLocalError(code).toJson(),
          );
          await _mount(
            tester,
            SingleChildScrollView(
              child: AutomationStatusSection(
                busy: false,
                openingRecipes: false,
                canRetry: false,
                errorCode: legal.code,
                onRetry: () {},
                onDismiss: () {},
                onStopWaiting: () {},
              ),
            ),
            variant,
          );
          expect(
            find.text(
              code == 'UNSUPPORTED'
                  ? 'Операция не поддерживается в текущем окружении.'
                  : code == 'TIMEOUT'
                  ? 'Ответ локальной службы не получен вовремя.'
                  : 'Локальная служба недоступна. Проверьте её состояние.',
            ),
            findsOneWidget,
          );
          expect(
            find.textContaining('Не удалось выполнить запрос:'),
            findsNothing,
          );
        });
      }
      testWidgets('T036 regression durable uncertain reply ${variant.suffix}', (
        tester,
      ) async {
        await _mount(
          tester,
          SingleChildScrollView(
            child: AutomationStatusSection(
              busy: false,
              openingRecipes: false,
              canRetry: true,
              writeOutcome: AutomationWriteOutcome(
                label: 'План установки',
                errorCode: TrustedLocalError('TIMEOUT').code,
              ),
              pendingLabel: 'План установки',
              onRetry: () {},
              onDismiss: () {},
              onStopWaiting: () {},
            ),
          ),
          variant,
        );
        expect(find.text('Исход записи не подтверждён'), findsOneWidget);
      });
    }
  }
}

void _registerPreflightRegressions(_Variant variant) {
  _registerGenericDraftRegressions(variant);
  _registerProfileDraftRegressions(variant);
  _registerProfileLifecycleRegressions(variant);
  _registerProfileRecoveryRegressions(variant);
  _registerRetainedWriteJourney(variant);
  for (final definitive in ['FORBIDDEN', 'VALIDATION']) {
    testWidgets('T093 write $definitive then read TIMEOUT ${variant.suffix}', (
      tester,
    ) async {
      final operation = AutomationUiOperation();
      String? errorCode, pendingLabel;
      AutomationUiResult result() =>
          AutomationUiResult(errorCode: errorCode, pendingLabel: pendingLabel);
      Widget status() => SingleChildScrollView(
        child: AutomationStatusSection(
          busy: false,
          openingRecipes: false,
          canRetry: true,
          errorCode: operation.readErrorCode,
          writeOutcome: operation.writeOutcome,
          pendingLabel: pendingLabel,
          operationLabel: operation.label,
          onRetry: () {},
          onDismiss: () {},
          onStopWaiting: () {},
        ),
      );
      try {
        await operation.run(AutomationUiPhase.saveProfile, () async {
          pendingLabel = 'Сохранение профиля';
          errorCode = definitive;
        }, result: result);
        await _mount(tester, status(), variant);
        expect(find.text(automationMessage(definitive)), findsOneWidget);
        await operation.run(AutomationUiPhase.profiles, () async {
          errorCode = 'TIMEOUT';
        }, result: result);
        await _mount(tester, status(), variant);
        expect(find.text('Исход записи не подтверждён'), findsNothing);
        expect(find.text(automationMessage(definitive)), findsOneWidget);
        expect(find.text(automationMessage('TIMEOUT')), findsOneWidget);
      } finally {
        operation.dispose();
      }
    });
  }
  testWidgets('T093 unknown write then successful read ${variant.suffix}', (
    tester,
  ) async {
    final operation = AutomationUiOperation();
    String? errorCode, pendingLabel;
    AutomationUiResult result() =>
        AutomationUiResult(errorCode: errorCode, pendingLabel: pendingLabel);
    Widget status() => SingleChildScrollView(
      child: AutomationStatusSection(
        busy: false,
        openingRecipes: false,
        canRetry: true,
        errorCode: operation.readErrorCode,
        writeOutcome: operation.writeOutcome,
        pendingLabel: pendingLabel,
        operationLabel: operation.label,
        onRetry: () {},
        onDismiss: () {},
        onStopWaiting: () {},
      ),
    );
    try {
      await operation.run(AutomationUiPhase.saveProfile, () async {
        pendingLabel = 'Сохранение профиля';
        errorCode = 'TIMEOUT';
      }, result: result);
      await _mount(tester, status(), variant);
      expect(find.text('Исход записи не подтверждён'), findsOneWidget);
      await operation.run(AutomationUiPhase.profiles, () async {
        errorCode = null;
      }, result: result);
      await _mount(tester, status(), variant);
      expect(find.text('Исход записи не подтверждён'), findsOneWidget);
      expect(find.text('Запрос: Сохранение профиля'), findsOneWidget);
    } finally {
      operation.dispose();
    }
  });
  testWidgets(
    'T095 actual automation host has no debug banner ${variant.suffix}',
    (tester) async {
      await _mount(tester, const Text('Automation state host'), variant);
      expect(find.byType(CheckedModeBanner), findsNothing);
    },
  );
}

/// Borrowed owner boundary only. Real production flow/presenter/renderer are
/// exercised; these counters make no native request or authority claim.
class _JsonRecoveryFixture extends ChangeNotifier {
  _JsonRecoveryFixture(this.phase, {String? source})
    : input = TextEditingController(text: source ?? _jsonDraftSource(phase)),
      submission = AutomationJsonDraftSubmission(phase);
  final AutomationUiPhase phase;
  final TextEditingController input;
  final AutomationJsonDraftSubmission submission;
  final operation = AutomationUiOperation();
  bool busy = false, current = true, live = true, admit = true;
  bool changeReadback = false;
  bool throwBeforeAdmission = false;
  bool targetsAvailable = true, submissionDisposed = false;
  bool overwriteGlobalAfterSnapshot = false;
  String? pending, error, nextError = 'VALIDATION';
  AutomationUiResult? completed;
  int submits = 0, retries = 0, dismisses = 0, closes = 0;
  Object? identity;
  Map<String, Object?>? payload;
  final identities = <Object?>[];
  Completer<void>? gate;
  AutomationUiResult result() =>
      AutomationUiResult(errorCode: error, pendingLabel: pending);
  AutomationUiResult captureResult() {
    final snapshot = result();
    completed = snapshot;
    if (overwriteGlobalAfterSnapshot) error = 'FORBIDDEN';
    return snapshot;
  }

  Map<String, Object?> get counters => {
    'newSubmits': submits,
    'exactRetries': retries,
    'dismisses': dismisses,
    'closeCallbacks': closes,
    'sameIdentity': identities.every((id) => identical(id, identities.first)),
  };
  Future<void> _work() async {
    busy = true;
    error = null;
    if (phase.durable) pending = phase.label;
    if (gate != null) {
      await gate!.future;
    } else {
      await Future<void>.value();
    }
    error = nextError;
    if (phase.durable && error == null) pending = null;
    if (changeReadback && error == null) current = false;
    busy = false;
  }

  Future<void> submit() => submission.submit(
    source: input.text,
    current: () => current && live,
    completionCurrent: () => live,
    canSubmit: () => !busy && (!phase.durable || pending == null),
    targetsAvailable: (_) => targetsAvailable,
    submit: (value, admitted) {
      if (!admit) return Future<void>.value();
      if (throwBeforeAdmission) {
        final dynamic wrongType = 'synthetic raw exception never shown';
        wrongType as int;
      }
      submits++;
      identity = Object();
      identities.add(identity);
      payload = value;
      completed = null;
      return operation.run(
        phase,
        _work,
        result: captureResult,
        admitted: () {
          if (busy) admitted();
          return busy;
        },
      );
    },
    result: () => completed,
    close: () {
      closes++;
      notifyListeners();
    },
  );
  Future<void> retry() => submission.retrySaved(
    current: () => current && live,
    completionCurrent: () => live,
    canRetry: () => !busy && pending != null,
    retry: (admitted) {
      retries++;
      identities.add(identity);
      completed = null;
      return operation.run(
        AutomationUiPhase.retry,
        _work,
        result: captureResult,
        admitted: () {
          if (busy) admitted();
          return busy;
        },
      );
    },
    result: () => completed,
    close: () {
      closes++;
      notifyListeners();
    },
  );
  void dismiss() => submission.dismissSaved(
    completionCurrent: () => live,
    dismiss: () => operation.dismiss(() {
      if (!busy) {
        dismisses++;
        pending = error = null;
      }
    }, result),
    pendingLabel: () => pending,
  );
  Widget editor() => ListenableBuilder(
    listenable: Listenable.merge([this, submission, operation]),
    builder: (_, _) {
      submission.observe(current: current && live, pendingLabel: pending);
      if (closes != 0) return const Text('JSON editor closed');
      return AutomationJsonEditorDialog(
        title: 'T099 JSON',
        input: input,
        error: submission.error,
        saving: submission.saving,
        requestRetained: submission.requestRetained,
        contextCurrent: current && !submission.retired,
        canContinue: !busy && (!phase.durable || pending == null),
        ownerStatus: !(submission.saving || submission.requestRetained)
            ? null
            : AutomationStatusSection(
                busy: submission.saving,
                openingRecipes: false,
                canRetry:
                    current &&
                    !submission.retired &&
                    !busy &&
                    submission.requestRetained,
                pendingLabel: submission.requestRetained ? phase.label : null,
                writeOutcome: submission.writeOutcome,
                errorCode: phase.durable ? null : submission.errorCode,
                operationLabel: submission.saving ? phase.label : null,
                onRetry: () => retry().ignore(),
                onDismiss: dismiss,
                onStopWaiting: () {},
              ),
        onClose: () {
          live = false;
          closes++;
          notifyListeners();
        },
        onContinue: () => submit().ignore(),
      );
    },
  );
  @override
  void dispose() {
    live = false;
    if (!submissionDisposed) submission.dispose();
    operation.dispose();
    input.dispose();
    super.dispose();
  }
}

String _jsonDraftSource(AutomationUiPhase phase) =>
    '  ${jsonEncode(switch (phase) {
      AutomationUiPhase.createPlan => {'greeting': 0},
      // A legal client draft still exercises a delayed owner VALIDATION result
      // (for example a state/policy change), after pre-admission validation.
      AutomationUiPhase.delegate => {..._input('39-delegations'), 'lifetimeSeconds': 3600},
      AutomationUiPhase.version => {'revision': 1},
      AutomationUiPhase.compare => {'fromRevision': 1, 'toRevision': 1},
      _ => {..._input('37-ai-grant-form'), 'label': 'Точный черновик 日本語', 'lifetimeSeconds': 0},
    })}\n ';

Future<void> _captureJsonCheckpoint(
  WidgetTester tester,
  _Variant variant,
  _JsonRecoveryFixture fixture,
  String phase, {
  DesignStateCategory category = DesignStateCategory.validation,
}) => captureDesignState(
  tester,
  family: 'automation',
  caseIds: [
    designStateCases
        .firstWhere(
          (item) =>
              item.originId ==
                  switch (fixture.phase) {
                    AutomationUiPhase.version ||
                    AutomationUiPhase.compare => '34-profile-revisions',
                    AutomationUiPhase.createPlan => '35-plan-parameters',
                    AutomationUiPhase.delegate => '39-delegations',
                    _ => '37-ai-grant-form',
                  } &&
              item.category == category,
        )
        .caseId,
  ],
  phase: phase,
  theme: variant.dark ? 'dark' : 'light',
  scale: variant.scale,
  counters: fixture.counters,
  assertions: [
    'Actual shared JSON submission flow, production operation presenter and production renderer; same route controller preserves exact text.',
    'Only explicit admitted borrowed callbacks affect close or retained-request presentation; no automatic dispatch.',
  ],
  scope: 'Additional T099 generic-editor provider checkpoint; controlled borrowed owner callback, no native request, service validation or authority proof.',
);

void _registerGenericRecoveryJourneys(_Variant variant) {
  testWidgets(
    'T160 delegation original zero-TTL draft rejects before admission ${variant.suffix}',
    (tester) async {
      // Preserve the original T099 zero-TTL input at its real admission stage;
      // the delayed recovery journey above keeps a valid client-side request.
      final text =
          '  ${jsonEncode({..._input('39-delegations'), 'lifetimeSeconds': 0})}\n ';
      final fixture = _JsonRecoveryFixture(
        AutomationUiPhase.delegate,
        source: text,
      );
      try {
        await _mount(tester, fixture.editor(), variant);
        await _click(tester, 'Продолжить');
        expect(fixture.submits, 0);
        expect(fixture.closes, 0);
        expect(fixture.pending, isNull);
        expect(fixture.identity, isNull);
        expect(fixture.identities, isEmpty);
        expect(fixture.submission.saving, isFalse);
        expect(fixture.submission.requestRetained, isFalse);
        expect(fixture.submission.error, automationDraftInputError());
        expect(fixture.input.text, text);
        expect(
          tester
              .widget<TextField>(await _showDraftField(tester, fixture.input))
              .enabled,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
      }
    },
  );
  testWidgets(
    'T099 pre-dispatch target rejection preserves draft ${variant.suffix}',
    (tester) async {
      final fixture = _JsonRecoveryFixture(AutomationUiPhase.createPlan)
        ..targetsAvailable = false;
      final text = fixture.input.text;
      try {
        await _mount(tester, fixture.editor(), variant);
        await _click(tester, 'Продолжить');
        expect(fixture.submits, 0);
        expect(fixture.closes, 0);
        expect(fixture.input.text, text);
        expect(
          fixture.submission.error,
          'Не удалось проверить целевые серверы. Проверьте локальные профили и идентификаторы.',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
      }
    },
  );
  testWidgets(
    'T099 captured own result survives later global error ${variant.suffix}',
    (tester) async {
      final fixture = _JsonRecoveryFixture(AutomationUiPhase.version)
        ..nextError = null
        ..overwriteGlobalAfterSnapshot = true;
      try {
        await _mount(tester, fixture.editor(), variant);
        await _click(tester, 'Продолжить');
        expect(fixture.closes, 1);
        expect(fixture.completed!.errorCode, isNull);
        expect(fixture.error, 'FORBIDDEN');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
      }
    },
  );
  testWidgets(
    'T099 disposed shared form ignores late completion ${variant.suffix}',
    (tester) async {
      final fixture = _JsonRecoveryFixture(AutomationUiPhase.saveGrant)
        ..gate = Completer<void>();
      try {
        await _mount(tester, fixture.editor(), variant);
        await _click(tester, 'Продолжить');
        await tester.pumpWidget(const SizedBox.shrink());
        var notifications = 0;
        fixture.submission.addListener(() => notifications++);
        fixture.submission.dispose();
        fixture.submissionDisposed = true;
        fixture.gate!.complete();
        await tester.pumpAndSettle();
        expect(fixture.closes, 0);
        expect(notifications, 0);
        expect(tester.takeException(), isNull);
      } finally {
        if (!fixture.gate!.isCompleted) fixture.gate!.complete();
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
      }
    },
  );
  for (final phase in [
    AutomationUiPhase.createPlan,
    AutomationUiPhase.replaceGrant,
    AutomationUiPhase.delegate,
  ]) {
    testWidgets(
      'T099 ${phase.name} delayed semantic validation ${variant.suffix}',
      (tester) async {
        final fixture = _JsonRecoveryFixture(phase)..gate = Completer<void>();
        final text = fixture.input.text;
        try {
          await _mount(tester, fixture.editor(), variant);
          final original = tester
              .widget<FilledButton>(_button('Продолжить'))
              .onPressed!;
          original();
          original();
          await tester.pumpAndSettle();
          expect(fixture.submits, 1);
          expect(fixture.closes, 0);
          expect(fixture.submission.saving, isTrue);
          expect(
            tester
                .widget<TextField>(await _showDraftField(tester, fixture.input))
                .enabled,
            isFalse,
          );
          fixture.gate!.complete();
          await tester.pumpAndSettle();
          expect(fixture.submission.requestRetained, isTrue);
          expect(fixture.submission.error, automationMessage('VALIDATION'));
          expect(fixture.input.text, text);
          expect(fixture.closes, 0);
          original();
          await tester.pumpAndSettle();
          expect(fixture.submits, 1);
          await tester.ensureVisible(
            await _showDraftField(tester, fixture.input),
          );
          await tester.pumpAndSettle();
          await _captureJsonCheckpoint(
            tester,
            variant,
            fixture,
            't099-${phase.name.toLowerCase()}-retained-validation',
          );
        } finally {
          if (!fixture.gate!.isCompleted) fixture.gate!.complete();
          await tester.pumpWidget(const SizedBox.shrink());
          fixture.dispose();
        }
      },
    );
  }
  testWidgets(
    'T099 own retained exact retry dismiss corrected explicit submit ${variant.suffix}',
    (tester) async {
      final fixture = _JsonRecoveryFixture(AutomationUiPhase.saveGrant);
      final originalText = fixture.input.text;
      try {
        await _mount(tester, fixture.editor(), variant);
        await _click(tester, 'Продолжить');
        final originalIdentity = fixture.identity,
            originalPayload = fixture.payload;
        fixture.nextError = 'TIMEOUT';
        await _click(tester, 'Повторить тот же запрос');
        expect(fixture.retries, 1);
        expect(fixture.submits, 1);
        expect(fixture.identity, same(originalIdentity));
        expect(fixture.payload, same(originalPayload));
        expect(fixture.identities, everyElement(same(originalIdentity)));
        expect(fixture.input.text, originalText);
        expect(fixture.submission.writeOutcome!.unconfirmed, isTrue);
        await _captureJsonCheckpoint(
          tester,
          variant,
          fixture,
          't099-grant-exact-retry-unknown',
          category: DesignStateCategory.unknown,
        );
        await _click(tester, 'Закрыть запрос');
        expect(fixture.dismisses, 1);
        expect(fixture.submits, 1);
        expect(fixture.submission.requestRetained, isFalse);
        expect(fixture.input.text, originalText);
        expect(
          tester
              .widget<TextField>(await _showDraftField(tester, fixture.input))
              .enabled,
          isTrue,
        );
        await _captureJsonCheckpoint(
          tester,
          variant,
          fixture,
          't099-grant-dismissed-exact-draft',
        );
        await tester.enterText(
          await _showDraftField(tester, fixture.input),
          '  ${jsonEncode({..._input('37-ai-grant-form'), 'label': 'Исправлено 日本語', 'lifetimeSeconds': 3600})}\n ',
        );
        expect(fixture.submits, 1);
        fixture.nextError = null;
        await _click(tester, 'Продолжить');
        expect(fixture.submits, 2);
        expect(fixture.closes, 1);
        expect(identical(fixture.identity, originalIdentity), isFalse);
        expect(fixture.payload!['lifetimeSeconds'], 3600);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
      }
    },
  );
  for (final phase in [AutomationUiPhase.version, AutomationUiPhase.compare]) {
    testWidgets(
      'T099 ${phase.name} validation preserves unrelated pending ${variant.suffix}',
      (tester) async {
        final fixture = _JsonRecoveryFixture(phase)..pending = 'Чужая запись';
        final text = fixture.input.text;
        try {
          await _mount(tester, fixture.editor(), variant);
          await _click(tester, 'Продолжить');
          expect(fixture.closes, 0);
          expect(fixture.input.text, text);
          expect(fixture.submission.error, automationMessage('VALIDATION'));
          expect(fixture.submission.requestRetained, isFalse);
          expect(fixture.pending, 'Чужая запись');
          expect(
            tester
                .widget<TextField>(await _showDraftField(tester, fixture.input))
                .enabled,
            isTrue,
          );
          expect(find.text('Повторить тот же запрос'), findsNothing);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          fixture.dispose();
        }
      },
    );
    testWidgets(
      'T099 ${phase.name} own read ignores unrelated retained write ${variant.suffix}',
      (tester) async {
        final fixture = _JsonRecoveryFixture(phase, source: '{"revision":1}')
          ..pending = 'Чужая запись'
          ..error = 'TIMEOUT'
          ..nextError = null
          ..gate = Completer<void>();
        try {
          await fixture.operation.run(
            AutomationUiPhase.saveProfile,
            () async {},
            result: () => const AutomationUiResult(
              errorCode: 'TIMEOUT',
              pendingLabel: 'Чужая запись',
            ),
          );
          final unrelated = fixture.operation.writeOutcome;
          await _mount(tester, fixture.editor(), variant);
          await _click(tester, 'Продолжить');
          expect(fixture.submits, 1);
          expect(fixture.submission.requestRetained, isFalse);
          expect(find.text('Исход записи не подтверждён'), findsNothing);
          await _captureJsonCheckpoint(
            tester,
            variant,
            fixture,
            't099-${phase.name}-own-read-with-unrelated-write',
            category: DesignStateCategory.loading,
          );
          fixture.gate!.complete();
          await tester.pumpAndSettle();
          expect(fixture.closes, 1);
          expect(fixture.pending, 'Чужая запись');
          expect(fixture.operation.writeOutcome, same(unrelated));
        } finally {
          if (!fixture.gate!.isCompleted) fixture.gate!.complete();
          await tester.pumpWidget(const SizedBox.shrink());
          fixture.dispose();
        }
      },
    );
  }
  testWidgets('T099 no-op does not adopt old global result ${variant.suffix}', (
    tester,
  ) async {
    final fixture = _JsonRecoveryFixture(AutomationUiPhase.version)
      ..admit = false
      ..error = 'FORBIDDEN'
      ..pending = 'Чужая запись';
    try {
      await _mount(tester, fixture.editor(), variant);
      await _click(tester, 'Продолжить');
      expect(fixture.submits, 0);
      expect(fixture.closes, 0);
      expect(fixture.submission.error, isNull);
      expect(fixture.submission.requestRetained, isFalse);
      expect(fixture.error, 'FORBIDDEN');
      expect(fixture.pending, 'Чужая запись');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    }
  });
  for (final malformed in [false, true]) {
    testWidgets(
      'T099 synchronous ${malformed ? 'JSON' : 'type'} failure stays in form ${variant.suffix}',
      (tester) async {
        final fixture = _JsonRecoveryFixture(AutomationUiPhase.delegate)
          ..throwBeforeAdmission = !malformed;
        if (malformed) fixture.input.text = ' { "not-complete": ';
        final text = fixture.input.text;
        try {
          await _mount(tester, fixture.editor(), variant);
          await _click(tester, 'Продолжить');
          expect(fixture.submits, 0);
          expect(fixture.closes, 0);
          expect(fixture.input.text, text);
          expect(fixture.submission.error, automationDraftInputError());
          expect(find.textContaining('synthetic raw exception'), findsNothing);
          expect(fixture.submission.requestRetained, isFalse);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          fixture.dispose();
        }
      },
    );
  }
  testWidgets(
    'T099 own successful readback closes without renewed context consent ${variant.suffix}',
    (tester) async {
      final fixture = _JsonRecoveryFixture(AutomationUiPhase.replaceGrant)
        ..nextError = null
        ..changeReadback = true;
      try {
        await _mount(tester, fixture.editor(), variant);
        await _click(tester, 'Продолжить');
        expect(fixture.submits, 1);
        expect(fixture.closes, 1);
        expect(fixture.pending, isNull);
        expect(fixture.current, isFalse);
        fixture.current = true;
        await fixture.submit();
        expect(
          fixture.submits,
          1,
          reason: 'Readback retirement never renews dispatch consent.',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
      }
    },
  );
  for (final retirement in [
    'close',
    'owner-replacement',
    'private-epoch',
    'context',
  ]) {
    testWidgets(
      'T099 late result after $retirement is ignored ${variant.suffix}',
      (tester) async {
        final fixture = _JsonRecoveryFixture(AutomationUiPhase.saveGrant)
          ..gate = Completer<void>();
        try {
          await _mount(tester, fixture.editor(), variant);
          await _click(tester, 'Продолжить');
          if (retirement == 'context') {
            fixture.current = false;
          } else {
            fixture.live = false;
          }
          fixture.submission.observe(
            current: false,
            pendingLabel: fixture.pending,
          );
          var notifications = 0;
          fixture.submission.addListener(() => notifications++);
          fixture.gate!.complete();
          await tester.pumpAndSettle();
          expect(fixture.closes, 0);
          expect(fixture.submission.error, isNull);
          expect(notifications, retirement == 'context' ? 1 : 0);
          fixture.current = fixture.live = true;
          await fixture.submit();
          expect(fixture.submits, 1);
        } finally {
          if (!fixture.gate!.isCompleted) fixture.gate!.complete();
          await tester.pumpWidget(const SizedBox.shrink());
          fixture.dispose();
        }
      },
    );
  }
}

void _registerGenericDraftRegressions(_Variant variant) {
  _registerGenericRecoveryJourneys(variant);
  testWidgets(
    'T099 shared JSON delayed VALIDATION retains draft ${variant.suffix}',
    (tester) async {
      final fixture = _JsonRecoveryFixture(AutomationUiPhase.saveGrant)
        ..gate = Completer<void>();
      final text = fixture.input.text;
      try {
        await _mount(tester, fixture.editor(), variant);
        await _click(tester, 'Продолжить');
        expect(fixture.submits, 1);
        expect(
          fixture.closes,
          0,
          reason: 'Own delayed result must leave the actual JSON editor open.',
        );
        fixture.gate!.complete();
        await tester.pumpAndSettle();
        expect(fixture.closes, 0);
        expect(find.byType(AutomationJsonEditorDialog), findsOneWidget);
        expect(
          tester
              .widget<TextField>(await _showDraftField(tester, fixture.input))
              .controller,
          same(fixture.input),
        );
        expect(fixture.input.text, text);
        expect(
          tester
              .widget<TextField>(await _showDraftField(tester, fixture.input))
              .decoration!
              .errorText,
          automationMessage('VALIDATION'),
        );
        await tester.ensureVisible(
          await _showDraftField(tester, fixture.input),
        );
        await tester.pumpAndSettle();
        await _captureJsonCheckpoint(
          tester,
          variant,
          fixture,
          't099-savegrant-retained-validation',
        );
      } finally {
        if (!fixture.gate!.isCompleted) fixture.gate!.complete();
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
      }
    },
  );
}

class _ProfileRecoveryFixture {
  _ProfileRecoveryFixture({AutomationProfileBasis? initial})
    : submission = AutomationProfileDraftSubmission(initialBasis: initial),
      profile = initial?.profile,
      revision = initial == null
          ? null
          : DesignAutomationFixtures.revision(number: initial.revision);
  final AutomationProfileDraftSubmission submission;
  final operation = AutomationUiOperation();
  final name = TextEditingController(text: 'Черновик');
  final description = TextEditingController(text: 'Описание черновика');
  final source = jsonEncode(DesignAutomationFixtures.body());
  late final body = TextEditingController(text: source);
  AutomationProfileRecord? profile;
  Map<String, Object?>? revision, payload;
  AutomationProfileBasis? nextBasis;
  String? pending, error;
  String nextWrite = 'TIMEOUT';
  String? nextRead;
  bool busy = false, current = true;
  int saves = 0, retries = 0, reads = 0, dismisses = 0, closes = 0;
  Object? identity;
  final identities = <Object?>[];
  Completer<void>? readGate;
  AutomationUiResult result() =>
      AutomationUiResult(errorCode: error, pendingLabel: pending);
  bool basisCurrent(AutomationProfileBasis basis) =>
      basis.matches(profile, revision);
  Map<String, Object?> get counters => {
    'saves': saves,
    'sameRequestRetries': retries,
    'reads': reads,
    'dismisses': dismisses,
    'closeCallbacks': closes,
  };
  Future<void> _write() async {
    busy = true;
    pending = 'Сохранение профиля';
    error = null;
    await Future<void>.value();
    error = nextWrite == 'success' ? null : nextWrite;
    if (error == null) pending = null;
    busy = false;
  }

  Future<void> save() => submission.save(
    name: name.text,
    description: description.text,
    source: body.text,
    current: () => current,
    canSubmit: () => !busy && pending == null,
    basisCurrent: basisCurrent,
    submit: (n, d, value) {
      saves++;
      identity = Object();
      identities.add(identity);
      payload = {
        'name': n,
        'description': d,
        'body': value,
        'expectedRevision': submission.currentBasis?.profile.headRevision,
      };
      return operation.run(
        AutomationUiPhase.saveProfile,
        _write,
        result: result,
        admitted: () => busy,
      );
    },
    resultError: () => error,
    pendingLabel: () => pending,
    close: () => closes++,
  );
  Future<void> retry() => submission.retrySaved(
    retry: () {
      retries++;
      identities.add(identity);
      return operation.run(
        AutomationUiPhase.retry,
        _write,
        result: result,
        admitted: () => busy,
      );
    },
    canRetry: () => !busy && pending != null,
    current: () => current,
    resultError: () => error,
    pendingLabel: () => pending,
    close: () => closes++,
  );
  void dismiss() => submission.dismissSaved(
    dismiss: () => operation.dismiss(() {
      if (!busy) {
        dismisses++;
        pending = error = null;
      }
    }, result),
    pendingLabel: () => pending,
  );
  Future<void> read() => submission.readBasis(
    current: () => current,
    canRead: () => !busy && pending == null,
    pendingLabel: () => pending,
    read: () async {
      reads++;
      await operation.run(
        AutomationUiPhase.version,
        () async {
          busy = true;
          error = null;
          if (readGate != null) {
            await readGate!.future;
          } else {
            await Future<void>.value();
          }
          error = nextRead;
          if (error == null && nextBasis != null) {
            profile = nextBasis!.profile;
            revision = DesignAutomationFixtures.revision(
              number: nextBasis!.revision,
            );
          }
          busy = false;
        },
        result: result,
        admitted: () => busy,
      );
      return error == null ? nextBasis : null;
    },
  );
  bool accept() => submission.acceptBasis(
    current: () => current,
    canAccept: () => !busy && pending == null,
    unchanged: basisCurrent,
  );
  void observe() =>
      submission.observeBasis(current: current, unchanged: basisCurrent);
  Widget editor() => ListenableBuilder(
    listenable: Listenable.merge([submission, operation]),
    builder: (_, _) {
      observe();
      return AutomationProfileEditorDialog(
        name: name,
        description: description,
        body: body,
        existing: submission.currentBasis?.profile,
        baseRevision: submission.initialBasis?.revision,
        validating: false,
        saving: submission.saving,
        canValidate: !busy,
        contextCurrent: current && !submission.contextRetired,
        requestRetained: pending != null,
        canSave: !busy && pending == null && !submission.requiresNewBasis,
        onBodyChanged: (_) {},
        onClose: () {},
        onValidate: () {},
        onSave: () => save().ignore(),
        ownerStatus: AutomationStatusSection(
          busy: busy,
          openingRecipes: false,
          canRetry: !busy && pending != null,
          pendingLabel: pending,
          errorCode: operation.readErrorCode,
          writeOutcome: operation.writeOutcome,
          operationLabel: operation.label,
          onRetry: () => retry().ignore(),
          onDismiss: dismiss,
          onStopWaiting: () {},
        ),
        basisReview: AutomationProfileBasisReview(
          submission: submission,
          canRead: current && !busy && pending == null,
          canAccept: current && !busy && pending == null,
          requestRetained: pending != null,
          onRead: () => read().ignore(),
          onAccept: accept,
        ),
      );
    },
  );
  void dispose() {
    submission.dispose();
    operation.dispose();
    name.dispose();
    description.dispose();
    body.dispose();
  }
}

Future<void> _captureProfileCheckpoint(
  WidgetTester tester,
  _Variant variant,
  String phase,
  Map<String, Object?> counters,
  List<String> assertions, {
  DesignStateCategory category = DesignStateCategory.validation,
}) => captureDesignState(
  tester,
  family: 'automation',
  caseIds: [
    designStateCases
        .firstWhere(
          (c) => c.originId == '33-profile-authoring' && c.category == category,
        )
        .caseId,
  ],
  phase: phase.toLowerCase().replaceAll('_', '-'),
  theme: variant.dark ? 'dark' : 'light',
  scale: variant.scale,
  counters: counters,
  assertions: assertions,
  scope: 'Additional actual profile-editor presentation checkpoint for T094/T096/T097; borrowed callback boundaries, no native execution/authority proof.',
  limitations: [
    'DTO/result fixtures, not a TrustedApiClient or service/RPC journey.',
  ],
);

void _registerProfileRecoveryRegressions(_Variant variant) {
  testWidgets(
    'T097 retained request actions stay inside actual editor ${variant.suffix}',
    (tester) async {
      final fixture = _ProfileRecoveryFixture();
      try {
        await _mount(tester, fixture.editor(), variant);
        final retainedSave = tester
            .widget<ButtonStyleButton>(_button('Сохранить версию'))
            .onPressed!;
        await _click(tester, 'Сохранить версию');
        expect(fixture.saves, 1);
        expect(fixture.closes, 0);
        final editor = find.byType(AutomationProfileEditorDialog);
        for (final text in ['Повторить тот же запрос', 'Закрыть запрос']) {
          expect(
            find.descendant(of: editor, matching: find.text(text)),
            findsOneWidget,
          );
        }
        expect(
          tester
              .widget<TextField>(
                find.byWidgetPredicate(
                  (w) =>
                      w is TextField && identical(w.controller, fixture.name),
                ),
              )
              .enabled,
          isFalse,
        );
        retainedSave();
        await tester.pumpAndSettle();
        expect(fixture.saves, 1);
        await _captureProfileCheckpoint(
          tester,
          variant,
          't097-unknown-retained-in-editor',
          fixture.counters,
          [
            'Actual editor contains retained-request actions; locked fields preserve exact sent draft.',
            'No automatic new save or read.',
          ],
          category: DesignStateCategory.unknown,
        );
        await fixture.read(); // unknown cannot enable CAS recovery
        expect(fixture.reads, 0);
        expect(fixture.submission.candidateBasis, isNull);
        await fixture.operation.run(AutomationUiPhase.profiles, () async {
          fixture.error = null;
        }, result: fixture.result);
        await tester.pumpAndSettle();
        expect(fixture.closes, 0);
        expect(find.text('Исход записи не подтверждён'), findsOneWidget);
        fixture.nextWrite = 'VALIDATION';
        await _click(tester, 'Повторить тот же запрос');
        expect(fixture.retries, 1);
        expect(fixture.saves, 1);
        expect(fixture.identities[1], same(fixture.identities[0]));
        await _click(tester, 'Закрыть запрос');
        expect(fixture.dismisses, 1);
        expect(fixture.name.text, 'Черновик');
        expect(fixture.description.text, 'Описание черновика');
        expect(fixture.body.text, fixture.source);
        await _captureProfileCheckpoint(
          tester,
          variant,
          't097-dismiss-retains-editable-draft',
          fixture.counters,
          [
            'Explicit owner dismiss retains all draft controllers; no physical-cancel claim.',
            'Fields become editable only after retained request retirement.',
          ],
        );
        fixture.nextWrite = 'TIMEOUT';
        await _click(tester, 'Сохранить версию');
        expect(fixture.saves, 2);
        fixture.nextWrite = 'success';
        await _click(tester, 'Повторить тот же запрос');
        expect(fixture.retries, 2);
        expect(fixture.closes, 1);
        expect(fixture.identities[3], same(fixture.identities[2]));
        expect(fixture.pending, isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
      }
    },
  );
  testWidgets(
    'T097 definitive CAS read explicit basis acceptance preserves draft ${variant.suffix}',
    (tester) async {
      final originalRevision = DesignAutomationFixtures.revision(number: 1);
      final initial = AutomationProfileBasis(
        profile: DesignAutomationFixtures.profile(),
        revision: 1,
        digest: originalRevision['digest'] as String,
      );
      final fixture = _ProfileRecoveryFixture(initial: initial)
        ..nextWrite = 'REVISION_CONFLICT';
      fixture.nextBasis = AutomationProfileBasis(
        profile: DesignAutomationFixtures.profile(headRevision: 3),
        revision: 3,
        digest:
            DesignAutomationFixtures.revision(number: 3)['digest'] as String,
      );
      try {
        await _mount(tester, fixture.editor(), variant);
        await _click(tester, 'Сохранить версию');
        expect(fixture.saves, 1);
        expect(fixture.reads, 0);
        expect(fixture.closes, 0);
        expect(fixture.payload!['expectedRevision'], 2);
        await _captureProfileCheckpoint(
          tester,
          variant,
          't097-cas-retained-in-editor',
          fixture.counters,
          [
            'Definitive write CAS is distinct from read errors and unknown write.',
            'Original selected revision 1 and expected head 2 remain separate.',
          ],
        );
        expect(
          tester
              .widget<ButtonStyleButton>(_button('Перечитать текущую версию'))
              .onPressed,
          isNull,
        );
        await fixture.read();
        expect(fixture.reads, 0);
        expect(fixture.accept(), isFalse);
        await _click(tester, 'Закрыть запрос');
        expect(fixture.name.text, 'Черновик');
        expect(fixture.body.text, fixture.source);
        expect(fixture.submission.requiresNewBasis, isTrue);
        fixture.readGate = Completer<void>();
        final retainedRead = tester
            .widget<ButtonStyleButton>(_button('Перечитать текущую версию'))
            .onPressed!;
        await _click(tester, 'Перечитать текущую версию');
        retainedRead();
        await tester.pumpAndSettle();
        expect(fixture.reads, 1);
        fixture.readGate!.complete();
        await tester.pumpAndSettle();
        expect(fixture.reads, 1);
        expect(fixture.saves, 1);
        expect(fixture.closes, 0);
        expect(fixture.submission.candidateBasis!.revision, 3);
        expect(fixture.submission.acceptedBasis, isNull);
        await tester.ensureVisible(
          _button('Принять текущую версию как основу'),
        );
        await tester.pumpAndSettle();
        await _captureProfileCheckpoint(
          tester,
          variant,
          't097-cas-current-revision-read',
          fixture.counters,
          [
            'Explicit dismiss retained draft before the single explicit read.',
            'Successful read exposes current revision/digest without accepting or closing editor.',
          ],
        );
        await _click(tester, 'Принять текущую версию как основу');
        expect(fixture.submission.acceptedBasis!.profile.headRevision, 3);
        expect(fixture.submission.initialBasis!.revision, 1);
        expect(fixture.saves, 1);
        expect(fixture.reads, 1);
        expect(fixture.closes, 0);
        expect(fixture.name.text, 'Черновик');
        expect(fixture.body.text, fixture.source);
        await _captureProfileCheckpoint(
          tester,
          variant,
          't097-cas-base-explicitly-accepted',
          fixture.counters,
          [
            'Explicit acceptance changes only expected head to 3; original revision 1 and draft body are unchanged.',
            'Read/accept perform zero additional saves.',
          ],
        );
        fixture.nextWrite = 'success';
        await _click(tester, 'Сохранить версию');
        expect(fixture.saves, 2);
        expect(fixture.payload!['expectedRevision'], 3);
        expect(fixture.payload!['body'], DesignAutomationFixtures.body());
        expect(fixture.closes, 1);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
      }
    },
  );
}

void _registerProfileLifecycleRegressions(_Variant variant) {
  testWidgets('T094 actual fields retain over-limit input ${variant.suffix}', (
    tester,
  ) async {
    final name = TextEditingController(), description = TextEditingController();
    final source = jsonEncode(DesignAutomationFixtures.body());
    final body = TextEditingController(text: source);
    final submission = AutomationProfileDraftSubmission();
    var dispatches = 0, closes = 0;
    try {
      await _mount(
        tester,
        ListenableBuilder(
          listenable: submission,
          builder: (_, _) => AutomationProfileEditorDialog(
            name: name,
            description: description,
            body: body,
            validating: false,
            saving: submission.saving,
            canValidate: true,
            nameError: submission.nameError,
            descriptionError: submission.descriptionError,
            onBodyChanged: (_) {},
            onValidate: () {},
            onClose: () {},
            onSave: () => submission
                .save(
                  name: name.text,
                  description: description.text,
                  source: body.text,
                  current: () => true,
                  submit: (n, d, body) async {
                    dispatches++;
                  },
                  resultError: () => null,
                  close: () => closes++,
                )
                .ignore(),
          ),
        ),
        variant,
      );
      final nameInput = find.byWidgetPredicate(
        (w) => w is TextField && identical(w.controller, name),
      );
      final descriptionInput = find.byWidgetPredicate(
        (w) => w is TextField && identical(w.controller, description),
      );
      expect(
        tester.widget<TextField>(nameInput).maxLength,
        isNull,
        reason: 'No grapheme counter can misrepresent the protocol rune limit.',
      );
      expect(tester.widget<TextField>(descriptionInput).maxLength, isNull);
      await tester.enterText(nameInput, 'a' * 101);
      await tester.enterText(descriptionInput, 'a' * 2001);
      FocusManager.instance.primaryFocus?.unfocus();
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await _click(tester, 'Сохранить версию');
      expect(name.text, 'a' * 101);
      expect(description.text, 'a' * 2001);
      expect(body.text, source);
      expect(dispatches, 0);
      expect(closes, 0);
      expect(
        tester.widget<TextField>(nameInput).decoration!.errorText,
        isNotNull,
      );
      expect(
        tester.widget<TextField>(descriptionInput).decoration!.errorText,
        isNotNull,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      submission.dispose();
      name.dispose();
      description.dispose();
      body.dispose();
    }
  });
  testWidgets(
    'T094 closed actual route ignores late save but retains owner result ${variant.suffix}',
    (tester) async {
      final name = TextEditingController(text: 'Профиль'),
          description = TextEditingController(text: 'Описание');
      final body = TextEditingController(
        text: jsonEncode(DesignAutomationFixtures.body()),
      );
      final submission = AutomationProfileDraftSubmission(),
          operation = AutomationUiOperation();
      final gate = Completer<void>();
      Future<void>? saved;
      String? ownerError, pending;
      var dispatches = 0, closeRequests = 0, successCloses = 0;
      try {
        await _mount(
          tester,
          Builder(
            builder: (context) => ListenableBuilder(
              listenable: operation,
              builder: (_, _) => _scroll(
                Column(
                  children: [
                    FilledButton(
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (dialog) => ListenableBuilder(
                            listenable: submission,
                            builder: (_, _) => AutomationProfileEditorDialog(
                              name: name,
                              description: description,
                              body: body,
                              validating: false,
                              saving: submission.saving,
                              canValidate: !submission.saving,
                              saveError: submission.saveError,
                              onBodyChanged: (_) {},
                              onValidate: () {},
                              onClose: () {
                                closeRequests++;
                                Navigator.pop(dialog);
                              },
                              onSave: () {
                                saved = submission.save(
                                  name: name.text,
                                  description: description.text,
                                  source: body.text,
                                  current: () => dialog.mounted,
                                  submit: (n, d, value) => operation.run(
                                    AutomationUiPhase.saveProfile,
                                    () async {
                                      dispatches++;
                                      pending = 'Сохранение профиля';
                                      await gate.future;
                                      ownerError = 'REVISION_CONFLICT';
                                    },
                                    result: () => AutomationUiResult(
                                      errorCode: ownerError,
                                      pendingLabel: pending,
                                    ),
                                  ),
                                  resultError: () => ownerError,
                                  close: () {
                                    successCloses++;
                                    Navigator.pop(dialog);
                                  },
                                );
                                saved!.ignore();
                              },
                            ),
                          ),
                        ).whenComplete(submission.dispose).ignore();
                      },
                      child: const Text('Открыть форму'),
                    ),
                    AutomationStatusSection(
                      busy: operation.label != null,
                      openingRecipes: false,
                      canRetry: false,
                      operationLabel: operation.label,
                      pendingLabel: pending,
                      errorCode: operation.readErrorCode,
                      writeOutcome: operation.writeOutcome,
                      onRetry: () {},
                      onDismiss: () {},
                      onStopWaiting: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
          variant,
        );
        await _click(tester, 'Открыть форму');
        await _click(tester, 'Сохранить версию');
        expect(dispatches, 1);
        expect(successCloses, 0);
        for (final field in find.byType(TextField).evaluate()) {
          final input = field.widget as TextField;
          // Readonly context remains selectable; mutating editors stay blocked.
          if (input.readOnly) {
            expect(input.onChanged, isNull);
            expect(input.onSubmitted, isNull);
          } else {
            expect(input.enabled, isFalse);
          }
        }
        await _click(tester, 'Закрыть');
        expect(closeRequests, 1);
        expect(find.byType(AutomationProfileEditorDialog), findsNothing);
        gate.complete();
        await tester.pump();
        await saved;
        await tester.pumpAndSettle();
        expect(dispatches, 1);
        expect(successCloses, 0);
        expect(ownerError, 'REVISION_CONFLICT');
        expect(operation.writeOutcome!.errorCode, 'REVISION_CONFLICT');
        expect(
          find.text(automationMessage('REVISION_CONFLICT')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        if (!gate.isCompleted) {
          gate.complete();
          await tester.pump();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        // The actual route continuation owns submission.dispose, like Panel.
        operation.dispose();
        name.dispose();
        description.dispose();
        body.dispose();
      }
    },
  );
}

void _registerSubmissionAndProvenanceBoundaries() {
  test(
    'T094 shared metadata validator preserves exact Unicode boundaries',
    () async {
      var dispatches = 0;
      final source = jsonEncode(DesignAutomationFixtures.body());
      final invalidNames = [
        '',
        'a' * 101,
        '😀' * 101,
        '👍🏽' * 51,
        'e\u0301',
        for (final control in [
          '\n',
          '\t',
          '\r',
          '\u0000',
          '\u007f',
          '\u0085',
          '\u009f',
        ])
          'a${control}b',
        String.fromCharCode(0xd800),
      ];
      final invalidDescriptions = [
        'a' * 2001,
        '😀' * 2001,
        '👍🏽' * 1001,
        'e\u0301',
        for (final control in ['\r', '\u0000', '\u007f', '\u0085', '\u009f'])
          'a${control}b',
        String.fromCharCode(0xdc00),
      ];
      Future<void> submit(String n, String d, Map<String, Object?> body) async {
        dispatches++;
      }

      for (final name in invalidNames) {
        expect(
          () => submitAutomationProfileDraft(
            name: name,
            description: '',
            source: source,
            current: () => true,
            submit: submit,
          ),
          throwsA(
            isA<AutomationProfileMetadataError>().having(
              (e) => e.nameError,
              'name error',
              isNotNull,
            ),
          ),
        );
      }
      for (final description in invalidDescriptions) {
        expect(
          () => submitAutomationProfileDraft(
            name: 'Профиль',
            description: description,
            source: source,
            current: () => true,
            submit: submit,
          ),
          throwsA(
            isA<AutomationProfileMetadataError>().having(
              (e) => e.descriptionError,
              'description error',
              isNotNull,
            ),
          ),
        );
      }
      expect(dispatches, 0);
      for (final (name, description) in [
        ('a', ''),
        (' ', '\n\t'),
        ('😀' * 100, '😀' * 2000),
        ('👍🏽' * 50, '👍🏽' * 1000),
        ('  é😀  ', ' é\n\t😀 '),
      ]) {
        await submitAutomationProfileDraft(
          name: name,
          description: description,
          source: source,
          current: () => true,
          submit: (n, d, body) async {
            expect(n, name);
            expect(d, description);
            expect(body, DesignAutomationFixtures.body());
            dispatches++;
          },
        );
      }
      expect(dispatches, 5);
      expect(
        () => submitAutomationProfileDraft(
          name: 'Профиль',
          description: '',
          source: '{',
          current: () => true,
          submit: submit,
        ),
        throwsFormatException,
      );
      expect(dispatches, 5);
    },
  );
  test('T093 no-op admission, dismiss, replacement and stale completions fence provenance', () async {
    final operation = AutomationUiOperation();
    String? code, pending;
    AutomationUiResult result() =>
        AutomationUiResult(errorCode: code, pendingLabel: pending);
    try {
      await operation.run(AutomationUiPhase.saveProfile, () async {
        code = 'FORBIDDEN';
        pending = 'Первый запрос';
      }, result: result);
      await operation.run(AutomationUiPhase.profiles, () async {
        code = 'TIMEOUT';
      }, result: result);
      final original = operation.writeOutcome;
      await operation.run(
        AutomationUiPhase.approve,
        () async {},
        result: result,
        admitted: () => false,
      );
      expect(operation.writeOutcome, same(original));
      expect(operation.readErrorCode, 'TIMEOUT');
      operation.dismiss(() {}, result); // owner busy/no-op dismissal retains it
      expect(operation.writeOutcome, same(original));
      operation.observeOwner(
        const AutomationUiResult(
          errorCode: 'SERVICE_UNAVAILABLE',
          pendingLabel: 'Первый запрос',
        ),
      );
      expect(operation.writeOutcome, same(original));
      expect(operation.readErrorCode, 'SERVICE_UNAVAILABLE');
      final oldGate = Completer<void>();
      final old = operation.run(
        AutomationUiPhase.retry,
        () => oldGate.future,
        result: () => const AutomationUiResult(
          errorCode: 'TIMEOUT',
          pendingLabel: 'Старый запрос',
        ),
      );
      operation.reset(); // actual Panel replacement path uses this same reset
      expect(operation.writeOutcome, isNull);
      expect(operation.readErrorCode, isNull);
      await operation.run(AutomationUiPhase.createPlan, () async {
        code = 'VALIDATION';
        pending = 'Новый запрос';
      }, result: result);
      final current = operation.writeOutcome;
      oldGate.complete();
      await old;
      expect(operation.writeOutcome, same(current));
      expect(operation.writeOutcome!.errorCode, 'VALIDATION');
      expect(operation.label, isNull);
      operation.dismiss(() {
        pending = null;
        code = null;
      }, result);
      expect(operation.writeOutcome, isNull);
      expect(operation.readErrorCode, isNull);
      expect(
        () => operation.run(
          AutomationUiPhase.saveProfile,
          () => throw const FormatException('VALIDATION'),
          result: result,
        ),
        throwsFormatException,
      );
      expect(operation.writeOutcome, isNull);
    } finally {
      operation.dispose();
    }
  });
}

void _registerRetainedWriteJourney(_Variant variant) {
  testWidgets(
    'T093 retained write active read retry dismiss next write ${variant.suffix}',
    (tester) async {
      final operation = AutomationUiOperation();
      String? error, pending;
      var ownerBusy = false, writes = 0, reads = 0, dismisses = 0;
      var nextCode = 'TIMEOUT';
      Object identity = Object();
      final dispatchedIdentities = <Object>[];
      AutomationUiResult result() =>
          AutomationUiResult(errorCode: error, pendingLabel: pending);
      Future<void> write() async {
        writes++;
        dispatchedIdentities.add(identity);
        ownerBusy = true;
        pending = 'Сохранение профиля';
        error = null;
        await Future<void>.value();
        error = nextCode == 'success' ? null : nextCode;
        if (error == null) pending = null;
        ownerBusy = false;
      }

      Widget status() => ListenableBuilder(
        listenable: operation,
        builder: (_, _) => _scroll(
          AutomationStatusSection(
            busy: ownerBusy,
            openingRecipes: false,
            canRetry: !ownerBusy && pending != null,
            pendingLabel: pending,
            operationLabel: operation.label,
            errorCode: operation.readErrorCode,
            writeOutcome: operation.writeOutcome,
            onRetry: () => operation
                .run(
                  AutomationUiPhase.retry,
                  write,
                  result: result,
                  admitted: () => ownerBusy,
                )
                .ignore(),
            onDismiss: () => operation.dismiss(() {
              dismisses++;
              pending = error = null;
            }, result),
            onStopWaiting: () {},
          ),
        ),
      );
      try {
        await operation.run(
          AutomationUiPhase.saveProfile,
          write,
          result: result,
          admitted: () => ownerBusy,
        );
        await _mount(tester, status(), variant);
        expect(find.text('Исход записи не подтверждён'), findsOneWidget);
        final gate = Completer<void>();
        final read = operation.run(
          AutomationUiPhase.profiles,
          () async {
            reads++;
            ownerBusy = true;
            error = null;
            await gate.future;
            error = 'SERVICE_UNAVAILABLE';
            ownerBusy = false;
          },
          result: result,
          admitted: () => ownerBusy,
        );
        await tester.pump();
        expect(find.text('Профили'), findsOneWidget);
        expect(find.text('Запрос: Сохранение профиля'), findsOneWidget);
        expect(find.text('Повторить тот же запрос'), findsNothing);
        expect(find.text('Закрыть запрос'), findsNothing);
        gate.complete();
        await tester.pump();
        await read;
        await tester.pumpAndSettle();
        expect(find.text('Исход записи не подтверждён'), findsOneWidget);
        expect(find.text('Ошибка чтения'), findsOneWidget);
        expect(
          find.text(automationMessage('SERVICE_UNAVAILABLE')),
          findsOneWidget,
        );
        nextCode = 'FORBIDDEN';
        await _click(tester, 'Повторить тот же запрос');
        expect(writes, 2);
        expect(
          dispatchedIdentities[1],
          same(dispatchedIdentities[0]),
          reason: 'Borrowed callback fixture identity only, no native request-ID claim.',
        );
        expect(find.text('Исход записи не подтверждён'), findsNothing);
        expect(find.text(automationMessage('FORBIDDEN')), findsOneWidget);
        await operation.run(AutomationUiPhase.jobs, () async {
          reads++;
          error = null;
        }, result: result);
        await tester.pumpAndSettle();
        expect(find.text(automationMessage('FORBIDDEN')), findsOneWidget);
        await _click(tester, 'Закрыть запрос');
        expect(dismisses, 1);
        expect(operation.writeOutcome, isNull);
        nextCode = 'TIMEOUT';
        identity = Object();
        await operation.run(
          AutomationUiPhase.saveProfile,
          write,
          result: result,
        );
        await tester.pumpAndSettle();
        expect(find.text('Исход записи не подтверждён'), findsOneWidget);
        nextCode = 'success';
        await _click(tester, 'Повторить тот же запрос');
        expect(writes, 4);
        expect(reads, 2);
        expect(dispatchedIdentities[3], same(dispatchedIdentities[2]));
        expect(operation.writeOutcome, isNull);
        expect(find.text('Исход записи не подтверждён'), findsNothing);
        await _mount(
          tester,
          status(),
          _Variant(variant.size, variant.scale, !variant.dark),
        );
        expect(writes, 4);
        expect(reads, 2);
        expect(dismisses, 1);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        operation.dispose();
      }
    },
  );
}

void _registerProfileDraftRegressions(_Variant variant) {
  for (final field in ['name', 'description']) {
    testWidgets(
      'T094 semantic invalid $field retains draft ${variant.suffix}',
      (tester) async {
        final name = TextEditingController(
          text: field == 'name' ? '' : 'Профиль',
        );
        final description = TextEditingController(
          text: field == 'description' ? 'a\rb' : 'Точное описание',
        );
        final source = jsonEncode(DesignAutomationFixtures.body());
        final body = TextEditingController(text: source);
        final submission = AutomationProfileDraftSubmission();
        var dispatches = 0, closes = 0;
        Map<String, Object?>? payload;
        Widget editor() => ListenableBuilder(
          listenable: submission,
          builder: (_, _) => AutomationProfileEditorDialog(
            name: name,
            description: description,
            body: body,
            validating: submission.saving,
            canValidate: !submission.saving,
            error: submission.error,
            nameError: submission.nameError,
            descriptionError: submission.descriptionError,
            saveError: submission.saveError,
            onBodyChanged: (_) {},
            onValidate: () {},
            onClose: () {},
            onSave: () => submission
                .save(
                  name: name.text,
                  description: description.text,
                  source: body.text,
                  current: () => true,
                  submit: (n, d, value) async {
                    dispatches++;
                    payload = {'name': n, 'description': d, 'body': value};
                  },
                  resultError: () => null,
                  close: () => closes++,
                )
                .ignore(),
          ),
        );
        try {
          final originalName = name.text,
              originalDescription = description.text;
          await _mount(tester, editor(), variant);
          await _click(tester, 'Сохранить версию');
          expect(dispatches, 0);
          expect(closes, 0);
          final controller = field == 'name' ? name : description;
          final input = tester.widget<TextField>(
            find.byWidgetPredicate(
              (w) => w is TextField && identical(w.controller, controller),
            ),
          );
          expect(input.decoration!.errorText, isNotNull);
          await tester.ensureVisible(
            find.byWidgetPredicate(
              (w) => w is TextField && identical(w.controller, controller),
            ),
          );
          await tester.pumpAndSettle();
          await _captureProfileCheckpoint(
            tester,
            variant,
            't096-$field-error-visible',
            {'saveCallbacks': dispatches, 'closeCallbacks': closes},
            [
              'Actual field-linked semantic metadata error; exact draft retained and zero save callbacks.',
              'Bounded reason wraps completely; ordinary test output flag remains unset.',
            ],
          );

          expect(name.text, originalName);
          expect(description.text, originalDescription);
          expect(body.text, source);
          await _mount(
            tester,
            editor(),
            _Variant(variant.size, variant.scale, !variant.dark),
          );
          expect(name.text, originalName);
          expect(description.text, originalDescription);
          expect(body.text, source);
          name.text = '  é😀  ';
          description.text = 'Точное\n\tописание';
          await _click(tester, 'Сохранить версию');
          expect(dispatches, 1);
          expect(closes, 1);
          expect(payload, {
            'name': name.text,
            'description': description.text,
            'body': DesignAutomationFixtures.body(),
          });
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          submission.dispose();
          name.dispose();
          description.dispose();
          body.dispose();
        }
      },
    );
  }
  for (final ownerCode in ['REVISION_CONFLICT', 'VALIDATION', 'TIMEOUT']) {
    testWidgets(
      'T094 owner $ownerCode retains actual editor draft ${variant.suffix}',
      (tester) async {
        final name = TextEditingController(text: 'Профиль');
        final description = TextEditingController(text: 'Сохранить описание');
        final source = jsonEncode(DesignAutomationFixtures.body());
        final body = TextEditingController(text: source);
        final submission = AutomationProfileDraftSubmission();
        var dispatches = 0, closes = 0;
        String? ownerError;
        try {
          await _mount(
            tester,
            ListenableBuilder(
              listenable: submission,
              builder: (_, _) => AutomationProfileEditorDialog(
                name: name,
                description: description,
                body: body,
                validating: submission.saving,
                canValidate: !submission.saving,
                error: submission.error,
                saveError: submission.saveError,
                saveUnconfirmed: submission.saveUnconfirmed,
                saving: submission.saving,
                canSave: ownerError == null,
                onBodyChanged: (_) {},
                onClose: () {},
                onValidate: () {},
                onSave: () => submission
                    .save(
                      name: name.text,
                      description: description.text,
                      source: body.text,
                      current: () => true,
                      canSubmit: () => ownerError == null,
                      submit: (n, d, value) async {
                        dispatches++;
                        ownerError = ownerCode;
                      },
                      resultError: () => ownerError,
                      close: () => closes++,
                    )
                    .ignore(),
              ),
            ),
            variant,
          );
          final retainedSave = tester
              .widget<ButtonStyleButton>(_button('Сохранить версию'))
              .onPressed!;
          await _click(tester, 'Сохранить версию');
          expect(dispatches, 1);
          expect(closes, 0);
          expect(find.text(automationMessage(ownerCode)), findsOneWidget);
          if (ownerCode == 'TIMEOUT') {
            expect(find.text('Исход записи не подтверждён'), findsOneWidget);
          }
          retainedSave();
          await tester.pumpAndSettle();
          expect(dispatches, 1);
          expect(name.text, 'Профиль');
          expect(description.text, 'Сохранить описание');
          expect(body.text, source);
          expect(
            tester
                .widget<ButtonStyleButton>(_button('Сохранить версию'))
                .onPressed,
            isNull,
          );
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          submission.dispose();
          name.dispose();
          description.dispose();
          body.dispose();
        }
      },
    );
  }
}

void _registerProfileRecoveryBoundaries() {
  AutomationProfileBasis basis(
    int head, {
    String? id,
    String? workspace,
    bool archived = false,
  }) => AutomationProfileBasis(
    profile: AutomationProfileRecord.fromJson({
      ...DesignAutomationFixtures.profile(
        headRevision: head,
        archived: archived,
      ).toJson(),
      if (id != null) 'id': id,
      if (workspace != null) 'workspaceId': workspace,
    }),
    revision: head,
    digest: DesignAutomationFixtures.revision(number: head)['digest'] as String,
  );
  final initial = AutomationProfileBasis(
    profile: DesignAutomationFixtures.profile(),
    revision: 1,
    digest: DesignAutomationFixtures.revision(number: 1)['digest'] as String,
  );
  test(
    'T097 CAS rejects mismatched stale archived and returned old basis consent',
    () async {
      final fixture = _ProfileRecoveryFixture(initial: initial)
        ..nextWrite = 'REVISION_CONFLICT';
      try {
        await fixture.save();
        fixture.dismiss();
        for (final rejected in [
          basis(3, id: '00000000-0000-4000-8000-000000000999'),
          basis(3, workspace: '00000000-0000-4000-8000-000000000999'),
          basis(3, archived: true),
          AutomationProfileBasis(
            profile: DesignAutomationFixtures.profile(headRevision: 4),
            revision: 3,
            digest: DesignAutomationFixtures.hash,
          ),
        ]) {
          fixture.nextBasis = rejected;
          await fixture.read();
          expect(fixture.submission.candidateBasis, isNull);
          expect(fixture.accept(), isFalse);
          expect(fixture.saves, 1);
        }
        fixture.nextBasis = basis(3);
        await fixture.read();
        final exactVersion = Map<String, Object?>.of(fixture.revision!);
        fixture.revision = {...fixture.revision!, 'digest': 'b' * 64};
        fixture.observe();
        fixture.revision = exactVersion;
        fixture.observe();
        expect(
          fixture.accept(),
          isFalse,
          reason: 'A changed candidate does not regain consent when its old digest returns.',
        );
        await fixture.read();
        expect(fixture.accept(), isTrue);
        fixture.profile = basis(4).profile;
        fixture.revision = DesignAutomationFixtures.revision(number: 4);
        fixture.observe();
        fixture.profile = basis(3).profile;
        fixture.revision = exactVersion;
        fixture.observe();
        await fixture.save();
        expect(
          fixture.saves,
          1,
          reason: 'Retired accepted basis cannot dispatch a new save.',
        );
        final row = DesignAutomationFixtures.profile(headRevision: 3);
        final version = DesignAutomationFixtures.revision(number: 3);
        expect(
          AutomationProfileBasis.fromOwner(row, {
            ...version,
            'profileId': '00000000-0000-4000-8000-000000000999',
          }, currentHead: true),
          isNull,
        );
        expect(
          AutomationProfileBasis.fromOwner(row, {
            ...version,
            'workspaceId': '00000000-0000-4000-8000-000000000999',
          }, currentHead: true),
          isNull,
        );
        expect(
          AutomationProfileBasis.fromOwner(
            row,
            DesignAutomationFixtures.revision(number: 2),
            currentHead: true,
          ),
          isNull,
        );
        expect(fixture.closes, 0);
      } finally {
        fixture.dispose();
      }
    },
  );
  test(
    'T097 retired or disposed presentation ignores late basis completion',
    () async {
      for (final disposed in [false, true]) {
        final submission = AutomationProfileDraftSubmission(
          initialBasis: initial,
        );
        String? code, pending;
        var saves = 0, reads = 0, closes = 0, current = true;
        await submission.save(
          name: 'Профиль',
          description: '',
          source: jsonEncode(DesignAutomationFixtures.body()),
          current: () => current,
          submit: (n, d, body) async {
            saves++;
            code = 'REVISION_CONFLICT';
            pending = 'Сохранение профиля';
          },
          resultError: () => code,
          pendingLabel: () => pending,
          close: () => closes++,
        );
        submission.dismissSaved(
          dismiss: () {
            pending = code = null;
          },
          pendingLabel: () => pending,
        );
        final gate = Completer<AutomationProfileBasis?>();
        final reading = submission.readBasis(
          read: () {
            reads++;
            return gate.future;
          },
          current: () => current,
          canRead: () => true,
          pendingLabel: () => pending,
        );
        if (disposed) {
          submission.dispose();
        } else {
          current = false;
          submission.observeBasis(current: current, unchanged: (_) => true);
          current = true;
        }
        gate.complete(basis(3));
        await reading;
        expect(submission.candidateBasis, isNull);
        expect(
          submission.acceptBasis(
            current: () => current,
            canAccept: () => true,
            unchanged: (_) => true,
          ),
          isFalse,
        );
        await submission.save(
          name: 'Профиль',
          description: '',
          source: jsonEncode(DesignAutomationFixtures.body()),
          current: () => current,
          submit: (n, d, body) async {
            saves++;
          },
          resultError: () => null,
          close: () => closes++,
        );
        expect(saves, 1);
        expect(reads, 1);
        expect(closes, 0);
        if (!disposed) submission.dispose();
      }
    },
  );
}
