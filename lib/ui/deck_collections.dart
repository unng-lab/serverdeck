import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/brand_tokens.dart';
import '../theme/brand_theme.dart';
import 'deck_components.dart';

enum DeckDataState {
  data,
  loading,
  refreshing,
  empty,
  noResults,
  error,
  unavailable,
  stale,
  partial,
  unknown,
}

enum DeckSelection { none, single, multiple }

enum DeckCollectionLayout { adaptive, list }

enum DeckSortDirection { ascending, descending }

@immutable
class DeckSort {
  const DeckSort(this.column, this.direction);
  final String column;
  final DeckSortDirection direction;
}

@immutable
class DeckColumn<T> {
  const DeckColumn({
    required this.id,
    required this.label,
    required this.value,
    this.builder,
    this.numeric = false,
    this.sortable = false,
    this.minimumWidth = 120,
  }) : assert(minimumWidth > 0);

  final String id, label;
  final String? Function(T) value;
  final Widget Function(BuildContext, T)? builder;
  final bool numeric, sortable;
  final double minimumWidth;
}

/// Controlled collection. It renders a provided portion lazily; all queries,
/// sorting, paging, stable IDs, and selected IDs belong to the caller.
class DeckCollection<T> extends StatelessWidget {
  const DeckCollection({
    super.key,
    required this.rows,
    required this.idOf,
    required this.columns,
    this.state = DeckDataState.data,
    this.message,
    this.onRetry,
    this.onClearSearch,
    this.selection = DeckSelection.none,
    this.selectedIds = const {},
    this.onSelectionChanged,
    this.canSelect,
    this.sort,
    this.onSortChanged,
    this.actions,
    this.onOpen,
    this.maxBodyHeight = 480,
    this.header,
    this.layout = DeckCollectionLayout.adaptive,
    this.showColumnLabels = true,
  }) : assert(columns.length > 0),
       assert(maxBodyHeight > 0);

  final List<T> rows;
  final String Function(T) idOf;
  final List<DeckColumn<T>> columns;
  final DeckDataState state;
  final String? message;
  final VoidCallback? onRetry, onClearSearch;
  final DeckSelection selection;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>>? onSelectionChanged;
  final bool Function(T)? canSelect;
  final DeckSort? sort;
  final ValueChanged<DeckSort?>? onSortChanged;
  final List<Widget> Function(T)? actions;
  final ValueChanged<T>? onOpen;
  final double maxBodyHeight;
  final Widget? header;
  final DeckCollectionLayout layout;
  final bool showColumnLabels;

  void _toggle(T row, bool selected) {
    final id = idOf(row);
    if (canSelect?.call(row) == false) return;
    final next = selection == DeckSelection.single
        ? <String>{}
        : Set<String>.of(selectedIds);
    if (selected) {
      next.add(id);
    } else {
      next.remove(id);
    }
    onSelectionChanged?.call(Set.unmodifiable(next));
  }

  void _sort(DeckColumn<T> column) {
    final current = sort;
    onSortChanged?.call(
      current?.column != column.id
          ? DeckSort(column.id, DeckSortDirection.ascending)
          : current?.direction == DeckSortDirection.ascending
          ? DeckSort(column.id, DeckSortDirection.descending)
          : null,
    );
  }

  Widget _value(BuildContext context, T row, DeckColumn<T> column) =>
      column.builder?.call(context, row) ??
      Text(column.value(row) ?? 'Нет данных');

