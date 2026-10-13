import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:serverdeck_protocol/models.dart';

import 'local_api_client.dart';

/// Owns startup timing and presentation; platform callbacks own verified launch.
class BootstrapController extends ChangeNotifier {
  BootstrapController({
    required this.client,
    required Future<void> Function() prepare,
    required Future<void> Function() ensureService,
    Future<void> Function()? recoverService,
    Duration Function()? elapsed,
    Future<void> Function(Duration)? delay,
    ScheduleDeadline? schedule,
  }) : _prepare = prepare,
       _ensureService = ensureService,
       _recoverService = recoverService,
       _delay = delay ?? Future<void>.delayed,
       _schedule = schedule ?? _timer {
    _elapsed = elapsed ?? () => _watch.elapsed;
    _connectionStates = client.states.listen((state) {
      if (!_disposed &&
          state == ClientConnectionState.disconnected &&
          _state == ReadinessState.ready) {
        client.stopPolling();
        _show(ReadinessState.unavailable, ErrorCode.serviceUnavailable);
        retry().ignore();
      }
    });
    _snapshotErrors = client.snapshotErrors.listen((code) {
      if (_disposed || _state != ReadinessState.ready) return;
      final state = switch (code) {
        ErrorCode.storageBlocked => ReadinessState.storageBlocked,
        ErrorCode.incompatible => ReadinessState.incompatible,
        ErrorCode.notReady => ReadinessState.unavailable,
        _ => null,
      };
      if (state != null) {
        client.stopPolling();
        _show(state, code);
      }
    });
  }

  final LocalApiClient client;
  final Future<void> Function() _prepare, _ensureService;
  final Future<void> Function()? _recoverService;
  late final StreamSubscription<ClientConnectionState> _connectionStates;
  late final StreamSubscription<ErrorCode> _snapshotErrors;
  final Future<void> Function(Duration) _delay;
  final ScheduleDeadline _schedule;
  final _watch = Stopwatch()..start();
  late final Duration Function() _elapsed;
  Future<void>? _attempt;
  bool _disposed = false;
  int _notifications = 0;
  bool _notifierDisposed = false;
  ReadinessState _state = ReadinessState.unavailable;
  int _readinessEpoch = 0;
  ErrorCode? _reason;
  String? _workspaceId;
  ReadinessState get state => _state;

  /// Changes before notifying listeners, including nested readiness cycles.
  int get readinessEpoch => _readinessEpoch;
  ErrorCode? get reason => _reason;
  String? get workspaceId => _workspaceId;
  bool get retryInProgress => _attempt != null;

  static CancelDeadline _timer(Duration duration, void Function() action) {
    final timer = Timer(duration, action);
    return timer.cancel;
  }

  Future<void> retry() {
    if (_disposed) return Future.value();
    if (_attempt != null) return _attempt!;
    final completed = Completer<void>();
    _attempt = completed.future;
    _run()
        .then(
          (_) {
            _attempt = null;
            completed.complete();
            _notify();
          },
          onError: (Object error, StackTrace stack) {
            _attempt = null;
            completed.completeError(error, stack);
            _notify();
          },
        )
        .ignore();
    return completed.future;
  }

  void _show(ReadinessState state, ErrorCode? reason, [String? workspace]) {
    if (_disposed) return;
    if (state != _state) _readinessEpoch++;
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
      if (_disposed && _notifications == 0) _disposeNotifier();
    }
  }

  void _disposeNotifier() {
    if (_notifierDisposed) return;
    _notifierDisposed = true;
    super.dispose();
  }

  Future<void> _run() async {
    final deadline = _elapsed() + const Duration(seconds: 30);
    var expired = false;
    final cancel = _schedule(const Duration(seconds: 30), () {
      if (_disposed) return;
      expired = true;
      client.stopPolling();
      _show(ReadinessState.unavailable, ErrorCode.timeout);
    });
    bool live() => !_disposed && !expired && _elapsed() < deadline;
    Future<void> wait(Duration duration) async {
      final remaining = deadline - _elapsed();
      if (remaining > Duration.zero) {
        await _delay(duration < remaining ? duration : remaining);
      }
    }

    client.stopPolling();
    _show(ReadinessState.starting, null);
    try {
      if (!live()) return;
      await _prepare();
      if (!live()) {
        _show(ReadinessState.unavailable, ErrorCode.timeout);
        return;
      }
      await _ensureService();
      var backoff = const Duration(milliseconds: 100);
      while (live()) {
        try {
          await client.connect();
          if (!live()) break;
          final response = await client.read(ApiMethod.readinessGet);
          if (!live()) break;
          final value = response.result;
          final wireState = value['state'] as String;
          final state = wireState == 'storage-blocked'
              ? ReadinessState.storageBlocked
              : ReadinessState.values.byName(wireState);
          final code = value['reason'];
          final reason = code == null
              ? null
              : ErrorCode.values.firstWhere((e) => e.wireName == code);
          _show(state, reason, value['workspaceId'] as String?);
          if (state == ReadinessState.ready) {
            if (live()) client.startPolling();
            return;
          }
          if (state == ReadinessState.storageBlocked ||
              state == ReadinessState.incompatible ||
              state == ReadinessState.unavailable)
            return;
          await wait(const Duration(milliseconds: 250));
        } on LocalApiException catch (error) {
          if (error.code != ErrorCode.serviceUnavailable &&
              error.code != ErrorCode.timeout)
            rethrow;
          if (live()) await _recoverService?.call();
          await wait(backoff);
          backoff = Duration(
            milliseconds: (backoff.inMilliseconds * 2).clamp(100, 1000),
          );
        }
      }
      if (!_disposed) _show(ReadinessState.unavailable, ErrorCode.timeout);
    } on Object catch (error) {
      if (expired || _elapsed() >= deadline) {
        _show(ReadinessState.unavailable, ErrorCode.timeout);
        return;
      }
      final code = error is LocalApiException
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
    if (!_disposed) dispose();
    await _attempt;
    await client.close();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _connectionStates.cancel().ignore();
    _snapshotErrors.cancel().ignore();
    client.stopPolling();
    _watch.stop();
    if (_notifications == 0) {
      _notifierDisposed = true;
      super.dispose();
    }
  }
}
