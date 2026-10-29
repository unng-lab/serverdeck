import 'package:flutter/material.dart';
import 'package:serverdeck_protocol/models.dart'
    show ProfileView, ReadinessState, ErrorCode;
import 'package:serverdeck_windows/operational_auth_client.dart';

import '../automation/automation_panel.dart';
import '../profiles/profile_controller.dart';
import '../profiles/profile_list.dart';
import '../profiles/recovery_view.dart';
import '../profiles/startup_recovery.dart';
import '../servers/server_panel.dart';
import '../servers/server_sections.dart' show ServerLogTargetSelector;
import '../settings/settings_view.dart';
import '../software/software_panel.dart';
import '../ui/deck_page.dart';
import '../ui/deck_icon.dart';
import '../theme/motion.dart';
import 'foundation_shell.dart';
import 'deck_navigation.dart';

/// Production navigation borrows the existing authenticated service owners.
class BaseWorkspace extends StatefulWidget {
  const BaseWorkspace({
    super.key,
    required this.profiles,
    required this.recovery,
    required this.client,
    required this.state,
    this.privateEpoch = 0,
    this.reason,
    this.retryInProgress = false,
    this.onRetry,
  });
  final ProfileController profiles;
  final StartupRecovery recovery;
  final TrustedApiClient? client;
  final ReadinessState state;
  final int privateEpoch;
  final ErrorCode? reason;
  final bool retryInProgress;
  final VoidCallback? onRetry;
  @override
  State<BaseWorkspace> createState() => _BaseWorkspaceState();
}

class _BaseWorkspaceState extends State<BaseWorkspace> {
  final _navigation = DeckNavigationController();
  DeckLocation? _recentCaller;
  DeckLocation get _location => _navigation.value;
  FoundationSection get _section => _location.section;
  Object? _planReviewToken;
  DeckLocation? _planReviewOrigin;
  int? _planReviewEpoch;
  String? _planReviewServerId;
  void _clearPlanReview() {
    _planReviewToken = null;
    _planReviewOrigin = null;
    _planReviewEpoch = null;
    _planReviewServerId = null;
  }

  void _retireChangedPlanReview() {
    if (_planReviewToken != null &&
        (!identical(_planReviewOrigin, _location) ||
            _planReviewServerId != _target?.id)) {
      _clearPlanReview();
    }
  }

  @override
  void initState() {
    super.initState();
    _navigation.addListener(_retireChangedPlanReview);
    widget.profiles.addListener(_retireChangedPlanReview);
  }

  FoundationSection get _visualSection =>
      _planReviewToken != null &&
          identical(_planReviewOrigin, _location) &&
          _planReviewEpoch == widget.privateEpoch &&
          _planReviewServerId == _target?.id &&
          widget.state == ReadinessState.ready
      ? FoundationSection.jobs
      : _section;

  VoidCallback _beginPlanReview() {
    if (!mounted || widget.state != ReadinessState.ready) return () {};
    final token = Object();
    setState(() {
      _planReviewToken = token;
      _planReviewOrigin = _location;
      _planReviewEpoch = widget.privateEpoch;
      _planReviewServerId = _target?.id;
    });
    return () {
      if (!mounted || !identical(_planReviewToken, token)) return;
      setState(_clearPlanReview);
    };
  }

  String? get _serverId => _location.serverId;
  ServerPanelSection _serverSection = ServerPanelSection.overview;
  String get _automationSection => switch (_location.view) {
    DeckView.automationProfiles => 'profiles',
    DeckView.grants => 'grants',
    _ => 'jobs',
  };
  @override
  void dispose() {
    widget.profiles.removeListener(_retireChangedPlanReview);
    _navigation.removeListener(_retireChangedPlanReview);
    _navigation.dispose();
    super.dispose();
  }

