import 'package:flutter/material.dart';

import '../shell/error_view.dart';
import '../theme/motion.dart';
import '../theme/brand_tokens.dart';
import '../ui/deck_components.dart';
import 'startup_recovery.dart';

/// Identifies a confirmed history entry by its original request identity.
class RecentOperationReceiptKey extends ValueKey<String> {
  const RecentOperationReceiptKey(super.value);
}

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
          child: SingleChildScrollView(
            padding: EdgeInsets.all(BrandSpacing.space24),
            child: DeckStatus(
              label: 'Проверка текущих данных и недавних операций',
              tone: DeckTone.running,
            ),
          ),
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
            icon: const Icon(Icons.history, size: BrandGeometry.iconSize),
            onPressed: () => showMotionDialog<void>(
              context: context,
              builder: (_) => _History(recovery: recovery),
            ),
          )
        : const SizedBox.shrink(),
  );
}

class _History extends StatefulWidget {
  const _History({required this.recovery});
  final StartupRecovery recovery;
  @override
  State<_History> createState() => _HistoryState();
}

class _HistoryState extends State<_History> {
  bool _readingError = false;
  StartupRecovery get recovery => widget.recovery;

  Future<void> _readAgain() async {
    if (_readingError || recovery.busy) return;
    final owner = recovery;
    setState(() => _readingError = true);
    try {
      await owner.reload();
    } finally {
      if (mounted && identical(recovery, owner)) {
        setState(() => _readingError = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: recovery,
    builder: (context, _) => DeckDialogLayout(
      title: 'Недавние подтверждённые операции',
      actions: [
        if (recovery.loaded)
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: recovery.busy || _readingError
                ? null
                : () => _readAgain().ignore(),
            child: const Text('Обновить список'),
          ),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!recovery.loaded)
            if (recovery.error ?? recovery.model.error case final code?)
              ReadErrorView(
                code: code,
                reading: _readingError,
                pendingLabel: 'Проверка текущих данных и недавних операций',
                onReadAgain: () => _readAgain().ignore(),
                onCheckService: () => recovery.model.bootstrap.retry().ignore(),
              )
            else
              const DeckStatus(
                label: 'Проверка текущих данных и недавних операций',
                tone: DeckTone.running,
                pending: true,
              )
          else ...[
            if (_readingError)
              const Padding(
                padding: EdgeInsets.only(bottom: BrandSpacing.space16),
                child: DeckStatus(
                  label: 'Проверка текущих данных и недавних операций',
                  tone: DeckTone.running,
                  pending: true,
                ),
              ),
            const Text(
              'Общие операции пространства, включая другие окна. До 20 последних подтверждённых записей. Отсутствие записи не доказывает исход потерянного запроса. Автоматический повтор не выполняется.',
            ),
            if (recovery.receipts.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: BrandSpacing.space16),
                child: DeckNotice(
                  message: 'Подтверждённых записей в выборке нет',
                  tone: DeckTone.neutral,
                ),
              ),
            if (recovery.truncated)
              const Padding(
                padding: EdgeInsets.only(top: BrandSpacing.space16),
                child: DeckStatus(
                  label: 'Показана часть сохранённых записей',
                  tone: DeckTone.warning,
                ),
              ),
            for (final item in recovery.receipts)
              Padding(
                padding: const EdgeInsets.only(top: BrandSpacing.space12),
                child: DeckSurface(
                  key: RecentOperationReceiptKey(item.requestId),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DeckStatus(
                        tone: DeckTone.success,
                        label: switch (item.operation) {
                          'profiles.create' => 'Создание профиля подтверждено',
                          'profiles.update' => 'Изменение профиля подтверждено',
                          'profiles.delete' => 'Удаление профиля подтверждено',
                          'settings.update' =>
                            'Изменение настроек подтверждено',
                          _ => 'Операция подтверждена',
                        },
                      ),
                      const SizedBox(height: BrandSpacing.space8),
                      DeckKeyValue(
                        label: 'Запрос',
                        value: item.requestId,
                        selectable: true,
                      ),
                      if (item.profileId != null)
                        DeckKeyValue(
                          label: 'ID профиля',
                          value: item.profileId!,
                          selectable: true,
                        ),
                      DeckKeyValue(
                        label: 'Ревизия пространства',
                        value: item.storeRevision,
                        selectable: true,
                      ),
                      DeckKeyValue(
                        label: 'Время подтверждения UTC',
                        value: item.committedAt,
                        selectable: true,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    ),
  );
}
