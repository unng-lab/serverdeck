import 'package:serverdeck_locald/mcp/grants.dart';
import 'package:test/test.dart';

const request = '10000000-0000-4000-8000-000000000001';
const grant = '10000000-0000-4000-8000-000000000002';
Map<String, Object?> create() => {
  'requestId': request,
  'grantId': grant,
  'label': 'Synthetic',
  'scopes': ['author'],
  'serverIds': <String>[],
};

void main() {
  test('owner grant input is strict, snapshotted and default-normalized', () {
    final input = create();
    final command = OwnerGrantCommand.parse('grant.create', input);
    (input['scopes'] as List).clear();
    input['label'] = 'changed';
    expect(command.label, 'Synthetic');
    expect(command.lifetimeSeconds, 28800);
    expect(command.policy!.scopes.single.name, 'author');
    expect(
      command.canonicalRequest,
      OwnerGrantCommand.parse('grant.create', {
        ...create(),
        'lifetimeSeconds': 28800,
      }).canonicalRequest,
    );
    expect(
      (command.canonicalRequest['params'] as Map).containsKey('requestId'),
      false,
    );
  });
  test(
    'rejects extras, null, coercion, duplicates and incomplete replacement',
    () {
      for (final input in [
        {...create(), 'originGrantId': null},
        {...create(), 'owner': true},
        {...create(), 'lifetimeSeconds': null},
        {...create(), 'lifetimeSeconds': 299},
        {...create(), 'lifetimeSeconds': 2592001},
        {...create(), 'lifetimeSeconds': 300.0},
        {
          ...create(),
          'scopes': ['author', 'author'],
        },
        {...create(), 'label': 'e\u0301'},
      ]) {
        expect(
          () => OwnerGrantCommand.parse('grant.create', input),
          throwsFormatException,
        );
      }
      expect(
        () => OwnerGrantCommand.parse('grant.replace', create()),
        throwsFormatException,
      );
      expect(
        () => OwnerGrantCommand.parse('grant.revoke', {
          ...create(),
          'expectedRevision': 1,
        }),
        throwsFormatException,
      );
      final revoke = OwnerGrantCommand.parse('grant.revoke', {
        'requestId': request,
        'grantId': grant,
        'expectedRevision': 1,
      });
      expect(revoke.policy, null);
    },
  );
}
