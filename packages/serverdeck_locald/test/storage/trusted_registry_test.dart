import 'dart:convert';

import 'package:serverdeck_locald/storage/automation_records.dart';
import 'package:serverdeck_locald/storage/host_trust_records.dart';
import 'package:serverdeck_locald/storage/native_registry.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:test/test.dart';

import 'automation_registry_test.dart' as fixture;

void main() {
  test('only explicit trusted preflight recognizes complete schema1/2/3', () {
    for (final (schemas, version) in [
      (workspaceSchemas, 1),
      (automationWorkspaceSchemas, 2),
      (trustedWorkspaceSchemas, 3),
    ]) {
      final documents = fixture.registry(schemas);
      final before = jsonEncode(documents);
      expect(recognizeTrustedNativeRegistry(documents), version);
      expect(jsonEncode(documents), before);
    }
    final documents = fixture.registry(trustedWorkspaceSchemas);
    expect(() => recognizeNativeRegistry(documents), throwsStateError);
    expect(() => validateNativeRegistry(documents), throwsStateError);
  });

  test('partial/mixed registries and altered trust schema never fall back', () {
    for (final mutate in <void Function(Map<String, List<int>>)>[
      (r) => r.remove('StoredAutomationJob'),
      (r) => r['Foreign'] = utf8.encode('{}'),
      (r) => r['StoredHostTrust'] = utf8.encode(
        utf8
            .decode(r['StoredHostTrust']!)
            .replaceFirst('"replace":false', '"replace":true'),
      ),
      (r) => r['StoredHostTrust'] = utf8.encode(
        utf8
            .decode(r['StoredHostTrust']!)
            .replaceFirst('"caseSensitive":true', '"caseSensitive":false'),
      ),
      (r) => r['StoredHostTrust'] = utf8.encode(
        utf8
            .decode(r['StoredHostTrust']!)
            .replaceFirst('"type":"String"', '"type":"Long"'),
      ),
    ]) {
      final documents = fixture.registry(trustedWorkspaceSchemas);
      mutate(documents);
      expect(
        () => recognizeTrustedNativeRegistry(documents),
        throwsA(
          isA<StateError>().having((e) => e.message, 'code', 'INCOMPATIBLE'),
        ),
      );
    }
    final mixed = fixture.registry(workspaceSchemas)
      ..addAll(fixture.registry([StoredHostTrustSchema]));
    expect(() => recognizeTrustedNativeRegistry(mixed), throwsStateError);
  });

  test('malformed bytes take precedence over unknown or incomplete names', () {
    final documents = fixture.registry(trustedWorkspaceSchemas)
      ..['Foreign'] = utf8.encode('{private-marker');
    expect(
      () => recognizeTrustedNativeRegistry(documents),
      throwsA(
        isA<StateError>().having((e) => e.message, 'code', 'STORAGE_BLOCKED'),
      ),
    );
  });
}
