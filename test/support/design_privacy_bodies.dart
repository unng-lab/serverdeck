import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:serverdeck/automation/automation_presentation.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/servers/server_sections.dart';
import 'package:serverdeck/software/software_panel.dart';
import 'package:serverdeck/ui/deck_components.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/executor_enrollment.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/remote_reads.dart';

import 'design_automation_fixtures.dart';
import 'design_server_fixtures.dart';

/// Real public presentation bodies mounted by the privacy runner in the actual
/// authorized FoundationApp route. Synthetic DTOs confer no RPC/native authority.
/// The supplied model is the root's model; this fixture creates no controller.
/// Expand production ExpansionTiles before inspecting their private markers.
class DesignPrivacyRemoteBody {
  DesignPrivacyRemoteBody(this.family, {required this.model}) {
    if (!families.contains(family)) {
      throw ArgumentError.value(
        family,
        'family',
        'Unknown remote privacy body',
      );
    }
    for (final action in _actionNames) {
      _effects[action] = 0;
    }
    _filter.text = _marker('filter draft');
    _name.text = _marker('authoring name');
    _description.text = _marker('authoring description');
    _body.text = _pretty(DesignAutomationFixtures.body());
    _input.text = _pretty(_editorDraft);
  }

  static const families = <String>[
    'server-overview',
    'trust',
    'software-catalog',
    'recipe-detail',
    'preflight',
    'plan-decision',
    'logs',
    'log-record',
    'job-list',
    'job-detail',
    'job-unknown',
    'job-cancel',
    'automation-profiles',
    'authoring',
    'revisions',
    'parameters',
    'grants',
    'grant-editor',
    'mcp-config',
    'delegations-list',
    'executor',
    'invalidated-plan',
    'revoke-trust',
    'revoke-executor',
    'delegation-chooser',
    'delegation-editor',
    'revoke-grant',
    'archive-profile',
  ];

  final String family;
  final ProfileController model;
  final _effects = <String, int>{};
  final _filter = TextEditingController();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _body = TextEditingController();
  final _input = TextEditingController();
  bool _disposed = false;

  static const _actions = AutomationActionAvailability(
    read: true,
    mutate: true,
    select: true,
  );
  static const _actionNames = <String>[
    'refreshConnection',
    'probeTrust',
    'confirmTrust',
    'connect',
    'disconnect',
    'revokeTrust',
    'cancelRead',
    'createRecipePlan',
    'approve',
    'deny',
    'apply',
    'refreshPlan',
    'loadLogs',
    'previousLogs',
    'openRecord',
    'refreshJobs',
    'refreshAuthorities',
    'selectJob',
    'moreJobs',
    'showPlan',
    'cancelJob',
    'reconcileJob',
    'selectProfile',
    'moreProfiles',
    'saveVersion',
    'validateVersion',
    'selectVersion',
    'validate',
    'compare',
    'edit',
    'createPlan',
    'delegate',
    'archive',
    'continueEditor',
    'refreshGrants',
    'createGrant',
    'configureGrant',
    'editGrant',
    'revokeGrant',
    'copyConfiguration',
    'openPlan',
    'revokeDelegation',
    'moreApprovals',
    'moreDelegations',
    'confirmExecutor',
    'revokeExecutor',
    'selectGrant',
  ];

  String get originId => switch (family) {
    'server-overview' => '06-server-overview',
    'trust' || 'revoke-trust' => '10-host-trust',
    'software-catalog' => '16-install-catalog',
    'recipe-detail' => '17-recipe-detail',
    'preflight' => '18-install-preflight',
    'plan-decision' => '19-plan-approval',
    'logs' => '22-server-logs',
    'log-record' => '23-log-record',
    'job-list' => '27-job-list',
    'job-detail' => '28-job-detail',
    'job-unknown' => '29-job-unknown',
    'job-cancel' => '30-job-cancel',
    'automation-profiles' || 'archive-profile' => '32-automation-profiles',
    'authoring' => '33-profile-authoring',
    'revisions' => '34-profile-revisions',
    'parameters' => '35-plan-parameters',
    'grants' || 'revoke-grant' => '36-ai-grants',
    'grant-editor' => '37-ai-grant-form',
    'mcp-config' => '38-mcp-client-config',
    'delegations-list' ||
    'delegation-chooser' ||
    'delegation-editor' => '39-delegations',
    'executor' || 'revoke-executor' => '40-executor-binding',
    'invalidated-plan' => '94-plan-invalidated',
    _ => throw StateError('Unknown family $family'),
  };

