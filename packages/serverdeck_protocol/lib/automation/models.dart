import '../validation.dart';

export 'grant_records.dart';
export 'profile_body.dart';
export 'profile_records.dart';
export 'job_records.dart';
export 'observation_records.dart';
export 'plan_records.dart';

/// Content equality is not execution authority: all three fields are required.
final class AutomationRevisionKey {
  const AutomationRevisionKey._(this.profileId, this.revision, this.bodyDigest);

  factory AutomationRevisionKey.fromJson(Map<String, Object?> value) {
    requireFields(value, {'profileId', 'revision', 'bodyDigest'});
    final profileId = requireUuid(value['profileId']);
    final revision = requireAutomationRevision(value['revision']);
    final digest = value['bodyDigest'];
    if (digest is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('VALIDATION');
    }
    return AutomationRevisionKey._(profileId, revision, digest);
  }

  final String profileId;
  final int revision;
  final String bodyDigest;

  Map<String, Object?> toJson() => {
    'profileId': profileId,
    'revision': revision,
    'bodyDigest': bodyDigest,
  };

  @override
  bool operator ==(Object other) =>
      other is AutomationRevisionKey &&
      profileId == other.profileId &&
      revision == other.revision &&
      bodyDigest == other.bodyDigest;

  @override
  int get hashCode => Object.hash(profileId, revision, bodyDigest);
}

int requireAutomationRevision(Object? value) {
  if (value is! int || value < 1 || value > 2147483647) {
    throw const FormatException('VALIDATION');
  }
  return value;
}

enum McpScope { read, logs, author, plan, apply }

/// Validates the structural portion of a grant, never looks up server data.
/// Locald must separately resolve targets and check live revision/expiry/revoke.
final class GrantScopePolicy {
  GrantScopePolicy._(Set<McpScope> scopes, Set<String> serverIds)
    : scopes = Set.unmodifiable(scopes),
      serverIds = Set.unmodifiable(serverIds);

  factory GrantScopePolicy.fromJson(Map<String, Object?> value) {
    requireFields(value, {'scopes', 'serverIds'});
    final rawScopes = value['scopes'];
    final rawTargets = value['serverIds'];
    if (rawScopes is! List ||
        rawTargets is! List ||
        rawScopes.length > McpScope.values.length ||
        rawTargets.length > 250) {
      throw const FormatException('VALIDATION');
    }
    final scopes = <McpScope>{};
    for (final raw in rawScopes) {
      McpScope? scope;
      for (final candidate in McpScope.values) {
        if (raw == candidate.name) scope = candidate;
      }
      if (scope == null || !scopes.add(scope)) {
        throw const FormatException('VALIDATION');
      }
    }
    final targets = <String>{};
    for (final raw in rawTargets) {
      if (!targets.add(requireUuid(raw))) {
        throw const FormatException('VALIDATION');
      }
    }
    final hasServerScope = scopes.any((scope) => scope != McpScope.author);
    if (hasServerScope != targets.isNotEmpty ||
        (scopes.any(
              (scope) => const {
                McpScope.logs,
                McpScope.plan,
                McpScope.apply,
              }.contains(scope),
            ) &&
            !scopes.contains(McpScope.read)) ||
        (scopes.contains(McpScope.apply) && !scopes.contains(McpScope.plan))) {
      throw const FormatException('VALIDATION');
    }
    return GrantScopePolicy._(scopes, targets);
  }

  final Set<McpScope> scopes;
  final Set<String> serverIds;

  bool allowsScope(McpScope scope) => scopes.contains(scope);
  bool allowsServer(String serverId) => serverIds.contains(serverId);

  Map<String, Object?> toJson() => {
    'scopes': [
      for (final scope in McpScope.values)
        if (scopes.contains(scope)) scope.name,
    ],
    'serverIds': serverIds.toList(),
  };
}
