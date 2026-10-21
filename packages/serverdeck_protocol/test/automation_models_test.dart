import 'package:serverdeck_protocol/automation/models.dart';
import 'package:test/test.dart';

const profileA = '10000000-0000-4000-8000-000000000001';
const profileB = '10000000-0000-4000-8000-000000000002';
const bodyDigest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  Map<String, Object?> identity({String id = profileA, int revision = 1}) => {
    'profileId': id,
    'revision': revision,
    'bodyDigest': bodyDigest,
  };

  test(
    'execution authority distinguishes equal bodies across revisions and IDs',
    () {
      final original = AutomationRevisionKey.fromJson(identity());
      final same = AutomationRevisionKey.fromJson(identity());
      final newRevision = AutomationRevisionKey.fromJson(identity(revision: 2));
      final otherProfile = AutomationRevisionKey.fromJson(
        identity(id: profileB),
      );
      expect(original, same);
      expect(original.hashCode, same.hashCode);
      expect({original}.contains(newRevision), isFalse);
      expect({original}.contains(otherProfile), isFalse);
      expect(original.toJson(), identity());
    },
  );

  test(
    'authority keys reject incomplete, unknown and malformed identity fields',
    () {
      for (final input in <Map<String, Object?>>[
        {'bodyDigest': bodyDigest},
        {...identity(), 'revision': '1'},
        {...identity(), 'revision': 0},
        {...identity(), 'revision': 2147483648},
        {
          ...identity(),
          'profileId': profileA.toUpperCase().replaceFirst('1', 'A'),
        },
        {...identity(), 'bodyDigest': bodyDigest.toUpperCase()},
        {...identity(), 'extra': 'private-marker'},
      ]) {
        expect(
          () => AutomationRevisionKey.fromJson(input),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'author-only works in an empty workspace without implicit server rights',
    () {
      final author = GrantScopePolicy.fromJson({
        'scopes': ['author'],
        'serverIds': <String>[],
      });
      expect(author.allowsScope(McpScope.author), isTrue);
      expect(author.allowsScope(McpScope.read), isFalse);
      expect(author.allowsScope(McpScope.apply), isFalse);
      expect(author.allowsServer(profileA), isFalse);
      expect(author.toJson(), {
        'scopes': ['author'],
        'serverIds': <String>[],
      });
      expect(
        GrantScopePolicy.fromJson({
          'scopes': <String>[],
          'serverIds': <String>[],
        }).scopes,
        isEmpty,
      );
    },
  );

  test(
    'server scopes require explicit targets and their read/plan dependencies',
    () {
      for (final scopes in <List<String>>[
        ['logs'],
        ['plan'],
        ['apply'],
        ['read', 'apply'],
        ['plan', 'apply'],
      ]) {
        expect(
          () => GrantScopePolicy.fromJson({
            'scopes': scopes,
            'serverIds': [profileA],
          }),
          throwsFormatException,
        );
      }
      final policy = GrantScopePolicy.fromJson({
        'scopes': ['read', 'logs', 'plan', 'apply'],
        'serverIds': [profileA],
      });
      expect(policy.allowsServer(profileA), isTrue);
      expect(policy.allowsServer(profileB), isFalse);
      expect(policy.allowsScope(McpScope.author), isFalse);
      expect(policy.allowsScope(McpScope.apply), isTrue);
    },
  );

  test(
    'malformed, duplicate, excess or implicit target/scope grants fail closed',
    () {
      final tooMany = List.generate(
        251,
        (i) =>
            '10000000-0000-4000-8000-${i.toRadixString(16).padLeft(12, '0')}',
      );
      for (final input in <Map<String, Object?>>[
        {
          'scopes': ['read'],
          'serverIds': <String>[],
        },
        {
          'scopes': ['author'],
          'serverIds': [profileA],
        },
        {
          'scopes': <String>[],
          'serverIds': [profileA],
        },
        {
          'scopes': ['read'],
          'serverIds': [profileA, profileA],
        },
        {
          'scopes': ['read', 'read'],
          'serverIds': [profileA],
        },
        {
          'scopes': ['owner'],
          'serverIds': [profileA],
        },
        {
          'scopes': ['read'],
          'serverIds': ['*'],
        },
        {
          'scopes': ['read'],
          'serverIds': tooMany,
        },
        {
          'scopes': ['read'],
          'serverIds': [profileA],
          'secret': 'private-marker',
        },
        {
          'scopes': 'read',
          'serverIds': [profileA],
        },
      ]) {
        expect(() => GrantScopePolicy.fromJson(input), throwsFormatException);
      }
    },
  );

  test('validated policy cannot be broadened by mutating input or output', () {
    final scopes = ['read'];
    final targets = [profileA];
    final policy = GrantScopePolicy.fromJson({
      'scopes': scopes,
      'serverIds': targets,
    });
    scopes.add('apply');
    targets.add(profileB);
    expect(() => policy.scopes.add(McpScope.apply), throwsUnsupportedError);
    expect(() => policy.serverIds.add(profileB), throwsUnsupportedError);
    final copy = policy.toJson();
    (copy['serverIds'] as List).add(profileB);
    expect(policy.allowsServer(profileB), isFalse);
    expect(policy.allowsScope(McpScope.apply), isFalse);
  });

  test(
    'validation failure never includes private input in exception source',
    () {
      try {
        GrantScopePolicy.fromJson({
          'scopes': ['private-marker'],
          'serverIds': <String>[],
        });
        fail('Expected validation rejection');
      } on FormatException catch (error) {
        expect(error.message, 'VALIDATION');
        expect(error.source, isNull);
        expect(error.toString(), isNot(contains('private-marker')));
      }
    },
  );
}
