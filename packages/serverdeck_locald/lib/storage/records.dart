import 'dart:convert';

import 'package:isar_community/isar.dart';
import 'package:serverdeck_protocol/codec.dart';

import 'models.dart';

part 'records.g.dart';

@collection
class StoredWorkspace {
  Id id = 1;
  String payload = '';
}

@collection
class StoredSettings {
  Id id = 1;
  String payload = '';
}

@collection
class StoredProfile {
  Id id = Isar.autoIncrement;
  @Index(unique: true, caseSensitive: true, replace: false)
  String entityId = '';
  String payload = '';
}

@collection
class StoredCredential {
  Id id = Isar.autoIncrement;
  @Index(unique: true, caseSensitive: true, replace: false)
  String entityId = '';
  String payload = '';
}

@collection
class StoredReceipt {
  Id id = Isar.autoIncrement;
  @Index(unique: true, caseSensitive: true, replace: false)
  String entityId = '';
  String payload = '';
}

const workspaceSchemas = <CollectionSchema>[
  StoredWorkspaceSchema,
  StoredSettingsSchema,
  StoredProfileSchema,
  StoredCredentialSchema,
  StoredReceiptSchema,
];

/// Bounded ordinary row documents, never a workspace-wide encrypted aggregate.
/// Native IDs are unresolved for multi-row entities. The repository must retain
/// existing IDs on updates and allocate IDs only for new business identities.
class WorkspaceRecords {
  WorkspaceRecords._(
    this.workspace,
    this.settings,
    this.profiles,
    this.credentials,
    this.receipts,
  );
  factory WorkspaceRecords.fromState(WorkspaceState state) {
    final codec = StrictCodec();
    String document(Map<String, Object?> value, int maxBytes) =>
        utf8.decode(codec.encode(value, maxBytes: maxBytes));
    return WorkspaceRecords._(
      StoredWorkspace()
        ..payload = document({
          'schemaVersion': 1,
          'workspaceId': state.workspaceId,
          'receiptKeyId': state.receiptKeyId,
          'ownerSid': state.ownerSid,
          'storeRevision': state.storeRevision,
        }, 4096),
      StoredSettings()..payload = document(state.settings.toJson(), 4096),
      List.unmodifiable([
        for (final value in state.profiles.values)
          StoredProfile()
            ..entityId = value.id
            ..payload = document(value.toJson(), 16 * 1024),
      ]),
      List.unmodifiable([
        for (final value in state.credentials.values)
          StoredCredential()
            ..entityId = value.id
            ..payload = document(value.toJson(), 512 * 1024),
      ]),
      List.unmodifiable([
        for (final value in state.receipts.values)
          StoredReceipt()
            ..entityId = value.requestId
            ..payload = document(value.toJson(), 4096),
      ]),
    );
  }
  final StoredWorkspace workspace;
  final StoredSettings settings;
  final List<StoredProfile> profiles;
  final List<StoredCredential> credentials;
  final List<StoredReceipt> receipts;
}
