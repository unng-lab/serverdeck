import 'package:serverdeck_locald/automation/profile_commands.dart';
import 'package:test/test.dart';

const request = '12345678-1234-4234-8234-123456789abc';
const profile = '22345678-1234-4234-8234-123456789abc';
Map<String, Object?> body() => {
  'format': 1,
  'environment': 'ubuntu24.04-amd64-systemd',
  'parameters': <String, Object?>{},
  'steps': <Object?>[],
};

void main() {
  test('create captures immutable body and explicit default description', () {
    final raw = body();
    final command = AutomationProfileCommand.parse('profile.create', {
      'requestId': request,
      'name': 'Public profile',
      'body': raw,
    });
    (raw['steps'] as List).add({'kind': 'shell'});
    expect(command.description, '');
    expect(command.body!.toJson()['steps'], isEmpty);
    final canonical = command.canonicalRequest(null);
    (canonical['params'] as Map)['name'] = 'Changed';
    expect(
      (command.canonicalRequest(null)['params'] as Map)['name'],
      'Public profile',
    );
    expect(command.canonicalRequest(null).toString(), isNot(contains(request)));
  });
  test(
    'update omissions remain distinct from explicitly supplied metadata',
    () {
      final arguments = {
        'requestId': request,
        'profileId': profile,
        'expectedRevision': 1,
        'body': body(),
      };
      final missing = AutomationProfileCommand.parse(
        'profile.update',
        arguments,
      );
      final present = AutomationProfileCommand.parse('profile.update', {
        ...arguments,
        'description': '',
      });
      expect(
        (missing.canonicalRequest(null)['params'] as Map).containsKey(
          'description',
        ),
        false,
      );
      expect(
        (present.canonicalRequest(null)['params'] as Map)['description'],
        '',
      );
      expect(missing.canonicalRequest(profile)['originGrantId'], profile);
    },
  );
  test('archive is a strict body-free CAS command', () {
    final args = {
      'requestId': request,
      'profileId': profile,
      'expectedRevision': 20,
    };
    final command = AutomationProfileCommand.parse('profile.archive', args);
    expect(command.body, null);
    expect(command.expectedRevision, 20);
    for (final invalid in [
      {...args, 'expectedRevision': 20.0},
      {...args, 'body': body()},
      {...args, 'originGrantId': profile},
      {...args, 'expectedRevision': 0},
    ]) {
      expect(
        () => AutomationProfileCommand.parse('profile.archive', invalid),
        throwsFormatException,
      );
    }
  });
  test('invalid text, author overrides and AST cannot be normalized into admission', () {
    for (final invalid in [
      {'requestId': request, 'name': 'e\u0301', 'body': body()},
      {
        'requestId': request,
        'name': 'Name',
        'body': {...body(), 'format': 1.0},
      },
      {
        'requestId': request,
        'name': 'Name',
        'body': body(),
        'authorGrantId': profile,
      },
    ]) {
      expect(
        () => AutomationProfileCommand.parse('profile.create', invalid),
        throwsFormatException,
      );
    }
  });
}
