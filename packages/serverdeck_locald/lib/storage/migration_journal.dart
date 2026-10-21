import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/validation.dart';

Never _blocked() => throw StateError('STORAGE_BLOCKED');
Never _incompatible() => throw StateError('INCOMPATIBLE');

String _digest(Object? value) {
  if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value))
    _blocked();
  return value;
}

void _document(Map<String, Object?> value) {
  try {
    StrictCodec().encode(value, maxBytes: 4096);
  } on FormatException {
    _blocked();
  }
}

String _uuid(Object? value) {
  try {
    return requireUuid(value);
  } on FormatException {
    _blocked();
  }
}

void _fields(Map<String, Object?> value, Set<String> fields) {
  try {
    requireFields(value, fields);
  } on FormatException {
    _blocked();
  }
}

String _sid(Object? value) {
  if (value is! String || !RegExp(r'^S-1-\d+(?:-\d+)+$').hasMatch(value))
    _blocked();
  return value;
}

final class MigrationManifest {
  MigrationManifest._(
    this.schema,
    this.workspaceId,
    this.receiptKeyId,
    this.ownerSid,
  );
  factory MigrationManifest.fromJson(Map<String, Object?> value) {
    _document(value);
    final schema = value['schema'];
    if (schema is! int || (schema != 1 && schema != 2)) _incompatible();
    _fields(value, {
      'product',
      'schema',
      'workspaceId',
      'receiptKeyId',
      'ownerSid',
      if (schema == 2) 'format',
    });
    if (value['product'] != 'serverdeck-next') _blocked();
    if (schema == 2 && (value['format'] is! int || value['format'] != 2))
      _incompatible();
    return MigrationManifest._(
      schema,
      _uuid(value['workspaceId']),
      _uuid(value['receiptKeyId']),
      _sid(value['ownerSid']),
    );
  }
  final int schema;
  final String workspaceId, receiptKeyId, ownerSid;
  Map<String, Object?> toJson() => {
    'product': 'serverdeck-next',
    'schema': schema,
    if (schema == 2) 'format': 2,
    'workspaceId': workspaceId,
    'receiptKeyId': receiptKeyId,
    'ownerSid': ownerSid,
  };
}

enum MigrationPhase { preparing, prepared }

/// Strict private recovery metadata. Contains no caller paths or authority to
/// open a DB. The native migrator must bind identity to verified key custody.
final class MigrationJournal {
  MigrationJournal._(
    this.migrationId,
    this.workspaceId,
    this.receiptKeyId,
    this.ownerSid,
    this.sourceDbDigest,
    this.sourceManifestDigest,
    this.sourceKeyWrapperDigest,
    this.phase,
    this.targetDbDigest,
    this.targetManifestDigest,
    this.sourceRowsDigest,
  );
  factory MigrationJournal.fromJson(Map<String, Object?> value) {
    _document(value);
    if (value['format'] is! int ||
        value['format'] != 1 ||
        value['fromSchema'] is! int ||
        value['fromSchema'] != 1 ||
        value['toSchema'] is! int ||
        value['toSchema'] != 2)
      _blocked();
    final phase = switch (value['phase']) {
      'preparing' => MigrationPhase.preparing,
      'prepared' => MigrationPhase.prepared,
      _ => _blocked(),
    };
    _fields(value, {
      'format',
      'fromSchema',
      'toSchema',
      'migrationId',
      'workspaceId',
      'receiptKeyId',
      'ownerSid',
      'sourceDbDigest',
      'sourceManifestDigest',
      'sourceKeyWrapperDigest',
      'phase',
      if (phase == MigrationPhase.prepared) ...{
        'targetDbDigest',
        'targetManifestDigest',
        'sourceRowsDigest',
      },
    });
    return MigrationJournal._(
      _uuid(value['migrationId']),
      _uuid(value['workspaceId']),
      _uuid(value['receiptKeyId']),
      _sid(value['ownerSid']),
      _digest(value['sourceDbDigest']),
      _digest(value['sourceManifestDigest']),
      _digest(value['sourceKeyWrapperDigest']),
      phase,
      phase == MigrationPhase.prepared
          ? _digest(value['targetDbDigest'])
          : null,
      phase == MigrationPhase.prepared
          ? _digest(value['targetManifestDigest'])
          : null,
      phase == MigrationPhase.prepared
          ? _digest(value['sourceRowsDigest'])
          : null,
    );
  }
  final String migrationId, workspaceId, receiptKeyId, ownerSid;
  final String sourceDbDigest, sourceManifestDigest, sourceKeyWrapperDigest;
  final MigrationPhase phase;
  final String? targetDbDigest, targetManifestDigest, sourceRowsDigest;

