import 'dart:convert';

import 'package:serverdeck_locald/storage/native_registry.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:test/test.dart';

Map<String, List<int>> registry() => {
  for (final schema in workspaceSchemas)
    schema.name: utf8.encode(
      jsonEncode({
        'name': schema.name,
        'embedded': false,
        'properties': [
          if (schema.indexes.isNotEmpty)
            {'name': 'entityId', 'type': 'String', 'target': null},
          {'name': 'payload', 'type': 'String', 'target': null},
        ],
        'indexes': [
          if (schema.indexes.isNotEmpty)
            {
              'name': 'entityId',
              'properties': [
                {'name': 'entityId', 'type': 'Hash', 'caseSensitive': true},
              ],
              'unique': true,
              'replace': false,
            },
        ],
        'links': [],
        'version': 2,
      }),
    ),
};

void main() {
  test('exact pinned ordinary registry is accepted without changing input', () {
    final documents = registry();
    final before = jsonEncode(documents);
    validateNativeRegistry(documents);
    expect(jsonEncode(documents), before);
  });

  test(
    'well-formed foreign schemas and changed index contract are incompatible',
    () {
      for (final change in <void Function(Map<String, List<int>>)>[
        (r) => r.remove('StoredWorkspace'),
        (r) => r['Foreign'] = utf8.encode('{}'),
        (r) => r['StoredProfile'] = utf8.encode(
          utf8
              .decode(r['StoredProfile']!)
              .replaceFirst('"replace":false', '"replace":true'),
        ),
        (r) => r['StoredSettings'] = utf8.encode(
          utf8
              .decode(r['StoredSettings']!)
              .replaceFirst('"version":2', '"version":3'),
        ),
        (r) => r['StoredCredential'] = utf8.encode(
          utf8
              .decode(r['StoredCredential']!)
              .replaceFirst('"type":"String"', '"type":"Long"'),
        ),
      ]) {
        final documents = registry();
        change(documents);
        expect(
          () => validateNativeRegistry(documents),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'safe code',
              'INCOMPATIBLE',
            ),
          ),
        );
      }
    },
  );

  test(
    'invalid JSON, duplicate keys, UTF8 and oversized schemas are blocked',
    () {
      for (final bytes in <List<int>>[
        utf8.encode('{"name":"StoredWorkspace","name":"other"}'),
        utf8.encode('{broken-private-marker'),
        [0xff],
        List.filled(16 * 1024 + 1, 32),
      ]) {
        final documents = registry()..['StoredWorkspace'] = bytes;
        expect(
          () => validateNativeRegistry(documents),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'safe code',
              'STORAGE_BLOCKED',
            ),
          ),
        );
      }
    },
  );
}
