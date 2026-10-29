import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

import '../theme/brand_theme.dart';
import '../theme/brand_tokens.dart';
import '../ui/deck_components.dart';
import '../ui/deck_icon.dart';

/// Bounded source-order observations. Presentation never samples or polls.
class MetricsHistory extends StatefulWidget {
  const MetricsHistory({
    super.key,
    required this.points,
    this.quality,
    this.stale = false,
    this.source,
    this.observedAt,
    this.receivedAt,
    this.actions,
    this.showPlots = true,
    this.showHeading = true,
  });

  final List<Object?> points;
  final String? quality, source, observedAt, receivedAt;
  final bool stale, showPlots, showHeading;
  final Widget? actions;

  @override
  State<MetricsHistory> createState() => _MetricsHistoryState();
}

class _MetricsHistoryState extends State<MetricsHistory> {
  bool _expanded = false;
  final _valuesSectionKey = GlobalKey();
  final _valuesQualityKey = GlobalKey();
  final _valuesController = ScrollController();
  final _valuesFocus = FocusNode(debugLabel: 'History values scroll area');
  int _valuesRevealEpoch = 0;

  @override
  void dispose() {
    _valuesController.dispose();
    _valuesFocus.dispose();
    super.dispose();
  }

  KeyEventResult _scrollValues(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final up = event.logicalKey == LogicalKeyboardKey.pageUp;
    final down = event.logicalKey == LogicalKeyboardKey.pageDown;
    if ((!up && !down) || !_expanded || !_valuesController.hasClients) {
      return KeyEventResult.ignored;
    }
    final position = _valuesController.position;
    final increment = position.viewportDimension * .8 * (up ? -1 : 1);
    // Paging owns the scroll area's visible focus. A focused selectable row
    // would otherwise remain alive outside the viewport and reveal itself
    // again when its owner rebuilds. Invalidate its queued reveal as well:
    // that callback may run after the focus has moved to the scroll area.
    _valuesRevealEpoch++;
    _valuesFocus.requestFocus();
    _valuesController.jumpTo(
      (position.pixels + increment).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    return KeyEventResult.handled;
  }

  void _revealValuesQuality([BuildContext? row]) {
    final epoch = _valuesRevealEpoch;
    // EditableText reveals its caret after focus. Reveal the bounded section
    // afterwards so that its quality header remains visible with the rows.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_expanded ||
          !_valuesFocus.hasFocus ||
          epoch != _valuesRevealEpoch) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final section = _valuesSectionKey.currentContext;
        if (!mounted ||
            !_expanded ||
            !_valuesFocus.hasFocus ||
            epoch != _valuesRevealEpoch ||
            section == null) {
          return;
        }
        final quality = _valuesQualityKey.currentContext;
        final revealRow = row?.mounted == true && !_fullyVisible(row!);
        final revealSection = _valuesFocus.hasPrimaryFocus
            ? !_fullyVisible(section)
            : quality != null && !_fullyVisible(quality);
        if (revealRow) {
          unawaited(Scrollable.ensureVisible(row));
        }
        if (revealRow || revealSection) {
          unawaited(Scrollable.ensureVisible(section, alignment: .5));
        }
      });
      WidgetsBinding.instance.scheduleFrame();
    });
  }

  bool _fullyVisible(BuildContext target) {
    final box = target.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    bool containedBy(Rect bounds) =>
        rect.left >= bounds.left - .1 &&
        rect.right <= bounds.right + .1 &&
        rect.top >= bounds.top - .1 &&
        rect.bottom <= bounds.bottom + .1;
    var visible = containedBy(Offset.zero & MediaQuery.sizeOf(target));
    target.visitAncestorElements((element) {
      if (element.widget is Scrollable) {
        final viewport = element.findRenderObject();
        if (viewport is RenderBox && viewport.hasSize) {
          visible =
              visible &&
              containedBy(viewport.localToGlobal(Offset.zero) & viewport.size);
        }
      }
      return visible;
    });
    return visible;
  }

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final point in widget.points.take(120))
        point is Map<String, Object?> ? point : const <String, Object?>{},
    ];
    final stale = widget.stale || widget.quality == 'stale';
    final colors = Theme.of(context).extension<BrandColors>()!;
    final quality = stale ? 'stale' : widget.quality;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeading)
          const DeckSectionHeader(
            title: 'История ресурсов',
            description: 'До 10 минут · значения от 0 до 100%',
          ),
        const SizedBox(height: BrandSpacing.space8),
        if (widget.source != null) Text('Источник: ${widget.source}'),
        if (widget.observedAt != null)
          Text('Наблюдение: ${widget.observedAt} · UTC'),
        if (widget.receivedAt != null)
          Text('Получено: ${widget.receivedAt} · UTC'),
        if (rows.isEmpty) const Text('Истории пока нет.'),
        if (_hasMissingValues(rows))
          const Text(
            'В истории есть пропуски значений; они не заменены нулями.',
          ),
        const SizedBox(height: BrandSpacing.space12),
        if (!widget.showPlots)
          DeckStatus(
            key: const ValueKey('metrics-history-plot-quality'),
            label: _qualityLabel(quality),
            tone: _qualityTone(quality),
          ),
        if (widget.showPlots)
          LayoutBuilder(
            builder: (context, constraints) {
              final viewport = MediaQuery.sizeOf(context).width;
              final phone = viewport <= BrandGeometry.phoneBreakpoint;
              final preferred = viewport > BrandGeometry.compactBreakpoint
                  ? 300.0
                  : 270.0;
              final width = math.min(preferred, constraints.maxWidth);
              final plots = SizedBox(
                key: const ValueKey('metrics-history-plots'),
                width: width,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DeckStatus(
                      key: const ValueKey('metrics-history-plot-quality'),
                      label: _qualityLabel(quality),
                      tone: _qualityTone(quality),
                    ),
                    const SizedBox(height: BrandSpacing.space8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (
                          var index = 0;
                          index < _series.length;
                          index++
                        ) ...[
                          if (index > 0)
                            const SizedBox(width: BrandSpacing.space8),
                          Expanded(
                            child: _SeriesPlot(
                              series: _series[index],
                              rows: rows,
                              color: colors[_series[index].role],
                              grid: colors['border'],
                              stale: stale,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
              final actions = widget.actions;
              if (actions == null) {
                return Align(alignment: Alignment.centerRight, child: plots);
              }
              final minimumActions =
                  280 * MediaQuery.textScalerOf(context).scale(14) / 14;
              if (!phone &&
                  constraints.maxWidth >=
                      width + BrandSpacing.space24 + minimumActions) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: KeyedSubtree(
                        key: const ValueKey('server-overview-actions'),
                        child: actions,
                      ),
                    ),
                    const SizedBox(width: BrandSpacing.space24),
                    plots,
                  ],
                );
              }
              final actionGroup = KeyedSubtree(
                key: const ValueKey('server-overview-actions'),
                child: actions,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!phone) ...[
                    actionGroup,
                    const SizedBox(height: BrandSpacing.space16),
                  ],
                  Align(alignment: Alignment.centerRight, child: plots),
                  if (phone) ...[
                    const SizedBox(height: BrandSpacing.space16),
                    actionGroup,
                  ],
                ],
              );
            },
          ),
        const SizedBox(height: BrandSpacing.space12),
        Align(
          alignment: Alignment.centerLeft,
          child: Semantics(
            expanded: _expanded,
            child: TextButton.icon(
              clipBehavior: Clip.none,
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Transform.rotate(
                angle: _expanded ? math.pi : 0,
                child: const DeckIcon('chevron'),
              ),
              label: const Text('Значения истории'),
            ),
          ),
        ),
        if (_expanded)
          ConstrainedBox(
            key: _valuesSectionKey,
            constraints: const BoxConstraints(minHeight: 44, maxHeight: 280),
            child: Focus(
              key: const ValueKey('metrics-history-values-focus'),
              focusNode: _valuesFocus,
              onKeyEvent: _scrollValues,
              onFocusChange: (focused) {
                if (!mounted) return;
                setState(() {});
                if (focused) _revealValuesQuality();
              },
              child: Semantics(
                label: 'Текстовые значения истории. Page Up и Page Down прокручивают значения.',
                child: Container(
                  padding: const EdgeInsets.all(BrandGeometry.focusGap),
                  decoration: BoxDecoration(
                    border: Border.all(
                      width: BrandGeometry.focusWidth,
                      color: _valuesFocus.hasFocus
                          ? colors['focus']
                          : Colors.transparent,
                    ),
                  ),
                  child: Column(
                    key: const ValueKey('metrics-history-values-section'),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      KeyedSubtree(
                        key: _valuesQualityKey,
                        child: DeckStatus(
                          key: const ValueKey('metrics-history-values-quality'),
                          label: _qualityLabel(quality),
                          tone: _qualityTone(quality),
                        ),
                      ),
                      Flexible(
                        child: FocusTraversalGroup(
                          policy: OrderedTraversalPolicy(),
                          child: ListView.builder(
                            key: const ValueKey('metrics-history-values'),
                            controller: _valuesController,
                            primary: false,
                            shrinkWrap: true,
                            // A scaled row can be taller than the viewport.
                            // Keep its adjacent row available for Shift+Tab
                            // without retaining all 120 samples or focus nodes.
                            scrollCacheExtent: ScrollCacheExtent.pixels(
                              MediaQuery.textScalerOf(context).scale(400),
                            ),
                            itemCount: rows.length,
                            itemBuilder: (context, index) {
                              final row = rows[index];
                              final gap = index == 0
                                  ? null
                                  : _gapReason(rows[index - 1], row);
                              return FocusTraversalOrder(
                                order: NumericFocusOrder(index.toDouble()),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: BrandSpacing.space4,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (gap != null)
                                        Text(
                                          'Разрыв перед наблюдением ${index + 1}: $gap',
                                        ),
                                      _HistoryValue(
                                        '${_timeLabel(row)} · CPU: ${_valueLabel(row['cpuPercent'])} · RAM: ${_valueLabel(row['memoryUsedPercent'])} · Диск /: ${_valueLabel(row['rootDiskUsedPercent'])}',
                                        style: BrandTypography.table.copyWith(
                                          color: colors['text'],
                                        ),
                                        onFocus: _revealValuesQuality,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HistoryValue extends StatefulWidget {
  const _HistoryValue(this.text, {required this.style, required this.onFocus});
  final String text;
  final TextStyle style;
  final ValueChanged<BuildContext> onFocus;

  @override
  State<_HistoryValue> createState() => _HistoryValueState();
}

class _HistoryValueState extends State<_HistoryValue> {
  final _focus = FocusNode(debugLabel: 'History value');

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (!mounted) return;
    setState(() {});
    if (_focus.hasFocus) widget.onFocus(context);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    MediaQuery.of(context);
    if (_focus.hasFocus) widget.onFocus(context);
  }

  @override
  void didUpdateWidget(covariant _HistoryValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focus.hasFocus) widget.onFocus(context);
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    key: const ValueKey('metrics-history-row-focus'),
    foregroundPainter: _HistoryFocusPainter(
      Theme.of(context).extension<BrandColors>()!['focus'],
      _focus.hasFocus,
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: BrandGeometry.minTarget,
        minHeight: BrandGeometry.minTarget,
      ),
      child: Padding(
        padding: const EdgeInsets.all(
          BrandGeometry.focusGap + BrandGeometry.focusWidth,
        ),
        child: SelectableText(
          widget.text,
          style: widget.style,
          focusNode: _focus,
        ),
      ),
    ),
  );
}

class _HistoryFocusPainter extends CustomPainter {
  const _HistoryFocusPainter(this.color, this.focused);
  final Color color;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    if (!focused) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(BrandGeometry.focusWidth / 2),
        const Radius.circular(BrandGeometry.radiusControl),
      ),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = BrandGeometry.focusWidth,
    );
  }

  @override
  bool shouldRepaint(covariant _HistoryFocusPainter oldDelegate) =>
      color != oldDelegate.color || focused != oldDelegate.focused;
}

class _Series {
  const _Series(this.id, this.label, this.field, this.role, this.pattern);
  final String id, label, field, role;
  final List<double> pattern;
}

const _series = [
  _Series('cpu', 'CPU', 'cpuPercent', 'accent', []),
  _Series('memory', 'RAM', 'memoryUsedPercent', 'chart2', [6, 4]),
  _Series('disk', 'Диск /', 'rootDiskUsedPercent', 'chart3', [2, 4]),
];

class _SeriesPlot extends StatelessWidget {
  const _SeriesPlot({
    required this.series,
    required this.rows,
    required this.color,
    required this.grid,
    required this.stale,
  });
  final _Series series;
  final List<Map<String, Object?>> rows;
  final Color color, grid;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final pattern = stale ? const <double>[6, 4] : series.pattern;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${series.label} · %', style: BrandTypography.caption),
        Semantics(
          label:
              '${series.label}: ${_patternLabel(pattern)}, ${_symbolLabel(series.id)}',
          child: Align(
            alignment: Alignment.centerLeft,
            child: CustomPaint(
              key: ValueKey('metrics-history-legend-${series.id}'),
              size: const Size(32, 12),
              painter: _LegendPainter(series.id, color, pattern),
            ),
          ),
        ),
        const SizedBox(height: BrandSpacing.space4),
        Semantics(
          label:
              '${series.label}, история в процентах; пропуски означают отсутствие данных',
          child: CustomPaint(
            key: ValueKey('metrics-history-plot-${series.id}'),
            size: const Size(double.infinity, 25),
            painter: _SeriesPainter(rows, series, color, grid, pattern),
          ),
        ),
      ],
    );
  }
}

class _SeriesPainter extends CustomPainter {
  const _SeriesPainter(
    this.rows,
    this.series,
    this.color,
    this.grid,
    this.pattern,
  );
  final List<Map<String, Object?>> rows;
  final _Series series;
  final Color color, grid;
  final List<double> pattern;

  @override
  void paint(Canvas canvas, Size size) {
    final times = rows.map(_time).toList();
    final validTimes = times.whereType<int>();
    if (validTimes.isEmpty) return;
    final start = validTimes.reduce(math.min),
        end = validTimes.reduce(math.max);
    const inset = 3.0;
    final width = math.max(0.0, size.width - 2 * inset);
    final height = math.max(0.0, size.height - 2 * inset);
    for (final percent in [0, 50, 100]) {
      final y = inset + height * (1 - percent / 100);
      canvas.drawLine(
        Offset(inset, y),
        Offset(inset + width, y),
        Paint()..color = grid,
      );
    }
    final path = Path();
    final points = <Offset>[];
    int? last;
    for (var index = 0; index < rows.length; index++) {
      final value = historyPercentValue(rows[index][series.field]),
          time = times[index];
      if (value == null || time == null) {
        last = null;
        continue;
      }
      final x =
          inset +
          (start == end ? width / 2 : width * (time - start) / (end - start));
      final y = inset + height * (1 - value / 100);
      final point = Offset(x, y);
      if (last == null || time <= last || time - last > 15000) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      last = time;
      points.add(point);
    }
    canvas.drawPath(_patternPath(path, pattern), _stroke(color));
    for (final point in points) {
      _drawSymbol(canvas, point, series.id, color);
    }
  }

  @override
  bool shouldRepaint(covariant _SeriesPainter oldDelegate) =>
      oldDelegate.rows != rows ||
      oldDelegate.color != color ||
      oldDelegate.grid != grid ||
      oldDelegate.pattern != pattern;
}

class _LegendPainter extends CustomPainter {
  const _LegendPainter(this.id, this.color, this.pattern);
  final String id;
  final Color color;
  final List<double> pattern;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height / 2)
      ..lineTo(size.width, size.height / 2);
    canvas.drawPath(_patternPath(path, pattern), _stroke(color));
    _drawSymbol(canvas, Offset(size.width / 2, size.height / 2), id, color);
  }

  @override
  bool shouldRepaint(covariant _LegendPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.pattern != pattern;
}

Paint _stroke(Color color) => Paint()
  ..color = color
  ..strokeWidth = 2
  ..style = PaintingStyle.stroke;

Path _patternPath(Path path, List<double> pattern) {
  if (pattern.isEmpty) return path;
  final dashed = Path();
  for (final metric in path.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      dashed.addPath(
        metric.extractPath(
          distance,
          math.min(distance + pattern[0], metric.length),
        ),
        Offset.zero,
      );
      distance += pattern[0] + pattern[1];
    }
  }
  return dashed;
}

