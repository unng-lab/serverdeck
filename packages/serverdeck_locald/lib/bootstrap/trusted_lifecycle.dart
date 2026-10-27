import 'dart:async';

import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/protocol.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../api/operational_auth.dart';
import 'lifecycle.dart' show ShutdownResources;

/// Same process-entry deadline/session lease/grace, owned by the real format3
/// registry once its native publication gate has been obtained.
final class TrustedServiceLifecycle {
  TrustedServiceLifecycle({
    required this.generation,
    required this.elapsed,
    required this.resources,
  }) {
    requireUuid(generation);
    _done.future.ignore();
    changed();
  }
  final String generation;
  final Duration Function() elapsed;
  final ShutdownResources resources;
  final _done = Completer<void>();
  TrustedSessions? _sessions;
  Timer? _timer;
  Duration? _graceAt;
  bool stopping = false,
      _complete = false,
      _authenticated = false,
      _advancing = false;
  ErrorCode? reason;
  Future<void> get finished => _done.future;

  void attach(TrustedSessions sessions) {
    if (stopping ||
        _sessions != null ||
        sessions.generation != generation ||
        !sessions.hasNativePublicationGate)
      throw StateError('NOT_READY');
    _sessions = sessions;
    changed();
  }

  void checkStartupDeadline() {
    if (elapsed() >= startupDeadline) {
      close(reason: ErrorCode.timeout).ignore();
      throw StateError('TIMEOUT');
    }
    if (stopping) throw StateError('NOT_READY');
  }

  void bootstrapComplete() {
    checkStartupDeadline();
    _complete = true;
    changed();
  }

  void changed() {
    if (stopping || _advancing) return;
    final now = elapsed(), sessions = _sessions;
    if ((!_complete || !_authenticated) && now >= startupDeadline) {
      close(reason: ErrorCode.timeout).ignore();
      return;
    }
    if (_graceAt != null && now >= _graceAt!) {
      close().ignore();
      return;
    }
    if ((sessions?.count ?? 0) > 0) {
      _authenticated = true;
      _graceAt = null;
    } else if (_authenticated) {
      _graceAt ??= (sessions?.emptyAt ?? now) + shutdownGrace;
    }
    Duration? next = sessions?.nextExpiry;
    for (final value in [
      if (!_complete || !_authenticated) startupDeadline,
      if (_graceAt != null) _graceAt!,
    ]) {
      if (next == null || value < next) next = value;
    }
    _timer?.cancel();
    _timer = null;
    if (next != null) {
      final left = next - now;
      _timer = Timer(left.isNegative ? Duration.zero : left, () {
        if (stopping) return;
        _advancing = true;
        try {
          _sessions?.expire();
        } catch (_) {
          close(reason: ErrorCode.serviceUnavailable).ignore();
        } finally {
          _advancing = false;
        }
        changed();
      });
    }
  }

  Future<void> close({ErrorCode? reason}) {
    if (stopping) return finished;
    this.reason ??= reason;
    stopping = true;
    _timer?.cancel();
    _timer = null;
    var stopFailed = false;
    try {
      _sessions?.stop();
    } catch (_) {
      stopFailed = true;
    }
    () async {
      try {
        await resources.cancelStartup();
        await resources.drainMutations();
        if (stopFailed) throw StateError('SERVICE_UNAVAILABLE');
        await resources.closeStorage();
        await resources.closePipes();
        await resources.removeDiscovery();
        await resources.clearKeys();
        await resources.releaseMutex();
        _done.complete();
      } catch (_) {
        this.reason = ErrorCode.storageBlocked;
        _done.completeError(StateError('STORAGE_BLOCKED'));
      }
    }();
    return finished;
  }

  Future<void> waitForExit() async {
    await finished;
    if (reason != null) throw StateError(reason!.wireName);
  }
}
