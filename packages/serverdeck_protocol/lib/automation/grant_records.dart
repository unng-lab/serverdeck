import '../validation.dart';
import 'models.dart'
    show
        AutomationRevisionKey,
        GrantScopePolicy,
        McpScope,
        requireAutomationRevision;
import 'values.dart';

/// Persisted public grant metadata and an opaque OS custody reference.
/// Parsing expired/revoked history does not make it current again.
final class ClientGrantRecord {
  ClientGrantRecord._({
    required this.id,
    required this.workspaceId,
    required this.label,
    required this.revision,
    required this.policy,
    required this.createdAt,
    required this.issuedAt,
    required this.expiresAt,
    required this.revokedAt,
    required this.secretRef,
  });

  factory ClientGrantRecord.fromJson(Map<String, Object?> value) {
    requireAutomationDocument(value);
    requireFields(value, {
      'id',
      'workspaceId',
      'label',
      'revision',
      'scopes',
      'serverIds',
      'createdAt',
      'issuedAt',
      'expiresAt',
      'revokedAt',
      'secretRef',
    });
    final created = automationTimestamp(value['createdAt']);
    final issued = automationTimestamp(value['issuedAt']);
    final expires = automationTimestamp(value['expiresAt']);
    final revoked = nullableAutomationTimestamp(value['revokedAt']);
    final revision = requireAutomationRevision(value['revision']);
    _grantLifetime(expires.difference(issued));
    if (issued.isBefore(created) ||
        revision == 1 && issued != created ||
        revoked != null && revoked.isBefore(issued))
      invalidAutomationValue();
    return ClientGrantRecord._(
      id: requireUuid(value['id']),
      workspaceId: requireUuid(value['workspaceId']),
      label: automationText(value['label'], min: 1, max: 100),
      revision: revision,
      policy: GrantScopePolicy.fromJson({
        'scopes': value['scopes'],
        'serverIds': value['serverIds'],
      }),
      createdAt: created,
      issuedAt: issued,
      expiresAt: expires,
      revokedAt: revoked,
      secretRef: requireUuid(value['secretRef']),
    );
  }

  final String id, workspaceId, label, secretRef;
  final int revision;
  final GrantScopePolicy policy;
  final DateTime createdAt, issuedAt, expiresAt;
  final DateTime? revokedAt;

  static DateTime expiryFor(
    DateTime issuedAt, {
    Duration lifetime = const Duration(hours: 8),
  }) {
    requireAutomationInstant(issuedAt);
    _grantLifetime(lifetime);
    final expires = issuedAt.add(lifetime);
    requireAutomationInstant(expires);
    return expires;
  }

  bool isCurrentAt(DateTime at) =>
      revokedAt == null && !at.isBefore(issuedAt) && at.isBefore(expiresAt);

  /// Structural transition checks only. Owner role, CAS, actual staged DPAPI
  /// rotation, receipt atomicity and invalidating sessions are service duties.
  /// Explicit replacement may renew an expired, but never revoked, grant.
  void validateReplacement(ClientGrantRecord next, {required DateTime at}) {
    _transitionIdentity(next, at);
    if (next.issuedAt != at ||
        next.revokedAt != null ||
        next.secretRef == secretRef)
      invalidAutomationValue();
  }

  void validateRevocation(ClientGrantRecord next, {required DateTime at}) {
    _transitionIdentity(next, at);
    if (next.revokedAt != at ||
        next.issuedAt != issuedAt ||
        next.expiresAt != expiresAt ||
        next.secretRef != secretRef ||
        next.label != label ||
        next.policy.scopes.length != policy.scopes.length ||
        !next.policy.scopes.containsAll(policy.scopes) ||
        next.policy.serverIds.length != policy.serverIds.length ||
        !next.policy.serverIds.containsAll(policy.serverIds)) {
      invalidAutomationValue();
    }
  }

  void _transitionIdentity(ClientGrantRecord next, DateTime at) {
    requireAutomationInstant(at);
    if (revokedAt != null ||
        at.isBefore(issuedAt) ||
        next.id != id ||
        next.workspaceId != workspaceId ||
        next.createdAt != createdAt ||
        next.revision != revision + 1) {
      invalidAutomationValue();
    }
  }

