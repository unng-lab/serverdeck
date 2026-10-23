import 'dart:async';

import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/protocol.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';

import '../../../../lib/bootstrap/local_api_client.dart';

/// Test-only owner UI response-interest faults above the genuine typed client.
/// This is not evidence of native frame loss: physical EOF/process-loss cases
/// must separately cross the actual native connection. No product hooks exist.
class OwnerResultFaults {
  String? dropNextMethod, holdNextMethod, dropReplyId, holdRequestId;
  bool requestHeld = false, replyDropped = false, lateOriginalDelivered = false;
}

class OwnerResultFaultClient extends LocalApiClient {
  OwnerResultFaultClient(this.inner, this.faults, {this.closeOwner})
    : super.trusted(
        connect: () async {
          await inner.connect();
          return (inner.trustedClient!, inner.generation!);
        },
      );
  final LocalApiClient inner;
  final Future<void> Function()? closeOwner;
  final OwnerResultFaults faults;
  final _waits = <Completer<void>, Timer>{};
  StreamSubscription<ClientConnectionState>? _stateSubscription;
  void _watchConnection() {
    _stateSubscription ??= inner.states.listen((state) {
      if (state == ClientConnectionState.disconnected ||
          state == ClientConnectionState.closed)
        _abortWaits();
    });
  }

  void _abortWaits() {
    for (final entry in _waits.entries.toList()) {
      entry.value.cancel();
      if (!entry.key.isCompleted)
        entry.key.completeError(
          const LocalApiException(ErrorCode.serviceUnavailable),
        );
    }
  }

  MutationIntent? _held;
  bool _closed = false;
  Future<void>? _closingFixture;

  Future<void> _deadline() async {
    final done = Completer<void>();
    done.future.ignore();
    _waits[done] = Timer(rpcDeadline, done.complete);
    try {
      await done.future;
      throw const LocalApiException(ErrorCode.timeout);
    } finally {
      _waits.remove(done)?.cancel();
    }
  }

  @override
  Stream<ClientConnectionState> get states => inner.states;
  @override
  Stream<ClientSnapshot> get snapshots => inner.snapshots;
  @override
  Stream<ErrorCode> get snapshotErrors => inner.snapshotErrors;
  @override
  String? get generation => inner.generation;
  @override
  TrustedApiClient? get trustedClient => inner.trustedClient;
  @override
  void captureResult(String method, Map<String, Object?> value) =>
      inner.captureResult(method, value);
  @override
  Future<void> connect() => inner.connect();
  @override
  void startPolling() => inner.startPolling();
  @override
  void stopPolling() => inner.stopPolling();
  @override
  Future<void> refreshSnapshot() => inner.refreshSnapshot();
  @override
  Future<ApiReply> read(
    ApiMethod method, [
    Map<String, Object?> params = const {},
  ]) => inner.read(method, params);
  @override
  Future<ApiReply> mutationStatus(MutationIntent intent) =>
      inner.mutationStatus(intent);

  @override
  Future<ApiReply> mutate(MutationIntent intent) async {
    if (_closed) throw const LocalApiException(ErrorCode.serviceUnavailable);
    _watchConnection();
    if (faults.holdNextMethod == intent.method.wireName ||
        faults.holdRequestId == intent.id && !faults.requestHeld) {
      faults.holdNextMethod = null;
      faults.holdRequestId = intent.id;
      faults.requestHeld = true;
      _held = intent;
      await _deadline();
    }
    final drop =
        !faults.replyDropped &&
        (faults.dropNextMethod == intent.method.wireName ||
            faults.dropReplyId == intent.id);
    if (drop) {
      faults.dropNextMethod = null;
      faults.dropReplyId = intent.id;
    }
    final result = await inner.mutate(intent);
    if (drop) {
      // Commit and authenticated RPC result are real; only this UI's response
      // interest is suppressed. Other windows and receipt reads are unaffected.
      faults.replyDropped = true;
      await _deadline();
    }
    final original = _held;
    if (original != null && original.id == intent.id) {
      if (!identical(original, intent))
        throw StateError('FIXTURE_INTENT_CHANGED');
      final delayed = await inner.mutate(original);
      final codec = StrictCodec();
      final first = codec.canonical(result.result),
          second = codec.canonical(delayed.result);
      if (result.generation != delayed.generation ||
          first.length != second.length ||
          Iterable<int>.generate(first.length)
              .any((index) => first[index] != second[index])) {
        throw StateError('FIXTURE_REPLAY_CHANGED');
      }
      faults.lateOriginalDelivered = true;
      _held = null;
    }
    return result;
  }

  @override
  Future<void> close() => _closingFixture ??= _closeFixture();
  Future<void> _closeFixture() async {
    _closed = true;
    _held = null;
    _abortWaits();
    await _stateSubscription?.cancel();
    try {
      await inner.close();
    } finally {
      try {
        await closeOwner?.call();
      } finally {
        await super.close();
      }
    }
  }
}
