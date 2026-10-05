import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/app_updates.dart';

class UpdateControls extends StatefulWidget {
  const UpdateControls({
    super.key,
    required this.updater,
    this.readPreference,
    this.writePreference,
  });
  final UpdateController updater;
  final Future<bool> Function()? readPreference;
  final Future<void> Function(bool)? writePreference;
  @override
  State<UpdateControls> createState() => _UpdateControlsState();
}

class _UpdateControlsState extends State<UpdateControls>
    with WidgetsBindingObserver {
  Timer? _timer;
  final _refresh = ValueNotifier<int>(0);
  bool _auto = false;
  String _preferenceError = '';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final enabled = await widget.readPreference?.call() ?? true;
      if (!mounted) return;
      setState(() => _auto = enabled);
      _refresh.value++;
      _schedule();
      if (_auto) unawaited(widget.updater.check());
    } catch (_) {
      if (mounted) {
        setState(
          () => _preferenceError =
              'Настройки недоступны. Автопроверка приостановлена.',
        );
        _refresh.value++;
      }
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (_auto) {
      _timer = Timer.periodic(
        const Duration(hours: 6),
        (_) => unawaited(widget.updater.check()),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _auto && widget.updater.isStore) {
      unawaited(widget.updater.check());
    }
  }

  Future<void> _toggle(bool enabled) async {
    try {
      await widget.writePreference?.call(enabled);
      if (!mounted) return;
      setState(() {
        _auto = enabled;
        _preferenceError = '';
      });
      _refresh.value++;
      _schedule();
      if (enabled) unawaited(widget.updater.check());
    } catch (_) {
      if (mounted) {
        setState(
          () => _preferenceError = 'Не удалось сохранить настройку. Повторите.',
        );
        _refresh.value++;
      }
    }
  }

  String get _status => switch (widget.updater.state) {
    UpdateState.idle => 'Проверка ещё не выполнялась.',
    UpdateState.checking => 'Проверка обновлений…',
    UpdateState.current => 'Установлена актуальная версия.',
    UpdateState.available =>
      'Доступно обновление ${widget.updater.availableVersion}.',
    UpdateState.notPublished => 'Стабильные релизы пока не опубликованы.',
    UpdateState.unsupported =>
      'Обновление для этого устройства пока недоступно.',
    UpdateState.downloading => 'Загрузка обновления…',
    UpdateState.downloaded =>
      widget.updater.isStore
          ? 'Обновление готово к установке через RuStore.'
          : 'Файл проверен и готов к установке.',
    UpdateState.error => 'Обновление не выполнено.',
  };
  void _show() {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => AnimatedBuilder(
          animation: Listenable.merge([widget.updater, _refresh]),
          builder: (context, _) => AlertDialog(
            title: const Text('Обновления ServerDeck'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Установлена версия ${widget.updater.installedVersion}',
                    ),
                    const SizedBox(height: 12),
                    Text(_status, key: const ValueKey('update-status')),
                    if (widget.updater.busy) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: widget.updater.state == UpdateState.downloading
                            ? widget.updater.progress
                            : null,
                      ),
                    ],
                    if (widget.updater.notes.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 160),
                        child: SingleChildScrollView(
                          child: SelectableText(widget.updater.notes),
                        ),
                      ),
                    ],
                    if (widget.updater.message.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(widget.updater.message),
                    ],
                    if (widget.updater.state == UpdateState.downloaded &&
                        !widget.updater.isStore) ...[
                      const SizedBox(height: 12),
                      Text(
                        Platform.isMacOS
                            ? 'Закройте ServerDeck, скопируйте приложение из DMG в Applications с заменой и запустите заново.'
                            : Platform.isLinux
                            ? 'Закройте ServerDeck и установите DEB через менеджер пакетов. При отсутствии обработчика: sudo apt install /путь/к/файлу.deb'
                            : 'Установщик предложит закрыть ServerDeck и локальный сервис. После установки запустите приложение заново.',
                      ),
                      if (widget.updater is AppUpdater)
                        SelectableText(
                          (widget.updater as AppUpdater).downloadedFile?.path ??
                              '',
                        ),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      key: const ValueKey('update-auto'),
                      title: const Text('Проверять автоматически'),
                      subtitle: const Text('При запуске и каждые 6 часов'),
                      value: _auto,
                      onChanged: (value) => unawaited(_toggle(value)),
                    ),
                    if (_preferenceError.isNotEmpty) Text(_preferenceError),
                  ],
                ),
              ),
            ),
            actions: [
              if (widget.updater.isStore)
                TextButton(
                  onPressed: () => unawaited(widget.updater.openStore()),
                  child: const Text('Открыть RuStore'),
                ),
              TextButton(
                key: const ValueKey('update-check'),
                onPressed: widget.updater.busy
                    ? null
                    : () => unawaited(widget.updater.check()),
                child: const Text('Проверить'),
              ),
              if (widget.updater.state == UpdateState.available ||
                  (widget.updater.state == UpdateState.error &&
                      !widget.updater.isStore &&
                      widget.updater.availableVersion != null))
                FilledButton(
                  key: const ValueKey('update-download'),
                  onPressed: () => unawaited(widget.updater.download()),
                  child: Text(
                    widget.updater.isStore
                        ? 'Скачать через RuStore'
                        : 'Скачать',
                  ),
                ),
              if (widget.updater.state == UpdateState.downloaded)
                FilledButton(
                  key: const ValueKey('update-install'),
                  onPressed: () => unawaited(widget.updater.openInstaller()),
                  child: Text(
                    widget.updater.isStore
                        ? 'Установить через RuStore'
                        : 'Открыть установщик',
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Закрыть'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.updater,
    builder: (context, _) => IconButton(
      key: const ValueKey('app-updates'),
      tooltip: widget.updater.state == UpdateState.available
          ? _status
          : 'Обновления ServerDeck',
      onPressed: _show,
      icon: Badge(
        isLabelVisible: {
          UpdateState.available,
          UpdateState.downloaded,
        }.contains(widget.updater.state),
        child: const Icon(Icons.system_update_alt),
      ),
    ),
  );
  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _refresh.dispose();
    super.dispose();
  }
}