void _drawSymbol(Canvas canvas, Offset point, String id, Color color) {
  final paint = Paint()..color = color;
  switch (id) {
    case 'cpu':
      canvas.drawCircle(point, 2.5, paint);
    case 'memory':
      canvas.drawRect(
        Rect.fromCenter(center: point, width: 5, height: 5),
        paint,
      );
    case 'disk':
      canvas.drawPath(
        Path()
          ..moveTo(point.dx, point.dy - 3)
          ..lineTo(point.dx + 3, point.dy + 2.5)
          ..lineTo(point.dx - 3, point.dy + 2.5)
          ..close(),
        paint,
      );
  }
}

/// Shared plot/text projection: invalid samples remain gaps, never coercions.
int? historyPercentValue(Object? value) =>
    value is int && value >= 0 && value <= 100 ? value : null;
int? _time(Map<String, Object?> row) =>
    DateTime.tryParse('${row['receivedAt']}')?.millisecondsSinceEpoch;
String _timeLabel(Map<String, Object?> row) {
  final value = DateTime.tryParse('${row['receivedAt']}');
  return value == null
      ? 'Время не указано'
      : '${value.toUtc().toIso8601String()} UTC';
}

String _valueLabel(Object? value) =>
    historyPercentValue(value) == null ? 'нет данных' : '$value%';