  Type get productionType => switch (family) {
    'server-overview' => ServerOverviewSection,
    'trust' => ServerTrustConfirmation,
    'software-catalog' => AutomationRecipesSection,
    'recipe-detail' => AutomationRecipesSection,
    'preflight' || 'invalidated-plan' => AutomationPlanSection,
    'plan-decision' => AutomationPlanDecisionDialog,
    'logs' => ServerLogsSection,
    'log-record' => ServerLogRecordDialog,
    'job-list' ||
    'job-detail' ||
    'job-unknown' ||
    'job-cancel' => AutomationJobsSection,
    'automation-profiles' => AutomationProfilesSection,
    'authoring' => AutomationProfileEditorDialog,
    'revisions' => AutomationProfileDetailSection,
    'parameters' ||
    'grant-editor' ||
    'delegation-editor' => AutomationJsonEditorDialog,
    'grants' || 'mcp-config' => AutomationGrantsSection,
    'delegations-list' => AutomationAuthoritiesSection,
    'executor' => ServerExecutorConfirmation,
    'revoke-trust' || 'revoke-executor' => ServerConfirmationDialog,
    'delegation-chooser' => AutomationDelegationGrantDialog,
    'revoke-grant' || 'archive-profile' => AutomationConfirmationDialog,
    _ => throw StateError('Unknown family $family'),
  };

  /// Markers belong to actual fields of the body, never to the fixture wrapper.
  /// Catalog references intentionally retain their immutable qualified payload.
  List<String> get markers => switch (family) {
    'server-overview' => [_hostname],
    'trust' || 'executor' => [_pin.fingerprint],
    'software-catalog' ||
    'recipe-detail' => ['Синтетический пример лицензии', '16.10-1'],
    'preflight' ||
    'plan-decision' ||
    'invalidated-plan' => [_profile.name, _server.address],
    'logs' => [_recordMessage, _filter.text],
    'log-record' => [
      _recordMessage,
      _rootProfile.name,
      '${_rootProfile.address}:${_rootProfile.port}',
      _logs['source'] as String,
      _record['timestamp'] as String,
      _logs['observedAt'] as String,
    ],
    'job-list' || 'job-detail' || 'job-unknown' || 'job-cancel' => [_jobId],
    'automation-profiles' || 'revisions' => [_profile.name],
    'authoring' => [_name.text, _description.text],
    'parameters' => [_marker('parameter draft'), _profile.name],
    'grants' ||
    'grant-editor' ||
    'delegation-chooser' ||
    'revoke-grant' => [_grantLabel],
    'mcp-config' => [_command, _argument],
    'delegations-list' => [_delegationGrantId, _marker('predicate value')],
    'delegation-editor' => [_grantLabel, _marker('predicate draft')],
    'revoke-trust' => [
      _rootProfile.name,
      '${_rootProfile.address}:${_rootProfile.port}',
      'Отозвать доверие',
      'Доступ к серверу будет остановлен до нового подтверждения ключа.',
    ],
    'revoke-executor' => [
      _rootProfile.name,
      '${_rootProfile.address}:${_rootProfile.port}',
      'Отозвать привязку',
      'Новые изменения через этот исполнитель будут недоступны.',
    ],
    'archive-profile' => [
      _profile.name,
      'История версий и заданий сохранится.',
    ],
    _ => throw StateError('Unknown family $family'),
  };

  Map<String, int> get effects => Map.unmodifiable(_effects);

