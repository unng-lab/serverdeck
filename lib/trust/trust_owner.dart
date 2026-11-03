import 'dart:async';

import '../connections/connection_owner.dart';
import '../connections/ssh_transport.dart';
import '../domain/actor.dart';
import '../domain/app_operations.dart';
import '../domain/models.dart';
import '../domain/receipt_book.dart';
import '../profiles/key_envelope.dart';
import '../runtime/capability.dart';
import '../runtime/owned_work.dart';
import '../storage/domain_repository.dart';
import '../storage/records.dart';

final class TrustOwner
    implements ConnectionTrustPolicy, TrustOperations, RuntimeCapability {
  TrustOwner({
    required this.repository,
    required this.getGate,
    required this.connections,
    required this.receipts,
    required this.newId,
    required this.utcNow,
    Duration Function()? monotonicNow,
    ScheduleOwnedDeadline? schedule,
  }) : _now = monotonicNow ?? (() => _clock.elapsed),
       _schedule = schedule ?? _timer;
  static final _clock = Stopwatch()..start();
  static const lifetime = Duration(minutes: 5);
  final DomainRepository repository;
  final DomainCommandGate Function() getGate;
  final ConnectionOwner connections;
  final ReceiptBook receipts;
  final String Function() newId;
  final int Function() utcNow;
  final Duration Function() _now;
  final ScheduleOwnedDeadline _schedule;
  final _challenges = <String, _Consent>{};
  final _pendingWarnings = <String, _PendingObservation>{};
  final _deciding = <_Consent>{};
  final _work = <Future<void>>{};
  bool _stopped = false;
  @override
  String get id => 'trust';
  static void Function() _timer(Duration duration, void Function() callback) {
    final t = Timer(duration, callback);
    return t.cancel;
  }

  String _id() {
    final value = newId();
    if (!isCanonicalUuid(value))
      throw const OperationFailure(FailureCode.storageUnavailable);
    return value;
  }

  void _admit() {
    if (_stopped) throw const OperationFailure(FailureCode.shuttingDown);
  }

  Profile _profile(DomainRead r, String id) {
    if (!isCanonicalUuid(id))
      throw const OperationFailure(
        FailureCode.invalidArgument,
        field: OperationField.profileId,
      );
    return r.profile(id) ??
        (throw const OperationFailure(FailureCode.profileNotFound));
  }

  EndpointTrust _endpoint(DomainRead r, String id) =>
      r.endpoint(id) ??
      (throw const OperationFailure(FailureCode.storageUnavailable));
  int _advance(DomainTransaction r) {
    final s = r.settings;
    s.dataRevision = nextRevision(s.dataRevision);
    r.putSettings(s);
    return s.dataRevision;
  }

  bool _equal(List<int>? a, List<int> b) => a != null && sameKeyBytes(a, b);

  @override
  TrustChallenge? challenge(String profileId) {
    final record = _challenges[profileId];
    if (record == null) return null;
    // Projections produced by the selected decision must not invalidate its
    // pending wait after the durable revision changes but before authentication
    // is resumed. Hide the in-flight consent until the decision finishes.
    if (_deciding.contains(record)) return null;
    final valid = repository.read((r) {
      final p = r.profile(profileId),
          e = p == null ? null : r.endpoint(p.endpointId);
      return p != null &&
          e != null &&
          p.endpointId == record.proof.endpointId &&
          p.profileRevision == record.public.profileRevision &&
          e.trustRevision == record.public.trustRevision &&
          e.observationRevision == record.public.observationRevision &&
          connections.generation(profileId) == record.proof.generation;
    });
    if (!record.active || _now() >= record.deadline || !valid) {
      _drop(
        record,
        _now() >= record.deadline ? FailureCode.timeout : FailureCode.conflict,
      );
      return null;
    }
    return record.public;
  }

  @override
  TrustView view(String profileId, EndpointTrust endpoint) {
    final pending = _pendingWarnings[endpoint.endpointId];
    final overlay =
        pending != null &&
        pending.trustRevision == endpoint.trustRevision &&
        endpoint.acceptedKeyBytes != null &&
        !_equal(endpoint.acceptedKeyBytes, pending.observation.blob) &&
        endpoint.observationRevision <= pending.observationRevision + 1;
    return TrustView(
      trustRevision: endpoint.trustRevision,
      observationRevision: endpoint.observationRevision,
      changed: endpoint.changed || overlay,
      acceptedFingerprint: endpoint.acceptedFingerprint,
      keyType: endpoint.acceptedType,
      observedFingerprint: overlay
          ? pending.observation.fingerprint
          : endpoint.observedFingerprint,
      observedKeyType: overlay
          ? pending.observation.keyType
          : endpoint.observedType,
      detectedAt: overlay ? pending.detectedAt : endpoint.detectedAt,
      challenge: challenge(profileId),
    );
  }

  @override
  Future<OperationResult<TrustView>> getTrust(Actor actor, String profileId) =>
      _owned(
        getGate().submit(
          actor,
          (ctx) => ctx.read(
            () => repository.read((r) {
              final p = _profile(r, profileId);
              return view(profileId, _endpoint(r, p.endpointId));
            }),
          ),
        ),
      );
  @override
  void invalidate(String profileId, String attemptId) {
    final record = _challenges[profileId];
    if (record != null &&
        record.proof.attemptId == attemptId &&
        !_deciding.contains(record))
      _drop(record, FailureCode.conflict);
  }

  void _drop(_Consent record, FailureCode reason) {
    if (!record.active) return;
    record.active = false;
    record.cancelTimer?.call();
    if (identical(_challenges[record.proof.profileId], record))
      _challenges.remove(record.proof.profileId);
    if (!(record.wait?.isCompleted ?? true))
      record.wait!.completeError(OperationFailure(reason));
  }

  void _dropEndpoint(String endpointId, {_Consent? except}) {
    for (final c in List.of(_challenges.values)) {
      if (c.proof.endpointId == endpointId && !identical(c, except))
        _drop(c, FailureCode.conflict);
    }
  }

  _Consent _issue(
    CommandContext ctx,
    ConnectionProof proof,
    HostObservation offered,
    TrustKind kind,
  ) {
    connections.checkProof(
      ctx,
      proof,
      allowTerminal: kind == TrustKind.replace,
    );
    final fields = repository.read((r) {
      final p = _profile(r, proof.profileId);
      return (p, _endpoint(r, p.endpointId));
    });
    final previous = _challenges[proof.profileId];
    if (previous != null &&
        previous.active &&
        previous.proof.attemptId == proof.attemptId &&
        previous.public.kind == kind &&
        previous.public.trustRevision == fields.$2.trustRevision &&
        previous.public.observationRevision == fields.$2.observationRevision &&
        previous.public.profileRevision == fields.$1.profileRevision &&
        sameKeyBytes(previous.offered.blob, offered.blob) &&
        _now() < previous.deadline)
      return previous;
    if (previous != null) _drop(previous, FailureCode.conflict);
    final p = fields.$1, e = fields.$2;
    final value = TrustChallenge(
      kind: kind,
      nonce: _id(),
      attemptId: proof.attemptId,
      endpointId: proof.endpointId,
      profileRevision: p.profileRevision,
      trustRevision: e.trustRevision,
      observationRevision: e.observationRevision,
      fingerprint: offered.fingerprint,
      expiresAt: utcNow() + lifetime.inMilliseconds,
      host: p.originalHost,
      port: p.port,
      keyType: offered.keyType,
      oldFingerprint: kind == TrustKind.replace ? e.acceptedFingerprint : null,
    );
    final record = _Consent(proof, offered, value, _now() + lifetime);
    if (kind == TrustKind.first) {
      record.wait = Completer<bool>();
      record.wait!.future.ignore();
    }
    _challenges[p.profileId] = record;
    void arm() {
      record.cancelTimer = _schedule(record.deadline - _now(), () {
        if (!record.active || !identical(_challenges[p.profileId], record))
          return;
        if (_now() < record.deadline) {
          arm();
          return;
        }
        _drop(record, FailureCode.timeout);
      });
    }

    arm();
    return record;
  }

  void _observeRecord(EndpointTrust e, HostObservation o, int time) {
    if (!_equal(e.acceptedKeyBytes, o.blob)) {
      if (!_equal(e.observedKeyBytes, o.blob)) {
        e.observationRevision = nextRevision(e.observationRevision);
        e.observedKeyBytes = List.of(o.blob);
        e.observedType = o.keyType;
        e.observedFingerprint = o.fingerprint;
        e.detectedAt = time;
      }
      if (e.acceptedKeyBytes != null) e.changed = true;
    }
    e.lastSeenAt = utcNow();
  }

  Future<_Observed> _observe(
    ConnectionProof proof,
    HostObservation observation, {
    bool rekey = false,
  }) async {
    ConnectionCleanup? cleanup;
    _PendingObservation? baseline;
    try {
      return await getGate().prepare(proof.actor, (ctx) async {
        _admit();
        connections.checkProof(ctx, proof);
        final old = repository.read((r) => _endpoint(r, proof.endpointId));
        baseline = _PendingObservation(
          observation,
          old.trustRevision,
          old.observationRevision,
          utcNow(),
        );
        var mismatch = false, matched = false, changed = false;
        await repository.write(
          (tx) => ctx.linearize(() {
            connections.checkProof(ctx, proof);
            final p = _profile(tx, proof.profileId),
                e = _endpoint(tx, proof.endpointId);
            if (p.endpointId != e.endpointId)
              throw const OperationFailure(FailureCode.conflict);
            final pending = _pendingWarnings[e.endpointId];
            if (pending != null &&
                pending.trustRevision == e.trustRevision &&
                e.observationRevision <= pending.observationRevision + 1 &&
                (e.observationRevision == pending.observationRevision ||
                    _equal(e.observedKeyBytes, pending.observation.blob)))
              _observeRecord(e, pending.observation, pending.detectedAt);
            final previous = e.observationRevision;
            _observeRecord(e, observation, utcNow());
            matched = _equal(e.acceptedKeyBytes, observation.blob);
            mismatch = e.acceptedKeyBytes != null && !matched;
            changed = e.changed;
            if (previous != e.observationRevision) _dropEndpoint(e.endpointId);
            if (mismatch)
              cleanup = connections.invalidateEndpoint(ctx, e.endpointId);
            tx.putEndpoint(e);
            _advance(tx);
            return view(proof.profileId, e);
          }, fence: proof.baseFence),
        );
        _pendingWarnings.remove(proof.endpointId);
        if (mismatch) {
          final terminal = connections.proofFor(
            ctx,
            proof.profileId,
            proof.attemptId,
            allowTerminal: true,
          );
          final consent = _issue(ctx, terminal, observation, TrustKind.replace);
          return _Observed(false, consent, cleanup);
        }
        if (rekey) throw const OperationFailure(FailureCode.conflict);
        if (matched) {
          connections.allowAuthentication(ctx, proof, observation);
          if (changed) _issue(ctx, proof, observation, TrustKind.retain);
          return const _Observed(true, null, null);
        }
        final consent = _issue(ctx, proof, observation, TrustKind.first);
        final wait = connections.beginTrustWait(ctx, proof);
        wait.result
            .then(
              (value) {
                if (!(consent.wait?.isCompleted ?? true))
                  consent.wait!.complete(value);
              },
              onError: (Object error, StackTrace stack) {
                if (!(consent.wait?.isCompleted ?? true))
                  consent.wait!.completeError(error, stack);
              },
            )
            .ignore();
        return _Observed(false, consent, null);
      });
    } catch (error) {
      if (baseline != null) _pendingWarnings[proof.endpointId] = baseline!;
      if (cleanup != null) {
        connections.observedStorageFailure(proof);
        try {
          await cleanup!.close();
        } catch (_) {}
      }
      rethrow;
    }
  }

  @override
  Future<bool> verify(ConnectionProof proof, HostObservation observation) =>
      _owned(_verify(proof, observation));
  Future<bool> _verify(
    ConnectionProof proof,
    HostObservation observation,
  ) async {
    final result = await _observe(proof, observation);
    if (result.cleanup != null) {
      try {
        await result.cleanup!.close();
      } catch (error) {
        if (result.consent != null)
          _drop(result.consent!, FailureCode.cleanupRequired);
        rethrow;
      }
      return false;
    }
    if (result.accepted) return true;
    return result.consent!.wait!.future;
  }

  @override
  Future<void> changed(ConnectionProof proof, HostObservation observation) =>
      _owned(_changed(proof, observation));
  Future<void> _changed(
    ConnectionProof proof,
    HostObservation observation,
  ) async {
    final result = await _observe(proof, observation, rekey: true);
    if (result.cleanup != null) {
      try {
        await result.cleanup!.close();
      } catch (error) {
        if (result.consent != null)
          _drop(result.consent!, FailureCode.cleanupRequired);
        rethrow;
      }
    }
  }

  Map<String, Object?> _payload(TrustDecision d) => {
    'profileId': d.profileId,
    'attemptId': d.attemptId,
    'nonce': d.nonce,
    'expectedProfileRevision': d.expectedProfileRevision,
    'expectedTrustRevision': d.expectedTrustRevision,
    'expectedObservationRevision': d.expectedObservationRevision,
    'confirmed': d.confirmed,
    if (d is! ReplacementDecision && d is! RetentionDecision)
      'fingerprint': d.fingerprint,
    if (d is ReplacementDecision) 'oldFingerprint': d.oldFingerprint,
    if (d is ReplacementDecision) 'newFingerprint': d.newFingerprint,
    if (d is RetentionDecision) 'acceptedFingerprint': d.acceptedFingerprint,
  };
  _Consent _validate(
    CommandContext ctx,
    DomainRead r,
    TrustDecision d,
    TrustKind kind,
  ) {
    _admit();
    final p = _profile(r, d.profileId),
        e = _endpoint(r, p.endpointId),
        c = _challenges[d.profileId];
    if (c == null ||
        !c.active ||
        _now() >= c.deadline ||
        c.public.kind != kind ||
        c.public.nonce != d.nonce ||
        c.proof.attemptId != d.attemptId ||
        c.public.fingerprint != d.fingerprint ||
        c.proof.endpointId != p.endpointId ||
        p.profileRevision != d.expectedProfileRevision ||
        e.trustRevision != d.expectedTrustRevision ||
        e.observationRevision != d.expectedObservationRevision ||
        c.public.profileRevision != d.expectedProfileRevision ||
        c.public.trustRevision != d.expectedTrustRevision ||
        c.public.observationRevision != d.expectedObservationRevision)
      throw const OperationFailure(FailureCode.conflict);
    if (!d.confirmed)
      throw const OperationFailure(
        FailureCode.invalidArgument,
        field: OperationField.request,
      );
    connections.checkProof(
      ctx,
      c.proof,
      allowTerminal: kind != TrustKind.first,
    );
    if (kind == TrustKind.first) {
      if (e.acceptedKeyBytes != null ||
          !_equal(e.observedKeyBytes, c.offered.blob))
        throw const OperationFailure(FailureCode.conflict);
    } else if (kind == TrustKind.replace) {
      final replacement = d as ReplacementDecision;
      if (!e.changed ||
          e.acceptedKeyBytes == null ||
          !_equal(e.observedKeyBytes, c.offered.blob) ||
          replacement.oldFingerprint != e.acceptedFingerprint ||
          replacement.newFingerprint != c.offered.fingerprint)
        throw const OperationFailure(FailureCode.conflict);
    } else {
      final retain = d as RetentionDecision;
      if (!e.changed ||
          !_equal(e.acceptedKeyBytes, c.offered.blob) ||
          retain.acceptedFingerprint != e.acceptedFingerprint)
        throw const OperationFailure(FailureCode.conflict);
    }
    return c;
  }

  @override
  Future<OperationResult<MutationValue>> acceptTrust(
    Actor a,
    TrustDecision d,
  ) => _owned(_decide(a, d, TrustKind.first, ReceiptMethod.acceptTrust));
  @override
  Future<OperationResult<MutationValue>> replaceTrust(
    Actor a,
    ReplacementDecision d,
  ) => _owned(_decide(a, d, TrustKind.replace, ReceiptMethod.replaceTrust));
  @override
  Future<OperationResult<MutationValue>> retainTrust(
    Actor a,
    RetentionDecision d,
  ) => _owned(_decide(a, d, TrustKind.retain, ReceiptMethod.retainTrust));
  Future<OperationResult<MutationValue>> _decide(
    Actor actor,
    TrustDecision d,
    TrustKind kind,
    ReceiptMethod method,
  ) async {
    ReceiptTicket? ticket;
    _Consent? selected;
    try {
      _admit();
      ticket = receipts.ticket(actor, method, d.mutationId, _payload(d));
      final intent = await getGate().prepare(actor, (ctx) async {
        final replay = repository.read((r) => receipts.lookup(ctx, r, ticket!));
        if (replay != null) return _DecisionIntent(replay, null, null);
        final consent = repository.read((r) => _validate(ctx, r, d, kind));
        selected = consent;
        _deciding.add(consent);
        final batch = connections.invalidateEndpoint(
          ctx,
          consent.proof.endpointId,
          preserve: kind == TrustKind.first ? consent.proof : null,
        );
        if (kind != TrustKind.first)
          consent.proof = connections.proofFor(
            ctx,
            d.profileId,
            d.attemptId,
            allowTerminal: true,
          );
        return _DecisionIntent(null, consent, batch);
      });
      if (intent.replay != null)
        return await getGate().submit(actor, (_) => intent.replay!);
      try {
        await intent.cleanup!.close();
      } catch (error) {
        _drop(intent.consent!, FailureCode.cleanupRequired);
        rethrow;
      }
      return await getGate().submit(actor, (ctx) async {
        _Consent? committed;
        final result = await repository.write((tx) {
          final replay = receipts.lookup(ctx, tx, ticket!);
          if (replay != null) return replay;
          final consent = _validate(ctx, tx, d, kind);
          return ctx.linearize(
            () {
              final e = _endpoint(tx, consent.proof.endpointId);
              if (kind != TrustKind.retain) {
                e.acceptedKeyBytes = List.of(consent.offered.blob);
                e.acceptedType = consent.offered.keyType;
                e.acceptedFingerprint = consent.offered.fingerprint;
                e.acceptedAt = utcNow();
              }
              e.changed = false;
              e.observedKeyBytes = null;
              e.observedType = null;
              e.observedFingerprint = null;
              e.detectedAt = null;
              e.trustRevision = nextRevision(e.trustRevision);
              tx.putEndpoint(e);
              final revision = _advance(tx);
              final value = MutationValue(
                entityId: d.profileId,
                revision: e.trustRevision,
              );
              receipts.record(tx, ticket!, value, revision);
              committed = consent;
              return value;
            },
            fence: VersionFence(
              profileId: d.profileId,
              profileRevision: d.expectedProfileRevision,
              connectionRevision: consent.proof.baseFence.connectionRevision,
              credentialRevision: consent.proof.baseFence.credentialRevision,
              endpointId: consent.proof.endpointId,
              trustRevision: d.expectedTrustRevision,
              observationRevision: d.expectedObservationRevision,
              attemptGeneration: consent.proof.generation,
            ),
          );
        });
        if (committed != null) {
          final c = committed!;
          _pendingWarnings.remove(c.proof.endpointId);
          if (kind == TrustKind.first) {
            connections.allowAuthentication(ctx, c.proof, c.offered);
          }
          _dropEndpoint(c.proof.endpointId, except: c);
          c.active = false;
          c.cancelTimer?.call();
          if (identical(_challenges[d.profileId], c))
            _challenges.remove(d.profileId);
        }
        return result;
      });
    } catch (error) {
      if (ticket != null) {
        try {
          final replay = await getGate().prepare(
            actor,
            (ctx) => repository.read((r) => receipts.lookup(ctx, r, ticket!)),
          );
          if (replay != null)
            return await getGate().submit(actor, (_) => replay);
        } catch (auth) {
          return OperationResult.failure(_failure(auth));
        }
      }
      return OperationResult.failure(_failure(error));
    } finally {
      if (selected != null) _deciding.remove(selected);
      ticket?.dispose();
    }
  }

  Future<T> _owned<T>(Future<T> work) {
    final done = work.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _work.add(done);
    done.whenComplete(() => _work.remove(done)).ignore();
    return work;
  }

  OperationFailure _failure(Object error) => error is OperationFailure
      ? error
      : const OperationFailure(FailureCode.storageUnavailable, retryable: true);
  @override
  Future<void> stopAdmission() async {
    _stopped = true;
  }

  @override
  Future<void> cancelPending() async {
    for (final c in List.of(_challenges.values)) {
      _drop(c, FailureCode.shuttingDown);
    }
  }

  @override
  Future<void> closeSessions() async {}
  @override
  Future<void> drain() async {
    while (_work.isNotEmpty) {
      await Future.wait(List.of(_work));
    }
  }

  @override
  Future<void> dispose() async {
    await stopAdmission();
    await cancelPending();
    await drain();
    _pendingWarnings.clear();
  }
}

final class _Consent {
  _Consent(this.proof, this.offered, this.public, this.deadline);
  ConnectionProof proof;
  final HostObservation offered;
  final TrustChallenge public;
  final Duration deadline;
  bool active = true;
  void Function()? cancelTimer;
  Completer<bool>? wait;
}

final class _PendingObservation {
  const _PendingObservation(
    this.observation,
    this.trustRevision,
    this.observationRevision,
    this.detectedAt,
  );
  final HostObservation observation;
  final int trustRevision, observationRevision, detectedAt;
}

final class _Observed {
  const _Observed(this.accepted, this.consent, this.cleanup);
  final bool accepted;
  final _Consent? consent;
  final ConnectionCleanup? cleanup;
}

final class _DecisionIntent {
  const _DecisionIntent(this.replay, this.consent, this.cleanup);
  final MutationValue? replay;
  final _Consent? consent;
  final ConnectionCleanup? cleanup;
}
