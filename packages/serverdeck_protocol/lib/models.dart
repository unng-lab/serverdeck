enum ReadinessState {
  starting,
  recovering,
  ready,
  storageBlocked,
  incompatible,
  stopping,
  unavailable,
}

enum Capability {
  readinessRead('readiness.read'),
  profilesRead('profiles.read'),
  profilesWrite('profiles.write'),
  settingsRead('settings.read'),
  settingsWrite('settings.write'),
  mutationsRead('mutations.read');

  const Capability(this.wireName);
  final String wireName;
}

enum ApiMethod {
  readinessGet('readiness.get', Capability.readinessRead, false),
  sessionPing('session.ping', null, false),
  sessionClose('session.close', null, false),
  profilesList('profiles.list', Capability.profilesRead, true),
  profilesGet('profiles.get', Capability.profilesRead, true),
  profilesCreate('profiles.create', Capability.profilesWrite, true),
  profilesUpdate('profiles.update', Capability.profilesWrite, true),
  profilesDelete('profiles.delete', Capability.profilesWrite, true),
  settingsGet('settings.get', Capability.settingsRead, true),
  settingsUpdate('settings.update', Capability.settingsWrite, true),
  mutationsGet('mutations.get', Capability.mutationsRead, true),
  mutationsRecent('mutations.recent', Capability.mutationsRead, true);

  const ApiMethod(this.wireName, this.capability, this.requiresReady);
  final String wireName;
  final Capability? capability;
  final bool requiresReady;
  bool get isMutation => const {
    profilesCreate,
    profilesUpdate,
    profilesDelete,
    settingsUpdate,
  }.contains(this);
}

enum CredentialKind { none, password, privateKey }

enum CredentialMode { keep, remove, replace }

enum MutationState { queued, running, committed, notFound }

enum ThemePreference { system, light, dark }

enum ErrorCode {
  unsupported('UNSUPPORTED'),
  unauthorized('UNAUTHORIZED'),
  forbidden('FORBIDDEN'),
  incompatible('INCOMPATIBLE'),
  notReady('NOT_READY'),
  storageBlocked('STORAGE_BLOCKED'),
  validation('VALIDATION'),
  notFound('NOT_FOUND'),
  alreadyExists('ALREADY_EXISTS'),
  revisionConflict('REVISION_CONFLICT'),
  idempotencyConflict('IDEMPOTENCY_CONFLICT'),
  resourceLimit('RESOURCE_LIMIT'),
  timeout('TIMEOUT'),
  serviceUnavailable('SERVICE_UNAVAILABLE'),
  internal('INTERNAL');

  const ErrorCode(this.wireName);
  final String wireName;
}

class ReadinessView {
  const ReadinessView({
    required this.state,
    required this.reason,
    required this.workspaceId,
    required this.generation,
  });
  final ReadinessState state;
  final ErrorCode? reason;
  final String? workspaceId;
  final String generation;
  Map<String, Object?> toJson() => {
    'state': state == ReadinessState.storageBlocked
        ? 'storage-blocked'
        : state.name,
    'reason': reason?.wireName,
    'product': 'serverdeck-next',
    'apiMajor': 1,
    'apiMinor': 0,
    'workspaceSlot': 'default',
    'workspaceId': workspaceId,
    'generation': generation,
    'storageSchema': 1,
    'features': {
      'profiles': true,
      'ssh': false,
      'jobs': false,
      'backend': false,
    },
    'clientPlatform': 'windows-x64',
  };
}

/// Ephemeral request input only. Never returned as a read projection.
class CredentialAction {
  const CredentialAction.keep()
    : mode = CredentialMode.keep,
      kind = null,
      password = null,
      privateKey = null,
      passphrase = null;
  const CredentialAction.remove()
    : mode = CredentialMode.remove,
      kind = null,
      password = null,
      privateKey = null,
      passphrase = null;
  const CredentialAction.password(this.password)
    : mode = CredentialMode.replace,
      kind = CredentialKind.password,
      privateKey = null,
      passphrase = null;
  const CredentialAction.privateKey(this.privateKey, this.passphrase)
    : mode = CredentialMode.replace,
      kind = CredentialKind.privateKey,
      password = null;
  final CredentialMode mode;
  final CredentialKind? kind;
  final String? password, privateKey, passphrase;
  Map<String, Object?> toJson() => {
    'action': mode.name,
    if (kind != null) 'kind': kind!.name,
    if (kind == CredentialKind.password) 'password': password,
    if (kind == CredentialKind.privateKey) 'privateKey': privateKey,
    if (kind == CredentialKind.privateKey) 'passphrase': passphrase,
  };
}

/// Read projection deliberately has no credential reference or secret buffer.
class ProfileView {
  const ProfileView({
    required this.id,
    required this.revision,
    required this.name,
    required this.address,
    required this.port,
    required this.sshUser,
    required this.tags,
    required this.credentialRevision,
    required this.connectionRevision,
    required this.trustRevision,
    required this.createdAt,
    required this.updatedAt,
    required this.credentialKind,
    required this.credentialConfigured,
  });
  final String id, revision, name, address, sshUser;
  final int port;
  final List<String> tags;
  final String credentialRevision, connectionRevision, trustRevision;
  final String createdAt, updatedAt;
  final CredentialKind credentialKind;
  final bool credentialConfigured;
  Map<String, Object?> toJson() => {
    'id': id,
    'revision': revision,
    'name': name,
    'address': address,
    'port': port,
    'sshUser': sshUser,
    'tags': tags,
    'credentialRevision': credentialRevision,
    'connectionRevision': connectionRevision,
    'trustRevision': trustRevision,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'credential': {
      'kind': credentialKind.name,
      'configured': credentialConfigured,
    },
  };
}

