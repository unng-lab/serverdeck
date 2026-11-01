import 'package:flutter/material.dart';
import 'package:serverdeck_protocol/models.dart' show ErrorCode, ReadinessState;

import '../theme/brand_tokens.dart';
import '../ui/deck_components.dart';

class ReadinessView extends StatelessWidget {
  const ReadinessView({
    super.key,
    required this.state,
    this.reason,
    this.workspaceBusy = false,
    this.onRetry,
    this.retryInProgress = false,
  });

  final ReadinessState state;
  final ErrorCode? reason;
  final bool workspaceBusy;
  final VoidCallback? onRetry;
  final bool retryInProgress;

  @override
  Widget build(BuildContext context) {
    if (state == ReadinessState.ready) {
      throw StateError('Ready requires the workspace shell');
    }
    final title = workspaceBusy
        ? 'Рабочее пространство было занято при запуске'
        : switch (state) {
            ReadinessState.starting => 'Запуск ServerDeck',
            ReadinessState.recovering =>
              'Восстановление локального пространства',
            ReadinessState.storageBlocked =>
              'Локальное хранилище заблокировано',
            ReadinessState.incompatible =>
              'Компоненты или данные ServerDeck несовместимы',
            ReadinessState.stopping => 'Завершение работы ServerDeck',
            ReadinessState.unavailable => 'ServerDeck недоступен',
            ReadinessState.ready => throw StateError(
              'Ready requires the workspace shell',
            ),
          };
    final retryAvailable =
        !workspaceBusy &&
        onRetry != null &&
        switch (state) {
          ReadinessState.storageBlocked ||
          ReadinessState.incompatible ||
          ReadinessState.unavailable => true,
          _ => false,
        };
    final pending =
        retryInProgress ||
        {
          ReadinessState.starting,
          ReadinessState.recovering,
          ReadinessState.stopping,
        }.contains(state);
    final tone = switch (state) {
      ReadinessState.storageBlocked => DeckTone.error,
      ReadinessState.incompatible => DeckTone.warning,
      ReadinessState.unavailable => DeckTone.unavailable,
      _ => DeckTone.running,
    };
    final stage = workspaceBusy
        ? 'Этот экземпляр не открывал данные.'
        : retryInProgress
        ? 'Ожидаем результат текущей попытки.'
        : switch (state) {
            ReadinessState.starting ||
            ReadinessState.recovering => 'Ожидаем результат запуска.',
            ReadinessState.stopping => 'Ожидаем завершения работы ServerDeck.',
            ReadinessState.unavailable => 'Локальное пространство недоступно.',
            ReadinessState.incompatible => 'Требуется совместимая версия.',
            ReadinessState.storageBlocked => 'Доступ к хранилищу заблокирован.',
            ReadinessState.ready => throw StateError(
              'Ready requires the workspace shell',
            ),
          };
    final nextStep = workspaceBusy
        ? 'Используйте уже запущенное приложение. Если оно завершено, закройте это окно и запустите ServerDeck снова.'
        : switch (state) {
            ReadinessState.starting => 'Дождитесь готовности локального пространства. Данные появятся после проверки доступа.',
            ReadinessState.recovering =>
              'Дождитесь завершения восстановления локального пространства.',
            ReadinessState.stopping =>
              'Дождитесь завершения ServerDeck перед новым запуском.',
            ReadinessState.unavailable =>
              'Повторите проверку состояния ServerDeck.',
            ReadinessState.incompatible => 'Проверьте целостность комплекта ServerDeck и поддерживаемый формат данных. Исходные данные сохранены.',
            ReadinessState.storageBlocked => 'Проверьте доступность защищённого локального хранилища, затем повторите запуск.',
            ReadinessState.ready => throw StateError(
              'Ready requires the workspace shell',
            ),
          };
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : 0,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(BrandSpacing.space24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Semantics(
                    liveRegion: true,
                    child: DeckSurface(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          const SizedBox(height: BrandSpacing.space16),
                          DeckStatus(
                            label: stage,
                            tone: tone,
                            pending: pending,
                          ),
                          if (reason != null && !workspaceBusy) ...[
                            const SizedBox(height: BrandSpacing.space16),
                            Text(_reasonMessage(reason!)),
                          ],
                          const SizedBox(height: BrandSpacing.space16),
                          Text(
                            retryInProgress
                                ? 'Текущая попытка уже выполняется. Дождитесь результата.'
                                : nextStep,
                          ),
                          if (retryAvailable) ...[
                            const SizedBox(height: BrandSpacing.space24),
                            DeckActions(
                              children: [
                                FilledButton(
                                  onPressed: retryInProgress ? null : onRetry,
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(48, 48),
                                  ),
                                  child: const Text(
                                    'Повторить запуск',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

String _reasonMessage(ErrorCode reason) => switch (reason) {
  ErrorCode.unsupported => 'Эта функция ServerDeck пока недоступна.',
  ErrorCode.unauthorized => 'Не удалось подтвердить доступ к ServerDeck.',
  ErrorCode.forbidden => 'ServerDeck не разрешил это действие.',
  ErrorCode.incompatible =>
    'Компоненты приложения или формат данных несовместимы.',
  ErrorCode.notReady => 'Локальное пространство ещё не готово.',
  ErrorCode.storageBlocked => 'Доступ к локальному хранилищу заблокирован. Требуется проверка локального пространства.',
  ErrorCode.validation => 'ServerDeck отклонил некорректный запрос.',
  ErrorCode.notFound => 'Запрошенные локальные данные не найдены.',
  ErrorCode.alreadyExists => 'Такие локальные данные уже существуют.',
  ErrorCode.revisionConflict =>
    'Локальные данные изменились. Требуется перечитать состояние.',
  ErrorCode.idempotencyConflict =>
    'Запрос повтора отличается от исходного действия.',
  ErrorCode.resourceLimit =>
    'Достигнуто ограничение ресурсов локального пространства.',
  ErrorCode.timeout => 'Время ожидания ответа ServerDeck истекло.',
  ErrorCode.serviceUnavailable => 'ServerDeck сейчас недоступен.',
  ErrorCode.internal => 'ServerDeck не смог завершить действие.',
};
