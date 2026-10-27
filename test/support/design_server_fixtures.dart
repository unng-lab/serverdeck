import 'package:serverdeck_protocol/connections.dart';
import 'package:serverdeck_protocol/executor_enrollment.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/remote_reads.dart';

/// Synthetic protocol metadata for the same sections used by `ServerPanel`.
/// These values establish no native client, grant, transport, or live authority.
abstract final class DesignServerFixtures {
  static const serverId = '00000000-0000-4000-8000-000000000003';
  static const workspaceId = '00000000-0000-4000-8000-000000000004';
  static const hostId = '00000000-0000-4000-8000-000000000005';
  static const challengeId = '00000000-0000-4000-8000-000000000006';
  static const observedAt = '2026-10-25T09:00:00.000Z';
  static const expiresAt = '2026-10-25T09:05:00.000Z';
  static final _digest = List.filled(64, 'a').join();
  static final key = SshHostPin(
    'ssh-ed25519',
    'SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  );

  static ProfileView profile({
    String id = serverId,
    String revision = '2',
    String address = '192.0.2.44',
    int port = 2222,
    String connectionRevision = '1',
    String credentialRevision = '1',
    String trustRevision = '2',
  }) => ProfileView(
    id: id,
    revision: revision,
    name: 'Синтетический сервер',
    address: address,
    port: port,
    sshUser: 'synthetic',
    tags: const [],
    credentialRevision: credentialRevision,
    connectionRevision: connectionRevision,
    trustRevision: trustRevision,
    createdAt: observedAt,
    updatedAt: observedAt,
    credentialKind: CredentialKind.password,
    credentialConfigured: true,
  );

  static ConnectionIdentity identity() => ConnectionIdentity.fromJson({
    'profileId': serverId,
    'connectionRevision': '1',
    'credentialRevision': '1',
    'trustRevision': '2',
    'key': key.toJson(),
  });

  static ConnectionSnapshot connection({
    String state = 'connected',
    bool? interested,
  }) => ConnectionSnapshot.fromJson({
    'profileId': serverId,
    'state': state,
    'interested': interested ?? (state != 'disconnected' && state != 'closing'),
    'identity': state == 'disconnected' ? null : identity().toJson(),
  });

  static HostTrustSnapshot trust({
    HostTrustStatus? status = HostTrustStatus.trusted,
  }) => HostTrustSnapshot.fromJson({
    'profileId': serverId,
    'profileRevision': '2',
    'connectionRevision': '1',
    'credentialRevision': '1',
    'trustRevision': status == null ? '1' : '2',
    'trust': status == null
        ? null
        : {
            'profileId': serverId,
            'revision': '2',
            'connectionRevision': '1',
            'status': status.name,
            'key': key.toJson(),
            'createdAt': observedAt,
            'updatedAt': observedAt,
          },
  });

  static HostTrustChallenge challenge() => HostTrustChallenge.fromJson({
    'challengeId': challengeId,
    'profileId': serverId,
    'expectedRevision': '2',
    'connectionRevision': '1',
    'credentialRevision': '1',
    'trustRevision': '2',
    'key': key.toJson(),
    'expiresAt': expiresAt,
  });

  static ExecutorEnrollment executor() => ExecutorEnrollment.fromJson({
    'format': 1,
    'workspaceId': workspaceId,
    'serverId': serverId,
    'connection': identity().toJson(),
    'hostId': hostId,
    'runtimeVersion': '1.0.0+$_digest',
    'lockDigest': _digest,
    'registryDigest': _digest,
    'compilerDigest': _digest,
    'bridgeDigest': _digest,
    'createdAt': observedAt,
  });

  static Map<String, Object?> executorInspection() =>
      captureRemoteReadPayload('executorInspect', {
        'serverId': serverId,
        'challengeId': challengeId,
        'expiresAt': expiresAt,
        'enrollment': executor().toJson(),
      });

  /// Raw graph projections also permit invalid values for defensive UI cases.
  /// Noninteger samples go directly to MetricsHistory: StrictCodec rejects them.
  static Map<String, Object?> point({
    String time = observedAt,
    Object? cpuPercent = 25,
    Object? memoryUsedPercent = 50,
    Object? rootDiskUsedPercent = 75,
  }) => Map.unmodifiable({
    'receivedAt': time,
    'cpuPercent': cpuPercent,
    'memoryUsedPercent': memoryUsedPercent,
    'rootDiskUsedPercent': rootDiskUsedPercent,
  });

  /// Source order is retained, including any explicit per-index time override.
  static List<Object?> history({
    int count = 3,
    Duration interval = const Duration(seconds: 5),
    Map<int, Map<String, Object?>> overrides = const {},
  }) {
    RangeError.checkValueInInterval(count, 0, 120, 'count');
    final start = DateTime.parse(observedAt);
    return List<Object?>.unmodifiable([
      for (var index = 0; index < count; index++)
        Map<String, Object?>.unmodifiable({
          ...point(
            time: start.add(interval * index).toIso8601String(),
            cpuPercent: (index * 7) % 101,
            memoryUsedPercent: (index * 11) % 101,
            rootDiskUsedPercent: (index * 13) % 101,
          ),
          ...?overrides[index],
        }),
    ]);
  }

  static Map<String, Object?> state({
    String quality = 'known',
    bool stale = false,
    List<Object?>? points,
    Map<String, Object?>? system,
    Map<String, Object?>? metrics,
    bool valuesAvailable = true,
    bool observedTimeAvailable = true,
    bool cacheDropped = false,
    bool truncated = false,
    int parseErrors = 0,
    String? code,
  }) => captureRemoteReadPayload('state', {
    'serverId': serverId,
    'identity': identity().toJson(),
    'connection': connection().toJson(),
    'system': _observation(
      'ssh:os-release/uname/proc',
      quality,
      stale,
      system ??
          {
            'hostname': 'synthetic-сервер-例.example',
            'architecture': 'x86_64',
            'kernel': 'Linux 6.8.0',
          },
      valuesAvailable: valuesAvailable,
      observedTimeAvailable: observedTimeAvailable,
      truncated: truncated,
      parseErrors: parseErrors,
      code: code,
    ),
    'metrics': _observation(
      'ssh:proc/stat+meminfo+net/dev+df',
      quality,
      stale,
      metrics ??
          {
            'cpuPercent': 25,
            'memory': {'usedPercent': 50},
            'rootDisk': {'usedPercent': 75},
          },
      valuesAvailable: valuesAvailable,
      observedTimeAvailable: observedTimeAvailable,
      truncated: truncated,
      parseErrors: parseErrors,
      code: code,
    ),
    'packages': _observation(
      'ssh:dpkg-query',
      quality,
      stale,
      const [],
      valuesAvailable: valuesAvailable,
      observedTimeAvailable: observedTimeAvailable,
      truncated: truncated,
      parseErrors: parseErrors,
      code: code,
    ),
    'units': _observation(
      'ssh:systemctl',
      quality,
      stale,
      const [],
      valuesAvailable: valuesAvailable,
      observedTimeAvailable: observedTimeAvailable,
      truncated: truncated,
      parseErrors: parseErrors,
      code: code,
    ),
    'history': points ?? history(),
    'cacheDropped': cacheDropped,
  });

  static Map<String, Object?> record({
    String timestamp = observedAt,
    String message = 'Синтетическая запись журнала · 例 · проверка переноса.',
    String cursor = 'synthetic-cursor-1',
  }) => Map.unmodifiable({
    'timestamp': timestamp,
    'message': message,
    'cursor': cursor,
  });

  static Map<String, Object?> logs({
    String quality = 'known',
    List<Map<String, Object?>>? records,
    bool gaps = false,
    int dropped = 0,
    int duplicates = 0,
    int parseErrors = 0,
    bool truncated = false,
    String? nextCursor,
  }) => captureRemoteReadPayload('logs', {
    'serverId': serverId,
    'identity': identity().toJson(),
    'source': 'journald',
    'timezone': 'UTC',
    'observedAt': observedAt,
    'quality': quality,
    'records': records ?? [record()],
    'gaps': gaps,
    'dropped': dropped,
    'duplicates': duplicates,
    'parseErrors': parseErrors,
    'truncated': truncated,
    if (nextCursor != null) 'nextCursor': nextCursor,
  });

  static Map<String, Object?> _observation(
    String source,
    String quality,
    bool stale,
    Object? value, {
    bool valuesAvailable = true,
    bool observedTimeAvailable = true,
    bool truncated = false,
    int parseErrors = 0,
    String? code,
  }) => {
    'source': source,
    'observedAt': observedTimeAvailable ? observedAt : null,
    'receivedAt': observedAt,
    'quality': quality,
    'stale': stale,
    'value': valuesAvailable ? value : null,
    if (truncated) 'truncated': true,
    if (parseErrors != 0) 'parseErrors': parseErrors,
    if (code != null) 'code': code,
  };
}