class SettingsView {
  const SettingsView({
    this.revision = '1',
    this.theme = ThemePreference.system,
    this.reduceMotion = false,
    this.selectedProfileId,
  });
  final String revision;
  final ThemePreference theme;
  final bool reduceMotion;
  final String? selectedProfileId;
  Map<String, Object?> toJson() => {
    'revision': revision,
    'theme': theme.name,
    'reduceMotion': reduceMotion,
    'selectedProfileId': selectedProfileId,
  };
}

class MutationResult {
  const MutationResult({
    required this.entityId,
    required this.entityRevision,
    required this.storeRevision,
    required this.deleted,
  });
  final String? entityId, entityRevision;
  final String storeRevision;
  final bool deleted;
  Map<String, Object?> toJson() => {
    'entityId': entityId,
    'entityRevision': entityRevision,
    'storeRevision': storeRevision,
    'deleted': deleted,
  };
}

class ApiRequest {
  const ApiRequest({
    required this.id,
    required this.sessionId,
    required this.method,
    required this.params,
  });
  final String id, sessionId, method;
  final Map<String, Object?> params;
  Map<String, Object?> toJson() => {
    'v': 1,
    'id': id,
    'sessionId': sessionId,
    'method': method,
    'params': params,
  };
  factory ApiRequest.mutationStatus({
    required String queryId,
    required String sessionId,
    required String mutationRequestId,
  }) {
    if (queryId == mutationRequestId)
      throw ArgumentError('INVALID_STATUS_CORRELATION');
    return ApiRequest(
      id: queryId,
      sessionId: sessionId,
      method: 'mutations.get',
      params: {'requestId': mutationRequestId},
    );
  }
}

class ApiResponse {
  const ApiResponse.success({
    required this.id,
    required this.generation,
    required Map<String, Object?> this.result,
  }) : error = null;
  const ApiResponse.failure({
    required this.id,
    required this.generation,
    required Map<String, Object?> this.error,
  }) : result = null;
  final String id, generation;
  final Map<String, Object?>? result, error;
  Map<String, Object?> toJson() => {
    'v': 1,
    'id': id,
    'generation': generation,
    if (result != null) 'result': result,
    if (error != null) 'error': error,
  };
}

class ServerHello {
  const ServerHello({required this.generation, required this.serverNonce});
  final String generation, serverNonce;
  Map<String, Object?> toJson() => {
    'hello': {
      'product': 'serverdeck-next',
      'apiMajor': 1,
      'apiMinor': 0,
      'workspaceSlot': 'default',
      'generation': generation,
      'serverNonce': serverNonce,
    },
  };
}

class Authenticate {
  const Authenticate({
    required this.clientNonce,
    required this.clientBuildId,
    required this.requestedCapabilities,
    required this.proof,
  });
  final String clientNonce, clientBuildId, proof;
  final List<String> requestedCapabilities;
  Map<String, Object?> toJson() => {
    'authenticate': {
      'clientNonce': clientNonce,
      'clientBuildId': clientBuildId,
      'requestedCapabilities': requestedCapabilities,
      'proof': proof,
    },
  };
}

class Authenticated {
  const Authenticated({
    required this.sessionId,
    required this.capabilities,
    required this.proof,
  });
  final String sessionId, proof;
  final List<String> capabilities;
  Map<String, Object?> toJson() => {
    'authenticated': {
      'sessionId': sessionId,
      'capabilities': capabilities,
      'idleLeaseSeconds': 60,
      'proof': proof,
    },
  };
}

class ProfilesSnapshot {
  const ProfilesSnapshot(this.storeRevision, this.profiles);
  final String storeRevision;
  final List<ProfileView> profiles;
  Map<String, Object?> toJson() => {
    'storeRevision': storeRevision,
    'profiles': profiles.map((p) => p.toJson()).toList(),
  };
}

class ProfileSnapshot {
  const ProfileSnapshot(this.storeRevision, this.profile);
  final String storeRevision;
  final ProfileView profile;
  Map<String, Object?> toJson() => {
    'storeRevision': storeRevision,
    'profile': profile.toJson(),
  };
}

class SettingsSnapshot {
  const SettingsSnapshot(this.storeRevision, this.settings);
  final String storeRevision;
  final SettingsView settings;
  Map<String, Object?> toJson() => {
    'storeRevision': storeRevision,
    'settings': settings.toJson(),
  };
}

class MutationStatusResult {
  const MutationStatusResult.queued()
    : state = MutationState.queued,
      result = null;
  const MutationStatusResult.running()
    : state = MutationState.running,
      result = null;
  const MutationStatusResult.notFound()
    : state = MutationState.notFound,
      result = null;
  const MutationStatusResult.committed(MutationResult committedResult)
    : state = MutationState.committed,
      result = committedResult;
  final MutationState state;
  final MutationResult? result;
  Map<String, Object?> toJson() => {
    'state': state == MutationState.notFound ? 'not-found' : state.name,
    'result': result?.toJson(),
  };
}

class MutationReceiptView {
  const MutationReceiptView({
    required this.requestId,
    required this.operation,
    required this.profileId,
    required this.result,
    required this.committedAt,
  });
  final String requestId, operation, committedAt;
  final String? profileId;
  final MutationResult result;
  Map<String, Object?> toJson() => {
    'requestId': requestId,
    'operation': operation,
    'profileId': profileId,
    'result': result.toJson(),
    'committedAt': committedAt,
  };
}

class RecentMutationsView {
  const RecentMutationsView(this.receipts, {required this.truncated});
  final List<MutationReceiptView> receipts;
  final bool truncated;
  Map<String, Object?> toJson() => {
    'receipts': receipts.map((r) => r.toJson()).toList(),
    'truncated': truncated,
  };
}
