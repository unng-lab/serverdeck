import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide ConnectionState;

import '../domain/models.dart';
import '../console/console_owner.dart';
import '../console/console_view.dart';
import '../software/software_owner.dart';
import '../software/software_view.dart';
import '../journals/journal_owner.dart';
import '../journals/journal_view.dart';
import '../shell/foundation_shell.dart';
import '../domain/error_presentation.dart';
import '../ui/deck_components.dart';
import '../monitoring/monitoring_owner.dart';
import '../monitoring/monitoring_view.dart';
import 'profile_controller.dart';
import 'profile_form.dart';

class ProfileViewPanel extends StatefulWidget {
  const ProfileViewPanel({
    super.key,
    required this.controller,
    required this.pickKey,
    this.monitoring,
    this.journals,
    this.consoles,
    this.software,
    this.onApplicationSettings,
    this.applicationStatus,
    this.runtimeNotice,
  });
  final ProfileController controller;
  final MonitoringOwner? monitoring;
  final JournalsOwner? journals;
  final ConsoleOwner? consoles;
  final SoftwareOwner? software;
  final Future<void> Function()? onApplicationSettings;
  final Widget? applicationStatus, runtimeNotice;
  final Future<Uint8List?> Function() pickKey;
  @override
  State<ProfileViewPanel> createState() => _ProfileViewPanelState();
}

