import 'package:serverdeck_protocol/automation/models.dart';
import 'package:test/test.dart';

const workspace = '20000000-0000-4000-8000-000000000001';
const grantId = '20000000-0000-4000-8000-000000000002';
const serverId = '20000000-0000-4000-8000-000000000003';
const delegationId = '20000000-0000-4000-8000-000000000004';
const profileId = '20000000-0000-4000-8000-000000000005';
const secretRef = '20000000-0000-4000-8000-000000000006';
const digest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final issuedAt = DateTime.utc(2026, 10, 21);

Map<String, Object?> grantJson() => {
  'id': grantId,
  'workspaceId': workspace,
  'label': 'Automation client',
  'revision': 1,
  'scopes': ['read', 'plan', 'apply'],
  'serverIds': [serverId],
  'createdAt': issuedAt.toIso8601String(),
  'issuedAt': issuedAt.toIso8601String(),
  'expiresAt': issuedAt.add(const Duration(hours: 8)).toIso8601String(),
  'revokedAt': null,
  'secretRef': secretRef,
};

Map<String, Object?> delegationJson() => {
  'id': delegationId,
  'workspaceId': workspace,
  'grantId': grantId,
  'revision': 1,
  'serverIds': [serverId],
  'profileRevisions': [
    {'profileId': profileId, 'revision': 1, 'bodyDigest': digest},
  ],
  'predicates': {
    'enabled': {
      'type': 'enum',
      'values': [true],
    },
    'connections': {'type': 'integer', 'minimum': 10, 'maximum': 100},
  },
  'expiresAt': issuedAt.add(const Duration(hours: 1)).toIso8601String(),
  'revokedAt': null,
};

