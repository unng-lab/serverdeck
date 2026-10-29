import 'package:flutter/material.dart';

import '../shell/error_view.dart';
import '../theme/motion.dart';
import '../ui/deck_components.dart';
import '../ui/deck_icon.dart';
import '../ui/deck_page.dart';
import '../ui/deck_table_controls.dart';
import '../theme/brand_tokens.dart';
import '../theme/brand_assets.dart';
import '../theme/brand_theme.dart';
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
  const RecentOperationsButton({
    super.key,
    required this.recovery,
    this.onOpen,
  });
  final StartupRecovery recovery;
  final VoidCallback? onOpen;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: recovery,
    builder: (context, _) => recovery.loaded
        ? IconButton(
            tooltip: 'Недавние подтверждённые операции',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const DeckIcon('clock'),
            onPressed:
                onOpen ??
                () => showMotionDialog<void>(
                  context: context,
                  builder: (_) => RecentOperationsView(recovery: recovery),
                ),
          )
        : const SizedBox.shrink(),
  );
}

/// The same history composition is used by ordinary navigation and its dialog.
class RecentOperationsView extends StatefulWidget {
  const RecentOperationsView({
    super.key,
    required this.recovery,
    this.asPage = false,
    this.onClose,
  });
  final StartupRecovery recovery;
  final bool asPage;
  final VoidCallback? onClose;
  @override
  State<RecentOperationsView> createState() => _RecentOperationsViewState();
}

