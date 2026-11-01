import 'package:serverdeck_windows/publication_binding.dart';
import 'package:test/test.dart';

const owner = 'S-1-5-21-1-2-3-1001';
const generation = '12345678-1234-4234-9234-123456789ad1';
String name(String root) => windowsPublicationIdentity(
  ownerIdentity: owner,
  appRoot: root,
  generation: generation,
).mutexName;

void main() {
  test(
    'same Windows copy has one mutex across drive/root case and normalization',
    () {
      expect(
        name(r'C:\UNIT\App'),
        r'Global\ServerDeckNext.v1.3f043f8a21b14b91be32bd332d5498d11848930f0e2f9d5c60c0dfcd985781af',
      );
      final expected = name(r'C:\App');
      for (final root in [
        r'c:\app',
        r'C:\APP',
        r'c:/App',
        r'C:\App\.',
        r'C:\other\..\APP',
      ]) {
        expect(name(root), expected);
        expect(
          windowsPublicationIdentity(
            ownerIdentity: owner,
            appRoot: root,
            generation: generation,
          ).poisonName,
          '$expected.poison',
        );
      }
      expect(name(r'C:\other'), isNot(expected));
    },
  );
  test('UNC host/share/root spelling follows the same Windows case policy', () {
    expect(name(r'\\SERVER\Share\App'), name(r'\\server\share\app'));
    expect(name(r'\\server\other\app'), isNot(name(r'\\server\share\app')));
  });
  test('relative and invalid Windows metadata cannot name a native gate', () {
    for (final root in ['', r'App', r'C:App', 'a' * 32768, 'C:\\bad\nroot']) {
      expect(
        () => name(root),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'safe code',
            'UNAUTHORIZED',
          ),
        ),
      );
    }
  });
}
