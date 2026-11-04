import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../domain/actor.dart';
import '../domain/app_operations.dart';
import '../domain/models.dart';
import '../profiles/key_envelope.dart';
import '../profiles/profile_owner.dart';
import '../runtime/capability.dart';
import '../runtime/owned_work.dart';
import '../monitoring/linux_metrics.dart';
import '../monitoring/monitoring_job.dart';
import '../monitoring/monitoring_models.dart';
import '../monitoring/monitoring_port.dart';
import '../storage/domain_repository.dart';
import '../storage/records.dart';
import 'host_signature.dart';
import 'network_budget.dart';
import 'owned_dial.dart';
import 'private_signer.dart';
import 'ssh_transport.dart';

/// Real TrustOwner is mandatory. It authorizes/persists with the same gate and
/// calls allowAuthentication/beginTrustWait only in its guarded phases. No default
/// policy accepts hosts; public operations cannot supply this capability.
abstract interface class ConnectionTrustPolicy {
  Future<bool> verify(ConnectionProof proof, HostObservation observation);
  Future<void> changed(ConnectionProof proof, HostObservation observation);
  TrustChallenge? challenge(String profileId);
  TrustView view(String profileId, EndpointTrust endpoint);
  void invalidate(String profileId, String attemptId);
}

final class ConnectionProof {
  ConnectionProof._(this._entry, this.actor, this.generation);
  final _ConnectionEntry _entry;
  final CommandActor actor;
  final int generation;
  String get profileId => _entry.profileId;
  String get attemptId => _entry.attemptId;
  String get endpointId => _entry.endpointId;
  VersionFence get baseFence => VersionFence(
    profileId: profileId,
    connectionRevision: _entry.connectionRevision,
    credentialRevision: _entry.credentialRevision,
    endpointId: endpointId,
    attemptGeneration: generation,
  );
}

/// Carries a wait out of a prepare phase without awaiting it under the gate.
final class TrustInputWait {
  const TrustInputWait(this.result);
  final Future<bool> result;
}

final class ConnectionCleanup {
  ConnectionCleanup._(this._owner, this._entries);
  final ConnectionOwner _owner;
  final List<_ConnectionEntry> _entries;
  Future<void> close() => _owner._closeBatch(_entries);
}

final class ConnectionTransportOptions {
  const ConnectionTransportOptions({
    required this.username,
    required this.credential,
    required this.admitWrite,
    required this.checkAuthentication,
    required this.verifyHost,
    required this.changedHost,
    required this.requestPassphrase,
    required this.remainingBudget,
    required this.cancellation,
  });
  final String username;
  final AttemptCredential credential;
  final AdmitSshWrite admitWrite;
  final void Function() checkAuthentication;
  final Future<bool> Function(HostObservation) verifyHost;
  final Future<void> Function(HostObservation) changedHost;
  final Future<String?> Function() requestPassphrase;
  final Duration Function() remainingBudget;
  final WorkCancellation cancellation;
}

typedef CreateSshConnection = SshConnection Function(
  SSHSocket socket,
  ConnectionTransportOptions options,
);

