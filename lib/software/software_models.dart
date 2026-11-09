import 'dart:convert';

import '../domain/models.dart';
import '../storage/records.dart';

const softwareCardBytes = 32 * 1024;
const softwareEventBytes = 8 * 1024;
const softwareCardLimit = 10000;
const softwareProfileCardLimit = 1000;
const softwareEventLimit = 10000;

void _identity(String id, String profileId, Iterable<int> numbers) {
  if (!isCanonicalUuid(id) ||
      !isCanonicalUuid(profileId) ||
      numbers.any((n) => n < -9007199254740991 || n > 9007199254740991))
    _invalid();
}

void _budget(SoftwareProjection value, int max) {
  void strings(Object? node) {
    if (node is String) {
      if (!isWellFormedUnicode(node) || node.contains('\u0000')) _invalid();
    } else if (node is Map<String, Object?>) {
      for (final value in node.values) {
        strings(value);
      }
    } else if (node is Iterable) {
      for (final value in node) {
        strings(value);
      }
    }
  }

  strings(value.toJson());
  if (utf8.encode(jsonEncode(value.toJson())).length > max) _invalid();
}

Never _invalid() => throw const OperationFailure(
  FailureCode.invalidArgument,
  field: OperationField.request,
);

String _string(String value, {required int max, bool required = false}) {
  if (!isWellFormedUnicode(value) || value.contains('\u0000')) _invalid();
  final result = value.trim();
  if ((required && result.isEmpty) || result.runes.length > max) _invalid();
  return result;
}

List<String> _paths(List<String> values) {
  if (values.length > 16 || values.toSet().length != values.length) _invalid();
  for (final value in values) {
    if (!isWellFormedUnicode(value) ||
        !value.startsWith('/') ||
        value.contains(RegExp(r'[\r\n\x00]')) ||
        utf8.encode(value).length > 1024) {
      _invalid();
    }
  }
  return List.unmodifiable(values);
}

/// Full replacement of the five user-maintained fields. Never executable input.
final class SoftwareCardInput {
  SoftwareCardInput({
    required String name,
    required String? version,
    required String? service,
    required List<String> dataPaths,
    required List<String> configPaths,
  }) : name = _string(name, max: 100, required: true),
       version = version == null ? null : _string(version, max: 256),
       service = service == null ? null : _string(service, max: 256),
       dataPaths = _paths(dataPaths),
       configPaths = _paths(configPaths),
       receiptPayload = Map.unmodifiable({
         'name': name,
         'version': version,
         'service': service,
         'dataPaths': List<String>.unmodifiable(dataPaths),
         'configPaths': List<String>.unmodifiable(configPaths),
       });

  /// Exact typed spelling for the existing receipt HMAC; never a public view.
  final Map<String, Object?> receiptPayload;
  final String name;
  final String? version, service;
  final List<String> dataPaths, configPaths;
  Map<String, Object?> toJson() => {
    'name': name,
    'version': version,
    'service': service,
    'dataPaths': dataPaths,
    'configPaths': configPaths,
  };
}

final class SoftwareNoteInput {
  SoftwareNoteInput({
    required this.action,
    required String summary,
    required this.outcome,
  }) : summary = _note(summary) {
    if (!const {
          'install',
          'update',
          'remove',
          'configure',
          'analyze',
          'status',
          'other',
        }.contains(action) ||
        !const {'success', 'failed', 'unknown'}.contains(outcome)) {
      _invalid();
    }
  }
  final String action, summary, outcome;
  static String _note(String value) {
    if (!isWellFormedUnicode(value) ||
        value.contains('\u0000') ||
        value.isEmpty ||
        utf8.encode(value).length > 2048)
      _invalid();
    return value;
  }
}

sealed class SoftwareProjection {
  const SoftwareProjection();
  Map<String, Object?> toJson();
}

final class SoftwareCardView extends SoftwareProjection {
  SoftwareCardView(SoftwareCardRecord record, {required this.currentTarget})
    : softwareId = record.softwareId,
      profileId = record.profileId,
      endpointId = record.endpointId,
      host = record.host,
      port = record.port,
      username = record.username,
      revision = record.revision,
      createdAt = record.createdAt,
      updatedAt = record.updatedAt,
      card = SoftwareCardInput(
        name: record.name,
        version: record.version,
        service: record.service,
        dataPaths: record.dataPaths,
        configPaths: record.configPaths,
      ) {
    _identity(softwareId, profileId, [revision, createdAt, updatedAt]);
    if (revision < 1) _invalid();
    _budget(this, softwareCardBytes);
  }
  final String softwareId, profileId, endpointId, host, username;
  final int port, revision, createdAt, updatedAt;
  final bool currentTarget;
  final SoftwareCardInput card;
  @override
  Map<String, Object?> toJson() => {
    'softwareId': softwareId,
    'profileId': profileId,
    'target': {
      'endpointId': endpointId,
      'host': host,
      'port': port,
      'username': username,
    },
    'currentTarget': currentTarget,
    ...card.toJson(),
    'revision': revision,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
}

final class SoftwareEventView extends SoftwareProjection {
  SoftwareEventView(SoftwareEventRecord r)
    : eventId = r.eventId,
      profileId = r.profileId,
      endpointId = r.endpointId,
      host = r.host,
      port = r.port,
      username = r.username,
      softwareId = r.softwareId,
      softwareName = r.softwareName,
      kind = r.kind,
      action = r.action,
      summary = r.summary,
      outcome = r.outcome,
      changedFields = List.unmodifiable(r.changedFields),
      actorKind = r.actorKind,
      clientId = r.clientId,
      createdAt = r.createdAt {
    _identity(eventId, profileId, [createdAt]);
    if (softwareId != null && !isCanonicalUuid(softwareId!)) _invalid();
    if (!const {'created', 'updated', 'deleted', 'note'}.contains(kind) ||
        !const {'ui', 'mcp'}.contains(actorKind) ||
        (actorKind == 'mcp' ? clientId == null : clientId != null) ||
        changedFields.toSet().length != changedFields.length ||
        changedFields.any(
          (f) => !const {
            'name',
            'version',
            'service',
            'dataPaths',
            'configPaths',
          }.contains(f),
        ) ||
        (kind != 'updated' && changedFields.isNotEmpty))
      _invalid();
    if (kind == 'note') {
      SoftwareNoteInput(
        action: action ?? '',
        summary: summary,
        outcome: outcome ?? '',
      );
    } else if (action != null || outcome != null) {
      _invalid();
    }
    _budget(this, softwareEventBytes);
  }
  final String eventId,
      profileId,
      endpointId,
      host,
      username,
      kind,
      summary,
      actorKind;
  final String? softwareId, softwareName, action, outcome, clientId;
  final List<String> changedFields;
  final int port, createdAt;
  @override
  Map<String, Object?> toJson() => {
    'eventId': eventId,
    'profileId': profileId,
    'endpointId': endpointId,
    'host': host,
    'port': port,
    'username': username,
    'softwareId': softwareId,
    'softwareName': softwareName,
    'kind': kind,
    'action': action,
    'summary': summary,
    'outcome': outcome,
    'changedFields': changedFields,
    'actorKind': actorKind,
    'clientId': clientId,
    'createdAt': createdAt,
  };
}

final class SoftwarePage extends SoftwareProjection {
  SoftwarePage(Iterable<SoftwareProjection> items, this.nextCursor)
    : items = List.unmodifiable(items);
  final List<SoftwareProjection> items;
  final String? nextCursor;
  @override
  Map<String, Object?> toJson() => {
    'items': items.map((e) => e.toJson()).toList(),
    'nextCursor': nextCursor,
  };
}
