import '../domain/models.dart';

/// Runtime-only values. Nothing in this model contains credentials or raw output.
enum MetricKind {
  cpu('CPU'),
  memory('RAM'),
  disk('Диск /');

  const MetricKind(this.label);
  final String label;
}

enum MonitoringReason {
  waiting,
  baseline,
  unsupportedOs,
  sourceUnavailable,
  invalidResponse,
  timeout,
  outputLimit,
  disconnected,
  paused,
  stopped,
  cleanupPending,
}

final class MetricReading {
  const MetricReading._(
    this.percent,
    this.receivedAt,
    this.displayAt,
    this.reason,
  );

  const MetricReading.missing([
    MonitoringReason reason = MonitoringReason.waiting,
  ]) : this._(null, null, null, reason);

  factory MetricReading.sample(
    double percent,
    Duration receivedAt,
    int displayAt,
  ) {
    if (!percent.isFinite ||
        percent < 0 ||
        percent > 100 ||
        receivedAt.isNegative) {
      throw ArgumentError('Invalid monitoring sample');
    }
    return MetricReading._(percent, receivedAt, displayAt, null);
  }

  final double? percent;
  final Duration? receivedAt;
  final int? displayAt;
  final MonitoringReason? reason;
  static const staleAfter = Duration(seconds: 15);

  bool isFresh(Duration now) =>
      percent != null &&
      reason == null &&
      receivedAt != null &&
      now >= receivedAt! &&
      now - receivedAt! < staleAfter;

  MetricReading unavailable(MonitoringReason reason) =>
      MetricReading._(percent, receivedAt, displayAt, reason);

  bool isCritical(Duration now) => isFresh(now) && percent! >= 90;
  String? get formattedPercent {
    final value = percent;
    if (value == null) return null;
    final rounded = (value == 0 ? 0.0 : value).toStringAsFixed(1);
    if (value < 90 && rounded == '90.0') return '<90,0';
    return rounded.replaceAll('.', ',');
  }
}

/// Linux aggregate CPU's first eight fields. Guest time is already in user/nice.
final class CpuCounters {
  CpuCounters(List<int> counters) : values = List.unmodifiable(counters) {
    if (values.length != 8 || values.any((value) => value < 0)) {
      throw ArgumentError('Invalid CPU counters');
    }
  }
  final List<int> values;

  /// BigInt aggregation avoids wrapping when eight valid signed64 counters sum.
  double? busyPercentSince(CpuCounters previous) {
    var total = BigInt.zero, idle = BigInt.zero;
    for (var i = 0; i < values.length; i++) {
      if (values[i] < previous.values[i]) return null;
      final delta = BigInt.from(values[i]) - BigInt.from(previous.values[i]);
      total += delta;
      if (i == 3 || i == 4) idle += delta;
    }
    if (total == BigInt.zero) return null;
    return (total - idle).toDouble() / total.toDouble() * 100;
  }
}

final class MonitoringSnapshot {
  MonitoringSnapshot({
    required this.profileId,
    required this.connectionRevision,
    required this.generation,
    this.sessionId,
    this.connection,
    this.statusReason,
    this.collecting = false,
    Map<MetricKind, MetricReading> readings = const {},
  }) : readings = Map.unmodifiable({
         for (final kind in MetricKind.values)
           kind: readings[kind] ?? const MetricReading.missing(),
       });

  final String profileId;
  final String? sessionId;
  final ConnectionView? connection;
  final MonitoringReason? statusReason;
  final bool collecting;
  final int connectionRevision, generation;
  final Map<MetricKind, MetricReading> readings;
  bool hasCritical(Duration now) =>
      readings.values.any((r) => r.isCritical(now));
  bool isPartial(Duration now) {
    final fresh = readings.values.where((r) => r.isFresh(now)).length;
    return fresh > 0 && fresh < MetricKind.values.length;
  }
}
