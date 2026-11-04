import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/journals/journal_models.dart';
import 'package:serverdeck/journals/journal_protocol.dart';

import 'journal_owner_test.dart' show JournalHarness;

void main() {
  test(
    'pending prefix expires after hour even when collection is disabled',
    () async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      await h.owner.start();
      final id = await h.owner.add('a', JournalKind.file, '/a', 'A');
      h.connection.respond = (r) async => JournalReply(
        identity: '1:2',
        size: 10,
        body: r.identity == null
            ? null
            : Uint8List.fromList('sensitive-prefix'.codeUnits),
      );
      await h.tick();
      await h.tick();
      expect(h.owner.payload(id).checkpoint['fragment'], isNotNull);
      await h.owner.setEnabled(id, false);
      h.clock.utc += 3600000;
      await h.owner.reconcile();
      expect(h.owner.payload(id).checkpoint['fragment'], isNull);
      expect(h.owner.payload(id).checkpoint['discard'], isTrue);
      expect(h.owner.payload(id).partial, isTrue);
    },
  );
  test(
    'file initial EOF and reconnect reset never fabricate old lines',
    () async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      await h.owner.start();
      final id = await h.owner.add(
        'a',
        JournalKind.file,
        '/opt/app.log',
        'App',
      );
      h.connection.respond = (r) async => JournalReply(
        identity: '1:2',
        size: r.identity == null ? 50 : 60,
        body: r.identity == null ? null : Uint8List.fromList('new\n'.codeUnits),
      );
      await h.tick();
      expect(h.owner.entries(id), isEmpty);
      expect(h.owner.payload(id).checkpoint['offset'], 50);
      await h.tick();
      expect(h.owner.entries(id).single.text, 'new');
      h.connection.session = 'next';
      await h.tick();
      expect(h.connection.requests.last.identity, isNull);
      expect(h.owner.entries(id), hasLength(1));
      expect(h.owner.payload(id).checkpoint['offset'], 50);
      expect(h.owner.payload(id).partial, isTrue);
    },
  );
  test('one source permission failure does not stop next source and reads are spaced', () async {
    final h = JournalHarness();
    addTearDown(h.dispose);
    await h.owner.start();
    await h.owner.add('a', JournalKind.file, '/no', 'No');
    final good = await h.owner.add(
      'a',
      JournalKind.journal,
      'good.service',
      'Good',
    );
    h.connection.respond = (r) async => r.target == '/no'
        ? JournalReply(failure: JournalStatus.permissionDenied)
        : JournalReply(
            cursor: 'ok',
            events: [
              const JournalEntry(id: 'ok', receivedAt: 0, text: 'healthy'),
            ],
          );
    await h.tick();
    await h.tick();
    expect(h.owner.entries(good).single.text, 'healthy');
    final count = h.connection.requests.length;
    await h.owner.reconcile();
    await h.owner.reconcile();
    // At most a previously idle source may run; no source runs twice at same instant.
    expect(h.connection.requests.length, lessThanOrEqualTo(count + 1));
  });
}
