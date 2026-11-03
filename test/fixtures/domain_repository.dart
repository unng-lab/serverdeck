import 'dart:async';

import 'package:serverdeck/storage/domain_repository.dart';
import 'package:serverdeck/storage/records.dart';

import 'fake_store_backend.dart' show copySettings, copySecurity;

/// Snapshot model for owner unit tests. Does not load an Isar engine.
final class MemoryDomain {
  AppSettings settings = AppSettings();
  SecurityState security = SecurityState()..protectedReceiptHmacKey = [1];
  final profiles = <String, Profile>{};
  final credentials = <String, Credential>{};
  final endpoints = <String, EndpointTrust>{};
  final grants = <String, McpGrant>{};
  final receipts = <(String, String), MutationReceipt>{};
  MemoryDomain clone() => MemoryDomain()
    ..settings = copySettings(settings)
    ..security = copySecurity(security)
    ..profiles.addAll(profiles.map((k, v) => MapEntry(k, copyProfile(v))))
    ..credentials.addAll(
      credentials.map((k, v) => MapEntry(k, copyCredential(v))),
    )
    ..endpoints.addAll(endpoints.map((k, v) => MapEntry(k, copyEndpoint(v))))
    ..grants.addAll(grants.map((k, v) => MapEntry(k, copyGrant(v))))
    ..receipts.addAll(receipts.map((k, v) => MapEntry(k, copyReceipt(v))));
}

final class MemoryDomainRepository implements DomainRepository {
  MemoryDomain state = MemoryDomain();
  MemoryDomain? _ambient;
  Future<void> _tail = Future.value();
  Future<void> Function()? beforeWrite;
  int? failAfterWrite;
  bool failCommit = false;
  int? receiptCountOverride;
  int committedWrites = 0;
  @override
  T read<T>(T Function(DomainRead) body) {
    final records = _MemoryRecords(
      _ambient ?? state,
      false,
      (_) {},
      receiptCountOverride,
    );
    try {
      return body(records);
    } finally {
      records.active = false;
    }
  }

  @override
  Future<T> write<T>(T Function(DomainTransaction) body) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        await beforeWrite?.call();
        final working = state.clone();
        var writes = 0;
        final records = _MemoryRecords(working, true, (_) {
          writes++;
          if (writes == failAfterWrite)
            throw StateError('synthetic write fault');
        }, receiptCountOverride);
        _ambient = working;
        try {
          final value = body(records);
          if (value is Future)
            throw StateError('Expected synchronous transaction');
          if (failCommit) {
            failCommit = false;
            throw StateError('synthetic commit fault');
          }
          state = working;
          committedWrites++;
          result.complete(value);
        } finally {
          records.active = false;
          _ambient = null;
        }
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }
}

final class _MemoryRecords implements DomainTransaction {
  _MemoryRecords(
    this.state,
    this.writable,
    this.touch,
    this.receiptCountOverride,
  );
  final MemoryDomain state;
  final bool writable;
  final void Function(String) touch;
  final int? receiptCountOverride;
  bool active = true;
  void check() {
    if (!active) throw StateError('Expired record view');
  }

  void write(String kind) {
    check();
    if (!writable) throw StateError('Read-only record view');
    touch(kind);
  }

  @override
  AppSettings get settings {
    check();
    return copySettings(state.settings);
  }

  @override
  SecurityState get security {
    check();
    return copySecurity(state.security);
  }

  @override
  List<Profile> profiles() {
    check();
    return state.profiles.values.map(copyProfile).toList();
  }

  @override
  Profile? profile(String id) {
    check();
    final p = state.profiles[id];
    return p == null ? null : copyProfile(p);
  }

  @override
  Credential? credential(String id) {
    check();
    final c = state.credentials[id];
    return c == null ? null : copyCredential(c);
  }

  @override
  EndpointTrust? endpoint(String id) {
    check();
    final e = state.endpoints[id];
    return e == null ? null : copyEndpoint(e);
  }

  @override
  McpGrant? grant(String id) {
    check();
    final g = state.grants[id];
    return g == null ? null : copyGrant(g);
  }

  @override
  List<McpGrant> grants() {
    check();
    return state.grants.values.map(copyGrant).toList();
  }

  @override
  MutationReceipt? receipt(String clientId, String mutationId) {
    check();
    final r = state.receipts[(clientId, mutationId)];
    return r == null ? null : copyReceipt(r);
  }

  @override
  List<MutationReceipt> receipts() {
    check();
    return state.receipts.values.map(copyReceipt).toList();
  }

  @override
  int unexpiredReceiptCount(int now) {
    check();
    return receiptCountOverride ??
        state.receipts.values.where((r) => r.expiresAt > now).length;
  }

