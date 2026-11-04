import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/monitoring/monitoring_history.dart';
import 'package:serverdeck/storage/records.dart';

import '../fixtures/domain_repository.dart';

void main() {
  test('strict history preserves fractions, nulls and segment boundaries', () {
    final points = [
      const HistoryPoint(utcMs: 1, segment: 'a', cpu: 89.95, disk: 0),
      const HistoryPoint(utcMs: 2, segment: 'b', cpu: 100, memory: 0),
    ];
    final restored = HistoryCodec.decode(HistoryCodec.encode(points));
    expect(restored.first.cpu, 89.95);
    expect(restored.first.memory, isNull);
    expect(HistoryCodec.chart(restored).last['breakBefore'], isTrue);
    for (final payload in [
      '{}',
      '{"version":2,"points":[]}',
      '{"version":1.0,"points":[]}',
      '{"version":1,"points":[[1,"a",101,null,null]]}',
      '{"version":1,"points":[[1,"a","5",null,null]]}',
      '{"version":1,"points":[[-1,"a",5,null,null]]}',
      jsonEncode({
        'version': 1,
        'points': List.filled(721, [1, 'a', 0, 0, 0]),
      }),
      ' ' * (HistoryCodec.maxBytes + 1),
    ]) {
      expect(() => HistoryCodec.decode(payload), throwsFormatException);
    }
  });
  test('hour excludes boundary/future and monotonic expiry; cap and dedup', () {
    final points = [
      for (var i = 0; i < 725; i++)
        HistoryPoint(utcMs: 3600000 + i, segment: 'a', cpu: i % 100.0),
      const HistoryPoint(utcMs: 724, segment: 'old'),
      const HistoryPoint(utcMs: 3600726, segment: 'future'),
    ];
    final kept = HistoryCodec.prune(points, 3600724, Duration.zero);
    expect(kept, hasLength(720));
    expect(kept.first.utcMs, 3600005);
    expect(
      HistoryCodec.prune(
        [
          const HistoryPoint(
            utcMs: 100,
            segment: 'a',
            monotonicAt: Duration.zero,
          ),
        ],
        100,
        const Duration(hours: 1),
      ),
      isEmpty,
    );
    expect(
      HistoryCodec.prune([kept.last, kept.last], 3600724, Duration.zero),
      hasLength(1),
    );
  });
  test(
    'repository guards actual commit, rename preserves, revision/delete clear',
    () async {
      final repository = MemoryDomainRepository();
      final profile = Profile()..profileId = 'p';
      repository.state.profiles['p'] = profile;
      await repository.saveHistory('p', 1, 'payload', () => false);
      expect(repository.loadHistory('p', 1), isNull);
      await repository.saveHistory('p', 1, 'payload', () => true);
      await repository.write(
        (r) => r.putProfile(profile..displayName = 'Renamed'),
      );
      expect(repository.loadHistory('p', 1), 'payload');
      await repository.write(
        (r) => r.putProfile(profile..connectionRevision = 2),
      );
      expect(repository.loadHistory('p', 1), isNull);
      await repository.saveHistory('p', 1, 'late', () => true);
      expect(repository.loadHistory('p', 1), isNull);
      await repository.saveHistory('p', 2, 'new', () => true);
      await repository.write((r) => r.deleteProfile('p'));
      expect(repository.loadHistory('p', 2), isNull);
    },
  );
}
