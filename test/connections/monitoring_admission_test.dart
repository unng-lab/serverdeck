import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/actor.dart';
import 'package:serverdeck/monitoring/linux_metrics.dart';
import 'package:serverdeck/monitoring/monitoring_models.dart';
import 'package:serverdeck/runtime/owned_work.dart';

import 'connection_owner_test.dart' as fixture;

void main() {
  test(
    'owner accepts only its UI capability and exact live session/revision',
    () async {
      final h = fixture.Harness();
      addTearDown(h.dispose);
      final s = await h.connected();
      final sessionId = h.owner.connection(fixture.id(1)).sessionId!;
      final foreign = ActorAuthority(fixture.id(901));
      for (final create in [
        () => h.owner.beginMonitoring(
          foreign.ui,
          fixture.id(1),
          sessionId,
          expectedConnectionRevision: 1,
          cancellation: WorkCancellation(),
        ),
        () => h.owner.beginMonitoring(
          h.actors.ui,
          fixture.id(1),
          fixture.id(999),
          expectedConnectionRevision: 1,
          cancellation: WorkCancellation(),
        ),
        () => h.owner.beginMonitoring(
          h.actors.ui,
          fixture.id(1),
          sessionId,
          expectedConnectionRevision: 2,
          cancellation: WorkCancellation(),
        ),
      ]) {
        expect((await create().result).failure, MonitoringReason.disconnected);
      }
      expect(s.collections, 0);
      final result = await h.owner
          .beginMonitoring(
            h.actors.ui,
            fixture.id(1),
            sessionId,
            expectedConnectionRevision: 1,
            cancellation: WorkCancellation(),
          )
          .result;
      expect(result.memoryPercent, 25);
      expect(s.collections, 1);
    },
  );

  test('revoked initiating grant does not own a promoted session', () async {
    final h = fixture.Harness();
    addTearDown(h.dispose);
    final s = await h.connected(actor: h.mcp);
    h.grants.revoked = true;
    await h.owner.cancelPendingClient(h.mcp.clientId);
    final result = await h.owner
        .beginMonitoring(
          h.actors.ui,
          fixture.id(1),
          h.owner.connection(fixture.id(1)).sessionId!,
          expectedConnectionRevision: 1,
          cancellation: WorkCancellation(),
        )
        .result;
    expect(result.memoryPercent, 25);
    expect(s.collections, 1);
  });

  test('revocation before promotion does not permit monitoring pending authentication', () async {
    final h = fixture.Harness();
    addTearDown(h.dispose);
    final s = await h.ready(actor: h.mcp);
    h.grants.revoked = true;
    await h.owner.cancelPendingClient(h.mcp.clientId);
    final result = await h.owner
        .beginMonitoring(
          h.actors.ui,
          fixture.id(1),
          fixture.id(999),
          expectedConnectionRevision: 1,
          cancellation: WorkCancellation(),
        )
        .result;
    expect(result.failure, isNotNull);
    expect(s.collections, 0);
  });

  test('pre-cancellation never dispatches a collector', () async {
    final h = fixture.Harness();
    addTearDown(h.dispose);
    final s = await h.connected();
    final cancel = WorkCancellation()..cancel();
    final result = await h.owner
        .beginMonitoring(
          h.actors.ui,
          fixture.id(1),
          h.owner.connection(fixture.id(1)).sessionId!,
          expectedConnectionRevision: 1,
          cancellation: cancel,
        )
        .result;
    expect(result.failure, MonitoringReason.paused);
    expect(s.collections, 0);
  });

  for (final mutation in ['connection', 'credential', 'trust', 'delete']) {
    test('late result cannot cross $mutation fence', () async {
      final h = fixture.Harness();
      addTearDown(h.dispose);
      final s = await h.connected();
      final pending = Completer<LinuxSample>();
      s.collection = pending;
      final job = h.owner.beginMonitoring(
        h.actors.ui,
        fixture.id(1),
        h.owner.connection(fixture.id(1)).sessionId!,
        expectedConnectionRevision: 1,
        cancellation: WorkCancellation(),
      );
      await fixture.turns();
      expect(s.collections, 1);
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
      pending.complete(const LinuxSample(memoryPercent: 99));
      expect((await job.result).memoryPercent, isNull);
    });
  }

  test(
    'disconnect cancels child promptly and discards a late fake result',
    () async {
      final h = fixture.Harness();
      addTearDown(h.dispose);
      final s = await h.connected();
      final pending = Completer<LinuxSample>();
      s.collection = pending;
      final sessionId = h.owner.connection(fixture.id(1)).sessionId!;
      final job = h.owner.beginMonitoring(
        h.actors.ui,
        fixture.id(1),
        sessionId,
        expectedConnectionRevision: 1,
        cancellation: WorkCancellation(),
      );
      await fixture.turns();
      await h.owner.disconnect(
        h.actors.ui,
        fixture.id(1),
        sessionId: sessionId,
      );
      expect((await job.result).failure, MonitoringReason.disconnected);
      expect(s.collectionCancellation!.isCancelled, isTrue);
      pending.complete(const LinuxSample(memoryPercent: 99));
    },
  );

  test(
    'deadline returns timeout while keeping unresolved local work bounded',
    () async {
      final h = fixture.Harness();
      addTearDown(h.dispose);
      final s = await h.connected();
      final pending = Completer<LinuxSample>();
      s.collection = pending;
      final sessionId = h.owner.connection(fixture.id(1)).sessionId!;
      final job = h.owner.beginMonitoring(
        h.actors.ui,
        fixture.id(1),
        sessionId,
        expectedConnectionRevision: 1,
        cancellation: WorkCancellation(),
      );
      await fixture.turns();
      h.clock.advance(const Duration(seconds: 5));
      expect((await job.result).failure, MonitoringReason.timeout);
      expect(s.collectionCancellation!.isCancelled, isTrue);
      expect(
        (await h.owner
                .beginMonitoring(
                  h.actors.ui,
                  fixture.id(1),
                  sessionId,
                  expectedConnectionRevision: 1,
                  cancellation: WorkCancellation(),
                )
                .result)
            .failure,
        MonitoringReason.cleanupPending,
      );
      expect(s.collections, 1);
      pending.complete(const LinuxSample(memoryPercent: 99));
    },
  );

  test(
    'cancellation while gate admission waits prevents late collection start',
    () async {
      final h = fixture.Harness();
      addTearDown(h.dispose);
      final s = await h.connected();
      final release = Completer<void>();
      var held = false;
      h.state.before = (actor, _) async {
        if (!held && actor is UiActor) {
          held = true;
          await release.future;
        }
      };
      final cancel = WorkCancellation();
      final job = h.owner.beginMonitoring(
        h.actors.ui,
        fixture.id(1),
        h.owner.connection(fixture.id(1)).sessionId!,
        expectedConnectionRevision: 1,
        cancellation: cancel,
      );
      await fixture.turns();
      cancel.cancel();
      expect((await job.result).failure, MonitoringReason.paused);
      release.complete();
      await fixture.turns();
      expect(s.collections, 0);
    },
  );

  test('at most four unresolved collections admitted globally', () async {
    final h = fixture.Harness();
    addTearDown(h.dispose);
    final held = <Completer<LinuxSample>>[];
    final jobs = <Future<LinuxSample>>[];
    for (var i = 1; i <= 5; i++) {
      if (i != 1) h.seed(i, host: 'host$i.invalid');
      final s = await h.connected(profile: fixture.id(i));
      final pending = Completer<LinuxSample>();
      s.collection = pending;
      held.add(pending);
      final job = h.owner.beginMonitoring(
        h.actors.ui,
        fixture.id(i),
        h.owner.connection(fixture.id(i)).sessionId!,
        expectedConnectionRevision: 1,
        cancellation: WorkCancellation(),
      );
      if (i == 5) {
        expect((await job.result).failure, MonitoringReason.cleanupPending);
        expect(s.collections, 0);
      } else {
        jobs.add(job.result);
      }
    }
    for (final pending in held) {
      pending.complete(const LinuxSample(memoryPercent: 50));
    }
    for (final result in await Future.wait(jobs)) {
      expect(result.memoryPercent, 50);
    }
  });

  test('shutdown stops monitoring admission and cancels active jobs', () async {
    final h = fixture.Harness();
    addTearDown(h.dispose);
    final s = await h.connected();
    final pending = Completer<LinuxSample>();
    s.collection = pending;
    final sessionId = h.owner.connection(fixture.id(1)).sessionId!;
    final job = h.owner.beginMonitoring(
      h.actors.ui,
      fixture.id(1),
      sessionId,
      expectedConnectionRevision: 1,
      cancellation: WorkCancellation(),
    );
    await fixture.turns();
    await h.owner.stopAdmission();
    expect((await job.result).failure, MonitoringReason.stopped);
    expect(
      (await h.owner
              .beginMonitoring(
                h.actors.ui,
                fixture.id(1),
                sessionId,
                expectedConnectionRevision: 1,
                cancellation: WorkCancellation(),
              )
              .result)
          .failure,
      MonitoringReason.stopped,
    );
    pending.complete(const LinuxSample(memoryPercent: 99));
  });
}
