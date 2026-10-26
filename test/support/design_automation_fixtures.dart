import 'package:cryptography/dart.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/executor_recipes.dart';

/// Synthetic existing-protocol projections for production automation sections.
/// No fixture creates a client, reads credentials, or grants live authority.
abstract final class DesignAutomationFixtures {
  static const serverId = '00000000-0000-4000-8000-000000000003';
  static const workspaceId = '00000000-0000-4000-8000-000000000004';
  static const hostId = '00000000-0000-4000-8000-000000000005';
  static const profileId = '00000000-0000-4000-8000-000000000101';
  static const planId = '00000000-0000-4000-8000-000000000102';
  static const jobId = '00000000-0000-4000-8000-000000000103';
  static const grantId = '00000000-0000-4000-8000-000000000104';
  static const delegationId = '00000000-0000-4000-8000-000000000105';
  static const approvalId = '00000000-0000-4000-8000-000000000106';
  static const requestId = '00000000-0000-4000-8000-000000000107';
  static const createdAt = '2026-10-25T09:00:00.000Z';

  /// Explicit historical presentation basis, never a live permission claim.
  static DateTime presentationNow() => DateTime.parse(createdAt);
  static const expiresAt = '2026-10-25T09:05:00.000Z';
  static const hash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  static String _digest(Object? value) => const DartSha256()
      .hashSync(StrictCodec().canonical(value))
      .bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  static AutomationProfileRecord profile({
    bool archived = false,
    String name = 'Приветствие сервера',
    int headRevision = 2,
  }) => AutomationProfileRecord.fromJson({
    'workspaceId': workspaceId,
    'id': profileId,
    'name': name,
    'description': 'Синтетический профиль настройки приветствия сервера.',
    'headRevision': headRevision,
    'archived': archived,
  });

  static Map<String, Object?> body() => AutomationBody.fromJson({
    'format': 1,
    'environment': 'ubuntu24.04-amd64-systemd',
    'parameters': {
      'greeting': {'type': 'string', 'maxLength': 100, 'default': 'Привет'},
    },
    'steps': [
      {
        'id': 'motd',
        'kind': 'config_file',
        'resourceId': 'system.motd',
        'values': {
          'text': {'param': 'greeting'},
        },
      },
    ],
  }).toJson();

  /// Exact immutable revision shape; the body digest uses the protocol codec.
  static Map<String, Object?> revision({int number = 2}) {
    final content = body();
    return {
      'workspaceId': workspaceId,
      'profileId': profileId,
      'revision': number,
      'parentRevision': number == 1 ? null : number - 1,
      'bodyFormat': 1,
      'body': content,
      'digest': _digest(content),
      'authorGrantId': null,
      'createdAt': '2026-10-23T09:00:00.000Z',
    };
  }

  /// Full plan shape, without proving any actual target state or permission.
  static Map<String, Object?> plan({
    bool blocked = false,
    bool expired = false,
  }) {
    final content = AutomationBody.fromJson(body());
    final params = content.resolveParameters({});
    final baselines = [
      {'resourceId': 'system.motd', 'fingerprint': hash},
    ];
    final preflight = <String, Object?>{
      'format': 1,
      'operationId': requestId,
      'hostId': hostId,
      'environment': 'ubuntu24.04-amd64-systemd',
      'profileDigest': _digest(body()),
      'inputDigest': _digest(params),
      'runtimeVersion': 'serverdeck-executor/1',
      'runtimeLockDigest': hash,
      'compilerDigest': hash,
      'registryDigest': hash,
      'bootIdHash': hash,
      'packageSnapshotDigest': hash,
      'expectedPackageSnapshotDigest': hash,
      'netbirdSnapshotDigest': hash,
      'aptIndexDigests': <String>[],
      'recipes': <Object?>[],
      'baseObservations': baselines,
    };
    final value = <String, Object?>{
      'workspaceId': workspaceId,
      'id': planId,
      'requestId': requestId,
      'profileId': profileId,
      'profileRevision': 2,
      'profileDigest': _digest(body()),
      'serverId': serverId,
      'serverRevision': '2',
      'connectionRevision': '2',
      'accessRevision': '1',
      'trustRevision': '2',
      'hostId': blocked ? null : hostId,
      'registryDigest': blocked ? null : hash,
      'exactParams': params,
      'inputDigest': _digest(params),
      'desired': content.resolveSteps(params),
      'baseObservations': blocked ? <Object?>[] : baselines,
      'effects': blocked
          ? <Object?>[]
          : [
              {
                'id': 'write',
                'sourceStepId': 'motd',
                'kind': 'config_file',
                'resourceId': 'system.motd',
                'values': {'text': params['greeting']},
                'renderedDigest': hash,
              },
            ],
      'checks': blocked
          ? <Object?>[]
          : [
              {
                'id': 'written',
                'effectId': 'write',
                'resourceId': 'system.motd',
                'kind': 'file_digest',
                'digest': hash,
              },
            ],
      'preflight': blocked ? null : preflight,
      'preflightDigest': blocked ? null : _digest(preflight),
      'status': blocked ? 'blocked' : 'runnable',
      'reasons': blocked
          ? [
              {
                'code': 'EXECUTOR_UNAVAILABLE',
                'field': 'executor',
                'stepId': null,
              },
            ]
          : <Object?>[],
      'createdAt': expired ? '2026-10-24T09:00:00.000Z' : createdAt,
      'expiresAt': expired ? '2026-10-24T09:05:00.000Z' : expiresAt,
      'originGrantId': null,
    };
    return {...value, 'digest': _digest(value)};
  }

