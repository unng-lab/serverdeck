import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../domain/actor.dart';
import '../domain/app_operations.dart';
import '../domain/models.dart';
import '../runtime/capability.dart';
import '../runtime/owned_work.dart';
import 'linux_metrics.dart';
import 'monitoring_job.dart';
import 'monitoring_history.dart';
import 'monitoring_models.dart';
import 'monitoring_port.dart';

/// Owns only monitoring projections/work. SSH authority remains in ConnectionOwner.
final class MonitoringOwner implements Listenable, RuntimeCapability {
  MonitoringOwner({
    required this.historyStore,
    required this.operations,
    required this.actor,
    required this.connections,
    required bool startupAutoAllowed,
    Duration Function()? monotonicNow,
    int Function()? utcNow,
    ScheduleOwnedDeadline? schedule,
  }) : _blocked = !startupAutoAllowed,
       _now = monotonicNow,
       _utc = utcNow ?? _systemUtc,
       _schedule = schedule ?? _timer {
    _clock.start();
    _subscription = connections.changes.listen((_) {
      if (_stopped) return;
      _notify(); // Snapshot reads canonical liveness immediately, before async refresh.
      if (_active) unawaited(reconcile());
    });
  }
  final AppOperations operations;
  final MonitoringHistoryStore historyStore;
  final UiActor actor;
  final MonitoringConnectionPort connections;
  final Duration Function()? _now;
  final int Function() _utc;
  final ScheduleOwnedDeadline _schedule;
  final _clock = Stopwatch(), _notifier = _MonitoringNotifier();
  final _entries = <String, _ProfileMonitoring>{};
  final _order = Queue<String>();
  final _pending = <Future<void>>{};
  final _autoJobs = <_ProfileMonitoring, WorkCancellation>{};
  final _jobs = <MonitoringJob, WorkCancellation>{};
  List<ProfileView> _profiles = const [];
  StreamSubscription<void>? _subscription;
  Future<void>? _refresh, _disposal;
  void Function()? _cancelTick;
  bool _active = false,
      _blocked,
      _stopped = false,
      _disposed = false,
      _rerun = false;
  int _epoch = 0;
  Duration _lastHistoryCleanup = Duration.zero;
  MonitoringReason? error;
  @override
  String get id => 'monitoring';
  bool get active => _active && !_stopped;
  bool get startupBlocked => _blocked;
  int get profileCount => _entries.length;
  List<ProfileView> get profiles => _profiles;
  Duration get now => _now?.call() ?? _clock.elapsed;
  static int _systemUtc() => DateTime.now().toUtc().millisecondsSinceEpoch;
  static void Function() _timer(Duration d, void Function() callback) {
    final timer = Timer(d, callback);
    return timer.cancel;
  }

  @override
  void addListener(VoidCallback listener) => _notifier.addListener(listener);
  @override
  void removeListener(VoidCallback listener) =>
      _notifier.removeListener(listener);
  void _notify() {
    if (!_disposed) _notifier.changed();
  }

  void _track(Future<void> work) {
    _pending.add(work);
    work
        .then(
          (_) => _pending.remove(work),
          onError: (Object _, StackTrace __) => _pending.remove(work),
        )
        .ignore();
  }

  ConnectionView _connection(String id) {
    try {
      return connections.connection(id);
    } catch (_) {
      return const ConnectionView(
        state: ConnectionState.failed,
        failureCode: FailureCode.storageUnavailable,
      );
    }
  }

  static bool _connecting(ConnectionState state) => switch (state) {
    ConnectionState.connecting ||
    ConnectionState.needTrust ||
    ConnectionState.needPassphrase ||
    ConnectionState.authenticating => true,
    _ => false,
  };
  void setActive(bool value) {
    if (_stopped || value == _active) return;
    _active = value;
    _epoch++;
    if (!value) {
      _cancelTick?.call();
      _cancelTick = null;
      _cancelWork(MonitoringReason.paused);
    } else {
      _armTick();
      unawaited(reconcile());
    }
    _notify();
  }

  void startExplicitly() {
    if (_stopped || !_blocked) return;
    _blocked = false;
    _notify();
    if (_active) unawaited(reconcile());
  }