/// Canonical attempt/session owner. Lazy accessors resolve the root's gate/state/
/// trust construction cycle; runtime must finish that graph before admission.
final class ConnectionOwner
    implements
        ConnectionOperations,
        ProfileConnectionPort,
        RuntimeCapability,
        MonitoringConnectionPort {
  ConnectionOwner({
    required this.actors,
    required this.repository,
    required this.getGate,
    required this.getState,
    required this.getTrust,
    required this.unprotect,
    required this.verifier,
    required this.signer,
    required this.newId,
    required this.utcNow,
    BeginSshDial? beginDial,
    CreateSshConnection? createTransport,
    Duration Function()? monotonicNow,
    ScheduleOwnedDeadline? schedule,
  }) : _beginDial = beginDial,
       _factory = createTransport,
       _now = monotonicNow,
       _schedule = schedule ?? _timer;
  final ActorAuthority actors;
  final DomainRepository repository;
  final DomainCommandGate Function() getGate;
  final OperationState Function() getState;
  final ConnectionTrustPolicy Function() getTrust;
  final Future<Uint8List> Function(Uint8List, String) unprotect;
  final HostSignatureVerifier verifier;
  final PrivateSigner signer;
  final String Function() newId;
  final int Function() utcNow;
  final BeginSshDial? _beginDial;
  final CreateSshConnection? _factory;
  final Duration Function()? _now;
  final ScheduleOwnedDeadline _schedule;
  final _entries = <String, _ConnectionEntry>{}, _generations = <String, int>{};
  final _live = <_ConnectionEntry>{}, _pending = <Future<void>>{};
  final _quarantine = <String, Set<_ConnectionEntry>>{};
  final _changes = StreamController<void>.broadcast();
  final _monitoringJobs = <String, void Function(MonitoringReason)>{};
  bool _stopped = false, _disposed = false;
  static const maxLive = 64, cleanupDuration = Duration(seconds: 5);
  @override
  String get id => 'connections';
  int get liveResources => _live.length;
  Stream<void> get changes => _changes.stream;

  /// Private application capability, absent from AppOperations and MCP schemas.
  /// A caller can cancel before gate admission without waiting for that gate.
  MonitoringJob beginMonitoring(
    UiActor actor,
    String profileId,
    String sessionId, {
    required int expectedConnectionRevision,
    required WorkCancellation cancellation,
  }) {
    MonitoringJob rejected(MonitoringReason reason) =>
        MonitoringJob(Future.value(LinuxSample.failed(reason)), () {});
    if (_stopped) return rejected(MonitoringReason.stopped);
    if (_monitoringJobs.length >= 4 || _monitoringJobs.containsKey(profileId)) {
      return rejected(MonitoringReason.cleanupPending);
    }
    final child = WorkCancellation(), result = Completer<LinuxSample>();
    void fail(MonitoringReason reason) {
      if (!result.isCompleted) result.complete(LinuxSample.failed(reason));
      child.cancel();
    }

    _monitoringJobs[profileId] = fail;
    final elapsed = Stopwatch()..start();
    final startedAt = _now?.call();
    Duration remaining() {
      final used = startedAt == null ? elapsed.elapsed : _now!() - startedAt;
      return const Duration(seconds: 5) -
          (used.isNegative ? Duration.zero : used);
    }

    final unlisten = cancellation.listen(() => fail(MonitoringReason.paused));
    final cancelDeadline = _schedule(
      const Duration(seconds: 5),
      () => fail(MonitoringReason.timeout),
    );
    Future<void> run() async {
      try {
        final sample = await _collectMonitoring(
          actor,
          profileId,
          sessionId,
          expectedConnectionRevision,
          child,
          remaining,
          () => fail(MonitoringReason.disconnected),
        );
        if (!result.isCompleted) result.complete(sample);
      } on WorkCancelled {
        fail(MonitoringReason.paused);
      } on OperationFailure catch (error) {
        fail(
          error.code == FailureCode.shuttingDown
              ? MonitoringReason.stopped
              : MonitoringReason.disconnected,
        );
      } catch (_) {
        fail(MonitoringReason.invalidResponse);
      } finally {
        unlisten();
        cancelDeadline();
        elapsed.stop();
        if (identical(_monitoringJobs[profileId], fail)) {
          _monitoringJobs.remove(profileId);
        }
      }
    }

    _track(run());
    return MonitoringJob(result.future, () => fail(MonitoringReason.paused));
  }

  Future<LinuxSample> _collectMonitoring(
    UiActor actor,
    String profileId,
    String sessionId,
    int expectedRevision,
    WorkCancellation cancellation,
    Duration Function() remaining,
    void Function() disconnected,
  ) async {
    cancellation.check();
    _ConnectionEntry? captured;
    Future<LinuxSample>? pending;
    void Function()? unlistenParent;
    void check(_ConnectionEntry e) {
      cancellation.check();
      _check(e, auth: true);
      if (e.actor is! OwnerActor ||
          e.state != ConnectionState.connected ||
          e.sessionId != sessionId ||
          e.connectionRevision != expectedRevision ||
          (e.transport?.isClosed ?? true)) {
        throw const OperationFailure(FailureCode.conflict);
      }
    }

    try {
      await getGate().prepare(actor, (context) {
        _validateProfile(profileId);
        final e = _entries[profileId];
        if (e == null) throw const OperationFailure(FailureCode.conflict);
        captured = e;
        context.linearize(() {
          check(e);
          final transport = e.transport;
          if (transport is! MonitoringSshConnection) {
            pending = Future.value(
              const LinuxSample.failed(MonitoringReason.sourceUnavailable),
            );
          } else {
            final budget = remaining();
            if (budget <= Duration.zero) {
              pending = Future.value(
                const LinuxSample.failed(MonitoringReason.timeout),
              );
            } else {
              unlistenParent = e.cancellation.listen(disconnected);
              cancellation.check();
              pending = (transport as MonitoringSshConnection)
                  .collectMonitoring(cancellation, timeout: budget);
            }
          }
          pending?.ignore(); // Observe adapter errors even if response auth fails first.
          return _view(e);
        }, fence: e.fence);
      });
      final sample = await pending!;
      return await getGate().prepare(
        actor,
        (context) => context.read(() {
          check(captured!);
          return sample;
        }),
      );
    } finally {
      unlistenParent?.call();
    }
  }

  static void Function() _timer(Duration duration, void Function() callback) {
    final timer = Timer(duration, callback);
    return timer.cancel;
  }

  void _notify() {
    if (!_disposed) _changes.add(null);
  }

  @override
  int generation(String profileId) => _generations[profileId] ?? 0;
  @override
  bool isQuarantined(String endpointId) =>
      _quarantine[endpointId]?.isNotEmpty ?? false;
  @override
  TrustChallenge? challenge(String profileId) =>
      getTrust().challenge(profileId);
  @override
  TrustView trustView(String profileId, EndpointTrust endpoint) =>
      getTrust().view(profileId, endpoint);
  @override
  ConnectionView connection(String profileId) {
    final entry = _entries[profileId];
    if (entry != null) return _view(entry);
    final endpoint = repository.read((r) => r.profile(profileId)?.endpointId);
    return ConnectionView(
      state: endpoint != null && isQuarantined(endpoint)
          ? ConnectionState.failed
          : ConnectionState.disconnected,
      failureCode: endpoint != null && isQuarantined(endpoint)
          ? FailureCode.cleanupRequired
          : null,
    );
  }

  bool _binding(_ConnectionEntry e, EntityVersions v) =>
      e.endpointId == v.endpointId &&
      e.connectionRevision == v.connectionRevision &&
      e.credentialRevision == v.credentialRevision;
  ConnectionView _view(_ConnectionEntry e) {
    final current = getState().versions(e.profileId);
    if (current == null || !_binding(e, current)) {
      final blocked = current != null && isQuarantined(current.endpointId);
      return ConnectionView(
        state: blocked ? ConnectionState.failed : ConnectionState.disconnected,
        failureCode: blocked ? FailureCode.cleanupRequired : null,
      );
    }
    final quarantine = isQuarantined(current.endpointId);
    final lost =
        e.state == ConnectionState.connected && (e.transport?.isClosed ?? true);
    return ConnectionView(
      state: quarantine
          ? ConnectionState.failed
          : lost
          ? ConnectionState.disconnected
          : e.state,
      attemptId: e.attemptId,
      sessionId: e.sessionId,
      failureCode: quarantine
          ? FailureCode.cleanupRequired
          : lost
          ? FailureCode.networkError
          : e.failure,
      challenge: challenge(e.profileId),
      pendingInput: e.input,
    );
  }

  void _pruneTerminalBindings() {
    for (final e in List.of(_entries.values)) {
      if (_live.contains(e)) continue;
      final current = getState().versions(e.profileId);
      if (current == null || !_binding(e, current)) {
        _entries.remove(e.profileId);
        if (current == null) _generations.remove(e.profileId);
      }
    }
  }

  String _id() {
    final value = newId();
    if (!isCanonicalUuid(value))
      throw const OperationFailure(FailureCode.storageUnavailable);
    return value;
  }

  EntityVersions _versions(String id) =>
      getState().versions(id) ??
      (throw const OperationFailure(FailureCode.profileNotFound));
  void _validateProfile(String id) {
    if (!isCanonicalUuid(id))
      throw const OperationFailure(
        FailureCode.invalidArgument,
        field: OperationField.profileId,
      );
    _versions(id);
  }

  void _admit() {
    if (_stopped) throw const OperationFailure(FailureCode.shuttingDown);
  }

  void _check(_ConnectionEntry e, {bool auth = false}) {
    _admit();
    if (e.cancelled ||
        !_live.contains(e) ||
        !identical(_entries[e.profileId], e) ||
        generation(e.profileId) != e.startGeneration)
      throw const OperationFailure(FailureCode.conflict);
    e.fence.check(_versions(e.profileId));
    if (!getState().isAuthorizedNow(e.actor))
      throw const OperationFailure(FailureCode.authRequired);
    if (auth && !e.trusted)
      throw const OperationFailure(FailureCode.trustRequired);
    if (e.sessionId == null && e.budget.remaining <= Duration.zero)
      throw const OperationFailure(FailureCode.timeout);
  }

  void _track(Future<void> future) {
    _pending.add(future);
    future
        .then(
          (_) => _pending.remove(future),
          onError: (Object _, StackTrace __) => _pending.remove(future),
        )
        .ignore();
  }

  int _advance(String id) {
    final old = generation(id);
    if (old >= 9007199254740991)
      throw const OperationFailure(FailureCode.resourceExhausted);
    return _generations[id] = old + 1;
  }

  @override
  Future<OperationResult<ConnectionView>> connect(
    Actor actor,
    String profileId, {
    required int expectedRevision,
  }) => _connect(actor, profileId, expectedRevision: expectedRevision);

  @override
  Future<MonitoringConnectResult> connectForMonitoring(
    UiActor actor,
    String profileId, {
    required int expectedRevision,
    required WorkCancellation cancellation,
  }) async {
    var cancelledBeforeAdmission = false;
    final operation = await _connect(
      actor,
      profileId,
      expectedRevision: expectedRevision,
      autoCancellation: cancellation,
      onAutoCancelled: () => cancelledBeforeAdmission = true,
    );
    return MonitoringConnectResult(
      operation,
      cancelledBeforeAdmission: cancelledBeforeAdmission,
    );
  }

  Future<OperationResult<ConnectionView>> _connect(
    Actor actor,
    String profileId, {
    required int expectedRevision,
    WorkCancellation? autoCancellation,
    void Function()? onAutoCancelled,
  }) async {
    _ConnectionEntry? started;
    final result = await getGate().submit(actor, (context) {
      _admit();
      void checkAuto() {
        if (autoCancellation?.isCancelled ?? false) {
          onAutoCancelled?.call();
          throw const OperationFailure(FailureCode.conflict);
        }
        if (autoCancellation != null && generation(profileId) != 0) {
          throw const OperationFailure(FailureCode.conflict);
        }
      }

      checkAuto();
      if (expectedRevision < 1 || expectedRevision > 9007199254740991)
        throw const OperationFailure(
          FailureCode.invalidArgument,
          field: OperationField.expectedRevision,
        );
      _validateProfile(profileId);
      final versions = _versions(profileId);
      if (versions.profileRevision != expectedRevision)
        throw const OperationFailure(
          FailureCode.conflict,
          field: OperationField.expectedRevision,
        );
      if (isQuarantined(versions.endpointId)) throw _cleanup;
      final old = _entries[profileId];
      if (old != null && _live.contains(old)) return _view(old);
      if (_live.length >= maxLive)
        throw const OperationFailure(
          FailureCode.resourceExhausted,
          retryable: true,
        );
      return context.linearize(
        () {
          checkAuto();
          _pruneTerminalBindings();
          final records = repository.read((r) {
            final p = r.profile(profileId)!;
            final c = r.credential(p.credentialId);
            if (c == null)
              throw const OperationFailure(FailureCode.storageUnavailable);
            return (p, c);
          });
          final e = _ConnectionEntry(
            records.$1,
            records.$2,
            actor,
            _id(),
            _advance(profileId),
          );
          e.budget = NetworkBudget(
            onExpired: (_) =>
                _terminate(e, ConnectionState.failed, FailureCode.timeout),
            now: _now,
            schedule: _schedule,
          );
          _entries[profileId] = e;
          _live.add(e);
          // This dial factory starts inside the actual guarded admission effect.
          e.dial = OwnedSshDial(e.host, e.port, begin: _beginDial);
          started = e;
          _notify();
          return _view(e);
        },
        fence: VersionFence(
          profileId: profileId,
          profileRevision: expectedRevision,
        ),
      );
    });
    if (started != null) _track(_run(started!));
    return result;
  }

  @override
  Future<OperationResult<ConnectionView>> getConnection(
    Actor actor,
    String profileId,
  ) => getGate().submit(
    actor,
    (context) => context.read(() {
      _validateProfile(profileId);
      return connection(profileId);
    }),
  );

  Future<void> _run(_ConnectionEntry e) async {
    Uint8List? plaintext;
    try {
      try {
        _check(e);
        try {
          plaintext = await unprotect(
            e.ciphertext,
            'credential.v1:${e.credentialId}',
          );
        } catch (_) {
          throw const OperationFailure(FailureCode.protectionUnavailable);
        }
        if (plaintext.isEmpty || plaintext.length > 1024 * 1024)
          throw const OperationFailure(FailureCode.protectionUnavailable);
        _check(e);
        final AttemptCredential credential;
        if (e.kind == 'password') {
          credential = PasswordCredential(plaintext);
        } else if (e.kind == 'privateKey') {
          final hint = readPublicKeyHint(plaintext);
          if (hint.inspection.keyType != e.keyType ||
              hint.inspection.bits != e.keyBits)
            throw const OperationFailure(FailureCode.storageUnavailable);
          credential = PrivateKeyCredential(
            plaintext,
            revision: e.credentialRevision,
            inspection: hint.inspection,
          );
        } else {
          throw const OperationFailure(FailureCode.storageUnavailable);
        }
        e.credential = credential;
        await e.dial!.socket;
        await getGate().prepare(
          e.actor,
          (context) => context.linearize(() {
            _check(e);
            e.raw = e.dial!.takeSocket();
            final options = ConnectionTransportOptions(
              username: e.username,
              credential: credential,
              admitWrite: (write) => _write(e, write),
              checkAuthentication: () => _check(e, auth: true),
              verifyHost: (observation) =>
                  getTrust().verify(_proof(e), observation),
              changedHost: (observation) =>
                  getTrust().changed(_proof(e), observation),
              requestPassphrase: () => _requestPhrase(e),
              remainingBudget: () => e.sessionId != null
                  ? NetworkBudget.networkDuration
                  : e.budget.remaining,
              cancellation: e.cancellation,
            );
            e.transport = (_factory ?? _create)(e.raw!, options);
            e.transport!.ended.then((failure) {
              if (!e.cancelled)
                _terminate(
                  e,
                  ConnectionState.failed,
                  failure?.code ?? FailureCode.networkError,
                );
            }).ignore();
            return _view(e);
          }, fence: e.fence),
        );
      } finally {
        plaintext?.fillRange(0, plaintext.length, 0);
        e.ciphertext.fillRange(0, e.ciphertext.length, 0);
        if (!e.prepared.isCompleted) e.prepared.complete();
      }
      final transport = e.transport!;
      await transport.authenticated;
      await getGate().prepare(
        e.actor,
        (context) => context.linearize(() {
          _check(e, auth: true);
          if (transport.isClosed || !e.budget.tryComplete())
            throw const OperationFailure(FailureCode.timeout);
          e.sessionId = _id();
          e.actor = actors.owner;
          e.state = ConnectionState.connected;
          e.failure = null;
          e.watchdog = ConnectionWatchdog(
            ping: transport.ping,
            onFailure: () =>
                _terminate(e, ConnectionState.failed, FailureCode.networkError),
            now: _now,
            schedule: _schedule,
          );
          _notify();
          return _view(e);
        }, fence: e.fence),
      );
    } catch (error) {
      if (!e.cancelled)
        _terminate(e, ConnectionState.failed, sshFailure(error).code);
    }
  }

  SshConnection _create(SSHSocket socket, ConnectionTransportOptions o) =>
      StrictSshTransport(
        socket: socket,
        username: o.username,
        credential: o.credential,
        verifier: verifier,
        signer: signer,
        admitWrite: o.admitWrite,
        checkAuthentication: o.checkAuthentication,
        verifyHost: o.verifyHost,
        changedHost: o.changedHost,
        requestPassphrase: o.requestPassphrase,
        remainingBudget: o.remainingBudget,
        cancellation: o.cancellation,
      );
  Future<void> _write(_ConnectionEntry e, void Function() write) async {
    final actor = e.actor;
    var sent = false;
    Future<void> phase(CommandActor current) =>
        getGate().prepare(current, (context) {
          context.linearize(() {
            _check(e);
            if (!sent) {
              sent = true;
              write();
            }
            return _view(e);
          }, fence: e.fence);
        });
    try {
      await phase(actor);
    } on OperationFailure catch (error) {
      if (actor is! OwnerActor &&
          e.actor is OwnerActor &&
          [
            FailureCode.authRequired,
            FailureCode.accessRevoked,
            FailureCode.grantExpired,
          ].contains(error.code)) {
        // Only private write completion migrates; no MCP result is disclosed.
        await phase(e.actor);
      } else {
        rethrow;
      }
    }
  }

  ConnectionProof _proof(_ConnectionEntry e) {
    _check(e);
    return ConnectionProof._(e, e.actor, generation(e.profileId));
  }

  /// TrustOwner calls this under its authorized gate for a current or retained
  /// terminal observation. This never creates or authenticates a new resource.
  ConnectionProof proofFor(
    CommandContext context,
    String profileId,
    String attemptId, {
    bool allowTerminal = false,
  }) => context.read(() {
    final e = _entries[profileId];
    if (e == null ||
        e.attemptId != attemptId ||
        (!allowTerminal && e.cancelled))
      throw const OperationFailure(FailureCode.conflict);
    return ConnectionProof._(e, e.actor, generation(profileId));
  });
  void checkProof(
    CommandContext context,
    ConnectionProof proof, {
    bool allowTerminal = false,
  }) => context.read(() {
    if (!identical(_entries[proof.profileId], proof._entry) ||
        generation(proof.profileId) != proof.generation ||
        (!allowTerminal && proof._entry.cancelled))
      throw const OperationFailure(FailureCode.conflict);
    proof.baseFence.check(_versions(proof.profileId));
  });
  void allowAuthentication(
    CommandContext context,
    ConnectionProof proof,
    HostObservation observation,
  ) {
    context.linearize(() {
      checkProof(context, proof);
      final e = proof._entry;
      final versions = _versions(e.profileId),
          endpoint = repository.read((r) => r.endpoint(e.endpointId));
      if (endpoint?.acceptedKeyBytes == null ||
          !sameKeyBytes(endpoint!.acceptedKeyBytes!, observation.blob) ||
          endpoint.acceptedType != observation.keyType ||
          endpoint.acceptedFingerprint != observation.fingerprint)
        throw const OperationFailure(FailureCode.trustRequired);
      if (e.trustLease != null && !e.budget.resume(e.trustLease!))
        throw const OperationFailure(FailureCode.timeout);
      e.trustLease = null;
      e.trusted = true;
      e.fence = _fence(e, versions);
      e.state = ConnectionState.authenticating;
      if (!(e.trustWait?.isCompleted ?? true)) e.trustWait!.complete(true);
      e.trustWait = null;
      _notify();
      return _view(e);
    }, fence: proof.baseFence);
  }

  TrustInputWait beginTrustWait(CommandContext context, ConnectionProof proof) {
    late TrustInputWait wait;
    context.linearize(() {
      checkProof(context, proof);
      final e = proof._entry;
      if (e.trustWait != null) {
        wait = TrustInputWait(e.trustWait!.future);
        return _view(e);
      }
      final lease = e.budget.pauseForPrompt(PromptKind.trust);
      if (lease == null) throw const OperationFailure(FailureCode.timeout);
      e.trustLease = lease;
      e.trustWait = Completer<bool>();
      e.state = ConnectionState.needTrust;
      wait = TrustInputWait(e.trustWait!.future);
      _notify();
      return _view(e);
    }, fence: proof.baseFence);
    return wait;
  }

  Future<String?> _requestPhrase(_ConnectionEntry e) async {
    final wait = await getGate().prepare(e.actor, (context) {
      late _PhraseWait result;
      context.linearize(() {
        _check(e, auth: true);
        if (e.phrase != null)
          throw const OperationFailure(FailureCode.conflict);
        final lease = e.budget.pauseForPrompt(PromptKind.passphrase);
        if (lease == null) throw const OperationFailure(FailureCode.timeout);
        e.phraseLease = lease;
        e.phrase = Completer<String?>();
        e.phrase!.future.ignore();
        e.input = PendingInput(
          nonce: _id(),
          attemptId: e.attemptId,
          expiresAt: utcNow() + 300000,
        );
        e.state = ConnectionState.needPassphrase;
        result = _PhraseWait(e.phrase!.future);
        _notify();
        return _view(e);
      }, fence: e.fence);
      return result;
    });
    return wait.result;
  }

  @override
  Future<OperationResult<ConnectionView>> providePassphrase(
    Actor actor,
    String profileId, {
    required String attemptId,
    required String nonce,
    required String passphrase,
  }) => getGate().submit(actor, (context) {
    _validateProfile(profileId);
    final e = _entries[profileId];
    if (e == null ||
        e.attemptId != attemptId ||
        e.input?.nonce != nonce ||
        e.phrase == null ||
        e.phrase!.isCompleted)
      throw const OperationFailure(FailureCode.conflict);
    if (!isKeyPassphraseBounded(passphrase))
      throw const OperationFailure(
        FailureCode.invalidArgument,
        field: OperationField.passphrase,
      );
    return context.linearize(() {
      _check(e, auth: true);
      if (!e.budget.resume(e.phraseLease!))
        throw const OperationFailure(FailureCode.timeout);
      final pending = e.phrase!;
      e.phrase = null;
      e.phraseLease = null;
      e.input = null;
      e.state = ConnectionState.authenticating;
      pending.complete(passphrase);
      _notify();
      return _view(e);
    }, fence: e.fence);
  });
  @override
  Future<OperationResult<ConnectionView>> cancelConnection(
    Actor actor,
    String profileId, {
    required String attemptId,
  }) => _closeCommand(actor, profileId, attemptId, false);
  @override
  Future<OperationResult<ConnectionView>> disconnect(
    Actor actor,
    String profileId, {
    required String sessionId,
  }) => _closeCommand(actor, profileId, sessionId, true);
  Future<OperationResult<ConnectionView>> _closeCommand(
    Actor actor,
    String profileId,
    String target,
    bool session,
  ) async {
    try {
      final batch = await getGate().prepare(actor, (context) {
        _validateProfile(profileId);
        final e = _entries[profileId];
        if (e == null ||
            !_binding(e, _versions(profileId)) ||
            (session ? e.sessionId : e.attemptId) != target ||
            (!session && e.sessionId != null))
          throw const OperationFailure(FailureCode.conflict);
        late ConnectionCleanup batch;
        context.linearize(() {
          final entries = isQuarantined(e.endpointId)
              ? _live.where((v) => v.endpointId == e.endpointId).toList()
              : [e];
          for (final entry in entries) {
            _invalidate(
              entry,
              session
                  ? ConnectionState.disconnected
                  : ConnectionState.cancelled,
              null,
              retarget: true,
            );
          }
          batch = ConnectionCleanup._(this, entries);
          return _view(e);
        });
        return batch;
      });
      await batch.close();
      return await getGate().submit(
        actor,
        (context) => context.read(() {
          _validateProfile(profileId);
          return connection(profileId);
        }),
      );
    } catch (error) {
      return OperationResult.failure(
        error is OperationFailure ? error : _cleanup,
      );
    }
  }

  @override
  Future<ProfileCloseOutcome> closeForMutation(
    Actor actor,
    String profileId,
    int expectedRevision, {
    MutationValue? Function(CommandContext)? findReplay,
  }) async {
    final intent = await getGate().prepare(actor, (context) {
      final replay = findReplay?.call(context);
      if (replay != null)
        return (replay, null as ConnectionCleanup?, null as VersionFence?);
      _validateProfile(profileId);
      final v = _versions(profileId);
      if (v.profileRevision != expectedRevision)
        throw const OperationFailure(FailureCode.conflict);
      if (isQuarantined(v.endpointId)) throw _cleanup;
      late VersionFence fence;
      late ConnectionCleanup batch;
      context.linearize(() {
        final e = _entries[profileId];
        if (e != null)
          _invalidate(e, ConnectionState.disconnected, null, retarget: true);
        fence = VersionFence(
          profileId: profileId,
          profileRevision: expectedRevision,
          connectionRevision: v.connectionRevision,
          credentialRevision: v.credentialRevision,
          endpointId: v.endpointId,
          attemptGeneration: generation(profileId),
        );
        batch = ConnectionCleanup._(this, e == null ? [] : [e]);
        return connection(profileId);
      });
      return (null as MutationValue?, batch, fence);
    });
    if (intent.$1 != null) return ProfileCloseOutcome.replayed(intent.$1!);
    await intent.$2!.close();
    return getGate().prepare(actor, (context) {
      final replay = findReplay?.call(context);
      if (replay != null) return ProfileCloseOutcome.replayed(replay);
      context.read(() => intent.$3!.check(_versions(profileId)));
      return ProfileCloseOutcome.closed(intent.$3!);
    });
  }

  ConnectionCleanup invalidateEndpoint(
    CommandContext context,
    String endpointId, {
    FailureCode reason = FailureCode.hostKeyChanged,
    ConnectionProof? preserve,
  }) {
    late List<_ConnectionEntry> entries;
    context.linearize(() {
      if (preserve != null) checkProof(context, preserve);
      entries = _live
          .where(
            (e) =>
                e.endpointId == endpointId && !identical(e, preserve?._entry),
          )
          .toList();
      for (final e in entries) {
        _invalidate(e, ConnectionState.failed, reason);
      }
      return const ConnectionView(state: ConnectionState.disconnected);
    });
    return ConnectionCleanup._(this, entries);
  }

  /// A warning transaction can fail after its fail-closed endpoint invalidation.
  /// Preserve that storage reason without reviving a cancelled or newer attempt.
  void observedStorageFailure(ConnectionProof proof) {
    final e = proof._entry;
    if (!identical(_entries[e.profileId], e) ||
        e.targetFailure != FailureCode.hostKeyChanged)
      return;
    e.targetState = e.sessionId == null
        ? ConnectionState.failed
        : ConnectionState.disconnected;
    e.targetFailure = FailureCode.storageUnavailable;
    e.state = e.targetState;
    e.failure = e.targetFailure;
    _notify();
  }

  /// Private lifecycle revocation latch, used synchronously by monotonic deadlines
  /// and runtime shutdown even if the product gate is waiting on persistence.
  /// It only invalidates/denies/closes; never commits or authorizes a new effect.
  void _invalidate(
    _ConnectionEntry e,
    ConnectionState state,
    FailureCode? failure, {
    bool retarget = false,
  }) {
    if (!e.cancelled) {
      e.cancelled = true;
      try {
        _advance(e.profileId);
      } on OperationFailure {
        // The denial latch still closes safely when the generation cannot grow.
        state = ConnectionState.failed;
        failure = FailureCode.resourceExhausted;
      }
      e.budget.finish();
      e.watchdog?.stop();
      e.cancellation.cancel();
      e.credential?.dispose();
      if (!(e.trustWait?.isCompleted ?? true)) e.trustWait!.complete(false);
      if (!(e.phrase?.isCompleted ?? true))
        e.phrase!.completeError(const WorkCancelled());
      e.trustWait = null;
      e.phrase = null;
      e.input = null;
      try {
        getTrust().invalidate(e.profileId, e.attemptId);
      } catch (_) {
        /* Generation already revoked. */
      }
      if (e.sessionId != null && state == ConnectionState.failed)
        state = ConnectionState.disconnected;
      e.targetState = state;
      e.targetFailure = failure;
    } else if (retarget) {
      try {
        getTrust().invalidate(e.profileId, e.attemptId);
      } catch (_) {}
      e.targetState = state;
      e.targetFailure = failure;
    }
    e.state = e.targetState;
    e.failure = e.targetFailure;
    _notify();
  }

  void _terminate(
    _ConnectionEntry e,
    ConnectionState state,
    FailureCode? failure,
  ) {
    if (e.cancelled) return;
    _invalidate(e, state, failure);
    _track(_closeBatch([e]).catchError((Object _) {}));
  }

  static const _cleanup = OperationFailure(
    FailureCode.cleanupRequired,
    retryable: true,
    reason: FailureReason.connectionCleanup,
  );
  Future<void> _bounded(Future<void> work) async {
    final result = Completer<void>();
    final cancel = _schedule(cleanupDuration, () {
      if (!result.isCompleted) result.completeError(_cleanup);
    });
    unawaited(
      work.then(
        (_) {
          if (!result.isCompleted) result.complete();
        },
        onError: (Object _, StackTrace __) {
          if (!result.isCompleted) result.completeError(_cleanup);
        },
      ),
    );
    try {
      await result.future;
    } finally {
      cancel();
    }
  }

  Future<void> _closeBatch(List<_ConnectionEntry> entries) async {
    final live = entries.where(_live.contains).toList();
    try {
      await _bounded(Future.wait(live.map(_startClose)));
    } catch (_) {
      for (final e in live.where(_live.contains)) {
        _markQuarantine(e);
      }
      throw _cleanup;
    }
  }

  Future<void> _startClose(_ConnectionEntry e) {
    if (!_live.contains(e)) return Future<void>.value();
    return e.closing ??= _closeExact(e);
  }

  Future<void> _closeExact(_ConnectionEntry e) async {
    try {
      final operations = <Future<void>>[];
      final captured = <Object>{};
      void capture() {
        final dial = e.dial, transport = e.transport, raw = e.raw;
        void add(Object resource, Future<void> Function() close) {
          if (!captured.add(resource)) return;
          final pending = Future<void>.sync(close);
          pending.ignore();
          operations.add(pending);
        }

        if (dial != null) add(dial, dial.close);
        if (transport != null) add(transport, transport.close);
        if (raw != null) add(raw, () => _closeRaw(raw));
      }

      // Cancel known DNS/connect/client immediately, including while DPAPI awaits.
      capture();
      await e.prepared.future;
      capture(); // Retain any exact handle created before the invalidation latch.
      await Future.wait(operations);
      _live.remove(e);
      _quarantine[e.endpointId]?.remove(e);
      if (!isQuarantined(e.endpointId)) _quarantine.remove(e.endpointId);
      e.state = e.targetState;
      e.failure = e.targetFailure;
      _notify();
    } catch (_) {
      _markQuarantine(e);
      throw _cleanup;
    } finally {
      e.closing = null;
    }
  }

  Future<void> _closeRaw(SSHSocket socket) async {
    try {
      socket.destroy();
    } catch (_) {}
    await socket.close();
    final done = socket.done;
    try {
      await done;
    } catch (_) {}
  }

  void _markQuarantine(_ConnectionEntry e) {
    if (!_live.contains(e)) return;
    final affected = _live.where((v) => v.endpointId == e.endpointId).toList();
    final group = _quarantine.putIfAbsent(e.endpointId, () => {});
    for (final entry in affected) {
      final newlyStopped = !entry.cancelled;
      _invalidate(entry, ConnectionState.disconnected, null);
      group.add(entry);
      entry.state = ConnectionState.failed;
      entry.failure = FailureCode.cleanupRequired;
      if (newlyStopped) _startClose(entry).catchError((Object _) {}).ignore();
    }
    _notify();
  }

  VersionFence _fence(_ConnectionEntry e, EntityVersions v) => VersionFence(
    profileId: e.profileId,
    connectionRevision: e.connectionRevision,
    credentialRevision: e.credentialRevision,
    endpointId: e.endpointId,
    trustRevision: v.trustRevision,
    observationRevision: v.observationRevision,
    attemptGeneration: e.startGeneration,
  );

  /// GrantOwner calls after durable revoke/expiry/clock-epoch invalidation.
  Future<void> cancelPendingClient(String clientId) async {
    final entries = _live
        .where(
          (e) =>
              e.actor is McpActor && (e.actor as McpActor).clientId == clientId,
        )
        .toList();
    for (final e in entries) {
      _invalidate(e, ConnectionState.cancelled, FailureCode.accessRevoked);
    }
    await _closeBatch(entries);
  }

  @override
  Future<void> stopAdmission() async {
    _stopped = true;
    for (final cancel in List.of(_monitoringJobs.values)) {
      cancel(MonitoringReason.stopped);
    }
  }

  @override
  Future<void> cancelPending() async {
    final entries = _live.where((e) => e.sessionId == null).toList();
    for (final e in entries) {
      _invalidate(e, ConnectionState.cancelled, FailureCode.shuttingDown);
    }
    await _closeBatch(entries);
  }

  @override
  Future<void> closeSessions() async {
    final entries = List.of(_live);
    for (final e in entries) {
      _invalidate(e, ConnectionState.disconnected, FailureCode.shuttingDown);
    }
    await _closeBatch(entries);
  }

  @override
  Future<void> drain() async {
    while (_pending.isNotEmpty) {
      await Future.wait(List.of(_pending));
    }
  }

  @override
  Future<void> dispose() async {
    await stopAdmission();
    await cancelPending();
    await closeSessions();
    await drain();
    if (!_disposed) {
      _disposed = true;
      await _changes.close();
    }
  }
}

