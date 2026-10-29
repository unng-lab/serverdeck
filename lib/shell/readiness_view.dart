import 'package:flutter/material.dart';
import 'package:serverdeck_protocol/models.dart' show ErrorCode, ReadinessState;

import '../ui/deck_components.dart';
import '../ui/deck_page.dart';
import '../servers/server_compositions.dart';

class ReadinessView extends StatefulWidget {
  const ReadinessView({
    super.key,
    required this.state,
    this.reason,
    this.onRetry,
    this.retryInProgress = false,
  });
  final ReadinessState state;
  final ErrorCode? reason;
  final VoidCallback? onRetry;
  final bool retryInProgress;
  @override
  State<ReadinessView> createState() => _ReadinessViewState();
}

class _ReadinessViewState extends State<ReadinessView> {
  bool _details = false;
  @override
  void didUpdateWidget(covariant ReadinessView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _details = false;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    if (state == ReadinessState.ready)
      throw StateError('Ready requires the workspace shell');
    final pending = {
      ReadinessState.starting,
      ReadinessState.recovering,
      ReadinessState.stopping,
    }.contains(state);
    final title = switch (state) {
      ReadinessState.starting => 'Запуск рабочего пространства',
      ReadinessState.recovering => 'Восстановление локального пространства',
      ReadinessState.stopping => 'Завершение работы локальной службы',
      ReadinessState.storageBlocked => 'Доступ к хранилищу заблокирован',
      ReadinessState.incompatible => 'Несовместимая версия локальной службы',
      _ => 'Локальная служба недоступна',
    };
    final stage = widget.retryInProgress
        ? 'Ожидаем результат текущей попытки.'
        : switch (state) {
            ReadinessState.starting => 'Запуск локальной службы',
            ReadinessState.recovering =>
              'Восстановление локального пространства',
            ReadinessState.stopping => 'Завершение работы локальной службы',
            ReadinessState.storageBlocked =>
              'Локальное хранилище заблокировано',
            ReadinessState.incompatible =>
              'Версии клиента и локальной службы несовместимы',
            _ => 'Служба недоступна',
          };
    final next = switch (state) {
      ReadinessState.starting => 'Ожидаем результат запуска.',
      ReadinessState.recovering =>
        'Дождитесь завершения восстановления локального пространства.',
      ReadinessState.stopping => 'Ожидаем завершения работы службы.',
      ReadinessState.incompatible => 'Используйте совместимые версии клиента и локальной службы, затем повторите запуск.',
      ReadinessState.storageBlocked => 'Проверьте доступность защищённого локального хранилища, затем повторите запуск.',
      _ => 'Проверьте доступность локальной службы и повторите запуск.',
    };
    final tone = switch (state) {
      ReadinessState.storageBlocked => DeckTone.error,
      ReadinessState.incompatible => DeckTone.warning,
      ReadinessState.unavailable => DeckTone.unavailable,
      _ => DeckTone.running,
    };
    final facts = <String, String>{
      'Состояние': stage,
      if (pending) ...{
        'Этап': next,
        'Доступ': 'Локальные данные появятся после проверки',
      },
      if (!pending && state != ReadinessState.storageBlocked) ...{
        'Причина': widget.reason == null
            ? 'Дополнительная причина не предоставлена'
            : _reasonMessage(widget.reason!),
        'Данные': 'Рабочее пространство сохранено',
        'Область отказа':
            'Локальная служба; это не SSH offline выбранного сервера',
      },
      if (state == ReadinessState.storageBlocked) ...{
        'Следующий шаг': next,
        'Сохранность': 'Исходные данные сохраняются',
        'Ограничение': 'Нет сброса данных и открытого запасного хранения',
      },
    };
    if ((pending || state == ReadinessState.storageBlocked) &&
        widget.reason != null)
      facts['Причина'] = _reasonMessage(widget.reason!);
    final tabs = pending
        ? const {
            ReadinessState.starting: 'Запуск',
            ReadinessState.recovering: 'Восстановление',
            ReadinessState.stopping: 'Завершение',
          }
        : const {
            ReadinessState.unavailable: 'Недоступна',
            ReadinessState.incompatible: 'Несовместимая версия',
          };
    return DeckPage(
      title: title,
      eyebrow: 'Серверы / Рабочее пространство',
      description: 'Состояние и следующие доступные действия',
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state != ReadinessState.storageBlocked) ...[
              Tooltip(
                message: 'Состояние определяет локальная служба',
                child: DeckTabs(
                  labels: tabs.values.toList(),
                  selected: tabs.keys
                      .toList()
                      .indexOf(state)
                      .clamp(0, tabs.length - 1),
                  onSelected: null,
                ),
              ),
              const DeckTabsGap(),
            ],
            ServerStatusBody(
              title: title,
              facts: facts,
              tone: tone,
              icon: pending ? 'clock' : 'close',
              emblemRole: pending ? 'running' : 'error',
              details: _details
                  ? Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(next),
                          if (widget.reason != null &&
                              state == ReadinessState.storageBlocked)
                            Text(_reasonMessage(widget.reason!)),
                          if (widget.retryInProgress)
                            const Text(
                              'Текущая попытка уже выполняется. Дождитесь результата.',
                            ),
                        ],
                      ),
                    )
                  : null,
              actions: [
                if (!pending && widget.onRetry != null)
                  FilledButton(
                    clipBehavior: Clip.none,
                    onPressed: widget.retryInProgress ? null : widget.onRetry,
                    child: const Text('Повторить запуск'),
                  ),
                if (pending)
                  const Tooltip(
                    message: 'Дождитесь перехода локальной службы. Повторный запуск не создаётся.',
                    child: FilledButton(
                      clipBehavior: Clip.none,
                      onPressed: null,
                      child: Text('Дождаться запуска'),
                    ),
                  ),
                if (!pending)
                  OutlinedButton(
                    clipBehavior: Clip.none,
                    onPressed: () => setState(() => _details = !_details),
                    child: Text(
                      state == ReadinessState.storageBlocked
                          ? 'Показать сведения'
                          : 'Открыть сведения',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _reasonMessage(ErrorCode reason) => switch (reason) {
  ErrorCode.unsupported => 'Эта функция локальной службы пока недоступна.',
  ErrorCode.unauthorized => 'Не удалось подтвердить доступ к локальной службе.',
  ErrorCode.forbidden => 'Локальная служба не разрешила это действие.',
  ErrorCode.incompatible => 'Версии клиента и локальной службы несовместимы.',
  ErrorCode.notReady => 'Локальное пространство ещё не готово.',
  ErrorCode.storageBlocked => 'Доступ к локальному хранилищу заблокирован. Требуется проверка локального пространства.',
  ErrorCode.validation => 'Локальная служба отклонила некорректный запрос.',
  ErrorCode.notFound => 'Запрошенные локальные данные не найдены.',
  ErrorCode.alreadyExists => 'Такие локальные данные уже существуют.',
  ErrorCode.revisionConflict =>
    'Локальные данные изменились. Требуется перечитать состояние.',
  ErrorCode.idempotencyConflict =>
    'Запрос повтора отличается от исходного действия.',
  ErrorCode.resourceLimit =>
    'Достигнуто ограничение ресурсов локального пространства.',
  ErrorCode.timeout => 'Время ожидания ответа локальной службы истекло.',
  ErrorCode.serviceUnavailable => 'Не удалось связаться с локальной службой.',
  ErrorCode.internal => 'Локальная служба не смогла завершить действие.',
};