  void _armTick() {
    if (!active || _cancelTick != null) return;
    _cancelTick = _schedule(const Duration(seconds: 1), () {
      _cancelTick = null;
      if (!active) return;
      _notify();
      unawaited(reconcile());
      _armTick();
    });
  }

  bool _current(int epoch) => active && epoch == _epoch;
  Future<void> reconcile() {
    if (!active) return Future.value();
    final running = _refresh;
    if (running != null) {
      _rerun = true;
      return running;
    }
    final epoch = _epoch;
    final work = _reconcile(epoch)
        .catchError((Object _) {
          if (_current(epoch)) {
            error = MonitoringReason.sourceUnavailable;
            for (final state in _entries.values)
              _invalidateReadings(state, MonitoringReason.sourceUnavailable);
            _notify();
          }
        })
        .whenComplete(() {
          _refresh = null;
          if (_rerun) {
            _rerun = false;
            if (active) unawaited(reconcile());
          }
        });
    _refresh = work;
    _track(work);
    return work;
  }

  Future<void> _reconcile(int epoch) async {
    final profiles = <ProfileView>[], cursors = <String>{};
    String? cursor;
    do {
      final page = await operations.listProfiles(
        actor,
        limit: 100,
        cursor: cursor,
      );
      if (!_current(epoch)) return;
      if (page.error != null || page.value == null)
        throw StateError('Profile list unavailable');
      profiles.addAll(page.value!.items);
      if (profiles.length > 1000) throw StateError('Profile limit');
      cursor = page.value!.nextCursor;
      if (cursor != null && !cursors.add(cursor))
        throw StateError('Invalid profile cursor');
    } while (cursor != null);
    final ids = profiles.map((p) => p.profileId).toSet();
    if (ids.length != profiles.length) throw StateError('Duplicate profiles');
    for (final id in _entries.keys.where((id) => !ids.contains(id)).toList()) {
      final state = _entries.remove(id)!;
      state.job?.cancel();
      _autoJobs[state]?.cancel();
      _order.remove(id);
    }
    _profiles = List.unmodifiable(profiles);
    error = null;
    for (final profile in profiles) {
      final state = _entries.putIfAbsent(profile.profileId, () {
        _order.addLast(profile.profileId);
        return _ProfileMonitoring(profile);
      });
      final view = _connection(profile.profileId);
      final changedRevision =
          state.profile.connectionRevision != profile.connectionRevision;
      final newSession = view.state == ConnectionState.connected
          ? view.sessionId
          : null;
      if (changedRevision || newSession != state.sessionId) {
        state.job?.cancel();
        state.baseline = null;
        state.unsupportedSession = null;
        if (changedRevision || newSession != null)
          state.readings = {
            for (final k in MetricKind.values) k: const MetricReading.missing(),
          };
        else
          _invalidateReadings(state, MonitoringReason.disconnected);
        state.sessionId = newSession;
        state.dueAt = Duration.zero;
        state.reason = null;
      }
      if (changedRevision) state.history = _ProfileHistory();
      state.profile = profile;
      _loadHistory(state);
      if (view.state == ConnectionState.connected &&
          state.unsupportedSession == view.sessionId) {
        state.reason = MonitoringReason.unsupportedOs;
      }
      if (connections.generation(profile.profileId) > 0 ||
          view.attemptId != null ||
          view.sessionId != null ||
          view.state != ConnectionState.disconnected)
        state.attempted = true;
      if (view.state != ConnectionState.connected) {
        state.baseline = null;
      }
    }
    if (now - _lastHistoryCleanup >= const Duration(minutes: 1)) {
      _lastHistoryCleanup = now;
      for (final state in _entries.values) {
        _pruneHistory(state.history);
        _persistHistory(state);
      }
    }
    if (!_blocked) {
      for (final profile in profiles) {
        if (!_current(epoch)) return;
        if (_autoBusy() >= 4) break;
        final state = _entries[profile.profileId]!;
        final view = _connection(profile.profileId);
        if (!state.attempted &&
            !_autoJobs.containsKey(state) &&
            view.state == ConnectionState.disconnected &&
            connections.generation(profile.profileId) == 0) {
          _startAuto(state, epoch);
        }
      }
      var visited = 0;
      final length = _order.length;
      while (_jobs.length < 4 && visited++ < length && _order.isNotEmpty) {
        final id = _order.removeFirst();
        _order.addLast(id);
        final state = _entries[id]!;
        final view = _connection(id);
        if (state.job == null &&
            view.state == ConnectionState.connected &&
            view.sessionId != null &&
            state.unsupportedSession != view.sessionId &&
            now >= state.dueAt) {
          _startCollection(state, view, epoch);
        }
      }
    }
    _notify();
  }

