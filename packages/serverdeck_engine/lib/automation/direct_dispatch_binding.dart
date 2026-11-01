import 'package:cryptography/dart.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/automation/direct_ssh_dispatch.dart';
import 'package:serverdeck_protocol/codec.dart';

/// Deterministic bindings only, never live authorization or remote evidence.
String directBindingDigest(Object? value) => const DartSha256()
    .hashSync(StrictCodec().canonical(value))
    .bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();

String directTargetBinding(AutomationPlanRecord plan) => directBindingDigest({
  'workspaceId': plan.workspaceId,
  'serverId': plan.serverId,
  'targetRevision': plan.serverRevision,
  'connectionRevision': plan.connectionRevision,
  'accessRevision': plan.accessRevision,
  'trustRevision': plan.trustRevision,
});

String directAuthorityBinding({
  required AutomationPlanRecord plan,
  required AutomationAuthorityRef authority,
  required String? grantId,
  required int? grantRevision,
  required DateTime? grantExpiresAt,
  required DateTime authorityExpiresAt,
}) => directBindingDigest({
  'authorityRef': authority.toJson(),
  'profileKey': plan.key.toJson(),
  'exactParams': plan.toJson()['exactParams'],
  'grantId': grantId,
  'grantRevision': grantRevision,
  'grantExpiresAt': grantExpiresAt?.toIso8601String(),
  'authorityExpiresAt': authorityExpiresAt.toIso8601String(),
});

/// Historical consistency only. The loader separately validates complete grant
/// receipt history; this never authorizes a new dispatch from retained metadata.
void validateDirectGrantDispatch({
  required DirectSshDispatch dispatch,
  required ClientGrantRecord grant,
  required String serverId,
  required List<AutomationMutationReceiptRecord> history,
}) {
  Never blocked() => throw StateError('STORAGE_BLOCKED');
  final index = history.indexWhere(
    (row) => row.result['revision'] == dispatch.grantRevision,
  );
  if (index < 0 ||
      history[index].operation == 'grant.revoke' ||
      dispatch.authorizedAt.isBefore(history[index].createdAt) ||
      index + 1 < history.length &&
          dispatch.authorizedAt.isAfter(history[index + 1].createdAt)) {
    blocked();
  }
  final latestIssuance = history.lastWhere(
    (row) => row.operation != 'grant.revoke',
  );
  if (latestIssuance.result['revision'] == dispatch.grantRevision &&
      (dispatch.grantExpiresAt != grant.expiresAt ||
          !grant.policy.allowsScope(McpScope.apply) ||
          !grant.policy.serverIds.contains(serverId)))
    blocked();
}
