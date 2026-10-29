import 'dart:async';

import 'package:flutter/material.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';

import '../theme/motion.dart';
import '../ui/deck_page.dart';
import 'server_compositions.dart';
import 'server_controller.dart';
import 'server_sections.dart';

enum ServerPanelSection {
  overview,
  software,
  resources,
  saved,
  logs,
  configuration,
  executor,
}

/// Remote operations use the same service as MCP through a verified owner RPC.
class ServerPanel extends StatefulWidget {
  const ServerPanel({
    super.key,
    required this.client,
    required this.profile,
    this.initialSection = ServerPanelSection.overview,
    this.onSectionChanged,
    this.onOpenSoftware,
    this.onOpenAutomation,
    this.onBack,
    this.contextBar,
  });
  final Widget? contextBar;
  final ServerPanelSection initialSection;
  final ValueChanged<ServerPanelSection>? onSectionChanged;
  final VoidCallback? onOpenSoftware, onOpenAutomation, onBack;
  final TrustedApiClient client;
  final ProfileView profile;
  @override
  State<ServerPanel> createState() => _ServerPanelState();
}

class _ServerPanelState extends State<ServerPanel> {
  late ServerController model;
  late ProfileView _operationProfile;
  final _text = TextEditingController();
  final _profileChanges = ValueNotifier(0);
  final _logsKey = GlobalKey<ServerLogsSectionState>();
  bool _retired = false;
  ServerPresentationOperation _operation = ServerPresentationOperation.read;
  Object? _trustConfirmChallenge;
  bool _dispatching = false, _wasBusy = false;
  String _resource = 'system.motd';
  late ServerPanelSection _section;
  String? _unit, _loadedUnit, _loadedText;
  bool _unitScope = false;

  Rect? _workspaceBounds() {
    if (!mounted) return null;
    final render = context.findRenderObject();
    if (render is! RenderBox || !render.attached || !render.hasSize)
      return null;
    return render.localToGlobal(Offset.zero) & render.size;
  }

