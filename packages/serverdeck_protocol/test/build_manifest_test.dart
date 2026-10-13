import 'package:serverdeck_protocol/build_manifest.dart';
import 'package:test/test.dart';

Map<String, Object?> fixture() => {
  'format': 1,
  'buildId': '${'a' * 40}+Debug+${'b' * 64}',
  'configuration': 'Debug',
  'testOnly': false,
  'appRoot': r'C:\synthetic\bundle',
  'sha256': {
    for (final name in ['serverdeck.exe', 'locald.exe', 'libisar.dll'])
      name: 'c' * 64,
  },
};

void main() {
  test('bundle manifest uses exact version, build identity and file set', () {
    final source = fixture();
    final manifest = BuildManifest.fromJson(source);
    expect(manifest.configuration, 'Debug');
    expect(manifest.testOnly, isFalse);
    (source['sha256'] as Map)['locald.exe'] = 'd' * 64;
    expect(manifest.sha256['locald.exe'], 'c' * 64);
    expect(
      () => manifest.sha256['locald.exe'] = 'd' * 64,
      throwsUnsupportedError,
    );
    for (final invalid in [
      fixture()..['format'] = 1.0,
      fixture()..['format'] = 2,
      fixture()..['extra'] = true,
      fixture()..['testOnly'] = true,
      fixture()..['configuration'] = 'Release',
      fixture()..['buildId'] = 'unverified',
      fixture()..['sha256'] = {'locald.exe': 'c' * 64},
      fixture()
        ..['sha256'] = {
          for (final name in ['serverdeck.exe', 'locald.exe', 'libisar.dll'])
            name: 'C' * 64,
        },
    ]) {
      expect(() => BuildManifest.fromJson(invalid), throwsFormatException);
    }
    final testBundle = fixture()..['testOnly'] = true;
    expect(BuildManifest.fromJson(testBundle, testOnly: true).testOnly, isTrue);
    expect(
      () => BuildManifest.fromJson(fixture(), testOnly: true),
      throwsFormatException,
    );
  });
}
