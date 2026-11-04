import 'dart:convert';

/// Owner-only capability. Commit guards run inside the actual storage transaction.
abstract interface class MonitoringHistoryStore {
  String? loadHistory(String profileId, int connectionRevision);
  Future<void> saveHistory(
    String profileId,
    int connectionRevision,
    String payload,
    bool Function() canCommit,
  );
}

final class HistoryPoint {
  const HistoryPoint({
    required this.utcMs,
    required this.segment,
    this.cpu,
    this.memory,
    this.disk,
    this.monotonicAt,
  });
  final int utcMs;
  final String segment;
  final double? cpu, memory, disk;
  final Duration? monotonicAt;

  List<Object?> toRow() => [utcMs, segment, cpu, memory, disk];
  Map<String, Object?> toChart({required bool breakBefore}) => {
    'receivedAt': DateTime.fromMillisecondsSinceEpoch(
      utcMs,
      isUtc: true,
    ).toIso8601String(),
    'cpuPercent': cpu,
    'memoryUsedPercent': memory,
    'rootDiskUsedPercent': disk,
    'breakBefore': breakBefore,
  };
}

abstract final class HistoryCodec {
  static const maxPoints = 720, maxBytes = 192 * 1024;
  static const retention = Duration(hours: 1);

  static List<HistoryPoint> decode(String payload) {
    if (utf8.encode(payload).length > maxBytes) {
      throw const FormatException('History size');
    }
    final value = jsonDecode(payload);
    if (value is! Map ||
        value.length != 2 ||
        value['version'] != 1 ||
        value['version'] is! int ||
        value['points'] is! List) {
      throw const FormatException('History format');
    }
    final rows = value['points'] as List;
    if (rows.length > maxPoints) throw const FormatException('History count');
    double? percent(Object? v) {
      if (v == null) return null;
      if (v is! num || !v.isFinite || v < 0 || v > 100) {
        throw const FormatException('History percent');
      }
      return v.toDouble();
    }

    return [
      for (final row in rows)
        if (row is List &&
            row.length == 5 &&
            row[0] is int &&
            row[0] >= 0 &&
            row[0] <= 8640000000000000 &&
            row[1] is String &&
            (row[1] as String).isNotEmpty &&
            (row[1] as String).length <= 128)
          HistoryPoint(
            utcMs: row[0] as int,
            segment: row[1] as String,
            cpu: percent(row[2]),
            memory: percent(row[3]),
            disk: percent(row[4]),
          )
        else
          throw const FormatException('History row'),
    ];
  }

  static String encode(List<HistoryPoint> points) {
    final payload = jsonEncode({
      'version': 1,
      'points': [for (final point in points) point.toRow()],
    });
    decode(payload); // Same strict current contract for reads and writes.
    return payload;
  }

  static List<HistoryPoint> prune(
    Iterable<HistoryPoint> points,
    int utcMs,
    Duration monotonicNow,
  ) {
    final unique = <(int, String), HistoryPoint>{};
    for (final point in points) {
      if (point.utcMs > utcMs ||
          utcMs - point.utcMs >= retention.inMilliseconds ||
          (point.monotonicAt != null &&
              monotonicNow - point.monotonicAt! >= retention)) {
        continue;
      }
      unique[(point.utcMs, point.segment)] = point;
    }
    final rows = unique.values.toList();
    return rows.length <= maxPoints
        ? rows
        : rows.sublist(rows.length - maxPoints);
  }

  static List<Map<String, Object?>> chart(List<HistoryPoint> points) => [
    for (var i = 0; i < points.length; i++)
      points[i].toChart(
        breakBefore: i == 0 || points[i - 1].segment != points[i].segment,
      ),
  ];
}
