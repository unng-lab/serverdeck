import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/profiles/credential_input.dart';
import 'package:serverdeck/profiles/mutation_controller.dart';
import 'package:serverdeck/profiles/mutation_status.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/profiles/profile_delete.dart';
import 'package:serverdeck/profiles/profile_form.dart';
import 'package:serverdeck/profiles/profile_list.dart';
import 'package:serverdeck/profiles/recovery_view.dart';
import 'package:serverdeck/profiles/startup_recovery.dart';
import 'package:serverdeck/servers/metrics_history.dart';
import 'package:serverdeck/servers/server_sections.dart';
import 'package:serverdeck/settings/settings_form.dart';
import 'package:serverdeck/settings/settings_view.dart' as settings;
import 'package:serverdeck/software/software_panel.dart';
import 'package:serverdeck/shell/readiness_view.dart';
import 'package:serverdeck_protocol/models.dart' hide ReadinessView;

import '../contract/profile_controller_test.dart' as model_fixture;
import 'design_automation_fixtures.dart';
import 'design_server_fixtures.dart';

/// An effect counter is deliberately separate from ModelClient.refreshes.
/// A presentation callback proves an invocation, never a native effect.
class DesignCallbackCounters {
  final Map<String, int> _values = {};
  int operator [](String name) => _values[name] ?? 0;
  Map<String, int> get values => Map.unmodifiable(_values);
  void hit(String name) =>
      _values.update(name, (n) => n + 1, ifAbsent: () => 1);
  VoidCallback callback(String name) =>
      () => hit(name);
  ValueChanged<T> change<T>(String name) =>
      (_) => hit(name);
}

/// Existing ModelClient transport seam; there is no TrustedApiClient or proof.
class DesignModelClient extends model_fixture.ModelClient {
  final mutations = <MutationIntent>[];
  final statusRequests = <MutationIntent>[];
  final reads = <ApiMethod>[];
  Completer<ApiReply>? mutationGate, statusGate, recentGate;
  ErrorCode mutationError = ErrorCode.revisionConflict;
  String mutationStatusValue = 'not-found';
  List<Map<String, Object?>> receipts = const [];
  bool receiptsTruncated = false;

  @override
  Future<ApiReply> mutate(MutationIntent intent) async {
    mutations.add(intent);
    if (mutationGate != null) return mutationGate!.future;
    throw LocalApiException(mutationError);
  }

  @override
  Future<ApiReply> mutationStatus(MutationIntent intent) async {
    statusRequests.add(intent);
    if (statusGate != null) return statusGate!.future;
    return ApiReply(generationId, {
      'state': mutationStatusValue,
      'result': null,
    });
  }

  @override
  Future<ApiReply> read(
    ApiMethod method, [
    Map<String, Object?> params = const {},
  ]) async {
    reads.add(method);
    if (method != ApiMethod.mutationsRecent) {
      throw StateError('No synthetic response configured for ${method.name}');
    }
    if (recentGate != null) return recentGate!.future;
    return ApiReply(generationId, {
      'receipts': receipts,
      'truncated': receiptsTruncated,
    });
  }
}

/// Reusable inputs for later adoption/graph/layout/state assertions. Changing a
/// projection does not claim its visual acceptance or exercise its native owner.
class DesignFixtureOptions {
  const DesignFixtureOptions({
    this.busy = false,
    this.empty = false,
    this.loaded = true,
    this.quality = 'known',
    this.stale = false,
    this.points,
    this.connectionState = 'connected',
    this.error,
    this.planBlocked = false,
    this.planExpired = false,
    this.jobState = 'running',
    this.longText = false,
    this.delayed = false,
    this.readiness,
  });
  final bool busy,
      empty,
      loaded,
      stale,
      planBlocked,
      planExpired,
      longText,
      delayed;
  final String quality, connectionState, jobState;
  final String? error;
  final List<Object?>? points;
  final ReadinessState? readiness;
}

/// Owns and disposes all model subscriptions, RAM editors, filters, and gates.
/// Mount real widgets with [buildOrigin]; unmount them before calling [close].
class DesignScenarioHarness {
  DesignScenarioHarness._(
    this.client,
    this.bootstrap,
    this.profiles,
    this.options,
  ) : mutation = MutationController(model: profiles),
      recovery = StartupRecovery(model: profiles);

