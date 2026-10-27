import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/validation.dart';

Never _blocked() => throw StateError('STORAGE_BLOCKED');

/// Immutable raw native row snapshot. No credential decrypt/re-encrypt here.
final class MigrationRow {
  const MigrationRow(this.nativeId, this.payload, {this.entityId});
  final int nativeId;
  final String payload;
  final String? entityId;
}

/// Binds exact old payload bytes and native/business IDs. The caller must first
/// run complete source/target row/reference/DPAPI validation on a protected copy.
/// This structural snapshot/digest is not a substitute for that semantic check.
final class MigrationRows {
  MigrationRows._(this._workspace, this._settings, this._groups);
  factory MigrationRows.capture({
    required int schema,
    required MigrationRow workspace,
    required MigrationRow settings,
    required List<MigrationRow> profiles,
    required List<MigrationRow> credentials,
    required List<MigrationRow> receipts,
  }) {
    if (schema != 1 && schema != 2) _blocked();
    var totalBytes = 0;
    Map<String, Object?> read(
      MigrationRow row,
      int bound, {
      bool singleton = false,
    }) {
      if (row.nativeId < 1 ||
          row.nativeId > 0x7fffffffffffffff ||
          (singleton && (row.nativeId != 1 || row.entityId != null)))
        _blocked();
      try {
        // Validate Unicode without replacing/normalizing raw persisted payload.
        StrictCodec().canonical(row.payload);
        final bytes = utf8.encode(row.payload);
        totalBytes += bytes.length;
        if (totalBytes > 64 * 1024 * 1024) _blocked();
        return StrictCodec().decode(bytes, maxBytes: bound);
      } on FormatException {
        _blocked();
      }
    }

    final metadata = read(workspace, 4096, singleton: true);
    try {
      requireFields(metadata, {
        'schemaVersion',
        'workspaceId',
        'receiptKeyId',
        'ownerSid',
        'storeRevision',
      });
      requireUuid(metadata['workspaceId']);
      requireUuid(metadata['receiptKeyId']);
      requireRevision(metadata['storeRevision'], allowZero: true);
    } on FormatException {
      _blocked();
    }
    if (metadata['schemaVersion'] is! int ||
        metadata['schemaVersion'] != schema ||
        metadata['ownerSid'] is! String ||
        !RegExp(r'^S-1-\d+(?:-\d+)+$').hasMatch(metadata['ownerSid'] as String))
      _blocked();
    metadata.remove('schemaVersion');
    read(settings, 4096, singleton: true);
    List<MigrationRow> group(
      List<MigrationRow> input,
      int limit,
      int bound,
      String idField,
    ) {
      if (input.length > limit) _blocked();
      final ids = <int>{};
      final entities = <String>{};
      final result = <MigrationRow>[];
      for (final row in input) {
        final parsed = read(row, bound);
        try {
          requireUuid(row.entityId);
        } on FormatException {
          _blocked();
        }
        if (!ids.add(row.nativeId) ||
            !entities.add(row.entityId!) ||
            parsed[idField] != row.entityId)
          _blocked();
        result.add(row);
      }
      result.sort((a, b) => a.nativeId.compareTo(b.nativeId));
      return List.unmodifiable(result);
    }

    final groups = <String, List<MigrationRow>>{
      'profiles': group(profiles, 250, 16 * 1024, 'id'),
      'credentials': group(credentials, 250, 512 * 1024, 'id'),
      'receipts': group(receipts, 10000, 4096, 'requestId'),
    };
    return MigrationRows._(
      Map.unmodifiable({
        'nativeId': workspace.nativeId,
        'payload': Map<String, Object?>.unmodifiable(metadata),
      }),
      settings,
      Map.unmodifiable(groups),
    );
  }

  final Map<String, Object?> _workspace;
  final MigrationRow _settings;
  final Map<String, List<MigrationRow>> _groups;

  /// Streams the exact canonical map in codepoint-key order. At most one row's
  /// bounded base64/canonical encoding is allocated in addition to the snapshot.
  String digest() {
    final sink = const DartSha256().newHashSink();
    final codec = StrictCodec();
    void text(String value) => sink.add(utf8.encode(value));
    Map<String, Object?> rowJson(MigrationRow row) => {
      'nativeId': row.nativeId,
      if (row.entityId != null) 'entityId': row.entityId,
      'payloadBase64': base64.encode(utf8.encode(row.payload)),
    };
    text('{');
    const names = [
      'credentials',
      'profiles',
      'receipts',
      'settings',
      'workspace',
    ];
    for (var i = 0; i < names.length; i++) {
      if (i != 0) text(',');
      final name = names[i];
      sink.add(codec.canonical(name));
      text(':');
      if (name == 'workspace') {
        sink.add(codec.canonical(_workspace));
      } else if (name == 'settings') {
        sink.add(codec.canonical(rowJson(_settings)));
      } else {
        text('[');
        final rows = _groups[name]!;
        for (var j = 0; j < rows.length; j++) {
          if (j != 0) text(',');
          sink.add(codec.canonical(rowJson(rows[j])));
        }
        text(']');
      }
    }
    text('}');
    sink.close();
    return sink
        .hashSync()
        .bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
