import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/src/ssh_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/connections/connection_owner.dart';
import 'package:serverdeck/connections/host_signature.dart';
import 'package:serverdeck/connections/owned_dial.dart';
import 'package:serverdeck/connections/private_signer.dart';
import 'package:serverdeck/connections/ssh_transport.dart';
import 'package:serverdeck/domain/actor.dart';
import 'package:serverdeck/domain/app_operations.dart';
import 'package:serverdeck/domain/canonical_state.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/profiles/credential_input.dart';
import 'package:serverdeck/storage/records.dart';
import 'package:serverdeck/runtime/owned_work.dart';
import 'package:serverdeck/monitoring/linux_metrics.dart';

import '../fixtures/domain_repository.dart';

String id(int n) =>
    '${n.toRadixString(16).padLeft(8, '0')}-0000-4000-8000-000000000000';
Future<void> turns([int count = 8]) async {
  for (var i = 0; i < count; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Matcher failure(FailureCode code) =>
    isA<OperationFailure>().having((e) => e.code, 'code', code);
HostObservation observation() {
  final writer = SSHMessageWriter()
    ..writeUtf8('ssh-ed25519')
    ..writeString(Uint8List(32));
  return HostObservation.fromVerifiedBlob('ssh-ed25519', writer.takeBytes());
}

final class Deadline {
  Deadline(this.at, this.callback);
  final Duration at;
  final void Function() callback;
  bool cancelled = false;
}

final class Clock {
  Duration current = Duration.zero;
  final timers = <Deadline>[];
  Duration now() => current;
  void Function() schedule(Duration d, void Function() callback) {
    final timer = Deadline(current + d, callback);
    timers.add(timer);
    return () => timer.cancelled = true;
  }

  void advance(Duration d) {
    current += d;
    while (true) {
      final due = timers.where((t) => !t.cancelled && t.at <= current).toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      if (due.isEmpty) return;
      due.first.cancelled = true;
      due.first.callback();
    }
  }
}

final class Dial extends Fake implements SshDialTask {
  Dial() {
    result.future.ignore();
  }
  final result = Completer<SSHSocket>();
  int cancels = 0;
  @override
  Future<SSHSocket> get socket => result.future;
  @override
  void cancel() {
    cancels++;
    if (!result.isCompleted) result.completeError(const WorkCancelled());
  }
}

final class Raw extends Fake implements SSHSocket {
  final doneValue = Completer<void>();
  int closes = 0, destroys = 0;
  @override
  Future<void> get done => doneValue.future;
  @override
  Future<void> close() async {
    closes++;
    if (!doneValue.isCompleted) doneValue.complete();
  }

  @override
  void destroy() {
    destroys++;
  }
}

final class Session implements SshConnection, MonitoringSshConnection {
  Session(this.options) {
    auth.future.ignore();
  }
  final ConnectionTransportOptions options;
  final auth = Completer<void>(), terminal = Completer<OperationFailure?>();
  bool closed = false, failClose = false;
  Completer<void>? holdClose, holdPing;
  int closes = 0, pings = 0, collections = 0;
  Completer<LinuxSample>? collection;
  WorkCancellation? collectionCancellation;
  @override
  Future<LinuxSample> collectMonitoring(
    WorkCancellation cancellation, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    collections++;
    collectionCancellation = cancellation;
    return collection?.future ??
        Future.value(const LinuxSample(memoryPercent: 25, diskPercent: 50));
  }

  @override
  Future<void> get authenticated => auth.future;
  @override
  Future<OperationFailure?> get ended => terminal.future;
  @override
  bool get isClosed => closed;
  Future<void> authenticate() async {
    try {
      if (!await options.verifyHost(observation()))
        throw const OperationFailure(FailureCode.trustRequired);
      options.checkAuthentication();
      if (!auth.isCompleted) auth.complete();
    } catch (error) {
      if (!auth.isCompleted) auth.completeError(error);
    }
  }

  Future<void> write(void Function() effect) => options.admitWrite(effect);
  @override
  Future<void> ping() async {
    pings++;
    await write(() {});
    await holdPing?.future;
  }

  @override
  Future<void> close() async {
    closes++;
    closed = true;
    if (!auth.isCompleted) auth.completeError(const WorkCancelled());
    if (!terminal.isCompleted) terminal.complete(null);
    if (holdPing != null && !holdPing!.isCompleted)
      holdPing!.completeError(const WorkCancelled());
    if (failClose) throw StateError('SYNTHETIC_CLOSE_FAILURE');
    await holdClose?.future;
  }
}

final class Grants implements CanonicalGrantAuthorization {
  bool revoked = false;
  @override
  Future<void> authorize(McpActor a, AuthorizationPoint point) async {
    isAuthorizedNow(a);
  }

  @override
  bool isAuthorizedNow(McpActor a) {
    if (revoked) throw const OperationFailure(FailureCode.accessRevoked);
    return true;
  }
}

final class State implements OperationState {
  State(this.canonical);
  final CanonicalOperationState canonical;
  Future<void> Function(CommandActor, AuthorizationPoint)? before;
  @override
  String get ownerEpoch => canonical.ownerEpoch;
  @override
  bool get running => canonical.running;
  @override
  int get dataRevision => canonical.dataRevision;
  @override
  EntityVersions? versions(String id) => canonical.versions(id);
  @override
  bool isAuthorizedNow(CommandActor a) => canonical.isAuthorizedNow(a);
  @override
  Future<void> authorize(CommandActor a, AuthorizationPoint p) async {
    await before?.call(a, p);
    await canonical.authorize(a, p);
  }
}

final class Policy implements ConnectionTrustPolicy {
  Policy(this.h);
  final Harness h;
  bool wait = false, reject = false;
  ConnectionProof? proof;
  final current = <String, TrustChallenge>{};
  @override
  TrustChallenge? challenge(String profileId) => current[profileId];
  @override
  TrustView view(String id, EndpointTrust e) => TrustView(
    trustRevision: e.trustRevision,
    observationRevision: e.observationRevision,
    changed: e.changed,
    acceptedFingerprint: e.acceptedFingerprint,
    keyType: e.acceptedType,
    observedFingerprint: e.observedFingerprint,
    observedKeyType: e.observedType,
    detectedAt: e.detectedAt,
    challenge: challenge(id),
  );
  @override
  void invalidate(String profileId, String attemptId) =>
      current.remove(profileId);
  @override
  Future<bool> verify(ConnectionProof p, HostObservation o) async {
    proof = p;
    if (reject) return false;
    if (wait) {
      final input = await h.gate.prepare(p.actor, (ctx) {
        final v = h.state.versions(p.profileId)!;
        current[p.profileId] = TrustChallenge(
          kind: TrustKind.first,
          nonce: id(999),
          attemptId: p.attemptId,
          endpointId: p.endpointId,
          profileRevision: v.profileRevision,
          trustRevision: v.trustRevision,
          observationRevision: v.observationRevision,
          fingerprint: o.fingerprint,
          expiresAt: h.utc() + 300000,
          host: 'host.invalid',
          port: 22,
          keyType: o.keyType,
        );
        return h.owner.beginTrustWait(ctx, p);
      });
      return input.result;
    }
    await h.gate.prepare(p.actor, (ctx) {
      h.owner.allowAuthentication(ctx, p, o);
    });
    return true;
  }

  Future<void> accept() async {
    final p = proof!;
    final o = observation();
    await h.gate.prepare(h.actors.ui, (ctx) async {
      await h.repository.write(
        (tx) => ctx.linearize(() {
          final e = tx.endpoint(p.endpointId)!;
          e.acceptedKeyBytes = List.of(o.blob);
          e.acceptedType = o.keyType;
          e.acceptedFingerprint = o.fingerprint;
          e.trustRevision++;
          tx.putEndpoint(e);
          return const MutationValue(entityId: 'synthetic', revision: 2);
        }),
      );
      h.owner.allowAuthentication(ctx, p, o);
    });
  }

  @override
  Future<void> changed(ConnectionProof p, HostObservation o) async {
    final batch = await h.gate.prepare(
      p.actor,
      (ctx) => h.owner.invalidateEndpoint(ctx, p.endpointId),
    );
    await batch.close();
  }
}

final class Harness {
  Harness({this.autoDial = true}) {
    policy = Policy(this);
    owner = ConnectionOwner(
      actors: actors,
      repository: repository,
      getGate: () => gate,
      getState: () => state,
      getTrust: () => policy,
      unprotect: (bytes, purpose) async {
        decrypts++;
        purposes.add(purpose);
        return await (decrypt?.call(bytes) ??
            Future.value(Uint8List.fromList(bytes)));
      },
      verifier: verifier,
      signer: signer,
      newId: () => id(++sequence),
      utcNow: utc,
      monotonicNow: clock.now,
      schedule: clock.schedule,
      beginDial: (host, port) async {
        final d = Dial();
        dials.add(d);
        if (autoDial) {
          final raw = Raw();
          raws.add(raw);
          d.result.complete(raw);
        }
        return d;
      },
      createTransport: (socket, options) {
        final s = Session(options);
        sessions.add(s);
        return s;
      },
    );
    state = State(
      CanonicalOperationState(
        actors: actors,
        repository: repository,
        isRunning: () => running,
        grants: grants,
        connections: owner,
      ),
    );
    gate = DomainCommandGate(actors: actors, state: state);
    seed(1);
  }
  final repository = MemoryDomainRepository(), actors = ActorAuthority(id(900));
  final verifier = HostSignatureVerifier(),
      signer = PrivateSigner(),
      grants = Grants(),
      clock = Clock();
  late final ConnectionOwner owner;
  late final DomainCommandGate gate;
  late final State state;
  late final Policy policy;
  final bool autoDial;
  bool running = true;
  int sequence = 1000, decrypts = 0;
  final dials = <Dial>[],
      raws = <Raw>[],
      sessions = <Session>[],
      purposes = <String>[];
  Future<Uint8List> Function(Uint8List)? decrypt;
  int utc() => 1700000000000 + clock.current.inMilliseconds;
  McpActor get mcp => actors.mcp(clientId: id(800), grantVersion: 1);
  String seed(int n, {bool accepted = true, String host = 'host.invalid'}) {
    final pid = id(n), cid = id(n + 100), o = observation();
    final fields = validateProfileValues(
      displayName: 'Host$n',
      host: host,
      port: 22,
      username: 'root',
    );
    repository.state.profiles[pid] = Profile()
      ..profileId = pid
      ..credentialId = cid
      ..endpointId = fields.endpointId
      ..normalizedHost = host
      ..originalHost = host
      ..username = 'root';
    repository.state.credentials[cid] = Credential()
      ..credentialId = cid
      ..profileId = pid
      ..protectedBytes = List.of(utf8.encode('synthetic-password'));
    final e = repository.state.endpoints.putIfAbsent(
      fields.endpointId,
      () => EndpointTrust()
        ..endpointId = fields.endpointId
        ..normalizedHost = host,
    );
    e.profileRefCount++;
    if (accepted) {
      e.acceptedKeyBytes = List.of(o.blob);
      e.acceptedType = o.keyType;
      e.acceptedFingerprint = o.fingerprint;
    }
    return pid;
  }

  Future<OperationResult<ConnectionView>> connect({
    Actor? actor,
    String? profile,
  }) =>
      owner.connect(actor ?? actors.ui, profile ?? id(1), expectedRevision: 1);
  Future<Session> ready({Actor? actor, String? profile}) async {
    final r = await connect(actor: actor, profile: profile);
    expect(r.ok, isTrue);
    await turns();
    return sessions.last;
  }

  Future<Session> connected({Actor? actor, String? profile}) async {
    final s = await ready(actor: actor, profile: profile);
    await s.authenticate();
    await turns();
    expect(owner.connection(profile ?? id(1)).state, ConnectionState.connected);
    return s;
  }

  Future<void> dispose() async {
    for (final s in sessions) {
      s.failClose = false;
      if (s.holdClose != null && !s.holdClose!.isCompleted)
        s.holdClose!.complete();
    }
    for (final d in dials) {
      if (!d.result.isCompleted) d.result.completeError(const WorkCancelled());
    }
    await owner.dispose();
    gate.stopAdmission();
    await gate.drain();
    await verifier.dispose();
    await signer.dispose();
  }
}

void main() {
  test('rename leaves established binding and socket write usable', () async {
    final h = Harness();
    try {
      final s = await h.connected();
      final before = h.owner.connection(id(1)).sessionId;
      await h.gate.prepare(
        h.actors.ui,
        (ctx) => h.repository.write(
          (tx) => ctx.linearize(() {
            final p = tx.profile(id(1))!;
            p.displayName = 'Renamed';
            p.profileRevision++;
            tx.putProfile(p);
            return const MutationValue(entityId: 'synthetic', revision: 2);
          }),
        ),
      );
      var writes = 0;
      await s.write(() => writes++);
      expect(writes, 1);
      expect(s.closes, 0);
      expect(h.owner.connection(id(1)).state, ConnectionState.connected);
      expect(h.owner.connection(id(1)).sessionId, before);
    } finally {
      await h.dispose();
    }
  });
  for (final quarantineNew in [false, true]) {
    test(
      'moved profile uses canonical endpoint quarantine new=$quarantineNew and rejects old session cleanup',
      () async {
        final h = Harness();
        h.seed(2, host: 'new.invalid');
        h.seed(3);
        try {
          await h.connected();
          final oldSession = h.owner.connection(id(1)).sessionId!;
          final newEndpointSession = await h.connected(profile: id(2));
          final oldEndpointSession = await h.connected(profile: id(3));
          final closed = await h.owner.closeForMutation(h.actors.ui, id(1), 1);
          await h.gate.prepare(
            h.actors.ui,
            (ctx) => h.repository.write(
              (tx) => ctx.linearize(() {
                final p = tx.profile(id(1))!, target = tx.profile(id(2))!;
                final old = tx.endpoint(p.endpointId)!,
                    next = tx.endpoint(target.endpointId)!;
                old.profileRefCount--;
                next.profileRefCount++;
                tx.putEndpoint(old);
                tx.putEndpoint(next);
                p.endpointId = target.endpointId;
                p.originalHost = target.originalHost;
                p.normalizedHost = target.normalizedHost;
                p.connectionRevision++;
                p.profileRevision++;
                tx.putProfile(p);
                return const MutationValue(entityId: 'synthetic', revision: 2);
              }, fence: closed.fence),
            ),
          );
          final affected = quarantineNew
              ? newEndpointSession
              : oldEndpointSession;
          final affectedId = quarantineNew ? id(2) : id(3);
          affected.failClose = true;
          await h.owner.disconnect(
            h.actors.ui,
            affectedId,
            sessionId: h.owner.connection(affectedId).sessionId!,
          );
          await turns();
          final moved = (await h.owner.getConnection(
            h.actors.ui,
            id(1),
          )).value!;
          expect(
            moved.state,
            quarantineNew
                ? ConnectionState.failed
                : ConnectionState.disconnected,
          );
          expect(
            moved.failureCode,
            quarantineNew ? FailureCode.cleanupRequired : null,
          );
          expect(moved.sessionId, isNull);
          expect(moved.attemptId, isNull);
          final closeCount = affected.closes;
          expect(
            (await h.owner.disconnect(
              h.actors.ui,
              id(1),
              sessionId: oldSession,
            )).error!.code,
            FailureCode.conflict,
          );
          expect(affected.closes, closeCount);
        } finally {
          await h.dispose();
        }
      },
    );
  }
  test('connected projection requires live handle even before delayed ended notification', () async {
    final h = Harness();
    try {
      final s = await h.connected();
      s.closed = true;
      final view = (await h.owner.getConnection(h.actors.ui, id(1))).value!;
      expect(view.state, ConnectionState.disconnected);
      expect(view.failureCode, FailureCode.networkError);
    } finally {
      await h.dispose();
    }
  });
  test(
    'blackholed watchdog ping closes session at fifteen plus ten seconds',
    () async {
      final h = Harness();
      try {
        final s = await h.connected();
        s.holdPing = Completer<void>();
        h.clock.advance(const Duration(seconds: 15));
        await turns();
        expect(s.pings, 1);
        h.clock.advance(const Duration(seconds: 9));
        await turns();
        expect(h.owner.connection(id(1)).state, ConnectionState.connected);
        h.clock.advance(const Duration(seconds: 1));
        await turns();
        expect(h.owner.connection(id(1)).failureCode, FailureCode.networkError);
        expect(h.owner.connection(id(1)).state, ConnectionState.disconnected);
        expect(h.owner.liveResources, 0);
        expect(h.dials, hasLength(1));
      } finally {
        await h.dispose();
      }
    },
  );
  test('deadline invalidates and closes even while the common command gate is busy', () async {
    final h = Harness(),
        entered = Completer<void>(),
        release = Completer<void>();
    try {
      final s = await h.ready();
      final old = h.owner.generation(id(1));
      final blocking = h.gate.prepare(h.actors.ui, (_) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      var writes = 0;
      final queued = expectLater(
        s.write(() => writes++),
        throwsA(isA<OperationFailure>()),
      );
      h.clock.advance(const Duration(seconds: 30));
      await turns();
      expect(h.owner.generation(id(1)), greaterThan(old));
      expect(s.closes, greaterThan(0));
      expect(writes, 0);
      release.complete();
      await blocking;
      await queued;
      expect(h.owner.connection(id(1)).failureCode, FailureCode.timeout);
    } finally {
      if (!release.isCompleted) release.complete();
      await h.dispose();
    }
  });
  test(
    'a timed-out failed cleanup retry changes retained attempt to cancelled',
    () async {
      final h = Harness();
      try {
        final s = await h.ready();
        s.failClose = true;
        final attempt = h.owner.connection(id(1)).attemptId!;
        h.clock.advance(const Duration(seconds: 30));
        await turns();
        expect(
          h.owner.connection(id(1)).failureCode,
          FailureCode.cleanupRequired,
        );
        s.failClose = false;
        final retry = await h.owner.cancelConnection(
          h.actors.ui,
          id(1),
          attemptId: attempt,
        );
        expect(retry.ok, isTrue);
        expect(retry.value!.state, ConnectionState.cancelled);
        expect(retry.value!.failureCode, isNull);
      } finally {
        await h.dispose();
      }
    },
  );
  test('quarantine denies every profile of the endpoint and preserves other endpoints', () async {
    final h = Harness();
    h.seed(2);
    h.seed(3, host: 'other.invalid');
    try {
      final first = await h.connected();
      await h.connected(profile: id(2));
      await h.connected(profile: id(3));
      first.failClose = true;
      final sid = h.owner.connection(id(1)).sessionId!;
      await h.owner.disconnect(h.actors.ui, id(1), sessionId: sid);
      await turns();
      expect(
        h.owner.connection(id(2)).failureCode,
        FailureCode.cleanupRequired,
      );
      expect(h.owner.connection(id(3)).state, ConnectionState.connected);
      expect(
        (await h.connect(profile: id(2))).error!.code,
        FailureCode.cleanupRequired,
      );
      first.failClose = false;
      await h.owner.disconnect(h.actors.ui, id(1), sessionId: sid);
      await turns();
      expect(h.owner.connection(id(2)).state, ConnectionState.disconnected);
      expect(h.owner.connection(id(3)).state, ConnectionState.connected);
    } finally {
      await h.dispose();
    }
  });
  test('connect is explicit, repeated pending and connected calls keep exact IDs and one resource', () async {
    final h = Harness();
    try {
      expect(h.owner.connection(id(1)).state, ConnectionState.disconnected);
      expect(h.dials, isEmpty);
      final first = await h.connect();
      expect(first.value!.state, ConnectionState.connecting);
      final again = await h.connect();
      expect(again.value!.attemptId, first.value!.attemptId);
      await turns();
      expect(h.dials, hasLength(1));
      expect(h.sessions, hasLength(1));
      await h.sessions.single.authenticate();
      await turns();
      final connected = h.owner.connection(id(1));
      expect(connected.state, ConnectionState.connected);
      expect(connected.sessionId, isNotNull);
      expect((await h.connect()).value!.sessionId, connected.sessionId);
      expect(h.purposes, ['credential.v1:${id(101)}']);
      expect(h.owner.liveResources, 1);
    } finally {
      await h.dispose();
    }
  });
  test(
    'trust port cannot authorize a key missing from canonical accepted record',
    () async {
      final h = Harness();
      h.repository.state.endpoints.values.single.acceptedKeyBytes = null;
      try {
        final s = await h.ready();
        await s.authenticate();
        await turns();
        expect(
          h.owner.connection(id(1)).failureCode,
          FailureCode.trustRequired,
        );
        expect(h.owner.liveResources, 0);
      } finally {
        await h.dispose();
      }
    },
  );
  test('first trust waits without auth and durable acceptance resumes same attempt', () async {
    final h = Harness();
    h.policy.wait = true;
    h.repository.state.endpoints.values.single.acceptedKeyBytes = null;
    try {
      final s = await h.ready();
      final auth = s.authenticate();
      await turns();
      final pending = h.owner.connection(id(1));
      expect(pending.state, ConnectionState.needTrust);
      expect(pending.challenge, isNotNull);
      expect(s.auth.isCompleted, isFalse);
      h.clock.advance(const Duration(minutes: 4));
      expect(h.owner.connection(id(1)).state, ConnectionState.needTrust);
      await h.policy.accept();
      await auth;
      await turns();
      expect(h.owner.connection(id(1)).attemptId, pending.attemptId);
      expect(h.owner.connection(id(1)).state, ConnectionState.connected);
    } finally {
      await h.dispose();
    }
  });
  test(
    'passphrase uses current nonce once and resumes active budget',
    () async {
      final h = Harness();
      try {
        final s = await h.ready();
        await s.options.verifyHost(observation());
        final phrase = s.options.requestPassphrase();
        await turns();
        final input = h.owner.connection(id(1)).pendingInput!;
        expect(h.owner.connection(id(1)).state, ConnectionState.needPassphrase);
        h.clock.advance(const Duration(minutes: 4));
        final provided = await h.owner.providePassphrase(
          h.actors.ui,
          id(1),
          attemptId: input.attemptId,
          nonce: input.nonce,
          passphrase: ' exact phrase ',
        );
        expect(provided.ok, isTrue);
        expect(await phrase, ' exact phrase ');
        expect(
          (await h.owner.providePassphrase(
            h.actors.ui,
            id(1),
            attemptId: input.attemptId,
            nonce: input.nonce,
            passphrase: 'again',
          )).error!.code,
          FailureCode.conflict,
        );
        h.clock.advance(const Duration(seconds: 30));
        await turns();
        expect(h.owner.connection(id(1)).failureCode, FailureCode.timeout);
      } finally {
        await h.dispose();
      }
    },
  );
  test(
    'prompt deadline rejects late phrase without auth or resurrection',
    () async {
      final h = Harness();
      try {
        final s = await h.ready();
        await s.options.verifyHost(observation());
        final result = expectLater(
          s.options.requestPassphrase(),
          throwsA(isA<WorkCancelled>()),
        );
        await turns();
        final input = h.owner.connection(id(1)).pendingInput!;
        h.clock.advance(const Duration(minutes: 5));
        await result;
        await turns();
        expect(h.owner.connection(id(1)).failureCode, FailureCode.timeout);
        expect(s.auth.isCompleted, isTrue);
        expect(
          (await h.owner.providePassphrase(
            h.actors.ui,
            id(1),
            attemptId: input.attemptId,
            nonce: input.nonce,
            passphrase: 'late',
          )).ok,
          isFalse,
        );
      } finally {
        await h.dispose();
      }
    },
  );
  test('late successful auth at expired undelivered deadline cannot publish connected', () async {
    final h = Harness();
    try {
      final s = await h.ready();
      await s.options.verifyHost(observation());
      h.clock.current = const Duration(seconds: 30);
      s.auth.complete();
      await turns();
      expect(h.owner.connection(id(1)).state, ConnectionState.failed);
      expect(h.owner.connection(id(1)).failureCode, FailureCode.timeout);
      expect(h.owner.liveResources, 0);
    } finally {
      await h.dispose();
    }
  });
  test('cancel invalidates before close; late success and stale ID cannot affect new attempt', () async {
    final h = Harness();
    try {
      final s = await h.ready();
      final first = h.owner.connection(id(1));
      final gen = h.owner.generation(id(1));
      final cancelled = await h.owner.cancelConnection(
        h.actors.ui,
        id(1),
        attemptId: first.attemptId!,
      );
      expect(cancelled.ok, isTrue);
      expect(h.owner.generation(id(1)), greaterThan(gen));
      expect(h.owner.connection(id(1)).state, ConnectionState.cancelled);
      await s.authenticate();
      await turns();
      expect(h.owner.connection(id(1)).state, ConnectionState.cancelled);
      final next = await h.connect();
      expect(next.value!.attemptId, isNot(first.attemptId));
      expect(
        (await h.owner.cancelConnection(
          h.actors.ui,
          id(1),
          attemptId: first.attemptId!,
        )).error!.code,
        FailureCode.conflict,
      );
    } finally {
      await h.dispose();
    }
  });
  test(
    'disconnect addresses exact session and remains idempotent after cleanup',
    () async {
      final h = Harness();
      try {
        await h.connected();
        final session = h.owner.connection(id(1)).sessionId!;
        expect(
          (await h.owner.disconnect(
            h.actors.ui,
            id(1),
            sessionId: id(777),
          )).error!.code,
          FailureCode.conflict,
        );
        expect(
          (await h.owner.disconnect(h.actors.ui, id(1), sessionId: session)).ok,
          isTrue,
        );
        expect(
          (await h.owner.disconnect(h.actors.ui, id(1), sessionId: session)).ok,
          isTrue,
        );
        expect(h.owner.connection(id(1)).state, ConnectionState.disconnected);
      } finally {
        await h.dispose();
      }
    },
  );
  test('queued actual write sees revoked current MCP authority before socket effect', () async {
    final h = Harness();
    final release = Completer<void>(), entered = Completer<void>();
    try {
      final s = await h.ready(actor: h.mcp);
      var writes = 0;
      final blocker = h.gate.prepare(h.actors.ui, (_) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final write = expectLater(
        s.write(() => writes++),
        throwsA(failure(FailureCode.accessRevoked)),
      );
      h.grants.revoked = true;
      release.complete();
      await blocker;
      await write;
      expect(writes, 0);
    } finally {
      if (!release.isCompleted) release.complete();
      await h.dispose();
    }
  });
  test(
    'established app-owned session survives initiating grant revoke',
    () async {
      final h = Harness();
      try {
        final s = await h.connected(actor: h.mcp);
        h.grants.revoked = true;
        await h.owner.cancelPendingClient(id(800));
        var writes = 0;
        await s.write(() => writes++);
        expect(writes, 1);
        expect(h.owner.connection(id(1)).state, ConnectionState.connected);
        expect(h.owner.liveResources, 1);
      } finally {
        await h.dispose();
      }
    },
  );
  test(
    'pending grant revoke cancels only pending attempts and blocks late writes',
    () async {
      final h = Harness();
      try {
        final s = await h.ready(actor: h.mcp);
        h.grants.revoked = true;
        await h.owner.cancelPendingClient(id(800));
        await expectLater(
          s.write(() => fail('must not write')),
          throwsA(isA<OperationFailure>()),
        );
        expect(h.owner.connection(id(1)).state, ConnectionState.cancelled);
        expect(h.owner.liveResources, 0);
      } finally {
        await h.dispose();
      }
    },
  );
  test('failed close quarantines endpoint, retains quota, explicit retry uses same handle', () async {
    final h = Harness();
    try {
      final s = await h.connected();
      s.failClose = true;
      final session = h.owner.connection(id(1)).sessionId!;
      final result = await h.owner.disconnect(
        h.actors.ui,
        id(1),
        sessionId: session,
      );
      expect(result.error!.code, FailureCode.cleanupRequired);
      expect(result.error!.retryable, isTrue);
      final endpoint = h.repository.state.profiles[id(1)]!.endpointId;
      expect(h.owner.isQuarantined(endpoint), isTrue);
      expect(h.owner.liveResources, 1);
      expect((await h.connect()).error!.code, FailureCode.cleanupRequired);
      expect((await h.owner.getConnection(h.actors.ui, id(1))).ok, isTrue);
      s.failClose = false;
      expect(
        (await h.owner.disconnect(h.actors.ui, id(1), sessionId: session)).ok,
        isTrue,
      );
      expect(h.owner.isQuarantined(endpoint), isFalse);
      expect(h.owner.liveResources, 0);
      expect(h.dials, hasLength(1));
    } finally {
      await h.dispose();
    }
  });
  test('cleanup deadline retains pending closure until acknowledgment and allows retry', () async {
    final h = Harness();
    try {
      final s = await h.connected();
      s.holdClose = Completer<void>();
      final session = h.owner.connection(id(1)).sessionId!;
      final closing = h.owner.disconnect(
        h.actors.ui,
        id(1),
        sessionId: session,
      );
      await turns();
      h.clock.advance(const Duration(seconds: 5));
      final failed = await closing;
      expect(failed.error!.code, FailureCode.cleanupRequired);
      expect(h.owner.liveResources, 1);
      final count = s.closes;
      s.holdClose!.complete();
      await turns();
      expect(h.owner.liveResources, 0);
      expect(s.closes, count);
      expect(
        (await h.owner.disconnect(h.actors.ui, id(1), sessionId: session)).ok,
        isTrue,
      );
    } finally {
      await h.dispose();
    }
  });
  test('profile mutation replay precedes entity/revision validation and performs no close', () async {
    final h = Harness();
    try {
      final s = await h.connected();
      const replay = MutationValue(
        entityId: 'committed-id',
        revision: 2,
        replayed: true,
      );
      final outcome = await h.owner.closeForMutation(
        h.actors.ui,
        id(1),
        999,
        findReplay: (_) => replay,
      );
      expect(outcome.replay, same(replay));
      expect(s.closes, 0);
      expect(h.owner.connection(id(1)).state, ConnectionState.connected);
    } finally {
      await h.dispose();
    }
  });
  test('profile mutation close returns new generation fence and committed replay can win post-close', () async {
    final h = Harness();
    try {
      await h.connected();
      var lookups = 0;
      final outcome = await h.owner.closeForMutation(
        h.actors.ui,
        id(1),
        1,
        findReplay: (_) {
          lookups++;
          return lookups == 2
              ? const MutationValue(
                  entityId: 'committed',
                  revision: 2,
                  replayed: true,
                )
              : null;
        },
      );
      expect(outcome.replay!.replayed, isTrue);
      expect(lookups, 2);
      expect(h.owner.liveResources, 0);
      final closed = await h.owner.closeForMutation(h.actors.ui, id(1), 1);
      expect(closed.fence!.attemptGeneration, h.owner.generation(id(1)));
    } finally {
      await h.dispose();
    }
  });
  test('watchdog waits fifteen seconds and lost reply maps network failure without reconnect', () async {
    final h = Harness();
    try {
      final s = await h.connected();
      h.clock.advance(const Duration(seconds: 15));
      await turns();
      expect(s.pings, 1);
      expect(h.owner.connection(id(1)).state, ConnectionState.connected);
      s.terminal.complete(const OperationFailure(FailureCode.networkError));
      await turns();
      expect(h.owner.connection(id(1)).failureCode, FailureCode.networkError);
      expect(h.owner.connection(id(1)).state, ConnectionState.disconnected);
      expect(h.dials, hasLength(1));
      expect(h.owner.liveResources, 0);
    } finally {
      await h.dispose();
    }
  });
  test(
    'timeout cancels pending dial immediately while unprotect is still owned',
    () async {
      final h = Harness(autoDial: false);
      final plain = Completer<Uint8List>();
      h.decrypt = (_) => plain.future;
      try {
        await h.connect();
        await turns();
        h.clock.advance(const Duration(seconds: 30));
        await turns();
        expect(h.dials.single.cancels, 1);
        expect(h.owner.liveResources, 1);
        final late = Uint8List.fromList(utf8.encode('synthetic-password'));
        plain.complete(late);
        await turns();
        expect(late.every((b) => b == 0), isTrue);
        expect(h.owner.liveResources, 0);
        expect(h.sessions, isEmpty);
      } finally {
        if (!plain.isCompleted) plain.complete(Uint8List.fromList([1]));
        await h.dispose();
      }
    },
  );
  test(
    'shutdown closes resources after global operations gate already stopped',
    () async {
      final h = Harness();
      await h.connected();
      h.running = false;
      await h.owner.dispose();
      expect(h.owner.liveResources, 0);
      h.gate.stopAdmission();
      await h.gate.drain();
      await h.verifier.dispose();
      await h.signer.dispose();
    },
  );
  test('64 live limit includes pending dials; another connect is rejected without eviction', () async {
    final h = Harness(autoDial: false);
    try {
      for (var n = 2; n <= 65; n++) {
        h.seed(n);
      }
      for (var n = 1; n <= 64; n++) {
        expect((await h.connect(profile: id(n))).ok, isTrue);
      }
      expect(
        (await h.connect(profile: id(65))).error!.code,
        FailureCode.resourceExhausted,
      );
      expect(h.owner.liveResources, 64);
      expect(h.dials, hasLength(64));
    } finally {
      await h.dispose();
    }
  });
}
