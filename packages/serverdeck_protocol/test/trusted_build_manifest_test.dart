import 'package:serverdeck_protocol/build_manifest.dart';
import 'package:test/test.dart';

import 'mcp_build_manifest_test.dart' as mcp;

Map<String, Object?> fixture() => mcp.fixture()
  ..['format'] = 3
  ..['workspaceSchema'] = 3;

void main() {
  test('trusted manifest is explicit format3/schema3 and immutable', () {
    final source = fixture();
    final manifest = TrustedBuildManifest.fromJson(source);
    expect(manifest.workspaceSchema, 3);
    expect(manifest.apiMajor, 1);
    expect(manifest.apiMinor, 1);
    expect(manifest.sha256.length, 4);
    expect(manifest.buildId, source['buildId']);
    (source['sha256'] as Map)['mcp.exe'] = 'd' * 64;
    source['appRoot'] = 'changed';
    expect(manifest.sha256['mcp.exe'], 'c' * 64);
    expect(manifest.appRoot, r'C:\synthetic\bundle');
    expect(() => manifest.sha256.clear(), throwsUnsupportedError);
    expect(() => McpBuildManifest.fromJson(fixture()), throwsFormatException);
    expect(() => BuildManifest.fromJson(fixture()), throwsFormatException);
    expect(
      () => TrustedBuildManifest.fromJson(mcp.fixture()),
      throwsFormatException,
    );
  });

  test('trusted parser retains exact fields versions artifacts and build selection', () {
    for (final name in fixture().keys) {
      expect(
        () => TrustedBuildManifest.fromJson(fixture()..remove(name)),
        throwsFormatException,
      );
    }
    for (final change in <Map<String, Object?>>[
      {'format': 1},
      {'format': 2},
      {'format': 3.0},
      {'workspaceSchema': 2},
      {'workspaceSchema': 3.0},
      {'apiMajor': 2},
      {'apiMinor': 2},
      {'apiMinor': 1.0},
      {'product': 'other'},
      {'role': 'locald'},
      {'testOnly': true},
      {'testOnly': 0},
      {'configuration': 'Release'},
      {'buildId': 'unverified'},
      {'appRoot': ''},
      {'appRoot': 'a' * 32768},
      {'appRoot': 'a\u0000b'},
      {
        'sha256': {'mcp.exe': 'c' * 64},
      },
      {
        'sha256': {
          ...(fixture()['sha256'] as Map<String, Object?>),
          'extra.exe': 'c' * 64,
        },
      },
      {
        'sha256': {
          ...(fixture()['sha256'] as Map<String, Object?>),
          'mcp.exe': 'C' * 64,
        },
      },
    ]) {
      expect(
        () => TrustedBuildManifest.fromJson({...fixture(), ...change}),
        throwsFormatException,
      );
    }
    expect(
      TrustedBuildManifest.fromJson(
        fixture()..['testOnly'] = true,
        testOnly: true,
      ).testOnly,
      isTrue,
    );
    expect(
      () => TrustedBuildManifest.fromJson(fixture(), testOnly: true),
      throwsFormatException,
    );
  });
}
