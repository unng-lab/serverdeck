import '../validation.dart';
import 'models.dart' show AutomationRevisionKey, requireAutomationRevision;
import 'profile_body.dart';
import 'values.dart';

/// Workspace metadata. Persistence must compare headRevision atomically; this
/// DTO cannot provide CAS, author permission, or archive admission by itself.
final class AutomationProfileRecord {
  AutomationProfileRecord._(
    this.workspaceId,
    this.id,
    this.name,
    this.description,
    this.headRevision,
    this.archived,
  );

  factory AutomationProfileRecord.fromJson(Map<String, Object?> value) {
    requireAutomationDocument(value);
    requireFields(value, {
      'workspaceId',
      'id',
      'name',
      'description',
      'headRevision',
      'archived',
    });
    final archived = value['archived'];
    if (archived is! bool) invalidAutomationValue();
    return AutomationProfileRecord._(
      requireUuid(value['workspaceId']),
      requireUuid(value['id']),
      automationText(value['name'], min: 1, max: 100),
      automationText(value['description'], max: 2000, multiline: true),
      requireAutomationRevision(value['headRevision']),
      archived,
    );
  }

  final String workspaceId, id, name, description;
  final int headRevision;
  final bool archived;
  Map<String, Object?> toJson() => {
    'workspaceId': workspaceId,
    'id': id,
    'name': name,
    'description': description,
    'headRevision': headRevision,
    'archived': archived,
  };
}

/// Immutable persisted revision. Recomputes digest on load; body equality never
/// replaces the full revision key when checking execution authority.
final class AutomationRevisionRecord {
  AutomationRevisionRecord._(
    this.workspaceId,
    this.key,
    this.parentRevision,
    this.body,
    this.authorGrantId,
    this.createdAt,
  );

  static Future<AutomationRevisionRecord> fromJson(
    Map<String, Object?> value,
  ) async {
    requireAutomationDocument(value);
    requireFields(value, {
      'workspaceId',
      'profileId',
      'revision',
      'parentRevision',
      'bodyFormat',
      'body',
      'digest',
      'authorGrantId',
      'createdAt',
    });
    final workspaceId = requireUuid(value['workspaceId']);
    final key = AutomationRevisionKey.fromJson({
      'profileId': value['profileId'],
      'revision': value['revision'],
      'bodyDigest': value['digest'],
    });
    final rawParent = value['parentRevision'];
    final parent = rawParent == null
        ? null
        : requireAutomationRevision(rawParent);
    if ((key.revision == 1 && parent != null) ||
        (key.revision > 1 && parent != key.revision - 1) ||
        value['bodyFormat'] is! int ||
        value['bodyFormat'] != 1)
      invalidAutomationValue();
    final rawBody = value['body'];
    if (rawBody is! Map<String, Object?>) invalidAutomationValue();
    final body = AutomationBody.fromJson(rawBody);
    final rawAuthor = value['authorGrantId'];
    final author = rawAuthor == null ? null : requireUuid(rawAuthor);
    final createdAt = automationTimestamp(value['createdAt']);
    // All caller-owned input has been copied/validated before the first await.
    if (await body.digest() != key.bodyDigest) invalidAutomationValue();
    return AutomationRevisionRecord._(
      workspaceId,
      key,
      parent,
      body,
      author,
      createdAt,
    );
  }

  final String workspaceId;
  final AutomationRevisionKey key;
  final int? parentRevision;
  final AutomationBody body;
  final String? authorGrantId;
  final DateTime createdAt;
  Map<String, Object?> toJson() => {
    'workspaceId': workspaceId,
    'profileId': key.profileId,
    'revision': key.revision,
    'parentRevision': parentRevision,
    'bodyFormat': 1,
    'body': body.toJson(),
    'digest': key.bodyDigest,
    'authorGrantId': authorGrantId,
    'createdAt': createdAt.toIso8601String(),
  };
}
