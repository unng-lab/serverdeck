import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/fixtures.dart';
import '../domain/models.dart';

const _bg = Color(0xFF0C121C);
const _panel = Color(0xFF151E2B);
const _muted = Color(0xFF92A2B6);
const _accent = Color(0xFF64DFC5);
const _warning = Color(0xFFFFC47A);

class ServerDeckApp extends StatelessWidget {
  const ServerDeckApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ServerDeck',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: _bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _accent,
        brightness: Brightness.dark,
        surface: _panel,
        primary: _accent,
      ),
      fontFamily: 'Segoe UI',
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _bg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dividerColor: const Color(0xFF253246),
    ),
    home: const DeckShell(),
  );
}

class DeckShell extends StatefulWidget {
  const DeckShell({super.key});
  @override
  State<DeckShell> createState() => _DeckShellState();
}

class _DeckShellState extends State<DeckShell> {
  final repo = FixtureRepository();
  String selectedId = 'lab-a',
      page = 'servers',
      softwareQuery = '',
      recipe = 'PostgreSQL';
  bool allSoftware = true;
  Timer? _live;
  String? _liveServer;
  ServerProfile get selected =>
      repo.servers.firstWhere((s) => s.id == selectedId);
  JournalSession get session => repo.sessions[selectedId]!;
  static const pages = [
    ('servers', 'Серверы', Icons.dns_outlined),
    ('software', 'ПО и версии', Icons.inventory_2_outlined),
    ('journal', 'Журнал', Icons.subject_outlined),
    ('metrics', 'Ресурсы', Icons.monitor_heart_outlined),
    ('jobs', 'Задания', Icons.playlist_add_check_outlined),
  ];
  @override
  void dispose() {
    _live?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1000;
      return Scaffold(
        body: Row(
          children: [
            Container(
              width: wide ? 210 : 78,
              color: const Color(0xFF101925),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: wide
                        ? const FittedBox(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.layers_outlined, color: _accent),
                                SizedBox(width: 10),
                                Text(
                                  'ServerDeck',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const Icon(Icons.layers_outlined, color: _accent),
                  ),
                  ...pages.map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Tooltip(
                        message: item.$2,
                        child: Material(
                          color: page == item.$1
                              ? _accent.withValues(alpha: .12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            key: ValueKey('nav-${item.$1}'),
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => setState(() => page = item.$1),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                mainAxisAlignment: wide
                                    ? MainAxisAlignment.start
                                    : MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    item.$3,
                                    color: page == item.$1 ? _accent : _muted,
                                    size: 22,
                                  ),
                                  if (wide) ...[
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        item.$2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: page == item.$1
                                              ? _accent
                                              : _muted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: wide
                        ? const Text(
                            'LOCAL FIRST\nM0 · fixture preview',
                            style: TextStyle(
                              color: _muted,
                              fontSize: 11,
                              height: 1.8,
                            ),
                          )
                        : const Icon(Icons.computer, color: _muted),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFF253246)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            pages.firstWhere((p) => p.$1 == page).$2,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const StatusBadge('ДЕМО · без подключений', _warning),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.science_outlined,
                          color: _warning,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Синтетические данные. Изменения живут только в этой сессии.',
                            style: TextStyle(color: _muted, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: switch (page) {
                        'software' => _software(),
                        'journal' => _journal(),
                        'metrics' => _metrics(),
                        'jobs' => _jobs(),
                        _ => _servers(),
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _heading(String title, String subtitle, {Widget? action}) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(color: _muted, height: 1.5),
              ),
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: 12), action],
      ],
    ),
  );

  Widget _serverPicker() => DropdownButtonFormField<String>(
    key: ValueKey('server-picker-$page-$selectedId'),
    initialValue: selectedId,
    decoration: const InputDecoration(
      labelText: 'Тестовый сервер',
      isDense: true,
    ),
    items: repo.servers
        .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
        .toList(),
    onChanged: (id) => setState(() => selectedId = id!),
  );

  Widget _servers() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(
        'Ваши серверы',
        'Наблюдения, версии и состояние в одном месте.',
        action: FilledButton.icon(
          onPressed: () => _profileDialog(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Добавить fixture'),
        ),
      ),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          SummaryTile('ПРОФИЛЕЙ', '${repo.servers.length}', 'локальная сессия'),
          SummaryTile(
            'ONLINE · DEMO',
            '${repo.servers.where((s) => s.state == 'online').length}',
            'имитация связи',
          ),
          SummaryTile(
            'ПО',
            '${FixtureRepository.software.length}',
            'с источником версии',
          ),
        ],
      ),
      const SizedBox(height: 24),
      ...repo.servers.map(
        (server) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.dns_outlined,
                      color: server.id == selectedId ? _accent : _muted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            server.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${server.user}@${server.endpoint}:${server.port}',
                            style: const TextStyle(color: _muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    StatusBadge(
                      server.state,
                      server.state == 'online' ? _accent : _warning,
                    ),
                    PopupMenuButton<String>(
                      key: ValueKey('profile-menu-${server.id}'),
                      tooltip: 'Профиль',
                      onSelected: (value) {
                        if (value == 'edit') {
                          _profileDialog(existing: server);
                        }
                        if (value == 'remove') {
                          _removeProfile(server);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Редактировать fixture'),
                        ),
                        if (repo.servers.length > 1)
                          const PopupMenuItem(
                            value: 'remove',
                            child: Text('Удалить профиль fixture'),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: server.tags
                      .map((tag) => StatusBadge(tag, _muted))
                      .toList(),
                ),
                const SizedBox(height: 12),
                Text(
                  server.state == 'unknown'
                      ? 'Наблюдений ещё нет'
                      : 'Наблюдение: ${_time(server.observedAt)}${server.state == 'offline' ? ' · устарело, прошлые данные сохранены' : ' · demo'}',
                  style: TextStyle(
                    color: server.state == 'offline' ? _warning : _muted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        selectedId = server.id;
                        allSoftware = false;
                        page = 'software';
                      }),
                      child: const Text('ПО и службы →'),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        selectedId = server.id;
                        page = 'journal';
                      }),
                      child: const Text('Открыть журнал →'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  Widget _software() {
    final items = FixtureRepository.software
        .where(
          (s) =>
              repo.servers.any((host) => host.id == s.serverId) &&
              (allSoftware || s.serverId == selectedId) &&
              '${s.name} ${s.version} ${s.unit}'.toLowerCase().contains(
                softwareQuery.toLowerCase(),
              ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'Реестр установленного ПО',
          'Пакет, версия и служба — разные наблюдения.',
        ),
        _serverPicker(),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: softwareQuery,
                onChanged: (v) => setState(() => softwareQuery = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Поиск ПО, версии или службы',
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilterChip(
              label: const Text('Все серверы'),
              selected: allSoftware,
              onSelected: (v) => setState(() => allSoftware = v),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (items.isEmpty)
          const Panel(
            child: Text(
              'Нет совпадений. Пустой список не подтверждает успешное сканирование.',
            ),
          ),
        ...items.map((item) {
          final host = repo.servers
              .where((s) => s.id == item.serverId)
              .firstOrNull;
          if (host == null) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      StatusBadge(
                        item.state,
                        item.state == 'active' ? _accent : _warning,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      Text('Версия: ${item.version ?? 'неизвестна'}'),
                      Text(
                        'Источник: ${item.source}',
                        style: const TextStyle(color: _muted),
                      ),
                      Text(host.name, style: const TextStyle(color: _accent)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    item.unit,
                    style: const TextStyle(
                      fontFamily: 'Consolas',
                      color: _muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.confidence,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                  if (host.state == 'offline')
                    const Text(
                      'Устаревшее наблюдение · связь потеряна',
                      style: TextStyle(color: _warning, fontSize: 12),
                    ),
                  TextButton(
                    onPressed: () => setState(() {
                      selectedId = item.serverId;
                      session.unit = item.unit;
                      page = 'journal';
                    }),
                    child: const Text('Журнал этой службы →'),
                  ),
                ],
              ),
            ),
          );
        }),
        const Panel(
          child: Text(
            'Docker / Kubernetes: адаптеры не реализованы.\nCustom binary: версия может быть неизвестна.',
            style: TextStyle(color: _muted, height: 1.7),
          ),
        ),
      ],
    );
  }

  Widget _journal() {
    final state = session;
    final units = {
      'all',
      ...repo.installed(selectedId).map((s) => s.unit),
      ...state.journal.records.map((r) => r.unit),
    }.toList();
    final records = state.visible(DateTime.now().toUtc());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'Журнал systemd',
          'История + поток · локальное время с UTC-смещением',
        ),
        _serverPicker(),
        const SizedBox(height: 14),
        TextFormField(
          key: ValueKey('journal-search-$selectedId'),
          initialValue: state.query,
          onChanged: (v) => setState(() => state.query = v),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Поиск по сообщению',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 270,
              child: DropdownButtonFormField<String>(
                key: ValueKey('unit-$selectedId-${state.unit}'),
                initialValue: state.unit,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Служба',
                  isDense: true,
                ),
                items: units
                    .map(
                      (u) => DropdownMenuItem(
                        value: u,
                        child: Text(
                          u == 'all' ? 'Все службы' : u,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => state.unit = v!),
              ),
            ),
            SizedBox(
              width: 165,
              child: DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: state.maxPriority,
                key: ValueKey('priority-$selectedId'),
                decoration: const InputDecoration(
                  labelText: 'Приоритет',
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 7, child: Text('Все (0–7)')),
                  DropdownMenuItem(value: 4, child: Text('Warning ≤4')),
                  DropdownMenuItem(value: 3, child: Text('Error ≤3')),
                ],
                onChanged: (v) => setState(() => state.maxPriority = v!),
              ),
            ),
            SizedBox(
              width: 165,
              child: DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: state.minutes,
                key: ValueKey('period-$selectedId'),
                decoration: const InputDecoration(
                  labelText: 'Период',
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Вся история')),
                  DropdownMenuItem(value: 1, child: Text('1 минута')),
                  DropdownMenuItem(value: 5, child: Text('5 минут')),
                ],
                onChanged: (v) => setState(() => state.minutes = v!),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('journal-pause'),
              onPressed: () => setState(state.togglePause),
              icon: Icon(state.paused ? Icons.play_arrow : Icons.pause),
              label: Text(
                state.paused
                    ? 'Возобновить (${state.pending})'
                    : 'Пауза отображения',
              ),
            ),
            OutlinedButton.icon(
              onPressed: _toggleLive,
              icon: const Icon(Icons.sensors),
              label: Text(
                _liveServer == selectedId
                    ? 'Остановить demo-поток'
                    : 'Demo-поток',
              ),
            ),
            TextButton(
              onPressed: () => setState(() => repo.appendEvent(selectedId)),
              child: const Text('+ Тестовое событие'),
            ),
            TextButton(
              onPressed: _historyDialog,
              child: Text('История: ${state.historyLimit}'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  StatusBadge(
                    '${state.journal.records.length}/500 в памяти',
                    _accent,
                  ),
                  StatusBadge('Переполнение: ${state.journal.dropped}', _muted),
                  StatusBadge(
                    'Ошибки: ${state.journal.malformed + state.journal.oversized}',
                    _muted,
                  ),
                  StatusBadge('Пропуски: ${state.journal.gaps}', _muted),
                  StatusBadge('Дубликаты: ${state.journal.duplicates}', _muted),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                selected.state == 'offline'
                    ? 'Нет связи · сохранена demo-история'
                    : selected.state == 'unknown'
                    ? 'Нет наблюдений · источник не проверен'
                    : _liveServer == selectedId
                    ? 'Поток синтетических событий активен'
                    : 'Поток остановлен · история demo',
                style: const TextStyle(color: _warning, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (records.isEmpty)
          const Panel(child: Text('Нет событий, подходящих фильтрам.')),
        ...records.map(
          (r) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: _panel,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () => _recordDialog(r),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          Text(
                            _time(r.at),
                            style: const TextStyle(color: _muted, fontSize: 11),
                          ),
                          Text(
                            'P${r.priority}',
                            style: TextStyle(
                              color: r.priority <= 3 ? _warning : _accent,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            r.unit,
                            style: const TextStyle(color: _muted, fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      SelectableText(
                        r.message,
                        style: const TextStyle(
                          fontFamily: 'Consolas',
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _metrics() {
    final metrics = repo.metrics(selected);
    Widget metric(
      String label,
      Observation<double> value,
      String unit,
      String detail,
    ) {
      final stale = value.isStale(DateTime.now().toUtc());
      return SizedBox(
        width: 270,
        child: Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: _muted)),
              const SizedBox(height: 12),
              Text(
                value.value == null
                    ? 'Недоступно'
                    : '${value.value!.toStringAsFixed(1)} $unit',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                value.value == null ? 'Статус: ${value.status.name}' : detail,
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              StatusBadge(
                stale
                    ? 'Устарело'
                    : value.value == null
                    ? 'Нет значения'
                    : 'Demo-наблюдение',
                stale || value.value == null ? _warning : _accent,
              ),
              const SizedBox(height: 8),
              Text(
                _time(value.observedAt),
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'Ресурсы хоста',
          'Значение без свежего наблюдения не означает здоровый сервер.',
        ),
        _serverPicker(),
        const SizedBox(height: 20),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            metric(
              'CPU',
              metrics.cpu,
              '%',
              'Интервальный показатель · fixture',
            ),
            metric('RAM', metrics.ram, 'GiB', '5.2 / 16 GiB · fixture'),
            metric('DISK', metrics.disk, '%', '38.6 / 100 GiB · fixture'),
            metric('NETWORK', metrics.network, 'MiB/s', 'Адаптер недоступен'),
          ],
        ),
        const SizedBox(height: 20),
        Panel(
          child: Text(
            'Uptime: ${metrics.uptime ?? 'неизвестно'}\n'
            'CPU/RAM службы: недоступно в M0\nПорог устаревания: 15 секунд. Нули не подставляются вместо неизвестных значений.',
            style: const TextStyle(color: _muted, height: 1.8),
          ),
        ),
      ],
    );
  }

  Widget _jobs() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading('План установки', 'Предпросмотр M0 · задания не запускаются.'),
      _serverPicker(),
      const SizedBox(height: 16),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'PostgreSQL', label: Text('PostgreSQL')),
          ButtonSegment(value: 'ClickHouse', label: Text('ClickHouse')),
        ],
        selected: {recipe},
        onSelectionChanged: (values) => setState(() => recipe = values.single),
      ),
      const SizedBox(height: 20),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$recipe · ${recipe == 'PostgreSQL' ? '18.6' : '26.8.17.4 LTS'}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const StatusBadge(
              'Кандидат · совместимость не проверена',
              _warning,
            ),
            const SizedBox(height: 20),
            Text(
              'Хост: ${selected.name} (fixture)\nUbuntu 24.04 · amd64\n'
              'Режим: свежая установка; adoption требует отдельного плана\n'
              'APT pins: ${recipe == 'PostgreSQL' ? '18.6-3.pgdg24.04+1' : '26.8.17.4 (server/client/common-static)'}',
              style: const TextStyle(height: 1.9),
            ),
            const Divider(height: 32),
            const Text(
              'Планируемые шаги',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            const Text(
              '1. Проверить SSH identity, ОС, доступность версии и существующие данные\n'
              '2. Проверить ограниченные полномочия, remote lock и рецепт\n'
              '3. Показать check-mode прогноз и получить разрешение для этого хоста\n'
              '4. Выполнить рецепт через Linux Ansible Runner\n'
              '5. Проверить фактическую версию, unit и приложение',
              style: TextStyle(color: _muted, height: 1.9),
            ),
            const Divider(height: 32),
            const Text(
              'Выполнение закрыто: нужен проверенный privilege helper, pinned image\n'
              'и испытание рецепта на одноразовой systemd VM. NetBird защищён.',
              style: TextStyle(color: _warning, height: 1.7),
            ),
            const SizedBox(height: 20),
            const FilledButton(
              key: ValueKey('execute-job'),
              onPressed: null,
              child: Text('Запустить установку · недоступно в M0'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      const Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Долговечные задания · следующий этап',
              style: TextStyle(fontSize: 18),
            ),
            SizedBox(height: 12),
            Text(
              'queued → preflight → awaiting-approval → running → verified result\n'
              'Сбой: unknown → reconciling. Повторная запись блокируется до сверки.\n'
              'Отмена не означает откат. Выход из приложения не означает остановку задания.',
              style: TextStyle(color: _muted, height: 1.9),
            ),
          ],
        ),
      ),
    ],
  );

  void _toggleLive() {
    if (_liveServer == selectedId) {
      _live?.cancel();
      setState(() => _liveServer = null);
      return;
    }
    _live?.cancel();
    final id = selectedId;
    setState(() => _liveServer = id);
    _live = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && repo.sessions.containsKey(id)) {
        setState(() => repo.appendEvent(id));
      }
    });
  }

  Future<void> _recordDialog(JournalRecord record) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Поля journal · demo'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: SelectableText(
            const JsonEncoder.withIndent('  ').convert(record.toJson()),
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(
              ClipboardData(
                text: const JsonEncoder.withIndent('  ')
                    .convert(record.toJson()),
              ),
            );
          },
          child: const Text('Копировать поля'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
      ],
    ),
  );

  Future<void> _historyDialog() async {
    var historyText = '${session.historyLimit}';
    final form = GlobalKey<FormState>();
    final id = selectedId;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Объём demo-истории'),
        content: Form(
          key: form,
          child: TextFormField(
            initialValue: historyText,
            onChanged: (value) => historyText = value,
            decoration: const InputDecoration(
              labelText: '1…1000 строк (буфер максимум 500)',
            ),
            keyboardType: TextInputType.number,
            validator: (v) {
              final count = int.tryParse(v ?? '');
              return count == null || count < 1 || count > 1000
                  ? 'Укажите число от 1 до 1000'
                  : null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                setState(() => repo.loadHistory(id, int.parse(historyText)));
                Navigator.pop(context);
              }
            },
            child: const Text('Загрузить fixture'),
          ),
        ],
      ),
    );
  }

  Future<void> _profileDialog({ServerProfile? existing}) async {
    var name = existing?.name ?? 'Disposable Lab';
    var endpoint = existing?.endpoint ?? 'disposable.invalid';
    var port = '${existing?.port ?? 22}';
    final form = GlobalKey<FormState>();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          existing == null ? 'Добавить demo-профиль' : 'Изменить demo-профиль',
        ),
        content: SizedBox(
          width: 420,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Без сохранения на диск и без SSH-подключения.',
                  style: TextStyle(color: _warning),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: name,
                  onChanged: (value) => name = value,
                  key: const ValueKey('profile-name'),
                  decoration: const InputDecoration(labelText: 'Имя'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Нужно имя' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: endpoint,
                  onChanged: (value) => endpoint = value,
                  key: const ValueKey('profile-endpoint'),
                  decoration: const InputDecoration(
                    labelText: 'Адрес fixture (.invalid)',
                  ),
                  validator: (v) =>
                      v == null ||
                          !RegExp(r'^[a-zA-Z0-9.-]+\.invalid$')
                              .hasMatch(v.trim())
                      ? 'Используйте тестовый домен .invalid'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: port,
                  onChanged: (value) => port = value,
                  key: const ValueKey('profile-port'),
                  decoration: const InputDecoration(labelText: 'SSH порт'),
                  validator: (v) {
                    final p = int.tryParse(v ?? '');
                    return p == null || p < 1 || p > 65535
                        ? 'Порт 1…65535'
                        : null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) {
                return;
              }
              setState(() {
                final value = ServerProfile(
                  id:
                      existing?.id ??
                      'fixture-${DateTime.now().microsecondsSinceEpoch}',
                  name: name.trim(),
                  endpoint: endpoint.trim(),
                  port: int.parse(port),
                  tags: existing?.tags ?? ['fixture'],
                  observedAt: existing?.observedAt ?? DateTime.now().toUtc(),
                  state: existing?.state ?? 'unknown',
                );
                if (existing == null) {
                  repo.add(value);
                } else {
                  repo.servers[repo.servers.indexOf(existing)] = value;
                }
              });
              Navigator.pop(context);
            },
            child: const Text('Сохранить в сессии'),
          ),
        ],
      ),
    );
  }

  void _removeProfile(ServerProfile server) {
    setState(() {
      if (_liveServer == server.id) {
        _live?.cancel();
        _liveServer = null;
      }
      repo.remove(server.id);
      if (selectedId == server.id) {
        selectedId = repo.servers.first.id;
      }
    });
  }
}

String _time(DateTime at) {
  final local = at.toLocal();
  final offset = local.timeZoneOffset;
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(local.hour)}:${pad(local.minute)}:${pad(local.second)} UTC${offset.isNegative ? '-' : '+'}'
      '${pad(offset.inHours.abs())}:${pad(offset.inMinutes.abs() % 60)}';
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFF253246)),
    ),
    child: child,
  );
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, this.color, {super.key});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500),
    ),
  );
}

class SummaryTile extends StatelessWidget {
  const SummaryTile(this.label, this.value, this.note, {super.key});
  final String label, value, note;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 185,
    child: Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _muted,
              fontSize: 11,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w600),
          ),
          Text(note, style: const TextStyle(color: _muted, fontSize: 11)),
        ],
      ),
    ),
  );
}
