import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:test/test.dart';

import 'automation_recipe_records_test.dart' as recipes;

const workspace = '10000000-0000-4000-8000-000000000001';
const server = '10000000-0000-4000-8000-000000000002';
const host = '10000000-0000-4000-8000-000000000003';
const profile = '10000000-0000-4000-8000-000000000004';
const planId = '10000000-0000-4000-8000-000000000005';
const requestId = '10000000-0000-4000-8000-000000000006';
const hash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const created = '2026-10-21T10:00:00.000Z';
const expires = '2026-10-21T10:05:00.000Z';

Map<String, Object?> copy(Map<String, Object?> input) =>
    jsonDecode(jsonEncode(input)) as Map<String, Object?>;
Future<String> digest(Object? value) async =>
    (await Sha256().hash(StrictCodec().canonical(value))).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
Future<Map<String, Object?>> signPlan(Map<String, Object?> input) async {
  final value = copy(input)..remove('digest');
  value['digest'] = await digest(value);
  return value;
}

Map<String, Object?> observation() => {
  'workspaceId': workspace,
  'serverId': server,
  'resourceId': 'system.motd',
  'targetRevision': '9223372036854775807',
  'connectionRevision': '2',
  'accessRevision': '1',
  'trustRevision': '2',
  'hostId': host,
  'resourceRegistryDigest': hash,
  'observedAt': created,
  'status': 'known',
  'value': {
    'exists': true,
    'fileDigest': hash,
    'baselineDigest': hash,
    'values': {'text': 'before'},
  },
};

Future<AutomationRevisionRecord> revision({
  List<Map<String, Object?>>? steps,
}) async {
  final body = AutomationBody.fromJson({
    'format': 1,
    'environment': 'ubuntu24.04-amd64-systemd',
    'parameters': steps == null
        ? {
            'greeting': {'type': 'string', 'maxLength': 50, 'default': 'hello'},
          }
        : <String, Object?>{},
    'steps':
        steps ??
        [
          {
            'id': 'motd',
            'kind': 'config_file',
            'resourceId': 'system.motd',
            'values': {
              'text': {'param': 'greeting'},
            },
          },
        ],
  });
  return AutomationRevisionRecord.fromJson({
    'workspaceId': workspace,
    'profileId': profile,
    'revision': 1,
    'parentRevision': null,
    'bodyFormat': 1,
    'body': body.toJson(),
    'digest': await body.digest(),
    'authorGrantId': null,
    'createdAt': created,
  });
}

Future<Map<String, Object?>> capsule(AutomationRevisionRecord revision) async =>
    {
      'format': 1,
      'operationId': requestId,
      'hostId': host,
      'environment': 'ubuntu24.04-amd64-systemd',
      'profileDigest': revision.key.bodyDigest,
      'inputDigest': await digest(revision.body.resolveParameters({})),
      'runtimeVersion': 'serverdeck-executor/1',
      'runtimeLockDigest': hash,
      'compilerDigest': hash,
      'registryDigest': hash,
      'bootIdHash': hash,
      'packageSnapshotDigest': hash,
      'expectedPackageSnapshotDigest': hash,
      'netbirdSnapshotDigest': hash,
      'aptIndexDigests': <Object?>[],
      'recipes': <Object?>[],
      'baseObservations': [
        <String, Object?>{
          'resourceId': 'system.motd',
          'fingerprint': await ManagedResourceObservationRecord.fromJson(
            observation(),
          ).fingerprint(),
        },
      ],
    };

