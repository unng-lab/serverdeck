import 'dart:convert';

import 'package:serverdeck_protocol/codec.dart';

import 'records.dart';

/// Validates native _info documents before the caller may open Isar.
/// This primitive does not traverse an MDBX file or authorize writable open.
void validateNativeRegistry(Map<String, List<int>> documents) {
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
  if (decoded.length != workspaceSchemas.length ||
      workspaceSchemas.any((schema) => !decoded.containsKey(schema.name))) {
    throw StateError('INCOMPATIBLE');
  }
  for (final schema in workspaceSchemas) {
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