  void validateTargets(Set<String> existingServerIds) {
    if (!existingServerIds.containsAll(policy.serverIds))
      invalidAutomationValue();
  }

  Map<String, Object?> toPublicJson() => {
    'id': id,
    'workspaceId': workspaceId,
    'label': label,
    'revision': revision,
    ...policy.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'issuedAt': issuedAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'revokedAt': revokedAt?.toIso8601String(),
  };

  Map<String, Object?> toJson() => {...toPublicJson(), 'secretRef': secretRef};
}

void _grantLifetime(Duration value) {
  if (value < const Duration(minutes: 5) || value > const Duration(days: 30)) {
    invalidAutomationValue();
  }
}

sealed class ParameterConstraint {
  const ParameterConstraint();

  factory ParameterConstraint.fromJson(Map<String, Object?> value) {
    switch (value['type']) {
      case 'integer':
        requireFields(value, {'type', 'minimum', 'maximum'});
        final min = value['minimum'], max = value['maximum'];
        if (min is! int ||
            max is! int ||
            min < 0 ||
            max > 1000000 ||
            min > max) {
          invalidAutomationValue();
        }
        return IntegerConstraint._(min, max);
      case 'enum':
        requireFields(value, {'type', 'values'});
        final values = value['values'];
        if (values is! List || values.isEmpty || values.length > 32) {
          invalidAutomationValue();
        }
        final parsed = <Object>[];
        for (final item in values) {
          if (!_publicScalar(item) ||
              (parsed.isNotEmpty &&
                  item.runtimeType != parsed.first.runtimeType) ||
              parsed.contains(item)) {
            invalidAutomationValue();
          }
          parsed.add(item!);
        }
        return EnumConstraint._(List.unmodifiable(parsed));
      default:
        invalidAutomationValue();
    }
  }

  bool matches(Object? value);
  Map<String, Object?> toJson();
}

bool _publicScalar(Object? value) {
  if (value is bool) return true;
  if (value is int) return value >= 0 && value <= 1000000;
  if (value is! String ||
      value.contains('{{') ||
      value.contains('{%') ||
      value.contains('{#'))
    return false;
  try {
    automationText(value, max: 4096, multiline: true);
    return true;
  } on FormatException {
    return false;
  }
}

final class IntegerConstraint extends ParameterConstraint {
  const IntegerConstraint._(this.minimum, this.maximum);
  final int minimum, maximum;
  @override
  bool matches(Object? value) =>
      value is int && value >= minimum && value <= maximum;
  @override
  Map<String, Object?> toJson() => {
    'type': 'integer',
    'minimum': minimum,
    'maximum': maximum,
  };
}

final class EnumConstraint extends ParameterConstraint {
  const EnumConstraint._(this.values);
  final List<Object> values;
  @override
  bool matches(Object? value) => _publicScalar(value) && values.contains(value);
  @override
  Map<String, Object?> toJson() => {
    'type': 'enum',
    'values': List<Object>.of(values),
  };
}

/// Immutable delegation metadata. Locald must still check current policy and
/// target/trust revisions at admission and again after asynchronous work.
final class DelegationRecord {
  DelegationRecord._({
    required this.id,
    required this.workspaceId,
    required this.grantId,
    required this.revision,
    required Set<String> serverIds,
    required List<AutomationRevisionKey> profileRevisions,
    required Map<String, ParameterConstraint> predicates,
    required this.expiresAt,
    required this.revokedAt,
  }) : serverIds = Set.unmodifiable(serverIds),
       profileRevisions = List.unmodifiable(profileRevisions),
       predicates = Map.unmodifiable(predicates);

