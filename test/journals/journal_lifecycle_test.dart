import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/journals/journal_models.dart';
import 'package:serverdeck/journals/journal_protocol.dart';

import 'journal_owner_test.dart' show JournalHarness;

void main() {
  test(
    'renaming during a read retires loading status and late result',
    () async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      await h.owner.start();
      final id = await h.owner.add('a', JournalKind.journal, 'a.service', 'A');
      final held = Completer<JournalReply>();
      h.connection.respond = (_) => held.future;
      final running = h.owner.reconcile();
      await Future<void>.delayed(Duration.zero);
      await h.owner.rename(id, 'Renamed');
      held.complete(
        JournalReply(
          events: [const JournalEntry(id: 'late', receivedAt: 0, text: 'late')],
        ),
      );
      await running;
      await h.owner.drain();
      expect(
        h.owner.status(h.owner.sources('a').single),
        JournalStatus.waiting,
      );
      expect(h.owner.entries(id), isEmpty);
    },
  );
  for (final mode in ['offline', 'loading', 'error']) {
    test(
      'Refresh before prune never restamps old discovery for new revision: $mode',
      () async {
        final h = JournalHarness();
        addTearDown(h.dispose);
        await h.owner.start();
        h.connection.respond = (_) async =>
            JournalReply(units: ['old.service']);
        await h.owner.discover('a');
        // Expire retry cooldown without running the scheduled pruning tick.
        h.clock.elapsed += const Duration(seconds: 5);
        await h.repository.write((r) {
          final p = r.profile('a')!..connectionRevision = 2;
          r.putProfile(p);
        });
        final held = Completer<JournalReply>();
        if (mode == 'offline') {
          h.connection.connected = false;
        } else if (mode == 'loading') {
          h.connection.respond = (_) => held.future;
        } else {
          h.connection.respond = (_) async =>
              JournalReply(failure: JournalStatus.unavailable);
        }
        final refresh = h.owner.discover('a');
        await Future<void>.delayed(Duration.zero);
        final duringRefresh = h.owner.services['a'];
        if (mode == 'loading')
          held.complete(JournalReply(units: ['new.service']));
        await refresh;
        expect(duringRefresh, isNull);
        expect(
          h.owner.services['a'],
          mode == 'loading' ? ['new.service'] : isNull,
        );
      },
    );
  }
  test('discovery is hidden immediately on revision change and old in-flight result cannot restore it', () async {
    final h = JournalHarness();
    addTearDown(h.dispose);
    await h.owner.start();
    h.connection.respond = (_) async => JournalReply(units: ['old.service']);
    await h.owner.discover('a');
    expect(h.owner.services['a'], ['old.service']);
    h.clock.elapsed += const Duration(seconds: 5);
    final held = Completer<JournalReply>();
    h.connection.respond = (_) => held.future;
    final refresh = h.owner.discover('a');
    await Future<void>.delayed(Duration.zero);
    await h.repository.write((r) {
      final p = r.profile('a')!..connectionRevision = 2;
      r.putProfile(p);
    });
    expect(h.owner.services.containsKey('a'), isFalse);
    expect(h.owner.serviceStates.containsKey('a'), isFalse);
    held.complete(JournalReply(units: ['late-old.service']));
    await refresh;
    expect(h.owner.services.containsKey('a'), isFalse);
  });
  test(
    'profile deletion retires journal runtime source state at next prune',
    () async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      await h.owner.start();
      await h.owner.add('a', JournalKind.journal, 'a.service', 'A');
      await h.tick();
      expect(h.owner.retainedSourceStates, 1);
      await h.repository.write((r) => r.deleteProfile('a'));
      await h.tick();
      expect(h.owner.retainedSourceStates, 0);
    },
  );
  for (final action in ['delete', 'revision', 'shutdown']) {
    test('late batch after $action cannot republish old history', () async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      await h.owner.start();
      final id = await h.owner.add('a', JournalKind.journal, 'a.service', 'A');
      final held = Completer<JournalReply>();
      h.connection.respond = (_) => held.future;
      final running = h.owner.reconcile();
      await Future<void>.delayed(Duration.zero);
      switch (action) {
        case 'delete':
          await h.owner.deleteSource(id);
        case 'revision':
          await h.repository.write((r) {
            final p = r.profile('a')!..connectionRevision = 2;
            r.putProfile(p);
          });
        case 'shutdown':
          await h.owner.stopAdmission();
      }
      held.complete(
        JournalReply(
          cursor: 'late',
          events: [const JournalEntry(id: 'late', receivedAt: 0, text: 'late')],
        ),
      );
      await running;
      await h.owner.drain();
      expect(h.owner.entries(id), isEmpty);
      if (action == 'revision') {
        expect(h.owner.sources('a').single.name, 'A');
        expect(h.owner.sources('a').single.connectionRevision, 2);
      }
    });
  }
  test(
    'storage failure preserves cursor and successful retry receives batch once',
    () async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      await h.owner.start();
      final id = await h.owner.add('a', JournalKind.journal, 'a.service', 'A');
      h.connection.respond = (_) async {
        h.repository.failCommit = true;
        return JournalReply(
          cursor: 'c',
          events: [const JournalEntry(id: 'c', receivedAt: 0, text: 'entry')],
        );
      };
      await h.tick();
      expect(h.owner.payload(id).checkpoint, isEmpty);
      expect(h.owner.entries(id), isEmpty);
      h.connection.respond = (_) async => JournalReply(
        cursor: 'c',
        events: [const JournalEntry(id: 'c', receivedAt: 0, text: 'entry')],
      );
      await h.tick();
      await h.tick();
      expect(h.owner.entries(id), hasLength(1));
      expect(h.owner.payload(id).checkpoint['cursor'], 'c');
    },
  );
  test('cursor fallback empty and repeated failure abandon old cursor; output cap skips visibly', () async {
    final h = JournalHarness();
    addTearDown(h.dispose);
    await h.owner.start();
    final id = await h.owner.add('a', JournalKind.journal, 'a.service', 'A');
    var step = 0;
    h.connection.respond = (r) async {
      switch (++step) {
        case 1:
          return JournalReply(cursor: 'old');
        case 2:
          return JournalReply(
            failure: JournalStatus.unavailable,
            cursorRejected: true,
          );
        case 3:
          return JournalReply(failure: JournalStatus.unavailable);
        case 4:
          return JournalReply();
        case 5:
          return JournalReply(failure: JournalStatus.outputLimit);
        case 6:
          return JournalReply(cursor: 'metadata', partial: true);
        default:
          return JournalReply(
            cursor: 'last',
            events: [
              const JournalEntry(id: 'last', receivedAt: 0, text: 'after gap'),
            ],
          );
      }
    };
    for (var i = 0; i < 7; i++) {
      await h.tick();
    }
    expect(h.connection.requests[2].cursor, isNull);
    expect(h.connection.requests[3].cursor, isNull);
    expect(h.connection.requests[5].metadataRecovery, isTrue);
    expect(h.connection.requests[6].cursor, 'metadata');
    expect(h.owner.entries(id).single.text, 'after gap');
    expect(h.owner.payload(id).partial, isTrue);
  });
}