bool _hasMissingValues(List<Map<String, Object?>> rows) => rows.any(
  (row) =>
      _series.any((series) => historyPercentValue(row[series.field]) == null),
);
String? _gapReason(Map<String, Object?> previous, Map<String, Object?> next) {
  final first = _time(previous), second = _time(next);
  if (first == null || second == null) return 'время не указано';
  if (second == first) return 'время наблюдения повторилось';
  if (second < first) return 'время наблюдения идёт в обратном порядке';
  if (second - first > 15000) return 'между наблюдениями больше 15 секунд';
  return null;
}

String _patternLabel(List<double> pattern) => pattern.isEmpty
    ? 'сплошная линия'
    : 'пунктир ${pattern[0].toInt()}/${pattern[1].toInt()}';
String _symbolLabel(String id) => switch (id) {
  'cpu' => 'круг',
  'memory' => 'квадрат',
  _ => 'треугольник',
};
String _qualityLabel(String? value) => switch (value) {
  'known' => 'Данные получены',
  'stale' => 'Устаревшие данные',
  'incomplete' => 'Неполные данные',
  'denied' => 'Недостаточно прав',
  'unsupported' => 'Источник не поддерживается',
  'error' => 'Ошибка чтения',
  _ => 'Качество истории не указано',
};
DeckTone _qualityTone(String? value) => switch (value) {
  'known' => DeckTone.available,
  'stale' || 'incomplete' || 'denied' || 'unsupported' => DeckTone.warning,
  'error' => DeckTone.error,
  _ => DeckTone.unknown,
};
