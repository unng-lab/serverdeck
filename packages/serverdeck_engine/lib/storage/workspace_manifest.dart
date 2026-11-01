import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/validation.dart';

Never _blocked() => throw StateError('STORAGE_BLOCKED');
Never _incompatible() => throw StateError('INCOMPATIBLE');

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

/// Exact target workspace identity. Parsing never opens, upgrades, or rewrites data.
final class WorkspaceManifest {
  WorkspaceManifest._(this.workspaceId, this.receiptKeyId, this.ownerSid);
  factory WorkspaceManifest.fromJson(Map<String, Object?> value) {
    _document(value);
    if (value['schema'] is! int ||
        value['schema'] != 3 ||
        value['format'] is! int ||
        value['format'] != 3)
      _incompatible();
    _fields(value, {
      'product',
      'schema',
      'format',
      'workspaceId',
      'receiptKeyId',
      'ownerSid',
    });
    if (value['product'] != 'serverdeck-next') _blocked();
    return WorkspaceManifest._(
      _uuid(value['workspaceId']),
      _uuid(value['receiptKeyId']),
      _sid(value['ownerSid']),
    );
  }
  final String workspaceId, receiptKeyId, ownerSid;
  int get schema => 3;
  Map<String, Object?> toJson() => {
    'product': 'serverdeck-next',
    'format': 3,
    'schema': 3,
    'workspaceId': workspaceId,
    'receiptKeyId': receiptKeyId,
    'ownerSid': ownerSid,
  };
}
