import 'package:serverdeck_locald/automation/profile_commands.dart';
import 'package:serverdeck_locald/automation/profiles.dart';
import 'package:test/test.dart';

Map<String, Object?> body() => {
  'format': 1,
  'environment': 'ubuntu24.04-amd64-systemd',
  'parameters': <String, Object?>{},
  'steps': <Object?>[],
};

void main() {
  test(
    'capture preserves rejected Unicode before deferred semantic parsing',
    () {
      final raw = <String, Object?>{
        'requestId': '12345678-1234-4234-8234-123456789abc',
        'name': 'e\u0301',
        'body': body(),
      };
      final captured = ProfileCatalogInput.capture('create', raw);
      expect(captured.params['name'], 'e\u0301');
      for (final input in [raw, captured.params]) {
        expect(
          () => AutomationProfileCommand.parse('profile.create', input),
          throwsFormatException,
        );
      }
      raw['name'] = 'Changed';
      (raw['body'] as Map)['steps'] = [
        {'kind': 'shell'},
      ];
      expect(captured.params['name'], 'e\u0301');
      expect((captured.params['body'] as Map)['steps'], isEmpty);
    },
  );
  test(
    'capture preserves body text, keys and numeric types without repair',
    () {
      final raw = {
        'body': {
          ...body(),
          'parameters': {
            'text': {'type': 'string', 'maxLength': 64, 'default': 'e\u0301'},
          },
        },
        'e\u0301': 1.0,
        'é': 1,
      };
      final captured = ProfileCatalogInput.capture('validate', raw).params;
      expect(captured['e\u0301'], isA<double>());
      expect(captured['é'], isA<int>());
      expect(((captured['body'] as Map)['parameters'] as Map)['text'], {
        'type': 'string',
        'maxLength': 64,
        'default': 'e\u0301',
      });
    },
  );
  test('capture retains bounded strict JSON syntax before author parsing', () {
    for (final input in <Map<String, Object?>>[
      {'text': '\ud800'},
      {'value': double.nan},
      {'value': Object()},
      {'value': 'a' * (256 * 1024)},
    ]) {
      expect(
        () => ProfileCatalogInput.capture('validate', input),
        throwsFormatException,
      );
    }
    Object? nested = null;
    for (var i = 0; i < 17; i++) {
      nested = [nested];
    }
    expect(
      () => ProfileCatalogInput.capture('validate', {'value': nested}),
      throwsFormatException,
    );
  });
}
