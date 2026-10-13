import 'dart:async';

import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../credentials/provider.dart';
import '../storage/key_custody.dart';
import '../storage/models.dart';
import '../storage/state_store.dart';
import 'service.dart';
import 'validation.dart';

/// Internal authenticated-session consumer; no transport is enabled here.
class MutationCoordinator {
  MutationCoordinator(
    this.store,
    this.custody,
    this.receiptKey, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _profiles = ProfileService(CredentialProvider(custody));
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
      final receipt = store.state.receipts[requestId];
      if (receipt != null) {
        if (receipt.inputDigest != digest)
          throw StateError('IDEMPOTENCY_CONFLICT');
        return Future.value(receipt.result);
      }
      final existing = _inflight[requestId];
      if (existing != null) {
        if (existing.digest != digest) throw StateError('IDEMPOTENCY_CONFLICT');
        existing.requesters.add(requester);
        return existing.result.future;
      }
      if (_queue.length >= 32) throw StateError('RESOURCE_LIMIT');
      final pending = _Pending(requestId, method, input, digest, requester);
      _inflight[requestId] = pending;
      _queue.add(pending);
      if (!_running) {
        _running = true;
        scheduleMicrotask(_drain);
      }
      return pending.result.future;
    } catch (error) {
      return Future.error(_safe(error));
    }
  }

  void _ensure() {
    if (_blocked) throw StateError('STORAGE_BLOCKED');
    if (_stopping) throw StateError('NOT_READY');
    store.state;
  }

  MutationStatusResult status(String requestId) {
    _ensure();
    requireUuid(requestId);
    final receipt = store.state.receipts[requestId];
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
    final receipts = store.state.receipts.values.toList()
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
    return _profiles.list(store.state);
  }

  ProfileSnapshot getProfile(String id) {
    _ensure();
    requireUuid(id);
    return _profiles.get(store.state, id);
  }

  SettingsSnapshot getSettings() {
    _ensure();
    return _profiles.settings.get(store.state);
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
    final state = store.state;
    for (final receipt in state.receipts.values) {
      if (receipt.committedAt.compareTo(timestamp) > 0)
        timestamp = receipt.committedAt;
    }
    for (final profile in state.profiles.values) {
      final updated = profile.toJson()['updatedAt'] as String;
      if (updated.compareTo(timestamp) > 0) timestamp = updated;
    }
    return timestamp;
  }

  Future<void> _drain() async {
    while (_queue.isNotEmpty) {
      final pending = _queue.removeAt(0);
      pending.running = true;
      try {
        if (_blocked) throw StateError('STORAGE_BLOCKED');
        final now = _commitTimestamp();
        final prepared = await _profiles.prepare(
          store.state,
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
        final state = WorkspaceState.fromJson(
          prepared.value,
          workspaceId: store.state.workspaceId,
          receiptKeyId: store.state.receiptKeyId,
          ownerSid: store.state.ownerSid,
        );
        await store.commit(state);
        pending.result.complete(prepared.result);
      } catch (error) {
        final safe = _safe(error);
        if (safe is StateError && safe.message == 'STORAGE_BLOCKED')
          _blocked = true;
        pending.result.completeError(safe);
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
    for (final pending in _queue.toList()) _cancel(pending);
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
          'STORAGE_BLOCKED',
          'RESOURCE_LIMIT',
          'REVISION_CONFLICT',
          'IDEMPOTENCY_CONFLICT',
          'ALREADY_EXISTS',
          'NOT_FOUND',
          'NOT_READY',
          'SERVICE_UNAVAILABLE',
        }.contains(error.message))
      return error;
    return StateError('STORAGE_BLOCKED');
  }
}

class _Pending {
  _Pending(this.id, this.method, this.input, this.digest, String requester)
    : requesters = {requester};
  final String id, digest;
  final ApiMethod method;
  final Map<String, Object?> input;
  final Set<String> requesters;
  final result = Completer<MutationResult>();
  bool running = false;
}
