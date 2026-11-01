import 'dart:async';
import 'dart:collection';

import '../platform/ports.dart' show EngineClock;

enum JobControlKind { cancel, reconcile }

/// Scheduling and retained intent only. Nothing here proves actor authority.
final class JobControlTicket<T> {
  JobControlTicket._(
    this.jobId,
    this.attemptId,
    this.kind,
    this.value,
    this.deadline,
    this.epoch,
  );
  final String jobId, attemptId;
  final JobControlKind kind;
  final T value;
  final Duration deadline;
  final int epoch;
}

final class _Entry<T> {
  _Entry(this.attemptId, this.serverId);
  final String attemptId, serverId;
  Object stopBinding = Object();
  JobControlTicket<T>? cancel, reconcile;
  bool stopAcknowledged = false, reconcileTurn = false;
}

/// One physically owned metadata interest, including after reply cancellation.
final class JobControlAdmission {
  JobControlAdmission._(this.owner, this.deadline, this.valid, this.pump)
    : epoch = owner.epoch {
    _entered.future.ignore();
  }
  final JobControlContinuations<dynamic> owner;
  final Duration? deadline;
  final bool Function() valid;
  final bool pump;
  final int epoch;
  final _entered = Completer<void>();
  bool _active = false, _released = false;
  Future<void> get entered => _entered.future;
  void cancel() {
    if (!_active) owner._remove(this, 'CANCELLED');
  }

  void release() => owner._release(this);
}

/// Bounded FIFO metadata serialization, coalesced tickets and one expiry timer.
/// The service owns the pump, proofs, storage and every actual remote driver.
final class JobControlContinuations<T> {
  JobControlContinuations({
    required this.clock,
    required this.wake,
    Timer Function(Duration, void Function())? schedule,
  }) : _schedule = schedule ?? Timer.new;
  final EngineClock clock;
  final void Function() wake;
  final Timer Function(Duration, void Function()) _schedule;
  final _entries = LinkedHashMap<String, _Entry<T>>();
  final _queue = Queue<JobControlAdmission>();
  JobControlAdmission? _active;
  Timer? _timer;
  Object? _timerToken;
  int epoch = 0;
  bool sealed = false;
  int get entryCount => _entries.length;
  int get interestCount => _queue.length + (_active == null ? 0 : 1);
  int get pendingCount => _entries.values.fold(
    0,
    (n, e) => n + (e.cancel == null ? 0 : 1) + (e.reconcile == null ? 0 : 1),
  );
  Iterable<JobControlTicket<T>> get pending => [
    for (final e in _entries.values) ...[
      if (e.cancel != null) e.cancel!,
      if (e.reconcile != null) e.reconcile!,
    ],
  ];
  Iterable<String> get jobs => _entries.keys.toList();
  bool get idle => interestCount == 0;

  JobControlAdmission reserve({
    Duration? deadline,
    required bool Function() valid,
    bool pump = false,
  }) {
    if (sealed) throw StateError('NOT_READY');
    if (interestCount >= 33 ||
        !pump &&
            [_active, ..._queue]
                    .whereType<JobControlAdmission>()
                    .where((a) => !a.pump)
                    .length >=
                32 ||
        pump &&
            [
              _active,
              ..._queue,
            ].whereType<JobControlAdmission>().any((a) => a.pump)) {
      throw StateError('RESOURCE_LIMIT');
    }
    final a = JobControlAdmission._(this, deadline, valid, pump);
    _queue.add(a);
    _advance();
    _arm();
    return a;
  }

  bool _eligible(JobControlAdmission a) =>
      !sealed &&
      a.epoch == epoch &&
      (a.deadline == null || clock.elapsed < a.deadline!) &&
      a.valid();
  void _advance() {
    if (_active != null) return;
    while (_queue.isNotEmpty) {
      final a = _queue.removeFirst();
      if (!_eligible(a)) {
        a._released = true;
        a._entered.completeError(
          StateError(sealed ? 'NOT_READY' : 'CANCELLED'),
        );
        continue;
      }
      _active = a;
      a._active = true;
      a._entered.complete();
      return;
    }
  }

  void _remove(JobControlAdmission a, String code) {
    if (a._active || a._released) return;
    _queue.remove(a);
    a._released = true;
    if (!a._entered.isCompleted) a._entered.completeError(StateError(code));
    _arm();
  }

  void _release(JobControlAdmission a) {
    if (a._released) return;
    if (!identical(_active, a)) {
      _remove(a, 'CANCELLED');
      return;
    }
    a._released = true;
    _active = null;
    _advance();
    _arm();
  }

  void _owned(JobControlAdmission a) {
    if (!identical(_active, a) || a._released) throw StateError('NOT_READY');
  }