  MigrationJournal prepare({
    required String targetDbDigest,
    required String targetManifestDigest,
    required String sourceRowsDigest,
  }) {
    if (phase != MigrationPhase.preparing) _blocked();
    return MigrationJournal.fromJson({
      ...toJson(),
      'phase': 'prepared',
      'targetDbDigest': targetDbDigest,
      'targetManifestDigest': targetManifestDigest,
      'sourceRowsDigest': sourceRowsDigest,
    });
  }

  Map<String, Object?> toJson() => {
    'format': 1,
    'fromSchema': 1,
    'toSchema': 2,
    'migrationId': migrationId,
    'workspaceId': workspaceId,
    'receiptKeyId': receiptKeyId,
    'ownerSid': ownerSid,
    'sourceDbDigest': sourceDbDigest,
    'sourceManifestDigest': sourceManifestDigest,
    'sourceKeyWrapperDigest': sourceKeyWrapperDigest,
    'phase': phase.name,
    if (phase == MigrationPhase.prepared) ...{
      'targetDbDigest': targetDbDigest,
      'targetManifestDigest': targetManifestDigest,
      'sourceRowsDigest': sourceRowsDigest,
    },
  };
}

enum StagePresence { absent, empty, journal }

enum MigrationAction {
  prepare,
  rebuildStage,
  verifyTargetThenPublishManifest,
  verifyTargetThenCleanup,
  normalOpen,
}

/// Selects recovery intent only after read-only native/path/ACL/custody checks.
/// Never authorizes file deletion/publication, native open or service readiness;
/// the migrator must perform all copy-based semantic checks from the contract.
MigrationAction assessMigration({
  required int dbSchema,
  required MigrationManifest manifest,
  required StagePresence stage,
  required MigrationJournal? journal,
  required String dbDigest,
  required String manifestDigest,
  required String keyWrapperDigest,
  String? backupDigest,
}) {
  _digest(dbDigest);
  _digest(manifestDigest);
  _digest(keyWrapperDigest);
  if (backupDigest != null) _digest(backupDigest);
  if (dbSchema != 1 && dbSchema != 2) _incompatible();
  if ((stage == StagePresence.journal) != (journal != null)) _blocked();
  if (stage != StagePresence.journal && backupDigest != null) _blocked();
  if (journal != null &&
      (journal.workspaceId != manifest.workspaceId ||
          journal.receiptKeyId != manifest.receiptKeyId ||
          journal.ownerSid != manifest.ownerSid))
    _blocked();
  if (dbSchema == 1 && manifest.schema == 2) _incompatible();
  if (dbSchema == 1) {
    if (journal == null) return MigrationAction.prepare;
    if (dbDigest != journal.sourceDbDigest ||
        manifestDigest != journal.sourceManifestDigest ||
        keyWrapperDigest != journal.sourceKeyWrapperDigest)
      _blocked();
    return MigrationAction.rebuildStage;
  }
  if (journal == null) {
    if (manifest.schema != 2) _incompatible();
    return MigrationAction.normalOpen;
  }
  if (journal.phase != MigrationPhase.prepared) _incompatible();
  if (dbDigest != journal.targetDbDigest ||
      keyWrapperDigest != journal.sourceKeyWrapperDigest ||
      (backupDigest != null && backupDigest != journal.sourceDbDigest))
    _blocked();
  if (manifest.schema == 1) {
    if (backupDigest == null || manifestDigest != journal.sourceManifestDigest)
      _blocked();
    return MigrationAction.verifyTargetThenPublishManifest;
  }
  if (manifestDigest != journal.targetManifestDigest) _blocked();
  return MigrationAction.verifyTargetThenCleanup;
}