Future<Map<String, Object?>> plan(AutomationRevisionRecord revision) async {
  final preflight = await capsule(revision);
  return signPlan({
    'workspaceId': workspace,
    'id': planId,
    'requestId': requestId,
    'profileId': profile,
    'profileRevision': 1,
    'profileDigest': revision.key.bodyDigest,
    'serverId': server,
    'serverRevision': '9223372036854775807',
    'connectionRevision': '2',
    'accessRevision': '1',
    'trustRevision': '2',
    'hostId': host,
    'registryDigest': hash,
    'exactParams': revision.body.resolveParameters({}),
    'inputDigest': preflight['inputDigest'],
    'desired': revision.body.resolveSteps({}),
    'baseObservations': preflight['baseObservations'],
    'effects': [
      {
        'id': 'write',
        'sourceStepId': 'motd',
        'kind': 'config_file',
        'resourceId': 'system.motd',
        'values': {'text': 'hello'},
        'renderedDigest': hash,
      },
    ],
    'checks': [
      {
        'id': 'written',
        'effectId': 'write',
        'resourceId': 'system.motd',
        'kind': 'file_digest',
        'digest': hash,
      },
    ],
    'preflight': preflight,
    'preflightDigest': await digest(preflight),
    'status': 'runnable',
    'reasons': <Object?>[],
    'createdAt': created,
    'expiresAt': expires,
    'originGrantId': null,
  });
}

Future<Map<String, Object?>> programPlan(
  AutomationRevisionRecord rev, {
  required List<Map<String, Object?>> effects,
  required List<Map<String, Object?>> checks,
  List<String> resources = const [],
  List<Map<String, Object?>> selectedRecipes = const [],
}) async {
  final input = await plan(rev);
  final preflight = input['preflight'] as Map<String, Object?>;
  preflight['baseObservations'] = [
    for (final resource in resources)
      <String, Object?>{'resourceId': resource, 'fingerprint': hash},
  ];
  preflight['recipes'] = selectedRecipes;
  preflight['aptIndexDigests'] = selectedRecipes.isEmpty ? <String>[] : [hash];
  input['baseObservations'] = preflight['baseObservations'];
  input['effects'] = effects;
  input['checks'] = checks;
  input['preflightDigest'] = await digest(preflight);
  return signPlan(input);
}