  @override
  int pruneExpiredReceipts(int now) {
    final expired = state.receipts.entries
        .where((e) => e.value.expiresAt <= now)
        .map((e) => e.key)
        .toList();
    if (expired.isNotEmpty) {
      write('prune receipts');
      for (final key in expired) {
        state.receipts.remove(key);
      }
    }
    return expired.length;
  }

  @override
  void putSettings(AppSettings v) {
    write('settings');
    state.settings = copySettings(v);
  }

  @override
  void putSecurity(SecurityState v) {
    write('security');
    state.security = copySecurity(v);
  }

  @override
  void putProfile(Profile v) {
    write('profile');
    if (state.profiles.containsKey(v.profileId) &&
        state.profiles[v.profileId]!.id != v.id)
      throw StateError('duplicate profile');
    state.profiles[v.profileId] = copyProfile(v);
  }

  @override
  void putCredential(Credential v) {
    write('credential');
    if (state.credentials.values.any(
      (c) => c.profileId == v.profileId && c.credentialId != v.credentialId,
    ))
      throw StateError('duplicate profile credential');
    state.credentials[v.credentialId] = copyCredential(v);
  }

  @override
  void putEndpoint(EndpointTrust v) {
    write('endpoint');
    state.endpoints[v.endpointId] = copyEndpoint(v);
  }

  @override
  void putGrant(McpGrant v) {
    write('grant');
    state.grants[v.clientId] = copyGrant(v);
  }

  @override
  void putReceipt(MutationReceipt v) {
    write('receipt');
    if (state.receipts.containsKey((v.clientId, v.mutationId)))
      throw StateError('duplicate receipt');
    state.receipts[(v.clientId, v.mutationId)] = copyReceipt(v);
  }

  @override
  void deleteProfile(String id) {
    write('delete profile');
    state.profiles.remove(id);
  }

  @override
  void deleteCredential(String id) {
    write('delete credential');
    state.credentials.remove(id);
  }

  @override
  void deleteEndpoint(String id) {
    write('delete endpoint');
    state.endpoints.remove(id);
  }

  @override
  void deleteReceipt(String clientId, String mutationId) {
    write('delete receipt');
    state.receipts.remove((clientId, mutationId));
  }
}

Profile copyProfile(Profile p) => Profile()
  ..id = p.id
  ..profileId = p.profileId
  ..profileRevision = p.profileRevision
  ..connectionRevision = p.connectionRevision
  ..displayName = p.displayName
  ..normalizedHost = p.normalizedHost
  ..originalHost = p.originalHost
  ..port = p.port
  ..username = p.username
  ..authKind = p.authKind
  ..credentialId = p.credentialId
  ..endpointId = p.endpointId
  ..createdAt = p.createdAt
  ..updatedAt = p.updatedAt;
Credential copyCredential(Credential c) => Credential()
  ..id = c.id
  ..credentialId = c.credentialId
  ..profileId = c.profileId
  ..kind = c.kind
  ..protectedBytes = [...c.protectedBytes]
  ..publicKeyType = c.publicKeyType
  ..publicKeyBits = c.publicKeyBits
  ..secretRevision = c.secretRevision;
EndpointTrust copyEndpoint(EndpointTrust e) => EndpointTrust()
  ..id = e.id
  ..endpointId = e.endpointId
  ..normalizedHost = e.normalizedHost
  ..port = e.port
  ..trustRevision = e.trustRevision
  ..observationRevision = e.observationRevision
  ..acceptedKeyBytes = e.acceptedKeyBytes?.toList()
  ..acceptedType = e.acceptedType
  ..acceptedFingerprint = e.acceptedFingerprint
  ..acceptedAt = e.acceptedAt
  ..changed = e.changed
  ..observedKeyBytes = e.observedKeyBytes?.toList()
  ..observedType = e.observedType
  ..observedFingerprint = e.observedFingerprint
  ..detectedAt = e.detectedAt
  ..lastSeenAt = e.lastSeenAt
  ..profileRefCount = e.profileRefCount;
McpGrant copyGrant(McpGrant g) => McpGrant()
  ..id = g.id
  ..clientId = g.clientId
  ..name = g.name
  ..grantVersion = g.grantVersion
  ..authorizationEpoch = g.authorizationEpoch
  ..protectedSecret = [...g.protectedSecret]
  ..createdAt = g.createdAt
  ..expiresAt = g.expiresAt
  ..revokedAt = g.revokedAt
  ..ownerUserSid = g.ownerUserSid
  ..exportPending = g.exportPending;
MutationReceipt copyReceipt(MutationReceipt r) => MutationReceipt()
  ..id = r.id
  ..clientId = r.clientId
  ..mutationId = r.mutationId
  ..method = r.method
  ..payloadHmac = [...r.payloadHmac]
  ..createdAt = r.createdAt
  ..expiresAt = r.expiresAt
  ..resultCode = r.resultCode
  ..entityIds = [...r.entityIds]
  ..entityRevisions = [...r.entityRevisions]
  ..committedDataRevision = r.committedDataRevision;
