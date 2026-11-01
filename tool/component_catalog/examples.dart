import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/brand_assets.dart';
import 'package:serverdeck/theme/brand_tokens.dart';
import 'package:serverdeck/ui/deck_components.dart';

import 'job_example.dart';

import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck_protocol/models.dart' show ReadinessState;

class CatalogRow {
  const CatalogRow(this.id, this.name, this.value);
  final String id, name;
  final String? value;
}

/// Synthetic owner for examples. It changes only local RAM presentation state.
class ComponentExample extends StatefulWidget {
  const ComponentExample({super.key, required this.id, this.state = 'default'});
  final String id, state;
  @override
  State<ComponentExample> createState() => _ComponentExampleState();
}

class _ComponentExampleState extends State<ComponentExample> {
  final name = TextEditingController(text: 'atlas-web');
  final search = TextEditingController();
  final code = TextEditingController(text: '{\n  "name": "atlas-web"\n}');
  final date = TextEditingController(text: '2026-11-01');
  final time = TextEditingController(text: '10:42');
  final form = GlobalKey<FormState>();
  String? result;
  bool validationFailed = false, consent = false;
  final scope = FocusScopeNode(debugLabel: 'Component example');
  String zone = 'UTC', choice = 'key', radio = 'utc';
  bool checked = true;
  bool availableOnly = false;
  int tab = 0, page = 0, pageSize = 25;
  Set<String> selected = {}, expanded = {'etc'};
  String? selectedNode;
  DeckSort? sort;

  bool get disabled => widget.state == 'disabled' || widget.state == 'pending';
  bool get pending => widget.state == 'pending';
  final rows = [
    CatalogRow('web', 'atlas-web', '192.0.2.14'),
    CatalogRow('db', 'atlas-db', null),
    CatalogRow('worker', 'atlas-worker', '192.0.2.31'),
    CatalogRow('web-standby', 'atlas-web', '192.0.2.44'),
  ];

  @override
  void initState() {
    super.initState();
    _configureFixture();
  }

  @override
  void didUpdateWidget(covariant ComponentExample oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _configureFixture();
  }

