import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/monitoring/linux_metrics.dart';
import 'package:serverdeck/monitoring/monitoring_models.dart';

import '../fixtures/monitoring_harness.dart';

LinuxSample cpu(int busy, int idle) => LinuxSample(
  cpu: CpuCounters([busy, 0, 0, idle, 0, 0, 0, 0]),
  memoryPercent: 25,
  diskPercent: 50,
);
void main() {
  for (final terminal in [
    ConnectionState.disconnected,
    ConnectionState.failed,
  ]) {
    test(
      'active return restores canonical reason after $terminal, never paused',
      () async {
        final h = MonitoringHarness();
        addTearDown(h.dispose);
        h.add(1);
        h.port.generations[mid(1)] = 1;
        h.port.views[mid(1)] = ConnectionView(state: terminal);
        h.owner.setActive(true);
        await settle();
        h.owner.setActive(false);
        h.owner.setActive(true);
        await settle();
        expect(h.owner.active, isTrue);
        expect(
          h.owner.snapshot(mid(1)).statusReason,
          MonitoringReason.disconnected,
        );
        expect(h.port.attempts, isEmpty);
      },
    );
  }
  test('freshness expires exactly at15s without a successful update', () async {
    final h = MonitoringHarness();
    addTearDown(h.dispose);
    h.add(1, connected: true);
    h.owner.setActive(true);
    await settle();
    await h.tick(5);
    h.port.holdCollections = true;
    await h.tick(14);
    expect(
      h.owner
          .snapshot(mid(1))
          .readings[MetricKind.memory]!
          .isFresh(h.clock.now()),
      isTrue,
    );
    await h.tick();
    final reading = h.owner.snapshot(mid(1)).readings[MetricKind.memory]!;
    expect(reading.percent, 25);
    expect(reading.isFresh(h.clock.now()), isFalse);
  });
  test(
    'UTC rollback changes only display timestamps, never elapsed freshness',
    () async {
      final h = MonitoringHarness();
      addTearDown(h.dispose);
      h.add(1, connected: true);
      h.owner.setActive(true);
      await settle();
      final time = h.owner
          .snapshot(mid(1))
          .readings[MetricKind.memory]!
          .displayAt;
      h.clock.utcOffset = -100000000;
      await h.tick(1);
      expect(
        h.owner.snapshot(mid(1)).readings[MetricKind.memory]!.displayAt,
        time,
      );
      expect(
        h.owner
            .snapshot(mid(1))
            .readings[MetricKind.memory]!
            .isFresh(h.clock.now()),
        isTrue,
      );
    },
  );
  test('partial invalid sample preserves last value as stale, other metrics update', () async {
    final h = MonitoringHarness();
    addTearDown(h.dispose);
    h.add(1, connected: true);
    h.owner.setActive(true);
    await settle();
    final time = h.owner
        .snapshot(mid(1))
        .readings[MetricKind.memory]!
        .displayAt;
    h.port.samples[mid(1)] = Queue.of([
      LinuxSample(
        cpu: CpuCounters([20, 0, 0, 180, 0, 0, 0, 0]),
        diskPercent: 75,
        memoryReason: MonitoringReason.invalidResponse,
      ),
    ]);
    await h.tick(5);
    final s = h.owner.snapshot(mid(1));
    expect(s.readings[MetricKind.memory]!.percent, 25);
    expect(s.readings[MetricKind.memory]!.displayAt, time);
    expect(s.readings[MetricKind.memory]!.isFresh(h.clock.now()), isFalse);
    expect(s.readings[MetricKind.disk]!.percent, 75);
    expect(s.readings[MetricKind.disk]!.isFresh(h.clock.now()), isTrue);
    expect(s.readings[MetricKind.cpu]!.percent, 10);
  });
  for (final failure in [
    MonitoringReason.timeout,
    MonitoringReason.outputLimit,
    MonitoringReason.cleanupPending,
    MonitoringReason.sourceUnavailable,
    MonitoringReason.invalidResponse,
  ]) {
    test(
      'collection failure $failure invalidates data and recovery needs new CPU pair',
      () async {
        final h = MonitoringHarness();
        addTearDown(h.dispose);
        h.add(1, connected: true);
        h.port.samples[mid(1)] = Queue.of([
          cpu(10, 90),
          cpu(20, 180),
          LinuxSample.failed(failure),
          cpu(30, 270),
          cpu(40, 360),
        ]);
        h.owner.setActive(true);
        await settle();
        await h.tick(5);
        await h.tick(5);
        final failed = h.owner.snapshot(mid(1));
        expect(failed.statusReason, failure);
        expect(
          failed.readings[MetricKind.memory]!.isFresh(h.clock.now()),
          isFalse,
        );
        await h.tick(5);
        expect(
          h.owner
              .snapshot(mid(1))
              .readings[MetricKind.cpu]!
              .isFresh(h.clock.now()),
          isFalse,
        );
        expect(
          h.owner
              .snapshot(mid(1))
              .readings[MetricKind.memory]!
              .isFresh(h.clock.now()),
          isTrue,
        );
        await h.tick(5);
        expect(h.owner.snapshot(mid(1)).readings[MetricKind.cpu]!.percent, 10);
      },
    );
  }
  test(
    'CPU reset is invalid, then next valid pair establishes new baseline',
    () async {
      final h = MonitoringHarness();
      addTearDown(h.dispose);
      h.add(1, connected: true);
      h.port.samples[mid(1)] = Queue.of([
        cpu(10, 90),
        cpu(20, 180),
        cpu(0, 0),
        cpu(10, 90),
        cpu(20, 180),
      ]);
      h.owner.setActive(true);
      await settle();
      await h.tick(5);
      await h.tick(5);
      expect(
        h.owner.snapshot(mid(1)).readings[MetricKind.cpu]!.reason,
        MonitoringReason.invalidResponse,
      );
      await h.tick(5);
      expect(
        h.owner.snapshot(mid(1)).readings[MetricKind.cpu]!.reason,
        MonitoringReason.baseline,
      );
      await h.tick(5);
      expect(
        h.owner
            .snapshot(mid(1))
            .readings[MetricKind.cpu]!
            .isFresh(h.clock.now()),
        isTrue,
      );
    },
  );
  test(
    'new canonical session hides old values immediately, ignores old result',
    () async {
      final h = MonitoringHarness();
      addTearDown(h.dispose);
      h.add(1, connected: true);
      h.owner.setActive(true);
      await settle();
      h.port.holdCollections = true;
      h.port.completeOnCancel = false;
      await h.tick(5);
      final old = h.port.pending.last;
      h.port.connected(mid(1));
      expect(
        h.owner.snapshot(mid(1)).readings[MetricKind.memory]!.percent,
        isNull,
      );
      h.port.emit();
      await settle();
      old.completer.complete(const LinuxSample(memoryPercent: 99));
      await settle();
      expect(
        h.owner.snapshot(mid(1)).readings[MetricKind.memory]!.percent,
        isNull,
      );
      h.port.pending.last.completer.complete(
        const LinuxSample(memoryPercent: 30),
      );
      await settle();
      expect(h.owner.snapshot(mid(1)).readings[MetricKind.memory]!.percent, 30);
    },
  );
  test(
    'rename retains baseline while a connection revision change clears it',
    () async {
      final h = MonitoringHarness();
      addTearDown(h.dispose);
      h.add(1, connected: true);
      h.owner.setActive(true);
      await settle();
      h.operations.items[0] = profile(1, revision: 2, name: 'Renamed');
      await h.tick(5);
      expect(h.owner.profiles.single.displayName, 'Renamed');
      expect(h.owner.snapshot(mid(1)).readings[MetricKind.cpu]!.percent, 10);
      h.operations.items[0] = profile(1, revision: 3, connectionRevision: 2);
      h.port.generations[mid(1)] = 2;
      h.port.views[mid(1)] = const ConnectionView(
        state: ConnectionState.disconnected,
      );
      h.port.emit();
      await settle();
      expect(
        h.owner.snapshot(mid(1)).readings[MetricKind.memory]!.percent,
        isNull,
      );
      h.port.connected(mid(1));
      h.port.emit();
      await settle();
      expect(
        h.owner.snapshot(mid(1)).readings[MetricKind.cpu]!.percent,
        isNull,
      );
    },
  );
  test(
    'hide cancels collection, keeps SSH, resume clears CPU baseline',
    () async {
      final h = MonitoringHarness();
      addTearDown(h.dispose);
      h.add(1, connected: true);
      h.owner.setActive(true);
      await settle();
      await h.tick(5);
      h.port.holdCollections = true;
      await h.tick(5);
      h.owner.setActive(false);
      await settle();
      expect(h.port.cancelled, greaterThan(0));
      expect(h.port.connection(mid(1)).state, ConnectionState.connected);
      expect(
        h.owner
            .snapshot(mid(1))
            .readings[MetricKind.memory]!
            .isFresh(h.clock.now()),
        isFalse,
      );
      final count = h.port.collected.length;
      await h.tick(20);
      expect(h.port.collected, hasLength(count));
      h.port.holdCollections = false;
      h.owner.setActive(true);
      await settle();
      expect(
        h.owner
            .snapshot(mid(1))
            .readings[MetricKind.cpu]!
            .isFresh(h.clock.now()),
        isFalse,
      );
      expect(
        h.owner
            .snapshot(mid(1))
            .readings[MetricKind.memory]!
            .isFresh(h.clock.now()),
        isTrue,
      );
    },
  );
  test(
    'unsupported OS is sticky for session including pause, reset on reconnect',
    () async {
      final h = MonitoringHarness();
      addTearDown(h.dispose);
      h.add(1, connected: true);
      h.port.samples[mid(1)] = Queue.of([
        const LinuxSample.failed(MonitoringReason.unsupportedOs),
      ]);
      h.owner.setActive(true);
      await settle();
      await h.tick(20);
      expect(h.port.collected, hasLength(1));
      h.owner.setActive(false);
      h.owner.setActive(true);
      await settle();
      expect(
        h.owner.snapshot(mid(1)).statusReason,
        MonitoringReason.unsupportedOs,
      );
      expect(h.port.collected, hasLength(1));
      h.port.connected(mid(1));
      h.port.emit();
      await settle();
      expect(h.port.collected, hasLength(2));
      expect(h.owner.snapshot(mid(1)).readings[MetricKind.memory]!.percent, 25);
    },
  );
  test(
    'manual disconnect immediately stales data; reopen never auto reconnects',
    () async {
      final h = MonitoringHarness();
      addTearDown(h.dispose);
      h.add(1, connected: true);
      h.owner.setActive(true);
      await settle();
      h.port.views[mid(1)] = const ConnectionView(
        state: ConnectionState.disconnected,
      );
      expect(
        h.owner
            .snapshot(mid(1))
            .readings[MetricKind.memory]!
            .isFresh(h.clock.now()),
        isFalse,
      );
      h.port.emit();
      await settle();
      h.owner.setActive(false);
      h.owner.setActive(true);
      await settle();
      await h.tick(5);
      expect(h.port.attempts, isEmpty);
    },
  );
  test(
    'shutdown cancels/drains without closing canonical SSH or reviving timer',
    () async {
      final h = MonitoringHarness();
      addTearDown(h.dispose);
      h.add(1, connected: true);
      h.port.holdCollections = true;
      h.owner.setActive(true);
      await settle();
      await h.owner.stopAdmission();
      await h.owner.drain();
      final count = h.port.collected.length;
      await h.tick(10);
      expect(h.port.collected, hasLength(count));
      expect(h.port.connection(mid(1)).state, ConnectionState.connected);
      expect(h.owner.snapshot(mid(1)).statusReason, MonitoringReason.stopped);
      expect(h.clock.events.where((e) => !e.cancelled), isEmpty);
    },
  );
}
