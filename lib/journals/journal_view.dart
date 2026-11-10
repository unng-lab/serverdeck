import 'dart:async';

import 'package:flutter/material.dart';

import '../storage/records.dart';
import '../ui/deck_components.dart';
import 'journal_models.dart';
import 'journal_owner.dart';
import 'delete_source_dialog.dart';

String _failure(Object e) => e is ArgumentError
    ? '${e.message}'
    : e is StateError
    ? '${e.message}'
    : 'Не удалось сохранить журнал. Повторите действие.';

class JournalView extends StatefulWidget {
  const JournalView({
    super.key,
    required this.owner,
    required this.profileId,
    required this.connectionRevision,
  });
  final JournalsOwner owner;
  final String profileId;
  final int connectionRevision;
  @override
  State<JournalView> createState() => _JournalViewState();
}

class _JournalViewState extends State<JournalView> {
  String? _selected, _error;
  final _search = TextEditingController();
  String _query = '';
  int _limit = 200;
  void _selectSource(String id) {
    _selected = id;
    _limit = 200;
  }

  void _changeSearch(String value) => setState(() {
    _query = value.trim().toLowerCase();
  });
  final _routes = <(DialogRoute<void>, NavigatorState)>{};
  Future<void> _dialog(WidgetBuilder builder) async {
    final navigator = Navigator.of(context),
        route = DialogRoute<void>(context: context, builder: builder);
    _routes.add((route, navigator));
    try {
      await navigator.push(route);
    } finally {
      _routes.remove((route, navigator));
    }
  }

