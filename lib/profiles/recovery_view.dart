import 'package:flutter/material.dart';

import '../servers/server_compositions.dart';
import '../shell/error_view.dart';
import '../theme/motion.dart';
import '../ui/deck_components.dart';
import '../ui/deck_action_flow.dart';
import '../ui/deck_icon.dart';
import '../ui/deck_page.dart';
import '../ui/deck_table_controls.dart';
import '../theme/brand_tokens.dart';
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
                const ServerFactRows(
                  tableContext: true,
                  facts: {
                    'Область': 'Все окна рабочего пространства',
                    'Лимит': '20 последних подтверждённых записей',
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'Общие операции пространства, включая другие окна. До 20 последних подтверждённых записей. Отсутствие записи не доказывает исход потерянного запроса. Автоматический повтор не выполняется.',
                  style: BrandTypography.caption.copyWith(
                    color: deckColors(context)['muted'],
                    height: 20 / 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
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
            LayoutBuilder(
              builder: (context, bounds) => Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: bounds.maxWidth < 360 ? bounds.maxWidth : 360,
                    child: DeckSearchField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      hintText: 'Поиск по данным экрана',
                    ),
                  ),
                  DeckActionFlow(
                    children: [
                      DeckFilterChip(
                        label: 'Все ${recovery.receipts.length}',
                        active: query.isEmpty,
                        onPressed: () {
                          if (!mounted || !recovery.loaded) return;
                          _search.clear();
                          setState(() {});
                        },
                      ),
                      const DeckFilterChip(
                        label: 'Состояние',
                        icon: 'filter',
                        tooltip:
                            'История содержит только подтверждённые операции',
                      ),
                      const DeckFilterChip(
                        label: 'Теги',
                        trailing: 'chevron',
                        tooltip: 'История не содержит меток операций',
                      ),
                      DeckFilterChip(
                        label: _descending ? 'Сначала новые' : 'Сначала старые',
                        onPressed: () {
                          if (!mounted || !recovery.loaded) return;
                          setState(() => _descending = !_descending);
                        },
                      ),
                    ],
                  ),
                ],
              ),
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
            _historyTable(receipts),
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
          description: 'Просматривайте данные, состояние и доступные действия',
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
  Widget _operationCell(RecoveredCommit item) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        _operation(item.operation),
        style: BrandTypography.tableHeader.copyWith(
          fontSize: MediaQuery.sizeOf(context).width <= 520 ? 15 : 13,
          height: MediaQuery.sizeOf(context).width <= 520 ? 22 / 15 : 20 / 13,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'Ревизия пространства',
        style: BrandTypography.caption.copyWith(
          color: deckColors(context)['muted'],
        ),
      ),
      SelectableText(item.storeRevision, style: BrandTypography.log),
    ],
  );

  Widget _targetCell(RecoveredCommit item) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (item.profileId != null)
        SelectableText(item.profileId!, style: BrandTypography.log)
      else
        Text(
          item.operation == 'settings.update'
              ? 'Рабочее пространство'
              : 'Не предоставлено',
        ),
      SelectableText(item.requestId, style: BrandTypography.log),
    ],
  );

  List<Widget> _receiptCells(RecoveredCommit item) => [
    _operationCell(item),
    _targetCell(item),
    SelectableText(item.committedAt, style: BrandTypography.log),
    const DeckStatus(label: 'Подтверждено', tone: DeckTone.success),
  ];

  Widget _historyTable(List<RecoveredCommit> receipts) {
    final colors = deckColors(context);
    final phone = MediaQuery.sizeOf(context).width <= 520;
    const columns = ['Операция', 'Цель', 'Время UTC', 'Результат'];
    Widget row(List<Widget> cells, {bool header = false}) => DefaultTextStyle(
      style: BrandTypography.table.copyWith(color: colors['text']),
      child: Row(
        children: [
          for (final cell in cells)
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: header ? 10 : 12,
                ),
                child: cell,
              ),
            ),
        ],
      ),
    );
    return Container(
      decoration: phone
          ? null
          : BoxDecoration(
              color: colors['surface'],
              border: Border.all(color: colors['border']),
              borderRadius: BorderRadius.circular(12),
            ),
      clipBehavior: phone ? Clip.none : Clip.antiAlias,
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
          else if (phone)
            for (var i = 0; i < receipts.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _receiptCard(receipts[i]),
            ]
          else ...[
            Container(
              decoration: BoxDecoration(
                color: colors['raised'],
                border: Border(bottom: BorderSide(color: colors['border'])),
              ),
              child: row([
                for (final name in columns)
                  Text(
                    name,
                    style: BrandTypography.tableHeader.copyWith(
                      color: colors['muted'],
                    ),
                  ),
              ], header: true),
            ),
            for (var i = 0; i < receipts.length; i++)
              Container(
                key: RecentOperationReceiptKey(receipts[i].requestId),
                decoration: i == receipts.length - 1
                    ? null
                    : BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: colors['border']),
                        ),
                      ),
                child: row(_receiptCells(receipts[i])),
              ),
          ],
          Container(
            padding: EdgeInsets.fromLTRB(
              phone ? 0 : 16,
              phone ? 12 : 11,
              phone ? 0 : 16,
              phone ? 0 : 11,
            ),
            decoration: phone
                ? null
                : BoxDecoration(
                    border: Border(top: BorderSide(color: colors['border'])),
                  ),
            child: DefaultTextStyle(
              style: BrandTypography.caption.copyWith(color: colors['muted']),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text(
                    '${receipts.length} из ${recovery.receipts.length} подтверждённых записей · максимум 20',
                  ),
                  DeckActionFlow(
                    controlInset: 0,
                    spacing: 4,
                    children: const [
                      DeckPagerButton(reverse: true),
                      DeckPagerButton(page: 1, selected: true),
                      DeckPagerButton(),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _receiptCard(RecoveredCommit item) {
    final colors = deckColors(context);
    final cells = _receiptCells(item);
    const columns = ['Цель', 'Время UTC', 'Результат'];
    return Container(
      key: RecentOperationReceiptKey(item.requestId),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors['surface'],
        border: Border.all(color: colors['border']),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DefaultTextStyle(
        style: BrandTypography.table.copyWith(color: colors['text']),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors['border'])),
              ),
              child: cells.first,
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, bounds) => Wrap(
                spacing: 12,
                runSpacing: 14,
                children: [
                  for (var i = 0; i < columns.length; i++)
                    SizedBox(
                      width: (bounds.maxWidth - 12) / 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            columns[i],
                            style: BrandTypography.caption.copyWith(
                              color: colors['muted'],
                            ),
                          ),
                          const SizedBox(height: 4),
                          cells[i + 1],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _operation(String operation) => switch (operation) {
  'profiles.create' => 'Создание профиля подтверждено',
  'profiles.update' => 'Изменение профиля подтверждено',
  'profiles.delete' => 'Удаление профиля подтверждено',
  'settings.update' => 'Изменение настроек подтверждено',
  _ => 'Операция подтверждена',
};
