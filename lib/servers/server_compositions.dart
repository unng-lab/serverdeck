import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:serverdeck_protocol/models.dart' show ProfileView;

import '../theme/brand_assets.dart';
import '../theme/brand_theme.dart';
import '../ui/deck_components.dart';
import '../ui/deck_icon.dart';
import '../ui/deck_page.dart';
import '../ui/deck_workspace_overlay.dart';
import 'metrics_history.dart' show historyPercentValue;

/// Shared production page chrome. Data, selection and callbacks stay with the
/// current owner; rendering this frame never starts an operation.
class ServerPageFrame extends StatelessWidget {
  const ServerPageFrame({
    super.key,
    required this.profile,
    required this.title,
    this.description,
    this.eyebrow = 'Серверы / Рабочее пространство',
    this.actions = const [],
    this.contextBar,
    this.selectedTab = 0,
    this.showServerTabs = true,
    this.showIdentity = true,
    this.identityStatus,
    this.contentActions = const [],
    required this.onTabSelected,
    required this.child,
  });
  final ProfileView profile;
  final String title, eyebrow;
  final String? description;
  final List<Widget> actions;
  final Widget? contextBar;
  final int selectedTab;
  final bool showServerTabs;
  final bool showIdentity;
  final Widget? identityStatus;
  final List<Widget> contentActions;
  final ValueChanged<int> onTabSelected;
  final Widget child;
  @override
  Widget build(BuildContext context) => DeckPage(
    title: title,
    description: description,
    eyebrow: eyebrow,
    actions: actions,
    contextBar: contextBar == null && !showIdentity
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (contextBar != null) ...[
                contextBar!,
                const SizedBox(height: 16),
              ],
              if (showIdentity)
                Row(
                  children: [
                    Container(
                      width: MediaQuery.sizeOf(context).width <= 520 ? 42 : 48,
                      height: MediaQuery.sizeOf(context).width <= 520 ? 42 : 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: deckColors(context)['surface'],
                        border: Border.all(
                          color: deckColors(context)['border'],
                        ),
                        borderRadius: BorderRadius.circular(
                          MediaQuery.sizeOf(context).width <= 520 ? 10 : 12,
                        ),
                      ),
                      child: DeckIcon(
                        'server',
                        size: MediaQuery.sizeOf(context).width <= 520 ? 23 : 26,
                        color: deckColors(context)['accent'],
                      ),
                    ),
                    SizedBox(
                      width: MediaQuery.sizeOf(context).width <= 520 ? 10 : 14,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.name,
                            style: BrandTypography.log.copyWith(
                              fontSize: 20,
                              height: 28 / 20,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${profile.address.contains(':') ? '[${profile.address}]' : profile.address}:${profile.port}${profile.tags.isEmpty ? '' : ' · ${profile.tags.join(' · ')}'}',
                            style: BrandTypography.log.copyWith(
                              fontSize: 12,
                              height: 20 / 12,
                              color: deckColors(context)['muted'],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (identityStatus != null) ...[
                      SizedBox(
                        width: MediaQuery.sizeOf(context).width <= 520
                            ? 10
                            : 14,
                      ),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * .35,
                        ),
                        child: identityStatus!,
                      ),
                    ],
                  ],
                ),
              if (showIdentity && MediaQuery.sizeOf(context).width > 520)
                const SizedBox(height: 4),
            ],
          ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showServerTabs) ...[
          DeckTabs(
            labels: const [
              'Обзор',
              'ПО',
              'Ресурсы',
              'Автоматизация',
              'Offline / сохранённые данные',
            ],
            selected: selectedTab,
            onSelected: onTabSelected,
          ),
          const DeckTabsGap(),
        ],
        if (contentActions.isNotEmpty) DeckActions(children: contentActions),
        child,
      ],
    ),
  );
}