void main() {
  test(
    'exact tuple cannot follow another profile or revision with identical body',
    () async {
      final rev = await revision();
      final input = await plan(rev);
      for (final change in <void Function(Map<String, Object?>)>[
        (v) => v['profileId'] = server,
        (v) {
          v['revision'] = 2;
          v['parentRevision'] = 1;
        },
      ]) {
        final other = rev.toJson();
        change(other);
        final otherRevision = await AutomationRevisionRecord.fromJson(other);
        expect(otherRevision.key.bodyDigest, rev.key.bodyDigest);
        await expectLater(
          AutomationPlanRecord.fromJson(input, revision: otherRevision),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'bound document sizes, nulls, raw text and stored digest are fail closed',
    () async {
      final rev = await revision();
      final input = await plan(rev);
      final oversized = copy(input)..['unexpected'] = 'x' * (256 * 1024);
      await expectLater(
        AutomationPlanRecord.fromJson(oversized, revision: rev),
        throwsFormatException,
      );
      final hugeCapsule = await capsule(rev)
        ..['unexpected'] = 'x' * (256 * 1024);
      await expectLater(
        AutomationPreflightCapsule.fromJson(hugeCapsule),
        throwsFormatException,
      );
      final alteredCapsule = copy(input);
      final facts = alteredCapsule['preflight'] as Map<String, Object?>;
      facts['expectedPackageSnapshotDigest'] = 'b' * 64;
      alteredCapsule['preflightDigest'] = await digest(facts);
      await expectLater(
        AutomationPlanRecord.fromJson(
          await signPlan(alteredCapsule),
          revision: rev,
        ),
        throwsFormatException,
      );
      final changed = copy(input);
      ((changed['effects'] as List).first as Map)['values'] = {
        'text': 'e\u0301',
      };
      await expectLater(
        AutomationPlanRecord.fromJson(await signPlan(changed), revision: rev),
        throwsFormatException,
      );
      final blocked = copy(input)
        ..addAll({
          'status': 'blocked',
          'reasons': [
            {'code': 'UNSUPPORTED', 'field': 'qualification', 'stepId': 'motd'},
          ],
          'effects': <Object?>[],
          'checks': <Object?>[],
        });
      expect(
        (await AutomationPlanRecord.fromJson(
          await signPlan(blocked),
          revision: rev,
        )).status,
        'blocked',
      );
      ((blocked['reasons'] as List).first as Map)['stepId'] = 'missing';
      await expectLater(
        AutomationPlanRecord.fromJson(await signPlan(blocked), revision: rev),
        throwsFormatException,
      );
    },
  );
  test(
    'every service state and enabled variant has complete ordered checks',
    () async {
      for (final resource in ['postgresql.service', 'clickhouse.service']) {
        for (final state in ['started', 'stopped', 'restarted']) {
          for (final enabled in <bool?>[null, false, true]) {
            final step = <String, Object?>{
              'id': 'svc',
              'kind': 'service',
              'resourceId': resource,
              'state': state,
              if (enabled != null) 'enabled': enabled,
            };
            final rev = await revision(steps: [step]);
            final effects = <Map<String, Object?>>[
              {
                'id': 'state',
                'sourceStepId': 'svc',
                'kind': 'service_state',
                'resourceId': resource,
                'state': state,
              },
              if (enabled != null)
                {
                  'id': 'enabled',
                  'sourceStepId': 'svc',
                  'kind': 'service_enabled',
                  'resourceId': resource,
                  'enabled': enabled,
                },
            ];
            final checks = <Map<String, Object?>>[
              {
                'id': 'state_check',
                'effectId': 'state',
                'resourceId': resource,
                'kind': 'service_state',
                'state': state == 'stopped' ? 'inactive' : 'active',
              },
              if (state == 'restarted')
                {
                  'id': 'restart_check',
                  'effectId': 'state',
                  'resourceId': resource,
                  'kind': 'service_restarted',
                  'baselineFingerprint': hash,
                },
              if (state != 'stopped')
                {
                  'id': 'sql_check',
                  'effectId': 'state',
                  'resourceId': resource,
                  'kind': 'sql',
                  'expected': 1,
                },
              if (enabled != null)
                {
                  'id': 'enabled_check',
                  'effectId': 'enabled',
                  'resourceId': resource,
                  'kind': 'service_enabled',
                  'enabled': enabled,
                },
            ];
            final input = await programPlan(
              rev,
              effects: effects,
              checks: checks,
              resources: [resource],
            );
            expect(
              (await AutomationPlanRecord.fromJson(
                input,
                revision: rev,
              )).status,
              'runnable',
            );
            final missing = copy(input);
            (missing['checks'] as List).removeLast();
            await expectLater(
              AutomationPlanRecord.fromJson(
                await signPlan(missing),
                revision: rev,
              ),
              throwsFormatException,
            );
          }
        }
      }
    },
  );

  test('DB settings require ordered file check, runtime settings and restart health', () async {
    for (final prefix in ['postgresql', 'clickhouse']) {
      final values = prefix == 'postgresql'
          ? <String, Object?>{'max_connections': 100, 'shared_buffers_mb': 128}
          : <String, Object?>{
              'max_connections': 100,
              'max_server_memory_usage_mb': 1024,
            };
      final config = '$prefix.settings', service = '$prefix.service';
      final rev = await revision(
        steps: [
          {
            'id': 'settings',
            'kind': 'config_file',
            'resourceId': config,
            'values': values,
          },
        ],
      );
      final input = await programPlan(
        rev,
        resources: [config, service],
        effects: [
          {
            'id': 'write',
            'sourceStepId': 'settings',
            'kind': 'config_file',
            'resourceId': config,
            'values': values,
            'renderedDigest': hash,
          },
          {
            'id': 'restart',
            'sourceStepId': 'settings',
            'kind': 'service_state',
            'resourceId': service,
            'state': 'restarted',
          },
        ],
        checks: [
          {
            'id': 'file',
            'effectId': 'write',
            'resourceId': config,
            'kind': 'file_digest',
            'digest': hash,
          },
          {
            'id': 'settings',
            'effectId': 'write',
            'resourceId': config,
            'kind': 'settings',
            'values': values,
          },
          {
            'id': 'active',
            'effectId': 'restart',
            'resourceId': service,
            'kind': 'service_state',
            'state': 'active',
          },
          {
            'id': 'restarted',
            'effectId': 'restart',
            'resourceId': service,
            'kind': 'service_restarted',
            'baselineFingerprint': hash,
          },
          {
            'id': 'sql',
            'effectId': 'restart',
            'resourceId': service,
            'kind': 'sql',
            'expected': 1,
          },
        ],
      );
      expect(
        (await AutomationPlanRecord.fromJson(input, revision: rev)).status,
        'runnable',
      );
      for (final change in <void Function(Map<String, Object?>)>[
        (v) => v['effects'] = (v['effects'] as List).reversed.toList(),
        (v) => v['checks'] = (v['checks'] as List).reversed.toList(),
        (v) =>
            ((v['checks'] as List)[3] as Map)['baselineFingerprint'] = 'b' * 64,
        (v) => ((v['effects'] as List)[1] as Map)['sourceStepId'] = 'another',
        (v) =>
            ((v['checks'] as List)[1] as Map)['values'] = <String, Object?>{},
      ]) {
        final changed = copy(input);
        change(changed);
        await expectLater(
          AutomationPlanRecord.fromJson(await signPlan(changed), revision: rev),
          throwsFormatException,
        );
      }
    }
  });

  test('install recipe binds actual catalog version and excludes resource conflicts', () async {
    final descriptor = await recipes.signed(recipes.recipe());
    Map<String, Object?> install(String version) => {
      'id': 'install',
      'kind': 'install_recipe',
      'recipeDigest': descriptor['digest'],
      'version': version,
    };
    final effects = <Map<String, Object?>>[
      {
        'id': 'install',
        'sourceStepId': 'install',
        'kind': 'install_recipe',
        'recipeDigest': descriptor['digest'],
        'version': '16.10',
      },
    ];
    final checks = <Map<String, Object?>>[
      {
        'id': 'installed',
        'effectId': 'install',
        'resourceId': 'recipe.postgresql16',
        'kind': 'recipe',
        'recipeDigest': descriptor['digest'],
      },
    ];
    final rev = await revision(steps: [install('16.10')]);
    final input = await programPlan(
      rev,
      effects: effects,
      checks: checks,
      selectedRecipes: [descriptor],
    );
    final loaded = await AutomationPlanRecord.fromJson(input, revision: rev);
    expect(loaded.baseObservations, isEmpty);
    await loaded.validateCurrentObservations([], now: DateTime.parse(created));
    final wrong = await revision(steps: [install('16.11')]);
    final wrongInput = await programPlan(
      wrong,
      effects: effects,
      checks: checks,
      selectedRecipes: [descriptor],
    );
    await expectLater(
      AutomationPlanRecord.fromJson(wrongInput, revision: wrong),
      throwsFormatException,
    );
    final conflict = await revision(
      steps: [
        install('16.10'),
        {
          'id': 'svc',
          'kind': 'service',
          'resourceId': 'postgresql.service',
          'state': 'started',
        },
      ],
    );
    final conflicting = await programPlan(
      conflict,
      effects: effects,
      checks: checks,
      selectedRecipes: [descriptor],
      resources: ['postgresql.service'],
    );
    await expectLater(
      AutomationPlanRecord.fromJson(conflicting, revision: conflict),
      throwsFormatException,
    );
    final unselected = await plan(await revision());
    final facts = unselected['preflight'] as Map<String, Object?>;
    facts['recipes'] = [descriptor];
    facts['aptIndexDigests'] = [hash];
    unselected['preflightDigest'] = await digest(facts);
    await expectLater(
      AutomationPlanRecord.fromJson(
        await signPlan(unselected),
        revision: await revision(),
      ),
      throwsFormatException,
    );
  });
  test(
    'capsule snapshots/digests and descriptor references are immutable',
    () async {
      final rev = await revision();
      final input = await capsule(rev);
      final recipe = await recipes.signed(recipes.recipe());
      input['recipes'] = [recipe];
      input['aptIndexDigests'] = [hash];
      final expected = copy(input);
      final pending = AutomationPreflightCapsule.fromJson(input);
      input['runtimeVersion'] = 'tampered';
      (recipe['packagePins'] as List).clear();
      final record = await pending;
      expect(record.toJson(), expected);
      expect(record.digest, await digest(expected));
      expect(record.recipes.single.id, 'postgresql16');
      expect(() => record.baseObservations.clear(), throwsUnsupportedError);
      final output = record.toJson();
      (output['recipes'] as List).clear();
      expect(record.toJson(), expected);
    },
  );

  test(
    'capsule rejects malformed, duplicate and unbound nested facts',
    () async {
      final rev = await revision();
      final mutations = <void Function(Map<String, Object?>)>[
        (v) => v['extra'] = true,
        (v) => v.remove('compilerDigest'),
        (v) => v['environment'] = 'future',
        (v) => v['format'] = 2,
        (v) => v['operationId'] = 'x',
        (v) => v['runtimeVersion'] = '{{shell}}',
        (v) => v['runtimeLockDigest'] = null,
        (v) => v['aptIndexDigests'] = [hash, hash],
        (v) => (v['baseObservations'] as List).add(
          (v['baseObservations'] as List).first,
        ),
        (v) => ((v['baseObservations'] as List).first as Map)['resourceId'] =
            'netbird.service',
        (v) => ((v['baseObservations'] as List).first as Map)['fingerprint'] =
            null,
      ];
      for (final change in mutations) {
        final input = await capsule(rev);
        change(input);
        await expectLater(
          AutomationPreflightCapsule.fromJson(input),
          throwsFormatException,
        );
      }
      final input = await capsule(rev)
        ..['recipes'] = [await recipes.signed(recipes.recipe())];
      await expectLater(
        AutomationPreflightCapsule.fromJson(input),
        throwsFormatException,
      );
      input['aptIndexDigests'] = [hash];
      (input['recipes'] as List).add((input['recipes'] as List).first);
      await expectLater(
        AutomationPreflightCapsule.fromJson(input),
        throwsFormatException,
      );
    },
  );

  test(
    'runnable plan exact bindings, hash and snapshots before await',
    () async {
      final rev = await revision();
      final input = await plan(rev);
      final expected = copy(input);
      final pending = AutomationPlanRecord.fromJson(input, revision: rev);
      (input['exactParams'] as Map)['greeting'] = 'attacker';
      ((input['effects'] as List).first as Map)['renderedDigest'] = 'b' * 64;
      final record = await pending;
      expect(record.toJson(), expected);
      expect(record.key, rev.key);
      expect(record.serverRevision, '9223372036854775807');
      (record.toJson()['checks'] as List).clear();
      expect(record.toJson(), expected);
      expect(record.isWithinLifetimeAt(DateTime.parse(created)), isTrue);
      expect(record.isWithinLifetimeAt(DateTime.parse(expires)), isFalse);
      expect(
        record.isWithinLifetimeAt(
          DateTime.parse(created).subtract(const Duration(milliseconds: 1)),
        ),
        isFalse,
      );
      // Historical loading does not consult current time or restore authority.
      expect(
        await AutomationPlanRecord.fromJson(expected, revision: rev),
        isA<AutomationPlanRecord>(),
      );
    },
  );

  test(
    'blocked plan has explicit missing evidence and cannot retain effects',
    () async {
      final rev = await revision();
      final input = await plan(rev);
      input.addAll({
        'status': 'blocked',
        'reasons': [
          {'code': 'EXECUTOR_UNAVAILABLE', 'field': 'executor', 'stepId': null},
        ],
        'effects': <Object?>[],
        'checks': <Object?>[],
        'preflight': null,
        'preflightDigest': null,
        'hostId': null,
        'registryDigest': null,
        'baseObservations': <Object?>[],
      });
      expect(
        (await AutomationPlanRecord.fromJson(
          await signPlan(input),
          revision: rev,
        )).status,
        'blocked',
      );
      for (final field in ['preflightDigest', 'hostId', 'registryDigest']) {
        final changed = copy(input)..[field] = field == 'hostId' ? host : hash;
        await expectLater(
          AutomationPlanRecord.fromJson(await signPlan(changed), revision: rev),
          throwsFormatException,
        );
      }
      input['reasons'] = [];
      await expectLater(
        AutomationPlanRecord.fromJson(await signPlan(input), revision: rev),
        throwsFormatException,
      );
    },
  );

  test(
    'plan rejects tampered tuple, counters, defaults, TTL and full program',
    () async {
      final rev = await revision();
      final mutations = <void Function(Map<String, Object?>)>[
        (v) => v['extra'] = true,
        (v) => v['profileRevision'] = 2,
        (v) => v['profileId'] = server,
        (v) => v['workspaceId'] = server,
        (v) => v['profileDigest'] = hash,
        (v) => v['serverRevision'] = 1,
        (v) => v['serverRevision'] = '1',
        (v) => v['trustRevision'] = '1',
        (v) => v['exactParams'] = <String, Object?>{},
        (v) => (v['exactParams'] as Map)['greeting'] = 'changed',
        (v) => v['desired'] = <Object?>[],
        (v) => v['effects'] = <Object?>[],
        (v) => v['checks'] = <Object?>[],
        (v) =>
            ((v['effects'] as List).first as Map)['sourceStepId'] = 'missing',
        (v) => ((v['effects'] as List).first as Map)['resourceId'] =
            'postgresql.settings',
        (v) => ((v['checks'] as List).first as Map)['effectId'] = 'missing',
        (v) => ((v['checks'] as List).first as Map)['digest'] = 'b' * 64,
        (v) => (v['checks'] as List).add((v['checks'] as List).first),
        (v) => v['baseObservations'] = <Object?>[],
        (v) => v['expiresAt'] = '2026-10-21T10:05:00.001Z',
        (v) => v['createdAt'] = '2026-10-21T09:59:59.999Z',
        (v) => v['hostId'] = server,
        (v) => v['registryDigest'] = 'b' * 64,
        (v) => v['preflightDigest'] = hash,
        (v) => v['reasons'] = [
          {'code': 'INTERNAL', 'field': 'executor', 'stepId': null},
        ],
      ];
      for (final change in mutations) {
        final input = await plan(rev);
        change(input);
        await expectLater(
          AutomationPlanRecord.fromJson(await signPlan(input), revision: rev),
          throwsFormatException,
        );
      }
      final badHash = await plan(rev)
        ..['digest'] = hash;
      await expectLater(
        AutomationPlanRecord.fromJson(badHash, revision: rev),
        throwsFormatException,
      );
    },
  );

  test(
    'fresh comparison binds captured server counters and exact fingerprints',
    () async {
      final rev = await revision();
      final record = await AutomationPlanRecord.fromJson(
        await plan(rev),
        revision: rev,
      );
      final now = DateTime.parse(created).add(const Duration(seconds: 15));
      await record.validateCurrentObservations([
        ManagedResourceObservationRecord.fromJson(observation()),
      ], now: now);
      for (final field in [
        'workspaceId',
        'serverId',
        'hostId',
        'resourceRegistryDigest',
        'targetRevision',
        'accessRevision',
        'status',
      ]) {
        final input = observation();
        input[field] = switch (field) {
          'resourceRegistryDigest' => 'b' * 64,
          'targetRevision' => '9223372036854775806',
          'accessRevision' => '2',
          'status' => 'stale',
          _ => requestId,
        };
        await expectLater(
          record.validateCurrentObservations([
            ManagedResourceObservationRecord.fromJson(input),
          ], now: now),
          throwsFormatException,
        );
      }
      await expectLater(
        record.validateCurrentObservations([], now: now),
        throwsFormatException,
      );
      await expectLater(
        record.validateCurrentObservations([
          ManagedResourceObservationRecord.fromJson(observation()),
        ], now: now.add(const Duration(milliseconds: 1))),
        throwsFormatException,
      );
      final reread = observation()..['observedAt'] = '2026-10-21T10:02:00.000Z';
      await record.validateCurrentObservations([
        ManagedResourceObservationRecord.fromJson(reread),
      ], now: DateTime.parse('2026-10-21T10:02:00.000Z'));
    },
  );
}
