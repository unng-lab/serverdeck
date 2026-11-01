import 'dart:convert';

import 'package:isar_community/isar.dart';
import 'package:serverdeck_protocol/codec.dart';

import 'package:serverdeck_engine/storage/host_trust_records.dart';

/// Exact target3 _info documents. No older registry is recognized and this
/// metadata check neither opens a database nor validates application rows.
int inspectNativeRegistry(Map<String, List<int>> documents) {
  _validateRegistry(_decode(documents), workspaceSchemas);
  return 3;
}

Map<String, Map<String, Object?>> _decode(Map<String, List<int>> documents) {
  final codec = StrictCodec();
  final decoded = <String, Map<String, Object?>>{};
  // Parse every document before compatibility comparison. Corruption must not
  // be hidden by an unrelated unknown collection name.
  for (final entry in documents.entries) {
    try {
      decoded[entry.key] = codec.decode(entry.value, maxBytes: 16 * 1024);
    } on FormatException {
      throw StateError('STORAGE_BLOCKED');
    }
  }
  return decoded;
}

bool _matches(
  Map<String, Map<String, Object?>> decoded,
  List<CollectionSchema> schemas,
) =>
    decoded.length == schemas.length &&
    schemas.every((schema) => decoded.containsKey(schema.name));

void _validateRegistry(
  Map<String, Map<String, Object?>> decoded,
  List<CollectionSchema> schemas,
) {
  if (!_matches(decoded, schemas)) {
    throw StateError('INCOMPATIBLE');
  }
  for (final schema in schemas) {
    final expected = <String, Object?>{
      'name': schema.name,
      'embedded': false,
      'properties': [
        for (final property in schema.properties.values)
          {'name': property.name, 'type': 'String', 'target': null},
      ],
      'indexes': [
        for (final index in schema.indexes.values)
          {
            'name': index.name,
            'properties': [
              for (final property in index.properties)
                {
                  'name': property.name,
                  'type': 'Hash',
                  'caseSensitive': property.caseSensitive,
                },
            ],
            'unique': index.unique,
            'replace': index.replace,
          },
      ],
      'links': [],
      'version': 2,
    };
    // Compare exact keys and list order as well as values, independent of JSON
    // object key order. Never normalize native schema names/properties via NFC.
    if (jsonEncode(_sorted(decoded[schema.name])) !=
        jsonEncode(_sorted(expected))) {
      throw StateError('INCOMPATIBLE');
    }
  }
}

Object? _sorted(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _sorted(value[key])};
  }
  if (value is List) return value.map(_sorted).toList();
  return value;
}