  int _autoBusy() {
    var count = _autoJobs.length;
    for (final state in _entries.values) {
      if (!_autoJobs.containsKey(state) &&
          _connecting(_connection(state.profile.profileId).state))
        count++;
    }
    return count;
  }

  void _startAuto(_ProfileMonitoring state, int epoch) {
    final cancellation = WorkCancellation();
    _autoJobs[state] = cancellation;
    state.attempted = true;
    Future<void> run() async {
      var cancelledBeforeAdmission = false;
      try {
        final result = await connections.connectForMonitoring(
          actor,
          state.profile.profileId,
          expectedRevision: state.profile.revision,
          cancellation: cancellation,
        );
        cancelledBeforeAdmission = result.cancelledBeforeAdmission;
        if (result.operation.error != null && !cancelledBeforeAdmission)
          state.reason = MonitoringReason.sourceUnavailable;
      } catch (_) {
        state.reason = MonitoringReason.sourceUnavailable;
      } finally {
        _autoJobs.remove(state);
        if (cancelledBeforeAdmission &&
            connections.generation(state.profile.profileId) == 0)
          state.attempted = false;
        if (_current(epoch) || active) {
          _notify();
          unawaited(reconcile());
        }
      }
    }

    _track(run());
  }

  void _startCollection(
    _ProfileMonitoring state,
    ConnectionView view,
    int epoch,
  ) {
    final cancellation = WorkCancellation();
    final sessionId = view.sessionId!;
    final revision = state.profile.connectionRevision,
        generation = connections.generation(state.profile.profileId);
    state.dueAt = now + const Duration(seconds: 5);
    final MonitoringJob job;
    try {
      job = connections.beginMonitoring(
        actor,
        state.profile.profileId,
        sessionId,
        expectedConnectionRevision: revision,
        cancellation: cancellation,
      );
    } catch (_) {
      _invalidateReadings(state, MonitoringReason.sourceUnavailable);
      return;
    }
    state.job = job;
    _jobs[job] = cancellation;
    bool valid() =>
        _current(epoch) &&
        identical(_entries[state.profile.profileId], state) &&
        state.profile.connectionRevision == revision &&
        connections.generation(state.profile.profileId) == generation &&
        _connection(state.profile.profileId).state ==
            ConnectionState.connected &&
        _connection(state.profile.profileId).sessionId == sessionId;
    final work = job.result
        .then(
          (sample) {
            if (!valid()) return;
            _apply(state, sample);
            if (sample.failure == MonitoringReason.unsupportedOs)
              state.unsupportedSession = sessionId;
          },
          onError: (Object _, StackTrace __) {
            if (valid()) {
              _invalidateReadings(state, MonitoringReason.invalidResponse);
              _appendHistory(state);
            }
          },
        )
        .whenComplete(() {
          _jobs.remove(job);
          if (identical(state.job, job)) state.job = null;
          if (!_disposed) {
            _notify();
            if (active) unawaited(reconcile());
          }
        });
    _track(work);
  }