  Key _serverKey = UniqueKey();
  Key _automationKey = UniqueKey();
  Key _profilesKey = UniqueKey();
  Key _settingsKey = UniqueKey();
  Key _softwareKey = UniqueKey();
  @override
  void didUpdateWidget(covariant BaseWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.profiles, widget.profiles)) {
      oldWidget.profiles.removeListener(_retireChangedPlanReview);
      widget.profiles.addListener(_retireChangedPlanReview);
      _clearPlanReview();
    }
    if (widget.state != ReadinessState.ready ||
        oldWidget.privateEpoch != widget.privateEpoch ||
        !identical(oldWidget.client, widget.client)) {
      _clearPlanReview();
    }
    if (oldWidget.privateEpoch != widget.privateEpoch ||
        !identical(oldWidget.client, widget.client)) {
      _serverKey = UniqueKey();
      _automationKey = UniqueKey();
      _profilesKey = UniqueKey();
      _settingsKey = UniqueKey();
      _softwareKey = UniqueKey();
      if (_location.view == DeckView.recentOperations)
        _navigation.open(
          DeckLocation(view: DeckView.jobs, serverId: _serverId),
        );
      _recentCaller = null;
    }
  }

  ProfileView? get _target {
    final id = _serverId ?? widget.profiles.selected?.id;
    for (final profile in widget.profiles.profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  void _navigate(FoundationSection section) => setState(() {
    _navigation.open(
      DeckLocation(view: DeckView.forSection(section), serverId: _serverId),
    );
    _recentCaller = null;
    if (section == FoundationSection.logs)
      _serverSection = ServerPanelSection.logs;
  });
  void _openProfile(ProfileView profile) => setState(() {
    _navigation.open(DeckLocation(view: DeckView.server, serverId: profile.id));
    _serverSection = ServerPanelSection.overview;
    _recentCaller = null;
  });
  void _automation(DeckView view) => setState(() {
    _navigation.open(DeckLocation(view: view, serverId: _serverId));
    _recentCaller = null;
  });
  Widget _targetSelector() => DeckPanel(
    padding: const EdgeInsets.all(12),
    child: MotionDropdown<String>(
      key: ValueKey('workspace-target-${_target?.id}'),
      initialValue: _target?.id,
      decoration: const InputDecoration(
        labelText: 'Сервер',
        helperText: 'Выбор цели не подключает сервер',
      ),
      items: [
        for (final profile in widget.profiles.profiles)
          DropdownMenuItem(
            value: profile.id,
            child: Text('${profile.name} · ${profile.address}'),
          ),
      ],
      changes: widget.profiles,
      available: () => widget.state == ReadinessState.ready,
      onChanged: widget.state != ReadinessState.ready
          ? null
          : (id) {
              if (!mounted || widget.state != ReadinessState.ready) return;
              if (!widget.profiles.profiles.any((profile) => profile.id == id))
                return;
              setState(() => _navigation.open(_location.withServer(id)));
            },
    ),
  );
  Widget _chooseTarget(String title, String description) => DeckPage(
    title: title,
    eyebrow: '$title / Рабочее пространство',
    description: description,
    contextBar: _targetSelector(),
    child: DeckPanel(
      child: DeckEmptyState(
        title: 'Выберите сервер',
        description: widget.profiles.profiles.isEmpty
            ? 'Добавьте сервер в локальное пространство, чтобы открыть его данные.'
            : 'Журнал и состояние относятся к конкретному серверу. Выберите цель в списке.',
        actions: [
          FilledButton(
            clipBehavior: Clip.none,
            onPressed: () => _navigate(FoundationSection.servers),
            child: const DeckButtonLabel(icon: 'server', label: 'К серверам'),
          ),
        ],
      ),
    ),
  );
  Widget _logTargetSelector() => ServerLogTargetSelector(
    profiles: widget.profiles.profiles,
    selectedId: _target?.id,
    changes: widget.profiles,
    available: () =>
        widget.state == ReadinessState.ready && widget.profiles.loaded,
    onSelected: widget.state != ReadinessState.ready
        ? null
        : (id) {
            if (!mounted ||
                widget.state != ReadinessState.ready ||
                !widget.profiles.loaded)
              return;
            if (!widget.profiles.profiles.any((profile) => profile.id == id))
              return;
            setState(() => _navigation.open(_location.withServer(id)));
          },
  );
  Widget _server() {
    final target = _target, client = widget.client;
    if (target == null || client == null)
      return _chooseTarget(
        'Журнал сервера',
        'События выбранного сервера и точный источник данных.',
      );
    return ServerPanel(
      key: _serverKey,
      client: client,
      profile: target,
      initialSection: _serverSection,
      contextBar: _section == FoundationSection.logs
          ? _logTargetSelector()
          : null,
      onSectionChanged: (section) => setState(() {
        _serverSection = section;
        _navigation.open(
          DeckLocation(
            view: section == ServerPanelSection.logs
                ? DeckView.logs
                : DeckView.server,
            serverId: _serverId,
          ),
        );
      }),
      onBack: () => setState(() {
        _serverSection = ServerPanelSection.overview;
        _navigation.open(DeckLocation(serverId: _serverId));
      }),
      onOpenSoftware: () => _navigate(FoundationSection.software),
      onOpenAutomation: () => _automation(DeckView.automationProfiles),
    );
  }

  Widget _software() {
    final location = _location;
    final key = _softwareKey;
    final client = widget.client;
    final profiles = widget.profiles;
    return SoftwarePanel(
      key: key,
      profiles: profiles,
      client: client,
      onPlanReview: _beginPlanReview,
      serverId: location.serverId,
      onServerSelected: (id) {
        if (!mounted ||
            widget.state != ReadinessState.ready ||
            !profiles.loaded ||
            !identical(widget.profiles, profiles) ||
            !identical(widget.client, client) ||
            _softwareKey != key ||
            !identical(_location, location) ||
            !profiles.profiles.any((profile) => profile.id == id)) {
          return;
        }
        setState(() => _navigation.open(location.withServer(id)));
      },
    );
  }

  Widget _automationContent(String title, String description) =>
      widget.client == null
      ? DeckPage(
          title: title,
          eyebrow: _section == FoundationSection.settings
              ? 'Настройки / Рабочее пространство'
              : 'Задания / Рабочее пространство',
          description: description,
          actions: _jobsActions,
          contextBar: _targetSelector(),
          child: const DeckPanel(
            child: DeckEmptyState(
              title: 'Подключение к службе не подтверждено',
              description: 'Для работы с автоматизацией требуется подтверждённое локальное соединение. Выбор сервера не подтверждает доступ к службе; подготовка профилей допускается и без сервера.',
            ),
          ),
        )
      : AutomationPanel(
          key: _automationKey,
          client: widget.client!,
          serverId: _target?.id,
          initialSection: _automationSection,
          serverProfiles: widget.profiles.profiles,
          contextBar: _targetSelector(),
          workspaceActions: _jobsActions,
          onPlanReview: _beginPlanReview,
        );
  List<Widget> get _jobsActions => _location.view == DeckView.jobs
      ? [
          OutlinedButton(
            clipBehavior: Clip.none,
            onPressed: () => _automation(DeckView.grants),
            child: const Text('ИИ-доступ'),
          ),
          OutlinedButton(
            clipBehavior: Clip.none,
            onPressed: () => _automation(DeckView.automationProfiles),
            child: const Text('Ansible-профили'),
          ),
        ]
      : const [];
  Widget _content(BuildContext context, FoundationSection section) {
    if (section == FoundationSection.settings &&
        _location.view == DeckView.grants) {
      return _automationContent(
        'Доступ ИИ',
        'Для управления доступом ИИ требуется подтверждённое подключение к локальной службе.',
      );
    }
    if (_location.view == DeckView.recentOperations)
      return RecentOperationsView(
        recovery: widget.recovery,
        asPage: true,
        onClose: () => setState(() {
          _navigation.open(
            _recentCaller ??
                DeckLocation(view: DeckView.jobs, serverId: _serverId),
          );
          _recentCaller = null;
        }),
      );
    return switch (section) {
      FoundationSection.servers =>
        _location.view == DeckView.server && _target != null
            ? _server()
            : ProfileList(
                key: _profilesKey,
                controller: widget.profiles,
                controlClient: widget.client,
                onOpenProfile: _openProfile,
                onAiAccess: () => _automation(DeckView.grants),
              ),
      FoundationSection.logs => _server(),
      FoundationSection.software => _software(),
      FoundationSection.jobs => _automationContent(
        _location.view == DeckView.automationProfiles
            ? 'Ansible-профили'
            : 'Задания',
        _location.view == DeckView.automationProfiles
            ? 'Подготовка профилей допускается без выбранного сервера.'
            : 'Выберите область просмотра заданий.',
      ),
      FoundationSection.settings => SettingsView(
        key: _settingsKey,
        controller: widget.profiles,
        onAiAccess: () => _automation(DeckView.grants),
      ),
    };
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.profiles,
    builder: (context, _) => FoundationShell(
      state: widget.state,
      reason: widget.reason,
      retryInProgress: widget.retryInProgress,
      onRetry: widget.onRetry,
      section: _visualSection,
      onSectionSelected: _navigate,
      recoveryAction: RecentOperationsButton(
        recovery: widget.recovery,
        onOpen: () => setState(() {
          if (_location.view == DeckView.recentOperations) return;
          _recentCaller = _location;
          _navigation.open(
            DeckLocation(view: DeckView.recentOperations, serverId: _serverId),
          );
        }),
      ),
      onWorkspace: () => showMotionDialog<void>(
        context: context,
        privateContent: widget.state == ReadinessState.ready,
        builder: (dialog) => AlertDialog(
          title: const Text('Локальное пространство'),
          content: Text(
            widget.state == ReadinessState.ready
                ? '${widget.profiles.profiles.length} профилей на этом устройстве. Настройки и история хранятся в локальном пространстве.'
                : 'Локальное пространство этого устройства. Дождитесь готовности локальной службы.',
          ),
          actions: [
            TextButton(
              clipBehavior: Clip.none,
              onPressed: () {
                Navigator.pop(dialog);
                _navigate(FoundationSection.settings);
              },
              child: const Text('Настройки'),
            ),
            TextButton(
              clipBehavior: Clip.none,
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      ),
      contentBuilder: (context, _) => KeyedSubtree(
        key: ValueKey('workspace-private-${widget.privateEpoch}'),
        child: RecoveryView(
          recovery: widget.recovery,
          child: _content(context, _section),
        ),
      ),
    ),
  );
}
