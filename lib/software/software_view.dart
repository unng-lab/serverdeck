import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/actor.dart';
import '../domain/models.dart';
import '../domain/error_presentation.dart';
import '../ui/deck_components.dart';
import 'software_models.dart';
import 'software_owner.dart';
import 'software_analysis.dart';

/// C02/C03/C04/C05/C06/C07/C08/C09/C10/C11/C12/C13/C16/C18/C19/C20/C28.
/// Shell navigation delegates to the existing C26 owner; no commands are generated.
class SoftwareView extends StatefulWidget {
  const SoftwareView({
    super.key,
    required this.owner,
    required this.actor,
    required this.profile,
    required this.newId,
    this.onConsole,
    this.copyText,
  });
  final SoftwareOwner owner;
  final UiActor actor;
  final ProfileView profile;
  final String Function() newId;
  final VoidCallback? onConsole;
  final Future<void> Function(String)? copyText;
  @override
  State<SoftwareView> createState() => _SoftwareViewState();
}

class _SoftwareViewState extends State<SoftwareView> {
  final _search = TextEditingController(),
      _request = TextEditingController(),
      _summary = TextEditingController();
  final _fields = {
    for (final key in [
      'name',
      'version',
      'service',
      'dataPaths',
      'configPaths',
    ])
      key: TextEditingController(),
  };
  SoftwarePage? _cards, _history;
  OperationFailure? _loadError, _actionError;
  final _cardCursors = <String?>[null], _historyCursors = <String?>[null];
  String? _selectedSoftwareId;
  final _expandedEvents = <String>{};
  int _cardPage = 0, _historyPage = 0, _epoch = 0, _loadId = 0;
  String _query = '', _action = 'other', _outcome = 'unknown';
  String? _editing,
      _historySoftwareId,
      _historyName,
      _cardMutationId,
      _noteMutationId;
  int? _expectedRevision;
  bool _loading = true,
      _pending = false,
      _form = false,
      _note = false,
      _analysis = false,
      _copied = false,
      _editConflict = false;
  @override
  void initState() {
    super.initState();
    widget.owner.addListener(_changed);
    unawaited(_load());
  }

  void _changed() {
    if (mounted) unawaited(_load(reset: true));
  }

  bool _current(int epoch) => mounted && epoch == _epoch;
  @override
  void didUpdateWidget(covariant SoftwareView old) {
    super.didUpdateWidget(old);
    if (old.owner != widget.owner ||
        old.profile.profileId != widget.profile.profileId ||
        old.profile.endpointId != widget.profile.endpointId) {
      old.owner.removeListener(_changed);
      widget.owner.addListener(_changed);
      _epoch++;
      _form = false;
      _note = false;
      _analysis = false;
      _pending = false;
      _editing = null;
      _historySoftwareId = null;
      _historyName = null;
      _cardMutationId = null;
      _noteMutationId = null;
      _cards = null;
      _history = null;
      _resetExpansion();
      _resetEventExpansion();
      _actionError = null;
      _query = '';
      _search.clear();
      _request.clear();
      _summary.clear();
      for (final c in _fields.values) {
        c.clear();
      }
      unawaited(_load(reset: true));
    }
  }