  /// Call before a new metadata mutation, while holding its admission.
  void reserveJob(
    JobControlAdmission a,
    String id,
    String attempt, {
    required String serverId,
  }) {
    _owned(a);
    final old = _entries[id];
    if (old != null) {
      if (old.attemptId != attempt || old.serverId != serverId)
        throw StateError('REVISION_CONFLICT');
      return;
    }
    if (_entries.length >= 250) throw StateError('RESOURCE_LIMIT');
    _entries[id] = _Entry<T>(attempt, serverId);
  }

  bool register(
    JobControlAdmission a, {
    required String jobId,
    required String attemptId,
    required JobControlKind kind,
    required T value,
    required Duration deadline,
  }) {
    _owned(a);
    if (sealed || a.epoch != epoch || clock.elapsed >= deadline) return false;
    final e = _entries[jobId];
    if (e == null || e.attemptId != attemptId) throw StateError('NOT_READY');
    final ticket = JobControlTicket._(
      jobId,
      attemptId,
      kind,
      value,
      deadline,
      epoch,
    );
    if (kind == JobControlKind.cancel) {
      if (!e.stopAcknowledged) e.cancel = ticket;
    } else {
      e.reconcile = ticket;
    }
    _arm();
    wake();
    return true;
  }

  void prune(Set<String> nonterminal) {
    _entries.removeWhere((id, _) => !nonterminal.contains(id));
    _arm();
  }

  Object? stopBinding(String id, String attempt) {
    final e = _entries[id];
    return e != null && e.attemptId == attempt && !sealed
        ? e.stopBinding
        : null;
  }

  /// Retirement invalidates both cached ACKs and acknowledgements still in flight.
  /// Data-only invalidation does not release any actual driver/native ownership.
  void retireServer(String server) {
    for (final e in _entries.values) {
      if (e.serverId != server) continue;
      e.stopAcknowledged = false;
      e.stopBinding = Object();
    }
  }

  void acknowledgeStop(String id, String attempt, {required Object? binding}) {
    final e = _entries[id];
    if (e == null ||
        e.attemptId != attempt ||
        sealed ||
        binding == null ||
        !identical(binding, e.stopBinding))
      return;
    e.stopAcknowledged = true;
    e.cancel = null;
    _arm();
    wake();
  }

  bool hasReconcile(String id) => _entries[id]?.reconcile != null;
  bool current(JobControlTicket<T> ticket) =>
      !sealed &&
      ticket.epoch == epoch &&
      clock.elapsed < ticket.deadline &&
      _entries[ticket.jobId]?.attemptId == ticket.attemptId;
  void expire(JobControlAdmission a) {
    _owned(a);
    for (final e in _entries.values) {
      if (e.cancel != null && !current(e.cancel!)) e.cancel = null;
      if (e.reconcile != null && !current(e.reconcile!)) {
        e.reconcile = null;
        e.reconcileTurn = false;
      }
    }
    _arm();
  }

  JobControlTicket<T>? take(JobControlAdmission a, String id) {
    _owned(a);
    final e = _entries[id];
    if (sealed || e == null) return null;
    JobControlTicket<T>? chosen;
    if (e.reconcile != null && (e.cancel == null || e.reconcileTurn)) {
      chosen = e.reconcile;
      e.reconcile = null;
      e.reconcileTurn = false;
    } else if (e.cancel != null) {
      chosen = e.cancel;
      e.cancel = null;
      e.reconcileTurn = e.reconcile != null;
    }
    // Move a serviced job behind other ready entries.
    if (chosen != null) {
      _entries.remove(id);
      _entries[id] = e;
    }
    _arm();
    return chosen;
  }

  void seal() {
    if (sealed) return;
    sealed = true;
    epoch++;
    _timer?.cancel();
    _timer = null;
    for (final a in _queue.toList()) _remove(a, 'NOT_READY');
    for (final e in _entries.values) {
      e.cancel = e.reconcile = null;
      e.stopAcknowledged = e.reconcileTurn = false;
    }
  }

  void resume() {
    if (!sealed || !idle) throw StateError('NOT_READY');
    _entries.clear();
    sealed = false;
  }

  void _arm() {
    _timer?.cancel();
    _timer = null;
    _timerToken = null;
    if (sealed) return;
    Duration? next;
    void consider(Duration? t) {
      if (t != null && (next == null || t < next!)) next = t;
    }

    for (final a in _queue) consider(a.deadline);
    for (final e in _entries.values) {
      consider(e.cancel?.deadline);
      consider(e.reconcile?.deadline);
    }
    if (next == null) return;
    final captured = epoch;
    final token = _timerToken = Object();
    _timer = _schedule(
      next! > clock.elapsed ? next! - clock.elapsed : Duration.zero,
      () {
        if (sealed || captured != epoch || !identical(token, _timerToken))
          return;
        _timer = null;
        _timerToken = null;
        for (final a in _queue.toList()) {
          if (!_eligible(a)) _remove(a, 'TIMEOUT');
        }
        wake();
      },
    );
  }
}