  String _marker(String value) => 'PRIVATE remote $family $value';
  String get _hostname => 'privacy-$family.example';
  String get _recordMessage => _marker('journal record');
  String get _grantLabel => _marker('AI client');
  String get _command => 'C:\\Privacy\\$family\\mcp.exe';
  String get _argument => 'C:\\Privacy\\$family\\workspace';
  String get _futureDeadline => DateTime.fromMillisecondsSinceEpoch(
    DateTime.now().millisecondsSinceEpoch +
        const Duration(days: 1).inMilliseconds,
    isUtc: true,
  ).toIso8601String();
  String get _jobId =>
      '00000000-0000-4000-8000-${(700 + families.indexOf(family)).toString().padLeft(12, '0')}';
  String get _delegationGrantId =>
      '00000000-0000-4000-8000-${(800 + families.indexOf(family)).toString().padLeft(12, '0')}';

  late final _profile = DesignAutomationFixtures.profile(
    name: _marker('Ansible profile'),
  );
  late final _server = DesignServerFixtures.profile(
    connectionRevision: '2',
    address: 'privacy-$family-target.example',
  );
  // Plan and revision digests remain the exact fixture values. Readable names
  // live outside the immutable body and the historical clock is explicit.
  late final _plan = DesignAutomationFixtures.plan();
  late final _revision = DesignAutomationFixtures.revision();
  late final _grant = <String, Object?>{
    ...DesignAutomationFixtures.grant(),
    'label': _grantLabel,
  };
  late final _rootProfile =
      model.selected ??
      (throw StateError('Remote privacy bodies require an authorized target'));
  late final _pin = SshHostPin(
    'ssh-ed25519',
    'SHA256:${base64Encode(List<int>.filled(32, 10 + families.indexOf(family))).replaceAll('=', '')}',
  );
  late final _challenge = HostTrustChallenge.fromJson({
    ...DesignServerFixtures.challenge().toJson(),
    'profileId': _rootProfile.id,
    'expectedRevision': _rootProfile.revision,
    'connectionRevision': _rootProfile.connectionRevision,
    'credentialRevision': _rootProfile.credentialRevision,
    'trustRevision': _rootProfile.trustRevision,
    'key': _pin.toJson(),
    'expiresAt': _futureDeadline,
  });
  late final _inspection = captureRemoteReadPayload('executorInspect', {
    ...DesignServerFixtures.executorInspection(),
    'serverId': _rootProfile.id,
    'expiresAt': _futureDeadline,
    'enrollment': ExecutorEnrollment.fromJson({
      ...DesignServerFixtures.executor().toJson(),
      'serverId': _rootProfile.id,
      'connection': {
        'profileId': _rootProfile.id,
        'connectionRevision': _rootProfile.connectionRevision,
        'credentialRevision': _rootProfile.credentialRevision,
        'trustRevision': _rootProfile.trustRevision,
        'key': _pin.toJson(),
      },
    }).toJson(),
  });

  Map<String, Object?> get _editorDraft => switch (family) {
    'grant-editor' => {
      'label': _grantLabel,
      'scopes': ['read', 'logs', 'author', 'plan'],
      'serverIds': [DesignAutomationFixtures.serverId],
      'lifetimeSeconds': 28800,
    },
    'delegation-editor' => {
      'lifetimeSeconds': 3600,
      'predicates': {
        'greeting': {
          'type': 'enum',
          'values': [_marker('predicate draft')],
        },
      },
    },
    _ => {'greeting': _marker('parameter draft')},
  };

  VoidCallback _action(String name) => () {
    _effects.update(name, (value) => value + 1);
  };
  ValueChanged<T> _change<T>(String name) =>
      (_) => _action(name)();
  static String _pretty(Object? value) =>
      const JsonEncoder.withIndent('  ').convert(value);