  static Map<String, Object?> recipe() {
    final value = <String, Object?>{
      'format': 1,
      'id': 'postgresql16',
      'version': '16.10',
      'revision': 1,
      'environment': 'ubuntu24.04-amd64-systemd',
      'packagePins': [
        {
          'name': 'postgresql-16',
          'architecture': 'amd64',
          'version': '16.10-1',
          'sha256': hash,
        },
      ],
      'dependencyTransactionDigest': hash,
      'repositoryFingerprints': [hash],
      'aptIndexDigests': [hash],
      'expectedAbsentPaths': [
        '/etc/postgresql/16/main',
        '/var/lib/postgresql/16/main',
      ],
      'ownedResources': ['postgresql.service', 'postgresql.settings'],
      'prechecks': ['fresh_install', 'packages_qualified'],
      'postchecks': ['local_sql', 'packages_exact'],
      'licenseNotices': ['PostgreSQL License\nСинтетический пример лицензии'],
      'initialSettings': {'max_connections': 100, 'shared_buffers_mb': 128},
    };
    return QualifiedRecipeDescriptor.capture({
      ...value,
      'digest': _digest(value),
    }).toJson();
  }

  static Map<String, Object?> catalog({bool enabled = true}) =>
      captureExecutorRecipes({
        'hostId': hostId,
        'runtimeVersion': '1.0.0+$hash',
        'registryDigest': hash,
        'environment': 'ubuntu24.04-amd64-systemd',
        'installEnabled': enabled,
        'recipes': [recipe()],
        'unavailable': [
          if (!enabled)
            {'id': 'postgresql16', 'code': 'QUALIFICATION_REQUIRED'},
          {'id': 'clickhouse', 'code': 'QUALIFICATION_REQUIRED'},
        ],
        'prerequisites': {
          'requiresFreshInstall': true,
          'requiresPreflight': true,
          'metadataRefresh': false,
        },
      });

  static Map<String, Object?> grant({
    bool revoked = false,
    bool expired = false,
  }) => ClientGrantRecord.fromJson({
    'id': grantId,
    'workspaceId': workspaceId,
    'label': 'ИИ-клиент для синтетического сервера',
    'revision': 1,
    'scopes': ['read', 'logs', 'author', 'plan', 'apply'],
    'serverIds': [serverId],
    'createdAt': expired ? '2026-10-24T09:00:00.000Z' : createdAt,
    'issuedAt': expired ? '2026-10-24T09:00:00.000Z' : createdAt,
    'expiresAt': expired
        ? '2026-10-24T17:00:00.000Z'
        : '2026-10-25T17:00:00.000Z',
    'revokedAt': revoked ? '2026-10-25T09:01:00.000Z' : null,
    'secretRef': '00000000-0000-4000-8000-000000000108',
  }).toPublicJson();

