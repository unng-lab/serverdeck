import 'dart:async';

import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../credentials/provider.dart';
import '../storage/key_custody.dart';
import '../storage/host_trust_models.dart';
import '../storage/models.dart';
import '../storage/state_store.dart';
import 'service.dart';
import 'validation.dart';

enum _FoundationMode { legacy, operational, trusted }

/// Internal authenticated-session consumer; no transport is enabled here.
class MutationCoordinator {
  MutationCoordinator(
    StateStore store,
    KeyCustody custody,
    ReceiptKeyMaterial receiptKey, {
    DateTime Function()? clock,
  }) : this._(store, custody, receiptKey, _FoundationMode.legacy, clock);
  MutationCoordinator.operational(
    StateStore store,
    KeyCustody custody,
    ReceiptKeyMaterial receiptKey, {
    DateTime Function()? clock,
  }) : this._(store, custody, receiptKey, _FoundationMode.operational, clock);
  MutationCoordinator._(
    this.store,
    this.custody,
    this.receiptKey,
    this._mode,
    DateTime Function()? clock,
  ) : _clock = clock ?? DateTime.now,
      _profiles = ProfileService(CredentialProvider(custody)) {
    if (_isQueued) {
      final state = _state;
      if (receiptKey.workspaceId != state.workspaceId ||
          receiptKey.receiptKeyId != state.receiptKeyId ||
          receiptKey.ownerSid != state.ownerSid ||
          custody.ownerSid != state.ownerSid)
        throw StateError('STORAGE_BLOCKED');
      if (_trusted) store.assertAutomationCustody(custody, receiptKey);
    }
  }
  final _FoundationMode _mode;
  bool get isOperational => _operational;
  bool get _operational => _mode == _FoundationMode.operational;
  bool get isTrusted => _trusted;
  bool get _trusted => _mode == _FoundationMode.trusted;
  bool get _isQueued => _mode != _FoundationMode.legacy;
  WorkspaceState get _state => switch (_mode) {
    _FoundationMode.trusted => store.trustedOperational.foundation.foundation,
    _FoundationMode.operational => store.operational.foundation.state,
    _FoundationMode.legacy => store.state,
  };
  final StateStore store;
  final KeyCustody custody;
  final ReceiptKeyMaterial receiptKey;
  final ProfileService _profiles;
  final DateTime Function() _clock;
  final _inflight = <String, _Pending>{};
  final _queue = <_Pending>[];
  bool _running = false, _stopping = false, _blocked = false;
  Completer<void>? _closed;

  Future<MutationResult> submit(
    String requestId,
    ApiMethod method,
    Map<String, Object?> params, {
    required String requester,
  }) {
    try {
      return activate(reserve(requestId, method, params, requester: requester));
    } catch (error) {
      return Future.error(_safe(error));
    }
  }

  /// Pure, synchronous admission. No credential preparation, native wait or
  /// StateStore queue is entered until the trusted adapter activates its token.
  FoundationMutationReservation reserve(
    String requestId,
    ApiMethod method,
    Map<String, Object?> params, {
    required String requester,
  }) {
    try {
      _ensure();
      requireUuid(requestId);
      if (requester.isEmpty) throw const FormatException('VALIDATION');
      final codec = StrictCodec();
      final input = validateMutationInput(
        method,
        codec.decode(
          codec.encode(params, maxBytes: 256 * 1024),
          maxBytes: 256 * 1024,
        ),
      );
      final digest = custody.receiptDigestSync(receiptKey, {
        'operation': method.wireName,
        'params': input,
      });
      _checkAutomationId(requestId);
      final receipt = _state.receipts[requestId];
      if (receipt != null) {
        if (receipt.inputDigest != digest)
          throw StateError('IDEMPOTENCY_CONFLICT');
        return FoundationMutationReservation._(
          this,
          requestId,
          requester,
          null,
          Future.value(receipt.result),
        );
      }
      final existing = _inflight[requestId];
      if (existing != null) {
        if (existing.digest != digest) throw StateError('IDEMPOTENCY_CONFLICT');
        existing.requesters.add(requester);
        return FoundationMutationReservation._(
          this,
          requestId,
          requester,
          existing,
          existing.result.future,
        );
      }
      if ((_isQueued ? _inflight.length : _queue.length) >= 32)
        throw StateError('RESOURCE_LIMIT');
      final pending = _Pending(requestId, method, input, digest, requester);
      pending.result.future.ignore();
      _inflight[requestId] = pending;
      return FoundationMutationReservation._(
        this,
        requestId,
        requester,
        pending,
        pending.result.future,
      );
    } catch (error) {
      throw _safe(error);
    }
  }

