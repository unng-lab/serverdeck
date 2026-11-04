import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/actor.dart';
import 'package:serverdeck/domain/app_operations.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/monitoring/linux_metrics.dart';
import 'package:serverdeck/monitoring/monitoring_job.dart';
import 'package:serverdeck/monitoring/monitoring_history.dart';
import 'package:serverdeck/monitoring/monitoring_models.dart';
import 'package:serverdeck/monitoring/monitoring_owner.dart';
import 'package:serverdeck/monitoring/monitoring_port.dart';
import 'package:serverdeck/runtime/owned_work.dart';

String mid(int n) =>
    '${n.toRadixString(16).padLeft(8, '0')}-0000-4000-8000-000000000000';
Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ProfileView profile(
  int n, {
  int revision = 1,
  int connectionRevision = 1,
  String? name,
}) => ProfileView(
  profileId: mid(n),
  revision: revision,
  connectionRevision: connectionRevision,
  displayName: name ?? 'Host$n',
  host: 'host$n.invalid',
  port: 22,
  username: 'unit',
  authKind: AuthKind.password,
  hasCredential: true,
  endpointId: n.toRadixString(16).padLeft(64, '0'),
);

final class ClockEvent {
  ClockEvent(this.at, this.callback);
  final Duration at;
  final void Function() callback;
  bool cancelled = false;
}

final class MonitoringClock {
  Duration value = Duration.zero;
  int utcOffset = 0;
  final events = <ClockEvent>[];
  Duration now() => value;
  int utc() => 1700000000000 + value.inMilliseconds + utcOffset;
  void Function() schedule(Duration duration, void Function() callback) {
    final event = ClockEvent(value + duration, callback);
    events.add(event);
    return () => event.cancelled = true;
  }

  void advance(Duration duration) {
    final target = value + duration;
    while (true) {
      final due = events.where((e) => !e.cancelled && e.at <= target).toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      if (due.isEmpty) break;
      final e = due.first;
      value = e.at;
      e.cancelled = true;
      e.callback();
    }
    value = target;
  }
}

final class MonitoringOperations extends Fake implements AppOperations {
  final items = <ProfileView>[];
  int lists = 0;
  Completer<void>? holdList;
  Object? failure;
  OperationMeta get meta =>
      OperationMeta(dataRevision: 1, ownerEpoch: mid(900));
  @override
  Future<OperationResult<ProfilesPage>> listProfiles(
    Actor actor, {
    int limit = 50,
    String? cursor,
  }) async {
    lists++;
    await holdList?.future;
    if (failure != null) throw failure!;
    final start = cursor == null ? 0 : int.parse(cursor);
    final end = (start + limit).clamp(0, items.length);
    return OperationResult.success(
      ProfilesPage(
        items: items.sublist(start, end),
        snapshotRevision: 1,
        nextCursor: end < items.length ? '$end' : null,
      ),
      meta,
    );
  }
}

final class PendingCollection {
  PendingCollection(this.id, this.completer);
  final String id;
  final Completer<LinuxSample> completer;
}

final class MonitoringPort implements MonitoringConnectionPort {
  final views = <String, ConnectionView>{}, generations = <String, int>{};
  final attempts = <String>[], admitted = <String>[], collected = <String>[];
  final pending = <PendingCollection>[];
  final samples = <String, Queue<LinuxSample>>{};
  final _changes = StreamController<void>.broadcast(sync: true);
  ConnectionState autoState = ConnectionState.connecting;
  bool holdCollections = false, completeOnCancel = true;
  Completer<void>? holdAdmission;
  OperationFailure? admissionFailure;
  int cancelled = 0, sessions = 0;
  @override
  Stream<void> get changes => _changes.stream;
  void emit() => _changes.add(null);
  @override
  ConnectionView connection(String id) =>
      views[id] ?? const ConnectionView(state: ConnectionState.disconnected);
  @override
  int generation(String id) => generations[id] ?? 0;
  void connected(String id) {
    generations[id] = (generations[id] ?? 0) + 1;
    views[id] = ConnectionView(
      state: ConnectionState.connected,
      sessionId: mid(2000 + (++sessions)),
      attemptId: mid(1000 + sessions),
    );
  }

