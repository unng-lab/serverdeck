import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/wire.dart';
import 'package:test/test.dart';

Map<String, Object?> profile() => {
  'id': '10000000-0000-4000-8000-000000000001',
  'revision': '3',
  'name': 'Server',
  'address': 'example.test',
  'port': 22,
  'sshUser': 'user',
  'tags': ['test'],
  'credentialRevision': '1',
  'connectionRevision': '1',
  'trustRevision': '2',
  'createdAt': '2026-10-22T00:00:00.000Z',
  'updatedAt': '2026-10-22T00:00:01.000Z',
  'credential': {'kind': 'none', 'configured': false},
};

Map<String, Object?> result(String method, Map<String, Object?> item) => {
  'storeRevision': '3',
  if (method == 'profiles.get') 'profile': item else 'profiles': [item],
};

void main() {
  for (final method in ['profiles.get', 'profiles.list']) {
    test('$method preserves schema3 counters and freezes the whole result', () {
      for (final counters in <Map<String, Object?>>[
        {},
        {'trustRevision': '3'},
        {'credentialRevision': '3'},
        {'connectionRevision': '3', 'trustRevision': '3'},
        {
          'revision': '9223372036854775807',
          'connectionRevision': '9223372036854775806',
          'trustRevision': '9223372036854775807',
          'credentialRevision': '9223372036854775807',
        },
      ]) {
        final item = {...profile(), ...counters};
        final input = result(method, item);
        input['storeRevision'] = item['revision'];
        final before = StrictCodec().encode(input);
        final captured = captureTrustedMethodResult(method, input);
        expect(StrictCodec().encode(captured), before);
        item['trustRevision'] = '1';
        (item['tags'] as List).add('later');
        (item['credential'] as Map)['configured'] = true;
        expect(StrictCodec().encode(captured), before);
        expect(() => captured['storeRevision'] = '9', throwsUnsupportedError);
        final saved = method == 'profiles.get'
            ? captured['profile'] as Map
            : (captured['profiles'] as List).single as Map;
        expect(() => saved['revision'] = '9', throwsUnsupportedError);
        expect(() => (saved['tags'] as List).add('x'), throwsUnsupportedError);
      }
    });

    test('$method refuses impossible ordered counters without changing legacy', () {
      for (final patch in <Map<String, Object?>>[
        {'connectionRevision': '3'},
        {'trustRevision': '4'},
        {'credentialRevision': '4'},
        {
          'revision': '9007199254740993',
          'connectionRevision': '9007199254740993',
          'trustRevision': '9007199254740992',
        },
      ]) {
        final input = result(method, {...profile(), ...patch});
        // The existing codec has never imposed these relations. Keep it intact.
        validateMethodResult(method, input);
        expect(
          () => captureTrustedMethodResult(method, input),
          throwsFormatException,
        );
      }
    });

    test(
      '$method retains existing exact public shape and field validation',
      () {
        for (final patch in <Map<String, Object?>>[
          {'revision': '0'},
          {'trustRevision': '9223372036854775808'},
          {'credentialRevision': '01'},
          {'connectionRevision': 1},
          {'name': ' Server '},
          {'port': 0},
          {
            'credential': {'kind': 'password', 'configured': false},
          },
          {'secret': 'unrecognized'},
        ]) {
          expect(
            () => captureTrustedMethodResult(
              method,
              result(method, {...profile(), ...patch}),
            ),
            throwsFormatException,
          );
        }
        expect(
          () => captureTrustedMethodResult(method, {
            ...result(method, profile()),
            'extra': true,
          }),
          throwsFormatException,
        );
      },
    );
  }
  test('trusted profile list still bounds and uniquely identifies rows', () {
    expect(
      captureTrustedMethodResult('profiles.list', {
        'storeRevision': '0',
        'profiles': <Object?>[],
      })['profiles'],
      isEmpty,
    );
    for (final items in [
      [profile(), profile()],
      List.generate(251, (_) => profile()),
    ]) {
      expect(
        () => captureTrustedMethodResult('profiles.list', {
          'storeRevision': '3',
          'profiles': items,
        }),
        throwsFormatException,
      );
    }
  });
}