class _RecentOperationsViewState extends State<RecentOperationsView> {
  bool _readingError = false, _descending = true;
  final _search = TextEditingController();
  StartupRecovery get recovery => widget.recovery;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _close() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _readAgain() async {
    if (_readingError || recovery.busy) return;
    final owner = recovery;
    setState(() => _readingError = true);
    try {
      await owner.reload();
    } finally {
      if (mounted && identical(recovery, owner))
        setState(() => _readingError = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: recovery,
    builder: (context, _) {
      final actions = <Widget>[
        OutlinedButton(
          clipBehavior: Clip.none,
          onPressed: !recovery.loaded || recovery.busy || _readingError
              ? null
              : () {
                  if (recovery.loaded) _readAgain().ignore();
                },
          child: const DeckButtonLabel(
            icon: 'refresh',
            label: 'Обновить список',
          ),
        ),
        OutlinedButton(
          clipBehavior: Clip.none,
          onPressed: _close,
          child: const Text('Закрыть'),
        ),
      ];
      final query = _search.text.trim().toLowerCase();
      final receipts =
          recovery.receipts
              .where(
                (item) => [
                  item.requestId,
                  item.operation,
                  item.profileId ?? '',
                  item.committedAt,
                  item.storeRevision,
                ].any((value) => value.toLowerCase().contains(query)),
              )
              .toList()
            ..sort(
              (a, b) =>
                  (_descending ? -1 : 1) *
                  a.committedAt.compareTo(b.committedAt),
            );
      final body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DeckPanel(
            title: 'Область просмотра',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const DeckKeyValue(
                  label: 'Источник',
                  value: 'Локальная история подтверждённых операций',
                ),
                Text(
                  'Общие операции пространства, включая другие окна. До 20 последних подтверждённых записей. Отсутствие записи не доказывает исход потерянного запроса. Автоматический повтор не выполняется.',
                  style: BrandTypography.body,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
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
                pending: true,
                tone: DeckTone.running,
              )
          else ...[
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 360,
                  child: DeckSearchField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    hintText: 'Поиск по данным экрана',
                  ),
                ),
                OutlinedButton(
                  clipBehavior: Clip.none,
                  onPressed: () => setState(() => _descending = !_descending),
                  child: Text(_descending ? 'Сначала новые' : 'Сначала старые'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_readingError)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: DeckStatus(
                  label: 'Проверка текущих данных и недавних операций',
                  pending: true,
                  tone: DeckTone.running,
                ),
              ),
            DeckPanel(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (receipts.isEmpty)
                    DeckEmptyState(
                      title: recovery.receipts.isEmpty
                          ? 'Подтверждённых записей в выборке нет'
                          : 'Операции не найдены',
                      description: recovery.receipts.isEmpty
                          ? 'Здесь появятся недавние подтверждённые локальные операции.'
                          : 'Измените поисковый запрос.',
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final compact =
                            constraints.maxWidth < 680 ||
                            MediaQuery.textScalerOf(context).scale(14) >= 22;
                        if (compact)
                          return Column(
                            children: [
                              for (final item in receipts) _receiptCard(item),
                            ],
                          );
                        const widths = {
                          0: FlexColumnWidth(2),
                          1: FlexColumnWidth(2),
                          2: FlexColumnWidth(),
                          3: FlexColumnWidth(2),
                        };
                        return Column(
                          children: [
                            Table(
                              columnWidths: widths,
                              children: [
                                TableRow(
                                  decoration: BoxDecoration(
                                    color: deckColors(context)['raised'],
                                  ),
                                  children: [
                                    for (final name in [
                                      'Операция',
                                      'Цель / запрос',
                                      'Ревизия',
                                      'Подтверждено, UTC',
                                    ])
                                      _cell(
                                        Text(
                                          name,
                                          style: BrandTypography.table.copyWith(
                                            fontFamily:
                                                BrandAssets.semiboldFamily,
                                            fontWeight:
                                                BrandTypography.semiboldWeight,
                                            fontVariations: BrandTypography
                                                .semiboldVariations,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            for (final item in receipts)
                              Container(
                                key: RecentOperationReceiptKey(item.requestId),
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(
                                      color: deckColors(context)['border'],
                                    ),
                                  ),
                                ),
                                child: Table(
                                  columnWidths: widths,
                                  children: [
                                    TableRow(
                                      children: [
                                        _cell(
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(_operation(item.operation)),
                                              const SizedBox(height: 6),
                                              const DeckStatus(
                                                label: 'Подтверждено',
                                                tone: DeckTone.success,
                                              ),
                                            ],
                                          ),
                                        ),
                                        _cell(
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (item.profileId != null)
                                                SelectableText(item.profileId!),
                                              SelectableText(item.requestId),
                                            ],
                                          ),
                                        ),
                                        _cell(
                                          SelectableText(item.storeRevision),
                                        ),
                                        _cell(SelectableText(item.committedAt)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: deckColors(context)['border']),
                      ),
                    ),
                    child: Text(
                      '${receipts.length} из ${recovery.receipts.length} подтверждённых записей · максимум 20',
                    ),
                  ),
                ],
              ),
            ),
            if (recovery.truncated)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: DeckStatus(
                  label: 'Показана часть сохранённых записей',
                  tone: DeckTone.warning,
                ),
              ),
          ],
        ],
      );
      if (widget.asPage)
        return DeckPage(
          title: 'Недавние подтверждённые операции',
          eyebrow: 'Задания / РАБОЧЕЕ ПРОСТРАНСТВО',
          description: 'Подтверждённые изменения локального пространства.',
          actions: actions,
          child: body,
        );
      return DeckDialogLayout(
        title: 'Недавние подтверждённые операции',
        maxWidth: 960,
        actions: actions,
        child: body,
      );
    },
  );
  Widget _cell(Widget child) =>
      Padding(padding: const EdgeInsets.all(12), child: child);
  Widget _receiptCard(RecoveredCommit item) => Container(
    key: RecentOperationReceiptKey(item.requestId),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: deckColors(context)['border'])),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DeckStatus(label: _operation(item.operation), tone: DeckTone.success),
        const SizedBox(height: 12),
        DeckKeyValue(label: 'Запрос', value: item.requestId, selectable: true),
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
  );
}

String _operation(String operation) => switch (operation) {
  'profiles.create' => 'Создание профиля подтверждено',
  'profiles.update' => 'Изменение профиля подтверждено',
  'profiles.delete' => 'Удаление профиля подтверждено',
  'settings.update' => 'Изменение настроек подтверждено',
  _ => 'Операция подтверждена',
};
