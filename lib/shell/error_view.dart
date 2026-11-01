import 'package:flutter/material.dart';
import 'package:serverdeck_protocol/models.dart' show ErrorCode;

import '../theme/brand_tokens.dart';
import '../ui/deck_components.dart';

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
    ErrorCode.unauthorized => 'Доступ к ServerDeck не подтверждён',
    ErrorCode.forbidden => 'Операция запрещена',
    ErrorCode.incompatible => 'Компоненты или данные ServerDeck несовместимы',
    ErrorCode.notReady => 'ServerDeck ещё не готов',
    ErrorCode.storageBlocked => 'Локальное хранилище заблокировано',
    ErrorCode.validation => 'Локальные данные не прошли проверку',
    ErrorCode.notFound => 'Локальные данные не найдены',
    ErrorCode.alreadyExists => 'Локальные данные уже существуют',
    ErrorCode.revisionConflict => 'Данные изменились в другом окне',
    ErrorCode.idempotencyConflict =>
      'Повторная операция отличается от исходной',
    ErrorCode.resourceLimit => 'Достигнут лимит локальных ресурсов',
    ErrorCode.timeout => 'ServerDeck не ответил вовремя',
    ErrorCode.serviceUnavailable => 'ServerDeck сейчас недоступен',
    ErrorCode.internal => 'Ошибка ServerDeck',
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
        'Используйте версию ServerDeck с поддержкой этой функции.',
      ErrorCode.forbidden => 'Проверьте права доступа к ServerDeck.',
      ErrorCode.validation =>
        'Проверьте параметры действия и повторите чтение данных.',
      ErrorCode.alreadyExists || ErrorCode.idempotencyConflict =>
        'Перечитайте актуальные данные перед новой операцией.',
      ErrorCode.incompatible => 'Проверьте целостность комплекта ServerDeck и поддерживаемый формат данных. Исходные данные сохранены.',
      ErrorCode.storageBlocked => 'Проверьте доступность защищённого хранилища, затем повторите проверку ServerDeck.',
      _ =>
        read
            ? 'Повторите чтение актуальных локальных данных.'
            : 'Повторите проверку состояния ServerDeck.',
    };
    final tone = switch (code) {
      ErrorCode.serviceUnavailable || ErrorCode.timeout => DeckTone.unavailable,
      ErrorCode.storageBlocked ||
      ErrorCode.internal ||
      ErrorCode.unauthorized => DeckTone.error,
      _ => DeckTone.warning,
    };
    final notice = DeckNotice(
      title: category(code),
      message: hint,
      tone: tone,
      actions: [
        if (read || check)
          FilledButton(
            onPressed: reading
                ? null
                : read
                ? onReadAgain
                : onCheckService,
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            child: Text(read ? 'Повторить чтение' : 'Повторить проверку'),
          ),
      ],
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(BrandSpacing.space24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Semantics(
            liveRegion: true,
            child: reading
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DeckStatus(label: pendingLabel, pending: true),
                      const SizedBox(height: BrandSpacing.space12),
                      notice,
                    ],
                  )
                : notice,
          ),
        ),
      ),
    );
  }
}
