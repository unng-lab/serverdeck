import 'dart:convert';

import 'package:serverdeck_protocol/build_manifest.dart';
import 'package:test/test.dart';

Map<String, Object?> bundle({bool executor = false}) => {
  'format': 4,
  'product': 'serverdeck-next',
  'buildId': '${'a' * 40}+Release+${'b' * 64}',
  'configuration': 'Release',
  'testOnly': false,
  'appRoot': r'C:\unit\app',
  'apiMajor': 1,
  'apiMinor': 1,
  'workspaceSchema': 3,
  'sha256': <String, Object?>{
    'serverdeck.exe': 'c' * 64,
    'libisar.dll': 'd' * 64,
    if (executor) 'executor-release.json': 'e' * 64,
  },
};
Matcher invalid() => throwsA(
  isA<FormatException>()
      .having(
        (error) => error.message,
        'safe code',
        'INVALID_EMBEDDED_BUILD_MANIFEST',
      )
      .having((error) => error.source, 'private input is not retained', isNull),
);

void main() {
  test('format4 retains schema3 and exactly one executable with optional executor metadata', () {
    for (final executor in [false, true]) {
      final value = bundle(executor: executor);
      final manifest = EmbeddedBuildManifest.fromJson(value);
      expect(manifest.format, 4);
      expect(manifest.workspaceSchema, 3);
      expect(manifest.apiMajor, 1);
      expect(manifest.apiMinor, 1);
      expect(manifest.toJson(), value);
      expect(manifest.sha256.keys.where((name) => name.endsWith('.exe')), [
        'serverdeck.exe',
      ]);
    }
  });

  test('old formats and schema selectors have no fallback', () {
    for (final format in [1, 2, 3, 5, 4.0, '4', null]) {
      expect(
        () => EmbeddedBuildManifest.fromJson({...bundle(), 'format': format}),
        invalid(),
      );
    }
    for (final schema in [1, 2, 4, 3.0, '3']) {
      expect(
        () => EmbeddedBuildManifest.fromJson({
          ...bundle(),
          'workspaceSchema': schema,
        }),
        invalid(),
      );
    }
    expect(
      () => EmbeddedBuildManifest.fromJson({...bundle(), 'apiMajor': 2}),
      invalid(),
    );
    expect(
      () => EmbeddedBuildManifest.fromJson({...bundle(), 'apiMinor': 0}),
      invalid(),
    );
  });

  test('closed artifact and metadata sets refuse legacy executables and injected roles', () {
    for (final name in [
      'locald.exe',
      'mcp.exe',
      '../serverdeck.exe',
      'ServerDeck.exe',
      'other.dll',
    ]) {
      final value = bundle();
      (value['sha256'] as Map)[name] = 'f' * 64;
      expect(() => EmbeddedBuildManifest.fromJson(value), invalid());
    }
    expect(
      () => EmbeddedBuildManifest.fromJson({...bundle(), 'role': 'owner'}),
      invalid(),
    );
    final missing = bundle()..remove('testOnly');
    expect(() => EmbeddedBuildManifest.fromJson(missing), invalid());
    final missingApp = bundle();
    (missingApp['sha256'] as Map).remove('serverdeck.exe');
    expect(() => EmbeddedBuildManifest.fromJson(missingApp), invalid());
  });

  test('hashes are captured privately and exported copies cannot replace verified metadata', () {
    final value = bundle(executor: true), expected = bundle(executor: true);
    final manifest = EmbeddedBuildManifest.fromJson(value);
    (value['sha256'] as Map)['serverdeck.exe'] = '0' * 64;
    value['buildId'] = 'changed';
    expect(manifest.toJson(), expected);
    expect(() => manifest.sha256.clear(), throwsUnsupportedError);
    (manifest.toJson()['sha256'] as Map).clear();
    expect(manifest.toJson(), expected);
  });

  test('configuration binding, hash syntax and Unicode failures expose only a fixed category', () {
    for (final change in <Map<String, Object?>>[
      {'configuration': 'Debug'},
      {'buildId': 'private-build-path'},
      {'product': 'other'},
      {'appRoot': ''},
      {'appRoot': 'private\u0000path'},
      {'appRoot': String.fromCharCode(0xd800)},
    ]) {
      expect(
        () => EmbeddedBuildManifest.fromJson({...bundle(), ...change}),
        invalid(),
      );
    }
    for (final hash in ['A' * 64, 'c' * 63, true, null]) {
      final value = bundle();
      (value['sha256'] as Map)['serverdeck.exe'] = hash;
      expect(() => EmbeddedBuildManifest.fromJson(value), invalid());
    }
    final debug = bundle()
      ..['configuration'] = 'Debug'
      ..['buildId'] = '${'a' * 40}+Debug+${'b' * 64}';
    expect(EmbeddedBuildManifest.fromJson(debug).configuration, 'Debug');
  });

  test('testOnly requires explicit caller intent instead of trusting the input flag', () {
    final value = bundle()..['testOnly'] = true;
    expect(() => EmbeddedBuildManifest.fromJson(value), invalid());
    expect(
      EmbeddedBuildManifest.fromJson(value, testOnly: true).testOnly,
      isTrue,
    );
    expect(
      () => EmbeddedBuildManifest.fromJson(bundle(), testOnly: true),
      invalid(),
    );
  });

  test('raw JSON byte limit admits exactly16KiB and refuses overflow including Unicode', () {
    final value = bundle()..['appRoot'] = 'C:/';
    final padding = 16 * 1024 - utf8.encode(jsonEncode(value)).length;
    value['appRoot'] = 'C:/${'x' * padding}';
    expect(utf8.encode(jsonEncode(value)), hasLength(16 * 1024));
    expect(EmbeddedBuildManifest.fromJson(value).appRoot, value['appRoot']);
    expect(
      () => EmbeddedBuildManifest.fromJson({
        ...value,
        'appRoot': '${value['appRoot']}x',
      }),
      invalid(),
    );
    expect(
      () => EmbeddedBuildManifest.fromJson({
        ...bundle(),
        'appRoot': 'C:/${'Ж' * 9000}',
      }),
      invalid(),
    );
  });
}
