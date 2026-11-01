import 'dart:async';
import 'dart:developer' show Timeline;

import 'package:flutter/foundation.dart';
import 'package:serverdeck_engine/hosting/worker_controller.dart';
import 'package:serverdeck_protocol/models.dart';

import 'engine_client.dart';

/// Presents the one worker's startup/readiness. Retry never replaces the worker
/// or replays a mutation; only a new bound window attachment may be requested.
class BootstrapController extends ChangeNotifier {
  BootstrapController({
    required this.client,
    required Future<WorkerStatus> Function() start,
    int Function()? nowMicros,
    ScheduleDeadline? schedule,
  }) : _start = start,
       _now = nowMicros ?? (() => Timeline.now),
       _schedule = schedule ?? _timer {
    _connectionStates = client.states.listen((state) {
      if (!_disposed &&
          !_workspaceBusy &&
          state == ClientConnectionState.disconnected) {
        client.stopPolling();
        _show(ReadinessState.unavailable, ErrorCode.serviceUnavailable);
      }
    });
    _snapshotErrors = client.snapshotErrors.listen((code) {
      if (_disposed || _state != ReadinessState.ready) return;
      final state = switch (code) {
        ErrorCode.storageBlocked => ReadinessState.storageBlocked,
        ErrorCode.incompatible => ReadinessState.incompatible,
        ErrorCode.notReady ||
        ErrorCode.serviceUnavailable ||
        ErrorCode.unauthorized => ReadinessState.unavailable,
        _ => null,
      };
      if (state != null) {
        client.stopPolling();
        _show(state, code);
      }
    });
  }
  final EngineApiClient client;
  final Future<WorkerStatus> Function() _start;
  final int Function() _now;
  final ScheduleDeadline _schedule;
  late final StreamSubscription<ClientConnectionState> _connectionStates;
  late final StreamSubscription<ErrorCode> _snapshotErrors;
  Future<void>? _attempt;
  bool _disposed = false, _notifierDisposed = false;
  int _notifications = 0, _readinessEpoch = 0;
  ReadinessState _state = ReadinessState.unavailable;
  ErrorCode? _reason;
  String? _workspaceId;
  bool _workspaceBusy = false;
  bool get workspaceBusy => _workspaceBusy;
  ReadinessState get state => _state;
  int get readinessEpoch => _readinessEpoch;
  ErrorCode? get reason => _reason;
  String? get workspaceId => _workspaceId;
  bool get retryInProgress => _attempt != null;
  static CancelDeadline _timer(Duration d, void Function() action) {
    final timer = Timer(d, action);
    return timer.cancel;
  }

  void _show(ReadinessState state, ErrorCode? reason, [String? workspace]) {
    if (_disposed) return;
    if (_state != state) _readinessEpoch++;
    _state = state;
    _reason = reason;
    _workspaceId = state == ReadinessState.ready ? workspace : null;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    _notifications++;
    try {
      notifyListeners();
    } finally {
      _notifications--;
      if (_disposed && _notifications == 0 && !_notifierDisposed) {
        _notifierDisposed = true;
        super.dispose();
      }
    }
  }

  Future<void> retry() {
    if (_disposed || _workspaceBusy) return Future.value();
    if (_attempt != null) return _attempt!;
    final done = Completer<void>();
    _attempt = done.future;
    _run().then<void>(
      (_) {
        _attempt = null;
        done.complete();
        _notify();
      },
      onError: (Object error, StackTrace _) {
        _attempt = null;
        done.completeError(error);
        _notify();
      },
    );
    return done.future;
  }

  Future<void> _run() async {
    final end = _now() + 30000000;
    var expired = false;
    final cancel = _schedule(const Duration(seconds: 30), () {
      expired = true;
      if (!_disposed) {
        client.stopPolling();
        _show(ReadinessState.unavailable, ErrorCode.timeout);
      }
    });
    bool live() {
      if (_disposed) return false;
      if (expired || _now() >= end) {
        client.stopPolling();
        _show(ReadinessState.unavailable, ErrorCode.timeout);
        return false;
      }
      return true;
    }

    Duration remaining() {
      final micros = end - _now();
      if (micros <= 0) throw const EngineApiException(ErrorCode.timeout);
      return Duration(microseconds: micros);
    }

    client.stopPolling();
    _show(ReadinessState.starting, null);
    try {
      final status = await _start().timeout(remaining());
      if (!live()) return;
      if (status.phase == 'busy') {
        _workspaceBusy = true;
        _show(ReadinessState.storageBlocked, ErrorCode.storageBlocked);
        return;
      }
      if (status.phase != 'ready') {
        final reason =
            ErrorCode.values
                .where((c) => c.wireName == status.reason)
                .firstOrNull ??
            ErrorCode.serviceUnavailable;
        _show(
          reason == ErrorCode.storageBlocked
              ? ReadinessState.storageBlocked
              : reason == ErrorCode.incompatible
              ? ReadinessState.incompatible
              : ReadinessState.unavailable,
          reason,
        );
        return;
      }
      await client.connect().timeout(remaining());
      if (!live()) return;
      final response = await client
          .read(ApiMethod.readinessGet)
          .timeout(remaining());
      if (!live()) return;
      final value = response.result;
      final state = value['state'] == 'storage-blocked'
          ? ReadinessState.storageBlocked
          : ReadinessState.values.byName(value['state'] as String);
      final reason = ErrorCode.values
          .where((c) => c.wireName == value['reason'])
          .firstOrNull;
      _show(state, reason, value['workspaceId'] as String?);
      if (live() && state == ReadinessState.ready) client.startPolling();
    } catch (error) {
      if (_disposed) return;
      final code = expired || _now() >= end || error is TimeoutException
          ? ErrorCode.timeout
          : error is EngineApiException
          ? error.code
          : ErrorCode.serviceUnavailable;
      _show(
        code == ErrorCode.storageBlocked
            ? ReadinessState.storageBlocked
            : code == ErrorCode.incompatible
            ? ReadinessState.incompatible
            : ReadinessState.unavailable,
        code,
      );
    } finally {
      cancel();
    }
  }

  Future<void> close() async {
    dispose();
    await client.close();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _connectionStates.cancel().ignore();
    _snapshotErrors.cancel().ignore();
    client.stopPolling();
    if (_notifications == 0) {
      _notifierDisposed = true;
      super.dispose();
    }
  }
}
