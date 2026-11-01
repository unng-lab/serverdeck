import 'package:cryptography/dart.dart';
import 'package:serverdeck_engine/automation/authority_commands.dart';
import 'package:serverdeck_engine/automation/compiler.dart';
import 'package:serverdeck_engine/automation/plan_commands.dart';
import 'package:serverdeck_engine/storage/state_store.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/codec.dart';

import '../storage/actual_state_store_test.dart' as actual;
import 'schema3_fixture.dart' as fixture;

String hash(Object? value) => const DartSha256()
    .hashSync(StrictCodec().canonical(value))
    .bytes
    .map((v) => v.toRadixString(16).padLeft(2, '0'))
    .join();

/// Structural storage fixture only, not a verified executor response or a
/// permission to execute. Uses the real compiler and strict record parsers.
Future<(PlanCreateCommand, AutomationPlanRecord)> planFixture(
  StateStore store,
  int request, {
  String? profileId,
  String? originGrantId,
  bool blocked = false,
}) async {
  profileId ??=
      (await actual.profile(
            store,
            actual.createProfile(request + 100),
          ))['profileId']
          as String;
  final revision = store.snapshot.automation.revisions['$profileId:1']!;
  final parameters = <String, Object?>{'message': 'actual unit storage'};
  final command = PlanCreateCommand.fromJson({
    'requestId': actual.id(request),
    'serverId': fixture.profile,
    'profileId': profileId,
    'revision': 1,
    'parameters': parameters,
  });
  final program = compileAutomation(
    body: revision.body,
    parameters: parameters,
    baselineFingerprints: {'system.motd': hash('synthetic prior file')},
    qualifiedRecipes: {},
  ).toJson();
  final capsule = blocked
      ? null
      : await AutomationPreflightCapsule.fromJson({
          'format': 1,
          'operationId': actual.id(request + 300),
          'hostId': actual.id(999),
          'environment': 'ubuntu24.04-amd64-systemd',
          'profileDigest': revision.key.bodyDigest,
          'inputDigest': hash(parameters),
          'runtimeVersion': 'synthetic-unit-runtime',
          for (final field in [
            'runtimeLockDigest',
            'compilerDigest',
            'registryDigest',
            'bootIdHash',
            'packageSnapshotDigest',
            'expectedPackageSnapshotDigest',
            'netbirdSnapshotDigest',
          ])
            field: hash(
              field == 'expectedPackageSnapshotDigest'
                  ? 'packageSnapshotDigest'
                  : field,
            ),
          'aptIndexDigests': <String>[],
          'recipes': <Object?>[],
          'baseObservations': [
            {
              'resourceId': 'system.motd',
              'fingerprint': hash('synthetic prior file'),
            },
          ],
        });
  final server = store.state.profiles[fixture.profile]!;
  final doc = <String, Object?>{
    'workspaceId': fixture.workspace,
    'id': actual.id(request + 200),
    'requestId': command.requestId,
    'profileId': profileId,
    'profileRevision': 1,
    'profileDigest': revision.key.bodyDigest,
    'serverId': server.id,
    'serverRevision': server.revision,
    'connectionRevision': server.connectionRevision,
    'accessRevision': server.credentialRevision,
    'trustRevision': server.trustRevision,
    'hostId': capsule?.hostId,
    'registryDigest': capsule?.registryDigest,
    'exactParams': parameters,
    'inputDigest': hash(parameters),
    'desired': program['desired'],
    'baseObservations': capsule?.toJson()['baseObservations'] ?? <Object?>[],
    'effects': blocked ? <Object?>[] : program['effects'],
    'checks': blocked ? <Object?>[] : program['checks'],
    'preflight': capsule?.toJson(),
    'preflightDigest': capsule?.digest,
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
    'createdAt': actual.now().toIso8601String(),
    'expiresAt': actual.now().add(const Duration(minutes: 5)).toIso8601String(),
    'originGrantId': originGrantId,
  };
  doc['digest'] = hash(doc);
  return (
    command,
    await AutomationPlanRecord.fromTrustedJson(doc, revision: revision),
  );
}

Future<Map<String, Object?>> persist(
  StateStore store,
  (PlanCreateCommand, AutomationPlanRecord) fixture, {
  DateTime Function()? clock,
}) => store.persistTrustedPlan(
  fixture.$1,
  fixture.$2,
  originGrantId: null,
  expectedGrantRevision: null,
  clock: clock ?? actual.now,
);

Future<String> approve(
  StateStore store,
  AutomationPlanRecord plan,
  int request,
) async {
  final created = await store.mutateTrustedAuthority(
    AutomationAuthorityCommand.parse('approval.request', {
      'requestId': actual.id(request),
      'planId': plan.id,
    }),
    originGrantId: null,
    expectedGrantRevision: null,
    clock: actual.now,
  );
  final approvalId = created['approvalId'] as String;
  await store.mutateTrustedAuthority(
    AutomationAuthorityCommand.parse('approval.decide', {
      'requestId': actual.id(request + 1),
      'approvalId': approvalId,
      'planDigest': plan.toJson()['digest'],
      'decision': 'approved',
    }),
    originGrantId: null,
    expectedGrantRevision: null,
    clock: actual.now,
  );
  return approvalId;
}
