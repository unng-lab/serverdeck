import 'dart:async';

import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/protocol.dart';

import '../api/sessions.dart';

typedef DeadlineScheduler = void Function() Function(
  Duration delay,
  void Function() wake,
);

/// Callbacks are bound to resources owned by this service generation. A failed
/// step stops the chain: the mutex must never be released before storage closes.
class ShutdownResources {
  const ShutdownResources({
    required this.cancelStartup,
    required this.drainMutations,
    required this.closeStorage,
    required this.closePipes,
    required this.removeDiscovery,
    required this.clearKeys,
    required this.releaseMutex,
  });
  final Future<void> Function() cancelStartup,
      drainMutations,
      closeStorage,
      closePipes,
      removeDiscovery,
      clearKeys,
      releaseMutex;
}

class ServiceLifecycle {
  ServiceLifecycle({
    required String generation,
    required ShutdownResources resources,
    Duration Function()? elapsed,
    Duration? startupDeadlineAt,
    DeadlineScheduler? schedule,
    void Function(String)? onDetached,
    void Function(String)? onExpiredChannel,
  }) : _resources = resources {
    _clock = elapsed ?? () => _watch.elapsed;
    _schedule = schedule ?? _timer;
    // The owner passes the deadline measured from process entry, using the
    // same monotonic clock. Construction must not restart the startup budget.
    final latestStartupAt = _clock() + startupDeadline;
    if (startupDeadlineAt != null &&
        (startupDeadlineAt.isNegative || startupDeadlineAt > latestStartupAt)) {
      _watch.stop();
      throw ArgumentError('Invalid startup deadline');
    }
    _startupAt = startupDeadlineAt ?? latestStartupAt;
    _sessions = SessionRegistry(
      generation: generation,
      elapsed: _clock,
      onDetached: onDetached,
      onExpiredChannel: onExpiredChannel,
      onChanged: _changed,
    );
    _finished.future.ignore(); // Owner can still await the original completion.
    _changed();
  }
  final ShutdownResources _resources;
  final _watch = Stopwatch()..start();
  late final Duration Function() _clock;
  late final DeadlineScheduler _schedule;
  late final Duration _startupAt;
  late final SessionRegistry _sessions;
  final _finished = Completer<void>();
  void Function()? _cancel;
  Duration? _graceAt;
  bool _bootstrapComplete = false,
      _everAuthenticated = false,
      _stopping = false,
      _advancing = false;
  ErrorCode? _reason;
  SessionRegistry get sessions => _sessions;
  bool get stopping => _stopping;
  ErrorCode? get reason => _reason;
  Future<void> get finished => _finished.future;

  /// Process owner distinguishes clean teardown from an operational failure
  /// that was recorded before successfully releasing all resources.
  Future<void> waitForExit() async {
    await finished;
    if (_reason != null) throw StateError(_reason!.wireName);
  }

  static void Function() _timer(Duration delay, void Function() wake) {
    final timer = Timer(delay, wake);
    return timer.cancel;
  }

  void bootstrapComplete() {
    if (_stopping) throw StateError('NOT_READY');
    if (!_bootstrapComplete && _clock() >= _startupAt) {
      _reason = ErrorCode.timeout;
      unawaited(close());
      throw StateError('NOT_READY');
    }
    _bootstrapComplete = true;
    _changed();
    if (_stopping) throw StateError('NOT_READY');
  }

  /// Cooperative native completion may beat a delayed watchdog Timer callback.
  /// Record the same terminal reason before cancelling that timer in close().
  void checkStartupDeadline() {
    if (_clock() >= _startupAt) {
      _reason = ErrorCode.timeout;
      unawaited(close());
      throw StateError('TIMEOUT');
    }
    if (_stopping) throw StateError('NOT_READY');
  }

  void _changed() {
    if (_stopping || _advancing) return;
    final now = _clock();
    // A delayed timer must not let a late first grant erase the watchdog.
    if ((!_bootstrapComplete || !_everAuthenticated) && now >= _startupAt) {
      _reason = ErrorCode.timeout;
      unawaited(close());
      return;
    }
    // Registration can arrive before a delayed timer. Check the existing grace
    // before a newly inserted session is allowed to cancel it.
    if (_graceAt != null && now >= _graceAt!) {
      unawaited(close());
      return;
    }
    if (_sessions.count > 0) {
      _everAuthenticated = true;
      _graceAt = null;
    } else if (_everAuthenticated) {
      _graceAt ??= (_sessions.emptyAt ?? now) + shutdownGrace;
    }
    final startupPending = !_bootstrapComplete || !_everAuthenticated;
    if (startupPending && now >= _startupAt) {
      _reason = ErrorCode.timeout;
      unawaited(close());
      return;
    }
    if (_graceAt != null && now >= _graceAt!) {
      unawaited(close());
      return;
    }
    var next = _sessions.nextExpiry;
    for (final deadline in [
      if (startupPending) _startupAt,
      if (_graceAt != null) _graceAt!,
    ]) {
      if (next == null || deadline < next) next = deadline;
    }
    _cancel?.call();
    _cancel = null;
    if (next != null) {
      final delay = next - now;
      _cancel = _schedule(delay.isNegative ? Duration.zero : delay, _advance);
    }
  }

  void _advance() {
    if (_stopping) return;
    _advancing = true;
    try {
      _sessions.expire();
    } finally {
      _advancing = false;
    }
    _changed();
  }

  Future<void> close({ErrorCode? reason}) {
    if (_stopping) return _finished.future;
    _reason ??= reason;
    _stopping = true;
    _cancel?.call();
    _cancel = null;
    unawaited(_finish());
    return _finished.future;
  }

  Future<void> _finish() async {
    try {
      _sessions.stop();
      await _resources.cancelStartup();
      await _resources.drainMutations();
      await _resources.closeStorage();
      await _resources.closePipes();
      await _resources.removeDiscovery();
      await _resources.clearKeys();
      await _resources.releaseMutex();
      _finished.complete();
    } catch (_) {
      _reason = ErrorCode.storageBlocked;
      _finished.completeError(StateError('STORAGE_BLOCKED'));
    } finally {
      _watch.stop();
    }
  }
}