  EdgeInsetsGeometry _workspaceInsets() =>
      mounted ? DeckPageInsets.of(context) : EdgeInsets.zero;
  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
    _text.addListener(_filterChanged);
    _create();
  }

  void _create() {
    _operation = ServerPresentationOperation.read;
    _operationProfile = widget.profile;
    _trustConfirmChallenge = null;
    _wasBusy = false;
    model = ServerController(
      client: widget.client,
      profileId: widget.profile.id,
    );
    model.addListener(_observeOperation);
    model.refresh().ignore();
  }

  void _observeOperation() {
    // A sampler/read that starts outside an explicit panel dispatch must not
    // inherit an old write label. This observes existing owner notifications.
    if (model.busy && !_wasBusy) _operationProfile = widget.profile;
    if (model.busy && !_wasBusy && !_dispatching) {
      _operation = ServerPresentationOperation.read;
      _trustConfirmChallenge = null;
    }
    _wasBusy = model.busy;
  }

  Future<void> _dispatch(
    ServerPresentationOperation operation,
    Future<void> Function() action,
  ) async {
    if (!mounted || _retired || model.busy || widget.client.isClosed) return;
    _operation = operation;
    _trustConfirmChallenge =
        operation == ServerPresentationOperation.trustConfirm
        ? model.trustChallenge
        : null;
    _dispatching = true;
    late Future<void> result;
    try {
      result = action();
    } finally {
      _dispatching = false;
    }
    await result;
  }

  @override
  void didUpdateWidget(covariant ServerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.client, widget.client) ||
        oldWidget.profile.id != widget.profile.id) {
      model.removeListener(_observeOperation);
      model.dispose();
      _text.clear();
      _unit = _loadedUnit = _loadedText = null;
      _unitScope = false;
      _create();
    }
    if (oldWidget.initialSection != widget.initialSection)
      _section = widget.initialSection;
    _profileChanges.value++;
  }

  void _filterChanged() {
    if (mounted) setState(() {});
  }

  void _select(ServerPanelSection section) {
    setState(() => _section = section);
    widget.onSectionChanged?.call(section);
  }

  @override
  void dispose() {
    _retired = true;
    _profileChanges.value++;
    model.removeListener(_observeOperation);
    model.dispose();
    _text.dispose();
    _profileChanges.dispose();
    super.dispose();
  }

  bool _reviewIsCurrent(ServerController owner, ProfileView profile) =>
      mounted &&
      !_retired &&
      identical(owner, model) &&
      !widget.client.isClosed &&
      serverProfileReviewIsCurrent(profile, widget.profile);

  Future<bool> _confirm(
    String title,
    Widget content,
    String action, {
    bool Function()? consentCurrent,
  }) async {
    final owner = model, profile = widget.profile;
    final confirmed = await showServerConfirmationDialog(
      context: context,
      profile: profile,
      title: title,
      child: content,
      confirmLabel: action,
      changes: Listenable.merge([owner, _profileChanges]),
      currentProfile: () => mounted && !_retired ? widget.profile : null,
      currentOwner: () =>
          _reviewIsCurrent(owner, profile) && (consentCurrent?.call() ?? true),
    );
    return confirmed &&
        _reviewIsCurrent(owner, profile) &&
        (consentCurrent?.call() ?? true);
  }

  Future<void> _trust() async {
    final owner = model;
    final challenge = model.trustChallenge;
    if (challenge == null) return;
    final profile = widget.profile;
    if (await showMotionDialog<bool>(
              context: context,
              barrierDismissible: true,
              barrierColor: Colors.transparent,
              builder: (context) => ServerTrustConfirmation(
                workspaceBounds: _workspaceBounds,
                pageInsets: _workspaceInsets,
                challenge: challenge,
                profile: profile,
                changes: Listenable.merge([owner, _profileChanges]),
                currentProfile: () =>
                    mounted && !_retired ? widget.profile : null,
                currentChallenge: () =>
                    mounted && !_retired && identical(owner, model)
                    ? model.trustChallenge
                    : null,
                onCancel: () => Navigator.pop(context, false),
                onConfirm: () => Navigator.pop(context, true),
              ),
            ) ==
            true &&
        mounted &&
        identical(owner, model) &&
        identical(challenge, model.trustChallenge) &&
        serverTrustReviewIsCurrent(
          challenge: challenge,
          profile: profile,
          currentProfile: widget.profile,
          currentChallenge: model.trustChallenge,
        ))
      await _dispatch(
        ServerPresentationOperation.trustConfirm,
        model.confirmTrust,
      );
  }

  Future<void> _executor() async {
    final owner = model;
    final inspection = model.executorInspection;
    final enrolled = model.executor;
    if (inspection == null) return;
    final profile = widget.profile;
    final changes = Listenable.merge([owner, _profileChanges]);
    bool current() =>
        mounted &&
        !_retired &&
        identical(owner, model) &&
        serverExecutorReviewIsCurrent(
          inspection: inspection,
          profile: profile,
          currentProfile: widget.profile,
          currentInspection: model.executorInspection,
        );
    var retired = !current();
    void observe() => retired = retired || !current();
    changes.addListener(observe);
    try {
      final confirmed = await showMotionDialog<bool>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        builder: (context) => ServerExecutorConfirmation(
          workspaceBounds: _workspaceBounds,
          pageInsets: _workspaceInsets,
          inspection: inspection,
          profile: profile,
          changes: changes,
          currentProfile: () => mounted && !_retired ? widget.profile : null,
          currentInspection: () =>
              mounted && !_retired && identical(owner, model)
              ? model.executorInspection
              : null,
          onCancel: () => Navigator.pop(context, false),
          onConfirm: () => Navigator.pop(context, true),
          onRevoke: enrolled == null
              ? null
              : () => _revokeExecutor(
                  consentCurrent: () =>
                      current() && identical(owner.executor, enrolled),
                ).ignore(),
        ),
      );
      if (confirmed == true && !retired && current())
        await _dispatch(
          ServerPresentationOperation.executorWrite,
          owner.confirmExecutor,
        );
    } finally {
      changes.removeListener(observe);
    }
  }

  Future<void> _revokeTrust() async {
    final owner = model, profile = widget.profile;
    if (await _confirm(
          'Отозвать доверие',
          const Text(
            'Доступ к серверу будет остановлен до нового подтверждения ключа.',
          ),
          'Отозвать',
        ) &&
        _reviewIsCurrent(owner, profile))
      // This handler reads before its write. Without an owner phase marker a
      // timeout cannot establish whether the revoke was dispatched or ACKed.
      await _dispatch(
        ServerPresentationOperation.trustRevoke,
        owner.revokeTrust,
      );
  }

  Future<void> _revokeExecutor({bool Function()? consentCurrent}) async {
    final owner = model, profile = widget.profile;
    if (await _confirm(
          'Отозвать привязку',
          const Text(
            'Новые изменения через этот исполнитель будут недоступны.',
          ),
          'Отозвать',
          consentCurrent: consentCurrent,
        ) &&
        _reviewIsCurrent(owner, profile) &&
        (consentCurrent?.call() ?? true))
      await _dispatch(
        ServerPresentationOperation.executorWrite,
        owner.revokeExecutor,
      );
  }

  Future<void> _readLogs({bool previous = false}) async {
    final owner = model;
    final oldResult = owner.logs;
    final unit = previous
        ? _loadedUnit
        : _unitScope
        ? _unit
        : null;
    final text = previous ? _loadedText : _text.text;
    final cursor = previous ? (oldResult?['nextCursor'] as String?) : null;
    if (previous && cursor == null) return;
    await _dispatch(
      ServerPresentationOperation.read,
      () => owner.loadLogs(unit: unit, text: text, cursor: cursor),
    );
    if (mounted &&
        identical(owner, model) &&
        !identical(oldResult, owner.logs)) {
      setState(() {
        _loadedUnit = unit;
        _loadedText = text;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      final profile = widget.profile;
      final currentOperation = serverProfileReviewIsCurrent(
        _operationProfile,
        profile,
      );
      final error = currentOperation ? model.error : null;
      final logs =
          ServerLogRecordContext.capture(profile, model.logs).profile == null
          ? null
          : model.logs;
      final observation = model.state;
      final identity = observation?['identity'] as Map<String, Object?>?;
      final state =
          observation?['serverId'] == profile.id &&
              identity?['profileId'] == profile.id &&
              identity?['connectionRevision'] == profile.connectionRevision &&
              identity?['credentialRevision'] == profile.credentialRevision &&
              identity?['trustRevision'] == profile.trustRevision
          ? observation
          : null;
      final connectionValue = model.connection;
      final matchingConnection =
          connectionValue?.profileId == profile.id &&
              (connectionValue?.state == 'disconnected' ||
                  serverConnectionMatchesProfile(
                    connectionValue?.identity,
                    profile,
                  ))
          ? connectionValue
          : null;
      final trustValue = model.trust;
      final matchingTrust =
          trustValue?.profileId == profile.id &&
              trustValue?.connectionRevision == profile.connectionRevision &&
              trustValue?.credentialRevision == profile.credentialRevision &&
              trustValue?.trustRevision == profile.trustRevision
          ? trustValue
          : null;
      final executorValue = model.executor;
      final matchingExecutor =
          serverConnectionMatchesProfile(executorValue?.connection, profile)
          ? executorValue
          : null;
      final configurationValue = model.configuration;
      final configurationObservation =
          configurationValue?['observation'] as Map<String, Object?>?;
      final matchingConfiguration =
          configurationValue?['serverId'] == profile.id &&
              configurationObservation?['targetRevision'] == profile.revision &&
              configurationObservation?['connectionRevision'] ==
                  profile.connectionRevision &&
              configurationObservation?['accessRevision'] ==
                  profile.credentialRevision &&
              configurationObservation?['trustRevision'] ==
                  profile.trustRevision
          ? configurationValue
          : null;
      final recordContext = ServerLogRecordContext.capture(profile, logs);
      void readState() => _dispatch(
        ServerPresentationOperation.read,
        model.refreshState,
      ).ignore();
      final connection = ServerConnectionSection(
        connection: matchingConnection,
        trust: matchingTrust,
        busy: model.busy,
        error: error,
        busyLabel: currentOperation
            ? 'Выполняется операция сервера'
            : 'Ожидаем операцию прежних параметров профиля',
        operation: _operation,
        trustWriteAcknowledged:
            _operation == ServerPresentationOperation.trustConfirm &&
            _trustConfirmChallenge != null &&
            model.trustChallenge == null &&
            !widget.client.isClosed,
        hasTrustChallenge:
            model.trustChallenge != null &&
            serverTrustReviewIsCurrent(
              challenge: model.trustChallenge!,
              profile: profile,
              currentProfile: profile,
              currentChallenge: model.trustChallenge,
            ),
        onRefresh: () =>
            _dispatch(ServerPresentationOperation.read, model.refresh).ignore(),
        onProbeTrust: () => _dispatch(
          ServerPresentationOperation.read,
          model.probeTrust,
        ).ignore(),
        onConfirmTrust: () => _trust().ignore(),
        onConnect: () => _dispatch(
          ServerPresentationOperation.connectionWrite,
          model.connect,
        ).ignore(),
        onDisconnect: () => _dispatch(
          ServerPresentationOperation.connectionWrite,
          model.disconnect,
        ).ignore(),
        onRevokeTrust: () => _revokeTrust().ignore(),
        onCancel: () {
          _operation = ServerPresentationOperation.read;
          _trustConfirmChallenge = null;
          model.cancel().ignore();
        },
      );
      final unitsObservation = state?['units'] as Map<String, Object?>?;
      final units = [
        for (final row in (unitsObservation?['value'] as List? ?? const []))
          if (row is Map<String, Object?> && row['name'] is String)
            row['name'] as String,
      ];
      final connected =
          matchingConnection?.state == 'connected' &&
          matchingConnection?.interested == true;
      final changedKey = error == 'TRUST_CHANGED';
      final title = changedKey
          ? 'SSH-ключ изменился'
          : switch (_section) {
              ServerPanelSection.logs => 'Журнал сервера',
              ServerPanelSection.executor => 'Подготовка исполнителя',
              ServerPanelSection.configuration => 'Управляемая конфигурация',
              _ => 'Обзор сервера',
            };
      return ServerPageFrame(
        profile: profile,
        title: title,
        eyebrow:
            '${_section == ServerPanelSection.logs ? 'Журналы' : 'Серверы'} / Рабочее пространство',
        description: changedKey
            ? 'Сведения, наблюдения и доступные действия'
            : _section == ServerPanelSection.logs
            ? 'События выбранного сервера в хронологическом порядке'
            : 'Система, ресурсы и программное обеспечение ${profile.name}',
        actions: serverPageHeaderActions(
          busy: model.busy,
          connected: connected,
          changedKey: changedKey,
          logs: _section == ServerPanelSection.logs,
          onConnect: connection.onConnect,
          onDisconnect: connection.onDisconnect,
          onRefresh: readState,
          onSearch: () => _logsKey.currentState?.focusSearch(),
          onFilters: () => _logsKey.currentState?.toggleFilters(),
        ),
        contextBar: _section == ServerPanelSection.logs
            ? null
            : widget.contextBar,
        showIdentity: !changedKey && _section != ServerPanelSection.logs,
        identityStatus: ServerConnectionBadge(connection: matchingConnection),
        contentActions: !changedKey && _section == ServerPanelSection.overview
            ? serverOverviewActions(
                onSoftware: () => _select(ServerPanelSection.software),
                onLogs: () => _select(ServerPanelSection.logs),
              )
            : const [],
        selectedTab: switch (_section) {
          ServerPanelSection.software => 1,
          ServerPanelSection.resources => 2,
          ServerPanelSection.saved => 4,
          _ => 0,
        },
        showServerTabs: !changedKey && _section != ServerPanelSection.logs,
        onTabSelected: (index) {
          if (index == 3) {
            widget.onOpenAutomation?.call();
          } else {
            _select(
              [
                ServerPanelSection.overview,
                ServerPanelSection.software,
                ServerPanelSection.resources,
                ServerPanelSection.overview,
                ServerPanelSection.saved,
              ][index],
            );
          }
        },
        child: changedKey
            ? ServerChangedKeySection(
                profile: profile,
                previousFingerprint: model.trust?.trust?.key.fingerprint,
                currentFingerprint: model.trustChallenge?.key.fingerprint,
                onReview: model.busy ? null : connection.onProbeTrust,
                onClose: widget.onBack,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_section == ServerPanelSection.overview) ...[
                    ServerOverviewSection(
                      state: state,
                      connection: connection,
                      profile: profile,
                      onCloseChangedKey: widget.onBack,
                      currentFingerprint: model.trustChallenge?.key.fingerprint,
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          clipBehavior: Clip.none,
                          onPressed: () => _select(ServerPanelSection.executor),
                          child: const Text('Подготовка исполнителя'),
                        ),
                        OutlinedButton(
                          clipBehavior: Clip.none,
                          onPressed: () =>
                              _select(ServerPanelSection.configuration),
                          child: const Text('Управляемая конфигурация'),
                        ),
                      ],
                    ),
                  ],
                  if (_section == ServerPanelSection.resources)
                    ServerSystemSection(state: state),
                  if (_section == ServerPanelSection.saved)
                    DeckPanel(
                      title: 'Offline / сохранённые данные',
                      child: Column(
                        children: [
                          const Text(
                            'Показаны только удерживаемые текущим владельцем наблюдения. Актуальность нового соединения не подтверждена.',
                          ),
                          ServerSystemSection(state: state, showHistory: false),
                        ],
                      ),
                    ),
                  if (_section == ServerPanelSection.software)
                    ServerSoftwareSnapshot(
                      state: state,
                      onOpenCatalog: widget.onOpenSoftware,
                    ),
                  if (_section == ServerPanelSection.executor)
                    ServerExecutorSection(
                      executor: matchingExecutor,
                      hasInspection:
                          model.executorInspection != null &&
                          serverExecutorReviewIsCurrent(
                            inspection: model.executorInspection!,
                            profile: profile,
                            currentProfile: profile,
                            currentInspection: model.executorInspection,
                          ),
                      busy: model.busy,
                      onRefreshState: readState,
                      onInspect: () => _dispatch(
                        ServerPresentationOperation.read,
                        model.inspectExecutor,
                      ).ignore(),
                      onConfirm: () => _executor().ignore(),
                      onRevoke: () => _revokeExecutor().ignore(),
                    ),
                  if (_section == ServerPanelSection.configuration)
                    ServerConfigurationSection(
                      resource: _resource,
                      busy: model.busy,
                      onResourceChanged: (value) {
                        if (value != null) setState(() => _resource = value);
                      },
                      onRead: () => _dispatch(
                        ServerPresentationOperation.read,
                        () => model.readConfiguration(_resource),
                      ).ignore(),
                      result: matchingConfiguration == null
                          ? null
                          : _Configuration(value: matchingConfiguration),
                    ),
                  if (_section == ServerPanelSection.logs && error != null)
                    ServerOwnerStatus(
                      error: error,
                      operation: _operation,
                      trustWriteAcknowledged: connection.trustWriteAcknowledged,
                    ),
                  if (_section == ServerPanelSection.logs)
                    ServerLogsSection(
                      key: _logsKey,
                      targetSelector: widget.contextBar,
                      showHeaderActions: false,
                      profile: profile,
                      logs: logs,
                      filterController: _text,
                      busy: model.busy,
                      units: units,
                      selectedUnit: _unit,
                      unitScope: _unitScope,
                      onScopeChanged: (scope) => setState(() {
                        _unitScope = scope;
                        if (!scope) _unit = null;
                      }),
                      onUnitChanged: (unit) => setState(() => _unit = unit),
                      canRead:
                          !_unitScope ||
                          (_unit != null && units.contains(_unit)),
                      canPrevious:
                          _loadedUnit == (_unitScope ? _unit : null) &&
                          _loadedText == _text.text,
                      onLoad: () => _readLogs().ignore(),
                      onPrevious: () => _readLogs(previous: true).ignore(),
                      onOpenRecord: (row) => showMotionDialog<void>(
                        context: context,
                        barrierDismissible: true,
                        barrierColor: Colors.transparent,
                        builder: (context) => ServerLogRecordDialog(
                          workspaceBounds: _workspaceBounds,
                          pageInsets: _workspaceInsets,
                          recordContext: recordContext,
                          record: row,
                          onClose: () => Navigator.pop(context),
                        ),
                      ),
                    ),
                  if (_section != ServerPanelSection.overview &&
                      _section != ServerPanelSection.logs) ...[
                    const SizedBox(height: 20),
                    connection,
                  ],
                ],
              ),
      );
    },
  );
}