  void _apply(_ProfileMonitoring state, LinuxSample sample) {
    if (sample.failure != null) {
      _invalidateReadings(state, sample.failure!);
      _appendHistory(state);
      return;
    }
    state.reason = null;
    final received = now, display = _utc();
    void value(MetricKind kind, double? percent, MonitoringReason? reason) {
      if (percent == null) {
        state.readings[kind] = state.readings[kind]!.unavailable(
          reason ?? MonitoringReason.sourceUnavailable,
        );
      } else if (!percent.isFinite || percent < 0 || percent > 100) {
        state.readings[kind] = state.readings[kind]!.unavailable(
          MonitoringReason.invalidResponse,
        );
      } else
        state.readings[kind] = MetricReading.sample(percent, received, display);
    }

    final cpu = sample.cpu, previous = state.baseline;
    if (cpu == null) {
      state.baseline = null;
      value(MetricKind.cpu, null, sample.reasonFor(MetricKind.cpu));
    } else if (previous == null) {
      state.baseline = cpu;
      value(MetricKind.cpu, null, MonitoringReason.baseline);
    } else {
      final percent = cpu.busyPercentSince(previous);
      state.baseline = percent == null ? null : cpu;
      value(
        MetricKind.cpu,
        percent,
        percent == null ? MonitoringReason.invalidResponse : null,
      );
    }
    value(
      MetricKind.memory,
      sample.memoryPercent,
      sample.reasonFor(MetricKind.memory),
    );
    value(
      MetricKind.disk,
      sample.diskPercent,
      sample.reasonFor(MetricKind.disk),
    );
    _appendHistory(state);
  }

  void _pruneHistory(_ProfileHistory history) {
    final kept = HistoryCodec.prune(history.points, _utc(), now);
    if (kept.length != history.points.length) history.version++;
    history.points = kept;
  }

  void _loadHistory(_ProfileMonitoring state) {
    final history = state.history;
    if (history.loaded || history.readFailed) return;
    try {
      final payload = historyStore.loadHistory(
        state.profile.profileId,
        state.profile.connectionRevision,
      );
      final decoded = payload == null
          ? <HistoryPoint>[]
          : HistoryCodec.decode(payload);
      final utc = _utc(), monotonic = now;
      final stored = [
        for (final p in decoded)
          HistoryPoint(
            utcMs: p.utcMs,
            segment: p.segment,
            cpu: p.cpu,
            memory: p.memory,
            disk: p.disk,
            monotonicAt: monotonic - Duration(milliseconds: utc - p.utcMs),
          ),
      ];
      history.points = [...stored, ...history.points];
      history.loaded = true;
      history.error = false;
      _pruneHistory(history);
      // Persist any TTL pruning, and pending points accumulated during a read fault.
      if (history.version > 0) _persistHistory(state);
    } catch (_) {
      history.readFailed = history.error = true;
    }
  }

  void _appendHistory(_ProfileMonitoring state) {
    final history = state.history;
    final time = _utc();
    if (history.lastUtc != null && time < history.lastUtc!)
      history.clockSegment++;
    history.lastUtc = time;
    double? value(MetricKind kind) {
      final reading = state.readings[kind]!;
      return reading.reason == null ? reading.percent : null;
    }

    history.points.add(
      HistoryPoint(
        utcMs: time,
        segment:
            '${actor.ownerEpoch}:$_epoch:${state.sessionId}:${history.clockSegment}',
        monotonicAt: now,
        cpu: value(MetricKind.cpu),
        memory: value(MetricKind.memory),
        disk: value(MetricKind.disk),
      ),
    );
    history.version++;
    _pruneHistory(history);
    _persistHistory(state);
  }

  void _persistHistory(_ProfileMonitoring state) {
    final history = state.history;
    if (!history.loaded ||
        history.readFailed ||
        history.saving ||
        history.version == history.savedVersion)
      return;
    final revision = state.profile.connectionRevision;
    final id = state.profile.profileId;
    bool current() =>
        !_disposed &&
        identical(_entries[id], state) &&
        identical(state.history, history) &&
        state.profile.connectionRevision == revision;
    history.saving = true;
    final version = history.version;
    final work = Future<void>.sync(() async {
      var success = false;
      try {
        final payload = HistoryCodec.encode(history.points);
        await historyStore.saveHistory(id, revision, payload, current);
        if (!current()) return;
        history.savedVersion = version;
        history.error = false;
        success = true;
      } catch (_) {
        if (current()) history.error = true;
      } finally {
        history.saving = false;
        if (current()) {
          _notify();
          if (success && history.version != history.savedVersion)
            _persistHistory(state);
        }
      }
    });
    _track(work);
  }

  List<HistoryPoint> history(String id, int expectedConnectionRevision) {
    final state = _entries[id];
    if (state == null ||
        state.profile.connectionRevision != expectedConnectionRevision)
      return const [];
    return List.unmodifiable(
      HistoryCodec.prune(state.history.points, _utc(), now),
    );
  }

