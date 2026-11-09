import 'package:isar_community/isar.dart';

import '../domain/models.dart';
import '../monitoring/monitoring_history.dart';
import 'records.dart';
import 'workspace_store.dart';

/// Root/owners only. Returned records are detached; none is a public projection.
abstract interface class DomainRead {
  SoftwareCardRecord? softwareCard(String softwareId);
  int softwareCardCount({String? profileId});
  List<SoftwareCardRecord> softwareCards(
    String profileId, {
    int offset = 0,
    int limit = 100,
  });
  List<SoftwareEventRecord> softwareEvents(
    String profileId, {
    String? softwareId,
    int offset = 0,
    int limit = 100,
  });
  int softwareEventCount();
  List<JournalSource> journalSources();
  JournalSource? journalSource(String sourceId);
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
  MonitoringHistoryRecord? history(String profileId);
}

abstract interface class DomainTransaction implements DomainRead {
  void putSoftwareCard(SoftwareCardRecord value);
  void deleteSoftwareCard(String softwareId);
  void putSoftwareEvent(SoftwareEventRecord value);
  void pruneSoftwareEvents(int keep);
  void putJournalSource(JournalSource value);
  void deleteJournalSource(String sourceId);
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
  void putHistory(MonitoringHistoryRecord value);
}

abstract interface class DomainRepository implements MonitoringHistoryStore {
  T read<T>(T Function(DomainRead records) body);
  Future<T> write<T>(T Function(DomainTransaction records) body);
}

/// Uses the existing single WorkspaceStore; no cache, second DB or direct open.
final class WorkspaceDomainRepository implements DomainRepository {
  const WorkspaceDomainRepository(this.store);
  final WorkspaceStore store;
  @override
  String? loadHistory(String id, int revision) => read((records) {
    final value = records.history(id);
    return value?.connectionRevision == revision ? value!.payload : null;
  });
  @override
  Future<void> saveHistory(
    String id,
    int revision,
    String payload,
    bool Function() canCommit,
  ) => write((records) {
    if (!canCommit() || records.profile(id)?.connectionRevision != revision) {
      return;
    }
    final value = records.history(id) ?? MonitoringHistoryRecord();
    value
      ..profileId = id
      ..connectionRevision = revision
      ..payload = payload;
    records.putHistory(value);
  });
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
  SoftwareCardRecord? softwareCard(String id) =>
      db.softwareCardRecords.getBySoftwareIdSync(id);
  @override
  int softwareCardCount({String? profileId}) => profileId == null
      ? db.softwareCardRecords.countSync()
      : db.softwareCardRecords.where().profileIdEqualTo(profileId).countSync();
  @override
  List<SoftwareCardRecord> softwareCards(
    String profileId, {
    int offset = 0,
    int limit = 100,
  }) => db.softwareCardRecords
      .where()
      .profileIdEqualTo(profileId)
      .sortByCreatedAt()
      .thenBySoftwareId()
      .offset(offset)
      .limit(limit)
      .findAllSync();
  @override
  List<SoftwareEventRecord> softwareEvents(
    String profileId, {
    String? softwareId,
    int offset = 0,
    int limit = 100,
  }) {
    if (softwareId == null) {
      return db.softwareEventRecords
          .where()
          .profileIdEqualTo(profileId)
          .sortByCreatedAtDesc()
          .thenByEventIdDesc()
          .offset(offset)
          .limit(limit)
          .findAllSync();
    }
    return db.softwareEventRecords
        .where()
        .softwareIdEqualTo(softwareId)
        .filter()
        .profileIdEqualTo(profileId)
        .sortByCreatedAtDesc()
        .thenByEventIdDesc()
        .offset(offset)
        .limit(limit)
        .findAllSync();
  }

  @override
  int softwareEventCount() => db.softwareEventRecords.countSync();
  @override
  void putSoftwareCard(SoftwareCardRecord value) =>
      db.softwareCardRecords.putSync(value);
  @override
  void deleteSoftwareCard(String id) =>
      db.softwareCardRecords.deleteBySoftwareIdSync(id);
  @override
  void putSoftwareEvent(SoftwareEventRecord value) =>
      db.softwareEventRecords.putSync(value);
  @override
  void pruneSoftwareEvents(int keep) {
    final excess = softwareEventCount() - keep;
    if (excess > 0) {
      db.softwareEventRecords
          .where()
          .sortByCreatedAt()
          .thenByEventId()
          .limit(excess)
          .deleteAllSync();
    }
  }

  @override
  List<JournalSource> journalSources() =>
      db.journalSources.where().findAllSync();
  @override
  JournalSource? journalSource(String sourceId) =>
      db.journalSources.getBySourceIdSync(sourceId);
  @override
  void putJournalSource(JournalSource value) {
    db.journalSources.putSync(value);
  }

  @override
  void deleteJournalSource(String sourceId) {
    db.journalSources.deleteBySourceIdSync(sourceId);
  }

  @override
  MonitoringHistoryRecord? history(String id) =>
      db.monitoringHistoryRecords.getByProfileIdSync(id);
  @override
  void putHistory(MonitoringHistoryRecord value) {
    db.monitoringHistoryRecords.putSync(value);
  }

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
    final old = db.profiles.getByProfileIdSync(v.profileId);
    if (old != null && old.connectionRevision != v.connectionRevision) {
      db.monitoringHistoryRecords.deleteByProfileIdSync(v.profileId);
      for (final source
          in db.journalSources
              .where()
              .profileIdEqualTo(v.profileId)
              .findAllSync()) {
        source.connectionRevision = v.connectionRevision;
        source.payload =
            '{"version":1,"checkpoint":{},"entries":[],"partial":true}';
        db.journalSources.putSync(source);
      }
    }
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
    db.softwareCardRecords.where().profileIdEqualTo(id).deleteAllSync();
    db.softwareEventRecords.where().profileIdEqualTo(id).deleteAllSync();
    db.journalSources.where().profileIdEqualTo(id).deleteAllSync();
    db.monitoringHistoryRecords.deleteByProfileIdSync(id);
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
