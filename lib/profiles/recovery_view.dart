import 'package:flutter/material.dart';

import '../shell/error_view.dart';
import '../theme/motion.dart';
import 'startup_recovery.dart';

class RecoveryView extends StatelessWidget {
  const RecoveryView({super.key, required this.recovery, required this.child});
  final StartupRecovery recovery;
  final Widget child;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: recovery,
    builder: (context, _) {
      if (!recovery.model.loaded) return child;
      if (recovery.error case final code?)
        return ReadErrorView(
          code: code,
          onReadAgain: () => recovery.reload().ignore(),
          onCheckService: () => recovery.model.bootstrap.retry().ignore(),
        );
      if (!recovery.loaded)
        return const Center(
          child: Text('Проверка текущих данных и недавних операций'),
        );
      return child;
    },
  );
}

class RecentOperationsButton extends StatelessWidget {
  const RecentOperationsButton({super.key, required this.recovery});
  final StartupRecovery recovery;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: recovery,
    builder: (context, _) => recovery.loaded
        ? IconButton(
            tooltip: 'Недавние подтверждённые операции',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.history),
            onPressed: () => showMotionDialog<void>(
              context: context,
              builder: (_) => _History(recovery: recovery),
            ),
          )
        : const SizedBox.shrink(),
  );
}

class _History extends StatelessWidget {
  const _History({required this.recovery});
  final StartupRecovery recovery;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: recovery,
    builder: (context, _) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Недавние подтверждённые операции'),
              if (!recovery.loaded)
                const Text('Данные недоступны; проверьте локальную службу')
              else ...[
                const Text(
                  'Общие операции пространства, включая другие окна. До 20 последних подтверждённых записей. Отсутствие записи не доказывает исход потерянного запроса. Автоматический повтор не выполняется.',
                ),
                if (recovery.receipts.isEmpty)
                  const Text('Подтверждённых записей в выборке нет'),
                if (recovery.truncated)
                  const Text('Показана часть сохранённых записей'),
                for (final item in recovery.receipts)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(switch (item.operation) {
                            'profiles.create' =>
                              'Создание профиля подтверждено',
                            'profiles.update' =>
                              'Изменение профиля подтверждено',
                            'profiles.delete' =>
                              'Удаление профиля подтверждено',
                            'settings.update' =>
                              'Изменение настроек подтверждено',
                            _ => 'Операция подтверждена',
                          }),
                          Text('Запрос: ${item.requestId}'),
                          if (item.profileId != null)
                            Text('ID профиля: ${item.profileId}'),
                          Text('Ревизия пространства: ${item.storeRevision}'),
                          Text('Время подтверждения UTC: ${item.committedAt}'),
                        ],
                      ),
                    ),
                  ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: recovery.busy
                      ? null
                      : () => recovery.reload().ignore(),
                  child: const Text('Обновить список'),
                ),
              ],
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Закрыть'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
