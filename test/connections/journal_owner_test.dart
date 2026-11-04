import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/actor.dart';
import 'package:serverdeck/journals/journal_models.dart';
import 'package:serverdeck/journals/journal_protocol.dart';
import 'package:serverdeck/runtime/owned_work.dart';
import 'package:serverdeck/monitoring/linux_metrics.dart';

import 'connection_owner_test.dart' as fixture;

void main() {
  test(
    'FIFO gives both collectors progress across repeated phase collisions',
    () async {
      final h = fixture.Harness();
      addTearDown(h.dispose);
      final s = await h.connected();
      final profile = fixture.id(1),
          session = h.owner.connection(fixture.id(1)).sessionId!;
      for (var cycle = 0; cycle < 4; cycle++) {
        final held = Completer<LinuxSample>();
        s.collection = held;
        final monitoring = h.owner.beginMonitoring(
          h.actors.ui,
          profile,
          session,
          expectedConnectionRevision: 1,
          cancellation: WorkCancellation(),
        );
        await fixture.turns();
        h.clock.advance(const Duration(milliseconds: 100));
        final journal = h.owner.beginJournal(
          h.actors.ui,
          profile,
          session,
          expectedConnectionRevision: 1,
          request: const JournalRequest.discover(),
          cancellation: WorkCancellation(),
        );
        await fixture.turns();
        expect(s.journalCalls, cycle);
        h.clock.advance(const Duration(milliseconds: 900));
        held.complete(const LinuxSample(memoryPercent: 25));
        expect((await monitoring.result).memoryPercent, 25);
        expect((await journal.result).units, ['a.service']);
        expect(s.journalCalls, cycle + 1);
        await h.owner.drain();
        h.clock.advance(const Duration(seconds: 4));
      }
      expect(s.collections, 4);
      expect(s.journalCalls, 4);
    },
  );
  test(
    'cancelled FIFO waiter never dispatches or closes competing session',
    () async {
      final h = fixture.Harness();
      addTearDown(h.dispose);
      final s = await h.connected();
      final profile = fixture.id(1),
          session = h.owner.connection(fixture.id(1)).sessionId!;
      final held = Completer<LinuxSample>();
      s.collection = held;
      final monitoring = h.owner.beginMonitoring(
        h.actors.ui,
        profile,
        session,
        expectedConnectionRevision: 1,
        cancellation: WorkCancellation(),
      );
      await fixture.turns();
      final journal = h.owner.beginJournal(
        h.actors.ui,
        profile,
        session,
        expectedConnectionRevision: 1,
        request: const JournalRequest.discover(),
        cancellation: WorkCancellation(),
      );
      await fixture.turns();
      journal.cancel();
      expect((await journal.result).failure, JournalStatus.paused);
      expect(s.journalCalls, 0);
      expect(s.closed, isFalse);
      held.complete(const LinuxSample(memoryPercent: 25));
      await monitoring.result;
      await h.owner.drain();
      expect(s.journalCalls, 0);
      final next = await h.owner
          .beginJournal(
            h.actors.ui,
            profile,
            session,
            expectedConnectionRevision: 1,
            request: const JournalRequest.discover(),
            cancellation: WorkCancellation(),
          )
          .result;
      expect(next.failure, isNull);
      expect(s.journalCalls, 1);
    },
  );
  test(
    'typed journal checks UI issuer and exact owned session and revision',
    () async {
      final h = fixture.Harness();
      addTearDown(h.dispose);
      final s = await h.connected();
      final id = fixture.id(1),
          session = h.owner.connection(fixture.id(1)).sessionId!;
      for (final input in [
        (ActorAuthority(fixture.id(900)).ui, session, 1),
        (h.actors.ui, 'wrong', 1),
        (h.actors.ui, session, 2),
      ]) {
        final reply = await h.owner
            .beginJournal(
              input.$1,
              id,
              input.$2,
              expectedConnectionRevision: input.$3,
              request: const JournalRequest.discover(),
              cancellation: WorkCancellation(),
            )
            .result;
        expect(reply.failure, JournalStatus.disconnected);
      }
      expect(s.journalCalls, 0);
      final reply = await h.owner
          .beginJournal(
            h.actors.ui,
            id,
            session,
            expectedConnectionRevision: 1,
            request: const JournalRequest.discover(),
            cancellation: WorkCancellation(),
          )
          .result;
      expect(reply.units, ['a.service']);
      expect(s.journalCalls, 1);
    },
  );
  for (final mutation in ['connection', 'credential', 'trust', 'delete']) {
    test('late journal result is discarded after $mutation fence', () async {
      final h = fixture.Harness();
      addTearDown(h.dispose);
      final s = await h.connected();
      final held = Completer<JournalReply>();
      s.journalReply = held;
      final job = h.owner.beginJournal(
        h.actors.ui,
        fixture.id(1),
        h.owner.connection(fixture.id(1)).sessionId!,
        expectedConnectionRevision: 1,
        request: const JournalRequest.discover(),
        cancellation: WorkCancellation(),
      );
      await fixture.turns();
      expect(s.journalCalls, 1);
      final p = h.repository.state.profiles[fixture.id(1)]!;
      switch (mutation) {
        case 'connection':
          p.connectionRevision++;
        case 'credential':
          h.repository.state.credentials[p.credentialId]!.secretRevision++;
        case 'trust':
          h.repository.state.endpoints[p.endpointId]!.trustRevision++;
        case 'delete':
          h.repository.state.profiles.remove(p.profileId);
      }
      held.complete(JournalReply(units: ['secret.service']));
      final reply = await job.result;
      expect(reply.units, isEmpty);
      expect(reply.failure, isNotNull);
    });
  }
  test('pre-cancel and pending authentication never dispatch, cancellation keeps SSH healthy', () async {
    final h = fixture.Harness();
    addTearDown(h.dispose);
    final s = await h.connected();
    final session = h.owner.connection(fixture.id(1)).sessionId!;
    final pre = await h.owner
        .beginJournal(
          h.actors.ui,
          fixture.id(1),
          session,
          expectedConnectionRevision: 1,
          request: const JournalRequest.discover(),
          cancellation: WorkCancellation()..cancel(),
        )
        .result;
    expect(pre.failure, JournalStatus.paused);
    expect(s.journalCalls, 0);
    await h.owner.drain();
    final held = Completer<JournalReply>();
    s.journalReply = held;
    final job = h.owner.beginJournal(
      h.actors.ui,
      fixture.id(1),
      session,
      expectedConnectionRevision: 1,
      request: const JournalRequest.discover(),
      cancellation: WorkCancellation(),
    );
    await fixture.turns();
    job.cancel();
    expect((await job.result).failure, JournalStatus.paused);
    expect(s.closed, isFalse);
    held.complete(JournalReply());
    await h.owner.drain();
  });
}