/// Both runtime and visual fixtures render these controls with owner callbacks.
/// Availability changes presentation only; the owner still checks each action.
List<Widget> serverPageHeaderActions({
  required bool busy,
  bool connected = false,
  bool logs = false,
  bool changedKey = false,
  VoidCallback? onConnect,
  VoidCallback? onDisconnect,
  VoidCallback? onRefresh,
  VoidCallback? onSearch,
  VoidCallback? onFilters,
}) => changedKey
    ? const []
    : logs
    ? [
        OutlinedButton(
          clipBehavior: Clip.none,
          onPressed: onSearch,
          child: const Text('Поиск'),
        ),
        OutlinedButton(
          clipBehavior: Clip.none,
          onPressed: onFilters,
          child: const Text('Фильтры'),
        ),
      ]
    : [
        OutlinedButton(
          clipBehavior: Clip.none,
          onPressed: busy
              ? null
              : connected
              ? onDisconnect
              : onConnect,
          child: Text(connected ? 'Отключить' : 'Подключить'),
        ),
        OutlinedButton(
          clipBehavior: Clip.none,
          onPressed: busy ? null : onRefresh,
          child: const DeckButtonLabel(
            icon: 'refresh',
            label: 'Обновить данные',
          ),
        ),
      ];

List<Widget> serverOverviewActions({
  required VoidCallback? onSoftware,
  required VoidCallback? onLogs,
}) => [
  FilledButton(
    clipBehavior: Clip.none,
    onPressed: onSoftware,
    child: const Text('Открыть ПО'),
  ),
  OutlinedButton(
    clipBehavior: Clip.none,
    onPressed: onLogs,
    child: const Text('Журнал'),
  ),
];

/// Canonical description-list rows, including separated cell rules.
class ServerFactRowKey extends ValueKey<String> {
  const ServerFactRowKey(super.value);
}

class ServerFactRows extends StatelessWidget {
  const ServerFactRows({
    super.key,
    required this.facts,
    this.tableContext = false,
    this.valueStyles = const {},
    this.valueWidgets = const {},
  });
  final bool tableContext;
  final Map<String, String> facts;
  final Map<String, TextStyle> valueStyles;
  final Map<String, Widget> valueWidgets;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<BrandColors>()!;
    final phone = MediaQuery.sizeOf(context).width <= 520;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = math.max(0.0, constraints.maxWidth - 12);
        final labelWidth = tableContext
            ? math.min(available, math.max(110.0, available * 7 / 27))
            : available * 10 / 23;
        Widget cell(int flex, Widget child) => phone
            ? child
            : flex == 10
            ? SizedBox(width: labelWidth, child: child)
            : Expanded(child: child);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in facts.entries)
              KeyedSubtree(
                key: ServerFactRowKey(entry.key),
                child: Builder(
                  builder: (context) {
                    final row = Flex(
                      direction: phone ? Axis.vertical : Axis.horizontal,
                      mainAxisSize: phone ? MainAxisSize.min : MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        cell(
                          10,
                          Container(
                            padding: phone
                                ? EdgeInsets.only(
                                    top: entry.key == facts.keys.first ? 0 : 12,
                                  )
                                : const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: phone || entry.key == facts.keys.last
                                    ? BorderSide.none
                                    : BorderSide(color: colors['border']),
                              ),
                            ),
                            child: Text(
                              entry.key,
                              style: BrandTypography.caption.copyWith(
                                height: 20 / 12,
                                color: colors['muted'],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: phone ? 0 : 12),
                        cell(
                          13,
                          Container(
                            padding: phone
                                ? EdgeInsets.only(
                                    top: 4,
                                    bottom: entry.key == facts.keys.last
                                        ? 0
                                        : 12,
                                  )
                                : const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: entry.key == facts.keys.last
                                    ? BorderSide.none
                                    : BorderSide(color: colors['border']),
                              ),
                            ),
                            child:
                                valueWidgets[entry.key] ??
                                SelectableText(
                                  entry.value,
                                  style:
                                      valueStyles[entry.key] ??
                                      BrandTypography.log.copyWith(
                                        fontSize: phone ? 13 : 12,
                                        height: phone ? 22 / 13 : 20 / 12,
                                      ),
                                ),
                          ),
                        ),
                      ],
                    );
                    return phone ? row : IntrinsicHeight(child: row);
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class ServerPlanDialog extends StatelessWidget {
  const ServerPlanDialog({
    super.key,
    required this.title,
    required this.child,
    this.asPage = false,
    this.description = 'Сведения, наблюдения и доступные действия',
    this.eyebrow = 'Серверы / Рабочее пространство',
    this.workspaceBounds,
    this.pageInsets,
  });
  final String title, description;
  final Widget child;
  final bool asPage;
  final String eyebrow;
  final ValueGetter<Rect?>? workspaceBounds;
  final ValueGetter<EdgeInsetsGeometry>? pageInsets;
  @override
  Widget build(BuildContext context) {
    final page = DeckPage(
      title: title,
      eyebrow: eyebrow,
      description: description,
      child: child,
    );
    return asPage
        ? page
        : DeckWorkspaceOverlay(
            workspaceBounds: workspaceBounds,
            pageInsets: pageInsets,
            child: page,
          );
  }
}

/// Canonical columns collapse according to available content width.
class ServerColumns extends StatelessWidget {
  const ServerColumns({super.key, required this.left, required this.right});
  final Widget left, right;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide =
          constraints.maxWidth > 600 &&
          MediaQuery.sizeOf(context).width > 760 &&
          MediaQuery.textScalerOf(context).scale(14) <= 14;
      final width = wide
          ? (constraints.maxWidth - 20) / 2
          : constraints.maxWidth;
      // Keep the same element ancestry when direction changes; drafts, focus and
      // the bounded history list belong to their existing stateful children.
      return Flex(
        direction: wide ? Axis.horizontal : Axis.vertical,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: width, child: left),
          SizedBox(width: wide ? 20 : 0, height: wide ? 0 : 20),
          SizedBox(width: width, child: right),
        ],
      );
    },
  );
}

