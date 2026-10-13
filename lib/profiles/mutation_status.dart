import 'package:flutter/material.dart';

import '../shell/error_view.dart';
import 'mutation_controller.dart';

class MutationStatus extends StatelessWidget {
  const MutationStatus({
    super.key,
    required this.controller,
    required this.onReload,
    this.deleting = false,
    this.settings = false,
  });
  final MutationController controller;
  final VoidCallback onReload;
  final bool deleting;
  final bool settings;
  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    if (state == MutationPresentation.idle) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(switch (state) {
            MutationPresentation.submitting =>
              deleting ? 'Удаление' : 'Сохранение',
            MutationPresentation.unknown =>
              deleting
                  ? 'Удаление не подтверждено'
                  : 'Сохранение не подтверждено',
            MutationPresentation.waiting => 'Операция ещё выполняется',
            MutationPresentation.retryAllowed =>
              'Запрос не найден; можно повторить тот же запрос',
            MutationPresentation.committed =>
              deleting
                  ? 'Удаление выполнено; ожидается чтение актуального состояния'
                  : 'Сохранено; ожидается чтение актуального состояния',
            MutationPresentation.succeeded =>
              deleting ? 'Удалено' : 'Сохранено',
            MutationPresentation.conflict =>
              settings
                  ? 'Настройки изменены другим окном. Введённые данные сохранены в форме'
                  : deleting
                  ? 'Профиль изменён другим окном. Перечитайте его перед удалением'
                  : 'Профиль изменён другим окном. Введённые данные сохранены в форме',
            MutationPresentation.failed =>
              deleting ? 'Удаление отклонено' : 'Сохранение отклонено',
            MutationPresentation.idle => '',
          }),
          if (controller.error case final code?)
            Text(ReadErrorView.category(code)),
          if (!controller.busy)
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
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
                    () => controller.refreshCommitted().ignore(),
                  ),
                if (state == MutationPresentation.conflict)
                  _action(
                    settings ? 'Перечитать настройки' : 'Перечитать профиль',
                    onReload,
                  ),
                if (state == MutationPresentation.failed)
                  _action(
                    deleting ? 'Вернуться к подтверждению' : 'Исправить ввод',
                    controller.reset,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  static Widget _action(String label, VoidCallback action) => OutlinedButton(
    style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
    onPressed: action,
    child: Text(label),
  );
}