  void _closeRoutes() {
    final routes = List.of(_routes);
    _routes.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final pair in routes) {
        if (pair.$1.isActive && pair.$2.mounted) pair.$2.removeRoute(pair.$1);
      }
    });
  }

  @override
  void didUpdateWidget(covariant JournalView old) {
    super.didUpdateWidget(old);
    if (old.profileId != widget.profileId ||
        old.owner != widget.owner ||
        old.connectionRevision != widget.connectionRevision) {
      _closeRoutes();
      _selected = null;
      _search.clear();
      _query = '';
      _error = null;
      _limit = 200;
    }
  }

  @override
  void dispose() {
    _closeRoutes();
    _search.dispose();
    super.dispose();
  }

  Future<void> _action(Future<void> Function() action) async {
    final profile = widget.profileId,
        owner = widget.owner,
        revision = widget.connectionRevision;
    try {
      await action();
      if (mounted &&
          widget.profileId == profile &&
          widget.connectionRevision == revision &&
          identical(widget.owner, owner))
        setState(() => _error = null);
    } catch (e) {
      if (mounted &&
          widget.profileId == profile &&
          widget.connectionRevision == revision &&
          identical(widget.owner, owner))
        setState(() => _error = _failure(e));
    }
  }

  Future<void> _edit([JournalSource? source]) async {
    final owner = widget.owner,
        profile = widget.profileId,
        revision = widget.connectionRevision;
    await _dialog(
      (_) => _SourceForm(
        source: source,
        onSave: (name, path) async {
          if (!mounted ||
              widget.profileId != profile ||
              widget.connectionRevision != revision ||
              !identical(widget.owner, owner))
            throw StateError('Контекст сервера изменился');
          if (source != null) {
            await owner.rename(source.sourceId, name);
          } else {
            final id = await owner.add(profile, JournalKind.file, path, name);
            if (mounted &&
                widget.profileId == profile &&
                widget.connectionRevision == revision &&
                identical(widget.owner, owner))
              setState(() {
                _selectSource(id);
              });
          }
        },
      ),
    );
  }

  Future<void> _delete(JournalSource source) {
    final owner = widget.owner,
        profile = widget.profileId,
        revision = widget.connectionRevision;
    return _dialog(
      (_) => DeleteJournalSourceDialog(
        name: source.name,
        onDelete: () async {
          if (!mounted ||
              widget.profileId != profile ||
              widget.connectionRevision != revision ||
              !identical(widget.owner, owner))
            throw StateError('Контекст сервера изменился');
          await owner.deleteSource(source.sourceId);
        },
      ),
    );
  }

  void _record(JournalSource source, JournalEntry event) {
    final owner = widget.owner,
        profile = widget.profileId,
        sourceId = source.sourceId,
        revision = source.connectionRevision,
        eventId = event.id,
        receivedAt = event.receivedAt;
    unawaited(
      _dialog(
        (ctx) => ListenableBuilder(
          listenable: owner,
          builder: (_, _) {
            JournalSource? liveSource;
            JournalEntry? liveEvent;
            if (mounted &&
                widget.profileId == profile &&
                widget.connectionRevision == revision &&
                identical(widget.owner, owner) &&
                widget.connectionRevision == revision) {
              for (final s in owner.sources(profile)) {
                if (s.sourceId == sourceId && s.connectionRevision == revision)
                  liveSource = s;
              }
              if (liveSource != null)
                for (final e in owner.entries(sourceId)) {
                  if (e.id == eventId && e.receivedAt == receivedAt)
                    liveEvent = e;
                }
            }
            final current = liveEvent;
            return DeckDialogLayout(
              title: 'Запись журнала',
              child: current == null
                  ? const DeckNotice(
                      title: 'Запись больше недоступна',
                      message: 'Срок хранения истёк, источник удалён или контекст сервера изменился.',
                    )
                  : DeckLogMessage(
                      message: current.text,
                      source: liveSource!.name,
                      eventTime: current.sourceAt == null
                          ? null
                          : DateTime.fromMillisecondsSinceEpoch(
                              current.sourceAt!,
                              isUtc: true,
                            ).toIso8601String(),
                      observedAt: DateTime.fromMillisecondsSinceEpoch(
                        current.receivedAt,
                        isUtc: true,
                      ).toIso8601String(),
                    ),
              actions: [
                DeckButton(
                  child: const Text('Закрыть'),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.owner,
    builder: (context, _) {
      final owner = widget.owner, allSources = owner.sources(widget.profileId);
      JournalSource? selected;
      for (final s in allSources) {
        if (s.sourceId == _selected) selected = s;
      }
      final profile = widget.profileId, revision = widget.connectionRevision;
      bool current() =>
          mounted &&
          widget.profileId == profile &&
          widget.connectionRevision == revision &&
          identical(widget.owner, owner);
      Future<void> act(Future<void> Function() effect) async {
        if (current()) await _action(effect);
      }

      final source = selected;
      final entries = source == null
          ? <JournalEntry>[]
          : owner.entries(source.sourceId);
      final allServices = owner.services[widget.profileId] ?? const <String>[];
      final services = _query.isEmpty
          ? allServices
          : allServices.where((s) => s.toLowerCase().contains(_query)).toList();
      final sources = _query.isEmpty
          ? allSources
          : allSources
                .where(
                  (s) =>
                      s.name.toLowerCase().contains(_query) ||
                      s.target.toLowerCase().contains(_query),
                )
                .toList();
      void clearSearch() {
        if (current()) {
          _search.clear();
          _changeSearch('');
        }
      }

      final serviceState = owner.serviceStates[widget.profileId];
      var partial = false;
      if (source != null) {
        try {
          partial = owner.payload(source.sourceId).partial;
        } catch (_) {
          partial = true;
        }
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Журналы · последние 200 записей и история за последний час',
          ),
          const Text(
            'Сбор работает при подключённом сервере, в том числе в трее. Ограниченная история; возможны пропуски. Файлы читаются с момента включения, время строк — время получения.',
          ),
          if (_error != null)
            DeckNotice(
              title: 'Действие не выполнено',
              message: _error!,
              tone: DeckTone.error,
            ),
          if (owner.error != null)
            DeckNotice(
              title: 'Журналы недоступны',
              message: journalStatusLabel(owner.error!),
              tone: DeckTone.error,
            ),
          DeckActions(
            children: [
              DeckButton(
                child: const Text('Обновить сервисы'),
                onPressed: () => act(() => owner.discover(profile)),
              ),
              DeckButton(
                child: const Text('Добавить файл'),
                onPressed: () => act(() => _edit()),
              ),
            ],
          ),
          DeckSearch(
            key: ValueKey((owner, profile, revision)),
            controller: _search,
            label: 'Поиск сервиса или источника',
            onChanged: (value) {
              if (current()) _changeSearch(value);
            },
          ),
          if (serviceState != null)
            Text('Сервисы: ${journalStatusLabel(serviceState)}'),
          if (allServices.isNotEmpty || serviceState == JournalStatus.empty)
            DeckCollection<String>(
              rows: services,
              idOf: (s) => s,
              state: allServices.isEmpty
                  ? DeckDataState.empty
                  : services.isEmpty
                  ? DeckDataState.noResults
                  : DeckDataState.data,
              message: allServices.isEmpty
                  ? 'Сервисы не обнаружены'
                  : services.isEmpty
                  ? 'Сервисы не найдены'
                  : null,
              onClearSearch: clearSearch,
              columns: [
                DeckColumn(
                  id: 'unit',
                  label: 'Сервис systemd',
                  value: (s) => s,
                ),
              ],
              actions: (unit) => [
                DeckButton(
                  child: const Text('Добавить сервис'),
                  onPressed:
                      allSources.any(
                        (s) => s.kind == 'journal' && s.target == unit,
                      )
                      ? null
                      : () => act(() async {
                          final id = await owner.add(
                            profile,
                            JournalKind.journal,
                            unit,
                            String.fromCharCodes(unit.runes.take(80)),
                          );
                          if (current())
                            setState(() {
                              _selectSource(id);
                            });
                        }),
                ),
              ],
            ),
          DeckCollection<JournalSource>(
            rows: sources,
            idOf: (s) => s.sourceId,
            columns: [
              DeckColumn(id: 'name', label: 'Источник', value: (s) => s.name),
              DeckColumn(
                id: 'target',
                label: 'Расположение',
                value: (s) => s.target,
              ),
              DeckColumn(
                id: 'state',
                label: 'Сбор',
                value: (s) => journalStatusLabel(owner.status(s)),
              ),
            ],
            state: allSources.isEmpty
                ? DeckDataState.empty
                : sources.isEmpty
                ? DeckDataState.noResults
                : DeckDataState.data,
            message: allSources.isEmpty
                ? 'Добавьте сервис или файл журнала'
                : sources.isEmpty
                ? 'Источники не найдены'
                : null,
            onClearSearch: clearSearch,
            onOpen: (s) {
              if (!current()) return;
              setState(() {
                _selectSource(s.sourceId);
              });
            },
          ),
          if (source != null) ...[
            Text('Источник: ${source.name}'),
            Text(journalStatusLabel(owner.status(source))),
            if (partial)
              const DeckNotice(
                title: 'История неполная',
                message: 'Были пропуски, сброс позиции или ограничение объёма.',
              ),
            DeckActions(
              children: [
                DeckButton(
                  child: Text(
                    source.enabled ? 'Выключить сбор' : 'Включить сбор',
                  ),
                  onPressed: () => act(
                    () => owner.setEnabled(source.sourceId, !source.enabled),
                  ),
                ),
                DeckButton(
                  child: const Text('Переименовать'),
                  onPressed: () => act(() => _edit(source)),
                ),
                DeckButton(
                  child: const Text('Повторить чтение'),
                  onPressed: () => act(() => owner.retry(source.sourceId)),
                ),
                DeckButton(
                  kind: DeckButtonKind.danger,
                  child: const Text('Удалить'),
                  onPressed: () => act(() => _delete(source)),
                ),
              ],
            ),
            DeckCollection<JournalEntry>(
              rows: entries.take(_limit).toList(),
              idOf: (e) => e.id,
              columns: [
                DeckColumn(
                  id: 'time',
                  label: 'Получено UTC',
                  value: (e) => DateTime.fromMillisecondsSinceEpoch(
                    e.receivedAt,
                    isUtc: true,
                  ).toIso8601String(),
                ),
                DeckColumn(
                  id: 'source',
                  label: 'Источник',
                  value: (_) => source.name,
                ),
                DeckColumn(
                  id: 'eventTime',
                  label: 'Событие UTC',
                  value: (e) => e.sourceAt == null
                      ? 'Время получения'
                      : DateTime.fromMillisecondsSinceEpoch(
                          e.sourceAt!,
                          isUtc: true,
                        ).toIso8601String(),
                ),
                DeckColumn(
                  id: 'priority',
                  label: 'Важность',
                  value: (e) => e.priority?.toString() ?? 'Неизвестна',
                ),
                DeckColumn(
                  id: 'message',
                  label: 'Сообщение',
                  value: (e) =>
                      '${String.fromCharCodes(e.text.runes.take(200))}${e.truncated ? ' [усечено]' : ''}',
                ),
              ],
              state: entries.isEmpty ? DeckDataState.empty : DeckDataState.data,
              message: 'В источнике пока нет доступных записей',
              onOpen: (e) {
                if (current()) _record(source, e);
              },
            ),
            DeckLoadMore(
              hasMore: entries.length > _limit,
              onLoad: () {
                if (current()) setState(() => _limit += 200);
              },
            ),
          ],
        ],
      );
    },
  );
}

class _SourceForm extends StatefulWidget {
  const _SourceForm({this.source, required this.onSave});
  final JournalSource? source;
  final Future<void> Function(String, String) onSave;
  @override
  State<_SourceForm> createState() => _SourceFormState();
}

class _SourceFormState extends State<_SourceForm> {
  late final _name = TextEditingController(text: widget.source?.name ?? '');
  late final _path = TextEditingController(text: widget.source?.target ?? '');
  String? _error;
  bool _pending = false;
  @override
  void dispose() {
    _name.dispose();
    _path.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_pending) return;
    setState(() {
      _pending = true;
      _error = null;
    });
    try {
      await widget.onSave(_name.text, _path.text);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = _failure(e));
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_pending,
    child: DeckDialogLayout(
      title: widget.source == null
          ? 'Добавить файловый журнал'
          : 'Переименовать источник',
      child: DeckFormSection(
        title: 'Источник журнала',
        children: [
          DeckTextField(
            label: 'Название источника',
            controller: _name,
            enabled: !_pending,
          ),
          if (widget.source == null)
            DeckTextField(
              label: 'Абсолютный путь на сервере',
              controller: _path,
              enabled: !_pending,
              helper: 'Например /opt/app/logs/service.log; новые строки после включения',
            ),
          if (_error != null)
            DeckNotice(
              title: 'Не удалось сохранить',
              message: _error!,
              tone: DeckTone.error,
            ),
        ],
      ),
      actions: [
        DeckButton(
          child: const Text('Отмена'),
          onPressed: _pending ? null : () => Navigator.pop(context),
        ),
        DeckButton(
          kind: DeckButtonKind.primary,
          child: const Text('Сохранить источник'),
          pending: _pending,
          onPressed: _save,
        ),
      ],
    ),
  );
}
