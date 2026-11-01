import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:serverdeck_engine/automation/compiler.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/direct_ssh_runtime.dart';
import 'package:test/test.dart';

String _id(int value) =>
    '12345678-1234-4234-9234-' + value.toString().padLeft(12, '0');
String _hash(Object? value) => const DartSha256()
    .hashSync(StrictCodec().canonical(value))
    .bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();

typedef _Fixture = ({
  AutomationRevisionRecord revision,
  Map<String, Object?> doc,
  Map<String, Object?> program,
});

Future<_Fixture> _fixture(String product, {bool direct = true}) async {
  final resource = product + '.settings', service = product + '.service';
  final values = product == 'postgresql'
      ? <String, Object?>{'max_connections': 100, 'shared_buffers_mb': 256}
      : <String, Object?>{
          'max_connections': 4096,
          'max_server_memory_usage_mb': 2048,
        };
  final body = AutomationBody.fromJson({
    'format': 1,
    'environment': DirectSshRuntime.environment,
    'parameters': <String, Object?>{},
    'steps': [
      {
        'id': 'configure',
        'kind': 'config_file',
        'resourceId': resource,
        'values': values,
      },
    ],
  });
  final at = DateTime.utc(2026, 11, 1);
  final revision = await AutomationRevisionRecord.fromJson({
    'workspaceId': _id(1),
    'profileId': _id(2),
    'revision': 1,
    'parentRevision': null,
    'bodyFormat': 1,
    'body': body.toJson(),
    'digest': await body.digest(),
    'authorGrantId': null,
    'createdAt': at.toIso8601String(),
  });
  final program = compileAutomation(
    body: body,
    parameters: {},
    baselineFingerprints: {resource: 'a' * 64, service: 'b' * 64},
    qualifiedRecipes: {},
    directSsh: direct,
  ).toJson();
  final capsule = await AutomationPreflightCapsule.fromJson({
    'format': direct ? 2 : 1,
    'operationId': _id(3),
    'hostId': _id(4),
    'environment': DirectSshRuntime.environment,
    'profileDigest': revision.key.bodyDigest,
    'inputDigest': _hash(<String, Object?>{}),
    'runtimeVersion': direct ? DirectSshRuntime.version : 'historical-runtime',
    'runtimeLockDigest': direct
        ? DirectSshRuntime.prerequisiteDigest
        : 'c' * 64,
    'compilerDigest': direct ? DirectSshRuntime.compilerDigest : 'd' * 64,
    'registryDigest': direct ? DirectSshRuntime.registryDigest : 'e' * 64,
    'bootIdHash': 'f' * 64,
    'packageSnapshotDigest': '0' * 64,
    'expectedPackageSnapshotDigest': '0' * 64,
    'netbirdSnapshotDigest': '1' * 64,
    'aptIndexDigests': <Object?>[],
    'recipes': <Object?>[],
    'baseObservations': [
      {'resourceId': resource, 'fingerprint': 'a' * 64},
      {'resourceId': service, 'fingerprint': 'b' * 64},
    ],
  });
  final document = <String, Object?>{
    'workspaceId': _id(1),
    'id': _id(5),
    'requestId': _id(6),
    'profileId': _id(2),
    'profileRevision': 1,
    'profileDigest': revision.key.bodyDigest,
    'serverId': _id(7),
    'serverRevision': '1',
    'connectionRevision': '1',
    'accessRevision': '1',
    'trustRevision': '1',
    'hostId': capsule.hostId,
    'registryDigest': capsule.registryDigest,
    'exactParams': <String, Object?>{},
    'inputDigest': _hash(<String, Object?>{}),
    'desired': program['desired'],
    'baseObservations': capsule.toJson()['baseObservations'],
    'effects': program['effects'],
    'checks': program['checks'],
    'preflight': capsule.toJson(),
    'preflightDigest': capsule.digest,
    'status': 'runnable',
    'reasons': <Object?>[],
    'createdAt': at.toIso8601String(),
    'expiresAt': at.add(const Duration(minutes: 5)).toIso8601String(),
    'originGrantId': null,
  };
  document['digest'] = _hash(document);
  return (revision: revision, doc: document, program: program);
}

Map<String, Object?> _copy(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, Object?>;

void _rehash(Map<String, Object?> value) {
  value.remove('digest');
  value['digest'] = _hash(value);
}

void main() {
  for (final product in ['postgresql', 'clickhouse']) {
    test(
      product + ' config and activation share exactly one authorized effect',
      () async {
        final fixture = await _fixture(product);
        final effects = fixture.program['effects'] as List;
        final checks = fixture.program['checks'] as List;
        expect(effects, hasLength(1));
        expect((effects.single as Map)['kind'], 'database_configuration');
        expect(
          (effects.single as Map)['serviceResourceId'],
          product + '.service',
        );
        expect(checks, hasLength(5));
        expect(checks.map((row) => (row as Map)['effectId']).toSet(), {'e1'});
        expect(checks.map((row) => (row as Map)['kind']).toSet(), {
          'file_digest',
          'settings',
          'service_state',
          'service_restarted',
          'sql',
        });
        final plan = await AutomationPlanRecord.fromTrustedJson(
          fixture.doc,
          revision: fixture.revision,
        );
        expect(plan.preflight!.isDirectSsh, isTrue);
      },
    );

    test(
      product + ' cannot drop activation checks or change their target',
      () async {
        final fixture = await _fixture(product);
        final missing = _copy(fixture.doc);
        (missing['checks'] as List).removeLast();
        final wrongTarget = _copy(fixture.doc);
        ((wrongTarget['effects'] as List).single
            as Map)['serviceResourceId'] = product == 'postgresql'
            ? 'clickhouse.service'
            : 'postgresql.service';
        final wrongBaseline = _copy(fixture.doc);
        ((wrongBaseline['effects'] as List).single
                as Map)['baselineServiceFingerprint'] =
            '0' * 64;
        for (final document in [missing, wrongTarget, wrongBaseline]) {
          _rehash(document);
          await expectLater(
            AutomationPlanRecord.fromTrustedJson(
              document,
              revision: fixture.revision,
            ),
            throwsFormatException,
          );
        }
      },
    );

    test(
      product + ' history and direct programs cannot be relabelled',
      () async {
        final direct = await _fixture(product);
        final historical = await _fixture(product, direct: false);
        final original = jsonEncode(historical.doc);
        final parsed = await AutomationPlanRecord.fromTrustedJson(
          historical.doc,
          revision: historical.revision,
        );
        expect(parsed.preflight!.isDirectSsh, isFalse);
        expect(jsonEncode(parsed.toJson()), original);
        expect(historical.program['effects'] as List, hasLength(2));
        for (final pair in [(direct, historical), (historical, direct)]) {
          final mixed = _copy(pair.$1.doc)
            ..['effects'] = pair.$2.program['effects']
            ..['checks'] = pair.$2.program['checks'];
          _rehash(mixed);
          await expectLater(
            AutomationPlanRecord.fromTrustedJson(
              mixed,
              revision: pair.$1.revision,
            ),
            throwsFormatException,
          );
        }
      },
    );
  }
}
