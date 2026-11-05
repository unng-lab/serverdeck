part of 'deck_history.dart';

/// Page-sized C22 variant. All timestamps and observations come from its owner.
class _FullHistory extends StatefulWidget {
  const _FullHistory({
    required this.rows,
    required this.windowEnd,
    required this.stale,
    this.quality,
  });
  final List<Map<String, Object?>> rows;
  final DateTime windowEnd;
  final bool stale;
  final String? quality;
  @override
  State<_FullHistory> createState() => _FullHistoryState();
}

class _FullHistoryState extends State<_FullHistory> {
  final _focus = FocusNode(debugLabel: 'Resource history charts');
  int? _selected;
  bool _focused = false;
  int get _end => widget.windowEnd.millisecondsSinceEpoch;
  int get _start => _end - const Duration(hours: 1).inMilliseconds;
  List<int> get _times =>
      widget.rows
          .map(_time)
          .whereType<int>()
          .where((time) => time > _start && time <= _end)
          .toSet()
          .toList()
        ..sort();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _hover(double fraction) {
    final times = _times;
    if (times.isEmpty) return;
    final target = _start + (_end - _start) * fraction;
    final time = times.reduce(
      (a, b) => (a - target).abs() < (b - target).abs() ? a : b,
    );
    if (_selected != time) setState(() => _selected = time);
  }

  void _step(int step) {
    final times = _times;
    if (times.isEmpty) return;
    final current = _selected == null
        ? (step < 0 ? times.length : -1)
        : times.indexOf(_selected!);
    setState(
      () => _selected = times[(current + step).clamp(0, times.length - 1)],
    );
  }

  void _edge(bool last) {
    final times = _times;
    if (times.isNotEmpty)
      setState(() => _selected = last ? times.last : times.first);
  }