  Future<MutationResult> activate(FoundationMutationReservation reservation) {
    try {
      _ensure();
      if (!identical(reservation._coordinator, this))
        throw StateError('FORBIDDEN');
      _checkAutomationId(reservation._id);
      final pending = reservation._pending;
      if (pending == null || pending.result.isCompleted)
        return reservation.result;
      if (!identical(_inflight[pending.id], pending) ||
          !pending.requesters.contains(reservation._requester))
        throw StateError('SERVICE_UNAVAILABLE');
      if (pending.activated) return pending.result.future;
      pending.activated = true;
      _queue.add(pending);
      if (!_running) {
        _running = true;
        scheduleMicrotask(_drain);
      }
      return reservation.result;
    } catch (error) {
      return Future.error(_safe(error));
    }
  }

  void _checkAutomationId(String id) {
    if (_isQueued &&
        (_trusted
                ? store.trustedOperational.automation.receipts
                : store.operational.automation.receipts)
            .containsKey(id))
      throw StateError('IDEMPOTENCY_CONFLICT');
  }

  void _ensure() {
    if (_blocked) throw StateError('STORAGE_BLOCKED');
    if (_stopping) throw StateError('NOT_READY');
    _state;
    if (_operational) store.operational;
  }

  MutationStatusResult status(String requestId) {
    _ensure();
    requireUuid(requestId);
    final receipt = _state.receipts[requestId];
    if (receipt != null) return MutationStatusResult.committed(receipt.result);
    final pending = _inflight[requestId];
    if (pending == null) return const MutationStatusResult.notFound();
    return pending.running
        ? const MutationStatusResult.running()
        : const MutationStatusResult.queued();
  }

  RecentMutationsView recent({int limit = 20}) {
    _ensure();
    if (limit < 1 || limit > 100) throw const FormatException('VALIDATION');
    final receipts = _state.receipts.values.toList()
      ..sort(
        (a, b) =>
            BigInt.parse(b.result.storeRevision)
                .compareTo(BigInt.parse(a.result.storeRevision)),
      );
    return RecentMutationsView(
      List.unmodifiable(receipts.take(limit).map((r) => r.view)),
      truncated: receipts.length > limit,
    );
  }

  ProfilesSnapshot listProfiles() {
    _ensure();
    return _profiles.list(_state);
  }

  ProfileSnapshot getProfile(String id) {
    _ensure();
    requireUuid(id);
    return _profiles.get(_state, id);
  }

  SettingsSnapshot getSettings() {
    _ensure();
    return _profiles.settings.get(_state);
  }

  void detach(String requester) {
    for (final pending in _inflight.values.toList()) {
      pending.requesters.remove(requester);
      if (!pending.running && pending.requesters.isEmpty) _cancel(pending);
    }
  }

  void _cancel(_Pending pending) {
    _queue.remove(pending);
    _inflight.remove(pending.id);
    pending.input.clear();
    pending.result.completeError(StateError('SERVICE_UNAVAILABLE'));
  }

  String _commitTimestamp() {
    final wall = _clock().toUtc();
    var timestamp = DateTime.fromMillisecondsSinceEpoch(
      wall.millisecondsSinceEpoch,
      isUtc: true,
    ).toIso8601String();
    // A persisted floor survives restart and keeps revision-ordered receipts
    // compatible with timestamp-ordered wire validation after clock rollback.
    final state = _state;
    for (final receipt in state.receipts.values) {
      if (receipt.committedAt.compareTo(timestamp) > 0)
        timestamp = receipt.committedAt;
    }
    for (final profile in state.profiles.values) {
      final updated = profile.toJson()['updatedAt'] as String;
      if (updated.compareTo(timestamp) > 0) timestamp = updated;
    }
    if (_isQueued) {
      for (final receipt
          in (_trusted
                  ? store.trustedOperational.automation.receipts
                  : store.operational.automation.receipts)
              .values) {
        final value = receipt.createdAt.toUtc().toIso8601String();
        if (value.compareTo(timestamp) > 0) timestamp = value;
      }
    }
    return timestamp;
  }