void main() {
  test(
    'replacement renews explicit issuance at day29/day31 preserving creation',
    () {
      final original = ClientGrantRecord.fromJson(grantJson());
      for (final days in [29, 31]) {
        final replacementTime = issuedAt.add(Duration(days: days));
        final json = grantJson()
          ..addAll({
            'revision': 2,
            'secretRef': delegationId,
            'issuedAt': replacementTime.toIso8601String(),
            'expiresAt': replacementTime
                .add(const Duration(days: 30))
                .toIso8601String(),
          });
        final renewed = ClientGrantRecord.fromJson(json);
        original.validateReplacement(renewed, at: replacementTime);
        expect(renewed.createdAt, original.createdAt);
        expect(renewed.issuedAt, replacementTime);
        expect(renewed.toJson(), json);
        expect(
          renewed.toPublicJson()['issuedAt'],
          replacementTime.toIso8601String(),
        );
        expect(renewed.isCurrentAt(replacementTime), isTrue);
        expect(
          renewed.isCurrentAt(
            replacementTime.subtract(const Duration(milliseconds: 1)),
          ),
          isFalse,
        );
        expect(renewed.isCurrentAt(renewed.expiresAt), isFalse);
        expect(original.createdAt, issuedAt);
      }
    },
  );

  test('issuedAt is mandatory, bounded and anchored to initial revision', () {
    final mutations = <void Function(Map<String, Object?>)>[
      (v) => v.remove('issuedAt'),
      (v) => v['issuedAt'] = null,
      (v) => v['issuedAt'] = issuedAt
          .subtract(const Duration(milliseconds: 1))
          .toIso8601String(),
      (v) => v['issuedAt'] = issuedAt
          .add(const Duration(milliseconds: 1))
          .toIso8601String(),
      (v) => v['issuedAt'] = '2026-10-21T00:00:00Z',
      (v) => v['expiresAt'] = issuedAt
          .add(const Duration(minutes: 5) - const Duration(milliseconds: 1))
          .toIso8601String(),
      (v) => v['expiresAt'] = issuedAt
          .add(const Duration(days: 30, milliseconds: 1))
          .toIso8601String(),
    ];
    for (final change in mutations) {
      final input = grantJson();
      change(input);
      expect(() => ClientGrantRecord.fromJson(input), throwsFormatException);
    }
    for (final lifetime in [
      const Duration(minutes: 5),
      const Duration(days: 30),
    ]) {
      final grant = ClientGrantRecord.fromJson(
        grantJson()..['expiresAt'] = issuedAt.add(lifetime).toIso8601String(),
      );
      expect(grant.issuedAt, issuedAt);
    }
  });

  test('replacement rotates identity of credential but cannot rewrite creation or revoke', () {
    final original = ClientGrantRecord.fromJson(grantJson());
    final at = issuedAt.add(const Duration(days: 31));
    Map<String, Object?> replacement() => grantJson()
      ..addAll({
        'revision': 2,
        'secretRef': delegationId,
        'issuedAt': at.toIso8601String(),
        'expiresAt': ClientGrantRecord.expiryFor(at).toIso8601String(),
      });
    final mutations = <void Function(Map<String, Object?>)>[
      (v) => v['revision'] = 3,
      (v) => v['secretRef'] = secretRef,
      (v) => v['id'] = profileId,
      (v) => v['workspaceId'] = profileId,
      (v) => v['createdAt'] = issuedAt
          .add(const Duration(milliseconds: 1))
          .toIso8601String(),
      (v) => v['issuedAt'] = at
          .add(const Duration(milliseconds: 1))
          .toIso8601String(),
      (v) => v['revokedAt'] = at.toIso8601String(),
    ];
    for (final change in mutations) {
      final input = replacement();
      change(input);
      expect(
        () => original.validateReplacement(
          ClientGrantRecord.fromJson(input),
          at: at,
        ),
        throwsFormatException,
      );
    }
    final before = grantJson()
      ..addAll({
        'revision': 2,
        'revokedAt': issuedAt.add(const Duration(hours: 1)).toIso8601String(),
      });
    final revoked = ClientGrantRecord.fromJson(before);
    final next = replacement()..['revision'] = 3;
    expect(
      () =>
          revoked.validateReplacement(ClientGrantRecord.fromJson(next), at: at),
      throwsFormatException,
    );
    expect(
      () => original.validateReplacement(
        ClientGrantRecord.fromJson(replacement()),
        at: at.add(const Duration(microseconds: 1)),
      ),
      throwsFormatException,
    );
  });

  test('revocation preserves issuance/expiry and all metadata without implicit renewal', () {
    final original = ClientGrantRecord.fromJson(grantJson());
    final at = issuedAt.add(const Duration(days: 31));
    Map<String, Object?> revocation() =>
        grantJson()..addAll({'revision': 2, 'revokedAt': at.toIso8601String()});
    final revoked = ClientGrantRecord.fromJson(revocation());
    original.validateRevocation(revoked, at: at);
    expect(revoked.isCurrentAt(at), isFalse);
    expect(revoked.createdAt, original.createdAt);
    expect(revoked.issuedAt, original.issuedAt);
    expect(revoked.expiresAt, original.expiresAt);
    for (final change in <void Function(Map<String, Object?>)>[
      (v) => v['label'] = 'changed',
      (v) => v['secretRef'] = delegationId,
      (v) => v['scopes'] = ['author'],
      (v) => v['revision'] = 3,
      (v) => v['serverIds'] = [profileId],
      (v) => v['expiresAt'] = original.expiresAt
          .add(const Duration(hours: 1))
          .toIso8601String(),
      (v) => v['revokedAt'] = at
          .add(const Duration(milliseconds: 1))
          .toIso8601String(),
    ]) {
      final input = revocation();
      change(input);
      expect(
        () => original.validateRevocation(
          ClientGrantRecord.fromJson(input),
          at: at,
        ),
        throwsFormatException,
      );
    }
    expect(
      () => revoked.validateRevocation(revoked, at: at),
      throwsFormatException,
    );
  });
  test(
    'predicate text rejects C1 controls but retains adjacent public text',
    () {
      for (final codepoint in [0x7f, 0x80, 0x85, 0x9f]) {
        expect(
          () => ParameterConstraint.fromJson({
            'type': 'enum',
            'values': ['a${String.fromCharCode(codepoint)}b'],
          }),
          throwsFormatException,
        );
      }
      for (final codepoint in [0x7e, 0xa0, 9, 10]) {
        final text = 'a${String.fromCharCode(codepoint)}b';
        expect(
          ParameterConstraint.fromJson({
            'type': 'enum',
            'values': [text],
          }).matches(text),
          isTrue,
        );
      }
    },
  );

  test('public multiline strings are exact enum values, not templates', () {
    final predicate = ParameterConstraint.fromJson({
      'type': 'enum',
      'values': ['first\n\tsecond'],
    });
    expect(predicate.matches('first\n\tsecond'), isTrue);
    expect(predicate.matches('first second'), isFalse);
    expect(predicate.matches('first\u0000second'), isFalse);
    final copy = predicate.toJson();
    (copy['values'] as List).add('broader');
    expect(predicate.matches('broader'), isFalse);
  });

  test(
    'grant lifetime is bounded, strict UTC, and not extended by parsing',
    () {
      final grant = ClientGrantRecord.fromJson(grantJson());
      expect(grant.isCurrentAt(issuedAt), isTrue);
      expect(
        grant.isCurrentAt(issuedAt.subtract(const Duration(milliseconds: 1))),
        isFalse,
      );
      expect(
        grant.isCurrentAt(issuedAt.add(const Duration(hours: 8))),
        isFalse,
      );
      expect(
        ClientGrantRecord.expiryFor(issuedAt),
        issuedAt.add(const Duration(hours: 8)),
      );
      for (final lifetime in [
        const Duration(minutes: 4),
        const Duration(days: 31),
      ]) {
        expect(
          () => ClientGrantRecord.expiryFor(issuedAt, lifetime: lifetime),
          throwsFormatException,
        );
      }
      for (final invalid in [
        '2026-10-21T08:00:00Z',
        '2026-10-21T08:00:00.000+00:00',
        '2026-02-30T08:00:00.000Z',
      ]) {
        expect(
          () => ClientGrantRecord.fromJson({
            ...grantJson(),
            'expiresAt': invalid,
          }),
          throwsFormatException,
        );
      }
    },
  );

  test('revoked grant stays revoked at every later time and public view omits custody reference', () {
    final grant = ClientGrantRecord.fromJson({
      ...grantJson(),
      'revokedAt': issuedAt.add(const Duration(minutes: 10)).toIso8601String(),
    });
    expect(
      grant.isCurrentAt(issuedAt.add(const Duration(minutes: 20))),
      isFalse,
    );
    expect(grant.toPublicJson().containsKey('secretRef'), isFalse);
    expect(grant.toJson()['secretRef'], secretRef);
    expect(
      () => ClientGrantRecord.fromJson({...grantJson(), 'label': 'Cafe\u0301'}),
      throwsFormatException,
    );
    expect(
      () => ClientGrantRecord.fromJson({...grantJson(), 'unknown': true}),
      throwsFormatException,
    );
  });

  test('grant record applies author-only empty-target policy without target inheritance', () {
    final grant = ClientGrantRecord.fromJson({
      ...grantJson(),
      'scopes': ['author'],
      'serverIds': <String>[],
    });
    expect(grant.policy.allowsScope(McpScope.author), isTrue);
    expect(grant.policy.allowsServer(serverId), isFalse);
    expect(() => grant.validateTargets({}), returnsNormally);
    expect(
      () => ClientGrantRecord.fromJson(grantJson()).validateTargets({}),
      throwsFormatException,
    );
  });

  test('delegation matches exact tuple and every resolved parameter without coercion', () {
    final grant = ClientGrantRecord.fromJson(grantJson());
    final delegation = DelegationRecord.fromJson(delegationJson());
    final key = AutomationRevisionKey.fromJson({
      'profileId': profileId,
      'revision': 1,
      'bodyDigest': digest,
    });
    bool permits({
      AutomationRevisionKey? revision,
      Map<String, Object?>? parameters,
    }) => delegation.matches(
      grant: grant,
      serverId: serverId,
      profile: revision ?? key,
      parameters: parameters ?? {'enabled': true, 'connections': 10},
      at: issuedAt,
    );
    expect(permits(), isTrue);
    expect(permits(parameters: {'enabled': true, 'connections': 100}), isTrue);
    for (final params in <Map<String, Object?>>[
      {'enabled': false, 'connections': 10},
      {'enabled': true, 'connections': 101},
      {'enabled': true, 'connections': 10.0},
      {'enabled': true},
      {'enabled': true, 'connections': 10, 'extra': false},
    ]) {
      expect(permits(parameters: params), isFalse);
    }
    for (final other in [
      {'profileId': profileId, 'revision': 2, 'bodyDigest': digest},
      {'profileId': delegationId, 'revision': 1, 'bodyDigest': digest},
    ]) {
      expect(permits(revision: AutomationRevisionKey.fromJson(other)), isFalse);
    }
  });

  test('delegation creation validates grant identity, explicit targets and bounded lifetime', () {
    final grant = ClientGrantRecord.fromJson(grantJson());
    final delegation = DelegationRecord.fromJson(delegationJson());
    expect(
      () => delegation.validateForGrant(grant, issuedAt: issuedAt),
      returnsNormally,
    );
    expect(
      DelegationRecord.expiryFor(issuedAt, grant: grant),
      issuedAt.add(const Duration(hours: 1)),
    );
    for (final invalid in [
      {...delegationJson(), 'grantId': delegationId},
      {...delegationJson(), 'workspaceId': delegationId},
      {
        ...delegationJson(),
        'serverIds': [profileId],
      },
      {
        ...delegationJson(),
        'expiresAt': issuedAt
            .add(const Duration(days: 1, seconds: 1))
            .toIso8601String(),
      },
      {
        ...delegationJson(),
        'expiresAt': issuedAt.add(const Duration(minutes: 4)).toIso8601String(),
      },
    ]) {
      expect(
        () =>
            DelegationRecord.fromJson(invalid)
                .validateForGrant(grant, issuedAt: issuedAt),
        throwsFormatException,
      );
    }
    expect(
      () => ClientGrantRecord.expiryFor(DateTime.utc(9999, 12, 31, 23)),
      throwsFormatException,
    );
    expect(
      () => ClientGrantRecord.expiryFor(
        issuedAt.add(const Duration(microseconds: 1)),
      ),
      throwsFormatException,
    );
  });

  test('expired, revoked, foreign or less privileged grant never matches delegation', () {
    final delegation = DelegationRecord.fromJson(delegationJson());
    final key = AutomationRevisionKey.fromJson({
      'profileId': profileId,
      'revision': 1,
      'bodyDigest': digest,
    });
    bool matches(DelegationRecord d, ClientGrantRecord g, DateTime now) =>
        d.matches(
          grant: g,
          serverId: serverId,
          profile: key,
          parameters: {'enabled': true, 'connections': 10},
          at: now,
        );
    final grant = ClientGrantRecord.fromJson(grantJson());
    expect(
      matches(delegation, grant, issuedAt.add(const Duration(hours: 1))),
      isFalse,
    );
    expect(
      matches(
        DelegationRecord.fromJson({
          ...delegationJson(),
          'revokedAt': issuedAt.toIso8601String(),
        }),
        grant,
        issuedAt,
      ),
      isFalse,
    );
    for (final invalid in [
      {...grantJson(), 'id': delegationId},
      {...grantJson(), 'workspaceId': delegationId},
      {
        ...grantJson(),
        'scopes': ['read'],
      },
      {...grantJson(), 'revokedAt': issuedAt.toIso8601String()},
    ]) {
      expect(
        matches(delegation, ClientGrantRecord.fromJson(invalid), issuedAt),
        isFalse,
      );
    }
  });

  test('delegation rejects duplicate revision pairs even with different content digests', () {
    final first = (delegationJson()['profileRevisions'] as List).single;
    expect(
      () => DelegationRecord.fromJson({
        ...delegationJson(),
        'profileRevisions': [
          first,
          {...first as Map<String, Object?>, 'bodyDigest': 'b' * 64},
        ],
      }),
      throwsFormatException,
    );
    for (final predicate in <Map<String, Object?>>[
      {'type': 'regex', 'pattern': '.*'},
      {'type': 'integer', 'minimum': 11, 'maximum': 10},
      {
        'type': 'enum',
        'values': [1, 1],
      },
      {
        'type': 'enum',
        'values': [true, 'true'],
      },
      {
        'type': 'enum',
        'values': ['{{ shell }}'],
      },
      {'type': 'enum', 'values': <Object>[]},
    ]) {
      expect(
        () => DelegationRecord.fromJson({
          ...delegationJson(),
          'predicates': {'value': predicate},
        }),
        throwsFormatException,
      );
    }
  });
}