  @override
  Widget build(BuildContext context) {
    assert(rows.map(idOf).toSet().length == rows.length, 'Duplicate row ID');
    if ((rows.isEmpty && header == null) ||
        state == DeckDataState.unavailable) {
      return DeckCollectionState(
        state: state == DeckDataState.data ? DeckDataState.empty : state,
        message: message,
        onRetry: onRetry,
        onClearSearch: onClearSearch,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(13) / 13;
        final minimumWidth =
            columns.fold<double>(0, (v, c) => v + c.minimumWidth) * textScale +
            (selection == DeckSelection.none ? 0 : 56) +
            (onOpen == null && actions == null ? 0 : 100);
        final narrow =
            layout == DeckCollectionLayout.list ||
            constraints.maxWidth <= BrandGeometry.phoneBreakpoint ||
            constraints.maxWidth < minimumWidth;
        final notices = switch (state) {
          DeckDataState.loading || DeckDataState.refreshing =>
            'Обновляем данные; показан предыдущий снимок',
          DeckDataState.stale => 'Показаны устаревшие данные',
          DeckDataState.partial => 'Получена только часть данных',
          DeckDataState.unknown => 'Состояние данных неизвестно',
          DeckDataState.error =>
            'Обновление не удалось; показан предыдущий снимок',
          _ => null,
        };
        final headerHeight = narrow
            ? 0.0
            : _headerHeight(context, constraints.maxWidth);
        final desired =
            (rows.length + (header == null ? 0 : 1)) *
                (narrow ? 240.0 : 88.0) *
                textScale +
            headerHeight;
        final height = math.min(
          constraints.hasBoundedHeight
              ? math.min(maxBodyHeight, constraints.maxHeight)
              : maxBodyHeight,
          desired,
        );
        return SizedBox(
          height: height,
          child: CustomScrollView(
            slivers: [
              if (notices != null)
                SliverToBoxAdapter(
                  child: DeckNotice(
                    message: message ?? notices,
                    actions: [
                      if (state == DeckDataState.error && onRetry != null)
                        TextButton(
                          onPressed: onRetry,
                          child: const Text('Повторить чтение'),
                        ),
                    ],
                  ),
                ),
              if (narrow &&
                  (onSortChanged != null ||
                      selection == DeckSelection.multiple))
                SliverToBoxAdapter(
                  child: DeckActions(
                    children: [
                      if (selection == DeckSelection.multiple)
                        SizedBox(width: 56, child: _selectAll()),
                      if (onSortChanged != null)
                        for (final column in columns.where((c) => c.sortable))
                          TextButton(
                            onPressed: () => _sort(column),
                            child: Text(
                              'Сортировать: ${column.label}${sort?.column == column.id
                                  ? sort?.direction == DeckSortDirection.ascending
                                        ? ' ↑'
                                        : ' ↓'
                                  : ''}',
                            ),
                          ),
                    ],
                  ),
                ),
              if (!narrow)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _DeckHeaderDelegate(
                    height: headerHeight,
                    child: Material(
                      color: Theme.of(context)
                          .extension<BrandColors>()!['raised'],
                      child: _header(context),
                    ),
                  ),
                ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => header != null && index == 0
                      ? KeyedSubtree(
                          key: const ValueKey('deck-collection-header'),
                          child: header!,
                        )
                      : _row(
                          context,
                          rows[index - (header == null ? 0 : 1)],
                          narrow,
                        ),
                  childCount: rows.length + (header == null ? 0 : 1),
                  findChildIndexCallback: (key) {
                    if (header != null &&
                        key == const ValueKey('deck-collection-header'))
                      return 0;
                    final index = rows.indexWhere(
                      (row) => key == ValueKey('deck-row-${idOf(row)}'),
                    );
                    return index < 0 ? null : index + (header == null ? 0 : 1);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  double _headerHeight(BuildContext context, double width) {
    final usable = math.max(
      1.0,
      width -
          (selection == DeckSelection.none ? 0 : 56) -
          (onOpen == null && actions == null ? 0 : 100),
    );
    final total = columns.fold<double>(0, (v, c) => v + c.minimumWidth);
    var height = BrandGeometry.minTarget;
    for (final column in columns) {
      final painter = TextPainter(
        text: TextSpan(
          text: '${column.label} ↑',
          style: BrandTypography.button,
        ),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
      );
      painter.layout(
        maxWidth: math.max(1, usable * column.minimumWidth / total - 32),
      );
      height = math.max(height, painter.height + 24);
      painter.dispose();
    }
    return height;
  }

  Widget _selectAll() => Checkbox(
    semanticLabel: 'Выбрать отображаемую порцию',
    tristate: true,
    value: _allSelected,
    onChanged: onSelectionChanged == null
        ? null
        : (value) {
            final next = Set<String>.of(selectedIds);
            final ids = rows
                .where((r) => canSelect?.call(r) != false)
                .map(idOf);
            if (value == true) {
              next.addAll(ids);
            } else {
              next.removeAll(ids);
            }
            onSelectionChanged!(Set.unmodifiable(next));
          },
  );

  Widget _header(BuildContext context) => Row(
    children: [
      if (selection != DeckSelection.none)
        SizedBox(
          width: 56,
          child: selection == DeckSelection.multiple ? _selectAll() : null,
        ),
      for (final column in columns)
        Expanded(
          flex: column.minimumWidth.round(),
          child: column.sortable && onSortChanged != null
              ? TextButton(
                  onPressed: () => _sort(column),
                  child: Text(
                    '${column.label}${sort?.column == column.id
                        ? sort?.direction == DeckSortDirection.ascending
                              ? ' ↑'
                              : ' ↓'
                        : ''}',
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(column.label),
                ),
        ),
      if (actions != null || onOpen != null)
        const SizedBox(width: 100, child: Text('Действия')),
    ],
  );

  bool? get _allSelected {
    final ids = rows
        .where((r) => canSelect?.call(r) != false)
        .map(idOf)
        .toSet();
    final count = ids.intersection(selectedIds).length;
    return count == 0
        ? false
        : count == ids.length
        ? true
        : null;
  }

  Widget _row(BuildContext context, T row, bool narrow) {
    final id = idOf(row);
    final checkbox = selection == DeckSelection.none
        ? null
        : Checkbox(
            semanticLabel: 'Выбрать ${columns.first.value(row) ?? id}',
            value: selectedIds.contains(id),
            onChanged:
                onSelectionChanged == null || canSelect?.call(row) == false
                ? null
                : (value) => _toggle(row, value == true),
          );
    final rowActions = <Widget>[
      if (onOpen != null)
        TextButton(onPressed: () => onOpen!(row), child: const Text('Открыть')),
      ...?actions?.call(row),
    ];
    return Semantics(
      key: ValueKey('deck-row-$id'),
      selected: selectedIds.contains(id),
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selectedIds.contains(id)
              ? Theme.of(context).extension<BrandColors>()!['selected']
              : null,
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (checkbox != null)
                    Align(alignment: Alignment.centerLeft, child: checkbox),
                  for (final column in columns)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showColumnLabels)
                            Text(
                              column.label,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          _value(context, row, column),
                        ],
                      ),
                    ),
                  if (rowActions.isNotEmpty) DeckActions(children: rowActions),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (checkbox != null) SizedBox(width: 56, child: checkbox),
                  for (final column in columns)
                    Expanded(
                      flex: column.minimumWidth.round(),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Align(
                          alignment: column.numeric
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: _value(context, row, column),
                        ),
                      ),
                    ),
                  if (rowActions.isNotEmpty)
                    SizedBox(
                      width: 100,
                      child: DeckActions(children: rowActions),
                    ),
                ],
              ),
      ),
    );
  }
}