  @override
  Future<MonitoringConnectResult> connectForMonitoring(
    UiActor actor,
    String id, {
    required int expectedRevision,
    required WorkCancellation cancellation,
  }) async {
    attempts.add(id);
    final failure = admissionFailure;
    if (failure != null) {
      final outcome = OperationResult<ConnectionView>.failure(failure);
      await holdAdmission?.future;
      return MonitoringConnectResult(outcome);
    }
    await holdAdmission?.future;
    if (cancellation.isCancelled || generation(id) > 0) {
      return MonitoringConnectResult(
        const OperationResult.failure(OperationFailure(FailureCode.conflict)),
        cancelledBeforeAdmission: cancellation.isCancelled,
      );
    }
    admitted.add(id);
    generations[id] = 1;
    views[id] = ConnectionView(
      state: autoState,
      attemptId: mid(1000 + admitted.length),
    );
    emit();
    return MonitoringConnectResult(
      OperationResult.success(
        views[id]!,
        OperationMeta(dataRevision: 1, ownerEpoch: mid(900)),
      ),
    );
  }

  @override
  MonitoringJob beginMonitoring(
    UiActor actor,
    String id,
    String sessionId, {
    required int expectedConnectionRevision,
    required WorkCancellation cancellation,
  }) {
    collected.add(id);
    final result = Completer<LinuxSample>();
    pending.add(PendingCollection(id, result));
    void cancel() {
      cancelled++;
      if (completeOnCancel && !result.isCompleted)
        result.complete(const LinuxSample.failed(MonitoringReason.paused));
    }

    final unlisten = cancellation.listen(cancel);
    final future = result.future.whenComplete(unlisten);
    if (!holdCollections) {
      final queue = samples[id];
      final count = collected.where((x) => x == id).length;
      result.complete(
        queue != null && queue.isNotEmpty
            ? queue.removeFirst()
            : LinuxSample(
                cpu: CpuCounters([count * 10, 0, 0, count * 90, 0, 0, 0, 0]),
                memoryPercent: 25,
                diskPercent: 50,
              ),
      );
    }
    return MonitoringJob(future, cancel);
  }

  Future<void> dispose() async {
    await _changes.close();
  }
}

final class MonitoringHarness {
  MonitoringHarness({
    bool autoAllowed = true,
    MemoryHistoryStore? historyStore,
    String? ownerEpoch,
  }) : historyStore = historyStore ?? MemoryHistoryStore(),
       actors = ActorAuthority(ownerEpoch ?? mid(900)) {
    owner = MonitoringOwner(
      historyStore: this.historyStore,
      operations: operations,
      actor: actors.ui,
      connections: port,
      startupAutoAllowed: autoAllowed,
      monotonicNow: clock.now,
      utcNow: clock.utc,
      schedule: clock.schedule,
    );
  }
  final operations = MonitoringOperations(),
      port = MonitoringPort(),
      clock = MonitoringClock();
  final ActorAuthority actors;
  late final MonitoringOwner owner;
  final MemoryHistoryStore historyStore;
  void add(int n, {bool connected = false}) {
    operations.items.add(profile(n));
    if (connected) port.connected(mid(n));
  }

  Future<void> tick([int seconds = 1]) async {
    clock.advance(Duration(seconds: seconds));
    await settle();
  }

  Future<void> dispose() async {
    await owner.stopAdmission();
    if (!(operations.holdList?.isCompleted ?? true))
      operations.holdList!.complete();
    if (!(port.holdAdmission?.isCompleted ?? true))
      port.holdAdmission!.complete();
    for (final p in port.pending) {
      if (!p.completer.isCompleted)
        p.completer.complete(
          const LinuxSample.failed(MonitoringReason.stopped),
        );
    }
    await owner.dispose();
    await port.dispose();
  }
}

final class MemoryHistoryStore implements MonitoringHistoryStore {
  final values = <(String, int), String>{};
  bool failRead = false, failWrite = false;
  Completer<void>? holdWrite;
  int writes = 0;
  @override
  String? loadHistory(String id, int revision) {
    if (failRead) throw StateError('synthetic history read failure');
    return values[(id, revision)];
  }

  @override
  Future<void> saveHistory(
    String id,
    int revision,
    String payload,
    bool Function() canCommit,
  ) async {
    await holdWrite?.future;
    if (!canCommit()) return;
    if (failWrite) throw StateError('synthetic history write failure');
    values[(id, revision)] = payload;
    writes++;
  }
}
