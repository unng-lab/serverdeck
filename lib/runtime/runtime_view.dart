import 'dart:async';

import 'package:flutter/material.dart';

import '../shell/foundation_shell.dart';
import '../ui/deck_components.dart';
import 'runtime_coordinator.dart';
import 'feature_runtime.dart';
import '../profiles/profile_controller.dart';
import '../profiles/profile_view.dart';
import '../mcp/settings_controller.dart';
import 'application_settings_view.dart';
import '../updates/update_owner.dart';
import '../updates/update_view.dart';
import '../monitoring/monitoring_owner.dart';
import 'native_platform.dart';
import 'owned_settings_route.dart';

/// C17 shell with C01/C02/C10/C11/C12 content; feature slots are supplied by 003.
class RuntimeView extends StatefulWidget {
  const RuntimeView({
    super.key,
    required this.runtime,
    this.features,
    this.monitoring,
    this.updates,
  });
  final RuntimeCoordinator runtime;
  final FeatureRuntime? features;

  /// Optional owner injection for isolated activation tests/composition.
  final MonitoringOwner? monitoring;
  final UpdateOwner? updates;
  @override
  State<RuntimeView> createState() => _RuntimeViewState();
}

class _RuntimeViewState extends State<RuntimeView> {
  RuntimeCoordinator get runtime => widget.runtime;
  ProfileController? _profiles;
  McpSettingsController? _settings;
  OwnedSettingsRoute _applicationSettings = OwnedSettingsRoute();
  OwnedSettingsRoute _updateRoute = OwnedSettingsRoute();
  MonitoringOwner? get _monitoring =>
      widget.monitoring ?? widget.features?.monitoring;
  UpdateOwner? get _updates => widget.updates ?? widget.features?.updates;
  @override
  void initState() {
    super.initState();
    runtime.addListener(_runtimeChanged);
    _syncMonitoring();
    _startUpdates();
  }

  void _startUpdates() {
    if (runtime.acceptsOperations) unawaited(_updates?.start());
  }

  void _syncMonitoring() {
    final active =
        runtime.acceptsOperations &&
        runtime.window != WindowState.trayHidden &&
        !_applicationSettings.isOpen &&
        !_updateRoute.isOpen;
    _monitoring?.setActive(active);
    widget.features?.consoles.setKeyboardActive(active);
  }

