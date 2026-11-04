import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/journals/journal_models.dart';
import 'package:serverdeck/storage/records.dart';

import 'journal_owner_test.dart' show JournalHarness;

void seed(
  JournalHarness h,
  int profile,
  int count,
  String text, {
  int offset = 0,
}) {
  final id = 'p$profile';
  h.repository.state.profiles[id] = Profile()
    ..profileId = id
    ..endpointId = 'e';
  h.repository.state.journalSources[id] = JournalSource()
    ..sourceId = id
    ..profileId = id
    ..target = 'x.service'
    ..name = id
    ..enabled = false
    ..payload = JournalPayload(
      entries: List.generate(
        count,
        (i) => JournalEntry(
          id: '$id/$i',
          receivedAt: h.clock.utc + offset + i,
          text: text,
        ),
      ),
    ).encode();
}

void main() {
  test(
    'monotonic progress expires history even when UTC rolls backwards',
    () async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      seed(h, 1, 1, 'saved');
      await h.owner.start();
      expect(h.owner.entries('p1'), hasLength(1));
      h.clock.utc -= 7200000;
      h.clock.elapsed += const Duration(hours: 1);
      expect(h.owner.entries('p1'), isEmpty);
    },
  );
  test(
    'global record cap removes oldest across profiles without losing configs',
    () async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      for (var i = 0; i < 6; i++) {
        seed(h, i, 9000, 'x');
      }
      h.clock.utc += 10000;
      await h.owner.start();
      final payloads = h.repository.state.journalSources.values
          .map((s) => JournalPayload.decode(s.payload))
          .toList();
      expect(payloads.fold<int>(0, (n, p) => n + p.entries.length), 50000);
      expect(payloads.any((p) => p.partial), isTrue);
      expect(h.repository.state.journalSources, hasLength(6));
    },
  );
  test(
    'global byte cap and per-profile byte cap are bounded UTF8 bytes',
    () async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      for (var i = 0; i < 6; i++) {
        seed(h, i, 1100, 'я' * 4096);
      }
      h.clock.utc += 2000;
      await h.owner.start();
      var total = 0;
      for (final s in h.repository.state.journalSources.values) {
        final bytes = JournalPayload.decode(s.payload).entries
            .fold<int>(0, (n, e) => n + utf8.encode(e.text).length);
        expect(bytes, lessThanOrEqualTo(8 * 1024 * 1024));
        total += bytes;
      }
      expect(total, lessThanOrEqualTo(32 * 1024 * 1024));
    },
  );
  test(
    'restart keeps fresh history, backwards clock cannot resurrect expiry',
    () async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      seed(h, 1, 1, 'persisted');
      await h.owner.start();
      expect(h.owner.entries('p1').single.text, 'persisted');
      h.clock.utc += 3600000;
      expect(h.owner.entries('p1'), isEmpty);
      h.clock.utc -= 3600000;
      expect(h.owner.entries('p1'), isEmpty);
      await h.owner.reconcile();
      expect(
        JournalPayload.decode(h.repository.state.journalSources['p1']!.payload)
            .entries,
        isEmpty,
      );
    },
  );
  test('atomic global1024 admission includes disabled and serializes concurrent adds', () async {
    final h = JournalHarness();
    addTearDown(h.dispose);
    for (var i = 0; i < 1023; i++) {
      h.repository.state.journalSources['s$i'] = JournalSource()
        ..sourceId = 's$i'
        ..profileId = 'p${i ~/ 16}'
        ..enabled = false
        ..target = 's$i.service';
    }
    final results = await Future.wait([
      h.owner
          .add('a', JournalKind.journal, 'x.service', 'X')
          .then((_) => 'ok', onError: (Object _) => 'limit'),
      h.owner
          .add('a', JournalKind.journal, 'y.service', 'Y')
          .then((_) => 'ok', onError: (Object _) => 'limit'),
    ]);
    expect(results, ['ok', 'limit']);
    expect(h.repository.state.journalSources, hasLength(1024));
  });
}
