import 'dart:async';
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
import 'package:serverdeck/domain/mutation_receipts.dart';
import 'package:serverdeck/domain/owned_app_operations.dart';
import 'package:serverdeck/domain/receipt_book.dart';
import 'package:serverdeck/mcp/grant_owner.dart';
import 'package:serverdeck/profiles/credential_input.dart';
import 'package:serverdeck/profiles/key_parse_worker.dart';
import 'package:serverdeck/profiles/profile_owner.dart';
import 'package:serverdeck/runtime/owned_work.dart';
import 'package:serverdeck/trust/trust_owner.dart';

import 'domain_repository.dart';

String featureId(int n) =>
    '${n.toRadixString(16).padLeft(8, '0')}-0000-4000-8000-000000000000';
Future<void> featureTurns([int count = 12]) async {
  for (var i = 0; i < count; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Matcher featureFailure(FailureCode code) =>
    isA<OperationFailure>().having((e) => e.code, 'code', code);
HostObservation featureKey([int value = 1]) {
  final writer = SSHMessageWriter()
    ..writeUtf8('ssh-ed25519')
    ..writeString(Uint8List.fromList(List.filled(32, value)));
  return HostObservation.fromVerifiedBlob('ssh-ed25519', writer.takeBytes());
}

final class FeatureTimer {
  FeatureTimer(this.at, this.callback);
  final Duration at;
  final void Function() callback;
  bool cancelled = false;
}

final class FeatureClock {
  Duration elapsed = Duration.zero;
  int utc = 1700000000000;
  final timers = <FeatureTimer>[];
  Duration monotonic() => elapsed;
  int now() => utc;
  void Function() schedule(Duration d, void Function() callback) {
    final timer = FeatureTimer(elapsed + d, callback);
    timers.add(timer);
    return () => timer.cancelled = true;
  }

  void advance(Duration d) {
    elapsed += d;
    utc += d.inMilliseconds;
    for (;;) {
      final due = timers.where((t) => !t.cancelled && t.at <= elapsed).toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      if (due.isEmpty) return;
      due.first.cancelled = true;
      due.first.callback();
    }
  }
}

final class FeatureSocket extends Fake implements SSHSocket {
  final _done = Completer<void>();
  int closes = 0;
  @override
  Future<void> get done => _done.future;
  @override
  Future<void> close() async {
    closes++;
    if (!_done.isCompleted) _done.complete();
  }

  @override
  void destroy() {
    if (!_done.isCompleted) _done.complete();
  }
}

final class FeatureDial implements SshDialTask {
  FeatureDial(this.raw);
  final FeatureSocket raw;
  @override
  Future<SSHSocket> get socket => Future.value(raw);
  @override
  void cancel() {
    raw.destroy();
  }
}

final class FeatureSession implements SshConnection {
  FeatureSession(this.options) {
    auth.future.ignore();
  }
  final ConnectionTransportOptions options;
  final auth = Completer<void>(), terminal = Completer<OperationFailure?>();
  bool closed = false, failClose = false, askPassphrase = false;
  int closeCalls = 0;
  Completer<void>? holdClose;
  @override
  Future<void> get authenticated => auth.future;
  @override
  Future<OperationFailure?> get ended => terminal.future;
  @override
  bool get isClosed => closed;
  Future<void> authenticate([HostObservation? key]) async {
    try {
      if (!await options.verifyHost(key ?? featureKey()))
        throw const OperationFailure(FailureCode.hostKeyChanged);
      options.checkAuthentication();
      if (askPassphrase) {
        await options.requestPassphrase();
        options.checkAuthentication();
      }
      if (!auth.isCompleted) auth.complete();
    } catch (error) {
      if (!auth.isCompleted) auth.completeError(error);
    }
  }

  Future<void> rekey(HostObservation key) => options.changedHost(key);
  @override
  Future<void> ping() => options.admitWrite(() {});
  @override
  Future<void> close() async {
    closeCalls++;
    closed = true;
    if (!auth.isCompleted) auth.completeError(const WorkCancelled());
    if (!terminal.isCompleted) terminal.complete(null);
    if (failClose) throw StateError('synthetic close failure');
    await holdClose?.future;
  }
}

final class FeatureProtector implements SecretProtector {
  @override
  Future<Uint8List> protect(Uint8List bytes, String purpose) async =>
      Uint8List.fromList(bytes);
}

final class FeatureGrantTransport implements GrantTransport {
  bool enabled = false, failWrite = false, failClose = false;
  int writes = 0, closes = 0;
  Completer<void>? holdClose;
  final files = <String, (int, Uint8List)>{};
  final closedClients = <String>[],
      failedClients = <String>{},
      heldClients = <String, Completer<void>>{};
  @override
  Future<void> setEnabled(bool value) async {
    enabled = value;
  }

  @override
  Future<void> closeClient(String id) async {
    closes++;
    closedClients.add(id);
    if (failClose || failedClients.contains(id))
      throw StateError('synthetic close failure');
    await heldClients[id]?.future;
    await holdClose?.future;
  }

  @override
  Future<void> writeGrant(String id, int version, Uint8List bytes) async {
    writes++;
    if (failWrite) throw StateError('synthetic export failure');
    files[id] = (version, Uint8List.fromList(bytes));
  }

  @override
  Future<void> deleteGrant(String id) async {
    files.remove(id);
  }
}

/// Actual owners and gate over a detached snapshot repository. Network, native
/// protection, grant files and time are synthetic; no Isar engine or TCP socket.
final class FeatureHarness {
  FeatureHarness({int epoch = 9000, void Function(String)? onClientInvalidated})
    : actors = ActorAuthority(featureId(epoch)) {
    connections = ConnectionOwner(
      actors: actors,
      repository: repository,
      getGate: () => gate,
      getState: () => state,
      getTrust: () => trust,
      unprotect: (bytes, purpose) async => Uint8List.fromList(bytes),
      verifier: verifier,
      signer: privateSigner,
      newId: newId,
      utcNow: clock.now,
      monotonicNow: clock.monotonic,
      schedule: clock.schedule,
      beginDial: (host, port) async => FeatureDial(FeatureSocket()),
      createTransport: (socket, options) {
        final value = FeatureSession(options);
        sessions.add(value);
        return value;
      },
    );
    grants = GrantOwner(
      repository: repository,
      actors: actors,
      getGate: () => gate,
      connections: connections,
      transport: transport,
      protect: (bytes, purpose) async => Uint8List.fromList(bytes),
      unprotect: (bytes, purpose) async => Uint8List.fromList(bytes),
      newId: newId,
      utcNow: clock.now,
      userSid: 'synthetic-user',
      logonSid: 'synthetic-logon',
      exePath: r'C:\fixture\ServerDeck.exe',
      randomSecret: () => Uint8List.fromList(List.filled(32, 7)),
      onClientInvalidated: onClientInvalidated,
      schedule: clock.schedule,
    );
    state = CanonicalOperationState(
      actors: actors,
      repository: repository,
      isRunning: () => running,
      grants: grants,
      connections: connections,
    );
    gate = DomainCommandGate(actors: actors, state: state);
    final receipts = ReceiptBook(signer, clock.now);
    trust = TrustOwner(
      repository: repository,
      getGate: () => gate,
      connections: connections,
      receipts: receipts,
      newId: newId,
      utcNow: clock.now,
      monotonicNow: clock.monotonic,
      schedule: clock.schedule,
    );
    profiles = ProfileOwner(
      gate: gate,
      repository: repository,
      receipts: receipts,
      credentials: CredentialPreparer(FeatureProtector(), parser),
      connections: connections,
      newId: newId,
      utcNow: clock.now,
    );
    operations = OwnedAppOperations(profiles, connections, trust);
  }
  final repository = MemoryDomainRepository(), clock = FeatureClock();
  final ActorAuthority actors;
  final parser = CancellableKeyParser(),
      verifier = HostSignatureVerifier(),
      privateSigner = PrivateSigner();
  final signer = ReceiptSigner(Uint8List.fromList(List.filled(32, 17))),
      transport = FeatureGrantTransport();
  late final CanonicalOperationState state;
  late final DomainCommandGate gate;
  late final ConnectionOwner connections;
  late final TrustOwner trust;
  late final GrantOwner grants;
  late final ProfileOwner profiles;
  late final OwnedAppOperations operations;
  final sessions = <FeatureSession>[];
  int sequence = 100;
  bool running = true;
  String newId() => featureId(++sequence);
  Future<String> create({String host = 'host.invalid', Actor? actor}) async {
    final auth = PasswordInput('synthetic-only');
    try {
      final result = await profiles.createProfile(
        actor ?? actors.ui,
        ProfileDraft(
          displayName: 'Fixture',
          host: host,
          username: 'root',
          authentication: auth,
        ),
        mutationId: newId(),
      );
      expect(result.error, isNull);
      return result.value!.entityId;
    } finally {
      auth.dispose();
    }
  }

  Future<FeatureSession> connect(String id, {Actor? actor}) async {
    final result = await connections.connect(
      actor ?? actors.ui,
      id,
      expectedRevision: repository.state.profiles[id]!.profileRevision,
    );
    expect(result.error, isNull);
    await featureTurns();
    return sessions.last;
  }

  TrustDecision decision(String id, TrustChallenge c, {String? mutationId}) =>
      TrustDecision(
        profileId: id,
        attemptId: c.attemptId,
        nonce: c.nonce,
        expectedProfileRevision: c.profileRevision,
        expectedTrustRevision: c.trustRevision,
        expectedObservationRevision: c.observationRevision,
        fingerprint: c.fingerprint,
        mutationId: mutationId ?? newId(),
        confirmed: true,
      );
  Future<void> dispose() async {
    for (final s in sessions) {
      s.failClose = false;
      if (s.holdClose != null && !s.holdClose!.isCompleted)
        s.holdClose!.complete();
    }
    transport.failClose = false;
    transport.failedClients.clear();
    for (final held in transport.heldClients.values) {
      if (!held.isCompleted) held.complete();
    }
    if (transport.holdClose != null && !transport.holdClose!.isCompleted)
      transport.holdClose!.complete();
    await grants.stopAdmission();
    await grants.cancelPending();
    await trust.dispose();
    await profiles.dispose();
    await connections.dispose();
    gate.stopAdmission();
    await gate.drain();
    await parser.dispose();
    await verifier.dispose();
    await privateSigner.dispose();
    signer.dispose();
  }
}
