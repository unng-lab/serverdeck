import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/monitoring/linux_metrics.dart';
import 'package:serverdeck/monitoring/monitoring_models.dart';

import '../fixtures/monitoring_harness.dart';

void main() {
  test('completed pre-generation failure is not retried after hide crosses result delivery', () async {
    final h = MonitoringHarness();
    addTearDown(h.dispose);
    h.add(1);
    h.port.admissionFailure = const OperationFailure(
      FailureCode.resourceExhausted,
    );
    h.port.holdAdmission = Completer<void>();
    h.owner.setActive(true);
    await settle();
    expect(h.port.attempts, hasLength(1));
    h.owner.setActive(false);
    h.port.holdAdmission!.complete();
    await settle();
    h.owner.setActive(true);
    await settle();
    await h.tick(5);
    expect(h.port.attempts, hasLength(1));
    expect(h.port.admitted, isEmpty);
  });
  test('inactive owner does nothing; auto attempts hold four slots through prompts', () async {
    final h = MonitoringHarness();
    addTearDown(h.dispose);
    for (var n = 1; n <= 6; n++) h.add(n);
    await h.owner.reconcile();
    expect(h.port.attempts, isEmpty);
    h.port.autoState = ConnectionState.needTrust;
    h.owner.setActive(true);
    await settle();
    expect(h.port.admitted, [mid(1), mid(2), mid(3), mid(4)]);
    await h.tick(5);
    expect(h.port.admitted, hasLength(4));
    h.port.views[mid(1)] = const ConnectionView(state: ConnectionState.failed);
    h.port.emit();
    await settle();
    expect(h.port.admitted, [mid(1), mid(2), mid(3), mid(4), mid(5)]);
    expect(h.port.admitted.where((id) => id == mid(1)), hasLength(1));
  });
  test('all pages are included without exceeding attempt capacity', () async {
    final h = MonitoringHarness();
    addTearDown(h.dispose);
    for (var n = 1; n <= 205; n++) h.add(n);
    h.owner.setActive(true);
    await settle();
    expect(h.owner.profileCount, 205);
    expect(h.operations.lists, greaterThanOrEqualTo(3));
    expect(h.port.admitted, hasLength(4));
  });
  test('new profile on return included but inactive MCP connect/disconnect history suppressed', () async {
    final h = MonitoringHarness();
    addTearDown(h.dispose);
    h.add(1);
    h.owner.setActive(true);
    await settle();
    h.owner.setActive(false);
    h.add(2);
    h.add(3);
    h.port.generations[mid(2)] = 2;
    h.port.views[mid(2)] = const ConnectionView(
      state: ConnectionState.disconnected,
    );
    h.owner.setActive(true);
    await settle();
    expect(h.port.admitted, [mid(1), mid(3)]);
    h.operations.items[1] = profile(2, revision: 2, connectionRevision: 2);
    await h.tick(5);
    expect(h.port.admitted, [mid(1), mid(3)]);
  });
  test(
    'manual attempt between snapshot and admission wins; never auto retried',
    () async {
      final h = MonitoringHarness();
      addTearDown(h.dispose);
      h.add(1);
      h.port.holdAdmission = Completer<void>();
      h.owner.setActive(true);
      await settle();
      expect(h.port.attempts, hasLength(1));
      h.port.generations[mid(1)] = 2;
      h.port.views[mid(1)] = const ConnectionView(
        state: ConnectionState.disconnected,
      );
      h.port.holdAdmission!.complete();
      await settle();
      await h.tick(10);
      expect(h.port.admitted, isEmpty);
      expect(h.port.attempts, hasLength(1));
    },
  );
  test('hide before queued admission does not start SSH and unstarted profile resumes on return', () async {
    final h = MonitoringHarness();
    addTearDown(h.dispose);
    h.add(1);
    h.port.holdAdmission = Completer<void>();
    h.owner.setActive(true);
    await settle();
    h.owner.setActive(false);
    h.port.holdAdmission!.complete();
    await settle();
    expect(h.port.admitted, isEmpty);
    h.owner.setActive(true);
    await settle();
    expect(h.port.admitted, [mid(1)]);
  });
  test('late profile list cannot launch work after deactivation', () async {
    final h = MonitoringHarness();
    addTearDown(h.dispose);
    h.add(1);
    h.operations.holdList = Completer<void>();
    h.owner.setActive(true);
    await settle();
    h.owner.setActive(false);
    h.operations.holdList!.complete();
    await settle();
    expect(h.port.attempts, isEmpty);
    h.owner.setActive(true);
    await settle();
    expect(h.port.admitted, [mid(1)]);
  });
  test(
    'live sessions reused; first complete CPU pair by five-second cycle',
    () async {
      final h = MonitoringHarness();
      addTearDown(h.dispose);
      for (var n = 1; n <= 4; n++) h.add(n, connected: true);
      h.owner.setActive(true);
      await settle();
      expect(h.port.attempts, isEmpty);
      expect(h.port.collected, hasLength(4));
      final first = h.owner.snapshot(mid(1));
      expect(first.readings[MetricKind.cpu]!.percent, isNull);
      expect(first.readings[MetricKind.memory]!.percent, 25);
      await h.tick(5);
      final next = h.owner.snapshot(mid(1));
      expect(next.readings[MetricKind.cpu]!.percent, 10);
      expect(next.readings[MetricKind.cpu]!.isFresh(h.clock.now()), isTrue);
    },
  );
  test(
    'fair queue visits waiting servers before repeating served servers',
    () async {
      final h = MonitoringHarness();
      addTearDown(h.dispose);
      for (var n = 1; n <= 6; n++) h.add(n, connected: true);
      h.port.holdCollections = true;
      h.owner.setActive(true);
      await settle();
      expect(h.port.collected, [mid(1), mid(2), mid(3), mid(4)]);
      for (final p in List.of(h.port.pending))
        p.completer.complete(const LinuxSample(memoryPercent: 30));
      await settle();
      expect(h.port.collected.take(6), [
        mid(1),
        mid(2),
        mid(3),
        mid(4),
        mid(5),
        mid(6),
      ]);
    },
  );
  test(
    'slow collection never overlaps or accumulates per-profile backlog',
    () async {
      final h = MonitoringHarness();
      addTearDown(h.dispose);
      h.add(1, connected: true);
      h.port.holdCollections = true;
      h.owner.setActive(true);
      await settle();
      await h.tick(20);
      expect(h.port.collected, hasLength(1));
      h.port.pending.single.completer.complete(
        const LinuxSample(memoryPercent: 20),
      );
      await settle();
      expect(h.port.collected, hasLength(2));
    },
  );
  test(
    'deletion prunes state and discards an old non-cooperative result',
    () async {
      final h = MonitoringHarness();
      addTearDown(h.dispose);
      h.add(1, connected: true);
      h.port.holdCollections = true;
      h.port.completeOnCancel = false;
      h.owner.setActive(true);
      await settle();
      h.operations.items.clear();
      await h.owner.reconcile();
      expect(h.owner.profileCount, 0);
      h.port.pending.single.completer.complete(
        const LinuxSample(memoryPercent: 99),
      );
      await settle();
      expect(
        h.owner.snapshot(mid(1)).readings[MetricKind.memory]!.percent,
        isNull,
      );
    },
  );
  test(
    'startup gate needs explicit start even when a manual SSH session exists',
    () async {
      final h = MonitoringHarness(autoAllowed: false);
      addTearDown(h.dispose);
      h.add(1);
      h.add(2, connected: true);
      h.owner.setActive(true);
      await settle();
      expect(h.owner.startupBlocked, isTrue);
      expect(h.port.attempts, isEmpty);
      expect(h.port.collected, isEmpty);
      h.owner.startExplicitly();
      await settle();
      expect(h.port.admitted, [mid(1)]);
      expect(h.port.collected, [mid(2)]);
    },
  );
  test(
    'source list failure uses fixed reason and never launches a connection',
    () async {
      final h = MonitoringHarness();
      addTearDown(h.dispose);
      h.add(1);
      h.operations.failure = StateError('synthetic secret');
      h.owner.setActive(true);
      await settle();
      expect(h.owner.error, MonitoringReason.sourceUnavailable);
      expect(h.port.attempts, isEmpty);
    },
  );
}