final class _PhraseWait {
  const _PhraseWait(this.result);
  final Future<String?> result;
}

final class _ConnectionEntry {
  _ConnectionEntry(
    Profile p,
    Credential c,
    this.actor,
    this.attemptId,
    this.startGeneration,
  ) : profileId = p.profileId,
      endpointId = p.endpointId,
      host = p.normalizedHost,
      port = p.port,
      username = p.username,
      credentialId = c.credentialId,
      credentialRevision = c.secretRevision,
      connectionRevision = p.connectionRevision,
      kind = c.kind,
      keyType = c.publicKeyType,
      keyBits = c.publicKeyBits,
      ciphertext = Uint8List.fromList(c.protectedBytes),
      fence = VersionFence(
        profileId: p.profileId,
        connectionRevision: p.connectionRevision,
        credentialRevision: c.secretRevision,
        endpointId: p.endpointId,
        attemptGeneration: startGeneration,
      );
  final String profileId,
      endpointId,
      host,
      username,
      credentialId,
      kind,
      attemptId;
  final int port, credentialRevision, connectionRevision, startGeneration;
  final String? keyType;
  final int? keyBits;
  final Uint8List ciphertext;
  CommandActor actor;
  VersionFence fence;
  late NetworkBudget budget;
  OwnedSshDial? dial;
  SSHSocket? raw;
  SshConnection? transport;
  AttemptCredential? credential;
  final cancellation = WorkCancellation(), prepared = Completer<void>();
  ConnectionWatchdog? watchdog;
  ConnectionState state = ConnectionState.connecting,
      targetState = ConnectionState.disconnected;
  FailureCode? failure, targetFailure;
  String? sessionId;
  bool cancelled = false, trusted = false;
  Future<void>? closing;
  BudgetPrompt? trustLease, phraseLease;
  Completer<bool>? trustWait;
  Completer<String?>? phrase;
  PendingInput? input;
}
