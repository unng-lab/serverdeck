import 'dart:async';

import 'capability.dart';

final class WorkCancelled implements Exception {
  const WorkCancelled();
  @override
  String toString() => 'Operation cancelled';
}

final class WorkCancellation {
  bool _cancelled = false;
  final Set<void Function()> _listeners = {};
  bool get isCancelled => _cancelled;
  void check() {
    if (_cancelled) throw const WorkCancelled();
  }

  void Function() listen(void Function() callback) {
    if (_cancelled) {
      callback();
      return () {};
    }
    _listeners.add(callback);
    return () => _listeners.remove(callback);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final callback in List.of(_listeners)) {
      callback();
    }
    _listeners.clear();
  }
}

enum WorkFailureKind { stopped, capacity, timeout }

final class WorkFailure implements Exception {
  const WorkFailure(this.kind);
  final WorkFailureKind kind;
  @override
  String toString() => 'OwnedWorkFailure(${kind.name})';
}

abstract interface class OwnedWorker<T> {
  Future<T> get result;

  /// Completes only after this worker has exited, not merely requested stop.
  Future<void> stop();
}

typedef SpawnOwnedWorker<Q, T> = Future<OwnedWorker<T>> Function(Q request);
typedef ScheduleOwnedDeadline = void Function() Function(
  Duration duration,
  void Function() callback,
);
void Function() _scheduleWorkTimer(
  Duration duration,
  void Function() callback,
) {
  final timer = Timer(duration, callback);
  return timer.cancel;
}

/// One independent resource owner per pool instance. Takes ownership of request
/// on every path, including rejected admission; adapters supply idempotent cleanup.
final class OwnedWorkerPool<Q, T> implements RuntimeCapability {
  OwnedWorkerPool({
    required this.id,
    required SpawnOwnedWorker<Q, T> spawn,
    required void Function(Q) disposeRequest,
    required void Function(T) disposeLateResult,
    ScheduleOwnedDeadline? schedule,
  }) : _spawn = spawn,
       _disposeRequest = disposeRequest,
       _disposeLateResult = disposeLateResult,
       _schedule = schedule ?? _scheduleWorkTimer;
  @override
  final String id;
  final SpawnOwnedWorker<Q, T> _spawn;
  final void Function(Q) _disposeRequest;
  final void Function(T) _disposeLateResult;
  final ScheduleOwnedDeadline _schedule;
  final Set<_OwnedJob<Q, T>> _jobs = {};
  bool _stopped = false;
  static const maxWorkers = 4;
  static const maxDuration = Duration(seconds: 30);
  int get activeWorkers => _jobs.length;
  bool get isStopped => _stopped;

  Future<T> run(
    Q request, {
    WorkCancellation? cancellation,
    Duration timeout = maxDuration,
  }) {
    Object? failure;
    if (_stopped) {
      failure = const WorkFailure(WorkFailureKind.stopped);
    } else if (cancellation?.isCancelled ?? false) {
      failure = const WorkCancelled();
    } else if (timeout <= Duration.zero) {
      failure = const WorkFailure(WorkFailureKind.timeout);
    } else if (_jobs.length >= maxWorkers) {
      failure = const WorkFailure(WorkFailureKind.capacity);
    }
    if (failure != null) {
      _disposeRequest(request);
      return Future.error(failure);
    }
    late final _OwnedJob<Q, T> job;
    job = _OwnedJob(
      request,
      () => _jobs.remove(job),
      _disposeRequest,
      _disposeLateResult,
    );
    _jobs.add(job);
    try {
      job.start(
        _spawn,
        _schedule,
        timeout > maxDuration ? maxDuration : timeout,
        cancellation,
      );
    } catch (_) {
      job.rejectStart();
    }
    return job.result;
  }

  @override
  Future<void> stopAdmission() async {
    _stopped = true;
  }

  @override
  Future<void> cancelPending() async {
    for (final job in List.of(_jobs)) {
      job.cancel();
    }
  }

  @override
  Future<void> closeSessions() => drain();
  @override
  Future<void> drain() {
    final current = List.of(_jobs);
    for (final job in current) {
      job.retryStop();
    }
    return Future.wait(current.map((j) => j.closed));
  }

  @override
  Future<void> dispose() async {
    await stopAdmission();
    await cancelPending();
    await drain();
  }
}

final class _OwnedJob<Q, T> {
  _OwnedJob(
    this.request,
    this.release,
    this.disposeRequest,
    this.disposeLateResult,
  );
  final Q request;
  final void Function() release;
  final void Function(Q) disposeRequest;
  final void Function(T) disposeLateResult;
  final _closed = Completer<void>();
  final _result = Completer<T>();
  Future<T> get result => _result.future;
  Future<void> get closed => _closed.future;
  OwnedWorker<T>? _worker;
  Future<void>? _stopping;
  void Function()? _cancelDeadline, _removeListener;
  bool _ending = false, _released = false, _spawnStarted = false;
  void start(
    SpawnOwnedWorker<Q, T> spawn,
    ScheduleOwnedDeadline schedule,
    Duration timeout,
    WorkCancellation? cancellation,
  ) {
    _cancelDeadline = schedule(
      timeout,
      () => _fail(const WorkFailure(WorkFailureKind.timeout)),
    );
    _removeListener = cancellation?.listen(cancel);
    if (_ending) {
      _detach();
      _finish();
      return;
    }
    _spawnStarted = true;
    Future.sync(() => spawn(request)).then(
      (worker) {
        _worker = worker;
        // Spawn factories copy the request before completing, as Isolate.spawn does.
        disposeRequest(request);
        try {
          worker.result.then(
            (value) {
              if (_ending) {
                disposeLateResult(value);
              } else {
                _ending = true;
                _detach();
                _result.complete(value);
              }
              retryStop();
            },
            onError: (Object error, StackTrace _) {
              _fail(error);
            },
          );
        } catch (error) {
          _fail(error);
        }
        if (_ending) retryStop();
      },
      onError: (Object _, StackTrace __) {
        if (!_ending) {
          _ending = true;
          _detach();
          _result.completeError(const WorkFailure(WorkFailureKind.capacity));
        }
        _finish();
      },
    );
  }

  void _detach() {
    _cancelDeadline?.call();
    _removeListener?.call();
  }

  void _fail(Object error) {
    if (!_ending) {
      _ending = true;
      _detach();
      _result.completeError(error);
    }
    retryStop();
  }

  void cancel() => _fail(const WorkCancelled());
  void rejectStart() {
    _fail(const WorkFailure(WorkFailureKind.capacity));
    if (!_spawnStarted) _finish();
  }

  void retryStop() {
    if (!_ending || _worker == null || _released || _stopping != null) return;
    try {
      _stopping = _worker!.stop().then(
        (_) => _finish(),
        onError: (Object _, StackTrace __) {
          _stopping = null;
        },
      );
    } catch (_) {
      _stopping = null;
    }
  }

  void _finish() {
    if (_released) return;
    _released = true;
    disposeRequest(request);
    _detach();
    release();
    _closed.complete();
  }
}
