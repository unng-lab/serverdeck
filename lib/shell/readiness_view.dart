import 'package:flutter/material.dart';
import 'package:serverdeck_protocol/models.dart' show ErrorCode, ReadinessState;

import '../theme/brand_tokens.dart';
import '../ui/deck_components.dart';

class ReadinessView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (state == ReadinessState.ready) {
      throw StateError('Ready requires the workspace shell');
    }
    final title = switch (state) {
      ReadinessState.starting => 'Запуск локальной службы',
      ReadinessState.recovering => 'Восстановление локального пространства',
      ReadinessState.storageBlocked => 'Локальное хранилище заблокировано',
      ReadinessState.incompatible => 'Несовместимая версия локальной службы',
      ReadinessState.stopping => 'Завершение работы локальной службы',
      ReadinessState.unavailable => 'Локальная служба недоступна',
      ReadinessState.ready => throw StateError(
        'Ready requires the workspace shell',
      ),
    };
    final retryAvailable =
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
    final stage = retryInProgress
        ? 'Ожидаем результат текущей попытки.'
        : switch (state) {
            ReadinessState.starting ||
            ReadinessState.recovering => 'Ожидаем результат запуска.',
            ReadinessState.stopping => 'Ожидаем завершения работы службы.',
            ReadinessState.unavailable => 'Локальное пространство недоступно.',
            ReadinessState.incompatible => 'Требуется совместимая версия.',
            ReadinessState.storageBlocked => 'Доступ к хранилищу заблокирован.',
            ReadinessState.ready => throw StateError(
              'Ready requires the workspace shell',
            ),
          };
    final nextStep = switch (state) {
      ReadinessState.starting => 'Дождитесь готовности локального пространства. Данные появятся после проверки доступа.',
      ReadinessState.recovering =>
        'Дождитесь завершения восстановления локального пространства.',
      ReadinessState.stopping =>
        'Дождитесь завершения текущей службы перед новым запуском.',
      ReadinessState.unavailable =>
        'Проверьте доступность локальной службы и повторите запуск.',
      ReadinessState.incompatible => 'Используйте совместимые версии клиента и локальной службы, затем повторите запуск.',
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
                          if (reason != null) ...[
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
