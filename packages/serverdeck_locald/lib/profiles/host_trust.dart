import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/models.dart';

import '../storage/host_trust_models.dart';
import '../storage/models.dart';
import 'service.dart';

/// Pure schema3 transition only. This neither authorizes nor commits a write.
/// The common coordinator must own fresh owner proof, target fence, receipt
/// replay/HMAC, and a live challenge claim for confirm before using this value.
PreparedTrustedMutation prepareHostTrustMutation(
  HostTrustState snapshot,
  String method,
  Map<String, Object?> params,
  String timestamp,
) {
  if (method != 'servers.trust.confirm' && method != 'servers.trust.revoke')
    throw const FormatException('UNSUPPORTED');
  final input = captureHostTrustParams(method, params);
  final state = snapshot.foundation;
  final id = input['profileId'] as String, profile = state.profiles[id];
  if (profile == null) throw StateError('NOT_FOUND');
  if (profile.revision != input['expectedRevision'])
    throw StateError('REVISION_CONFLICT');
  final old = snapshot.trust[id];
  final confirming = method == 'servers.trust.confirm';
  if (!confirming && old == null) throw StateError('TRUST_REQUIRED');
  if (state.receipts.length >= 10000) throw StateError('RESOURCE_LIMIT');
  final revision = nextRevision(profile.revision);
  final trustRevision = nextRevision(profile.trustRevision);
  final storeRevision = nextRevision(state.storeRevision);
  final nextProfile = ProfileRecord.fromTrustedJson({
    ...profile.toJson(),
    'revision': revision,
    'trustRevision': trustRevision,
    'updatedAt': timestamp,
  });
  final row = HostTrustRecord.fromJson({
    'workspaceId': state.workspaceId,
    'profileId': id,
    'revision': trustRevision,
    'connectionRevision': confirming
        ? profile.connectionRevision
        : old!.connectionRevision,
    'status': confirming ? 'trusted' : 'revoked',
    'key': confirming ? input['key'] : old!.toJson()['key'],
    'createdAt': old?.toJson()['createdAt'] ?? timestamp,
    'updatedAt': timestamp,
  });
  final value = state.toJson();
  value['storeRevision'] = storeRevision;
  (value['profiles'] as Map)[id] = nextProfile.toJson();
  return PreparedTrustedMutation(
    value,
    MutationResult(
      entityId: id,
      entityRevision: revision,
      storeRevision: storeRevision,
      deleted: false,
    ),
    {...snapshot.trust, id: row},
  );
}
