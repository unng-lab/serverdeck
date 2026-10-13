import 'package:flutter/material.dart';
import 'package:serverdeck_protocol/models.dart' show ErrorCode, ReadinessState;

import '../theme/brand_theme.dart';

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
    final theme = Theme.of(context);
    final colors = theme.extension<BrandColors>()!;
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
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Semantics(
                    liveRegion: true,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            style: theme.textTheme.titleLarge,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        if (reason != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _reasonMessage(reason!),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        if (state == ReadinessState.starting ||
                            state == ReadinessState.recovering) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Ожидаем результат запуска.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                        if (retryAvailable) ...[
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: retryInProgress ? null : onRetry,
                            style: ButtonStyle(
                              minimumSize: const WidgetStatePropertyAll(
                                Size(48, 48),
                              ),
                              shape: WidgetStatePropertyAll(
                                RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              side: WidgetStateProperty.resolveWith(
                                (states) => BorderSide(
                                  color: states.contains(WidgetState.focused)
                                      ? colors['focus']
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: const Text(
                              'Повторить запуск',
                              textAlign: TextAlign.center,
                            ),
                          ),
                          if (retryInProgress) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Ожидаем результат текущей попытки.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ],
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
