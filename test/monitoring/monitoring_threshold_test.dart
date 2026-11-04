import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/monitoring/monitoring_models.dart';

void main() {
  for (final entry in <double, String>{
    0: '0,0',
    89.9: '89,9',
    89.95: '<90,0',
    90: '90,0',
    100: '100,0',
  }.entries) {
    test(
      'percent ${entry.key} is presented without threshold-rounding ambiguity',
      () {
        final reading = MetricReading.sample(entry.key, Duration.zero, 1000);
        expect(reading.formattedPercent, entry.value);
        expect(reading.isCritical(Duration.zero), entry.key >= 90);
      },
    );
  }
  test('stale/invalid readings never contribute current critical severity', () {
    final reading = MetricReading.sample(95, Duration.zero, 1000);
    expect(reading.isCritical(const Duration(seconds: 15)), isFalse);
    expect(
      reading.unavailable(MonitoringReason.timeout).isCritical(Duration.zero),
      isFalse,
    );
  });
  test('aggregate critical and partial flags are independent', () {
    final s = MonitoringSnapshot(
      profileId: 'unit',
      connectionRevision: 1,
      generation: 1,
      readings: {
        MetricKind.cpu: MetricReading.sample(95, Duration.zero, 1000),
        MetricKind.memory: MetricReading.sample(20, Duration.zero, 1000),
      },
    );
    expect(s.hasCritical(Duration.zero), isTrue);
    expect(s.isPartial(Duration.zero), isTrue);
    expect(s.hasCritical(const Duration(seconds: 15)), isFalse);
    expect(s.isPartial(const Duration(seconds: 15)), isFalse);
  });
}