  void _configureFixture() {
    validationFailed = widget.state == 'error' && widget.id == 'C13';
    if (widget.state == 'error' && widget.id == 'C13') name.clear();
    if (widget.state == 'empty') search.clear();
    result = null;
    if (widget.state == 'no-results')
      search.text = 'нет совпадений';
    else if (search.text == 'нет совпадений')
      search.clear();
    if (widget.state == 'error' && widget.id == 'C26')
      code.text = '{ invalid json';
    if (widget.state == 'error' && widget.id == 'C28') date.text = '2026-02-31';
    if (widget.state == 'selected') {
      selected = {'web'};
      selectedNode = 'config';
      tab = 1;
      radio = 'local';
      checked = true;
    }
    if (widget.state == 'focus') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.state == 'focus') {
          FocusManager.instance.highlightStrategy =
              FocusHighlightStrategy.alwaysTraditional;
          scope.requestFocus();
          scope.nextFocus();
        }
      });
    } else {
      scope.unfocus();
    }
  }

  String? _dateError(String? value) {
    if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value))
      return 'Введите дату ГГГГ-ММ-ДД';
    final parsed = DateTime.tryParse(value);
    if (parsed == null || parsed.toIso8601String().substring(0, 10) != value)
      return 'Некорректная дата';
    return null;
  }

  void _validate(String message) {
    final valid = form.currentState?.validate() ?? false;
    setState(() {
      validationFailed = !valid;
      result = valid ? message : null;
    });
  }

  @override
  void dispose() {
    for (final controller in [name, search, code, date, time]) {
      controller.dispose();
    }
    scope.dispose();
    super.dispose();
  }

  void report(String value) {
    setState(() => result = value);
  }

  Widget button(
    String label, {
    DeckButtonKind kind = DeckButtonKind.secondary,
  }) => DeckButton(
    kind: kind,
    pending: pending,
    onPressed: disabled ? null : () => report(label),
    child: Text(label),
  );
  Widget field() => DeckTextField(
    label: 'Имя сервера',
    controller: name,
    enabled: !disabled,
    error: widget.id == 'C03' && widget.state == 'error'
        ? 'Введите корректное имя'
        : null,
    validator: (v) => v == null || v.trim().isEmpty ? 'Введите имя' : null,
    helper: 'Локальное имя, без подключения к серверу',
  );
  List<CatalogRow> get visibleRows {
    if (widget.state == 'empty') return [];
    final list = rows
        .where(
          (r) =>
              r.name.toLowerCase().contains(search.text.toLowerCase()) &&
              (!availableOnly || r.value != null),
        )
        .toList();
    if (sort != null) {
      final original = rows.asMap().map(
        (index, row) => MapEntry(row.id, index),
      );
      list.sort((a, b) {
        final x = sort!.column == 'name' ? a.name : a.value;
        final y = sort!.column == 'name' ? b.name : b.value;
        if (x == null)
          return y == null ? original[a.id]!.compareTo(original[b.id]!) : 1;
        if (y == null) return -1;
        final comparison = x.toLowerCase().compareTo(y.toLowerCase());
        if (comparison == 0) return original[a.id]!.compareTo(original[b.id]!);
        return sort!.direction == DeckSortDirection.ascending
            ? comparison
            : -comparison;
      });
    }
    return list;
  }

  DeckDataState get dataState => switch (widget.state) {
    'pending' => DeckDataState.loading,
    'error' => DeckDataState.error,
    'stale' => DeckDataState.stale,
    'partial' => DeckDataState.partial,
    'empty' => DeckDataState.empty,
    'no-results' => DeckDataState.noResults,
    'unavailable' => DeckDataState.unavailable,
    'unknown' => DeckDataState.unknown,
    _ => DeckDataState.data,
  };
  Widget collection() => DeckCollection<CatalogRow>(
    rows: visibleRows,
    idOf: (r) => r.id,
    state: visibleRows.isEmpty && search.text.isNotEmpty
        ? DeckDataState.noResults
        : widget.state == 'no-results'
        ? DeckDataState.data
        : dataState,
    selection: DeckSelection.multiple,
    columns: [
      DeckColumn(
        id: 'name',
        label: 'Сервер',
        value: (r) => r.name,
        sortable: true,
      ),
      DeckColumn(
        id: 'address',
        label: 'Адрес',
        value: (r) => r.value,
        sortable: true,
      ),
    ],
    selectedIds: selected,
    onSelectionChanged: disabled
        ? null
        : (ids) => setState(() => selected = ids),
    sort: sort,
    onSortChanged: disabled ? null : (value) => setState(() => sort = value),
    onOpen: disabled ? null : (row) => report('Открыт ${row.name}'),
    actions: (row) => [
      TextButton(
        onPressed: disabled
            ? null
            : () => setState(() {
                rows.removeWhere((r) => r.id == row.id);
                selected = {...selected}..remove(row.id);
              }),
        child: const Text('Удалить из примера'),
      ),
    ],
    onRetry: () => report('Повтор чтения'),
    onClearSearch: () {
      search.clear();
      setState(() {});
    },
  );

  Widget sample(BuildContext context) => switch (widget.id) {
    'C01' => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Image.asset(
            BrandAssets.logo(Theme.of(context).brightness),
            width: 140,
            height: 40,
            semanticLabel: 'ServerDeck',
          ),
        ),
        Text('Заголовок страницы', style: BrandTypography.title),
        const Text('Основной текст · Noto Sans 14/20'),
        Text(
          '192.0.2.14:22 · Noto Sans Mono 13/20',
          style: BrandTypography.log,
        ),
        const SizedBox(height: 16),
        Text('Таблица · 13/20', style: BrandTypography.table),
        Text('Кнопка · 13/20/600', style: BrandTypography.button),
        Text('Подпись · 12/16', style: BrandTypography.caption),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final spacing in [4.0, 8.0, 12.0, 16.0, 24.0, 32.0, 48.0])
              Column(
                children: [
                  Container(
                    width: spacing,
                    height: 8,
                    color: Theme.of(context)
                        .extension<BrandColors>()!['accent'],
                  ),
                  Text('space ${spacing.round()}'),
                ],
              ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final radius in [
              BrandGeometry.radiusControl,
              BrandGeometry.radiusCard,
              BrandGeometry.radiusDialog,
            ])
              Container(
                width: 100,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context)
                        .extension<BrandColors>()!['control'],
                  ),
                  borderRadius: BorderRadius.circular(radius),
                ),
                child: Text('radius ${radius.round()}'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            Image.asset(
              BrandAssets.mark(Theme.of(context).brightness),
              width: 24,
              height: 24,
              semanticLabel: 'Знак ServerDeck',
            ),
            for (final icon in [
              Icons.dns_outlined,
              Icons.apps_outlined,
              Icons.article_outlined,
              Icons.task_alt_outlined,
              Icons.settings_outlined,
            ])
              Icon(icon, size: 20),
          ],
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final role in Theme.of(
              context,
            ).extension<BrandColors>()!.roles.keys)
              Column(
                children: [
                  Container(
                    width: 64,
                    height: 44,
                    color: Theme.of(context).extension<BrandColors>()![role],
                  ),
                  Text(role),
                ],
              ),
          ],
        ),
      ],
    ),
    'C02' => DeckActions(
      children: [
        for (final kind in DeckButtonKind.values)
          button(switch (kind) {
            DeckButtonKind.primary => 'Создать',
            DeckButtonKind.secondary => 'Изменить',
            DeckButtonKind.text => 'Подробнее',
            DeckButtonKind.danger => 'Удалить',
          }, kind: kind),
        IconButton(
          tooltip: 'Обновить',
          onPressed: disabled ? null : () => report('Обновить'),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    'C03' => Column(
      children: [
        field(),
        const SizedBox(height: 16),
        DeckTextField(
          label: 'Только просмотр',
          initialValue: 'Полученное значение',
          readOnly: true,
          enabled: !disabled,
        ),
        const SizedBox(height: 16),
        DeckTextField(
          label: 'Порт SSH',
          initialValue: '22',
          keyboardType: TextInputType.number,
          prefixText: ':',
          enabled: !disabled,
        ),
        const SizedBox(height: 16),
        DeckTextField(
          label: 'Интервал',
          initialValue: '5',
          suffixText: 'секунд',
          enabled: !disabled,
        ),
        const SizedBox(height: 16),
        DeckTextField(
          label: 'Пароль',
          initialValue: 'demo-only',
          secret: true,
          enabled: !disabled,
        ),
        const SizedBox(height: 16),
        DeckTextField(
          label: 'Описание',
          initialValue: 'Локальные параметры',
          maxLines: 3,
          enabled: !disabled,
        ),
      ],
    ),
    'C04' => Column(
      children: [
        CheckboxListTile(
          value: checked,
          onChanged: disabled
              ? null
              : (v) => setState(() => checked = v == true),
          title: const DeckFocusLabel(child: Text('Только доступные')),
        ),
        SwitchListTile(
          value: checked,
          onChanged: disabled ? null : (v) => setState(() => checked = v),
          title: const DeckFocusLabel(child: Text('Уведомления')),
        ),
        RadioGroup<String>(
          groupValue: radio,
          onChanged: (v) {
            if (!disabled && v != null) setState(() => radio = v);
          },
          child: Column(
            children: [
              RadioListTile(
                value: 'utc',
                title: const DeckFocusLabel(child: Text('UTC')),
                enabled: !disabled,
              ),
              RadioListTile(
                value: 'local',
                title: const DeckFocusLabel(child: Text('Локальное время')),
                enabled: !disabled,
              ),
            ],
          ),
        ),
        DropdownButtonFormField<String>(
          initialValue: choice,
          decoration: const InputDecoration(labelText: 'Способ доступа'),
          items: const [
            DropdownMenuItem(value: 'key', child: Text('Ключ SSH')),
            DropdownMenuItem(value: 'password', child: Text('Пароль')),
          ],
          onChanged: disabled
              ? null
              : (v) {
                  if (v != null) setState(() => choice = v);
                },
        ),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Список')),
            ButtonSegment(value: 1, label: Text('Таблица')),
          ],
          selected: {tab},
          onSelectionChanged: disabled
              ? null
              : (v) => setState(() => tab = v.first),
        ),
      ],
    ),
    'C05' => Column(
      children: [
        DeckSearch(
          controller: search,
          enabled: !disabled,
          onChanged: (_) => setState(() {}),
          filters: [
            FilterChip(
              label: const Text('Доступные'),
              selected: availableOnly,
              onSelected: disabled
                  ? null
                  : (v) => setState(() => availableOnly = v),
            ),
          ],
        ),
        const SizedBox(height: 16),
        collection(),
      ],
    ),
    'C06' => collection(),
    'C07' =>
      widget.state == 'empty'
          ? const DeckCollectionState(state: DeckDataState.empty)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final row in visibleRows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DeckListItem(
                      title: row.name,
                      description: row.value ?? 'Нет данных',
                      leading: const Icon(Icons.dns_outlined),
                      selected: selected.contains(row.id),
                      onTap: disabled
                          ? null
                          : () => setState(
                              () => selected = selected.contains(row.id)
                                  ? {}
                                  : {row.id},
                            ),
                      trailing: button('Открыть'),
                    ),
                  ),
                DeckExpander(
                  title: const Text('Раскрываемая строка'),
                  enabled: !disabled,
                  children: const [
                    DeckKeyValue(
                      label: 'Описание',
                      value: 'Дополнительные поля того же объекта',
                    ),
                  ],
                ),
              ],
            ),
    'C08' => Column(
      children: [
        DeckPagination(
          enabled: !disabled,
          page: page,
          hasMore: !disabled && page < 3,
          pending: pending,
          pageSize: pageSize,
          total: widget.state == 'unknown' ? null : 100,
          onPageChanged: (v) => setState(() => page = v),
          onPageSizeChanged: (v) => setState(() => pageSize = v),
        ),
        DeckLoadMore(
          hasMore: !disabled && page < 3,
          pending: pending,
          onLoad: () => setState(() => page++),
        ),
      ],
    ),
    'C09' => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DeckSurface(
          child: DeckSectionHeader(
            title: 'Обычная поверхность',
            description: 'Не интерактивна, не перехватывает фокус',
          ),
        ),
        const SizedBox(height: 16),
        DeckSurface(
          selected: widget.state == 'selected',
          error: widget.state == 'error',
          enabled: !disabled,
          onTap: () => report('Открыта карточка'),
          child: DeckFormSection(
            title: 'Интерактивная карточка',
            description: 'atlas-web · 192.0.2.14',
            children: [
              if (widget.state == 'error')
                const DeckNotice(
                  message: 'Не удалось обновить сведения',
                  tone: DeckTone.error,
                ),
              const Text('Tab/Enter или нажатие открывают локальное действие.'),
            ],
          ),
        ),
      ],
    ),
    'C10' => DeckActions(
      children: [
        for (final tone in switch (widget.state) {
          'error' => [DeckTone.error],
          'unknown' => [DeckTone.unknown],
          'unavailable' => [DeckTone.unavailable],
          'success' => [DeckTone.success],
          'pending' => [DeckTone.running],
          _ => DeckTone.values,
        })
          DeckStatus(
            label: switch (tone) {
              DeckTone.neutral => 'Информация',
              DeckTone.available => 'Доступен',
              DeckTone.unavailable => 'Недоступен',
              DeckTone.unknown => 'Неизвестно',
              DeckTone.warning => 'Внимание',
              DeckTone.error => 'Ошибка',
              DeckTone.running => 'Выполняется',
              DeckTone.success => 'Успех',
            },
            tone: tone,
            pending: tone == DeckTone.running && pending,
          ),
        const Chip(label: Text('production')),
        const Badge(
          label: Text('3'),
          child: Icon(Icons.notifications_outlined),
        ),
      ],
    ),
    'C11' => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.state == 'unknown')
          const DeckNotice(
            title: 'Исход неизвестен',
            message: 'На сервере могли произойти изменения',
            nextStep: 'Проверьте состояние операции перед следующим действием',
            tone: DeckTone.unknown,
          )
        else if (widget.state == 'pending')
          const DeckStatus(label: 'Действие выполняется', pending: true)
        else if (widget.state == 'error')
          DeckNotice(
            title: 'Не удалось получить данные',
            message: 'Источник не ответил',
            tone: DeckTone.error,
            actions: [button('Повторить чтение')],
          )
        else ...[
          const DeckNotice(message: 'Профиль сохранён', tone: DeckTone.success),
          const SizedBox(height: 12),
          const DeckNotice(
            title: 'SSH-ключ изменился',
            message: 'Подключение заблокировано',
            nextStep: 'Проверьте ключ по доверенному каналу',
            tone: DeckTone.error,
          ),
        ],
        const SizedBox(height: 12),
        DeckButton(
          onPressed: disabled
              ? null
              : () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Локальный результат'),
                    duration: Duration(seconds: 4),
                    showCloseIcon: true,
                  ),
                ),
          child: const Text('Показать уведомление'),
        ),
      ],
    ),
    'C12' => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DeckCollectionState(
          state: ['focus', 'hover', 'pressed'].contains(widget.state)
              ? DeckDataState.error
              : dataState,
          onRetry: () => report('Повтор чтения'),
          onClearSearch: () => report('Очистить поиск'),
          message: switch (widget.state) {
            'stale' => 'Предыдущий снимок: atlas-web · 10:42 UTC',
            'partial' => 'Получены 2 из 3 записей; источник указан владельцем',
            'unknown' => 'Подтверждённое наблюдение ещё не получено',
            _ => null,
          },
        ),
        if (pending) const DeckSkeleton(),
      ],
    ),
    'C13' => Form(
      key: form,
      autovalidateMode: widget.state == 'error'
          ? AutovalidateMode.always
          : AutovalidateMode.onUserInteraction,
      child: DeckFormSection(
        title: 'Параметры профиля',
        children: [
          if (validationFailed)
            const DeckNotice(
              title: 'Проверьте форму',
              message: 'Исправьте отмеченные поля',
              tone: DeckTone.error,
            ),
          field(),
          DeckButton(
            pending: pending,
            onPressed: disabled
                ? null
                : () {
                    _validate('Форма проверена');
                  },
            child: const Text('Сохранить'),
          ),
          button('Отмена', kind: DeckButtonKind.text),
        ],
      ),
    ),
    'C14' => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 400,
          child: DeckDialogLayout(
            title: 'Информационный диалог',
            child: const Text(
              'Параметры хранятся локально. На сервере ничего не изменяется.',
            ),
            actions: [button('Закрыть пример')],
          ),
        ),
        SizedBox(
          height: 480,
          child: DeckDialogLayout(
            title: 'Редактирование · пример',
            target: const Text('atlas-web · локальный профиль'),
            child: field(),
            actions: [
              button('Сохранить пример', kind: DeckButtonKind.primary),
              button('Отмена редактирования', kind: DeckButtonKind.text),
            ],
          ),
        ),
        SizedBox(
          height: 480,
          child: DeckDialogLayout(
            title: 'Подтверждение опасного действия',
            target: const Text('atlas-web · 192.0.2.14'),
            child: const Text(
              'Удаляется только локальный профиль. На сервере ничего не изменится.',
            ),
            actions: [
              button('Отмена удаления', kind: DeckButtonKind.text),
              button('Удалить пример', kind: DeckButtonKind.danger),
            ],
          ),
        ),

        DeckButton(
          onPressed: disabled
              ? null
              : () => showDialog<void>(
                  context: context,
                  builder: (dialog) => DeckDialogLayout(
                    title: 'Локальный профиль',
                    actions: [
                      DeckButton(
                        onPressed: () => Navigator.pop(dialog),
                        child: const Text('Закрыть'),
                      ),
                    ],
                    child: const Text(
                      'Параметры хранятся локально. Подключение выполняется отдельно.',
                    ),
                  ),
                ),
          child: const Text('Информационный диалог'),
        ),
        DeckButton(
          onPressed: disabled
              ? null
              : () => showDialog<void>(
                  context: context,
                  builder: (dialog) => DeckDialogLayout(
                    title: 'Редактирование',
                    actions: [
                      DeckButton(
                        onPressed: () => Navigator.pop(dialog),
                        child: const Text('Отмена'),
                      ),
                      DeckButton(
                        onPressed: () => Navigator.pop(dialog),
                        child: const Text('Сохранить'),
                      ),
                    ],
                    child: field(),
                  ),
                ),
          child: const Text('Диалог редактирования'),
        ),
        DeckButton(
          onPressed: disabled
              ? null
              : () => showDialog<void>(
                  context: context,
                  builder: (dialog) => DeckDialogLayout(
                    title: 'Удалить локальный профиль?',
                    target: const Text('atlas-web · 192.0.2.14'),
                    actions: [
                      DeckButton(
                        onPressed: () => Navigator.pop(dialog),
                        child: const Text('Отмена'),
                      ),
                      DeckButton(
                        kind: DeckButtonKind.danger,
                        onPressed: () => Navigator.pop(dialog),
                        child: const Text('Удалить профиль'),
                      ),
                    ],
                    child: const Text(
                      'Удаляются локальные параметры. На сервере ничего не изменится.',
                    ),
                  ),
                ),
          child: const Text('Открыть подтверждение'),
        ),
      ],
    ),
    'C15' => DeckActions(
      children: [
        DeckContextMenu(
          enabled: !disabled,
          entries: const [
            DeckMenuEntry('Открыть'),
            DeckMenuEntry('Изменить'),
            DeckMenuEntry('Удалить', enabled: false, reason: 'Нет разрешения'),
          ],
          onSelected: report,
          child: const DeckSurface(
            child: Text('Контекстное меню: правая кнопка / Shift+F10'),
          ),
        ),
        PopupMenuButton<String>(
          enabled: !disabled,
          tooltip: 'Действия',
          onSelected: report,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'Открыть', child: Text('Открыть')),
            PopupMenuItem(value: 'Изменить', child: Text('Изменить')),
            PopupMenuItem(
              value: 'Недоступно',
              enabled: false,
              child: Text('Нет разрешения'),
            ),
          ],
        ),
        Tooltip(
          message: 'Обновить разрешённые данные',
          child: IconButton(
            onPressed: disabled ? null : () => report('Обновить'),
            icon: const Icon(Icons.refresh),
          ),
        ),
      ],
    ),
    'C16' => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          tooltip: 'Назад',
          onPressed: disabled ? null : () => report('Назад'),
          icon: const Icon(Icons.arrow_back),
        ),
        DeckBreadcrumbs(
          labels: const ['Серверы', 'atlas-web'],
          onSelected: disabled ? null : (index) => report('Переход $index'),
        ),
        DeckTabs(
          labels: const ['Обзор', 'Журнал', 'Параметры'],
          selected: tab,
          onSelected: disabled ? null : (v) => setState(() => tab = v),
        ),
      ],
    ),
    'C17' => SizedBox(
      height: MediaQuery.sizeOf(context).height > 0
          ? MediaQuery.sizeOf(context).height
          : 600,
      child: FoundationShell(
        state: widget.state == 'unavailable'
            ? ReadinessState.unavailable
            : ReadinessState.ready,
        targetName: 'atlas-web',
        targetAddress: '192.0.2.14',
        servers: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DeckSectionHeader(title: 'Локальные профили'),
              collection(),
            ],
          ),
        ),
        settings: const SingleChildScrollView(
          child: Text('Настройки · синтетические значения'),
        ),
        software: const SingleChildScrollView(
          child: Text('Каталог ПО · синтетические значения'),
        ),
      ),
    ),
    'C18' => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.state == 'stale')
          const DeckNotice(
            message: 'Устаревшее значение из последнего снимка',
            tone: DeckTone.warning,
          ),
        if (widget.state == 'partial')
          const DeckNotice(
            message: 'Получены только отдельные поля',
            tone: DeckTone.warning,
          ),
        DeckKeyValue(
          label: 'Адрес',
          value: widget.state == 'unknown' ? 'Нет данных' : '192.0.2.14:22',
          selectable: true,
        ),
        if (widget.state != 'unknown')
          DeckCopyButton(
            value: '192.0.2.14:22',
            label: 'Скопировать адрес',
            enabled: !disabled,
          ),
      ],
    ),
    'C19' => DeckExpander(
      enabled: !disabled,
      title: const Text('Технические сведения'),
      initiallyExpanded: widget.state == 'expanded',
      children: [DeckCode(label: 'Идентификатор', text: 'server-demo-014')],
    ),
    'C20' =>
      widget.state == 'empty'
          ? const DeckCollectionState(state: DeckDataState.empty)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.state == 'stale')
                  const DeckNotice(
                    message: 'Показан устаревший журнал',
                    tone: DeckTone.warning,
                  ),
                if (widget.state == 'partial')
                  const DeckNotice(
                    message: 'Журнал неполон: пропущены 3 записи',
                    tone: DeckTone.warning,
                  ),
                DeckListItem(
                  title: '10:42:15 UTC · WARN · nginx',
                  description: 'Повторное соединение с upstream',
                  trailing: DeckButton(
                    onPressed: disabled
                        ? null
                        : () => showDialog<void>(
                            context: context,
                            builder: (dialog) => DeckDialogLayout(
                              title: 'Запись журнала',
                              target: const Text('atlas-web · journald'),
                              actions: [
                                DeckButton(
                                  onPressed: () => Navigator.pop(dialog),
                                  child: const Text('Закрыть'),
                                ),
                              ],
                              child: const DeckLogMessage(
                                message: 'WARN nginx: повторное соединение с upstream',
                                source: 'journald',
                                eventTime: '2026-11-01 10:42:15',
                                observedAt: '2026-11-01 10:42:18',
                              ),
                            ),
                          ),
                    child: const Text('Полная запись'),
                  ),
                ),
                const DeckLogMessage(
                  message: 'INFO nginx: проверка выполнена\nWARN nginx: повторное соединение с upstream\nПропущены 3 записи',
                  source: 'journald · atlas-web',
                  eventTime: '2026-11-01 10:42:15',
                  observedAt: '2026-11-01 10:42:18',
                ),
              ],
            ),
    'C21' => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DeckMetric(
          label: 'CPU',
          value: widget.state == 'unknown' ? null : '24',
          unit: '%',
          contextLabel: switch (widget.state) {
            'stale' => 'Устаревшее наблюдение · SSH · 10:42:18 UTC',
            'partial' => 'Неполный снимок · SSH · 10:42:18 UTC',
            'unknown' => 'Подтверждённое наблюдение ещё не получено',
            _ => 'SSH · 10:42:18 UTC',
          },
          tone: widget.state == 'unknown'
              ? DeckTone.unknown
              : ['stale', 'partial'].contains(widget.state)
              ? DeckTone.warning
              : DeckTone.neutral,
        ),
        const SizedBox(height: 16),
        DeckMetric(
          label: 'Память',
          value: widget.state == 'unknown' ? null : '6,2 / 16',
          unit: 'ГБ',
          contextLabel: 'Использовано / лимит',
        ),
      ],
    ),
    'C22' => DeckHistory(
      points: widget.state == 'empty'
          ? const []
          : [
              {
                'receivedAt': '2026-11-01T10:42:00Z',
                'cpuPercent': 24,
                'memoryUsedPercent': 39,
                'rootDiskUsedPercent': 35,
              },
              {
                'receivedAt': '2026-11-01T10:42:05Z',
                'cpuPercent': 30,
                'memoryUsedPercent': 42,
                'rootDiskUsedPercent': 35,
              },
              {
                'receivedAt': '2026-11-01T10:42:30Z',
                'cpuPercent': 20,
                'memoryUsedPercent': 40,
                'rootDiskUsedPercent': 35,
              },
            ],
      stale: widget.state == 'stale',
      quality: widget.state == 'partial'
          ? 'incomplete'
          : widget.state == 'unknown'
          ? 'unknown'
          : 'known',
      source: 'SSH · atlas-web',
      observedAt: '2026-11-01T10:42:30Z',
    ),
    'C23' => DeckProgress(
      label: switch (widget.state) {
        'success' => 'Задание завершено',
        'error' => 'Ошибка этапа',
        'cancelled' => 'Остановка подтверждена',
        'unknown' => 'Исход неизвестен',
        _ => 'Выполняется',
      },
      tone: switch (widget.state) {
        'success' => DeckTone.success,
        'error' => DeckTone.error,
        'cancelled' => DeckTone.warning,
        'unknown' => DeckTone.unknown,
        _ => DeckTone.running,
      },
      value: pending || widget.state == 'unknown'
          ? null
          : widget.state == 'success'
          ? 1
          : .6,
      steps: [
        const DeckProgressStep('Проверка условий', tone: DeckTone.success),
        DeckProgressStep(
          'Изменение пакетов',
          tone: switch (widget.state) {
            'success' => DeckTone.success,
            'error' => DeckTone.error,
            'cancelled' => DeckTone.warning,
            'unknown' => DeckTone.unknown,
            _ => DeckTone.running,
          },
        ),
        DeckProgressStep(
          'Проверка результата',
          tone: widget.state == 'success' ? DeckTone.success : DeckTone.unknown,
        ),
      ],
    ),
    'C24' => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DeckPlanSummary(
          target: 'atlas-db · 192.0.2.28',
          effects: 'Установить PostgreSQL; будет запущена служба',
          scope: 'Только выбранный сервер',
          deadline: '2026-11-01 10:46:00 UTC',
          warning: widget.state == 'error'
              ? 'План требует новой проверки'
              : 'Изменённый план требует нового согласия',
          details: const Text('plan-demo-001 · revision 2'),
        ),
        CheckboxListTile(
          title: const Text('Цель и последствия проверены'),
          value: consent,
          onChanged: disabled
              ? null
              : (value) => setState(() => consent = value == true),
        ),
        DeckActions(
          children: [
            DeckButton(
              kind: DeckButtonKind.primary,
              pending: pending,
              onPressed:
                  disabled ||
                      !consent ||
                      ['error', 'unknown', 'unavailable'].contains(widget.state)
                  ? null
                  : () => report('Подтверждён локальный пример плана'),
              disabledReason: !consent
                  ? 'Сначала проверьте цель и последствия'
                  : null,
              child: const Text('Подтвердить план'),
            ),
            button('Отмена', kind: DeckButtonKind.text),
          ],
        ),
      ],
    ),
    'C25' =>
      widget.state == 'empty'
          ? const DeckCollectionState(state: DeckDataState.empty)
          : const DeckDiff(
              entries: [
                DeckDifference(
                  label: 'worker_count',
                  before: '2',
                  after: '4',
                  change: DeckChange.changed,
                ),
                DeckDifference(
                  label: 'Новый параметр',
                  after: 'true',
                  change: DeckChange.added,
                ),
                DeckDifference(
                  label: 'Удалённый параметр',
                  before: 'legacy',
                  change: DeckChange.removed,
                ),
                DeckDifference(
                  label: 'Без изменений',
                  before: '22',
                  after: '22',
                  change: DeckChange.unchanged,
                ),
                DeckDifference(
                  label: 'Версия',
                  before: '1',
                  after: '2',
                  change: DeckChange.conflict,
                ),
              ],
            ),
    'C26' => Form(
      key: form,
      autovalidateMode: widget.state == 'error'
          ? AutovalidateMode.always
          : AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DeckCode(
            label: 'Конфигурация',
            controller: code,
            readOnly: false,
            enabled: !disabled,
            validator: (value) {
              try {
                jsonDecode(value ?? '');
                return null;
              } on FormatException {
                return 'Некорректный JSON';
              }
            },
          ),
          DeckButton(
            onPressed: disabled
                ? null
                : () => _validate('Формат JSON корректен'),
            child: const Text('Проверить формат'),
          ),
          if (validationFailed)
            const DeckNotice(
              message: 'Некорректный JSON',
              tone: DeckTone.error,
            ),
          const SizedBox(height: 16),
          const DeckCode(
            label: 'Команда · только просмотр',
            text: 'systemctl status demo.service',
            allowCopy: false,
          ),
        ],
      ),
    ),
    'C27' =>
      widget.state == 'empty'
          ? const DeckCollectionState(state: DeckDataState.empty)
          : widget.state == 'unavailable'
          ? const DeckCollectionState(
              state: DeckDataState.unavailable,
              message: 'Источник файлов недоступен. Выбор и раскрытие заблокированы.',
            )
          : DeckPathTree(
              enabled: !disabled,
              selectedId: selectedNode,
              path: const ['/', 'etc', 'demo-app'],
              nodes: const [
                DeckPathNode(
                  id: 'etc',
                  label: 'demo-app',
                  children: [
                    DeckPathNode(id: 'config', label: 'config.yaml'),
                    DeckPathNode(
                      id: 'private',
                      label: 'private/',
                      available: false,
                      reason: 'Недостаточно прав',
                    ),
                  ],
                ),
              ],
              expandedIds: expanded,
              onExpansionChanged: (ids) => setState(() => expanded = ids),
              onSelected: (id) => setState(() {
                selectedNode = id;
                result = 'Выбран узел: $id';
              }),
            ),
    'C28' => Form(
      key: form,
      autovalidateMode: widget.state == 'error'
          ? AutovalidateMode.always
          : AutovalidateMode.onUserInteraction,
      child: Column(
        children: [
          DeckDateTimeInput(
            dateController: date,
            timeController: time,
            zone: zone,
            onZoneChanged: (z) => setState(() => zone = z),
            enabled: !disabled,
            dateValidator: _dateError,
            timeValidator: (value) =>
                RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value ?? '')
                ? null
                : 'Некорректное время',
          ),
          DeckButton(
            onPressed: disabled
                ? null
                : () => _validate('Дата и время корректны'),
            child: const Text('Проверить дату и время'),
          ),
          if (validationFailed)
            const DeckNotice(
              message: 'Проверьте дату и время',
              tone: DeckTone.error,
            ),
          DeckTimestamp(
            label: 'Время наблюдения',
            value: DateTime.utc(2026, 11, 1, 10, 42, 18),
          ),
        ],
      ),
    ),
    'C29' => JobCollectionExample(
      disabled: disabled,
      pending: pending,
      state: dataState,
      initialSelected: widget.state == 'selected',
    ),
    'C30' => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!['unknown', 'unavailable', 'error'].contains(widget.state))
          const DeckCapability(
            title: 'Системные службы',
            reason: 'Доступно в выбранном контексте',
            tone: DeckTone.available,
          ),
        if (!['unknown', 'error'].contains(widget.state))
          DeckCapability(
            title: 'SMART',
            statusLabel: 'Не поддерживается',
            reason: 'Источник не поддерживается',
            tone: DeckTone.unavailable,
            nextStep: button('Подробнее', kind: DeckButtonKind.text),
          ),
        if (!['unavailable', 'error'].contains(widget.state))
          const DeckCapability(
            title: 'Датчики',
            reason: 'Подтверждённые сведения ещё не получены',
            tone: DeckTone.unknown,
          ),
        if (widget.state == 'error')
          const DeckCapability(
            title: 'Изменение доступа',
            reason: 'Недостаточно прав',
            tone: DeckTone.error,
          ),
      ],
    ),
    _ => const Text('Выберите компонент'),
  };

  @override
  Widget build(BuildContext context) => FocusScope(
    node: scope,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sample(context),
        if (result != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Semantics(
              liveRegion: true,
              child: Text('Демонстрация: $result'),
            ),
          ),
      ],
    ),
  );
}