  /// The runner owns the real showMotionDialog call and its private UI epoch.
  Widget build(BuildContext dialog) {
    if (_disposed) throw StateError('Disposed privacy body');
    void close() => Navigator.pop(dialog);
    final value = switch (family) {
      'server-overview' => _overview(),
      'trust' => ServerTrustConfirmation(
        challenge: _challenge,
        profile: _rootProfile,
        changes: model,
        currentProfile: () => model.selected,
        currentChallenge: () => model.loaded ? _challenge : null,
        onCancel: close,
        onConfirm: _action('confirmTrust'),
      ),
      'software-catalog' => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 320,
            child: SoftwarePanel(profiles: model, client: null),
          ),
          _recipes(),
        ],
      ),
      'recipe-detail' => _recipes(),
      'preflight' => _planSection(),
      'plan-decision' => AutomationPlanDecisionDialog(
        plan: _plan,
        approve: true,
        serverProfiles: [_server],
        automationProfile: _profile,
        now: DesignAutomationFixtures.presentationNow,
        onBack: close,
        onConfirm: _action('approve'),
      ),
      'logs' => ServerLogsSection(
        logs: _logs,
        filterController: _filter,
        busy: false,
        onLoad: _action('loadLogs'),
        onPrevious: _action('previousLogs'),
        onOpenRecord: _change('openRecord'),
      ),
      'log-record' => ServerLogRecordDialog(
        recordContext: ServerLogRecordContext.capture(_rootProfile, _logs),
        record: (_logs['records'] as List).single as Map<String, Object?>,
        onClose: close,
      ),
      'job-list' || 'job-detail' || 'job-unknown' || 'job-cancel' => _jobs(),
      'automation-profiles' => AutomationProfilesSection(
        profiles: [_profile],
        loaded: true,
        hasMore: false,
        actions: _actions,
        onSelect: _change('selectProfile'),
        onMore: _action('moreProfiles'),
      ),
      'authoring' => AutomationProfileEditorDialog(
        name: _name,
        description: _description,
        body: _body,
        validating: false,
        canValidate: true,
        onBodyChanged: (_) {},
        onClose: close,
        onSave: _action('saveVersion'),
        onValidate: _action('validateVersion'),
      ),
      'revisions' => AutomationProfileDetailSection(
        profile: _profile,
        revision: _revision,
        comparison: DesignAutomationFixtures.comparison(),
        hasServer: true,
        actions: _actions,
        onSelectVersion: _action('selectVersion'),
        onValidate: _action('validate'),
        onCompare: _action('compare'),
        onEdit: _action('edit'),
        onCreatePlan: _action('createPlan'),
        onDelegate: _action('delegate'),
        onArchive: _action('archive'),
      ),
      'parameters' || 'grant-editor' || 'delegation-editor' => _editor(close),
      'grants' || 'mcp-config' => _grants(),
      'delegations-list' => _authorities(),
      'executor' => ServerExecutorConfirmation(
        inspection: _inspection,
        profile: _rootProfile,
        changes: model,
        currentProfile: () => model.selected,
        currentInspection: () => model.loaded ? _inspection : null,
        onCancel: close,
        onConfirm: _action('confirmExecutor'),
      ),
      'invalidated-plan' => _planSection(invalidated: true),
      'revoke-trust' => ServerConfirmationDialog.revoke(
        profile: _rootProfile,
        title: 'Отозвать доверие',
        child: const Text(
          'Доступ к серверу будет остановлен до нового подтверждения ключа.',
        ),
        confirmLabel: 'Отозвать',
        onCancel: close,
        onConfirm: _action('revokeTrust'),
      ),
      'revoke-executor' => ServerConfirmationDialog.revoke(
        profile: _rootProfile,
        title: 'Отозвать привязку',
        child: const Text(
          'Новые изменения через этот исполнитель будут недоступны.',
        ),
        confirmLabel: 'Отозвать',
        onCancel: close,
        onConfirm: _action('revokeExecutor'),
      ),
      'delegation-chooser' => AutomationDelegationGrantDialog(
        grants: [_grant],
        onSelect: _change('selectGrant'),
      ),
      'revoke-grant' => AutomationConfirmationDialog(
        title: 'Отозвать доступ «$_grantLabel»?',
        message: 'Текущий шаг задания может завершиться. Следующие шаги потребуют действующих прав.',
        confirmLabel: 'Отозвать доступ',
        onBack: close,
        onConfirm: _action('revokeGrant'),
      ),
      'archive-profile' => AutomationConfirmationDialog(
        title: 'Архивировать «${_profile.name}»?',
        message: 'История версий и заданий сохранится.',
        confirmLabel: 'Архивировать',
        onBack: close,
        onConfirm: _action('archive'),
      ),
      _ => throw StateError('Unknown family $family'),
    };
    const inline = {
      'server-overview',
      'software-catalog',
      'recipe-detail',
      'preflight',
      'logs',
      'job-list',
      'job-detail',
      'job-unknown',
      'job-cancel',
      'automation-profiles',
      'revisions',
      'grants',
      'mcp-config',
      'delegations-list',
      'invalidated-plan',
    };
    return inline.contains(family)
        ? DeckDialogLayout(title: 'Просмотр', maxWidth: 900, child: value)
        : value;
  }

  Map<String, Object?> get _record => DesignServerFixtures.record(
    timestamp: '2026-10-24T07:08:09.000Z',
    message: _recordMessage,
  );
  late final _logs = Map<String, Object?>.unmodifiable({
    ...DesignServerFixtures.logs(records: [_record]),
    'serverId': _rootProfile.id,
    'identity': {
      ...DesignServerFixtures.identity().toJson(),
      'profileId': _rootProfile.id,
      'connectionRevision': _rootProfile.connectionRevision,
      'credentialRevision': _rootProfile.credentialRevision,
      'trustRevision': _rootProfile.trustRevision,
    },
  });

  ServerOverviewSection _overview() => ServerOverviewSection(
    connection: ServerConnectionSection(
      connection: DesignServerFixtures.connection(),
      trust: DesignServerFixtures.trust(),
      busy: false,
      error: null,
      hasTrustChallenge: false,
      onRefresh: _action('refreshConnection'),
      onProbeTrust: _action('probeTrust'),
      onConfirmTrust: _action('confirmTrust'),
      onConnect: _action('connect'),
      onDisconnect: _action('disconnect'),
      onRevokeTrust: _action('revokeTrust'),
      onCancel: _action('cancelRead'),
    ),
    state: DesignServerFixtures.state(
      system: {
        'hostname': _hostname,
        'architecture': 'x86_64',
        'kernel': 'Linux 6.8.0',
      },
    ),
  );

  AutomationRecipesSection _recipes() => AutomationRecipesSection(
    catalog: DesignAutomationFixtures.catalog(),
    canMutate: true,
    onCreatePlan: _change('createRecipePlan'),
  );

  AutomationPlanSection _planSection({bool invalidated = false}) =>
      AutomationPlanSection(
        plan: _plan,
        runnable: true,
        expired: false,
        invalidReason: invalidated
            ? 'Состояние сервера изменилось. Создайте новый план.'
            : null,
        serverProfiles: [_server],
        automationProfile: _profile,
        actions: _actions,
        onApprove: _action('approve'),
        onDeny: _action('deny'),
        onApply: _action('apply'),
        onRefresh: _action('refreshPlan'),
      );

  AutomationJobsSection _jobs() {
    final state = switch (family) {
      'job-unknown' => 'unknown',
      'job-cancel' => 'cancel-requested',
      _ => 'running',
    };
    final job = AutomationJobRecord.fromJson({
      ...DesignAutomationFixtures.job(state: state),
      'id': _jobId,
    }).toJson();
    final events = [
      for (final event in DesignAutomationFixtures.events())
        AutomationJobEventRecord.fromJson({...event, 'jobId': _jobId}).toJson(),
    ];
    return AutomationJobsSection(
      serverId: DesignAutomationFixtures.serverId,
      jobs: [
        {'job': job},
      ],
      job: family == 'job-list' ? null : job,
      events: family == 'job-list' ? const [] : events,
      loaded: true,
      hasMore: false,
      droppedEvents: 0,
      canCancel: family == 'job-detail',
      canReconcile: family == 'job-unknown',
      actions: _actions,
      onRefresh: _action('refreshJobs'),
      onRefreshAuthorities: _action('refreshAuthorities'),
      onSelect: _change('selectJob'),
      onMore: _action('moreJobs'),
      onShowPlan: _action('showPlan'),
      onCancel: _action('cancelJob'),
      onReconcile: _action('reconcileJob'),
    );
  }

  AutomationGrantsSection _grants() => AutomationGrantsSection(
    grants: [
      AutomationGrantPresentation(
        value: _grant,
        current: automationGrantCurrent(
          _grant,
          now: DesignAutomationFixtures.presentationNow(),
        ),
      ),
    ],
    serverProfiles: [_server],
    loaded: true,
    actions: _actions,
    launchConfiguration: family == 'mcp-config'
        ? {
            'command': _command,
            'args': ['--app-root', _argument, '--grant-id', _grant['id']],
          }
        : null,
    onRefresh: _action('refreshGrants'),
    onCreate: _action('createGrant'),
    onConfigure: _change('configureGrant'),
    onEdit: _change('editGrant'),
    onRevoke: _change('revokeGrant'),
    onCopyConfiguration: _action('copyConfiguration'),
  );

  AutomationAuthoritiesSection _authorities() => AutomationAuthoritiesSection(
    approvals: const [],
    delegations: [
      DelegationRecord.fromJson({
        ...DesignAutomationFixtures.delegation(),
        'grantId': _delegationGrantId,
        'predicates': {
          'greeting': {
            'type': 'enum',
            'values': [_marker('predicate value')],
          },
        },
      }).toJson(),
    ],
    loaded: true,
    hasMoreApprovals: false,
    hasMoreDelegations: false,
    actions: _actions,
    now: DesignAutomationFixtures.presentationNow,
    onOpenPlan: _change('openPlan'),
    onRevokeDelegation: _change('revokeDelegation'),
    onMoreApprovals: _action('moreApprovals'),
    onMoreDelegations: _action('moreDelegations'),
  );

  AutomationJsonEditorDialog _editor(VoidCallback close) {
    final delegating = family == 'delegation-editor';
    final parameters = family == 'parameters';
    return AutomationJsonEditorDialog(
      title: parameters
          ? 'Параметры плана'
          : delegating
          ? 'Делегирование «$_grantLabel» · версия 2'
          : 'Выдать ИИ доступ через MCP',
      input: _input,
      preview: _editorDraft,
      purpose: parameters
          ? 'Проверьте параметры для выбранной версии. Продолжение создаст план; запуск потребует отдельного подтверждения.'
          : delegating
          ? 'Разрешить запуск только этой неизменной версии в заданных границах параметров. Новые версии потребуют отдельного делегирования.'
          : 'Выдайте только необходимые права на перечисленные серверы. Сохранение выдаст доступ клиенту ИИ на указанный срок.',
      target: parameters
          ? 'Ansible-профиль: ${_profile.name} · версия 2.'
          : delegating
          ? 'Ansible-профиль: ${_profile.name} · версия 2. Доступ клиента до: ${_grant['expiresAt']} (UTC).'
          : null,
      serverProfiles: [_server],
      targetServerIds: [
        if (parameters || delegating) DesignAutomationFixtures.serverId,
      ],
      contextDetails: parameters || delegating
          ? {
              'profileId': _profile.id,
              'revision': _revision['revision'],
              'bodyDigest': _revision['digest'],
              'serverId': DesignAutomationFixtures.serverId,
              if (delegating) 'grantId': _grant['id'],
            }
          : null,
      onClose: close,
      onContinue: _action('continueEditor'),
    );
  }

  /// External editor controllers belong to this test fixture. Call only after
  /// the route/body has unmounted; this is not an app-owner disposal assertion.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final controller in [_filter, _name, _description, _body, _input]) {
      controller.dispose();
    }
  }
}
