import 'package:flutter/material.dart' hide ConnectionState;

import '../domain/error_presentation.dart';
import '../domain/models.dart';
import '../ui/deck_components.dart';
import 'console_models.dart';
import 'console_owner.dart';

class ConsoleView extends StatefulWidget {
  const ConsoleView({
    super.key,
    required this.owner,
    required this.profileId,
    required this.connectionRevision,
    required this.serverLabel,
    required this.username,
  });
  final ConsoleOwner owner;
  final String profileId, serverLabel, username;
  final int connectionRevision;
  @override
  State<ConsoleView> createState() => _ConsoleViewState();
}

class _ConsoleViewState extends State<ConsoleView> {
  String? _selected, _shellId, _error;
  bool _busy = false;
  final _routes = <(DialogRoute<bool>, NavigatorState)>{};
  ConsoleCaller get _caller => ConsoleCaller.ui(widget.owner.actors.ui);
  @override
  void initState() {
    super.initState();
    widget.owner.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _hide() {
    if (_selected != null) widget.owner.setVisible(_selected!, false);
  }

  void _closeRoutes() {
    final routes = List.of(_routes);
    _routes.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final (route, navigator) in routes) {
        if (route.isActive && navigator.mounted) navigator.removeRoute(route);
      }
    });
  }

  @override
  void didUpdateWidget(ConsoleView old) {
    super.didUpdateWidget(old);
    if (old.owner != widget.owner ||
        old.profileId != widget.profileId ||
        old.connectionRevision != widget.connectionRevision) {
      if (_selected != null) old.owner.setVisible(_selected!, false);
      old.owner.removeListener(_changed);
      widget.owner.addListener(_changed);
      _selected = null;
      _shellId = null;
      _error = null;
      _busy = false;
      _closeRoutes();
    }
  }

  Future<bool> _confirm(String title, String message) async {
    final navigator = Navigator.of(context);
    final route = DialogRoute<bool>(
      context: context,
      builder: (context) => DeckDialogLayout(
        title: title,
        child: Text(message),
        actions: [
          DeckButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          DeckButton(
            onPressed: () => Navigator.pop(context, true),
            kind: DeckButtonKind.primary,
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    );
    _routes.add((route, navigator));
    try {
      return await navigator.push(route) == true;
    } finally {
      _routes.remove((route, navigator));
    }
  }

  Future<void> _run(
    Future<OperationResult<ConsoleValue>> Function() action, {
    bool selectOpened = false,
  }) async {
    final owner = widget.owner,
        profile = widget.profileId,
        revision = widget.connectionRevision;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await action();
      if (!mounted ||
          owner != widget.owner ||
          profile != widget.profileId ||
          revision != widget.connectionRevision)
        return;
      setState(() {
        _error = result.error == null
            ? null
            : OperationPresentation.of(result.error!).message;
        if (result.value?.console case final ConsoleActionValue action) {
          if (action.status == 'outcomeUnknown') _error = 'Результат отправки неизвестен. Часть ввода могла попасть на сервер. Проверьте вывод перед новым действием.';
          if (action.status == 'cancelledBeforeSend')
            _error = 'Ввод отменён до отправки.';
          if (action.state != 'closed' && (_selected == null || selectOpened)) {
            _hide();
            _selected = action.sessionId;
            widget.owner.selectSession(widget.profileId, action.sessionId);
          }
        }
      });
    } catch (_) {
      if (mounted && owner == widget.owner)
        setState(
          () => _error = 'Операция консоли не выполнена. Повторите действие.',
        );
    } finally {
      if (mounted && owner == widget.owner && profile == widget.profileId)
        setState(() => _busy = false);
    }
  }

  Future<void> _paste(ConsoleSessionView session, String text) async {
    final owner = widget.owner,
        profile = widget.profileId,
        revision = widget.connectionRevision;
    String leaseToken;
    try {
      leaseToken = await owner.claimUiInput(session.sessionId);
    } on OperationFailure catch (failure) {
      if (mounted && owner == widget.owner && profile == widget.profileId)
        setState(() => _error = OperationPresentation.of(failure).message);
      return;
    }
    if (!mounted ||
        owner != widget.owner ||
        profile != widget.profileId ||
        revision != widget.connectionRevision ||
        _selected != session.sessionId)
      return;
    final multiline = text.contains('\n') || text.contains('\r');
    if (multiline) {
      final count = text.split(RegExp(r'\r\n|\r|\n')).length;
      if (!await _confirm(
        'Вставить несколько строк?',
        'Будет отправлено строк: $count. Переводы строки могут выполнить команды.',
      ))
        return;
    }
    if (!mounted ||
        owner != widget.owner ||
        profile != widget.profileId ||
        revision != widget.connectionRevision ||
        _selected != session.sessionId)
      return;
    if (owner.uiLeaseToken(session.sessionId) != leaseToken) return;
    await _run(
      () => owner.writeConsole(
        _caller,
        profile,
        session.sessionId,
        generation: session.generation,
        leaseToken: leaseToken,
        text: text,
        confirmedMultiline: multiline,
      ),
    );
  }

  Future<void> _close(ConsoleSessionView session) async {
    final owner = widget.owner, profile = widget.profileId;
    final revision = widget.connectionRevision;
    final leaseToken = owner.uiLeaseToken(session.sessionId);
    if (session.state == 'active' || session.state == 'opening') {
      if (!await _confirm(
        'Закрыть консоль?',
        'Удалённые процессы могут продолжить работу.',
      ))
        return;
    }
    if (!mounted ||
        owner != widget.owner ||
        profile != widget.profileId ||
        revision != widget.connectionRevision ||
        _selected != session.sessionId)
      return;
    await _run(
      () => owner.closeConsole(
        _caller,
        profile,
        session.sessionId,
        generation: session.generation,
        leaseToken: leaseToken,
        confirmed: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessions = widget.owner.sessionsFor(widget.profileId);
    if (!sessions.any((s) => s.sessionId == _selected)) {
      _hide();
      _selected = widget.owner.selectedSession(widget.profileId);
    }
    ConsoleSessionView? selected;
    for (final session in sessions) {
      if (session.sessionId == _selected) selected = session;
    }
    if (selected != null) widget.owner.setVisible(selected.sessionId, true);
    ConsoleConfiguration? config;
    try {
      config = widget.owner.configuration();
    } catch (_) {
      _error = 'Не удалось прочитать настройки терминала.';
    }
    final ready =
        widget.owner.connections.connection(widget.profileId).state ==
        ConnectionState.connected;
    final shellId =
        config?.profile(_shellId ?? config.defaultId)?.id ?? config?.defaultId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.serverLabel,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text('Пользователь: ${widget.username}'),
        if (_error != null) DeckNotice(message: _error!, tone: DeckTone.error),
        if (!ready)
          const DeckNotice(
            message: 'Подключитесь к серверу и подтвердите доверие в настройках сервера.',
          ),
        if (config != null)
          DropdownButtonFormField<String>(
            key: ValueKey('console-shell-$shellId'),
            initialValue: shellId,
            decoration: const InputDecoration(labelText: 'Профиль оболочки'),
            items: [
              for (final shell in config.all)
                DropdownMenuItem(value: shell.id, child: Text(shell.name)),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _shellId = value),
          ),
        DeckActions(
          children: [
            DeckButton(
              onPressed: _busy || !ready || config == null
                  ? null
                  : () => _run(
                      () => widget.owner.openConsole(
                        _caller,
                        widget.profileId,
                        shellProfileId: shellId,
                      ),
                      selectOpened: true,
                    ),
              child: Text(
                sessions.isEmpty ? 'Открыть консоль' : 'Новая консоль',
              ),
            ),
          ],
        ),
        if (sessions.isNotEmpty)
          DropdownButtonFormField<String>(
            key: ValueKey('console-session-$_selected'),
            initialValue: _selected,
            decoration: const InputDecoration(labelText: 'Сессия консоли'),
            items: [
              for (var i = 0; i < sessions.length; i++)
                DropdownMenuItem(
                  value: sessions[i].sessionId,
                  child: Text('Консоль ${i + 1} · ${sessions[i].shellName}'),
                ),
            ],
            onChanged: (value) => setState(() {
              _hide();
              _selected = value;
              widget.owner.selectSession(widget.profileId, value);
            }),
          ),
        if (selected != null) ...[
          if (widget.owner.inputFailure(selected.sessionId) case final failure?)
            DeckNotice(
              message: OperationPresentation.of(failure).message,
              tone: DeckTone.error,
            ),
          if (widget.owner.inputOutcome(selected.sessionId) == 'outcomeUnknown')
            const DeckNotice(
              message: 'Результат отправки неизвестен. Проверьте вывод перед новым действием.',
              tone: DeckTone.warning,
            ),
          DeckStatus(
            label: _status(selected.state),
            pending: selected.state == 'opening',
          ),
          if (selected.reason != null)
            DeckNotice(
              message: _reason(selected.reason!),
              tone: DeckTone.warning,
            ),
          if (selected.partial)
            const DeckNotice(
              message: 'Вывод может быть неполным.',
              tone: DeckTone.warning,
            ),
          if (selected.exitCode != null)
            Text('Код выхода оболочки: ${selected.exitCode}'),
          DeckButton(
            onPressed: _busy ? null : () => _close(selected!),
            child: const Text('Закрыть консоль'),
          ),
          if (selected.inputOwner.kind == 'mcp')
            Text(
              'Ввод: MCP · ${selected.inputOwner.name ?? selected.inputOwner.clientId}',
            ),
          DeckButton(
            onPressed: _busy || !['active', 'opening'].contains(selected.state)
                ? null
                : () => _run(
                    () => widget.owner.acquireConsole(
                      _caller,
                      widget.profileId,
                      selected!.sessionId,
                      generation: selected.generation,
                    ),
                  ),
            child: const Text('Взять управление'),
          ),
          if (selected.inputOwner.kind == 'ui')
            DeckButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => widget.owner.releaseConsole(
                        _caller,
                        widget.profileId,
                        selected!.sessionId,
                        generation: selected.generation,
                        leaseToken: widget.owner.uiLeaseToken(
                          selected.sessionId,
                        )!,
                      ),
                    ),
              child: const Text('Передать управление MCP'),
            ),
          SizedBox(
            height: 360,
            child: DeckTerminal(
              key: ValueKey('terminal-${selected.sessionId}'),
              terminal: widget.owner.engine(selected.sessionId)!.terminal,
              readOnly:
                  selected.state != 'active' ||
                  selected.inputOwner.kind == 'mcp',
              onPaste: (text) => _paste(selected!, text),
              onResize: (columns, rows) => widget.owner.resizeConsole(
                selected!.sessionId,
                columns,
                rows,
              ),
            ),
          ),
        ] else
          const DeckNotice(message: 'Консоль ещё не открыта.'),
      ],
    );
  }

  static String _status(String state) => switch (state) {
    'opening' => 'Открывается',
    'active' => 'Активна',
    'ended' => 'Завершена',
    'disconnected' => 'Связь потеряна',
    'error' => 'Ошибка',
    _ => 'Консоль закрыта',
  };
  static String _reason(String reason) => switch (reason) {
    'timeout' => 'Истекло время ожидания.',
    'unavailable' => 'Не удалось открыть выбранную оболочку. Проверьте путь и поддержку PTY на сервере.',
    'ptyDenied' => 'Сервер отказал в псевдотерминале (PTY).',
    'shellDenied' =>
      'Сервер отказал в запуске выбранной оболочки. Проверьте путь и права.',
    'cleanupRequired' =>
      'Достигнут предел незакрытых каналов. Дождитесь их закрытия.',
    'unsupportedServer' =>
      'Сервер прислал неподдерживаемые параметры терминального канала.',
    'networkError' => 'Не удалось открыть канал из-за ошибки SSH-соединения.',
    'outputLimit' => 'Вывод превысил допустимый предел.',
    'contextChanged' =>
      'Параметры подключения или доверие изменились. История очищена.',
    'connectionLost' => 'SSH-подключение закрыто.',
    'cancelled' => 'Открытие отменено.',
    'shutdown' => 'Приложение завершает работу.',
    _ => 'Канал оболочки завершился с ошибкой.',
  };
  @override
  void dispose() {
    _hide();
    _closeRoutes();
    widget.owner.removeListener(_changed);
    super.dispose();
  }
}
