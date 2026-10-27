import 'package:flutter/material.dart';

import '../shell/error_view.dart';
import '../ui/deck_components.dart';
import 'mutation_controller.dart';

class MutationStatus extends StatelessWidget {
  const MutationStatus({
    super.key,
    required this.controller,
    required this.onReload,
    this.deleting = false,
    this.settings = false,
    this.reloading = false,
    this.readPending = false,
    this.onReadCommitted,
  });
  final MutationController controller;
  final VoidCallback onReload;
  final bool deleting;
  final bool settings;
  final bool reloading;
  final bool readPending;
  final VoidCallback? onReadCommitted;
  @override
  Widget build(BuildContext context) {
    if (reloading) {
      return DeckStatus(
        label: settings
            ? 'Чтение актуальных настроек'
            : 'Чтение актуального профиля',
        pending: true,
      );
    }
    final state = controller.state;
    if (state == MutationPresentation.idle) return const SizedBox.shrink();
    final label = switch (state) {
      MutationPresentation.submitting => deleting ? 'Удаление' : 'Сохранение',
      MutationPresentation.unknown =>
        deleting ? 'Удаление не подтверждено' : 'Сохранение не подтверждено',
      MutationPresentation.waiting => 'Операция ещё выполняется',
      MutationPresentation.retryAllowed =>
        'Запрос не найден; можно повторить тот же запрос',
      MutationPresentation.committed =>
        deleting
            ? 'Удаление выполнено; ожидается чтение актуального состояния'
            : 'Сохранено; ожидается чтение актуального состояния',
      MutationPresentation.succeeded => deleting ? 'Удалено' : 'Сохранено',
      MutationPresentation.conflict =>
        settings
            ? 'Настройки изменены другим окном. Введённые данные сохранены в форме'
            : deleting
            ? 'Профиль изменён другим окном. Перечитайте его перед удалением'
            : 'Профиль изменён другим окном. Введённые данные сохранены в форме',
      MutationPresentation.failed =>
        deleting ? 'Удаление отклонено' : 'Сохранение отклонено',
      MutationPresentation.idle => '',
    };
    final tone = switch (state) {
      MutationPresentation.submitting ||
      MutationPresentation.waiting => DeckTone.running,
      MutationPresentation.unknown ||
      MutationPresentation.retryAllowed => DeckTone.unknown,
      MutationPresentation.conflict => DeckTone.warning,
      MutationPresentation.failed => DeckTone.error,
      MutationPresentation.committed ||
      MutationPresentation.succeeded => DeckTone.success,
      MutationPresentation.idle => DeckTone.neutral,
    };
    final detail = switch (state) {
      MutationPresentation.submitting => 'Запрос отправлен. Повторная отправка недоступна, пока ожидается результат.',
      MutationPresentation.unknown => 'Потерянный ответ не доказывает, что запись не выполнена. Автоматического повтора нет.',
      MutationPresentation.waiting => 'Окончательный результат ещё не получен. Проверка результата не отправляет запись повторно.',
      MutationPresentation.retryAllowed =>
        'Повтор доступен только для исходного запроса с теми же данными.',
      MutationPresentation.committed => 'Запись подтверждена. Для завершения нужно получить актуальное состояние локального пространства.',
      MutationPresentation.succeeded =>
        'Запись подтверждена, актуальное состояние прочитано.',
      MutationPresentation.conflict =>
        'Перечитайте актуальные данные перед новым подтверждением изменения.',
      MutationPresentation.failed => 'Локальная служба отклонила изменение. Проверьте причину перед новым действием.',
      MutationPresentation.idle => '',
    };
    return Semantics(
      liveRegion: true,
      child: DeckNotice(
        title: label,
        message: controller.error == null
            ? detail
            : ReadErrorView.category(controller.error!),
        nextStep: controller.busy && state != MutationPresentation.submitting
            ? 'Ожидаем ответ текущей проверки; повторные действия недоступны.'
            : controller.error == null
            ? null
            : detail,
        tone: tone,
        actions: [
          if (!controller.busy) ...[
            if ({
              MutationPresentation.unknown,
              MutationPresentation.waiting,
              MutationPresentation.retryAllowed,
            }.contains(state))
              _action(
                'Проверить результат',
                () => controller.checkResult().ignore(),
              ),
            if (state == MutationPresentation.retryAllowed)
              _action(
                'Повторить тот же запрос',
                () => controller.retry().ignore(),
              ),
            if (state == MutationPresentation.committed)
              _action(
                'Перечитать состояние',
                readPending
                    ? null
                    : onReadCommitted ??
                          () => controller.refreshCommitted().ignore(),
              ),
            if (state == MutationPresentation.conflict)
              _action(
                settings ? 'Перечитать настройки' : 'Перечитать профиль',
                readPending ? null : onReload,
              ),
            if (state == MutationPresentation.failed)
              _action(
                deleting ? 'Вернуться к подтверждению' : 'Исправить ввод',
                controller.reset,
              ),
          ],
        ],
      ),
    );
  }

  static Widget _action(String label, VoidCallback? action) => OutlinedButton(
    style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
    onPressed: action,
    child: Text(label),
  );
}