class _Configuration extends StatefulWidget {
  const _Configuration({required this.value});
  final Map<String, Object?> value;
  @override
  State<_Configuration> createState() => _ConfigurationState();
}

class _ConfigurationState extends State<_Configuration> {
  Timer? _age;
  Map<String, Object?> get value => widget.value;
  @override
  void initState() {
    super.initState();
    _scheduleAge();
  }

  @override
  void didUpdateWidget(covariant _Configuration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.value, widget.value)) _scheduleAge();
  }

  void _scheduleAge() {
    _age?.cancel();
    final comparison = value['comparison'] as Map<String, Object?>;
    if (!const {'matched', 'drift'}.contains(comparison['status'])) return;
    final observed = DateTime.tryParse('${comparison['observedAt']}');
    if (observed == null) return;
    final left = observed
        .add(const Duration(seconds: 15, milliseconds: 1))
        .difference(DateTime.now().toUtc());
    if (left <= Duration.zero) return;
    _age = Timer(left, () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _age?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final comparison = value['comparison'] as Map<String, Object?>;
    var comparisonStatus = comparison['status'];
    if (const {'matched', 'drift'}.contains(comparisonStatus)) {
      final observed = DateTime.tryParse('${comparison['observedAt']}');
      final age = observed == null
          ? null
          : DateTime.now().toUtc().difference(observed);
      if (age == null || age.isNegative || age > const Duration(seconds: 15))
        comparisonStatus = 'stale';
    }
    return ServerConfigurationResult(
      value: value,
      comparisonStatus: comparisonStatus,
    );
  }
}
