import 'dart:async';

import '../runtime/owned_work.dart';

final _monotonicClock = Stopwatch()..start();
Duration _monotonicNow() => _monotonicClock.elapsed;
void Function() _scheduleTimer(Duration duration, void Function() callback) {
  final timer = Timer(duration, callback);
  return timer.cancel;
}

enum BudgetExpiry { network, prompt }

enum PromptKind { trust, passphrase }

/// Opaque lease: an old prompt cannot resume a newer prompt or another attempt.
final class BudgetPrompt {
  BudgetPrompt._(this.kind);
  final PromptKind kind;
}

/// One monotonic clock owner per attempt, separate from any vendor timers.
/// onExpired must invalidate the owning generation and close its exact resources.
final class NetworkBudget {
  NetworkBudget({
    required void Function(BudgetExpiry reason) onExpired,
    Duration Function()? now,
    ScheduleOwnedDeadline? schedule,
  }) : _expired = onExpired,
       _now = now ?? _monotonicNow,
       _schedule = schedule ?? _scheduleTimer {
    _since = _now();
    _arm(networkDuration);
  }
  static const networkDuration = Duration(seconds: 30);
  static const promptDuration = Duration(minutes: 5);
  final Duration Function() _now;
  final ScheduleOwnedDeadline _schedule;
  final void Function(BudgetExpiry) _expired;
  Duration _left = networkDuration;
  late Duration _since;
  BudgetPrompt? _prompt;
  void Function()? _cancel;
  int _ticket = 0;
  bool _ended = false;
  bool get isEnded {
    _refresh();
    return _ended;
  }

  Duration get remaining {
    final now = _now();
    _refresh(now);
    if (_ended) return Duration.zero;
    return _prompt != null ? _left : _left - (now - _since);
  }

  BudgetPrompt? pauseForPrompt(PromptKind kind) {
    final now = _now();
    _refresh(now);
    if (_ended) return null;
    if (_prompt != null) {
      if (_prompt!.kind != kind) throw StateError('Another prompt is active');
      return _prompt; // A repeated observation does not extend five minutes.
    }
    _left -= now - _since;
    _since = now;
    _prompt = BudgetPrompt._(kind);
    _arm(promptDuration);
    return _prompt;
  }

  bool resume(BudgetPrompt prompt) {
    final now = _now();
    _refresh(now);
    if (_ended || !identical(_prompt, prompt)) return false;
    _prompt = null;
    _since = now;
    _arm(_left);
    return true;
  }

  void _refresh([Duration? current]) {
    if (_ended) return;
    final duration = _prompt == null ? _left : promptDuration;
    if ((current ?? _now()) - _since >= duration) {
      final reason = _prompt == null
          ? BudgetExpiry.network
          : BudgetExpiry.prompt;
      finish();
      _expired(reason);
    }
  }

  void _arm(Duration duration) {
    _cancel?.call();
    _cancel = null;
    final ticket = ++_ticket;
    final cancel = _schedule(duration, () {
      if (_ended || ticket != _ticket) return;
      _refresh();
      if (!_ended) {
        // Early timer delivery must never consume time the clock did not pass.
        final left =
            (_prompt == null ? _left : promptDuration) - (_now() - _since);
        _arm(left);
      }
    });
    if (!_ended && ticket == _ticket) {
      _cancel = cancel;
    } else {
      cancel();
    }
  }

  /// Must succeed inside the owner's final guarded connected transition.
  /// A queued late success cannot cancel an already expired deadline, and a
  /// pending user prompt is never an authenticated completion.
  bool tryComplete() {
    _refresh();
    if (_ended || _prompt != null) return false;
    finish();
    return true;
  }

  /// Cancel/error cleanup only. Success must use tryComplete before publication.
  void finish() {
    if (_ended) return;
    _ended = true;
    _prompt = null;
    ++_ticket;
    _cancel?.call();
    _cancel = null;
  }
}

/// One in-flight ping; all completions/timers are fenced after stop or failure.
/// The owner maps onFailure to NETWORK_ERROR and closes the exact live session.
final class ConnectionWatchdog {
  ConnectionWatchdog({
    required Future<void> Function() ping,
    required void Function() onFailure,
    Duration Function()? now,
    ScheduleOwnedDeadline? schedule,
  }) : _ping = ping,
       _failure = onFailure,
       _now = now ?? _monotonicNow,
       _schedule = schedule ?? _scheduleTimer {
    _since = _now();
    _arm(interval);
  }
  static const interval = Duration(seconds: 15),
      replyTimeout = Duration(seconds: 10);
  final Future<void> Function() _ping;
  final void Function() _failure;
  final Duration Function() _now;
  final ScheduleOwnedDeadline _schedule;
  late Duration _since;
  void Function()? _cancel;
  bool _stopped = false, _pending = false;
  int _ticket = 0, _pingGeneration = 0;
  bool get isStopped => _stopped;
  bool get pingPending => _pending;
  void _arm(Duration duration) {
    _cancel?.call();
    _cancel = null;
    final ticket = ++_ticket;
    final cancel = _schedule(duration, () {
      if (_stopped || ticket != _ticket) return;
      final left = (_pending ? replyTimeout : interval) - (_now() - _since);
      if (left > Duration.zero) {
        _arm(left);
        return;
      }
      if (_pending) {
        _fail();
        return;
      }
      _pending = true;
      _since = _now();
      _arm(replyTimeout);
      if (_stopped) return;
      final pingTicket = ++_pingGeneration;
      unawaited(
        Future.sync(_ping).then(
          (_) {
            if (_stopped || pingTicket != _pingGeneration) return;
            if (_now() - _since >= replyTimeout) {
              _fail();
              return;
            }
            _pending = false;
            _since = _now();
            _arm(interval);
          },
          onError: (Object _, StackTrace __) {
            if (!_stopped && pingTicket == _pingGeneration) _fail();
          },
        ),
      );
    });
    if (!_stopped && ticket == _ticket) {
      _cancel = cancel;
    } else {
      cancel();
    }
  }

  void _fail() {
    stop();
    _failure();
  }

  void stop() {
    if (_stopped) return;
    _stopped = true;
    _pending = false;
    ++_ticket;
    ++_pingGeneration;
    _cancel?.call();
    _cancel = null;
  }
}
