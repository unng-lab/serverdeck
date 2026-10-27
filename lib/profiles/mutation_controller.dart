import 'package:flutter/foundation.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/wire.dart';

import '../bootstrap/local_api_client.dart';
import 'profile_controller.dart';

enum MutationPresentation {
  idle,
  submitting,
  unknown,
  waiting,
  retryAllowed,
  committed,
  succeeded,
  conflict,
  failed,
}

/// One explicit action, retained across lost replies. Form drafts remain owned
/// by the form; a receipt never replaces the service-owned current snapshot.
class MutationController extends ChangeNotifier {
  MutationController({required this.model}) {
    _epoch = model.bootstrap.readinessEpoch;
    model.addListener(_snapshot);
    model.bootstrap.addListener(_readiness);
  }

  final ProfileController model;
  MutationIntent? _intent;
  MutationPresentation _state = MutationPresentation.idle;
  ErrorCode? _error;
  String? _committedRevision;
  bool _busy = false, _disposed = false;
  bool get _ready => model.bootstrap.state == ReadinessState.ready;
  int get _currentEpoch => model.bootstrap.readinessEpoch;
  bool _baseDisposed = false;
  bool _readbackStarted = false;
  int _epoch = 0, _notifications = 0;

  MutationPresentation get state => _state;
  ErrorCode? get error => _error;
  String? get requestId => _intent?.id;
  bool get busy => _busy;

  Future<void> submit(ApiMethod method, Map<String, Object?> input) async {
    _readiness();
    if (_disposed || _busy || !_ready || _state != MutationPresentation.idle) {
      return;
    }
    try {
      _intent = MutationIntent(method, input);
    } on LocalApiException catch (error) {
      _set(MutationPresentation.failed, error.code);
      return;
    }
    await _send();
  }

  Future<void> retry() async {
    _readiness();
    if (_disposed ||
        _busy ||
        !_ready ||
        _state != MutationPresentation.retryAllowed)
      return;
    await _send();
  }

  Future<void> _send() async {
    final intent = _intent!;
    final epoch = _currentEpoch;
    final generation = model.bootstrap.client.generation;
    _busy = true;
    _set(MutationPresentation.submitting);
    try {
      if (_disposed) return;
      if (!_ready ||
          epoch != _currentEpoch ||
          generation != model.bootstrap.client.generation) {
        _set(MutationPresentation.unknown, ErrorCode.notReady);
        return;
      }
      final reply = await model.bootstrap.client.mutate(intent);
      if (_disposed) return;
      await _committed(reply.result);
    } on Object catch (error) {
      if (_disposed) return;
      final code = error is LocalApiException ? error.code : ErrorCode.internal;
      if (code == ErrorCode.revisionConflict) {
        _set(MutationPresentation.conflict, code);
        if (!_disposed) await model.refresh();
      } else {
        _set(
          _noEffect(code)
              ? MutationPresentation.failed
              : MutationPresentation.unknown,
          code,
        );
      }
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> checkResult() async {
    _readiness();
    if (_disposed ||
        _busy ||
        !_ready ||
        _intent == null ||
        !{
          MutationPresentation.unknown,
          MutationPresentation.waiting,
          MutationPresentation.retryAllowed,
        }.contains(_state))
      return;
    final epoch = _currentEpoch;
    final generation = model.bootstrap.client.generation;
    _busy = true;
    _notify();
    try {
      if (_disposed) return;
      if (!_ready ||
          epoch != _currentEpoch ||
          generation != model.bootstrap.client.generation) {
        _set(MutationPresentation.unknown, ErrorCode.notReady);
        return;
      }
      final reply = await model.bootstrap.client.mutationStatus(_intent!);
      if (_disposed) return;
      validateMethodResult('mutations.get', reply.result);
      if (reply.result['state'] == 'committed') {
        // A durable receipt stays true across owner generations. Display its
        // effect only after observing a current coherent snapshot.
        await _committed(reply.result['result'] as Map<String, Object?>);
      } else if (epoch == _currentEpoch &&
          _ready &&
          generation == model.bootstrap.client.generation &&
          reply.generation == generation) {
        _set(
          reply.result['state'] == 'not-found'
              ? MutationPresentation.retryAllowed
              : MutationPresentation.waiting,
        );
      } else {
        _set(MutationPresentation.unknown);
      }
    } on Object catch (error) {
      if (!_disposed) {
        _set(
          MutationPresentation.unknown,
          error is LocalApiException ? error.code : ErrorCode.internal,
        );
      }
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> _committed(Map<String, Object?> result) async {
    validateMethodResult(_intent!.method.wireName, result);
    _committedRevision = result['storeRevision'] as String;
    _readbackStarted = false;
    _set(MutationPresentation.committed);
    if (_disposed) return;
    _readbackStarted = true;
    await model.refresh();
    _snapshot();
  }

  /// Retry a read after a known commit; never sends the mutation again.
  Future<void> refreshCommitted() async {
    if (_disposed ||
        _busy ||
        !_ready ||
        _state != MutationPresentation.committed)
      return;
    _busy = true;
    _notify();
    if (_disposed) return;
    try {
      await model.refresh();
      _snapshot();
    } finally {
      _busy = false;
      _notify();
    }
  }

  void _snapshot() {
    if (_disposed ||
        _state != MutationPresentation.committed ||
        !_readbackStarted ||
        !model.loaded ||
        BigInt.parse(model.storeRevision!) < BigInt.parse(_committedRevision!))
      return;
    // A resolved save no longer needs the retry payload. Keep only the safe
    // method/id on the disposed intent for result presentation until closure.
    _intent?.dispose();
    _set(MutationPresentation.succeeded);
  }

  void _readiness() {
    if (_disposed) return;
    final epoch = _currentEpoch;
    if (epoch == _epoch) return;
    _epoch = epoch;
    if (_state == MutationPresentation.retryAllowed ||
        _state == MutationPresentation.waiting) {
      _set(MutationPresentation.unknown);
    } else {
      _notify();
    }
  }

  /// Only a resolved action can be replaced with a new explicit action.
  /// Disposal can abandon unresolved presentation but cannot undo a commit.
  void reset() {
    if (_disposed ||
        _busy ||
        !{
          MutationPresentation.failed,
          MutationPresentation.conflict,
          MutationPresentation.succeeded,
        }.contains(_state))
      return;
    _intent?.dispose();
    _intent = null;
    _committedRevision = null;
    _readbackStarted = false;
    _set(MutationPresentation.idle);
  }

  static bool _noEffect(ErrorCode code) => {
    ErrorCode.unsupported,
    ErrorCode.forbidden,
    ErrorCode.validation,
    ErrorCode.notFound,
    ErrorCode.alreadyExists,
    ErrorCode.idempotencyConflict,
    ErrorCode.resourceLimit,
  }.contains(code);

  void _set(MutationPresentation state, [ErrorCode? error]) {
    _state = state;
    _error = error;
    _notify();
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
    model.removeListener(_snapshot);
    model.bootstrap.removeListener(_readiness);
    _intent?.dispose();
    _intent = null;
    _committedRevision = null;
    if (_notifications == 0) {
      _baseDisposed = true;
      super.dispose();
    }
  }
}
