import 'dart:typed_data';

import 'package:serverdeck/domain/actor.dart';
import 'package:serverdeck/domain/app_operations.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/domain/mutation_receipts.dart';
import 'package:serverdeck/domain/receipt_book.dart';
import 'package:serverdeck/profiles/credential_input.dart';
import 'package:serverdeck/profiles/credential_parser.dart';
import 'package:serverdeck/profiles/key_parse_worker.dart';
import 'package:serverdeck/profiles/profile_owner.dart';
import 'package:serverdeck/storage/records.dart';

import 'domain_repository.dart';

String fixtureId(int value) =>
    '${value.toRadixString(16).padLeft(8, '0')}-0000-4000-8000-000000000000';

final class ProfileHarness {
  ProfileHarness({String? epoch})
    : actors = ActorAuthority(epoch ?? fixtureId(1)) {
    state = ProfileState(this);
    gate = DomainCommandGate(actors: actors, state: state);
    connections = ProfileConnections(this);
    owner = ProfileOwner(
      gate: gate,
      repository: repository,
      receipts: ReceiptBook(signer, () => now),
      credentials: CredentialPreparer(protector, inspector),
      connections: connections,
      newId: () => fixtureId(++sequence),
      utcNow: () => now,
    );
  }
  final repository = MemoryDomainRepository();
  final ActorAuthority actors;
  final signer = ReceiptSigner(Uint8List.fromList(List.filled(32, 7)));
  final protector = ProfileProtector();
  final inspector = ProfileInspector();
  late final ProfileState state;
  late final DomainCommandGate gate;
  late final ProfileConnections connections;
  late final ProfileOwner owner;
  int now = 1700000000000, sequence = 100;
  McpActor get mcp => actors.mcp(clientId: fixtureId(2), grantVersion: 1);
  Future<void> dispose() async {
    await owner.dispose();
    gate.stopAdmission();
    await gate.drain();
    signer.dispose();
  }

  ProfileDraft draft({
    String name = ' Server ',
    String host = 'EXAMPLE.test.',
    int? port,
    String username = 'Root',
    String password = ' SYNTHETIC\n',
  }) => ProfileDraft(
    displayName: name,
    host: host,
    port: port,
    username: username,
    authentication: PasswordInput(password),
  );
  Future<OperationResult<MutationValue>> create({
    String mutation = 'create-1',
    String host = 'EXAMPLE.test.',
    Actor? actor,
  }) => owner.createProfile(
    actor ?? actors.ui,
    draft(host: host),
    mutationId: mutation,
  );
}

final class ProfileState implements OperationState {
  ProfileState(this.h);
  final ProfileHarness h;
  @override
  String get ownerEpoch => h.actors.ownerEpoch;
  @override
  bool running = true;
  bool revoked = false, expired = false;
  int canonicalGrantVersion = 1;
  Future<void> Function(AuthorizationPoint)? beforeAuthorize;
  @override
  int get dataRevision => h.repository.read((r) => r.settings.dataRevision);
  @override
  Future<void> authorize(CommandActor actor, AuthorizationPoint point) async {
    await beforeAuthorize?.call(point);
    isAuthorizedNow(actor);
  }

  @override
  bool isAuthorizedNow(CommandActor actor) {
    if (actor is McpActor) {
      if (revoked || actor.grantVersion != canonicalGrantVersion)
        throw const OperationFailure(FailureCode.accessRevoked);
      if (expired) throw const OperationFailure(FailureCode.grantExpired);
    }
    return h.actors.owns(actor);
  }

  @override
  EntityVersions? versions(String profileId) => h.repository.read((r) {
    final p = r.profile(profileId);
    if (p == null) return null;
    final c = r.credential(p.credentialId)!, e = r.endpoint(p.endpointId)!;
    return EntityVersions(
      profileId: profileId,
      profileRevision: p.profileRevision,
      connectionRevision: p.connectionRevision,
      credentialRevision: c.secretRevision,
      endpointId: p.endpointId,
      trustRevision: e.trustRevision,
      observationRevision: e.observationRevision,
      attemptGeneration: h.connections.generations[profileId] ?? 0,
      quarantined: h.connections.quarantine.contains(p.endpointId),
    );
  });
}

