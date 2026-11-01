import 'package:flutter/material.dart';
import 'package:serverdeck/ui/deck_components.dart';

@immutable
class CatalogJob {
  const CatalogJob(
    this.id,
    this.title,
    this.target,
    this.phase, {
    this.selectable = true,
  });
  final String id, title, phase;
  final String? target;
  final bool selectable;
}

const catalogJobs = [
  CatalogJob('job-check-1', 'Проверка', 'atlas-web', 'Завершено'),
  CatalogJob('job-check-2', 'Проверка', 'atlas-db', 'Выполняется'),
  CatalogJob(
    'job-blocked',
    'Изменение доступа',
    null,
    'Заблокировано',
    selectable: false,
  ),
];

/// Local job owner, deliberately independent of the server fixture and its IDs.
class JobCollectionExample extends StatefulWidget {
  const JobCollectionExample({
    super.key,
    this.disabled = false,
    this.pending = false,
    this.state = DeckDataState.data,
    this.initialSelected = false,
  });
  final bool disabled, pending;
  final DeckDataState state;
  final bool initialSelected;
  @override
  State<JobCollectionExample> createState() => _JobCollectionExampleState();
}

class _JobCollectionExampleState extends State<JobCollectionExample> {
  final search = TextEditingController();
  final jobs = List<CatalogJob>.of(catalogJobs);
  Set<String> selected = {};
  DeckSort? sort;
  String? lastAction;
  @override
  void initState() {
    super.initState();
    _configure();
  }

  @override
  void didUpdateWidget(covariant JobCollectionExample oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state ||
        oldWidget.initialSelected != widget.initialSelected)
      _configure();
  }

  void _configure() {
    if (widget.state == DeckDataState.noResults)
      search.text = 'нет совпадений';
    else if (search.text == 'нет совпадений')
      search.clear();
    if (widget.initialSelected) selected = {'job-check-1'};
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  List<CatalogJob> get visible {
    final indexed = jobs
        .asMap()
        .entries
        .where(
          (entry) => '${entry.value.title} ${entry.value.target ?? ''}'
              .toLowerCase()
              .contains(search.text.toLowerCase()),
        )
        .toList();
    if (sort != null)
      indexed.sort((a, b) {
        final x = sort!.column == 'title' ? a.value.title : a.value.target;
        final y = sort!.column == 'title' ? b.value.title : b.value.target;
        if (x == null) return y == null ? a.key.compareTo(b.key) : 1;
        if (y == null) return -1;
        final comparison = x.toLowerCase().compareTo(y.toLowerCase());
        if (comparison == 0) return a.key.compareTo(b.key);
        return sort!.direction == DeckSortDirection.ascending
            ? comparison
            : -comparison;
      });
    return indexed.map((e) => e.value).toList();
  }

  void remove(CatalogJob row) => setState(() {
    jobs.removeWhere((r) => r.id == row.id);
    selected = {...selected}..remove(row.id);
    lastAction = 'Удалён из примера: ${row.id}';
  });
  @override
  Widget build(BuildContext context) {
    final rows = widget.state == DeckDataState.empty
        ? const <CatalogJob>[]
        : visible;
    final state = rows.isEmpty && search.text.isNotEmpty
        ? DeckDataState.noResults
        : widget.state == DeckDataState.noResults
        ? DeckDataState.data
        : widget.state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DeckSearch(
          enabled: !widget.disabled && !widget.pending,
          controller: search,
          label: 'Поиск задания или цели',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        DeckSelectionBar(
          count: selected.length,
          onClear: widget.disabled || widget.pending
              ? null
              : () => setState(() => selected = {}),
          actions: [
            DeckButton(
              onPressed: selected.isEmpty || widget.disabled
                  ? null
                  : () => setState(
                      () => lastAction =
                          'Проверка выбранных: ${selected.join(', ')}',
                    ),
              child: const Text('Проверить выбранные задания'),
            ),
          ],
        ),
        DeckCollection<CatalogJob>(
          rows: rows,
          idOf: (r) => r.id,
          state: state,
          selection: DeckSelection.multiple,
          canSelect: (r) => r.selectable,
          selectedIds: selected,
          onSelectionChanged: widget.disabled || widget.pending
              ? null
              : (ids) => setState(() => selected = ids),
          sort: sort,
          onSortChanged: widget.disabled || widget.pending
              ? null
              : (value) => setState(() => sort = value),
          columns: [
            DeckColumn(
              id: 'title',
              label: 'Задание',
              value: (r) => r.title,
              sortable: true,
            ),
            DeckColumn(
              id: 'target',
              label: 'Цель',
              value: (r) => r.target,
              sortable: true,
            ),
            DeckColumn(
              id: 'phase',
              label: 'Состояние',
              value: (r) => r.phase,
              builder: (context, r) => DeckStatus(
                label: r.phase,
                tone: r.selectable ? DeckTone.neutral : DeckTone.unavailable,
              ),
            ),
          ],
          onOpen: widget.disabled
              ? null
              : (r) => setState(() => lastAction = 'Детали задания: ${r.id}'),
          actions: (r) => [
            TextButton(
              onPressed: widget.disabled || !r.selectable
                  ? null
                  : () => remove(r),
              child: const Text('Удалить из примера'),
            ),
          ],
          onClearSearch: () {
            search.clear();
            setState(() {});
          },
        ),
        if (lastAction != null) Text(lastAction!),
      ],
    );
  }
}