  @override
  Widget build(BuildContext context) {
    final times = _times;
    final selected = times.contains(_selected) ? _selected : null;
    final readingTime = selected ?? (times.isEmpty ? null : times.last);
    Map<String, Object?>? reading;
    for (final row in widget.rows) {
      if (_time(row) == readingTime) reading = row;
    }
    final colors = Theme.of(context).extension<BrandColors>()!;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _step(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _step(1),
        const SingleActivator(LogicalKeyboardKey.home): () => _edge(false),
        const SingleActivator(LogicalKeyboardKey.end): () => _edge(true),
      },
      child: Focus(
        focusNode: _focus,
        onFocusChange: (value) => setState(() => _focused = value),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Наведите на график, чтобы увидеть замер. Стрелки ← → — выбор с клавиатуры.',
              style: BrandTypography.caption.copyWith(color: colors['muted']),
            ),
            const SizedBox(height: BrandSpacing.space12),
            for (final series in _series) ...[
              DeckSurface(
                key: ValueKey('resource-chart-${series.id}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: BrandSpacing.space16,
                      runSpacing: BrandSpacing.space4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(switch (series.id) {
                          'cpu' => 'Процессор · CPU',
                          'memory' => 'Оперативная память · RAM',
                          _ => 'Корневой диск · /',
                        }, style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          _resourcePercent(reading?[series.field]),
                          key: ValueKey('resource-value-${series.id}'),
                          style: BrandTypography.title.copyWith(
                            color: colors[series.role],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: BrandSpacing.space4),
                    Semantics(
                      liveRegion: _focused,
                      child: Text(
                        readingTime == null
                            ? 'Замеров пока нет'
                            : '${selected == null ? 'Последний замер' : 'Выбранный замер'}: ${_resourceTime(readingTime, seconds: true)} UTC · ${_resourcePercent(reading?[series.field])}',
                        key: ValueKey('resource-reading-${series.id}'),
                        style: BrandTypography.caption.copyWith(
                          color: colors['muted'],
                        ),
                      ),
                    ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final style = BrandTypography.caption.copyWith(
                          color: colors['muted'],
                          fontSize: MediaQuery.textScalerOf(context)
                              .scale(BrandTypography.caption.fontSize ?? 12),
                        );
                        final label = TextPainter(
                          text: TextSpan(text: '100%', style: style),
                          textDirection: TextDirection.ltr,
                        )..layout();
                        final left = label.width + BrandSpacing.space12;
                        final height = 220.0 + label.height * 2;
                        void select(Offset position) => _hover(
                          ((position.dx - left) /
                                  math.max(1, constraints.maxWidth - left - 12))
                              .clamp(0.0, 1.0),
                        );
                        return MouseRegion(
                          cursor: SystemMouseCursors.precise,
                          onHover: (event) => select(event.localPosition),
                          onExit: (_) => setState(() => _selected = null),
                          child: GestureDetector(
                            onTapDown: (event) {
                              _focus.requestFocus();
                              select(event.localPosition);
                            },
                            child: Semantics(
                              label:
                                  '${series.label}: график за последний час, от 0 до 100 процентов, время UTC. Пунктир — порог 90 процентов.',
                              child: CustomPaint(
                                key: ValueKey('resource-plot-${series.id}'),
                                size: Size(constraints.maxWidth, height),
                                painter: _FullResourcePainter(
                                  rows: widget.rows,
                                  series: series,
                                  start: _start,
                                  end: _end,
                                  selected: selected,
                                  color: colors[series.role],
                                  grid: colors['border'],
                                  threshold: colors['error'],
                                  focus: colors['focus'],
                                  style: style,
                                  left: left,
                                  bottom: label.height + 20,
                                  stale: widget.stale,
                                  focused: _focused,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    Wrap(
                      spacing: BrandSpacing.space16,
                      children: [
                        Text(
                          'Время, UTC',
                          style: BrandTypography.caption.copyWith(
                            color: colors['muted'],
                          ),
                        ),
                        Text(
                          'Порог 90%',
                          style: BrandTypography.caption.copyWith(
                            color: colors['muted'],
                          ),
                        ),
                        if (!widget.rows.any(
                          (r) =>
                              _time(r) != null &&
                              _time(r)! > _start &&
                              _time(r)! <= _end &&
                              _validValue(r[series.field]) != null,
                        ))
                          const Text('Нет данных за последний час'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: BrandSpacing.space16),
            ],
            if (widget.rows.isNotEmpty ||
                const [
                  'denied',
                  'unsupported',
                  'error',
                  'unknown',
                ].contains(widget.quality))
              DeckStatus(
                label: widget.stale
                    ? 'История сохранена; сбор приостановлен'
                    : widget.quality != null &&
                          widget.quality != 'known' &&
                          widget.quality != 'incomplete'
                    ? widget.quality == 'unknown'
                          ? 'Состояние источника неизвестно'
                          : _qualityLabel(widget.quality)
                    : _hasMissingValues(widget.rows)
                    ? 'В истории есть пропуски'
                    : 'История получена',
                tone:
                    widget.quality != null &&
                        widget.quality != 'known' &&
                        widget.quality != 'incomplete'
                    ? _qualityTone(widget.quality)
                    : widget.stale || _hasMissingValues(widget.rows)
                    ? DeckTone.warning
                    : DeckTone.available,
              ),
          ],
        ),
      ),
    );
  }
}

String _resourcePercent(Object? value) {
  final number = _validValue(value);
  if (number == null) return 'Нет данных';
  final rounded = number.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  if (number < 90 && double.parse(rounded) >= 90) return '<90%';
  return '${rounded.replaceAll('.', ',')}%';
}

String _resourceTime(int time, {bool seconds = false}) {
  final date = DateTime.fromMillisecondsSinceEpoch(time, isUtc: true);
  String two(int n) => '$n'.padLeft(2, '0');
  return '${two(date.hour)}:${two(date.minute)}${seconds ? ':${two(date.second)}' : ''}';
}

class _FullResourcePainter extends CustomPainter {
  const _FullResourcePainter({
    required this.rows,
    required this.series,
    required this.start,
    required this.end,
    required this.selected,
    required this.color,
    required this.grid,
    required this.threshold,
    required this.focus,
    required this.style,
    required this.left,
    required this.bottom,
    required this.stale,
    required this.focused,
  });
  final List<Map<String, Object?>> rows;
  final _Series series;
  final int start, end;
  final int? selected;
  final Color color, grid, threshold, focus;
  final TextStyle style;
  final double left, bottom;
  final bool stale, focused;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
      left,
      16,
      math.max(left, size.width - 12),
      math.max(16, size.height - bottom),
    );
    if (plot.isEmpty) return;
    double x(int time) =>
        plot.left + plot.width * (time - start) / (end - start);
    double y(num value) => plot.bottom - plot.height * value / 100;
    void label(
      String text,
      Offset offset, {
      bool right = false,
      bool center = false,
    }) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        offset -
            Offset(
              right
                  ? painter.width
                  : center
                  ? painter.width / 2
                  : 0,
              0,
            ),
      );
    }

    for (final value in [0, 25, 50, 75, 100]) {
      canvas.drawLine(
        Offset(plot.left, y(value)),
        Offset(plot.right, y(value)),
        Paint()..color = grid.withValues(alpha: .5),
      );
      label(
        '$value%',
        Offset(plot.left - 12, y(value) - (style.fontSize ?? 12) * .65),
        right: true,
      );
    }
    final divisions = plot.width >= 500 ? 4 : 2;
    for (var i = 0; i <= divisions; i++) {
      final time = start + ((end - start) * i / divisions).round();
      canvas.drawLine(
        Offset(x(time), plot.top),
        Offset(x(time), plot.bottom),
        Paint()..color = grid.withValues(alpha: .3),
      );
      label(
        _resourceTime(time),
        Offset(x(time), plot.bottom + 10),
        right: i == divisions,
        center: i > 0 && i < divisions,
      );
    }
    canvas.save();
    canvas.clipRect(plot.inflate(3));
    canvas.drawPath(
      _patternPath(
        Path()
          ..moveTo(plot.left, y(90))
          ..lineTo(plot.right, y(90)),
        const [5, 5],
      ),
      Paint()
        ..color = threshold.withValues(alpha: .6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final segments = <List<Offset>>[];
    var segment = <Offset>[];
    int? previous;
    void flush() {
      if (segment.isNotEmpty) segments.add(segment);
      segment = [];
      previous = null;
    }

    for (final row in rows) {
      final time = _time(row), value = _validValue(row[series.field]);
      if (time == null || time <= start || time > end || value == null) {
        flush();
        continue;
      }
      if (previous != null &&
          (row['breakBefore'] == true ||
              time <= previous! ||
              time - previous! > 15000))
        flush();
      segment.add(Offset(x(time), y(value)));
      previous = time;
    }
    flush();
    for (final points in segments) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      if (points.length > 1) {
        final fill = Path.from(path)
          ..lineTo(points.last.dx, plot.bottom)
          ..lineTo(points.first.dx, plot.bottom)
          ..close();
        canvas.drawPath(
          fill,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: .18),
                color.withValues(alpha: .015),
              ],
            ).createShader(plot),
        );
        canvas.drawPath(
          stale ? _patternPath(path, const [6, 4]) : path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round,
        );
      } else {
        canvas.drawCircle(points.single, 3, Paint()..color = color);
      }
    }
    if (selected != null && selected! > start && selected! <= end) {
      canvas.drawLine(
        Offset(x(selected!), plot.top),
        Offset(x(selected!), plot.bottom),
        Paint()
          ..color = focus
          ..strokeWidth = 1,
      );
      for (final row in rows) {
        final value = _validValue(row[series.field]);
        if (_time(row) == selected && value != null) {
          canvas.drawCircle(
            Offset(x(selected!), y(value)),
            5,
            Paint()..color = color,
          );
        }
      }
    }
    canvas.restore();
    if (focused)
      canvas.drawRect(
        plot.inflate(3),
        Paint()
          ..color = focus
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
  }

  @override
  bool shouldRepaint(covariant _FullResourcePainter old) =>
      old.rows != rows ||
      old.start != start ||
      old.end != end ||
      old.selected != selected ||
      old.color != color ||
      old.grid != grid ||
      old.threshold != threshold ||
      old.focus != focus ||
      old.style != style ||
      old.left != left ||
      old.bottom != bottom ||
      old.stale != stale ||
      old.focused != focused;
}