  static Map<String, Object?> delegation({bool revoked = false}) =>
      DelegationRecord.fromJson({
        'id': delegationId,
        'workspaceId': workspaceId,
        'grantId': grantId,
        'revision': 1,
        'serverIds': [serverId],
        'profileRevisions': [
          {
            'profileId': profileId,
            'revision': 2,
            'bodyDigest': _digest(body()),
          },
        ],
        'predicates': {
          'greeting': {
            'type': 'enum',
            'values': ['Привет'],
          },
        },
        'expiresAt': '2026-10-25T10:00:00.000Z',
        'revokedAt': revoked ? '2026-10-25T09:01:00.000Z' : null,
      }).toJson();

  static Map<String, Object?> approval({String state = 'pending'}) =>
      AutomationApprovalRecord.fromJson({
        'workspaceId': workspaceId,
        'id': approvalId,
        'planId': planId,
        'planDigest': plan()['digest'],
        'grantId': grantId,
        'createdAt': createdAt,
        'expiresAt': expiresAt,
        'state': state,
        'jobId': state == 'consumed' ? jobId : null,
      }).toJson();

  static Map<String, Object?> job({String state = 'running'}) =>
      AutomationJobRecord.fromJson({
        'workspaceId': workspaceId,
        'id': jobId,
        'requestId': requestId,
        'immutablePlanId': planId,
        'planDigest': plan()['digest'],
        'profileId': profileId,
        'profileRevision': 2,
        'profileDigest': _digest(body()),
        'grantId': null,
        'authorityRef': {'kind': 'approval', 'id': approvalId, 'revision': 1},
        'hostAttemptId': '00000000-0000-4000-8000-000000000109',
        'state': state,
        'nextSequence': 201,
        'cancelRequested': state == 'cancel-requested',
        'createdAt': createdAt,
        'updatedAt': createdAt,
        'outcome':
            {'succeeded', 'failed', 'cancelled', 'unknown'}.contains(state)
            ? {
                'effects': state == 'unknown' ? 'uncertain' : 'confirmed',
                'checks': [
                  {
                    'checkId': 'written',
                    'stepId': 'motd',
                    'result': state == 'unknown' ? 'unknown' : 'passed',
                    'safeCode': null,
                  },
                ],
                'safeCode': switch (state) {
                  'unknown' => 'UNKNOWN_OUTCOME',
                  'failed' => 'CHECK_FAILED',
                  'cancelled' => 'CANCELLED',
                  _ => null,
                },
              }
            : null,
      }).toJson();

  static List<Map<String, Object?>> events({int count = 3, int dropped = 0}) {
    if (count < 0 || count > 200 || dropped < 0)
      throw ArgumentError('event bounds');
    return [
      for (var index = 0; index < count; index++)
        AutomationJobEventRecord.fromJson({
          'workspaceId': workspaceId,
          'jobId': jobId,
          'sequence': index + 1,
          'timestamp': createdAt,
          'kind': dropped > 0 && index == count - 1 ? 'dropped' : 'check',
          'stepId': dropped > 0 && index == count - 1 ? null : 'motd',
          'state': null,
          'safeCode': null,
          'checkResult': dropped > 0 && index == count - 1 ? null : 'passed',
          'droppedCount': index == count - 1 ? dropped : 0,
        }).toJson(),
    ];
  }

  static Map<String, Object?> validation({bool valid = true}) => valid
      ? {
          'valid': true,
          'issues': <Object?>[],
          'digest': _digest(body()),
          'normalizedBody': body(),
          'normalizedEffects': body()['steps'],
        }
      : {
          'valid': false,
          'issues': [
            {'field': 'body', 'code': 'VALIDATION'},
          ],
        };

  static Map<String, Object?> comparison() => {
    'profileId': profileId,
    'fromRevision': 1,
    'toRevision': 2,
    'result': {
      'changes': [
        {
          'op': 'replace',
          'path': '/parameters/greeting/default',
          'before': 'Здравствуйте',
          'after': 'Привет',
        },
      ],
      'truncated': false,
    },
  };

  static Map<String, Object?> launchConfiguration() => {
    'command': r'C:\Synthetic\ServerDeck\mcp.exe',
    'args': ['--app-root', r'C:\Synthetic\ServerDeck', '--grant-id', grantId],
  };
}
