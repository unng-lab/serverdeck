import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/deck_components.dart';
import 'update_owner.dart';

String _failure(String? code) => switch (code) {
  'UPDATE_NOT_CONFIGURED' => 'Источник обновлений не настроен для этой сборки.',
  'NETWORK_UNAVAILABLE' =>
    'Источник обновлений недоступен. Проверьте подключение.',
  'TIMEOUT' => 'Источник обновлений не ответил вовремя.',
  'SOURCE_UNTRUSTED' || 'INVALID_CATALOG' =>
    'Не удалось подтвердить подлинность каталога обновлений.',
  'SOURCE_EXPIRED' => 'Срок действия каталога обновлений истёк.',
  'SOURCE_CHANGED' =>
    'Состав выбранного выпуска изменился. Проверьте обновления заново.',
  'RELEASE_REVOKED' => 'Выбранный выпуск больше не доступен в каталоге.',
  'RELEASE_INCOMPATIBLE' =>
    'Новый выпуск несовместим с этой программой или форматом данных.',
  'INVALID_ARTIFACT' => 'Скачанный установщик не прошёл проверку целостности.',
  'DISK_SPACE' => 'Недостаточно свободного места для обновления.',
  'OWNER_RUNNING' => 'Для установки выйдите из ServerDeck через меню трея.',
  'BUSY' => 'Другая операция обновления ещё не завершена.',
  'CANCELLED' => 'Проверка или скачивание отменены.',
  'RECOVERY_REQUIRED' =>
    'Файлы установки требуют восстановления полным доверенным установщиком.',
  _ => 'Не удалось прочитать или сохранить состояние обновления.',
};

/// Global settings content. The runtime owns its route and every nested prompt;
/// this widget only presents state and requests explicit consent through C14.
class UpdateView extends StatefulWidget {
  const UpdateView({super.key, required this.owner});
  final UpdateOwner owner;
  @override
  State<UpdateView> createState() => _UpdateViewState();
}