class _ProfileViewPanelState extends State<ProfileViewPanel> {
  final _search = TextEditingController();
  String _query = '';
  bool _workspaceOpen = false, _onboarding = false, _promptOpen = false;
  String? _workspaceProfileId;
  _VerificationLease? _verification;
  final _ownedRoutes = <Route<dynamic>, NavigatorState>{};
  int _section = 0;
  static const _sections = [
    'ПО',
    'Журналы',
    'Задания',
    'Мониторинг',
    'Консоль',
    'Настройки',
  ];
  final _shownPrompts = <String>{};
  int _navigationGeneration = 0;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    unawaited(widget.controller.refresh());
  }

  Future<void> _edit([ProfileView? profile]) async {
    final controller = widget.controller;
    final navigation = _navigationGeneration;
    final saved = await _showOwnedDialog<ProfileSaveOutcome>(
      barrierDismissible: false,
      builder: (_) => ProfileForm(
        controller: controller,
        pickKey: widget.pickKey,
        profile: profile,
      ),
    );
    if (!mounted ||
        saved == null ||
        controller != widget.controller ||
        navigation != _navigationGeneration)
      return;
    await controller.refresh();
    if (!mounted ||
        controller != widget.controller ||
        navigation != _navigationGeneration)
      return;
    _search.clear();
    _query = '';
    await _selectServer(saved.profileId, verify: saved.requiresConnection);
  }

  @override
  void didUpdateWidget(covariant ProfileViewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _navigationGeneration++;
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _onboarding = false;
      _removeOwnedDialogs();
      _verification?.close(current: oldWidget.controller.details?.connection);
      _verification = null;
      _changed();
    }
  }

  Future<T?> _showOwnedDialog<T>({
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<T>(
      context: context,
      builder: builder,
      barrierDismissible: barrierDismissible,
    );
    _ownedRoutes[route] = navigator;
    try {
      return await navigator.push<T>(route);
    } finally {
      _ownedRoutes.remove(route);
    }
  }

  void _removeOwnedDialogs() {
    final routes = Map<Route<dynamic>, NavigatorState>.of(_ownedRoutes);
    _ownedRoutes.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final entry in routes.entries) {
        if (entry.value.mounted && entry.key.isActive)
          entry.value.removeRoute(entry.key);
      }
    });
  }

  void _retireWorkspace() {
    _navigationGeneration++;
    _onboarding = false;
    _verification?.close(
      current:
          widget.controller.details?.profile.profileId == _workspaceProfileId
          ? widget.controller.details?.connection
          : null,
    );
    _verification = null;
    _removeOwnedDialogs();
    _shownPrompts.clear();
  }

  void _changed() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = widget.controller;
      if (_workspaceOpen &&
          (c.selected != _workspaceProfileId ||
              !c.items.any((p) => p.profileId == _workspaceProfileId))) {
        _retireWorkspace();
        _workspaceProfileId = c.selected;
        _workspaceOpen = c.selected != null;
      }
      _offerPrompt();
    });
  }

  void _offerPrompt() {
    final c = widget.controller, d = c.details;
    if (!_onboarding ||
        _promptOpen ||
        c.pending ||
        d == null ||
        d.profile.profileId != _workspaceProfileId)
      return;
    final connection = d.connection;
    final challenge = d.trust.challenge ?? connection.challenge;
    if (challenge == null &&
        (connection.state == ConnectionState.connected ||
            connection.state == ConnectionState.failed ||
            connection.state == ConnectionState.cancelled)) {
      _onboarding = false;
      return;
    }
    final phrase = connection.pendingInput;
    final token = challenge != null
        ? '${d.profile.profileId}:${challenge.attemptId}:${challenge.nonce}'
        : phrase != null
        ? '${d.profile.profileId}:${phrase.attemptId}:${phrase.nonce}'
        : null;
    if (token == null || !_shownPrompts.add(token)) return;
    if (_shownPrompts.length > 64) _shownPrompts.remove(_shownPrompts.first);
    if (challenge != null) {
      unawaited(_trust(d.profile, challenge));
    } else if (phrase != null) {
      unawaited(_phrase(d.profile.profileId, phrase));
    }
  }

  Future<void> _verifySaved(String id) async {
    final c = widget.controller;
    if (!mounted || !_workspaceOpen || id != _workspaceProfileId) return;
    _verification?.close(current: c.details?.connection);
    final lease = _VerificationLease(c, id);
    _verification = lease;
    await c.select(id);
    final d = c.details;
    if (lease.closed ||
        !mounted ||
        !_workspaceOpen ||
        d?.profile.profileId != id)
      return;
    if (d!.connection.state != ConnectionState.connected) {
      await c.connect(d.profile, onStarted: lease.admit);
    } else if (d.trust.challenge == null && d.connection.challenge == null) {
      _onboarding = false;
    }
  }

  Future<void> _selectServer(String id, {bool verify = false}) async {
    _retireWorkspace();
    _workspaceOpen = true;
    _workspaceProfileId = id;
    _onboarding = verify;
    final navigation = _navigationGeneration, controller = widget.controller;
    await controller.select(id);
    if (!mounted ||
        navigation != _navigationGeneration ||
        controller != widget.controller ||
        controller.details?.profile.profileId != id)
      return;
    if (verify) await _verifySaved(id);
    _changed();
  }

  Future<void> _clearSelection() async {
    _retireWorkspace();
    _workspaceOpen = false;
    _workspaceProfileId = null;
    await widget.controller.select(null);
  }

  Future<void> _applicationSettings() async {
    _retireWorkspace();
    await widget.onApplicationSettings?.call();
  }

  Future<bool> _confirm(
    String title,
    Widget child,
    String action, {
    bool prompt = false,
  }) async =>
      await _showOwnedDialog<bool>(
        barrierDismissible: !prompt,
        builder: (context) {
          return DeckDialogLayout(
            title: title,
            child: child,
            actions: [
              DeckButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Отмена'),
              ),
              DeckButton(
                kind: DeckButtonKind.danger,
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          );
        },
      ) ??
      false;
  Future<void> _delete(ProfileView p) async {
    final controller = widget.controller, navigation = _navigationGeneration;
    final confirmed = await _confirm(
      'Удалить сервер?',
      Text(
        '${p.displayName}\n${p.username}@${p.host}:${p.port}\nПодключение будет закрыто. Профиль и его учётные данные будут удалены.',
      ),
      'Удалить',
    );
    if (!confirmed ||
        !mounted ||
        controller != widget.controller ||
        navigation != _navigationGeneration ||
        controller.selected != p.profileId)
      return;
    await controller.delete(p, confirmed: true);
  }

  Future<void> _trust(ProfileView p, TrustChallenge c) async {
    if (_promptOpen) return;
    _promptOpen = true;
    final navigation = _navigationGeneration, controller = widget.controller;
    try {
      final verb = switch (c.kind) {
        TrustKind.first => 'Принять ключ',
        TrustKind.replace => 'Заменить ключ',
        TrustKind.retain => 'Сохранить прежний ключ',
      };
      final confirmed = await _confirm(
        verb,
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${c.host}:${c.port} · ${c.keyType}'),
            if (c.oldFingerprint != null)
              DeckKeyValue(
                label: 'Прежний отпечаток',
                value: c.oldFingerprint!,
                selectable: true,
              ),
            DeckKeyValue(
              label: 'Подтверждаемый отпечаток',
              value: c.fingerprint,
              selectable: true,
            ),
            const Text(
              'Сверьте отпечаток с доверенным источником. Решение действует для всех профилей этого адреса.',
            ),
          ],
        ),
        verb,
        prompt: true,
      );
      if (!mounted ||
          navigation != _navigationGeneration ||
          controller != widget.controller ||
          !_workspaceOpen ||
          _workspaceProfileId != p.profileId ||
          widget.controller.details?.profile.profileId != p.profileId)
        return;
      if (confirmed)
        await widget.controller.decide(
          p.profileId,
          c,
          confirmed: true,
          mutationId: widget.controller.newId(),
        );
      else if (c.kind == TrustKind.first)
        await widget.controller.cancel(p.profileId, c.attemptId);
    } finally {
      _promptOpen = false;
      if (mounted) _changed();
    }
  }

  Future<void> _phrase(String id, PendingInput pending) async {
    if (_promptOpen) return;
    _promptOpen = true;
    final navigation = _navigationGeneration, controller = widget.controller;
    String? phrase;
    try {
      phrase = await _showOwnedDialog<String>(
        barrierDismissible: false,
        builder: (context) {
          return const _PassphraseDialog();
        },
      );
      if (!mounted ||
          navigation != _navigationGeneration ||
          controller != widget.controller ||
          !_workspaceOpen ||
          _workspaceProfileId != id ||
          widget.controller.details?.profile.profileId != id)
        return;
      if (phrase != null)
        await widget.controller.providePassphrase(id, pending, phrase);
      else
        await widget.controller.cancel(id, pending.attemptId);
    } finally {
      phrase = null;
      _promptOpen = false;
      if (mounted) _changed();
    }
  }

  String _state(ConnectionState state) => switch (state) {
    ConnectionState.disconnected => 'Не подключён',
    ConnectionState.connecting => 'Подключаемся',
    ConnectionState.needTrust => 'Ожидает подтверждения ключа',
    ConnectionState.needPassphrase => 'Ожидает passphrase',
    ConnectionState.authenticating => 'Проверяем учётные данные',
    ConnectionState.cancelled => 'Подключение отменено',
    ConnectionState.connected => 'Подключён',
    ConnectionState.failed => 'Ошибка подключения',
  };
  Widget _details(ProfileDetails d) {
    final p = d.profile,
        c = d.connection,
        t = d.trust,
        challenge = t.challenge ?? c.challenge;
    return DeckFormSection(
      title: p.displayName,
      description: '${p.username}@${p.host}:${p.port}',
      children: [
        if (widget.monitoring != null)
          ListenableBuilder(
            listenable: widget.monitoring!,
            builder: (_, _) => MonitoringReadings(
              detailsOnly: true,
              snapshot: widget.monitoring!.snapshot(p.profileId),
              now: widget.monitoring!.now,
            ),
          ),
        DeckStatus(
          label: _state(c.state),
          tone: c.state == ConnectionState.connected
              ? DeckTone.available
              : DeckTone.neutral,
        ),
        if (c.failureCode != null)
          DeckNotice(
            title: 'Состояние подключения',
            message: OperationPresentation.of(OperationFailure(c.failureCode!))
                .message,
            nextStep: OperationPresentation.of(OperationFailure(c.failureCode!))
                .nextStep,
            tone: DeckTone.error,
          ),
        DeckKeyValue(
          label: 'Способ входа',
          value: p.authKind == AuthKind.password
              ? 'Пароль'
              : 'Приватный ключ SSH',
        ),
        if (t.acceptedFingerprint != null)
          DeckKeyValue(label: 'Доверенный ключ', value: t.acceptedFingerprint!),
        if (t.changed)
          DeckNotice(
            title: 'Ключ сервера изменился',
            message:
                'Доверенный: ${t.acceptedFingerprint ?? "—"}\nНаблюдаемый: ${t.observedFingerprint ?? "—"}\nПеред решением проверьте ключ через доверенный источник.',
            tone: DeckTone.warning,
          ),
        if (challenge != null)
          DeckButton(
            onPressed: widget.controller.pending
                ? null
                : () => _trust(p, challenge),
            child: Text(switch (challenge.kind) {
              TrustKind.first => 'Проверить и принять ключ',
              TrustKind.replace => 'Проверить замену ключа',
              TrustKind.retain => 'Подтвердить прежний ключ',
            }),
          ),
        if (t.changed && challenge == null)
          const Text(
            'Для нового подтверждения повторите подключение. После решения о замене подключитесь снова.',
          ),
        DeckActions(
          children: [
            if (c.state == ConnectionState.disconnected ||
                c.state == ConnectionState.failed ||
                c.state == ConnectionState.cancelled)
              DeckButton(
                onPressed: widget.controller.pending
                    ? null
                    : () => widget.controller.connect(p),
                kind: DeckButtonKind.primary,
                child: const Text('Подключиться'),
              ),
            if (c.attemptId != null && c.state != ConnectionState.connected)
              DeckButton(
                onPressed: widget.controller.pending
                    ? null
                    : () => widget.controller.cancel(p.profileId, c.attemptId!),
                child: const Text('Отменить подключение'),
              ),
            if (c.sessionId != null)
              DeckButton(
                onPressed: widget.controller.pending
                    ? null
                    : () => widget.controller.disconnect(
                        p.profileId,
                        c.sessionId!,
                      ),
                child: const Text('Отключиться'),
              ),
            if (c.pendingInput != null)
              DeckButton(
                onPressed: widget.controller.pending
                    ? null
                    : () => _phrase(p.profileId, c.pendingInput!),
                child: const Text('Ввести passphrase'),
              ),
            DeckButton(
              onPressed: widget.controller.pending ? null : () => _edit(p),
              child: const Text('Изменить'),
            ),
            DeckButton(
              onPressed: widget.controller.pending ? null : () => _delete(p),
              kind: DeckButtonKind.danger,
              child: const Text('Удалить'),
            ),
          ],
        ),
      ],
    );
  }

  ({String label, IconData icon, DeckTone tone, bool text}) _rowStatus(
    ProfileView p,
  ) {
    final c = widget.controller, trust = c.trusts[p.profileId];
    if (trust?.changed == true)
      return (
        label: 'Ключ сервера изменился',
        icon: Icons.key_outlined,
        tone: DeckTone.warning,
        text: true,
      );
    final observed = widget.monitoring?.snapshot(p.profileId);
    final connection = observed?.connection ?? c.connections[p.profileId];
    if (connection == null)
      return (
        label: 'Состояние подключения неизвестно',
        icon: Icons.help_outline,
        tone: DeckTone.unknown,
        text: false,
      );
    if (connection.state == ConnectionState.failed)
      return (
        label: connection.failureCode == FailureCode.networkError
            ? 'Связь потеряна'
            : 'Ошибка подключения',
        icon: Icons.link_off,
        tone: DeckTone.error,
        text: true,
      );
    if (connection.state == ConnectionState.needTrust ||
        (trust != null &&
            trust.acceptedFingerprint == null &&
            (connection.state == ConnectionState.disconnected ||
                connection.state == ConnectionState.cancelled)))
      return (
        label: 'Требуется проверка ключа',
        icon: Icons.key_outlined,
        tone: DeckTone.warning,
        text: false,
      );
    if (connection.state == ConnectionState.needPassphrase)
      return (
        label: 'Ожидает passphrase',
        icon: Icons.password_outlined,
        tone: DeckTone.warning,
        text: false,
      );
    if (connection.state == ConnectionState.connected) {
      if (observed?.hasCritical(widget.monitoring!.now) == true)
        return (
          label: 'Порог нагрузки достигнут',
          icon: Icons.error_outline,
          tone: DeckTone.error,
          text: true,
        );
      if (observed?.isPartial(widget.monitoring!.now) == true)
        return (
          label: 'Частичные данные',
          icon: Icons.warning_amber_rounded,
          tone: DeckTone.warning,
          text: false,
        );
      return (
        label: 'SSH: подключён',
        icon: Icons.power_outlined,
        tone: DeckTone.available,
        text: false,
      );
    }
    return (
      label: _state(connection.state),
      icon:
          connection.state == ConnectionState.connecting ||
              connection.state == ConnectionState.authenticating
          ? Icons.sync
          : Icons.link_off,
      tone: DeckTone.neutral,
      text: false,
    );
  }

  Widget _server(ProfileView p, ProfileController c) {
    final status = _rowStatus(p);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DeckListItem(
        compact: true,
        error: status.tone == DeckTone.error,
        title: p.displayName,
        description: '${p.username}@${p.host}:${p.port}',
        statusLabel: status.text ? status.label : null,
        leading: const Icon(Icons.dns_outlined, size: 18),
        trailing: DeckStatus(
          label: status.label,
          icon: status.icon,
          iconOnly: true,
          tone: status.tone,
        ),
        selected: c.selected == p.profileId,
        onTap: () => unawaited(_selectServer(p.profileId)),
      ),
    );
  }

  Widget _sidebar(ProfileController c) {
    final visible = c.items.where(
      (p) => '${p.displayName} ${p.host} ${p.username}'.toLowerCase().contains(
        _query.toLowerCase(),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Text('Серверы')),
            IconButton(
              tooltip: 'Добавить сервер',
              icon: const Icon(Icons.add),
              onPressed: c.pending ? null : () => _edit(),
            ),
          ],
        ),
        DeckSearch(
          controller: _search,
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (c.loading)
                  const DeckStatus(label: 'Загружаем серверы', pending: true),
                if (!c.loading && c.items.isEmpty)
                  const Text('Серверов пока нет'),
                if (!c.loading && c.items.isNotEmpty && visible.isEmpty)
                  const Text('Серверы не найдены'),
                for (final p in visible) _server(p, c),
              ],
            ),
          ),
        ),
        DeckButton(
          onPressed: widget.onApplicationSettings == null
              ? null
              : _applicationSettings,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(child: Icon(Icons.settings_outlined)),
              SizedBox(width: 8),
              Flexible(child: Text('Настройки приложения')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _workspace(ProfileController c) {
    final d = c.details;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.runtimeNotice != null) widget.runtimeNotice!,
          if (widget.monitoring != null)
            MonitoringControls(owner: widget.monitoring!),
          if (c.error != null)
            DeckNotice(
              title: 'Операция не выполнена',
              message: OperationPresentation.of(c.error!).message,
              nextStep: OperationPresentation.of(c.error!).nextStep,
              tone: DeckTone.error,
              actions: [
                DeckButton(onPressed: c.refresh, child: const Text('Обновить')),
              ],
            ),
          if (c.selected == null)
            const DeckNotice(
              title: 'Выберите сервер',
              message: 'Выберите сервер слева или добавьте новый.',
            ),
          if (c.selected != null && d == null)
            const DeckStatus(label: 'Загружаем сервер', pending: true),
          if (d != null && d.profile.profileId == c.selected) ...[
            DeckSectionHeader(
              title: d.profile.displayName,
              description:
                  '${d.profile.username}@${d.profile.host}:${d.profile.port}',
              trailing: IconButton(
                tooltip: 'Снять выбор сервера',
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.monitoring != null)
              MonitoringReadings(
                compact: true,
                snapshot: widget.monitoring!.snapshot(d.profile.profileId),
                now: widget.monitoring!.now,
              )
            else
              DeckStatus(
                label: _state(d.connection.state),
                icon: d.connection.state == ConnectionState.connected
                    ? Icons.power_outlined
                    : Icons.link_off,
                tone: d.connection.state == ConnectionState.connected
                    ? DeckTone.available
                    : DeckTone.neutral,
                iconOnly: true,
              ),
            const SizedBox(height: 16),
            DeckTabs(
              labels: _sections,
              icons: const [
                Icons.apps_outlined,
                Icons.description_outlined,
                Icons.task_alt,
                Icons.monitor_outlined,
                Icons.terminal,
                Icons.tune,
              ],
              selected: _section,
              onSelected: (v) => setState(() => _section = v),
            ),
            const SizedBox(height: 16),
            if (_section == 0 && widget.software != null)
              SoftwareView(
                key: ValueKey('software-${d.profile.profileId}'),
                owner: widget.software!,
                actor: widget.controller.actor,
                profile: d.profile,
                newId: widget.controller.newId,
                onConsole: widget.consoles == null
                    ? null
                    : () => setState(() => _section = 4),
              )
            else if (_section == 5)
              _details(d)
            else if (_section == 1 && widget.journals != null)
              JournalView(
                key: ValueKey('journals-${d.profile.profileId}'),
                owner: widget.journals!,
                profileId: d.profile.profileId,
                connectionRevision: d.profile.connectionRevision,
              )
            else if (_section == 4 && widget.consoles != null)
              ConsoleView(
                key: ValueKey('console-${d.profile.profileId}'),
                owner: widget.consoles!,
                profileId: d.profile.profileId,
                connectionRevision: d.profile.connectionRevision,
                serverLabel: d.profile.displayName,
                username: d.profile.username,
              )
            else if (_section == 3 && widget.monitoring != null)
              MonitoringHistoryPanel(
                key: ValueKey('history-${d.profile.profileId}'),
                owner: widget.monitoring!,
                profileId: d.profile.profileId,
                connectionRevision: d.profile.connectionRevision,
              )
            else
              DeckNotice(
                title: _sections[_section],
                message:
                    'Раздел пока недоступен для сервера «${d.profile.displayName}».',
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listenables = [
      widget.controller,
      if (widget.monitoring != null) widget.monitoring!,
    ];
    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (context, _) {
        final c = widget.controller;
        return FoundationShell(
          state: ReadinessState.ready,
          sidebar: _sidebar(c),
          child: _workspace(c),
          status: widget.applicationStatus,
        );
      },
    );
  }

  @override
  void dispose() {
    _retireWorkspace();
    _workspaceOpen = false;
    widget.controller.removeListener(_changed);
    _search.dispose();
    super.dispose();
  }
}

/// A closed route retains this tiny lease until its own connect reply arrives.
/// No route/widget references survive here, and cancellation targets only the
/// admitted attempt ID through the canonical backend fences.
final class _VerificationLease {
  _VerificationLease(this.controller, this.profileId);
  final ProfileController controller;
  final String profileId;
  ConnectionView? _admitted;
  bool closed = false, _cancelled = false;
  void admit(ConnectionView connection) {
    _admitted = connection;
    if (closed) _cancel();
  }

  void close({ConnectionView? current}) {
    closed = true;
    if (current?.sessionId != null ||
        current?.state == ConnectionState.connected) {
      _cancelled = true;
      return;
    }
    _cancel();
  }

  void _cancel() {
    final connection = _admitted;
    if (_cancelled ||
        connection?.attemptId == null ||
        connection?.sessionId != null ||
        connection?.state == ConnectionState.connected)
      return;
    _cancelled = true;
    unawaited(controller.cancelOwnedAttempt(profileId, connection!.attemptId!));
  }
}

/// The route owns its secret controller until its actual unmount, including exit animation.
class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog();
  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final _value = TextEditingController();
  bool _submitted = false;
  void _close({required bool submit}) {
    if (_submitted || ModalRoute.of(context)?.isCurrent != true) return;
    _submitted = true;
    final phrase = submit ? _value.text : null;
    _value.clear();
    Navigator.pop(context, phrase);
  }

  @override
  Widget build(BuildContext context) => DeckDialogLayout(
    title: 'Passphrase приватного ключа',
    child: DeckTextField(label: 'Passphrase', controller: _value, secret: true),
    actions: [
      DeckButton(
        onPressed: () => _close(submit: false),
        child: const Text('Отмена'),
      ),
      DeckButton(
        onPressed: () => _close(submit: true),
        child: const Text('Продолжить'),
      ),
    ],
  );
  @override
  void dispose() {
    _value.clear();
    _value.dispose();
    super.dispose();
  }
}
