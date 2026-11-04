import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/monitoring/monitoring_models.dart';

void main() {
  test(
    'readings reject impossible percentages and retain stale last value',
    () {
      for (final value in [double.nan, double.infinity, -0.1, 100.1]) {
        expect(
          () => MetricReading.sample(value, const Duration(seconds: 2), 3000),
          throwsArgumentError,
        );
      }
      final reading = MetricReading.sample(
        95,
        const Duration(seconds: 2),
        3000,
      );
      expect(reading.isFresh(const Duration(seconds: 16)), isTrue);
      expect(reading.isFresh(const Duration(seconds: 17)), isFalse);
      final invalid = reading.unavailable(MonitoringReason.invalidResponse);
      expect(invalid.percent, 95);
      expect(invalid.displayAt, 3000);
      expect(invalid.isFresh(const Duration(seconds: 3)), isFalse);
      expect(const MetricReading.missing().percent, isNull);
    },
  );

  test('CPU delta excludes idle/iowait and does not count guests twice', () {
    final first = CpuCounters([100, 0, 50, 800, 50, 0, 0, 0]);
    final next = CpuCounters([150, 0, 70, 820, 60, 0, 0, 0]);
    expect(next.busyPercentSince(first), 70);
    expect(next.values, hasLength(8));
    expect(() => next.values[0] = 0, throwsUnsupportedError);
  });

  test('CPU reset and no elapsed CPU time do not invent zero load', () {
    final first = CpuCounters(List.filled(8, 100));
    expect(first.busyPercentSince(first), isNull);
    expect(
      CpuCounters([99, 101, 101, 101, 101, 101, 101, 101])
          .busyPercentSince(first),
      isNull,
    );
    expect(() => CpuCounters(List.filled(7, 0)), throwsArgumentError);
    expect(() => CpuCounters([-1, 0, 0, 0, 0, 0, 0, 0]), throwsArgumentError);
  });

  test('CPU totals can exceed signed64 without wrapping', () {
    final first = CpuCounters(List.filled(8, 0x7ffffffffffffffe));
    final next = CpuCounters(List.filled(8, 0x7fffffffffffffff));
    expect(next.busyPercentSince(first), 75);
  });
}
