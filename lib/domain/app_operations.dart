import 'dart:async';

import 'actor.dart';
import 'models.dart';

/// Typed API shared by controllers/router. No generic dispatch, raw DB or actor JSON.
/// Business implementations arrive in T006/T010/T013; this is the common contract.
abstract interface class ProfileOperations {
  Future<OperationResult<ProfilesPage>> listProfiles(
    Actor actor, {
    int limit = 50,
    String? cursor,
  });
  Future<OperationResult<ProfileDetails>> getProfile(
    Actor actor,
    String profileId,
  );
  Future<OperationResult<MutationValue>> createProfile(
    Actor actor,
    ProfileDraft draft, {
    required String mutationId,
  });
  Future<OperationResult<MutationValue>> updateProfile(
    Actor actor,
    String profileId,
    ProfilePatch patch, {
    required int expectedRevision,
    required String mutationId,
  });
  Future<OperationResult<MutationValue>> deleteProfile(
    UiActor actor,
    String profileId, {
    required int expectedRevision,
    required bool confirmed,
  });
}

abstract interface class ConnectionOperations {
  Future<OperationResult<ConnectionView>> connect(
    Actor actor,
    String profileId, {
    required int expectedRevision,
  });
  Future<OperationResult<ConnectionView>> getConnection(
    Actor actor,
    String profileId,
  );
  Future<OperationResult<ConnectionView>> providePassphrase(
    Actor actor,
    String profileId, {
    required String attemptId,
    required String nonce,
    required String passphrase,
  });
  Future<OperationResult<ConnectionView>> cancelConnection(
    Actor actor,
    String profileId, {
    required String attemptId,
  });
  Future<OperationResult<ConnectionView>> disconnect(
    Actor actor,
    String profileId, {
    required String sessionId,
  });
}

abstract interface class TrustOperations {
  Future<OperationResult<TrustView>> getTrust(Actor actor, String profileId);
  Future<OperationResult<MutationValue>> acceptTrust(
    Actor actor,
    TrustDecision decision,
  );
  Future<OperationResult<MutationValue>> replaceTrust(
    Actor actor,
    ReplacementDecision decision,
  );
  Future<OperationResult<MutationValue>> retainTrust(
    Actor actor,
    RetentionDecision decision,
  );
}

abstract interface class AppOperations
    implements ProfileOperations, ConnectionOperations, TrustOperations {}

enum AuthorizationPoint { admission, response }

/// Canonical owner boundary, not a second model or credential cache.
/// Grant owner supplies durable clock/auth checks and synchronous canonical checks.
/// isAuthorizedNow is also called INSIDE actual transaction/socket-write admission.
abstract interface class OperationState {
  String get ownerEpoch;
  bool get running;
  int get dataRevision;
  Future<void> authorize(CommandActor actor, AuthorizationPoint point);
  bool isAuthorizedNow(CommandActor actor);
  EntityVersions? versions(String profileId);
}

final class EntityVersions {
  const EntityVersions({
    required this.profileId,
    required this.profileRevision,
    required this.connectionRevision,
    required this.credentialRevision,
    required this.endpointId,
    required this.trustRevision,
    required this.observationRevision,
    required this.attemptGeneration,
    this.quarantined = false,
  });
  final String profileId, endpointId;
  final int profileRevision, connectionRevision, credentialRevision;
  final int trustRevision, observationRevision, attemptGeneration;
  final bool quarantined;
}

/// Capture only relevant invariants. Rename need not invalidate an established SSH
/// session, while consent can require the complete profile revision.
final class VersionFence {
  VersionFence({
    required this.profileId,
    this.profileRevision,
    this.connectionRevision,
    this.credentialRevision,
    this.endpointId,
    this.trustRevision,
    this.observationRevision,
    this.attemptGeneration,
    this.requiresUsableEndpoint = true,
  }) {
    if (!isCanonicalUuid(profileId) ||
        [
          profileRevision,
          connectionRevision,
          credentialRevision,
          trustRevision,
          observationRevision,
        ].any((v) => v != null && (v < 1 || v > 9007199254740991)) ||
        (attemptGeneration != null &&
            (attemptGeneration! < 0 ||
                attemptGeneration! > 9007199254740991))) {
      throw const OperationFailure(FailureCode.invalidArgument);
    }
  }
  final String profileId;
  final int? profileRevision, connectionRevision, credentialRevision;
  final String? endpointId;
  final int? trustRevision, observationRevision, attemptGeneration;
  final bool requiresUsableEndpoint;

  void check(EntityVersions? current) {
    if (current == null)
      throw const OperationFailure(FailureCode.profileNotFound);
    if (current.profileId != profileId ||
        (profileRevision != null &&
            profileRevision != current.profileRevision) ||
        (connectionRevision != null &&
            connectionRevision != current.connectionRevision) ||
        (credentialRevision != null &&
            credentialRevision != current.credentialRevision) ||
        (endpointId != null && endpointId != current.endpointId) ||
        (trustRevision != null && trustRevision != current.trustRevision) ||
        (observationRevision != null &&
            observationRevision != current.observationRevision) ||
        (attemptGeneration != null &&
            attemptGeneration != current.attemptGeneration)) {
      throw const OperationFailure(FailureCode.conflict);
    }
    if (requiresUsableEndpoint && current.quarantined) {
      throw const OperationFailure(
        FailureCode.cleanupRequired,
        retryable: true,
        reason: FailureReason.connectionCleanup,
      );
    }
  }
}

