import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/data/read_adapters.dart';

void main() {
  test('BR-P01 typed read operations encode cursor and refuse shell units', () {
    expect(
      ReadOperation.journal(
        limit: 100,
        unit: 'postgresql@18-main.service',
      ).command,
      contains("'postgresql@18-main.service'"),
    );
    expect(
      () => ReadOperation.journal(unit: 'a.service; reboot'),
      throwsArgumentError,
    );
    expect(() => ReadOperation.journal(limit: 1001), throwsArgumentError);
    expect(
      ReadOperation.journal(cursor: "s=a;i=1").command,
      contains("'s=a;i=1'"),
    );
    expect(posixQuote("a'b"), "'a'\"'\"'b'");
  });
  test('BR-I01/I02 dpkg includes installed only and rejects partial rows', () {
    final result = parsePackages(
      'postgresql-18\t18.6-3.pgdg24.04+1\tinstalled\n'
      'nginx\t1.24\tconfig-files\ninvalid row\n',
    );
    expect(result.values.length, 1);
    expect(result.values.single.version, '18.6-3.pgdg24.04+1');
    expect(result.malformed, 1);
    expect(result.complete, isFalse);
  });
  test('BR-I02 stopped failed and instance units remain discoverable', () {
    final result = parseUnits(
      jsonEncode([
        {
          'unit': 'postgresql@18-main.service',
          'load': 'loaded',
          'active': 'active',
          'sub': 'running',
        },
        {
          'unit': 'worker@batch.service',
          'load': 'loaded',
          'active': 'failed',
          'sub': 'failed',
        },
        {
          'unit': 'nginx.service',
          'load': 'loaded',
          'active': 'inactive',
          'sub': 'dead',
        },
      ]),
      jsonEncode([
        {'unit_file': 'custom.service', 'state': 'disabled'},
      ]),
    );
    expect(result.values.length, 4);
    expect(
      result.values.firstWhere((u) => u.name == 'worker@batch.service').active,
      'failed',
    );
    expect(
      result.values.firstWhere((u) => u.name == 'custom.service').active,
      'unknown',
    );
  });
  test(
    'BR-L05 denied command remains failed, never an empty parse success',
    () {
      expect(
        classifyReadFailure(1, 'Failed to open journal: Permission denied'),
        ReadFailure.denied,
      );
      expect(
        classifyReadFailure(127, 'command not found'),
        ReadFailure.unsupported,
      );
      expect(classifyReadFailure(255, 'SSH disconnect'), ReadFailure.transport);
      expect(classifyReadFailure(1, 'something else'), ReadFailure.failed);
    },
  );
  test('BR-M01 CPU uses counter deltas, guest time not counted twice', () {
    final first = CpuCounters.parse('cpu 100 20 30 200 10 5 5 0 50 0');
    final next = CpuCounters.parse('cpu 120 20 40 260 10 5 5 0 70 0');
    expect(next.utilizationSince(first), closeTo(100 / 3, .001));
    expect(first.utilizationSince(first), isNull);
    expect(first.utilizationSince(next), isNull);
  });
  test('BR-M01 invalid memory is unavailable rather than zero', () {
    expect(
      parseMemoryUsage('MemTotal: 1000 kB\nMemAvailable: 400 kB'),
      closeTo(.6, .001),
    );
    expect(parseMemoryUsage('MemTotal: 1000 kB'), isNull);
    expect(
      parseMemoryUsage('MemTotal: 1000 kB\nMemAvailable: 1400 kB'),
      isNull,
    );
  });
}