  void _runtimeChanged() {
    if (!runtime.acceptsOperations) _release();
    _syncMonitoring();
    _startUpdates();
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant RuntimeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runtime != widget.runtime) {
      oldWidget.runtime.removeListener(_runtimeChanged);
      runtime.addListener(_runtimeChanged);
    }
    final oldMonitoring =
        oldWidget.monitoring ?? oldWidget.features?.monitoring;
    if (oldMonitoring != _monitoring) oldMonitoring?.setActive(false);
    if (oldWidget.runtime != widget.runtime ||
        oldWidget.features != widget.features ||
        oldWidget.updates != widget.updates ||
        !runtime.acceptsOperations)
      _release();
    _syncMonitoring();
    _startUpdates();
  }

  void _release() {
    _updateRoute.retire();
    _updateRoute = OwnedSettingsRoute();
    _applicationSettings.retire();
    _applicationSettings = OwnedSettingsRoute();
    _profiles?.dispose();
    _settings?.dispose();
    _profiles = null;
    _settings = null;
  }

  void _bind() {
    final f = widget.features;
    if (f == null || !runtime.acceptsOperations) return;
    _profiles ??= ProfileController(
      operations: f.operations,
      actor: f.actors.ui,
      newId: FeatureRuntime.newId,
      changes: f.connections.changes,
      onAction: () => unawaited(f.monitoring.reconcile()),
    );
    _settings ??= McpSettingsController(
      owner: f.grants,
      actor: f.actors.ui,
      retryTransport: f.retryMcp,
      transportError: () => f.mcpError,
    );
  }

  Future<void> _openUpdates() async {
    if (_updateRoute.isOpen ||
        _applicationSettings.isOpen ||
        !runtime.acceptsOperations ||
        _updates == null)
      return;
    final session = _updateRoute;
    await session.show(
      context,
      title: 'Обновления',
      child: UpdateView(
        owner: _updates!,
        onRestart: runtime.requestUpdateRestart,
      ),
      onChanged: () {
        if (mounted && identical(session, _updateRoute)) _syncMonitoring();
      },
    );
  }

  Widget _updateEntry() {
    final owner = _updates;
    if (owner == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: owner,
      builder: (context, _) {
        final snapshot = owner.snapshot;
        final label =
            owner.error != null || snapshot.state == UpdateState.failed
            ? 'Ошибка обновления'
            : switch (snapshot.state) {
                UpdateState.checking => 'Проверка обновлений…',
                UpdateState.downloading ||
                UpdateState.verifying => 'Подготовка обновления…',
                _ when owner.canRestart => 'Обновление готово',
                UpdateState.available => 'Доступно обновление',
                _ => 'Обновления',
              };
        return DeckButton(
          onPressed: runtime.acceptsOperations ? _openUpdates : null,
          child: Text(label),
        );
      },
    );
  }

  Future<void> _openApplicationSettings() async {
    if (_updateRoute.isOpen ||
        _applicationSettings.isOpen ||
        !runtime.acceptsOperations ||
        _updates == null)
      return;
    final session = _applicationSettings;
    await session.show(
      context,
      child: ApplicationSettingsView(
        updates: _updates!,
        mcp: _settings,
        terminalSettings: widget.features?.consoleSettings,
        newTerminalProfileId: widget.features == null
            ? null
            : FeatureRuntime.newId,
        onUpdateRestart: runtime.requestUpdateRestart,
      ),
      onChanged: () {
        if (mounted && identical(session, _applicationSettings))
          _syncMonitoring();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _bind();
    final Widget content;
    if (runtime.state == RuntimeState.starting) {
      content = const DeckNotice(
        title: 'Открываем данные',
        message: 'Подождите',
        tone: DeckTone.running,
      );
    } else if (runtime.state == RuntimeState.storageBlocked) {
      content = DeckNotice(
        title: 'Данные недоступны',
        message: runtime.error ?? 'Не удалось открыть данные',
        tone: DeckTone.error,
        actions: [
          DeckButton(
            child: const Text('Повторить'),
            onPressed: runtime.retryOpen,
          ),
        ],
      );
    } else if (runtime.state == RuntimeState.shuttingDown ||
        runtime.state == RuntimeState.shutdownBlocked) {
      content = DeckNotice(
        title: runtime.state == RuntimeState.shutdownBlocked
            ? 'Завершение приостановлено'
            : 'Завершаем работу',
        message: runtime.error ?? 'Сохраняем данные и закрываем подключения',
        tone: runtime.error == null ? DeckTone.running : DeckTone.error,
        actions: [
          if (runtime.state == RuntimeState.shutdownBlocked &&
              runtime.updateRestartRequested)
            DeckButton(
              onPressed: runtime.requestExit,
              child: const Text('Повторить завершение обновления'),
            ),
        ],
      );
    } else {
      content = const DeckNotice(
        title: 'Серверов пока нет',
        message: 'Данные открыты. Добавленных серверов пока нет.',
        tone: DeckTone.neutral,
      );
    }
    final body = !runtime.trayAvailable
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DeckNotice(
                title: 'Значок трея недоступен',
                message: 'Окно останется доступным. Повторите создание значка.',
                tone: DeckTone.error,
              ),
              content,
            ],
          )
        : content;
    final status = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ValueListenableBuilder<String?>(
          valueListenable: runtime.platform.release,
          builder: (context, release, _) => DeckKeyValue(
            label: 'Версия ServerDeck',
            value: release == null || release.isEmpty
                ? 'Не определена'
                : release,
          ),
        ),
        if (runtime.state == RuntimeState.running)
          _updateEntry()
        else
          DeckStatus(
            label: switch (runtime.state) {
              RuntimeState.running => 'Приложение готово',
              RuntimeState.starting => 'Запуск',
              RuntimeState.storageBlocked => 'Данные недоступны',
              _ => 'Завершение работы',
            },
            tone: runtime.acceptsOperations
                ? DeckTone.available
                : DeckTone.unavailable,
          ),
      ],
    );
    final recovery = !runtime.trayAvailable
        ? DeckButton(
            child: const Text('Повторить создание значка'),
            onPressed: runtime.retryTray,
          )
        : null;
    if (runtime.acceptsOperations && _profiles != null) {
      return ProfileViewPanel(
        controller: _profiles!,
        pickKey: widget.features!.platform.pickPrivateKey,
        monitoring: _monitoring,
        journals: widget.features?.journals,
        consoles: widget.features?.consoles,
        applicationStatus: status,
        onApplicationSettings: _openApplicationSettings,
        runtimeNotice: !runtime.trayAvailable
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const DeckNotice(
                    title: 'Значок трея недоступен',
                    message: 'Окно останется доступным.',
                    tone: DeckTone.error,
                  ),
                  recovery!,
                ],
              )
            : null,
      );
    }
    return FoundationShell(
      state: ReadinessState.ready,
      sidebar: const Text('Серверы'),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            body,
            if (runtime.acceptsOperations && _updates != null)
              DeckButton(
                onPressed: _openApplicationSettings,
                child: const Text('Настройки приложения'),
              ),
          ],
        ),
      ),
      status: status,
      recoveryAction: recovery,
    );
  }

  @override
  void dispose() {
    runtime.removeListener(_runtimeChanged);
    _monitoring?.setActive(false);
    _release();
    super.dispose();
  }
}
