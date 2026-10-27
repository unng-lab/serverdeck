import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:test/test.dart';

const hash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Map<String, Object?> recipe() => {
  'format': 1,
  'id': 'postgresql16',
  'version': '16.10',
  'revision': 1,
  'environment': 'ubuntu24.04-amd64-systemd',
  'packagePins': [
    <String, Object?>{
      'name': 'postgresql-16',
      'architecture': 'amd64',
      'version': '16.10-1',
      'sha256': hash,
    },
    <String, Object?>{
      'name': 'postgresql-common',
      'architecture': 'all',
      'version': '257',
      'sha256': hash,
    },
  ],
  'dependencyTransactionDigest': hash,
  'repositoryFingerprints': ['a' * 40],
  'aptIndexDigests': [hash],
  'expectedAbsentPaths': [
    '/etc/postgresql/16/main',
    '/var/lib/postgresql/16/main',
  ],
  'ownedResources': ['postgresql.service', 'postgresql.settings'],
  'prechecks': ['fresh_install', 'packages_qualified'],
  'postchecks': ['local_sql', 'packages_exact'],
  'licenseNotices': ['PostgreSQL License\nPublic notice'],
};

Future<Map<String, Object?>> signed(Map<String, Object?> value) async {
  final result = jsonDecode(jsonEncode(value)) as Map<String, Object?>;
  result.remove('digest');
  final digest = await Sha256().hash(StrictCodec().canonical(result));
  result['digest'] = digest.bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return result;
}

void main() {
  test('descriptor roundtrip binds explicit product version and exact package pins', () async {
    final input = await signed(recipe());
    final record = await QualifiedRecipeDescriptor.fromJson(input);
    expect(record.toJson(), input);
    expect(record.id, 'postgresql16');
    expect(record.version, '16.10');
    expect(
      record.matchesSelection(recipeDigest: record.digest, version: '16.10'),
      isTrue,
    );
    expect(
      record.matchesSelection(recipeDigest: record.digest, version: '16.10-1'),
      isFalse,
    );
    expect(
      record.matchesSelection(recipeDigest: hash, version: '16.10'),
      isFalse,
    );
    final changed = jsonDecode(jsonEncode(input)) as Map<String, Object?>;
    changed['version'] = '16.11';
    expect(QualifiedRecipeDescriptor.fromJson(changed), throwsFormatException);
    final clickhouse = recipe()
      ..['id'] = 'clickhouse'
      ..['version'] = '25.8.1';
    clickhouse['ownedResources'] = [
      'clickhouse.settings',
      'clickhouse.service',
    ];
    expect(
      (await QualifiedRecipeDescriptor.fromJson(await signed(clickhouse))).id,
      'clickhouse',
    );
  });

  test(
    'input snapshot precedes async hashing and output cannot mutate descriptor',
    () async {
      final input = await signed(recipe());
      final expected = jsonDecode(jsonEncode(input));
      final pending = QualifiedRecipeDescriptor.fromJson(input);
      input['version'] = 'attacker';
      ((input['packagePins'] as List).first as Map)['version'] = 'attacker';
      final record = await pending;
      expect(record.toJson(), expected);
      final output = record.toJson();
      (output['ownedResources'] as List).clear();
      expect(record.toJson(), expected);
      expect(() => record.ownedResources.clear(), throwsUnsupportedError);
    },
  );

  test(
    'closed shapes, exact strings, limits and unsafe catalog metadata rejected',
    () async {
      final mutations = <void Function(Map<String, Object?>)>[
        (v) => v['extra'] = true,
        (v) => v.remove('version'),
        (v) => v['id'] = 'mysql',
        (v) => v['version'] = 'LATEST',
        (v) => v['version'] = 'e\u0301',
        (v) => v['version'] = '{{version}}',
        (v) => v['version'] = 'private\u0085text',
        (v) => v['revision'] = 0,
        (v) => v['environment'] = 'ubuntu22.04-amd64-systemd',
        (v) => v['packagePins'] = [],
        (v) => (v['packagePins'] as List).add((v['packagePins'] as List).first),
        (v) =>
            ((v['packagePins'] as List).first as Map)['architecture'] = 'arm64',
        (v) => ((v['packagePins'] as List).first as Map)['name'] = 'PostgreSQL',
        (v) => ((v['packagePins'] as List).first as Map)['version'] = 'latest',
        (v) => ((v['packagePins'] as List).first as Map)['sha256'] = 'A' * 64,
        (v) => ((v['packagePins'] as List).first as Map)['url'] =
            'https://example.org/',
        (v) => v['repositoryFingerprints'] = ['g' * 40],
        (v) => v['aptIndexDigests'] = [hash, hash],
        (v) => v['expectedAbsentPaths'] = ['/etc/../tmp'],
        (v) => v['expectedAbsentPaths'] = ['/etc//x'],
        (v) => v['expectedAbsentPaths'] = ['relative'],
        (v) => v['expectedAbsentPaths'] = ['/etc/{{x}}'],
        (v) => v['expectedAbsentPaths'] = ['/etc\\x'],
        (v) => v['ownedResources'] = ['system.motd', 'postgresql.service'],
        (v) =>
            v['ownedResources'] = ['postgresql.service', 'postgresql.service'],
        (v) => v['prechecks'] = ['RunShell'],
        (v) => v['postchecks'] = [],
        (v) => v['licenseNotices'] = ['x' * 2001],
        (v) => v['licenseNotices'] = ['{{execute}}'],
        (v) => v['dependencyTransactionDigest'] = null,
      ];
      for (final mutate in mutations) {
        final input = recipe();
        mutate(input);
        final document = await signed(input);
        await expectLater(
          QualifiedRecipeDescriptor.fromJson(document),
          throwsFormatException,
        );
      }
      final nonInteger = await signed(recipe())
        ..['format'] = 1.0;
      await expectLater(
        QualifiedRecipeDescriptor.fromJson(nonInteger),
        throwsFormatException,
      );
    },
  );
}
