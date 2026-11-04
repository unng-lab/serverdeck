import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/monitoring/linux_metrics.dart';
import 'package:serverdeck/monitoring/monitoring_history.dart';
import 'package:serverdeck/monitoring/monitoring_models.dart';

import '../fixtures/monitoring_harness.dart';

void main() {
  test('65 minutes retain only last hour and persisted owner restart has no live freshness', () async {
    final store = MemoryHistoryStore();
    final h = MonitoringHarness(historyStore: store);
    addTearDown(h.dispose);
    h.add(1, connected: true);
    h.owner.setActive(true);
    await settle();
    for (var n = 0; n < 780; n++) {
      await h.tick(5);
    }
    final points = h.owner.history(mid(1), 1);
    expect(points, hasLength(720));
    expect(points.every((p) => h.clock.utc() - p.utcMs < 3600000), isTrue);
    expect(HistoryCodec.decode(store.values[(mid(1), 1)]!), hasLength(720));
    final restored = MonitoringHarness(
      historyStore: store,
      autoAllowed: false,
      ownerEpoch: mid(901),
    );
    addTearDown(restored.dispose);
    restored.clock.value = h.clock.value;
    restored.add(1);
    restored.owner.setActive(true);
    await settle();
    expect(restored.owner.history(mid(1), 1), hasLength(720));
    expect(
      restored.owner
          .snapshot(mid(1))
          .readings
          .values
          .every((r) => r.percent == null),
      isTrue,
    );
    expect(restored.port.attempts, isEmpty);
    expect(restored.port.collected, isEmpty);
    expect(restored.owner.startupBlocked, isTrue);
    restored.owner.startExplicitly();
    restored.port.connected(mid(1));
    restored.port.emit();
    await settle();
    expect(
      restored.owner.history(mid(1), 1).last.segment,
      isNot(points.last.segment),
    );
  });

  test('partial/full failure use null, pause/reconnect break, rename retains and revision clears', () async {
    final h = MonitoringHarness();
    addTearDown(h.dispose);
    h.add(1, connected: true);
    h.port.samples[mid(1)] = Queue.of([
      const LinuxSample(memoryPercent: 25, diskPercent: 50),
      const LinuxSample(memoryPercent: 30),
      const LinuxSample.failed(MonitoringReason.timeout),
    ]);
    h.owner.setActive(true);
    await settle();
    await h.tick(5);
    expect(h.owner.history(mid(1), 1).last.memory, 30);
    expect(h.owner.history(mid(1), 1).last.disk, isNull);
    await h.tick(5);
    final failed = h.owner.history(mid(1), 1).last;
    expect([failed.cpu, failed.memory, failed.disk], everyElement(isNull));
    h.owner.setActive(false);
    await h.tick(5);
    h.owner.setActive(true);
    await settle();
    final resumed = h.owner.history(mid(1), 1).last;
    expect(resumed.segment, isNot(failed.segment));
    final count = h.owner.history(mid(1), 1).length;
    h.operations.items[0] = profile(1, name: 'renamed');
    await h.owner.reconcile();
    expect(h.owner.history(mid(1), 1), hasLength(count));
    h.port.views[mid(1)] = const ConnectionView(
      state: ConnectionState.disconnected,
    );
    h.port.emit();
    await settle();
    expect(h.owner.history(mid(1), 1), hasLength(count));
    h.operations.items[0] = profile(1, revision: 2, connectionRevision: 2);
    await h.owner.reconcile();
    expect(h.owner.history(mid(1), 2), isEmpty);
  });

  test('corrupt/read failure block overwrite; retry merges pending and write retry recovers', () async {
    final store = MemoryHistoryStore()..values[(mid(1), 1)] = 'corrupt';
    final h = MonitoringHarness(historyStore: store);
    addTearDown(h.dispose);
    h.add(1, connected: true);
    h.owner.setActive(true);
    await settle();
    expect(h.owner.historyError(mid(1), 1), isTrue);
    expect(store.writes, 0);
    await h.tick(5);
    expect(store.values[(mid(1), 1)], 'corrupt');
    store.values[(mid(1), 1)] = HistoryCodec.encode([
      HistoryPoint(utcMs: h.clock.utc() - 1000, segment: 'older', memory: 15),
    ]);
    h.owner.retryHistory(mid(1), 1);
    await settle();
    expect(h.owner.historyError(mid(1), 1), isFalse);
    expect(h.owner.history(mid(1), 1), hasLength(3));
    store.failWrite = true;
    await h.tick(5);
    expect(h.owner.historyError(mid(1), 1), isTrue);
    expect(
      h.owner
          .snapshot(mid(1))
          .readings[MetricKind.memory]!
          .isFresh(h.owner.now),
      isTrue,
    );
    store.failWrite = false;
    h.owner.retryHistory(mid(1), 1);
    await settle();
    expect(h.owner.historyError(mid(1), 1), isFalse);
    expect(HistoryCodec.decode(store.values[(mid(1), 1)]!), hasLength(4));
  });

  test('queued old revision save cannot overwrite replacement, shutdown drains admitted write', () async {
    final store = MemoryHistoryStore()..holdWrite = Completer<void>();
    final h = MonitoringHarness(historyStore: store);
    addTearDown(h.dispose);
    h.add(1, connected: true);
    h.owner.setActive(true);
    await settle();
    h.operations.items[0] = profile(1, connectionRevision: 2);
    await h.owner.reconcile();
    store.holdWrite!.complete();
    await settle();
    expect(store.values[(mid(1), 1)], isNull);
    expect(store.values[(mid(1), 2)], isNotNull);
    store.holdWrite = Completer<void>();
    await h.tick(5);
    await h.owner.stopAdmission();
    var drained = false;
    final drain = h.owner.drain().then((_) => drained = true);
    await settle();
    expect(drained, isFalse);
    store.holdWrite!.complete();
    await drain;
    expect(HistoryCodec.decode(store.values[(mid(1), 2)]!), hasLength(2));
  });

  test('read faults isolate profiles and UTC rollback cannot extend monotonic hour', () async {
    final store = MemoryHistoryStore()..failRead = true;
    final h = MonitoringHarness(historyStore: store);
    addTearDown(h.dispose);
    h.add(1, connected: true);
    h.owner.setActive(true);
    await settle();
    expect(store.writes, 0);
    store.failRead = false;
    h.owner.retryHistory(mid(1), 1);
    await settle();
    expect(h.owner.historyError(mid(1), 1), isFalse);
    h.owner.setActive(false);
    h.clock.utcOffset = -100000;
    expect(h.owner.history(mid(1), 1), isEmpty);
    await h.tick(3600);
    expect(h.owner.history(mid(1), 1), isEmpty);
  });
}