  factory DelegationRecord.fromJson(Map<String, Object?> value) {
    requireAutomationDocument(value);
    requireFields(value, {
      'id',
      'workspaceId',
      'grantId',
      'revision',
      'serverIds',
      'profileRevisions',
      'predicates',
      'expiresAt',
      'revokedAt',
    });
    final targets = value['serverIds'];
    if (targets is! List || targets.isEmpty || targets.length > 250)
      invalidAutomationValue();
    final ids = <String>{};
    for (final target in targets) {
      if (!ids.add(requireUuid(target))) invalidAutomationValue();
    }
    final rawProfiles = value['profileRevisions'];
    if (rawProfiles is! List || rawProfiles.isEmpty || rawProfiles.length > 100)
      invalidAutomationValue();
    final profiles = <AutomationRevisionKey>[];
    final identities = <(String, int)>{};
    for (final raw in rawProfiles) {
      if (raw is! Map<String, Object?>) invalidAutomationValue();
      final key = AutomationRevisionKey.fromJson(raw);
      if (!identities.add((key.profileId, key.revision)))
        invalidAutomationValue();
      profiles.add(key);
    }
    final rawPredicates = value['predicates'];
    if (rawPredicates is! Map<String, Object?> || rawPredicates.length > 32)
      invalidAutomationValue();
    final predicates = <String, ParameterConstraint>{};
    for (final entry in rawPredicates.entries) {
      final raw = entry.value;
      if (raw is! Map<String, Object?>) invalidAutomationValue();
      predicates[automationIdentifier(entry.key)] =
          ParameterConstraint.fromJson(raw);
    }
    return DelegationRecord._(
      id: requireUuid(value['id']),
      workspaceId: requireUuid(value['workspaceId']),
      grantId: requireUuid(value['grantId']),
      revision: requireAutomationRevision(value['revision']),
      serverIds: ids,
      profileRevisions: profiles,
      predicates: predicates,
      expiresAt: automationTimestamp(value['expiresAt']),
      revokedAt: nullableAutomationTimestamp(value['revokedAt']),
    );
  }

  final String id, workspaceId, grantId;
  final int revision;
  final Set<String> serverIds;
  final List<AutomationRevisionKey> profileRevisions;
  final Map<String, ParameterConstraint> predicates;
  final DateTime expiresAt;
  final DateTime? revokedAt;

  static DateTime expiryFor(
    DateTime issuedAt, {
    required ClientGrantRecord grant,
    Duration lifetime = const Duration(hours: 1),
  }) {
    requireAutomationInstant(issuedAt);
    _delegationLifetime(lifetime);
    final expires = issuedAt.add(lifetime);
    if (!grant.isCurrentAt(issuedAt) || expires.isAfter(grant.expiresAt))
      invalidAutomationValue();
    requireAutomationInstant(expires);
    return expires;
  }

  void validateForGrant(ClientGrantRecord grant, {required DateTime issuedAt}) {
    requireAutomationInstant(issuedAt);
    _delegationLifetime(expiresAt.difference(issuedAt));
    if (grant.id != grantId ||
        grant.workspaceId != workspaceId ||
        !grant.isCurrentAt(issuedAt) ||
        expiresAt.isAfter(grant.expiresAt) ||
        !grant.policy.allowsScope(McpScope.apply) ||
        !grant.policy.serverIds.containsAll(serverIds) ||
        revokedAt != null) {
      invalidAutomationValue();
    }
  }

  bool matches({
    required ClientGrantRecord grant,
    required String serverId,
    required AutomationRevisionKey profile,
    required Map<String, Object?> parameters,
    required DateTime at,
  }) {
    if (revokedAt != null ||
        !at.isBefore(expiresAt) ||
        grant.id != grantId ||
        grant.workspaceId != workspaceId ||
        !grant.isCurrentAt(at) ||
        !grant.policy.allowsScope(McpScope.apply) ||
        !grant.policy.allowsServer(serverId) ||
        !serverIds.contains(serverId) ||
        !profileRevisions.contains(profile) ||
        parameters.length != predicates.length)
      return false;
    for (final entry in predicates.entries) {
      if (!parameters.containsKey(entry.key) ||
          !entry.value.matches(parameters[entry.key]))
        return false;
    }
    return true;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'workspaceId': workspaceId,
    'grantId': grantId,
    'revision': revision,
    'serverIds': serverIds.toList(),
    'profileRevisions': [for (final key in profileRevisions) key.toJson()],
    'predicates': {
      for (final entry in predicates.entries) entry.key: entry.value.toJson(),
    },
    'expiresAt': expiresAt.toIso8601String(),
    'revokedAt': revokedAt?.toIso8601String(),
  };
}

void _delegationLifetime(Duration lifetime) {
  if (lifetime < const Duration(minutes: 5) ||
      lifetime > const Duration(hours: 24))
    invalidAutomationValue();
}