/// Canonical parameters, consequences and the explicit action bar.
class ServerReviewBody extends StatelessWidget {
  const ServerReviewBody({
    super.key,
    required this.facts,
    required this.consequences,
    required this.actions,
    this.factStyles = const {},
  });
  final Map<String, String> facts, consequences;
  final List<Widget> actions;
  final Map<String, TextStyle> factStyles;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DeckPanel(
        title: 'Параметры и условия',
        child: ServerFactRows(facts: facts, valueStyles: factStyles),
      ),
      if (consequences.isNotEmpty) ...[
        SizedBox(height: deckSectionGap(context)),
        DeckPanel(
          title: 'Последствия',
          child: ServerFactRows(facts: consequences),
        ),
      ],
      SizedBox(height: deckSectionGap(context)),
      DeckActions(children: actions),
    ],
  );
}

class ServerStatusBody extends StatelessWidget {
  const ServerStatusBody({
    super.key,
    required this.title,
    required this.facts,
    required this.actions,
    this.icon = 'info',
    this.tone = DeckTone.unknown,
    this.details,
    this.emblemRole,
  });
  final String title, icon;
  final String? emblemRole;
  final Map<String, String> facts;
  final List<Widget> actions;
  final DeckTone tone;
  final Widget? details;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<BrandColors>()!;
    final phone = MediaQuery.sizeOf(context).width <= 520;
    final role = emblemRole ?? (tone == DeckTone.neutral ? 'muted' : tone.name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DeckPanel(
          padding: EdgeInsets.symmetric(
            vertical: phone ? 28 : 30,
            horizontal: phone ? 16 : 20,
          ),
          child: Column(
            children: [
              Container(
                width: phone ? 56 : 64,
                height: phone ? 56 : 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: colors[role]),
                ),
                child: DeckIcon(icon, size: 28, color: colors[role]),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: BrandTypography.body.copyWith(
                  fontSize: phone ? 22 : 20,
                  height: phone ? 30 / 22 : 28 / 20,
                  fontFamily: BrandAssets.semiboldFamily,
                  fontWeight: BrandTypography.semiboldWeight,
                  fontVariations: BrandTypography.semiboldVariations,
                ),
              ),
              const SizedBox(height: 8),
              for (final entry in facts.entries.take(2))
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Text(
                    '${entry.key}: ${entry.value}',
                    textAlign: TextAlign.center,
                    style: BrandTypography.body.copyWith(
                      height: phone ? 24 / 14 : 22 / 14,
                      color: colors['muted'],
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: deckSectionGap(context)),
        DeckPanel(
          title: 'Состояние и следующие шаги',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ServerFactRows(facts: facts),
              if (details != null) details!,
            ],
          ),
        ),
        SizedBox(height: deckSectionGap(context)),
        DeckActions(children: actions),
      ],
    );
  }
}

