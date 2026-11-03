import '../storage/domain_repository.dart';
import 'actor.dart';
import 'app_operations.dart';
import 'models.dart';

/// Implemented by GrantOwner using canonical grant/security records and clock
/// guard. Required even before MCP is exposed; there is no allow-all default.
abstract interface class CanonicalGrantAuthorization {
  Future<void> authorize(McpActor actor, AuthorizationPoint point);
  bool isAuthorizedNow(McpActor actor);
}

abstract interface class ConnectionVersionState {
  int generation(String profileId);
  bool isQuarantined(String endpointId);
}

final class CanonicalOperationState implements OperationState {
  const CanonicalOperationState({
    required this.actors,
    required this.repository,
    required this.isRunning,
    required this.grants,
    required this.connections,
  });
  final ActorAuthority actors;
  final DomainRepository repository;
  final bool Function() isRunning;
  final CanonicalGrantAuthorization grants;
  final ConnectionVersionState connections;
  @override
  String get ownerEpoch => actors.ownerEpoch;
  @override
  bool get running => isRunning();
  @override
  int get dataRevision => repository.read((r) => r.settings.dataRevision);
  void _checkRoot(CommandActor actor) {
    if (!running) throw const OperationFailure(FailureCode.shuttingDown);
    if (!actors.owns(actor))
      throw const OperationFailure(FailureCode.authRequired);
  }

  @override
  Future<void> authorize(CommandActor actor, AuthorizationPoint point) async {
    _checkRoot(actor);
    if (actor is McpActor) await grants.authorize(actor, point);
    if (!isAuthorizedNow(actor))
      throw const OperationFailure(FailureCode.authRequired);
  }

  @override
  bool isAuthorizedNow(CommandActor actor) {
    _checkRoot(actor);
    return actor is! McpActor || grants.isAuthorizedNow(actor);
  }

  @override
  EntityVersions? versions(String profileId) => repository.read((r) {
    final p = r.profile(profileId);
    if (p == null) return null;
    final c = r.credential(p.credentialId), e = r.endpoint(p.endpointId);
    if (p.profileId != profileId ||
        !isCanonicalUuid(profileId) ||
        !isCanonicalUuid(p.credentialId) ||
        c == null ||
        e == null ||
        c.profileId != profileId ||
        c.kind != p.authKind ||
        !{'password', 'privateKey'}.contains(p.authKind) ||
        c.protectedBytes.isEmpty ||
        c.protectedBytes.length > 2 * 1024 * 1024 ||
        e.normalizedHost != p.normalizedHost ||
        e.port != p.port ||
        e.profileRefCount < 1 ||
        e.profileRefCount > 1000 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(p.endpointId) ||
        [
          p.profileRevision,
          p.connectionRevision,
          c.secretRevision,
          e.trustRevision,
          e.observationRevision,
        ].any((v) => v < 1 || v > 9007199254740991)) {
      throw const OperationFailure(FailureCode.storageUnavailable);
    }
    final generation = connections.generation(profileId);
    if (generation < 0 || generation > 9007199254740991)
      throw const OperationFailure(FailureCode.storageUnavailable);
    return EntityVersions(
      profileId: profileId,
      profileRevision: p.profileRevision,
      connectionRevision: p.connectionRevision,
      credentialRevision: c.secretRevision,
      endpointId: p.endpointId,
      trustRevision: e.trustRevision,
      observationRevision: e.observationRevision,
      attemptGeneration: generation,
      quarantined: connections.isQuarantined(p.endpointId),
    );
  });
}
