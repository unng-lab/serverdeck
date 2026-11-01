import 'package:serverdeck_protocol/host_trust.dart';

import 'models.dart';

/// Pure schema3 foundation/trust references. Does not validate automation rows,
/// native custody, owner authority or readiness; those are loader/service gates.
final class HostTrustState {
  HostTrustState._(this.foundation, this.trust);

  factory HostTrustState.fromRecords(
    WorkspaceState foundation,
    Map<String, HostTrustRecord> trust,
  ) {
    if (foundation.schemaVersion != 3) throw StateError('INCOMPATIBLE');
    if (trust.length > 250) throw StateError('STORAGE_BLOCKED');
    for (final entry in trust.entries) {
      final row = entry.value;
      final profile = foundation.profiles[entry.key];
      if (entry.key != row.profileId ||
          profile == null ||
          row.workspaceId != foundation.workspaceId ||
          row.revision != profile.trustRevision ||
          row.updatedAt.compareTo(profile.updatedAt) > 0 ||
          BigInt.parse(row.connectionRevision) >
              BigInt.parse(profile.connectionRevision) ||
          (row.status == HostTrustStatus.trusted &&
              row.connectionRevision != profile.connectionRevision)) {
        throw StateError('STORAGE_BLOCKED');
      }
    }
    for (final profile in foundation.profiles.values) {
      if (!trust.containsKey(profile.id) &&
          profile.trustRevision != profile.connectionRevision) {
        throw StateError('STORAGE_BLOCKED');
      }
    }
    return HostTrustState._(foundation, Map.unmodifiable(trust));
  }

  final WorkspaceState foundation;
  final Map<String, HostTrustRecord> trust;
}