  Future<void> _drain() async {
    while (_queue.isNotEmpty) {
      final pending = _queue.removeAt(0);
      pending.running = true;
      try {
        if (_blocked) throw StateError('STORAGE_BLOCKED');
        _checkAutomationId(pending.id);
        final now = _commitTimestamp();
        final prepared = _trusted
            ? await _profiles.prepareTrusted(
                store.trustedOperational.foundation,
                pending.method,
                pending.input,
                now,
              )
            : await _profiles.prepare(
                _state,
                pending.method,
                pending.input,
                now,
              );
        (prepared.value['receipts'] as Map)[pending.id] = {
          'requestId': pending.id,
          'inputDigest': pending.digest,
          'operation': pending.method.wireName,
          'profileId': prepared.result.entityId,
          'result': prepared.result.toJson(),
          'committedAt': now,
        };
        final parse = _trusted
            ? WorkspaceState.fromTrustedJson
            : WorkspaceState.fromJson;
        final state = parse(
          prepared.value,
          workspaceId: _state.workspaceId,
          receiptKeyId: _state.receiptKeyId,
          ownerSid: _state.ownerSid,
        );
        if (_trusted) {
          await store.commitTrustedFoundation(
            HostTrustState.fromRecords(
              state,
              (prepared as PreparedTrustedMutation).trust,
            ),
          );
        } else if (_operational) {
          await store.commitOperationalFoundation(state);
        } else {
          await store.commit(state);
        }
        pending.result.complete(prepared.result);
      } catch (error, stack) {
        final safe = _safe(error);
        if (safe is StateError && safe.message == 'STORAGE_BLOCKED')
          _blocked = true;
        pending.result.completeError(safe, stack);
      } finally {
        pending.input.clear();
        _inflight.remove(pending.id);
      }
    }
    _running = false;
    _closed?.complete();
  }

  Future<void> close() {
    if (_closed != null) return _closed!.future;
    _stopping = true;
    _closed = Completer<void>();
    for (final pending in _inflight.values.toList()) {
      if (!pending.running) _cancel(pending);
    }
    if (!_running) _closed!.complete();
    return _closed!.future;
  }

  Object _safe(Object error) {
    if (error is FormatException)
      return StateError(
        error.message == 'UNSUPPORTED' ? 'UNSUPPORTED' : 'VALIDATION',
      );
    if (error is StateError &&
        {
          'VALIDATION',
          'UNSUPPORTED',
          'STORAGE_BLOCKED',
          'RESOURCE_LIMIT',
          'REVISION_CONFLICT',
          'IDEMPOTENCY_CONFLICT',
          'ALREADY_EXISTS',
          'NOT_FOUND',
          'NOT_READY',
          'SERVICE_UNAVAILABLE',
          'HOST_BUSY',
          'FORBIDDEN',
        }.contains(error.message))
      return error;
    return StateError('STORAGE_BLOCKED');
  }
}

/// Fixed schema3 queue; never selected by request JSON or an owner role flag.
final class TrustedMutationCoordinator extends MutationCoordinator {
  TrustedMutationCoordinator(
    StateStore store,
    KeyCustody custody,
    ReceiptKeyMaterial receiptKey, {
    DateTime Function()? clock,
  }) : super._(store, custody, receiptKey, _FoundationMode.trusted, clock);
}

class _Pending {
  _Pending(this.id, this.method, this.input, this.digest, String requester)
    : requesters = {requester};
  final String id, digest;
  final ApiMethod method;
  final Map<String, Object?> input;
  final Set<String> requesters;
  final result = Completer<MutationResult>();
  bool running = false, activated = false;
}

/// Opaque, same-coordinator interest; never decoded from a wire request.
final class FoundationMutationReservation {
  FoundationMutationReservation._(
    this._coordinator,
    this._id,
    this._requester,
    this._pending,
    this.result,
  );
  final MutationCoordinator _coordinator;
  final String _id, _requester;
  final _Pending? _pending;
  final Future<MutationResult> result;
}
