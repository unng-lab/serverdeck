import 'dart:async';

import 'package:flutter/material.dart';

import '../shell/foundation_shell.dart';
import '../ui/deck_components.dart';
import 'runtime_coordinator.dart';
import 'feature_runtime.dart';
import '../profiles/profile_controller.dart';
import '../profiles/profile_view.dart';
import '../mcp/settings_controller.dart';
import '../mcp/settings_view.dart';
import '../monitoring/monitoring_owner.dart';
import 'native_platform.dart';

/// C17 shell with C01/C02/C10/C11/C12 content; feature slots are supplied by 003.
class RuntimeView extends StatefulWidget {
  const RuntimeView({
    super.key,
    required this.runtime,
    this.features,
    this.monitoring,
  });
  final RuntimeCoordinator runtime;
  final FeatureRuntime? features;

  /// Optional owner injection for isolated activation tests/composition.
  final MonitoringOwner? monitoring;
  @override
  State<RuntimeView> createState() => _RuntimeViewState();
}

class _RuntimeViewState extends State<RuntimeView> {
  RuntimeCoordinator get runtime => widget.runtime;
  ProfileController? _profiles;
  McpSettingsController? _settings;
  FoundationSection _section = FoundationSection.servers;
  MonitoringOwner? get _monitoring =>
      widget.monitoring ?? widget.features?.monitoring;
  @override
  void initState() {
    super.initState();
    runtime.addListener(_runtimeChanged);
    _syncMonitoring();
  }

  void _syncMonitoring() => _monitoring?.setActive(
    runtime.acceptsOperations &&
        runtime.window != WindowState.trayHidden &&
        _section == FoundationSection.servers,
  );
  void _runtimeChanged() {
    _syncMonitoring();
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
    if (oldWidget.features != widget.features || !runtime.acceptsOperations)
      _release();
    _syncMonitoring();
  }

  void _release() {
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
    return FoundationShell(
      state: ReadinessState.ready,
      onSectionChanged: (section) {
        _section = section;
        _syncMonitoring();
      },
      servers: runtime.acceptsOperations && _profiles != null
          ? ProfileViewPanel(
              controller: _profiles!,
              pickKey: widget.features!.platform.pickPrivateKey,
              monitoring: _monitoring,
            )
          : body,
      software: body,
      settings: runtime.acceptsOperations && _settings != null
          ? McpSettingsView(controller: _settings!)
          : body,
      fallbackContent: body,
      status: DeckStatus(
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
      recoveryAction: !runtime.trayAvailable
          ? DeckButton(
              child: const Text('Повторить создание значка'),
              onPressed: runtime.retryTray,
            )
          : null,
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