  final DesignModelClient client;
  final model_fixture.ModelBootstrap bootstrap;
  final ProfileController profiles;
  final MutationController mutation;
  final StartupRecovery recovery;
  final DesignFixtureOptions options;
  final counters = DesignCallbackCounters();
  final trustProfile = DesignServerFixtures.profile();
  final trustChallenge = DesignServerFixtures.challenge();
  final executorInspection = DesignServerFixtures.executorInspection();
  final recordLogs = DesignServerFixtures.logs(
    records: [
      DesignServerFixtures.record(timestamp: '2026-10-24T07:08:09.000Z'),
    ],
  );
  final filter = TextEditingController();
  final name = TextEditingController();
  final description = TextEditingController();
  final body = TextEditingController();
  final jsonInput = TextEditingController();
  final credentialKey = GlobalKey<CredentialInputState>();
  Completer<String?>? pickerGate;
  bool _closed = false;

  static Future<DesignScenarioHarness> create({
    String? screenId,
    DesignFixtureOptions options = const DesignFixtureOptions(),
  }) async {
    final client = DesignModelClient();
    if (options.delayed) {
      client.refreshGate = Completer<void>();
      client.recentGate = Completer<ApiReply>();
    }
    final bootstrap = model_fixture.ModelBootstrap(client)
      ..show(ReadinessState.ready);
    final profiles = ProfileController(bootstrap: bootstrap);
    final result = DesignScenarioHarness._(
      client,
      bootstrap,
      profiles,
      options,
    );
    client.receipts = [
      {
        'requestId': '00000000-0000-4000-8000-000000000099',
        'operation': 'settings.update',
        'profileId': null,
        'committedAt': DesignServerFixtures.observedAt,
        'result': {
          'entityId': null,
          'entityRevision': '1',
          'storeRevision': '1',
          'deleted': false,
        },
      },
    ];
    if (options.delayed) {
      result.pickerGate = Completer<String?>();
    }
    if (options.loaded) {
      result.publishSnapshot(
        empty: options.empty || screenId == '04-empty-workspace',
      );
    }
    result.name.text = options.longText
        ? List.filled(8, 'Синтетический · 例 · ').join()
        : 'Синтетический профиль';
    result.description.text = 'Только synthetic test input';
    result.body.text = const JsonEncoder.withIndent('  ')
        .convert(DesignAutomationFixtures.body());
    if (screenId == '13-mutation-conflict') {
      if (options.busy) client.mutationGate = Completer<ApiReply>();
      final pending = result.mutation.submit(ApiMethod.settingsUpdate, {
        'expectedRevision': '1',
        'theme': 'light',
        'reduceMotion': false,
        'selectedProfileId': null,
      });
      if (!options.busy) await pending;
    }
    return result;
  }

  void publishSnapshot({bool empty = false, String revision = '1'}) {
    final base = model_fixture.snapshot(revision: revision);
    final rows = (base.profiles.result['profiles'] as List)
        .cast<Map<String, Object?>>();
    client.events.add(
      ClientSnapshot(
        ApiReply(client.generationId, {
          'storeRevision': revision,
          'profiles': empty
              ? <Object?>[]
              : [
                  for (final row in rows)
                    {
                      ...row,
                      if (options.longText)
                        'name': List.filled(10, 'Профиль 例 ').join().trim(),
                    },
                ],
        }),
        ApiReply(client.generationId, {
          ...base.settings.result,
          'settings': {
            ...(base.settings.result['settings'] as Map<String, Object?>),
            if (empty) 'selectedProfileId': null,
          },
        }),
      ),
    );
  }

  /// Epoch transitions and late snapshots go through the existing model owner.
  void showReadiness(ReadinessState state) => bootstrap.show(state);

  void showReadError(ErrorCode code) => client.readErrors.add(code);

  ProfileView get initialProfile {
    if (profiles.profiles.isNotEmpty) return profiles.profiles.first;
    return const ProfileView(
      id: model_fixture.profileId,
      revision: '1',
      name: 'Saved profile',
      address: '192.0.2.1',
      port: 22,
      sshUser: 'admin',
      tags: ['production'],
      credentialRevision: '1',
      connectionRevision: '1',
      trustRevision: '1',
      createdAt: '2026-10-11T00:00:00.000Z',
      updatedAt: '2026-10-11T00:00:00.000Z',
      credentialKind: CredentialKind.password,
      credentialConfigured: true,
    );
  }