final class ProfileConnections implements ProfileConnectionPort {
  ProfileConnections(this.h);
  final ProfileHarness h;
  final generations = <String, int>{};
  final quarantine = <String>{};
  final views = <String, ConnectionView>{};
  final challenges = <String, TrustChallenge>{};
  int closeCalls = 0;
  bool failClose = false;
  Future<void> Function()? onClose;
  Future<void> Function()? beforeCloseAdmission;
  @override
  ConnectionView connection(String id) =>
      views[id] ?? const ConnectionView(state: ConnectionState.disconnected);
  @override
  TrustChallenge? challenge(String id) => challenges[id];
  @override
  TrustView trustView(String id, EndpointTrust e) => TrustView(
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
  bool isQuarantined(String endpointId) => quarantine.contains(endpointId);
  @override
  int generation(String profileId) => generations[profileId] ?? 0;
  @override
  Future<ProfileCloseOutcome> closeForMutation(
    Actor actor,
    String profileId,
    int expectedRevision, {
    MutationValue? Function(CommandContext context)? findReplay,
  }) async {
    await beforeCloseAdmission?.call();
    final replay = await h.gate.prepare<MutationValue?>(
      actor,
      (context) => context.read(() {
        final found = findReplay?.call(context);
        if (found != null) return found;
        VersionFence(
          profileId: profileId,
          profileRevision: expectedRevision,
        ).check(h.state.versions(profileId));
        generations[profileId] = (generations[profileId] ?? 0) + 1;
        closeCalls++;
        return null;
      }),
    );
    if (replay != null) return ProfileCloseOutcome.replayed(replay);
    await onClose?.call();
    if (failClose) {
      quarantine.add(
        h.repository.read((r) => r.profile(profileId)!.endpointId),
      );
      views[profileId] = const ConnectionView(
        state: ConnectionState.failed,
        failureCode: FailureCode.cleanupRequired,
      );
      throw const OperationFailure(
        FailureCode.cleanupRequired,
        retryable: true,
        reason: FailureReason.connectionCleanup,
      );
    }
    return h.gate.prepare(
      actor,
      (context) => context.read(() {
        final found = findReplay?.call(context);
        if (found != null) return ProfileCloseOutcome.replayed(found);
        final current = h.state.versions(profileId);
        VersionFence(
          profileId: profileId,
          profileRevision: expectedRevision,
        ).check(current);
        views[profileId] = const ConnectionView(
          state: ConnectionState.disconnected,
        );
        return ProfileCloseOutcome.closed(
          VersionFence(
            profileId: profileId,
            profileRevision: expectedRevision,
            connectionRevision: current!.connectionRevision,
            credentialRevision: current.credentialRevision,
            endpointId: current.endpointId,
            attemptGeneration: current.attemptGeneration,
          ),
        );
      }),
    );
  }
}

final class ProfileProtector implements SecretProtector {
  int calls = 0;
  bool fail = false;
  Uint8List? retainedInput;
  final purposes = <String>[];
  Future<void> Function()? beforeReturn;
  @override
  Future<Uint8List> protect(Uint8List bytes, String purpose) async {
    calls++;
    retainedInput = bytes;
    purposes.add(purpose);
    await beforeReturn?.call();
    if (fail) throw StateError('SYNTHETIC protection fault');
    return Uint8List.fromList([0xde, ...bytes.map((b) => b ^ 0xaa)]);
  }
}

final class ProfileInspector implements KeyInspector {
  int calls = 0;
  @override
  Future<KeyInspection> inspect(
    Uint8List bytes, {
    String? passphrase,
    CredentialCancellation? cancellation,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    calls++;
    cancellation?.check();
    final parsed = parseOpenSshKey(bytes, passphrase: passphrase);
    try {
      return parsed.inspection;
    } finally {
      parsed.dispose();
    }
  }
}