  bool historyError(String id, int expectedConnectionRevision) {
    final state = _entries[id];
    return state?.profile.connectionRevision == expectedConnectionRevision &&
        state!.history.error;
  }

  void retryHistory(String id, int expectedConnectionRevision) {
    if (_stopped) return;
    final state = _entries[id];
    if (state == null ||
        state.profile.connectionRevision != expectedConnectionRevision)
      return;
    state.history.readFailed = false;
    _loadHistory(state);
    _pruneHistory(state.history);
    _persistHistory(state);
    _notify();
  }

  void _invalidateReadings(
    _ProfileMonitoring state,
    MonitoringReason reason, {
    bool preserveServerReason = false,
  }) {
    if (!preserveServerReason) state.reason = reason;
    state.baseline = null;
    state.readings = state.readings.map(
      (kind, reading) => MapEntry(kind, reading.unavailable(reason)),
    );
  }

  MonitoringSnapshot snapshot(String id) {
    final state = _entries[id], view = _connection(id);
    final changedSession =
        view.state == ConnectionState.connected &&
        state?.sessionId != view.sessionId;
    final reason = _stopped
        ? MonitoringReason.stopped
        : !_active
        ? MonitoringReason.paused
        : _blocked
        ? MonitoringReason.stopped
        : _connecting(view.state) || changedSession
        ? MonitoringReason.waiting
        : view.state != ConnectionState.connected
        ? state?.reason ?? MonitoringReason.disconnected
        : state?.reason;
    final readings =
        (changedSession ? null : state?.readings) ??
        {for (final k in MetricKind.values) k: const MetricReading.missing()};
    return MonitoringSnapshot(
      profileId: id,
      connectionRevision: state?.profile.connectionRevision ?? 0,
      generation: connections.generation(id),
      sessionId: view.sessionId,
      connection: view,
      statusReason: reason,
      collecting: state?.job != null,
      readings: reason == null
          ? readings
          : readings.map((k, v) => MapEntry(k, v.unavailable(reason))),
    );
  }

  void _cancelWork(MonitoringReason reason) {
    for (final cancel in List.of(_autoJobs.values)) cancel.cancel();
    for (final entry in List.of(_jobs.entries)) {
      entry.value.cancel();
      entry.key.cancel();
    }
    for (final state in _entries.values) {
      _invalidateReadings(
        state,
        reason,
        preserveServerReason: reason == MonitoringReason.paused,
      );
    }
  }

  @override
  Future<void> stopAdmission() async {
    if (_stopped) return;
    _stopped = true;
    _active = false;
    _epoch++;
    _rerun = false;
    _cancelTick?.call();
    _cancelTick = null;
    _cancelWork(MonitoringReason.stopped);
    _notify();
  }

  @override
  Future<void> cancelPending() async => _cancelWork(MonitoringReason.stopped);
  @override
  Future<void> closeSessions() async => _cancelWork(MonitoringReason.stopped);
  @override
  Future<void> drain() async {
    while (_pending.isNotEmpty) {
      await Future.wait(List.of(_pending));
    }
  }

  @override
  Future<void> dispose() => _disposal ??= _dispose();
  Future<void> _dispose() async {
    await stopAdmission();
    await _subscription?.cancel();
    await drain();
    _disposed = true;
    _clock.stop();
    _notifier.dispose();
    _entries.clear();
    _profiles = const [];
    _order.clear();
  }
}

final class _ProfileMonitoring {
  _ProfileMonitoring(this.profile);
  ProfileView profile;
  _ProfileHistory history = _ProfileHistory();
  String? sessionId, unsupportedSession;
  bool attempted = false;
  Duration dueAt = Duration.zero;
  MonitoringJob? job;
  CpuCounters? baseline;
  MonitoringReason? reason;
  Map<MetricKind, MetricReading> readings = {
    for (final k in MetricKind.values) k: const MetricReading.missing(),
  };
}

final class _ProfileHistory {
  List<HistoryPoint> points = [];
  bool loaded = false, readFailed = false, saving = false, error = false;
  int version = 0, savedVersion = 0, clockSegment = 0;
  int? lastUtc;
}

final class _MonitoringNotifier extends ChangeNotifier {
  void changed() => notifyListeners();
}
