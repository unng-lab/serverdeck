import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/monitoring/linux_metrics.dart';
import 'package:serverdeck/monitoring/monitoring_models.dart';

String frame({
  String os = 'Linux',
  String cpu = 'cpu 100 0 50 800 50 0 0 0 200 7',
  String memory = 'MemTotal: 1000 kB\nMemAvailable: 250 kB',
  String disk = 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/root 1000 900 50 95% /',
}) => 'SDM1\nOS\n$os\nCPU\n$cpu\nMEM\n$memory\nDISK\n$disk\nEND\n';
LinuxSample parse(String value, {int? status = 0}) =>
    parseLinuxMetrics(Uint8List.fromList(utf8.encode(value)), exitCode: status);

void main() {
  test(
    'parses three independent sources and excludes reserved disk blocks',
    () {
      final sample = parse(frame());
      expect(sample.failure, isNull);
      expect(sample.cpu!.values, [100, 0, 50, 800, 50, 0, 0, 0]);
      expect(sample.memoryPercent, 75);
      expect(sample.diskPercent, closeTo(900 / 950 * 100, 0.00001));
    },
  );
  test('CPU ignores guest fields, reset is not a zero measurement', () {
    final first = parse(frame()).cpu!;
    final next = parse(frame(cpu: 'cpu 150 0 70 820 60 0 0 0 99999 88888'))
        .cpu!;
    expect(next.busyPercentSince(first), 70);
    expect(first.busyPercentSince(next), isNull);
    expect(first.busyPercentSince(first), isNull);
  });
  test('missing RAM is source-unavailable while CPU and disk remain valid', () {
    final sample = parse(frame(memory: 'MemTotal: 1000 kB'));
    expect(sample.memoryPercent, isNull);
    expect(
      sample.reasonFor(MetricKind.memory),
      MonitoringReason.sourceUnavailable,
    );
    expect(sample.cpu, isNotNull);
    expect(sample.diskPercent, isNotNull);
  });
  test('empty sources preserve unknown rather than zero', () {
    final sample = parse(frame(cpu: '', memory: '', disk: ''));
    expect(sample.failure, isNull);
    expect(sample.cpu, isNull);
    expect(sample.memoryPercent, isNull);
    expect(sample.diskPercent, isNull);
    for (final kind in MetricKind.values) {
      expect(sample.reasonFor(kind), MonitoringReason.sourceUnavailable);
    }
  });
  test('RAM duplicate/bad units/range invalidate only RAM', () {
    for (final memory in [
      'MemTotal: 1000 kB\nMemAvailable: 1001 kB',
      'MemTotal: 0 kB\nMemAvailable: 0 kB',
      'MemTotal: 1000 kB\nMemAvailable: -1 kB',
      'MemTotal: 1000 MB\nMemAvailable: 0 kB',
      'MemTotal: 1000 kB\nMemTotal: 2000 kB\nMemAvailable: 0 kB',
      'MemTotal: 9223372036854775808 kB\nMemAvailable: 0 kB',
    ]) {
      final sample = parse(frame(memory: memory));
      expect(
        sample.reasonFor(MetricKind.memory),
        MonitoringReason.invalidResponse,
      );
      expect(sample.cpu, isNotNull);
      expect(sample.diskPercent, isNotNull);
    }
  });
  test(
    'CPU malformed or duplicate aggregate does not invalidate other metrics',
    () {
      for (final cpu in [
        'cpu 1 2',
        'cpu -1 0 0 0 0 0 0 0',
        'cpu 9223372036854775808 0 0 0 0 0 0 0',
        'cpu 1 0 0 0 0 0 0 0\ncpu 2 0 0 0 0 0 0 0',
      ]) {
        final sample = parse(frame(cpu: cpu));
        expect(
          sample.reasonFor(MetricKind.cpu),
          MonitoringReason.invalidResponse,
        );
        expect(sample.memoryPercent, 75);
      }
    },
  );
  test(
    'df zero/negative/multiple/wrapped rows are unavailable without invention',
    () {
      for (final row in [
        'root 0 0 0 0% /',
        'root 100 -1 50 1% /',
        'root 100 50 -1 50% /',
        'root 100 50 50 bad /',
        'root 100 50 50 50% /home',
        'root 100 50 50 50% /\nroot 100 50 50 50% /',
        'root\n100 50 50 50% /',
      ]) {
        final sample = parse(frame(disk: 'header\n$row'));
        expect(sample.diskPercent, isNull);
        expect(sample.memoryPercent, 75);
        expect(
          sample.reasonFor(MetricKind.disk),
          MonitoringReason.invalidResponse,
        );
      }
    },
  );
  test('unsigned sums cannot overflow and exact zero/hundred stay valid', () {
    final sample = parse(
      frame(
        memory: 'MemTotal: 9223372036854775807 kB\nMemAvailable: 0 kB',
        disk: 'header\nroot 9223372036854775807 9223372036854775807 9223372036854775807 50% /',
      ),
    );
    expect(sample.memoryPercent, 100);
    expect(sample.diskPercent, 50);
    expect(
      parse(frame(memory: 'MemTotal: 100 kB\nMemAvailable: 100 kB'))
          .memoryPercent,
      0,
    );
  });
  test('framing, UTF8, line and total limits fail all metrics safely', () {
    final values = <Uint8List>[
      Uint8List.fromList([255]),
      Uint8List(65537),
      Uint8List.fromList(
        utf8.encode(frame().replaceFirst('CPU\n', 'CPU\nCPU\n')),
      ),
      Uint8List.fromList(
        utf8.encode(frame().replaceFirst('Linux', 'Linux\u0000')),
      ),
      Uint8List.fromList(
        utf8.encode(frame().replaceFirst('Linux', 'x' * 4097)),
      ),
      Uint8List.fromList(utf8.encode(frame().replaceFirst('END', 'DONE'))),
    ];
    for (final bytes in values) {
      final sample = parseLinuxMetrics(bytes, exitCode: 0);
      expect(sample.failure, MonitoringReason.invalidResponse);
      expect(sample.cpu, isNull);
      expect(sample.memoryPercent, isNull);
      expect(sample.diskPercent, isNull);
    }
  });
  test(
    'CRLF supported, missing/nonzero status rejected, unsupported OS fixed',
    () {
      expect(parse(frame(os: '')).failure, MonitoringReason.sourceUnavailable);
      expect(parse(frame().replaceAll('\n', '\r\n')).memoryPercent, 75);
      for (final status in <int?>[null, 1]) {
        expect(
          parse(frame(), status: status).failure,
          MonitoringReason.invalidResponse,
        );
      }
      expect(
        parse(frame(os: 'FreeBSD')).failure,
        MonitoringReason.unsupportedOs,
      );
    },
  );
}
