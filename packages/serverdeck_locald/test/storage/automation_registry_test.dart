import 'dart:convert';

import 'package:isar_community/isar.dart';
import 'package:serverdeck_locald/storage/automation_records.dart';
import 'package:serverdeck_locald/storage/native_registry.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:test/test.dart';

Map<String, List<int>> registry(List<CollectionSchema> schemas) => {
  for (final schema in schemas)
    schema.name: utf8.encode(
      jsonEncode({
        'name': schema.name,
        'embedded': false,
        'properties': [
          for (final field in schema.properties.values)
            {'name': field.name, 'type': 'String', 'target': null},
        ],
        'indexes': [
          for (final index in schema.indexes.values)
            {
              'name': index.name,
              'properties': [
                for (final field in index.properties)
                  {
                    'name': field.name,
                    'type': 'Hash',
                    'caseSensitive': field.caseSensitive,
                  },
              ],
              'unique': index.unique,
              'replace': index.replace,
            },
        ],
        'links': [],
        'version': 2,
      }),
    ),
};
void main() {
  test(
    'recognition accepts exact v1/v2 while original validator remains v1 only',
    () {
      final legacy = registry(workspaceSchemas),
          automation = registry(automationWorkspaceSchemas);
      expect(recognizeNativeRegistry(legacy), 1);
      expect(recognizeNativeRegistry(automation), 2);
      validateNativeRegistry(legacy);
      expect(() => validateNativeRegistry(automation), throwsStateError);
      expect(workspaceSchemas, hasLength(5));
      expect(automationOnlySchemas, hasLength(10));
    },
  );
  test('partial, foreign and altered indexes are incompatible without schema fallback', () {
    for (final mutate in <void Function(Map<String, List<int>>)>[
      (r) => r.remove('StoredAutomationJob'),
      (r) => r['Foreign'] = utf8.encode('{}'),
      (r) => r['StoredAutomationRevision'] = utf8.encode(
        utf8
            .decode(r['StoredAutomationRevision']!)
            .replaceFirst('"replace":false', '"replace":true'),
      ),
      (r) => r['StoredAutomationEvent'] = utf8.encode(
        utf8
            .decode(r['StoredAutomationEvent']!)
            .replaceFirst('"caseSensitive":true', '"caseSensitive":false'),
      ),
    ]) {
      final input = registry(automationWorkspaceSchemas);
      mutate(input);
      expect(
        () => recognizeNativeRegistry(input),
        throwsA(
          isA<StateError>().having((e) => e.message, 'code', 'INCOMPATIBLE'),
        ),
      );
    }
  });
  test('corruption still wins over unrelated unknown registry names', () {
    final input = registry(automationWorkspaceSchemas)
      ..['Foreign'] = utf8.encode('{private-marker');
    expect(
      () => recognizeNativeRegistry(input),
      throwsA(
        isA<StateError>().having((e) => e.message, 'code', 'STORAGE_BLOCKED'),
      ),
    );
  });
}