class ServerResourceCards extends StatelessWidget {
  const ServerResourceCards({super.key, required this.state});
  final Map<String, Object?>? state;
  @override
  Widget build(BuildContext context) {
    final observation = state?['metrics'] as Map<String, Object?>?;
    final value = observation?['value'] as Map<String, Object?>?;
    final memory = value?['memory'] as Map<String, Object?>?;
    final disk = value?['rootDisk'] as Map<String, Object?>?;
    final rows = (state?['history'] as List? ?? const [])
        .whereType<Map<String, Object?>>()
        .toList();
    ({String? main, String unit, String spoken}) percent(Object? value) =>
        value is num
        ? (main: '$value', unit: '%', spoken: '$value %')
        : (main: null, unit: '', spoken: '—');
    ({String? main, String unit, String spoken}) volume(
      Map<String, Object?>? part,
    ) {
      if (part?['usedBytes'] case final num used) {
        if (part?['totalBytes'] case final num total) {
          final main = _gib(used), unit = '/ ${_gib(total)} ГБ';
          return (main: main, unit: unit, spoken: '$main $unit');
        }
      }
      return percent(part?['usedPercent']);
    }

    final cards = [
      (
        label: 'CPU',
        icon: 'cpu',
        field: 'cpuPercent',
        role: 'accent',
        value: percent(value?['cpuPercent']),
        detail: 'Загрузка процессора',
      ),
      (
        label: 'Память',
        icon: 'memory',
        field: 'memoryUsedPercent',
        role: 'chart2',
        value: volume(memory),
        detail: '${memory?['usedPercent'] ?? '—'} % от общего объёма',
      ),
      (
        label: 'Диск /',
        icon: 'disk',
        field: 'rootDiskUsedPercent',
        role: 'running',
        value: volume(disk),
        detail:
            '${disk?['usedPercent'] ?? '—'} % · ${disk?['availableBytes'] is num ? '${_gib(disk!['availableBytes'] as num)} ГБ свободно' : 'Свободный объём не получен'}',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final phone = MediaQuery.sizeOf(context).width <= 520;
        final width = phone || MediaQuery.textScalerOf(context).scale(14) > 14
            ? constraints.maxWidth
            : (constraints.maxWidth - 24) / 3;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final card in cards)
              SizedBox(
                width: width,
                child: DeckSurface(
                  padding: const EdgeInsets.all(16),
                  child: Builder(
                    builder: (context) {
                      final details = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  card.label,
                                  style: BrandTypography.caption.copyWith(
                                    height: 20 / 12,
                                    color: deckColors(context)['muted'],
                                  ),
                                ),
                              ),
                              DeckIcon(
                                card.icon,
                                size: 15,
                                color: deckColors(context)['muted'],
                              ),
                            ],
                          ),
                          SizedBox(height: phone ? 6 : 10),
                          Text.rich(
                            TextSpan(
                              text: card.value.main ?? '—',
                              children: [
                                if (card.value.main != null &&
                                    card.value.unit.isNotEmpty) ...[
                                  const WidgetSpan(child: SizedBox(width: 4)),
                                  TextSpan(
                                    text: card.value.unit,
                                    style: BrandTypography.body.copyWith(
                                      fontSize: 12,
                                      height: 20 / 12,
                                      letterSpacing: 0,
                                      color: deckColors(context)['muted'],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            semanticsLabel: card.value.spoken,
                            style: BrandTypography.body.copyWith(
                              fontFamily: BrandAssets.semiboldFamily,
                              fontWeight: BrandTypography.semiboldWeight,
                              fontVariations:
                                  BrandTypography.semiboldVariations,
                              fontSize:
                                  phone ||
                                      MediaQuery.sizeOf(context).width > 960
                                  ? 26
                                  : 24,
                              height: phone
                                  ? 34 / 26
                                  : 32 /
                                        (MediaQuery.sizeOf(context).width > 960
                                            ? 26
                                            : 24),
                              letterSpacing: -1,
                            ),
                          ),
                          if (!phone) const SizedBox(height: 2),
                          Text(
                            card.value.main == null
                                ? 'Не получено'
                                : card.detail,
                            style: BrandTypography.caption.copyWith(
                              height: 18 / 12,
                              color: deckColors(context)['muted'],
                            ),
                          ),
                        ],
                      );
                      final chart = ServerObservationChart(
                        rows: rows,
                        field: card.field,
                        role: card.role,
                        height: phone ? 45 : 35,
                        stale:
                            observation?['stale'] == true ||
                            observation?['quality'] == 'stale',
                      );
                      return phone
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(child: details),
                                const SizedBox(width: 12),
                                Expanded(child: chart),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                details,
                                const SizedBox(height: 9),
                                chart,
                              ],
                            );
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Real source-order points only; missing values and gaps break the line.
class ServerObservationChart extends StatelessWidget {
  const ServerObservationChart({
    super.key,
    required this.rows,
    this.field = 'cpuPercent',
    this.role = 'accent',
    this.height = 166,
    this.stale = false,
  });
  final List<Map<String, Object?>> rows;
  final String field, role;
  final double height;
  final bool stale;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<BrandColors>()!;
    final axes = height >= 100;
    final boundedRows = rows.take(120).toList(growable: false);
    final scaler = MediaQuery.textScalerOf(context);
    const axisWidth = 28.0;
    final chartHeight =
        axes && height == 166 && MediaQuery.sizeOf(context).width <= 520
        ? 158.0
        : height;
    final plotHeight = chartHeight - 24;
    final times = boundedRows
        .map((r) => DateTime.tryParse('${r['receivedAt']}')?.toUtc())
        .whereType<DateTime>()
        .toList();
    final start = times.isEmpty
        ? null
        : times.reduce((a, b) => a.isBefore(b) ? a : b);
    final end = times.isEmpty
        ? null
        : times.reduce((a, b) => a.isAfter(b) ? a : b);
    String timeLabel(DateTime? value) => value == null
        ? '—'
        : '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    final style = BrandTypography.log.copyWith(
      fontSize: 10,
      height: 1.6,
      color: colors['muted'],
    );
    final plot = CustomPaint(
      painter: _ObservationPainter(
        boundedRows,
        field,
        colors[role],
        colors['border'],
        stale,
        field == 'memoryUsedPercent'
            ? const [6.0, 4.0]
            : field == 'rootDiskUsedPercent'
            ? const [2.0, 4.0]
            : const [],
        !axes,
        axes,
      ),
    );
    final timeLabels = [
      timeLabel(start),
      timeLabel(
        start == null || end == null
            ? null
            : start.add(
                Duration(
                  milliseconds: end.difference(start).inMilliseconds ~/ 2,
                ),
              ),
      ),
      timeLabel(end),
    ];
    return Semantics(
      label:
          'История $field, проценты. Пропуски не заменены нулями.${stale ? ' Сохранённые устаревшие данные.' : ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (axes)
            SizedBox(height: MediaQuery.sizeOf(context).width <= 520 ? 10 : 14),
          if (boundedRows.isEmpty)
            SizedBox(
              height: chartHeight,
              child: const Center(child: Text('Истории пока нет.')),
            )
          else if (!axes)
            SizedBox(height: height, child: plot)
          else ...[
            SizedBox(
              height: plotHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: axisWidth,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (var index = 0; index < 5; index++)
                          Positioned(
                            left: 0,
                            top: plotHeight * index / 4 - 9,
                            width: math.max(axisWidth, scaler.scale(30)),
                            child: Text(
                              '${[100, 75, 50, 25, 0][index]}',
                              style: style,
                              softWrap: false,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(child: plot),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.only(left: axisWidth),
              child: LayoutBuilder(
                builder: (context, constraints) =>
                    constraints.maxWidth >= scaler.scale(170)
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final label in timeLabels)
                            Text(label, style: style),
                        ],
                      )
                    : Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          for (final label in timeLabels)
                            Text(label, style: style),
                        ],
                      ),
              ),
            ),
          ],
          if (axes) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(width: 12, height: 2, color: colors[role]),
                Text(
                  '${field == 'cpuPercent'
                      ? 'CPU'
                      : field == 'memoryUsedPercent'
                      ? 'RAM'
                      : 'Диск /'}, % · UTC',
                  style: BrandTypography.caption.copyWith(
                    color: colors['muted'],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String _gib(num bytes) =>
    (bytes / 1073741824).toStringAsFixed(1).replaceAll('.', ',');

class _ObservationPainter extends CustomPainter {
  const _ObservationPainter(
    this.rows,
    this.field,
    this.color,
    this.grid,
    this.stale,
    this.pattern,
    this.markers,
    this.showGrid,
  );
  final List<Map<String, Object?>> rows;
  final String field;
  final Color color, grid;
  final bool stale, markers, showGrid;
  final List<double> pattern;
  @override
  void paint(Canvas canvas, Size size) {
    for (final fraction in showGrid ? [0.0, .25, .5, .75, 1.0] : <double>[]) {
      canvas.drawLine(
        Offset(0, size.height * fraction),
        Offset(size.width, size.height * fraction),
        Paint()..color = grid,
      );
    }
    final times = rows
        .map(
          (row) =>
              DateTime.tryParse('${row['receivedAt']}')?.millisecondsSinceEpoch,
        )
        .toList();
    final validTimes = times.whereType<int>();
    if (validTimes.isEmpty) return;
    final start = validTimes.reduce(math.min),
        end = validTimes.reduce(math.max);
    final segments = <List<Offset>>[];
    int? previous;
    for (var index = 0; index < rows.length; index++) {
      final value = historyPercentValue(rows[index][field]),
          time = times[index];
      if (value == null || time == null) {
        previous = null;
        continue;
      }
      if (previous == null || time <= previous || time - previous > 15000)
        segments.add([]);
      segments.last.add(
        Offset(
          start == end
              ? size.width / 2
              : size.width * (time - start) / (end - start),
          size.height * (1 - value / 100),
        ),
      );
      previous = time;
    }
    final stroke = Paint()
      ..color = color
      ..strokeWidth = showGrid ? 1.8 : 1.6
      ..style = PaintingStyle.stroke;
    void marker(Offset point) {
      final paint = Paint()..color = color;
      if (field == 'memoryUsedPercent') {
        canvas.drawRect(
          Rect.fromCenter(center: point, width: 4, height: 4),
          paint,
        );
      } else if (field == 'rootDiskUsedPercent') {
        canvas.drawPath(
          Path()
            ..moveTo(point.dx, point.dy - 3)
            ..lineTo(point.dx + 3, point.dy + 2)
            ..lineTo(point.dx - 3, point.dy + 2)
            ..close(),
          paint,
        );
      } else {
        canvas.drawCircle(point, 2, paint);
      }
    }

    for (final points in segments) {
      if (points.length == 1) {
        marker(points.first);
        continue;
      }
      final line = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        line.lineTo(point.dx, point.dy);
      }
      if (!stale) {
        final area = Path.from(line)
          ..lineTo(points.last.dx, size.height)
          ..lineTo(points.first.dx, size.height)
          ..close();
        canvas.drawPath(area, Paint()..color = color.withValues(alpha: .1));
      }
      final dash = stale ? const [6.0, 4.0] : pattern;
      if (markers) marker(points.last);
      if (dash.isEmpty) {
        canvas.drawPath(line, stroke);
        continue;
      }
      for (final metric in line.computeMetrics()) {
        for (
          var offset = 0.0;
          offset < metric.length;
          offset += dash[0] + dash[1]
        ) {
          canvas.drawPath(
            metric.extractPath(
              offset,
              math.min(offset + dash[0], metric.length),
            ),
            stroke,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ObservationPainter oldDelegate) => true;
}
