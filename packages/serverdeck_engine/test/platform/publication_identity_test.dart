import 'package:serverdeck_engine/platform/publication_identity.dart';
import 'package:test/test.dart';

const owner = 'S-1-5-21-1-2-3-1001';
const root = r'C:\unit\app';
const generation = '12345678-1234-4234-9234-123456789ad1';
PublicationIdentity identity({
  String sid = owner,
  String path = root,
  String id = generation,
}) => PublicationIdentity(ownerIdentity: sid, appRoot: path, generation: id);
Matcher failure() => throwsA(
  isA<StateError>().having((e) => e.message, 'safe code', 'UNAUTHORIZED'),
);

void main() {
  test(
    'existing publication namespace has a frozen independent SHA256 vector',
    () {
      final value = identity();
      expect(
        value.mutexName,
        r'Global\ServerDeckNext.v1.a241c1a26514b5b4f41071efcdf3fc6c2bdeec6335e84caa48efd6f1287bc641',
      );
      expect(value.poisonName, '${value.mutexName}.poison');
      expect(identity().mutexName, value.mutexName);
    },
  );
  test('owner root and generation each fence different kernel objects', () {
    final names = {
      identity().mutexName,
      identity(sid: 'S-1-5-21-1-2-3-1002').mutexName,
      identity(path: r'C:\unit\other').mutexName,
      identity(id: '12345678-1234-4234-9234-123456789ad2').mutexName,
    };
    expect(names, hasLength(4));
    expect(
      identity(path: 'C:\\unit\\e\u0301').mutexName,
      isNot(identity(path: 'C:\\unit\\é').mutexName),
    );
  });
  test('bounded wellformed metadata refuses separator and replacement collisions safely', () {
    for (final sid in [
      '',
      'a' * 4097,
      'bad\u0000owner',
      'bad\nowner',
      'bad\rowner',
      '\ud800',
    ]) {
      expect(() => identity(sid: sid), failure());
    }
    for (final path in [
      '',
      'a' * 32768,
      'bad\u0000root',
      'bad\nroot',
      'bad\rroot',
      '\udc00',
    ]) {
      expect(() => identity(path: path), failure());
    }
    expect(
      identity(sid: 'a' * 4096, path: 'b' * 32767).mutexName,
      startsWith(r'Global\ServerDeckNext.v1.'),
    );
  });
  test(
    'generation accepts only canonical UUIDv4 and cannot encode another tuple',
    () {
      for (final id in [
        '',
        '12345678-1234-1234-9234-123456789ad1',
        generation.toUpperCase(),
        '$generation\n',
      ]) {
        expect(() => identity(id: id), failure());
      }
    },
  );
}
