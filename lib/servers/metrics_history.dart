import 'package:flutter/material.dart';

/// Small bounded UI history; missing samples create gaps rather than zeroes.
class MetricsHistory extends StatelessWidget {
  const MetricsHistory({super.key, required this.points});
  final List<Object?> points;
  @override
  Widget build(BuildContext context) {
    final rows = points.whereType<Map<String, Object?>>().take(120).toList();
    if (rows.length < 2) return const Text('Для истории нужны два наблюдения.');
    final colors = [
      Theme.of(context).colorScheme.primary,
      Theme.of(context).colorScheme.tertiary,
      Theme.of(context).colorScheme.secondary,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('История, до 10 минут · 0–100%'),
        Wrap(
          spacing: 16,
          children: [
            for (var i = 0; i < 3; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.show_chart, color: colors[i], size: 18),
                  Text(const ['CPU', 'RAM', 'Диск /'][i]),
                ],
              ),
          ],
        ),
        Semantics(
          label: 'История CPU, оперативной памяти и корневого диска; пропуски означают отсутствие данных',
          child: SizedBox(
            height: 130,
            width: double.infinity,
            child: CustomPaint(
              painter: _HistoryPainter(
                rows,
                colors,
                Theme.of(context).dividerColor,
              ),
            ),
          ),
        ),
        Text('${rows.first['receivedAt']} — ${rows.last['receivedAt']}'),
      ],
    );
  }
}

class _HistoryPainter extends CustomPainter {
  _HistoryPainter(this.rows, this.colors, this.grid);
  final List<Map<String, Object?>> rows;
  final List<Color> colors;
  final Color grid;
  @override
  void paint(Canvas canvas, Size size) {
    final times = rows
        .map(
          (row) =>
              DateTime.tryParse('${row['receivedAt']}')?.millisecondsSinceEpoch,
        )
        .toList();
    final start = times.whereType<int>().fold<int?>(
      null,
      (a, b) => a == null || b < a ? b : a,
    );
    final end = times.whereType<int>().fold<int?>(
      null,
      (a, b) => a == null || b > a ? b : a,
    );
    if (start == null || end == null || start == end) return;
    for (final percent in [0, 25, 50, 75, 100]) {
      final y = size.height * (1 - percent / 100);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = grid
          ..strokeWidth = 1,
      );
    }
    const keys = ['cpuPercent', 'memoryUsedPercent', 'rootDiskUsedPercent'];
    for (var series = 0; series < keys.length; series++) {
      final path = Path();
      var joined = false;
      int? last;
      for (var index = 0; index < rows.length; index++) {
        final value = rows[index][keys[series]], time = times[index];
        if (time == null || value is! int || value < 0 || value > 100) {
          joined = false;
          continue;
        }
        final x = size.width * (time - start) / (end - start);
        final y = size.height * (1 - value / 100);
        if (!joined || last == null || time <= last || time - last > 15000)
          path.moveTo(x, y);
        else
          path.lineTo(x, y);
        last = time;
        joined = true;
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[series]
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HistoryPainter oldDelegate) => true;
}