/// One FIFO owner for local commands; do not await network/crypto/user prompts here.
/// Those prepare outside the gate and return with a captured VersionFence.
final class DomainCommandGate {
  DomainCommandGate({
    required ActorAuthority actors,
    required OperationState state,
  }) : _actors = actors,
       _state = state;
  final ActorAuthority _actors;
  final OperationState _state;
  static const maxQueuedCommands = 64;
  Future<void> _tail = Future.value();
  bool _accepting = true;
  int _queued = 0;
  int get queuedCommands => _queued;

  Future<OperationResult<T>> submit<T extends PublicValue>(
    CommandActor actor,
    FutureOr<T> Function(CommandContext context) action,
  ) async {
    final outcome = await _enqueue(actor, action);
    if (outcome.error != null) return OperationResult.failure(outcome.error!);
    return OperationResult.success(outcome.value as T, outcome.meta!);
  }

  /// Internal split-phase preparation, never a wire result or an effect lease.
  /// Authorization is checked before reading and again before returning private
  /// intent. Async crypto/network/close work occurs AFTER this future completes;
  /// the final command must reacquire the gate and fence its actual transaction.
  Future<T> prepare<T>(
    CommandActor actor,
    FutureOr<T> Function(CommandContext context) action,
  ) async {
    final outcome = await _enqueue(actor, action);
    if (outcome.error != null) throw outcome.error!;
    return outcome.value as T;
  }

  Future<_CommandOutcome<T>> _enqueue<T>(
    CommandActor actor,
    FutureOr<T> Function(CommandContext context) action,
  ) {
    // Preliminary fail-closed check avoids admitting stale actors into the queue.
    // It never replaces the canonical admission/boundary/response checks below.
    try {
      _checkNow(actor);
    } catch (error) {
      return Future.value(_CommandOutcome.failure(_failure(error)));
    }
    if (!_accepting) {
      return Future.value(
        const _CommandOutcome.failure(
          OperationFailure(FailureCode.shuttingDown),
        ),
      );
    }
    if (_queued >= maxQueuedCommands) {
      return Future.value(
        const _CommandOutcome.failure(
          OperationFailure(FailureCode.resourceExhausted, retryable: true),
        ),
      );
    }
    final result = Completer<_CommandOutcome<T>>();
    _queued++;
    _tail = _tail.then((_) async {
      _queued--;
      T? value;
      OperationFailure? failure;
      CommandContext? context;
      var admitted = false;
      try {
        _checkRuntime(actor);
        await _state.authorize(actor, AuthorizationPoint.admission);
        _checkNow(actor);
        admitted = true;
        context = CommandContext._(this, actor);
        value = await action(context);
      } catch (error) {
        failure = _failure(error);
      } finally {
        // Expire before response authorization awaits: late callbacks have no lease.
        if (context != null) context._active = false;
      }
      if (admitted) {
        try {
          _checkRuntime(actor);
          await _state.authorize(actor, AuthorizationPoint.response);
          _checkNow(actor);
        } catch (error) {
          failure = _failure(error);
        }
      }
      if (failure != null) {
        result.complete(_CommandOutcome.failure(failure));
      } else {
        try {
          final revision = _revision();
          result.complete(
            _CommandOutcome.success(
              value as T,
              OperationMeta(
                dataRevision: revision,
                ownerEpoch: _actors.ownerEpoch,
              ),
            ),
          );
        } catch (error) {
          result.complete(_CommandOutcome.failure(_failure(error)));
        }
      }
    });
    return result.future;
  }

  OperationFailure _failure(Object error) => error is OperationFailure
      ? error
      : const OperationFailure(FailureCode.storageUnavailable, retryable: true);

  void _checkRuntime(CommandActor actor) {
    if (actor is McpActor && actor.requestCancelled)
      throw const OperationFailure(FailureCode.conflict);
    if (!_accepting || !_state.running)
      throw const OperationFailure(FailureCode.shuttingDown);
    if (!_actors.owns(actor) || _state.ownerEpoch != _actors.ownerEpoch) {
      throw const OperationFailure(FailureCode.authRequired);
    }
  }

  void _checkNow(CommandActor actor) {
    _checkRuntime(actor);
    if (!_state.isAuthorizedNow(actor)) {
      throw const OperationFailure(FailureCode.authRequired);
    }
    _revision();
  }

  int _revision() {
    final value = _state.dataRevision;
    if (value < 1 || value > 9007199254740991) {
      throw const OperationFailure(FailureCode.storageUnavailable);
    }
    return value;
  }

  void stopAdmission() => _accepting = false;
  Future<void> drain() => _tail;
}

final class CommandContext {
  CommandContext._(this._gate, this.actor);
  final DomainCommandGate _gate;
  final CommandActor actor;
  bool _active = true;

  void _check() {
    if (!_active) throw const OperationFailure(FailureCode.conflict);
    _gate._checkNow(actor);
  }

  /// Receipt lookup is authorized before reading and intentionally has no entity
  /// fence: a committed replay must not repeat/require a consumed trust nonce.
  T read<T>(T Function() reader) {
    _check();
    return reader();
  }

  /// Synchronous linearization boundary. Call INSIDE writeTxnSync immediately
  /// before mutation/receipt, or immediately before socket.write admission.
  /// Never wrap WorkspaceStore.write/Future/network waits in this callback.
  T linearize<T extends PublicValue>(
    T Function() effect, {
    VersionFence? fence,
  }) {
    _check();
    if (fence != null) fence.check(_gate._state.versions(fence.profileId));
    return effect();
  }
}

final class _CommandOutcome<T> {
  const _CommandOutcome.success(this.value, this.meta) : error = null;
  const _CommandOutcome.failure(this.error) : value = null, meta = null;
  final T? value;
  final OperationMeta? meta;
  final OperationFailure? error;
}