  @override
  void dispose() {
    _epoch++;
    widget.owner.removeListener(_changed);
    _search.dispose();
    _request.dispose();
    _summary.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      if (_cardPage != 0) _resetExpansion();
      if (_historyPage != 0) _resetEventExpansion();
      _cardPage = 0;
      _historyPage = 0;
      _cardCursors
        ..clear()
        ..add(null);
      _historyCursors
        ..clear()
        ..add(null);
    }
    final epoch = _epoch,
        load = ++_loadId,
        owner = widget.owner,
        profile = widget.profile.profileId,
        actor = widget.actor;
    final cardCursor = _cardCursors[_cardPage],
        historyCursor = _historyCursors[_historyPage],
        filter = _historySoftwareId;
    if (mounted) setState(() => _loading = true);
    final values = await Future.wait([
      owner.list(actor, profile, cursor: cardCursor),
      owner.history(actor, profile, softwareId: filter, cursor: historyCursor),
    ]);
    if (!_current(epoch) || load != _loadId) return;
    setState(() {
      _loading = false;
      _loadError = values[0].error ?? values[1].error;
      if (values[0].ok) {
        _cards = values[0].value!.software as SoftwarePage;
        final ids = _cards!.items
            .whereType<SoftwareCardView>()
            .map((card) => card.softwareId)
            .toSet();
        if (!ids.contains(_selectedSoftwareId)) _selectedSoftwareId = null;
      }
      if (values[1].ok) {
        _history = values[1].value!.software as SoftwarePage;
        final ids = _history!.items
            .whereType<SoftwareEventView>()
            .map((event) => event.eventId)
            .toSet();
        _expandedEvents.removeWhere((id) => !ids.contains(id));
      }
    });
  }

  void _start(SoftwareCardView? card) {
    setState(() {
      _form = true;
      _editConflict = false;
      _actionError = null;
      _cardMutationId = null;
      _editing = card?.softwareId;
      _expectedRevision = card?.revision;
      final input = card?.card;
      _fields['name']!.text = input?.name ?? '';
      _fields['version']!.text = input?.version ?? '';
      _fields['service']!.text = input?.service ?? '';
      _fields['dataPaths']!.text = input?.dataPaths.join('\n') ?? '';
      _fields['configPaths']!.text = input?.configPaths.join('\n') ?? '';
    });
  }

  SoftwareCardInput _input() {
    String? optional(String field) =>
        _fields[field]!.text.trim().isEmpty ? null : _fields[field]!.text;
    List<String> paths(String field) => _fields[field]!.text
        .split(RegExp(r'\r?\n'))
        .where((p) => p.isNotEmpty)
        .toList();
    return SoftwareCardInput(
      name: _fields['name']!.text,
      version: optional('version'),
      service: optional('service'),
      dataPaths: paths('dataPaths'),
      configPaths: paths('configPaths'),
    );
  }

  Future<void> _save() async {
    final epoch = _epoch;
    try {
      final input = _input();
      setState(() {
        _pending = true;
        _actionError = null;
      });
      final result = await widget.owner.save(
        widget.actor,
        widget.profile.profileId,
        input,
        softwareId: _editing,
        expectedRevision: _expectedRevision,
        mutationId: _cardMutationId ??= widget.newId(),
      );
      if (!_current(epoch)) return;
      setState(() {
        _pending = false;
        _actionError = result.error;
        _editConflict = result.error?.code == FailureCode.conflict;
        if (result.ok) {
          _form = false;
          _cardMutationId = null;
        }
      });
    } on OperationFailure catch (error) {
      if (_current(epoch))
        setState(() {
          _pending = false;
          _actionError = error;
        });
    }
  }

  Future<void> _reread() async {
    if (_editing == null) return;
    final epoch = _epoch;
    final result = await widget.owner.get(widget.actor, _editing!);
    if (!_current(epoch)) return;
    if (result.ok) {
      _start(result.value!.software as SoftwareCardView);
    } else {
      setState(() => _actionError = result.error);
    }
  }

  Future<void> _delete(SoftwareCardView card) async {
    final epoch = _epoch;
    setState(() {
      _pending = true;
      _actionError = null;
    });
    final result = await widget.owner.delete(
      widget.actor,
      widget.profile.profileId,
      card.softwareId,
      expectedRevision: card.revision,
      mutationId: widget.newId(),
    );
    if (!_current(epoch)) return;
    setState(() {
      _pending = false;
      _actionError = result.error;
      if (result.ok && _editing == card.softwareId) _form = false;
    });
  }

  Future<void> _addNote() async {
    final epoch = _epoch;
    try {
      final note = SoftwareNoteInput(
        action: _action,
        summary: _summary.text,
        outcome: _outcome,
      );
      setState(() {
        _pending = true;
        _actionError = null;
      });
      final result = await widget.owner.addNote(
        widget.actor,
        widget.profile.profileId,
        note,
        softwareId: _historySoftwareId,
        mutationId: _noteMutationId ??= widget.newId(),
      );
      if (!_current(epoch)) return;
      setState(() {
        _pending = false;
        _actionError = result.error;
        if (result.ok) {
          _note = false;
          _summary.clear();
          _noteMutationId = null;
        }
      });
    } on OperationFailure catch (error) {
      if (_current(epoch))
        setState(() {
          _pending = false;
          _actionError = error;
        });
    }
  }

  void _historyFor(SoftwareCardView? card) {
    setState(() {
      if (_historySoftwareId != card?.softwareId) _resetEventExpansion();
      _historySoftwareId = card?.softwareId;
      _historyName = card?.card.name;
      _note = false;
      _noteMutationId = null;
    });
    unawaited(_load(reset: true));
  }

  void _page(bool history, int page) {
    final cursors = history ? _historyCursors : _cardCursors,
        data = history ? _history : _cards;
    if (page == cursors.length) {
      if (data?.nextCursor == null) return;
      cursors.add(data!.nextCursor);
    }
    setState(() {
      if (history) {
        if (_historyPage != page) _resetEventExpansion();
        _historyPage = page;
      } else {
        if (_cardPage != page) _resetExpansion();
        _cardPage = page;
      }
    });
    unawaited(_load());
  }

  void _resetExpansion() {
    _selectedSoftwareId = null;
  }

  void _resetEventExpansion() {
    _expandedEvents.clear();
  }

  String _time(int millis) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(
        millis,
        isUtc: true,
      ).toIso8601String();
    } on ArgumentError {
      return '$millis ms UTC';
    }
  }

  Widget _timestamp(int millis) {
    try {
      return DeckTimestamp(
        label: 'Изменено',
        value: DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
      );
    } on ArgumentError {
      return DeckKeyValue(label: 'Изменено UTC', value: '$millis ms UTC');
    }
  }

  void _selectSoftware(String id) => setState(() {
    _selectedSoftwareId = _selectedSoftwareId == id ? null : id;
  });

  Widget _softwareTable(List<SoftwareCardView> cards) =>
      DeckCollection<SoftwareCardView>(
        rows: cards,
        idOf: (card) => card.softwareId,
        selectedIds: {if (_selectedSoftwareId != null) _selectedSoftwareId!},
        columns: [
          DeckColumn(
            id: 'name',
            label: 'Название',
            value: (card) => card.card.name,
          ),
          DeckColumn(
            id: 'version',
            label: 'Версия',
            value: (card) => card.card.version ?? 'Не указана',
          ),
          DeckColumn(
            id: 'service',
            label: 'Служба',
            value: (card) => card.card.service ?? 'Не указана',
          ),
          DeckColumn(
            id: 'host',
            label: 'Хост',
            value: (card) => '${card.username}@${card.host}:${card.port}',
            builder: (context, card) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${card.username}@${card.host}:${card.port}'),
                if (!card.currentTarget)
                  const DeckStatus(label: 'Другой хост профиля'),
              ],
            ),
          ),
        ],
        actions: (card) => [
          DeckButton(
            onPressed: () => _selectSoftware(card.softwareId),
            child: const Text('Подробности'),
          ),
        ],
      );

  Widget _softwareDetails(SoftwareCardView card) => DeckSurface(
    key: ValueKey('software-details-${card.softwareId}'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DeckSectionHeader(title: 'Подробности: ${card.card.name}'),
        DeckKeyValue(label: 'Название', value: card.card.name),
        DeckKeyValue(label: 'Версия', value: card.card.version ?? 'Не указана'),
        DeckKeyValue(
          label: 'Исходный хост',
          value: '${card.username}@${card.host}:${card.port}',
          selectable: true,
        ),
        DeckKeyValue(label: 'Служба', value: card.card.service ?? 'Не указана'),
        DeckKeyValue(
          label: 'Данные',
          value: card.card.dataPaths.isEmpty
              ? 'Нет сведений'
              : card.card.dataPaths.join('\n'),
          selectable: true,
        ),
        DeckKeyValue(
          label: 'Конфиги',
          value: card.card.configPaths.isEmpty
              ? 'Нет сведений'
              : card.card.configPaths.join('\n'),
          selectable: true,
        ),
        _timestamp(card.updatedAt),
        DeckActions(
          children: [
            DeckButton(
              onPressed: _pending || !card.currentTarget
                  ? null
                  : () => _start(card),
              disabledReason: !card.currentTarget
                  ? 'Карточка относится к другому хосту'
                  : null,
              child: const Text('Изменить карточку'),
            ),
            DeckButton(
              onPressed: _pending ? null : () => _delete(card),
              child: const Text('Удалить карточку'),
            ),
            DeckButton(
              onPressed: _pending ? null : () => _historyFor(card),
              child: const Text('История карточки'),
            ),
            DeckButton(
              key: ValueKey('software-console-${card.softwareId}'),
              onPressed: card.currentTarget ? widget.onConsole : null,
              disabledReason: card.currentTarget
                  ? null
                  : 'Карточка относится к другому хосту',
              child: const Text('Открыть консоль'),
            ),
          ],
        ),
        DeckButton(
          onPressed: () => setState(() => _selectedSoftwareId = null),
          child: const Text('Закрыть подробности'),
        ),
      ],
    ),
  );
  String _eventPreview(String summary) {
    final normalized = summary.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return 'Без текста';
    final points = normalized.runes;
    return points.length <= 160
        ? normalized
        : '${String.fromCharCodes(points.take(159))}…';
  }

  String _eventSource(SoftwareEventView event) =>
      event.actorKind == 'ui' ? 'Пользователь' : 'MCP: ${event.clientId}';

  String _eventTitle(SoftwareEventView event) =>
      '${switch (event.kind) {
        'created' => 'Карточка создана',
        'updated' => 'Карточка изменена',
        'deleted' => 'Карточка удалена',
        _ => 'Сообщение',
      }} · ${event.softwareName ?? 'Хост'}';

  void _toggleEvent(String id) => setState(() {
    if (!_expandedEvents.remove(id)) _expandedEvents.add(id);
  });

  Widget _event(SoftwareEventView event) => Column(
    key: ValueKey('software-event-${event.eventId}'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DeckListItem(
        compact: true,
        title: _eventTitle(event),
        description: _eventPreview(event.summary),
        statusLabel:
            '${_eventSource(event)} · ${_time(event.createdAt)}${event.outcome == null ? '' : ' · Сообщённый исход: ${event.outcome}'}',
        selected: _expandedEvents.contains(event.eventId),
        onTap: () => _toggleEvent(event.eventId),
        trailing: MergeSemantics(
          child: Semantics(
            expanded: _expandedEvents.contains(event.eventId),
            child: DeckButton(
              onPressed: () => _toggleEvent(event.eventId),
              child: const Text('Подробности события'),
            ),
          ),
        ),
      ),
      if (_expandedEvents.contains(event.eventId))
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DeckKeyValue(
              label: 'Событие',
              value: '${event.kind} · ${event.softwareName ?? 'Хост'}',
            ),
            DeckKeyValue(
              label: 'Цель',
              value: '${event.username}@${event.host}:${event.port}',
              selectable: true,
            ),
            if (event.action != null)
              DeckKeyValue(label: 'Действие', value: event.action!),
            if (event.outcome != null)
              DeckKeyValue(label: 'Сообщённый исход', value: event.outcome!),
            if (event.changedFields.isNotEmpty)
              DeckKeyValue(
                label: 'Изменённые поля',
                value: event.changedFields.join(', '),
              ),
            DeckKeyValue(label: 'Источник', value: _eventSource(event)),
            DeckKeyValue(
              label: 'Время события UTC',
              value: _time(event.createdAt),
            ),
            DeckKeyValue(
              label: 'Сообщение',
              value: event.summary,
              selectable: true,
            ),
          ],
        ),
    ],
  );

  Widget _formWidget() => DeckFormSection(
    title: _editing == null ? 'Новая карточка ПО' : 'Изменение карточки ПО',
    description:
        'Локальный учёт. Сохранение карточки не выполняет команды на сервере.',
    children: [
      for (final entry in _fields.entries)
        DeckTextField(
          key: ValueKey('software-${entry.key}'),
          label: const {
            'name': 'Название ПО',
            'version': 'Версия',
            'service': 'Служба',
            'dataPaths': 'Данные — путь на строку',
            'configPaths': 'Конфиги — путь на строку',
          }[entry.key]!,
          controller: entry.value,
          enabled: !_pending,
          maxLines: entry.key.endsWith('Paths') ? 3 : 1,
          onChanged: (_) => _cardMutationId = null,
        ),
      if (_editConflict)
        const DeckNotice(
          title: 'Карточка изменилась',
          message: 'Ввод сохранён. Перечитайте актуальную карточку перед новым сохранением.',
        ),
      DeckActions(
        children: [
          DeckButton(
            onPressed: _pending || _editConflict ? null : _save,
            child: const Text('Сохранить карточку'),
          ),
          if (_editConflict)
            DeckButton(
              onPressed: _pending ? null : _reread,
              child: const Text('Перечитать карточку'),
            ),
          DeckButton(
            onPressed: _pending ? null : () => setState(() => _form = false),
            child: const Text('Отмена'),
          ),
        ],
      ),
    ],
  );
  Widget _noteWidget() => DeckFormSection(
    title: 'Сообщение о работе',
    description: 'Исход сообщён автором и не проверяется автоматически.',
    children: [
      DropdownButtonFormField<String>(
        initialValue: _action,
        decoration: const InputDecoration(labelText: 'Действие'),
        items: [
          for (final v in [
            'install',
            'update',
            'remove',
            'configure',
            'analyze',
            'status',
            'other',
          ])
            DropdownMenuItem(value: v, child: Text(v)),
        ],
        onChanged: _pending
            ? null
            : (v) => setState(() {
                _action = v!;
                _noteMutationId = null;
              }),
      ),
      DropdownButtonFormField<String>(
        initialValue: _outcome,
        decoration: const InputDecoration(labelText: 'Сообщённый исход'),
        items: [
          for (final v in ['success', 'failed', 'unknown'])
            DropdownMenuItem(value: v, child: Text(v)),
        ],
        onChanged: _pending
            ? null
            : (v) => setState(() {
                _outcome = v!;
                _noteMutationId = null;
              }),
      ),
      DeckTextField(
        key: const ValueKey('software-note-summary'),
        label: 'Краткое сообщение',
        controller: _summary,
        maxLines: 3,
        enabled: !_pending,
        onChanged: (_) => _noteMutationId = null,
      ),
      DeckActions(
        children: [
          DeckButton(
            onPressed: _pending ? null : _addNote,
            child: const Text('Добавить сообщение'),
          ),
          DeckButton(
            onPressed: _pending ? null : () => setState(() => _note = false),
            child: const Text('Отменить сообщение'),
          ),
        ],
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final cards = _cards?.items.whereType<SoftwareCardView>().toList() ?? [];
    final visible = cards
        .where(
          (c) => [
            c.card.name,
            c.card.version ?? '',
            c.card.service ?? '',
            ...c.card.dataPaths,
            ...c.card.configPaths,
          ].any((v) => v.toLowerCase().contains(_query)),
        )
        .toList();
    final error = _actionError ?? _loadError;
    final canNote =
        _historySoftwareId == null ||
        cards.any((c) => c.softwareId == _historySoftwareId && c.currentTarget);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DeckActions(
          children: [
            DeckButton(
              onPressed: _pending ? null : () => _start(null),
              child: const Text('Добавить ПО'),
            ),
            DeckButton(
              onPressed: () => setState(() {
                _analysis = !_analysis;
                _copied = false;
              }),
              child: const Text('Анализ сервера'),
            ),
            DeckButton(
              onPressed: _loading ? null : () => _load(reset: true),
              child: const Text('Обновить ПО'),
            ),
          ],
        ),
        if (error != null)
          DeckNotice(
            title: OperationPresentation.of(error).message,
            message:
                'Перечитайте список или исправьте ввод и повторите действие.',
            tone: DeckTone.error,
          ),
        if (_analysis)
          DeckFormSection(
            title: 'Задание внешнему ИИ',
            description: 'Скопируйте задание в ваш ИИ-клиент с доступом MCP.',
            children: [
              DeckTextField(
                key: const ValueKey('software-analysis-request'),
                label: 'Какое ПО искать',
                controller: _request,
                maxLines: 2,
              ),
              DeckButton(
                onPressed: () async {
                  final epoch = _epoch,
                      text = softwareAnalysisPrompt(
                        widget.profile,
                        _request.text,
                      );
                  try {
                    if (widget.copyText != null) {
                      await widget.copyText!(text);
                    } else {
                      await Clipboard.setData(ClipboardData(text: text));
                    }
                    if (_current(epoch)) setState(() => _copied = true);
                  } catch (_) {
                    if (_current(epoch))
                      setState(
                        () => _actionError = const OperationFailure(
                          FailureCode.storageUnavailable,
                        ),
                      );
                  }
                },
                child: const Text('Копировать задание'),
              ),
              if (_copied) const Text('Задание скопировано'),
            ],
          ),
        if (_form) _formWidget(),
        DeckSearch(
          controller: _search,
          label: 'Фильтр показанной страницы',
          onChanged: (v) => setState(() {
            _query = v.toLowerCase();
            _resetExpansion();
          }),
        ),
        if (_loading) const DeckCollectionState(state: DeckDataState.loading),
        if (!_loading && _cards != null && cards.isEmpty)
          const DeckNotice(
            title: 'Карточек ПО нет',
            message: 'Добавьте карточку или поручите анализ внешнему ИИ.',
          ),
        if (!_loading && cards.isNotEmpty && visible.isEmpty)
          const DeckCollectionState(state: DeckDataState.noResults),
        if (visible.isNotEmpty) _softwareTable(visible),
        for (final card in visible.where(
          (card) => card.softwareId == _selectedSoftwareId,
        ))
          _softwareDetails(card),
        DeckPagination(
          page: _cardPage,
          hasMore: _cards?.nextCursor != null,
          pending: _loading,
          onPageChanged: (p) => _page(false, p),
        ),
        DeckSectionHeader(
          title: _historySoftwareId == null
              ? 'История хоста'
              : 'История: ${_historyName ?? 'карточка'}',
          description: 'Хранятся последние 10 000 событий приложения. Сообщения отражают сведения автора.',
        ),
        DeckActions(
          children: [
            if (_historySoftwareId != null)
              DeckButton(
                onPressed: () => _historyFor(null),
                child: const Text('История хоста'),
              ),
            DeckButton(
              onPressed: _pending || !canNote
                  ? null
                  : () => setState(() {
                      _note = true;
                      _noteMutationId = null;
                    }),
              child: const Text('Написать сообщение'),
            ),
          ],
        ),
        if (_note) _noteWidget(),
        if (!_loading && _history?.items.isEmpty == true)
          const Text('Событий пока нет'),
        for (final event
            in _history?.items.whereType<SoftwareEventView>() ??
                <SoftwareEventView>[])
          _event(event),
        DeckPagination(
          page: _historyPage,
          hasMore: _history?.nextCursor != null,
          pending: _loading,
          onPageChanged: (p) => _page(true, p),
        ),
      ],
    );
  }
}
