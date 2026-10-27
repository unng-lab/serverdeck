import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:serverdeck_protocol/models.dart';

import '../bootstrap/local_api_client.dart';
import 'profile_controller.dart';

class RecoveredCommit {
  const RecoveredCommit(
    this.requestId,
    this.operation,
    this.profileId,
    this.storeRevision,
    this.committedAt,
  );
  final String requestId, operation, storeRevision, committedAt;
  final String? profileId;
}

/// Reads shared committed history once per ready epoch. Never reconstructs or
/// sends a mutation, and never applies an historical receipt to current state.
class StartupRecovery extends ChangeNotifier {
  StartupRecovery({required this.model, ScheduleDeadline? schedule})
    : _schedule = schedule ?? _timer {
    model.addListener(_changed);
    model.bootstrap.addListener(_changed);
    _changed();
  }
  final ProfileController model;
  final ScheduleDeadline _schedule;
  CancelDeadline? _cancelFloorWait;
  static CancelDeadline _timer(Duration delay, void Function() action) {
    final timer = Timer(delay, action);
    return timer.cancel;
  }

  int _epoch = -1, _serial = 0, _notifications = 0;
  bool _attempted = false, _busy = false, _received = false;
  bool _disposed = false, _baseDisposed = false;
  String _floor = '0';
  List<RecoveredCommit> _receipts = const [];
  ErrorCode? _error;
  bool truncated = false;
  bool get _ready => model.bootstrap.state == ReadinessState.ready;
  bool get busy => _busy;
  ErrorCode? get error => _error;
  bool get loaded =>
      !_disposed &&
      _ready &&
      model.loaded &&
      _received &&
      _error == null &&
      BigInt.parse(model.storeRevision!) >= BigInt.parse(_floor);
  List<RecoveredCommit> get receipts => loaded ? _receipts : const [];

  void _changed() {
    if (_disposed) return;
    final epoch = model.bootstrap.readinessEpoch;
    if (epoch != _epoch) {
      _cancelFloorWait?.call();
      _cancelFloorWait = null;
      _epoch = epoch;
      _serial++;
      _attempted = _busy = _received = truncated = false;
      _receipts = const [];
      _floor = '0';
      _error = null;
    }
    if (_ready && model.loaded && !_attempted) _read().ignore();
    if (loaded) {
      _cancelFloorWait?.call();
      _cancelFloorWait = null;
    }
    _notify();
  }

  Future<void> reload() async {
    if (_disposed || !_ready || _busy) return;
    if (!model.loaded) {
      _attempted = false;
      await model.refresh();
      if (_disposed || !_ready || !model.loaded || _busy) return;
    }
    await _read();
  }

  Future<void> _read() async {
    if (_disposed || !_ready || !model.loaded || _busy) return;
    final epoch = model.bootstrap.readinessEpoch;
    final generation = model.bootstrap.client.generation;
    final serial = ++_serial;
    bool live() =>
        !_disposed &&
        _ready &&
        epoch == model.bootstrap.readinessEpoch &&
        serial == _serial &&
        generation == model.bootstrap.client.generation;
    _attempted = _busy = true;
    _received = false;
    _error = null;
    _receipts = const [];
    _cancelFloorWait?.call();
    _cancelFloorWait = null;
    _notify();
    if (!live()) return;
    try {
      final reply = await model.bootstrap.client.read(
        ApiMethod.mutationsRecent,
        {'limit': 20},
      );
      if (!live()) return;
      if (reply.generation != generation)
        throw const FormatException('INCOMPATIBLE');
      model.bootstrap.client.captureResult('mutations.recent', reply.result);
      final raw = reply.result['receipts'] as List;
      if (raw.length > 20) throw const FormatException('INCOMPATIBLE');
      final values = <RecoveredCommit>[];
      BigInt floor = BigInt.zero;
      for (final item in raw) {
        final body = item as Map<String, Object?>;
        final result = body['result'] as Map<String, Object?>;
        final revision = result['storeRevision'] as String;
        final parsed = BigInt.parse(revision);
        if (parsed > floor) floor = parsed;
        values.add(
          RecoveredCommit(
            body['requestId'] as String,
            body['operation'] as String,
            body['profileId'] as String?,
            revision,
            body['committedAt'] as String,
          ),
        );
      }
      _receipts = List.unmodifiable(values);
      _floor = floor.toString();
      truncated = reply.result['truncated'] as bool;
      _received = true;
      if (!loaded) {
        _cancelFloorWait = _schedule(const Duration(seconds: 5), () {
          if (!live() || loaded) return;
          _received = false;
          _receipts = const [];
          _error = ErrorCode.timeout;
          _notify();
        });
        await model.refresh();
      }
    } on Object catch (error) {
      if (!live()) return;
      _receipts = const [];
      _received = false;
      _error = error is LocalApiException
          ? error.code
          : error is FormatException
          ? ErrorCode.incompatible
          : ErrorCode.internal;
    } finally {
      if (live()) {
        _busy = false;
        _notify();
      }
    }
  }

  void _notify() {
    if (_disposed) return;
    _notifications++;
    try {
      notifyListeners();
    } finally {
      _notifications--;
      if (_disposed && !_baseDisposed && _notifications == 0) {
        _baseDisposed = true;
        super.dispose();
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _serial++;
    _cancelFloorWait?.call();
    _cancelFloorWait = null;
    model.removeListener(_changed);
    model.bootstrap.removeListener(_changed);
    _receipts = const [];
    if (_notifications == 0) {
      _baseDisposed = true;
      super.dispose();
    }
  }
}