class DeckCollectionState extends StatelessWidget {
  const DeckCollectionState({
    super.key,
    required this.state,
    this.message,
    this.onRetry,
    this.onClearSearch,
  });
  final DeckDataState state;
  final String? message;
  final VoidCallback? onRetry, onClearSearch;
  @override
  Widget build(BuildContext context) {
    final loading =
        state == DeckDataState.loading || state == DeckDataState.refreshing;
    return DeckNotice(
      title: loading
          ? 'Получаем данные'
          : switch (state) {
              DeckDataState.noResults => 'Ничего не найдено',
              DeckDataState.error => 'Не удалось получить данные',
              DeckDataState.unavailable => 'Возможность недоступна',
              DeckDataState.stale => 'Данные устарели',
              DeckDataState.partial => 'Данные получены не полностью',
              DeckDataState.unknown => 'Состояние данных неизвестно',
              _ => 'Записей пока нет',
            },
      message:
          message ??
          (loading
              ? 'Первое наблюдение ещё не получено.'
              : 'Проверьте выбранный контекст.'),
      tone: state == DeckDataState.error ? DeckTone.error : DeckTone.neutral,
      actions: [
        if (state == DeckDataState.error && onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Повторить чтение')),
        if (state == DeckDataState.noResults && onClearSearch != null)
          TextButton(
            onPressed: onClearSearch,
            child: const Text('Очистить поиск'),
          ),
      ],
    );
  }
}

class DeckPagination extends StatelessWidget {
  const DeckPagination({
    super.key,
    required this.page,
    required this.hasMore,
    required this.onPageChanged,
    this.pending = false,
    this.enabled = true,
    this.total,
    this.pageSize = 25,
    this.pageSizes = const [25, 50, 100],
    this.onPageSizeChanged,
  });
  final int page, pageSize;
  final int? total;
  final bool hasMore, pending, enabled;
  final ValueChanged<int> onPageChanged;
  final List<int> pageSizes;
  final ValueChanged<int>? onPageSizeChanged;
  @override
  Widget build(BuildContext context) => DeckActions(
    children: [
      OutlinedButton(
        onPressed: !enabled || pending || page == 0
            ? null
            : () => onPageChanged(page - 1),
        child: const Text('Назад'),
      ),
      Text(
        'Страница ${page + 1} · ${total == null ? 'Всего неизвестно' : '$total записей'}',
      ),
      OutlinedButton(
        onPressed: !enabled || pending || !hasMore
            ? null
            : () => onPageChanged(page + 1),
        child: const Text('Далее'),
      ),
      if (onPageSizeChanged != null)
        SizedBox(
          width: 240,
          child: DropdownButton<int>(
            isExpanded: true,
            value: pageSize,
            items: pageSizes
                .map(
                  (n) => DropdownMenuItem(value: n, child: Text('$n записей')),
                )
                .toList(),
            onChanged: !enabled || pending
                ? null
                : (value) {
                    if (value != null) {
                      onPageSizeChanged!(value);
                      onPageChanged(0);
                    }
                  },
          ),
        ),
    ],
  );
}

class DeckSelectionBar extends StatelessWidget {
  const DeckSelectionBar({
    super.key,
    required this.count,
    required this.onClear,
    this.actions = const [],
  });
  final int count;
  final VoidCallback? onClear;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => DeckActions(
    children: [
      Text('Выбрано: $count'),
      ...actions,
      TextButton(onPressed: onClear, child: const Text('Очистить выбор')),
    ],
  );
}

class _DeckHeaderDelegate extends SliverPersistentHeaderDelegate {
  _DeckHeaderDelegate({required this.height, required this.child});
  final double height;
  final Widget child;
  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => SizedBox.expand(child: child);
  @override
  bool shouldRebuild(covariant _DeckHeaderDelegate oldDelegate) =>
      oldDelegate.height != height || oldDelegate.child != child;
}