  CredentialInput credentialInput({bool creating = true}) => CredentialInput(
    key: credentialKey,
    creating: creating,
    enabled: bootstrap.state == ReadinessState.ready && !options.busy,
    readReadyEpoch: () => bootstrap.state == ReadinessState.ready
        ? bootstrap.readinessEpoch
        : null,
    pickKey: () {
      counters.hit('pickKey');
      return (pickerGate ??= Completer<String?>()).future;
    },
    onSubmit: counters.callback('credentialSubmit'),
  );

  ProfileView get automationServerProfile =>
      DesignServerFixtures.profile(connectionRevision: '2');

  AutomationActionAvailability get actions => AutomationActionAvailability(
    read: !options.busy,
    mutate: !options.busy,
    select: !options.busy,
  );

  /// Only composition wrappers surround the same production sections used by
  /// ServerPanel/AutomationPanel. No layout is reimplemented in test support.
  Widget buildOrigin(String id) => switch (id) {
    '01-startup' => ReadinessView(
      state: options.readiness ?? ReadinessState.starting,
      onRetry: counters.callback('retry'),
    ),
    '02-service-unavailable' => ReadinessView(
      state: options.readiness ?? ReadinessState.unavailable,
      reason: ErrorCode.serviceUnavailable,
      retryInProgress: options.busy,
      onRetry: counters.callback('retry'),
    ),
    '03-storage-blocked' => ReadinessView(
      state: options.readiness ?? ReadinessState.storageBlocked,
      reason: ErrorCode.storageBlocked,
      onRetry: counters.callback('retry'),
    ),
    '04-empty-workspace' ||
    '05-server-list' => ProfileList(controller: profiles),
    '06-server-overview' => serverOverview(),
    '07-profile-create' ||
    '12-credential-input' => ProfileForm(model: profiles),
    '08-profile-edit' => ProfileForm(model: profiles, initial: initialProfile),
    '09-profile-delete' => ProfileDelete(
      model: profiles,
      initial: initialProfile,
    ),
    '10-host-trust' => ServerTrustConfirmation(
      challenge: trustChallenge,
      profile: trustProfile,
      changes: profiles,
      currentProfile: () => trustProfile,
      currentChallenge: () => trustChallenge,
      onCancel: counters.callback('cancelTrust'),
      onConfirm: counters.callback('confirmTrust'),
    ),
    '13-mutation-conflict' => ListenableBuilder(
      listenable: mutation,
      builder: (_, _) => MutationStatus(
        controller: mutation,
        onReload: counters.callback('reload'),
      ),
    ),
    '16-install-catalog' => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftwarePanel(profiles: profiles, client: null),
        recipes(),
      ],
    ),
    '17-recipe-detail' => recipes(),
    '18-install-preflight' => plan(blocked: options.planBlocked),
    '19-plan-approval' => AutomationPlanDecisionDialog(
      now: DesignAutomationFixtures.presentationNow,
      plan: DesignAutomationFixtures.plan(),
      serverProfiles: [automationServerProfile],
      automationProfile: DesignAutomationFixtures.profile(),
      approve: true,
      onBack: counters.callback('decisionBack'),
      onConfirm: counters.callback('approve'),
    ),
    '22-server-logs' => ServerLogsSection(
      logs: options.loaded
          ? DesignServerFixtures.logs(
              quality: options.quality,
              records: options.empty ? [] : null,
            )
          : null,
      filterController: filter,
      busy: options.busy,
      onLoad: counters.callback('readLogs'),
      onPrevious: counters.callback('previousLogs'),
      onOpenRecord: counters.change('openRecord'),
    ),
    '23-log-record' => ServerLogRecordDialog(
      recordContext: ServerLogRecordContext.capture(trustProfile, recordLogs),
      record: (recordLogs['records'] as List).single as Map<String, Object?>,
      onClose: counters.callback('closeRecord'),
    ),
    '27-job-list' => jobs(detail: false),
    '28-job-detail' => jobs(),
    '29-job-unknown' => jobs(state: 'unknown'),
    '30-job-cancel' => jobs(),
    '31-recent-operations' => RecoveryView(
      recovery: recovery,
      child: RecentOperationsButton(recovery: recovery),
    ),
    '32-automation-profiles' => AutomationProfilesSection(
      profiles: options.empty ? [] : [DesignAutomationFixtures.profile()],
      loaded: options.loaded,
      hasMore: false,
      actions: actions,
      onSelect: counters.change('selectAutomationProfile'),
      onMore: counters.callback('moreProfiles'),
    ),
    '33-profile-authoring' => AutomationProfileEditorDialog(
      name: name,
      description: description,
      body: body,
      validating: options.busy,
      canValidate: !options.busy,
      error: options.error,
      onBodyChanged: counters.change('editBody'),
      onClose: counters.callback('closeAuthoring'),
      onSave: counters.callback('saveVersion'),
      onValidate: counters.callback('validateVersion'),
    ),
    '34-profile-revisions' => revision(),
    '35-plan-parameters' => jsonEditor(
      'Параметры плана',
      const {'greeting': 'Привет'},
      purpose: 'Проверьте параметры для выбранной версии. Продолжение создаст план; запуск потребует отдельного подтверждения.',
      target: 'Ansible-профиль: Приветствие сервера · версия 2.',
      contextDetails: {
        'profileId': DesignAutomationFixtures.profileId,
        'revision': 2,
        'bodyDigest': DesignAutomationFixtures.revision()['digest'],
        'serverId': DesignAutomationFixtures.serverId,
      },
    ),
    '36-ai-grants' => grants(),
    '37-ai-grant-form' => jsonEditor(
      'Выдать ИИ доступ через MCP',
      {
        'label': 'Synthetic client',
        'scopes': ['read', 'logs', 'author', 'plan'],
        'serverIds': [DesignAutomationFixtures.serverId],
        'lifetimeSeconds': 28800,
      },
      purpose: 'Выдайте только необходимые права на перечисленные серверы. Сохранение выдаст доступ клиенту ИИ на указанный срок.',
    ),
    '38-mcp-client-config' => grants(configuration: true),
    '39-delegations' => jsonEditor(
      'Делегирование «Synthetic client» · версия 2',
      {
        'lifetimeSeconds': 3600,
        'predicates': <String, Object?>{
          'greeting': {
            'type': 'enum',
            'values': ['Привет'],
          },
        },
      },
      purpose: 'Разрешить запуск только этой неизменной версии в заданных границах параметров. Новые версии потребуют отдельного делегирования.',
      target:
          'Ansible-профиль: Приветствие сервера · версия 2. Доступ клиента до: ${DesignAutomationFixtures.grant()['expiresAt']} (UTC).',
      contextDetails: {
        'profileId': DesignAutomationFixtures.profileId,
        'revision': 2,
        'bodyDigest': DesignAutomationFixtures.revision()['digest'],
        'serverId': DesignAutomationFixtures.serverId,
        'grantId': DesignAutomationFixtures.grantId,
      },
    ),
    '40-executor-binding' => ServerExecutorConfirmation(
      inspection: executorInspection,
      profile: trustProfile,
      changes: profiles,
      currentProfile: () => trustProfile,
      currentInspection: () => executorInspection,
      onCancel: counters.callback('cancelExecutor'),
      onConfirm: counters.callback('confirmExecutor'),
    ),
    '84-settings' => settings.SettingsView(controller: profiles),
    '85-settings-form' => SettingsForm(model: profiles),
    '94-plan-invalidated' => plan(blocked: true),
    _ => throw ArgumentError.value(
      id,
      'id',
      'No runtime fixture for a concept or unknown ID',
    ),
  };

  Widget serverOverview() => ServerOverviewSection(
    connection: ServerConnectionSection(
      connection: DesignServerFixtures.connection(
        state: options.connectionState,
      ),
      trust: DesignServerFixtures.trust(),
      busy: options.busy,
      error: options.error,
      hasTrustChallenge: false,
      onRefresh: counters.callback('refreshConnection'),
      onProbeTrust: counters.callback('probeTrust'),
      onConfirmTrust: counters.callback('confirmTrust'),
      onConnect: counters.callback('connect'),
      onDisconnect: counters.callback('disconnect'),
      onRevokeTrust: counters.callback('revokeTrust'),
      onCancel: counters.callback('cancelRead'),
    ),
    state: options.loaded
        ? DesignServerFixtures.state(
            quality: options.quality,
            stale: options.stale,
            points: options.points,
          )
        : null,
  );

  MetricsHistory graph(List<Object?> points) => MetricsHistory(points: points);

  AutomationRecipesSection recipes() => AutomationRecipesSection(
    catalog: DesignAutomationFixtures.catalog(),
    canMutate: !options.busy,
    onCreatePlan: counters.change('createRecipePlan'),
  );

  AutomationPlanSection plan({bool blocked = false}) => AutomationPlanSection(
    serverProfiles: [automationServerProfile],
    automationProfile: DesignAutomationFixtures.profile(),
    plan: DesignAutomationFixtures.plan(
      blocked: blocked,
      expired: options.planExpired,
    ),
    runnable: !blocked && !options.planExpired,
    expired: options.planExpired,
    actions: actions,
    onApprove: counters.callback('approve'),
    onDeny: counters.callback('deny'),
    onApply: counters.callback('apply'),
    onRefresh: counters.callback('refreshPlan'),
  );

  AutomationJobsSection jobs({bool detail = true, String? state}) {
    final job = DesignAutomationFixtures.job(state: state ?? options.jobState);
    return AutomationJobsSection(
      serverId: DesignAutomationFixtures.serverId,
      jobs: options.empty
          ? []
          : [
              {'job': job},
            ],
      events: DesignAutomationFixtures.events(),
      job: detail && !options.empty ? job : null,
      loaded: options.loaded,
      hasMore: false,
      droppedEvents: 0,
      canCancel: detail && job['state'] == 'running',
      canReconcile: detail && job['state'] == 'unknown',
      actions: actions,
      onRefresh: counters.callback('refreshJobs'),
      onRefreshAuthorities: counters.callback('refreshAuthorities'),
      onSelect: counters.change('selectJob'),
      onMore: counters.callback('moreJobs'),
      onShowPlan: counters.callback('showPlan'),
      onCancel: counters.callback('cancelJob'),
      onReconcile: counters.callback('reconcileJob'),
    );
  }

  AutomationProfileDetailSection revision() => AutomationProfileDetailSection(
    profile: DesignAutomationFixtures.profile(),
    revision: DesignAutomationFixtures.revision(),
    comparison: DesignAutomationFixtures.comparison(),
    hasServer: true,
    actions: actions,
    onSelectVersion: counters.callback('selectVersion'),
    onValidate: counters.callback('validate'),
    onCompare: counters.callback('compare'),
    onEdit: counters.callback('edit'),
    onCreatePlan: counters.callback('createPlan'),
    onDelegate: counters.callback('delegate'),
    onArchive: counters.callback('archive'),
  );

  AutomationGrantsSection grants({bool configuration = false}) =>
      AutomationGrantsSection(
        serverProfiles: [automationServerProfile],
        grants: options.empty
            ? []
            : [
                AutomationGrantPresentation(
                  value: DesignAutomationFixtures.grant(),
                  current: true,
                ),
              ],
        loaded: options.loaded,
        actions: actions,
        launchConfiguration: configuration
            ? DesignAutomationFixtures.launchConfiguration()
            : null,
        onRefresh: counters.callback('refreshGrants'),
        onCreate: counters.callback('createGrant'),
        onConfigure: counters.change('configureGrant'),
        onEdit: counters.change('editGrant'),
        onRevoke: counters.change('revokeGrant'),
        onCopyConfiguration: counters.callback('copyConfiguration'),
      );

  AutomationJsonEditorDialog jsonEditor(
    String title,
    Map<String, Object?> input, {
    String? purpose,
    String? target,
    Map<String, Object?> contextDetails = const {},
  }) {
    if (jsonInput.text.isEmpty)
      jsonInput.text = const JsonEncoder.withIndent('  ').convert(input);
    return AutomationJsonEditorDialog(
      title: title,
      input: jsonInput,
      preview: input,
      purpose: purpose,
      target: target,
      serverProfiles: [automationServerProfile],
      targetServerIds: [
        if (contextDetails['serverId'] is String)
          contextDetails['serverId'] as String,
      ],
      contextDetails: contextDetails,
      error: options.error,
      onClose: counters.callback('closeEditor'),
      onContinue: counters.callback('continueEditor'),
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    recovery.dispose();
    mutation.dispose();
    profiles.dispose();
    for (final controller in [filter, name, description, body, jsonInput]) {
      controller.dispose();
    }
    if (pickerGate case final gate? when !gate.isCompleted) gate.complete(null);
    if (client.refreshGate case final gate? when !gate.isCompleted)
      gate.complete();
    for (final gate in [
      client.mutationGate,
      client.statusGate,
      client.recentGate,
    ]) {
      if (gate != null && !gate.isCompleted)
        gate.complete(
          ApiReply(client.generationId, {
            'receipts': <Object?>[],
            'truncated': false,
          }),
        );
    }
    await bootstrap.close();
    await client.events.close();
    await client.readErrors.close();
  }
}
