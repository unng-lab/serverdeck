import 'package:isar_community/isar.dart';

import 'store_manifest.dart';

part 'records.g.dart';

@collection
class AppSettings {
  Id id = 1;
  int logicalFormat = currentStorageFormat;
  int settingsRevision = 1;
  int dataRevision = 1;
  int profilesListRevision = 1;
  String theme = 'dark';
  String? terminalConfiguration;
  bool mcpEnabled = false;
  int createdAt = DateTime.now().toUtc().millisecondsSinceEpoch;
  int lastSuccessfulOpenAt = DateTime.now().toUtc().millisecondsSinceEpoch;
}

@collection
class Profile {
  Id id = Isar.autoIncrement;
  @Index(unique: true)
  String profileId = '';
  int profileRevision = 1;
  int connectionRevision = 1;
  String displayName = '';
  String normalizedHost = '';
  String originalHost = '';
  int port = 22;
  String username = '';
  String authKind = 'password';
  String credentialId = '';
  @Index()
  String endpointId = '';
  int createdAt = 0;
  int updatedAt = 0;
}

@collection
class Credential {
  Id id = Isar.autoIncrement;
  @Index(unique: true)
  String credentialId = '';
  @Index(unique: true)
  String profileId = '';
  String kind = 'password';
  List<byte> protectedBytes = [];
  String? publicKeyType;
  int? publicKeyBits;
  List<byte>? publicKeyBytes;
  int secretRevision = 1;
}

@collection
class EndpointTrust {
  Id id = Isar.autoIncrement;
  @Index(unique: true)
  String endpointId = '';
  @Index(unique: true, composite: [CompositeIndex('port')])
  String normalizedHost = '';
  int port = 22;
  int trustRevision = 1;
  int observationRevision = 1;
  List<byte>? acceptedKeyBytes;
  String? acceptedType;
  String? acceptedFingerprint;
  int? acceptedAt;
  bool changed = false;
  List<byte>? observedKeyBytes;
  String? observedType;
  String? observedFingerprint;
  int? detectedAt;
  int? lastSeenAt;
  int profileRefCount = 0;
}

@collection
class McpGrant {
  Id id = Isar.autoIncrement;
  @Index(unique: true)
  String clientId = '';
  String name = '';
  int grantVersion = 1;
  int authorizationEpoch = 1;
  List<byte> protectedSecret = [];
  int createdAt = 0;
  @Index()
  int expiresAt = 0;
  int? revokedAt;
  String ownerUserSid = '';
  bool exportPending = true;
}

@collection
class MutationReceipt {
  Id id = Isar.autoIncrement;
  @Index(unique: true, composite: [CompositeIndex('mutationId')])
  String clientId = '';
  String mutationId = '';
  String method = '';
  List<byte> payloadHmac = [];
  int createdAt = 0;
  @Index()
  int expiresAt = 0;
  String resultCode = '';
  List<String> entityIds = [];
  List<int> entityRevisions = [];
  int committedDataRevision = 1;
}

@collection
class SecurityState {
  Id id = 1;
  List<byte> protectedReceiptHmacKey = [];
  int authorizationEpoch = 1;
  int lastAuthorizationUtc = 0;
  int minimumClockUtc = 0;
  int? lastClockRollbackAt;
}

@collection
class MonitoringHistoryRecord {
  Id id = Isar.autoIncrement;
  @Index(unique: true)
  String profileId = '';
  int connectionRevision = 1;
  String payload = '';
}

/// Every current store open uses the complete current set.
@collection
class JournalSource {
  Id id = Isar.autoIncrement;
  @Index(unique: true)
  String sourceId = '';
  @Index()
  String profileId = '';
  int connectionRevision = 1;
  String kind = 'journal';
  String target = '';
  String name = '';
  bool enabled = true;
  String payload = '{"version":1,"checkpoint":{},"entries":[],"partial":false}';
}

@collection
class SoftwareCardRecord {
  Id id = Isar.autoIncrement;
  @Index(unique: true)
  String softwareId = '';
  @Index()
  String profileId = '';
  String endpointId = '';
  String host = '';
  int port = 22;
  String username = '';
  String name = '';
  String? version;
  String? service;
  List<String> dataPaths = [];
  List<String> configPaths = [];
  int revision = 1;
  @Index()
  int createdAt = 0;
  int updatedAt = 0;
}

@collection
class SoftwareEventRecord {
  Id id = Isar.autoIncrement;
  @Index(unique: true)
  String eventId = '';
  @Index()
  String profileId = '';
  String endpointId = '';
  String host = '';
  int port = 22;
  String username = '';
  @Index()
  String? softwareId;
  String? softwareName;
  String kind = 'note';
  String? action;
  String summary = '';
  String? outcome;
  List<String> changedFields = [];
  String actorKind = 'ui';
  String? clientId;
  @Index()
  int createdAt = 0;
}

const workspaceSchemas = [
  AppSettingsSchema,
  ProfileSchema,
  CredentialSchema,
  EndpointTrustSchema,
  McpGrantSchema,
  MutationReceiptSchema,
  SecurityStateSchema,
  MonitoringHistoryRecordSchema,
  JournalSourceSchema,
  SoftwareCardRecordSchema,
  SoftwareEventRecordSchema,
];
