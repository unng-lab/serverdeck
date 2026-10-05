import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/models.dart';

void main() {
  test('BR-L03 pause freezes display while bounded transport continues', () {
    final state = JournalSession();
    state.journal.add(
      JournalRecord(
        cursor: 'one',
        bootId: 'boot',
        at: DateTime.now(),
        unit: 'a.service',
        priority: 6,
        message: 'one',
      ),
    );
    state.togglePause();
    state.journal.add(
      JournalRecord(
        cursor: 'two',
        bootId: 'boot',
        at: DateTime.now(),
        unit: 'a.service',
        priority: 6,
        message: 'two',
      ),
    );
    expect(state.visible(DateTime.now()).length, 1);
    expect(state.pending, 1);
    state.togglePause();
    expect(state.visible(DateTime.now()).length, 2);
    expect(state.visible(DateTime.now()).first.cursor, 'two');
  });
  JournalRecord record(int i, {String boot = 'boot-a'}) => JournalRecord(
    cursor: 'cursor-$i',
    bootId: boot,
    at: DateTime.utc(2026, 10, 5),
    unit: 'postgresql@18-main.service',
    priority: 6,
    message: 'event $i',
  );
  test('BR-L02 ring is bounded and overflow remains visible', () {
    final journal = BoundedJournal();
    for (var i = 0; i < 620; i++) {
      journal.add(record(i));
    }
    expect(journal.records.length, 500);
    expect(journal.records.first.cursor, 'cursor-120');
    expect(journal.dropped, 120);
  });
  test('BR-L03 duplicate cursor/boot and gap are explicit', () {
    final journal = BoundedJournal();
    journal.add(record(1));
    journal.add(record(1));
    journal.add(record(1, boot: 'boot-b'));
    journal.markGap();
    expect(journal.records.length, 2);
    expect(journal.duplicates, 1);
    expect(journal.gaps, 1);
  });
  test('BR-L05 malformed/oversized records are counted', () {
    final journal = BoundedJournal();
    journal.addJson('invalid');
    journal.addJson(jsonEncode({'MESSAGE': 'x' * 70000}));
    journal.addJson(jsonEncode({'MESSAGE': 'missing identity'}));
    expect(journal.malformed, 2);
    expect(journal.oversized, 1);
    expect(journal.records, isEmpty);
  });
  test('BR-L02 history range does not silently clamp', () {
    expect(validateHistoryLimit(100), 100);
    expect(validateHistoryLimit(1), 1);
    expect(validateHistoryLimit(1000), 1000);
    expect(() => validateHistoryLimit(0), throwsArgumentError);
    expect(() => validateHistoryLimit(1001), throwsArgumentError);
  });
  test('BR-M01 unavailable is null, old data is stale', () {
    final at = DateTime.utc(2026, 10, 5);
    final value = Observation<double>(
      value: null,
      observedAt: at,
      status: ObservationStatus.unsupported,
    );
    expect(value.value, isNull);
    expect(value.isStale(at.add(const Duration(seconds: 16))), isTrue);
    expect(value.isStale(at.add(const Duration(seconds: 14))), isFalse);
  });
  test('BR-P01 identifiers reject shell and protect NetBird', () {
    expect(
      validateUnit('postgresql@18-main.service'),
      'postgresql@18-main.service',
    );
    expect(
      () => validateUnit('a.service; touch /tmp/pwned'),
      throwsArgumentError,
    );
    expect(
      () => validateUnit('netbird.service', write: true),
      throwsArgumentError,
    );
    expect(
      () => validateUnit('my-netbird-client.service', write: true),
      throwsArgumentError,
    );
  });
}
