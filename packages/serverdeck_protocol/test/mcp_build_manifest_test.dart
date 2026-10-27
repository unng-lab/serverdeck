import 'package:serverdeck_protocol/build_manifest.dart';
import 'package:test/test.dart';

Map<String, Object?> fixture() => {
  'format': 2,
  'product': 'serverdeck-next',
  'buildId': '${'a' * 40}+Debug+${'b' * 64}',
  'configuration': 'Debug',
  'testOnly': false,
  'appRoot': r'C:\synthetic\bundle',
  'apiMajor': 1,
  'apiMinor': 1,
  'workspaceSchema': 2,
  'sha256': {
    for (final name in [
      'serverdeck.exe',
      'locald.exe',
      'mcp.exe',
      'libisar.dll',
    ])
      name: 'c' * 64,
  },
};

void main() {
  test('MCP bundle is strict format2 API1.1 schema2 and immutable', () {
    final source = fixture();
    final parsed = McpBuildManifest.fromJson(source);
    expect(parsed.buildId, source['buildId']);
    expect(parsed.apiMajor, 1);
    expect(parsed.apiMinor, 1);
    expect(parsed.workspaceSchema, 2);
    (source['sha256'] as Map)['mcp.exe'] = 'd' * 64;
    source['appRoot'] = 'changed';
    expect(parsed.sha256['mcp.exe'], 'c' * 64);
    expect(parsed.appRoot, r'C:\synthetic\bundle');
    expect(() => parsed.sha256.clear(), throwsUnsupportedError);
    expect(() => BuildManifest.fromJson(fixture()), throwsFormatException);
    for (final field in fixture().keys) {
      expect(
        () => McpBuildManifest.fromJson(fixture()..remove(field)),
        throwsFormatException,
        reason: 'missing $field',
      );
    }
    for (final source in [
      fixture()..['format'] = 1,
      fixture()..['format'] = 2.0,
      fixture()..['apiMajor'] = 1.0,
      fixture()..['apiMinor'] = 1.0,
      fixture()..['workspaceSchema'] = 2.0,
      fixture()..['apiMajor'] = 2,
      fixture()..['apiMinor'] = 0,
      fixture()..['apiMinor'] = 2,
      fixture()..['workspaceSchema'] = 1,
      fixture()..['workspaceSchema'] = 3,
      fixture()..['product'] = 'other',
      fixture()..['role'] = 'owner',
      fixture()..['testOnly'] = true,
      fixture()..['testOnly'] = 0,
      fixture()..['configuration'] = 'Release',
      fixture()..['buildId'] = 'unverified',
      fixture()..['appRoot'] = '',
      fixture()..['appRoot'] = 'a' * 32768,
      fixture()..['appRoot'] = 'a\u0000b',
      fixture()..['sha256'] = {'mcp.exe': 'c' * 64},
      fixture()
        ..['sha256'] = {...(fixture()['sha256'] as Map), 'extra.exe': 'c' * 64},
      fixture()
        ..['sha256'] = {...(fixture()['sha256'] as Map), 'mcp.exe': 'C' * 64},
      fixture()
        ..['sha256'] = {...(fixture()['sha256'] as Map), 'mcp.exe': null},
    ]) {
      expect(() => McpBuildManifest.fromJson(source), throwsFormatException);
    }
  });

  test(
    'MCP test build selection is explicit and old manifest stays closed',
    () {
      expect(
        McpBuildManifest.fromJson(
          fixture()..['testOnly'] = true,
          testOnly: true,
        ).testOnly,
        isTrue,
      );
      expect(
        () => McpBuildManifest.fromJson(fixture(), testOnly: true),
        throwsFormatException,
      );
      final old = fixture()
        ..['format'] = 1
        ..remove('product')
        ..remove('apiMajor')
        ..remove('apiMinor')
        ..remove('workspaceSchema');
      (old['sha256'] as Map).remove('mcp.exe');
      expect(BuildManifest.fromJson(old).sha256.length, 3);
      expect(() => McpBuildManifest.fromJson(old), throwsFormatException);
    },
  );
}
