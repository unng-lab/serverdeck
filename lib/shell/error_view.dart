import 'package:flutter/material.dart';
import 'package:serverdeck_protocol/models.dart' show ErrorCode;

import '../theme/brand_tokens.dart';
import '../ui/deck_components.dart';
import '../ui/deck_page.dart';
import '../servers/server_compositions.dart';

/// Only a safe code enters presentation; private exception text is excluded.
class ReadErrorView extends StatelessWidget {
  const ReadErrorView({
    super.key,
    required this.code,
    required this.onReadAgain,
    required this.onCheckService,
    this.reading = false,
    this.pendingLabel = 'Чтение актуальных локальных данных',
  });
  final ErrorCode code;
  final VoidCallback onReadAgain, onCheckService;
  final bool reading;
  final String pendingLabel;

  static String category(ErrorCode code) => switch (code) {
    ErrorCode.unsupported => 'Функция недоступна в этой версии',
    ErrorCode.unauthorized => 'Доступ к локальной службе не подтверждён',
    ErrorCode.forbidden => 'Операция запрещена',
    ErrorCode.incompatible => 'Несовместимая версия локальной службы',
    ErrorCode.notReady => 'Локальная служба ещё не готова',
    ErrorCode.storageBlocked => 'Локальное хранилище заблокировано',
    ErrorCode.validation => 'Локальные данные не прошли проверку',
    ErrorCode.notFound => 'Локальные данные не найдены',
    ErrorCode.alreadyExists => 'Локальные данные уже существуют',
    ErrorCode.revisionConflict => 'Данные изменились в другом окне',
    ErrorCode.idempotencyConflict =>
      'Повторная операция отличается от исходной',
    ErrorCode.resourceLimit => 'Достигнут лимит локальных ресурсов',
    ErrorCode.timeout => 'Локальная служба не ответила вовремя',
    ErrorCode.serviceUnavailable => 'Связь с локальной службой потеряна',
    ErrorCode.internal => 'Ошибка локальной службы',
  };

  @override
  Widget build(BuildContext context) {
    final read = {
      ErrorCode.timeout,
      ErrorCode.resourceLimit,
      ErrorCode.internal,
      ErrorCode.notFound,
      ErrorCode.revisionConflict,
    }.contains(code);
    final check = {
      ErrorCode.unauthorized,
      ErrorCode.serviceUnavailable,
      ErrorCode.notReady,
      ErrorCode.storageBlocked,
      ErrorCode.incompatible,
    }.contains(code);
    final hint = switch (code) {
      ErrorCode.unsupported =>
        'Используйте версию клиента с поддержкой этой функции.',
      ErrorCode.forbidden => 'Проверьте права доступа к локальной службе.',
      ErrorCode.validation =>
        'Проверьте совместимость клиента и локальной службы.',
      ErrorCode.alreadyExists || ErrorCode.idempotencyConflict =>
        'Перечитайте актуальные данные перед новой операцией.',
      ErrorCode.incompatible => 'Используйте совместимые версии клиента и службы, затем повторите проверку.',
      ErrorCode.storageBlocked => 'Проверьте доступность локального хранилища, затем повторите проверку службы.',
      _ =>
        read
            ? 'Повторите чтение актуальных локальных данных.'
            : 'Повторите проверку подключения к локальной службе.',
    };
    final tone = switch (code) {
      ErrorCode.serviceUnavailable || ErrorCode.timeout => DeckTone.unavailable,
      ErrorCode.storageBlocked ||
      ErrorCode.internal ||
      ErrorCode.unauthorized => DeckTone.error,
      _ => DeckTone.warning,
    };
    return DeckPage(
      title: 'Не удалось прочитать локальные данные',
      eyebrow: 'Рабочее пространство',
      description: 'Состояние чтения локальной службы',
      child: Semantics(
        liveRegion: true,
        child: ServerStatusBody(
          title: category(code),
          tone: tone,
          icon: code == ErrorCode.storageBlocked ? 'shield' : 'network',
          facts: {
            'Состояние': category(code),
            'Источник': 'Локальная служба',
            'Данные': 'Сохранённые данные не удалены',
            'Следующий шаг': hint,
          },
          details: reading
              ? Padding(
                  padding: const EdgeInsets.only(top: BrandSpacing.space12),
                  child: DeckStatus(label: pendingLabel, pending: true),
                )
              : null,
          actions: [
            if (read || check)
              FilledButton(
                clipBehavior: Clip.none,
                onPressed: reading
                    ? null
                    : read
                    ? onReadAgain
                    : onCheckService,
                child: Text(
                  read ? 'Повторить чтение' : 'Повторить проверку службы',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
