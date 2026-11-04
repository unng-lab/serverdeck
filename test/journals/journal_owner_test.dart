import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/actor.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/journals/journal_models.dart';
import 'package:serverdeck/journals/journal_owner.dart';
import 'package:serverdeck/journals/journal_port.dart';
import 'package:serverdeck/journals/journal_protocol.dart';
import 'package:serverdeck/runtime/owned_work.dart';
import 'package:serverdeck/storage/records.dart';

import '../fixtures/domain_repository.dart';
import '../fixtures/feature_harness.dart' show FeatureClock, featureId;

class FakeJournalConnection implements JournalConnectionPort {
  final stream = StreamController<void>.broadcast();
  final requests = <JournalRequest>[];
  bool connected = true;
  String session = 'session';
  Future<JournalReply> Function(JournalRequest)? respond;
  int cancelled = 0;
  @override
  Stream<void> get changes => stream.stream;
  @override
  ConnectionView connection(String id) => ConnectionView(
    state: connected ? ConnectionState.connected : ConnectionState.disconnected,
    sessionId: connected ? session : null,
  );
  @override
  JournalJob beginJournal(
    UiActor actor,
    String profileId,
    String sessionId, {
    required int expectedConnectionRevision,
    required JournalRequest request,
    required WorkCancellation cancellation,
  }) {
    requests.add(request);
    return JournalJob(
      respond?.call(request) ?? Future.value(JournalReply()),
      () {
        cancelled++;
      },
    );
  }
}

class JournalHarness {
  final repository = MemoryDomainRepository(),
      clock = FeatureClock(),
      connection = FakeJournalConnection();
  late final JournalsOwner owner;
  int next = 100;
  JournalHarness() {
    repository.state.profiles['a'] = Profile()
      ..profileId = 'a'
      ..endpointId = 'e';
    repository.state.endpoints['e'] = EndpointTrust()
      ..endpointId = 'e'
      ..acceptedKeyBytes = [1];
    owner = JournalsOwner(
      repository: repository,
      actor: ActorAuthority(featureId(1)).ui,
      connections: connection,
      newId: () => featureId(next++),
      utcNow: clock.now,
      monotonicNow: clock.monotonic,
      schedule: clock.schedule,
    );
  }
  Future<void> dispose() async {
    await owner.dispose();
    await connection.stream.close();
  }

  Future<void> tick() async {
    clock.advance(const Duration(seconds: 5));
    await owner.reconcile();
    await owner.drain();
  }
}

void main() {
  test(
    'previously successful sources show waiting when due behind another source',
    () async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      await h.owner.start();
      final a = await h.owner.add('a', JournalKind.journal, 'a.service', 'A');
      for (var i = 0; i < 15; i++) {
        await h.owner.add('a', JournalKind.journal, 's$i.service', 'S$i');
      }
      h.connection.respond = (_) async => JournalReply(
        cursor: 'c',
        events: [const JournalEntry(id: 'c', receivedAt: 0, text: 'old')],
      );
      await h.tick();
      expect(h.owner.payload(a).partial, isTrue);
      final held = Completer<JournalReply>();
      h.connection.respond = (_) => held.future;
      h.clock.advance(const Duration(seconds: 5));
      await Future<void>.delayed(Duration.zero);
      expect(h.owner.status(h.owner.sources('a').first), JournalStatus.waiting);
      expect(h.owner.entries(a).single.text, 'old');
      held.complete(JournalReply());
      await h.owner.drain();
    },
  );
  test(
    'explicit source persists, batches dedupe and cursor failure recovers',
    () async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      var step = 0;
      h.connection.respond = (r) async {
        step++;
        if (step == 2)
          return JournalReply(
            failure: JournalStatus.unavailable,
            cursorRejected: true,
          );
        return JournalReply(
          cursor: 'c$step',
          events: [JournalEntry(id: 'same', receivedAt: 0, text: 'hello')],
        );
      };
      await h.owner.start();
      final id = await h.owner.add(
        'a',
        JournalKind.journal,
        'a.service',
        'Service',
      );
      await h.tick();
      expect(h.owner.entries(id).single.text, 'hello');
      await h.tick();
      await h.tick();
      expect(h.connection.requests.last.cursor, isNull);
      expect(h.owner.entries(id), hasLength(1));
      expect(h.owner.payload(id).partial, isTrue);
    },
  );
  test(
    'disabled history expires at exact hour and survives owner restart',
    () async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      await h.owner.start();
      final id = await h.owner.add('a', JournalKind.journal, 'a.service', 'A');
      await h.repository.write((r) {
        final s = r.journalSource(id)!;
        s.enabled = false;
        s.payload = JournalPayload(
          entries: [
            JournalEntry(id: 'x', receivedAt: h.clock.utc, text: 'saved'),
          ],
        ).encode();
        r.putJournalSource(s);
      });
      expect(h.owner.entries(id).single.text, 'saved');
      h.clock.utc += 3600000;
      expect(h.owner.entries(id), isEmpty);
      await h.owner.reconcile();
      expect(
        JournalPayload.decode(h.repository.state.journalSources[id]!.payload)
            .entries,
        isEmpty,
      );
    },
  );
  test(
    'failed storage leaves checkpoint and late disabled batch cannot commit',
    () async {
      final h = JournalHarness();
      addTearDown(h.dispose);
      await h.owner.start();
      final id = await h.owner.add('a', JournalKind.journal, 'a.service', 'A');
      final held = Completer<JournalReply>();
      h.connection.respond = (_) => held.future;
      final running = h.owner.reconcile();
      await Future<void>.delayed(Duration.zero);
      await h.owner.setEnabled(id, false);
      held.complete(
        JournalReply(
          cursor: 'late',
          events: [JournalEntry(id: 'late', receivedAt: 0, text: 'late')],
        ),
      );
      await running;
      await h.owner.drain();
      expect(h.owner.entries(id), isEmpty);
      expect(h.owner.payload(id).checkpoint, isEmpty);
      h.repository.failCommit = true;
      await expectLater(h.owner.rename(id, 'new name'), throwsA(anything));
      expect(h.owner.sources('a').single.name, 'A');
    },
  );
  test(
    'connection revision keeps settings atomically and clears history',
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
      await h.repository.write((r) {
        final p = r.profile('a')!..connectionRevision = 2;
        r.putProfile(p);
      });
      final s = h.owner.sources('a').single;
      expect(
        (s.sourceId, s.kind, s.target, s.name, s.enabled, s.connectionRevision),
        (id, 'file', '/opt/app.log', 'App', true, 2),
      );
      expect(h.owner.payload(id).entries, isEmpty);
      expect(h.owner.payload(id).partial, isTrue);
      await h.repository.write((r) => r.deleteProfile('a'));
      expect(h.repository.state.journalSources, isEmpty);
    },
  );
}