class _UpdateViewState extends State<UpdateView> {
  bool _pending = false;
  Future<void> _run(Future<void> Function() action) async {
    if (_pending) return;
    setState(() => _pending = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  Future<void> _confirm() async {
    final owner = widget.owner, offer = widget.owner.snapshot.offer;
    if (offer == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => DeckDialogLayout(
        title: 'Подготовить обновление ${offer.version}?',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Будет скачан полный установщик: ${offer.setupSize} байт.'),
            const Text(
              'После проверки этот выпуск установится при следующем запуске программы. '
              'Когда будете готовы, выйдите через меню трея и снова запустите ServerDeck. '
              'Профили, настройки и защищённые учётные данные сохранятся.',
            ),
          ],
        ),
        actions: [
          DeckButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          DeckButton(
            kind: DeckButtonKind.primary,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Скачать и установить при следующем запуске'),
          ),
        ],
      ),
    );
    if (!mounted ||
        !identical(owner, widget.owner) ||
        confirmed != true ||
        owner.snapshot.state != UpdateState.available ||
        !identical(owner.snapshot.offer, offer))
      return;
    unawaited(owner.download(offer));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.owner,
    builder: (context, _) {
      final owner = widget.owner,
          snapshot = owner.snapshot,
          offer = snapshot.offer;
      return SingleChildScrollView(
        child: DeckFormSection(
          title: 'Обновления',
          children: [
            DeckKeyValue(
              label: 'Текущая версия',
              value: snapshot.currentVersion,
            ),
            SwitchListTile(
              title: const Text('Проверять обновления автоматически'),
              subtitle: const Text(
                'Раз в 24 часа. Скачивание начинается только после вашего подтверждения.',
              ),
              value: snapshot.enabled,
              onChanged: _pending
                  ? null
                  : (value) => unawaited(owner.setEnabled(value)),
            ),
            DeckTimestamp(
              label: 'Последняя попытка',
              value: _date(snapshot.lastAttempt),
            ),
            DeckTimestamp(
              label: 'Последняя успешная проверка',
              value: _date(snapshot.lastSuccess),
            ),
            DeckStatus(
              label: switch (snapshot.state) {
                UpdateState.idle => 'Ожидание проверки',
                UpdateState.checking => 'Проверяем обновления',
                UpdateState.current => 'Установлена актуальная версия',
                UpdateState.available => 'Доступно обновление',
                UpdateState.downloading => 'Скачиваем установщик',
                UpdateState.verifying => 'Проверяем установщик',
                UpdateState.ready => 'Обновление готово',
                UpdateState.failed =>
                  'Не удалось завершить проверку или скачивание',
              },
              tone: snapshot.active
                  ? DeckTone.running
                  : snapshot.state == UpdateState.failed
                  ? DeckTone.warning
                  : DeckTone.neutral,
            ),
            if (owner.error != null || snapshot.code != null)
              DeckNotice(
                title: 'Обновление не завершено',
                message: _failure(owner.error ?? snapshot.code),
                nextStep: 'Рабочая установка и пользовательские данные сохраняются. Повторите проверку, когда будете готовы.',
                tone: DeckTone.warning,
              ),
            if (snapshot.preparedVersion != null &&
                (snapshot.state != UpdateState.ready ||
                    snapshot.preparedVersion != offer?.version ||
                    snapshot.preparedCode != null))
              DeckNotice(
                title: 'Ранее подготовлено ${snapshot.preparedVersion}',
                message: snapshot.preparedCode == null
                    ? 'Комплект сохранён для следующего запуска и будет повторно проверен перед применением. '
                          'Подготовка другого выпуска заменит его только после успешного скачивания и проверки.'
                    : '${_failure(snapshot.preparedCode)} Сохранённые файлы остаются на диске. Другой выпуск требует отдельного подтверждения.',
                tone: snapshot.preparedCode == null
                    ? DeckTone.neutral
                    : DeckTone.warning,
              ),
            if (offer != null) ...[
              DeckKeyValue(label: 'Новая версия', value: offer.version),
              DeckKeyValue(
                label: 'Размер установщика',
                value: '${offer.setupSize} байт',
              ),
              DeckTimestamp(
                label: 'Дата выпуска',
                value: _date(offer.publishedUtc),
              ),
              DeckKeyValue(label: 'Платформа', value: offer.platform),
              DeckCapability(
                title: 'Совместимость выпуска',
                reason:
                    '${offer.compatibilityReason.isEmpty ? 'Совместим с текущей программой и форматом данных.' : offer.compatibilityReason} ABI ${offer.bootstrapAbi}; формат данных ${offer.storeFormat}.',
                tone: DeckTone.available,
                statusLabel: 'Совместимо',
              ),
              DeckKeyValue(
                label: 'Что нового',
                value: offer.notes.isEmpty
                    ? 'Описание выпуска отсутствует.'
                    : offer.notes,
              ),
            ],
            if (snapshot.state == UpdateState.downloading)
              DeckProgress(
                label: snapshot.total == null
                    ? '${snapshot.bytes} байт · общий объём загрузки не сообщён'
                    : '${snapshot.bytes} из ${snapshot.total} байт',
                value: snapshot.total == null || snapshot.total == 0
                    ? null
                    : snapshot.bytes / snapshot.total!,
              ),
            if (snapshot.state == UpdateState.ready)
              const DeckNotice(
                title: 'Установщик проверен',
                message: 'Когда будете готовы, выйдите из ServerDeck через меню трея, затем снова запустите программу. Обновление применится до открытия данных.',
                nextStep: 'Текущие SSH-подключения продолжают работать до вашего выхода.',
                tone: DeckTone.success,
              ),
            DeckActions(
              children: [
                DeckButton(
                  onPressed: _pending || snapshot.active
                      ? null
                      : () => unawaited(owner.check()),
                  child: const Text('Проверить сейчас'),
                ),
                if (snapshot.state == UpdateState.available) ...[
                  DeckButton(
                    kind: DeckButtonKind.primary,
                    onPressed: _pending || owner.error != null
                        ? null
                        : () => _run(_confirm),
                    child: const Text('Подготовить обновление'),
                  ),
                  DeckButton(
                    onPressed: _pending ? null : () => unawaited(owner.defer()),
                    child: const Text('Позже'),
                  ),
                ],
                if (snapshot.active)
                  DeckButton(
                    onPressed: _pending
                        ? null
                        : () => unawaited(owner.cancel()),
                    child: const Text('Отменить'),
                  ),
                if (owner.error != null)
                  DeckButton(
                    onPressed: _pending
                        ? null
                        : () => unawaited(owner.refresh()),
                    child: const Text('Повторить чтение состояния'),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
  DateTime? _date(int? seconds) {
    if (seconds == null || seconds > 8640000000000) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }
}
