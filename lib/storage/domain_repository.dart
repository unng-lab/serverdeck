import 'package:isar_community/isar.dart';

import '../domain/models.dart';
import 'records.dart';
import 'workspace_store.dart';

/// Root/owners only. Returned records are detached; none is a public projection.
abstract interface class DomainRead {
  AppSettings get settings;
  SecurityState get security;
  List<Profile> profiles();
  Profile? profile(String profileId);
  Credential? credential(String credentialId);
  EndpointTrust? endpoint(String endpointId);
  McpGrant? grant(String clientId);
  List<McpGrant> grants();
  MutationReceipt? receipt(String clientId, String mutationId);
  List<MutationReceipt> receipts();
  int unexpiredReceiptCount(int utcNow);
}

abstract interface class DomainTransaction implements DomainRead {
  void putSettings(AppSettings value);
  void putSecurity(SecurityState value);
  void putProfile(Profile value);
  void putCredential(Credential value);
  void putEndpoint(EndpointTrust value);
  void putGrant(McpGrant value);
  void putReceipt(MutationReceipt value);
  void deleteProfile(String profileId);
  void deleteCredential(String credentialId);
  void deleteEndpoint(String endpointId);
  void deleteReceipt(String clientId, String mutationId);
  int pruneExpiredReceipts(int utcNow);
}

abstract interface class DomainRepository {
  T read<T>(T Function(DomainRead records) body);
  Future<T> write<T>(T Function(DomainTransaction records) body);
}

/// Uses the existing single WorkspaceStore; no cache, second DB or direct open.
final class WorkspaceDomainRepository implements DomainRepository {
  const WorkspaceDomainRepository(this.store);
  final WorkspaceStore store;
  @override
  T read<T>(T Function(DomainRead records) body) =>
      store.readSync((db) => body(_IsarRecords(db)));
  @override
  Future<T> write<T>(T Function(DomainTransaction records) body) =>
      store.write((db) => body(_IsarRecords(db)));
}

final class _IsarRecords implements DomainTransaction {
  const _IsarRecords(this.db);
  final Isar db;
  @override
  AppSettings get settings =>
      db.appSettings.getSync(1) ??
      (throw const OperationFailure(FailureCode.storageUnavailable));
  @override
  SecurityState get security =>
      db.securityStates.getSync(1) ??
      (throw const OperationFailure(FailureCode.storageUnavailable));
  @override
  List<Profile> profiles() => db.profiles.where().findAllSync();
  @override
  Profile? profile(String id) => db.profiles.getByProfileIdSync(id);
  @override
  Credential? credential(String id) => db.credentials.getByCredentialIdSync(id);
  @override
  EndpointTrust? endpoint(String id) =>
      db.endpointTrusts.getByEndpointIdSync(id);
  @override
  McpGrant? grant(String id) => db.mcpGrants.getByClientIdSync(id);
  @override
  List<McpGrant> grants() => db.mcpGrants.where().findAllSync();
  @override
  MutationReceipt? receipt(String clientId, String mutationId) =>
      db.mutationReceipts.getByClientIdMutationIdSync(clientId, mutationId);
  @override
  List<MutationReceipt> receipts() => db.mutationReceipts.where().findAllSync();
  @override
  int unexpiredReceiptCount(int utcNow) =>
      db.mutationReceipts.where().expiresAtGreaterThan(utcNow).countSync();
  @override
  int pruneExpiredReceipts(int utcNow) => db.mutationReceipts
      .where()
      .expiresAtLessThan(utcNow, include: true)
      .deleteAllSync();
  @override
  void putSettings(AppSettings v) {
    db.appSettings.putSync(v);
  }

  @override
  void putSecurity(SecurityState v) {
    db.securityStates.putSync(v);
  }

  @override
  void putProfile(Profile v) {
    db.profiles.putSync(v);
  }

  @override
  void putCredential(Credential v) {
    db.credentials.putSync(v);
  }

  @override
  void putEndpoint(EndpointTrust v) {
    db.endpointTrusts.putSync(v);
  }

  @override
  void putGrant(McpGrant v) {
    db.mcpGrants.putSync(v);
  }

  @override
  void putReceipt(MutationReceipt v) {
    db.mutationReceipts.putSync(v);
  }

  @override
  void deleteProfile(String id) {
    db.profiles.deleteByProfileIdSync(id);
  }

  @override
  void deleteCredential(String id) {
    db.credentials.deleteByCredentialIdSync(id);
  }

  @override
  void deleteEndpoint(String id) {
    db.endpointTrusts.deleteByEndpointIdSync(id);
  }

  @override
  void deleteReceipt(String clientId, String mutationId) {
    db.mutationReceipts.deleteByClientIdMutationIdSync(clientId, mutationId);
  }
}
