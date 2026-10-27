import 'package:serverdeck_protocol/automation/models.dart';

enum JobSessionUse { admission, effect, control }

/// Compares identities only. This is not a native session/authority producer:
/// the caller must independently authenticate and revalidate the real session.
void validateJobSession({
  required AutomationPlanRecord plan,
  required Map<String, Object?> target,
  required String hostId,
  required String registryDigest,
  required Object? bootIdHash,
  required JobSessionUse use,
}) {
  if (target['workspaceId'] != plan.workspaceId ||
      target['serverId'] != plan.serverId ||
      hostId != plan.hostId) {
    throw StateError('TRUST_CHANGED');
  }
  if (use != JobSessionUse.control &&
      (target['targetRevision'] != plan.serverRevision ||
          target['connectionRevision'] != plan.connectionRevision ||
          target['accessRevision'] != plan.accessRevision ||
          target['trustRevision'] != plan.trustRevision ||
          registryDigest != plan.registryDigest)) {
    throw StateError('TRUST_CHANGED');
  }
  if (use == JobSessionUse.admission &&
      bootIdHash != plan.preflight!.toJson()['bootIdHash']) {
    throw StateError('PLAN_STALE');
  }
}
