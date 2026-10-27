import 'dart:convert';

import 'package:serverdeck_protocol/automation/models.dart';
import 'package:test/test.dart';

import 'automation_observation_records_test.dart' as observed;
import 'automation_plan_records_test.dart' as planned;

Map<String, Object?> observation() => {
  ...planned.observation(),
  'targetRevision': '2',
  'connectionRevision': '1',
  'trustRevision': '2',
};

Future<Map<String, Object?>> plan(AutomationRevisionRecord revision) async {
  final value = await planned.plan(revision);
  final baseline = [
    {
      'resourceId': 'system.motd',
      'fingerprint': await ManagedResourceObservationRecord.fromTrustedJson(
        observation(),
      ).fingerprint(),
    },
  ];
  final preflight = (value['preflight'] as Map<String, Object?>)
    ..['baseObservations'] = baseline;
  return planned.signPlan({
    ...value,
    'serverRevision': '2',
    'connectionRevision': '1',
    'trustRevision': '2',
    'baseObservations': baseline,
    'preflightDigest': await planned.digest(preflight),
  });
}

void main() {
  test(
    'schema3 known/unknown observations capture independent trust epochs',
    () async {
      final value = observation();
      final record = ManagedResourceObservationRecord.fromTrustedJson(value);
      expect(record.connectionRevision, '1');
      expect(record.trustRevision, '2');
      expect(record.toJson(), value);
      expect(
        () => ManagedResourceObservationRecord.fromJson(value),
        throwsFormatException,
      );
      final unknown = {
        ...value,
        'status': 'unknown',
        'hostId': null,
        'resourceRegistryDigest': null,
        'value': null,
      };
      expect(
        ManagedResourceObservationRecord.fromTrustedJson(unknown).toJson(),
        unknown,
      );
      expect(
        () => ManagedResourceObservationRecord.fromJson(unknown),
        throwsFormatException,
      );
      (value['value'] as Map).clear();
      expect(record.toJson(), observation());
    },
  );

  test('schema3 plan uses captured epochs and exact nested baseline fingerprints', () async {
    final revision = await planned.revision();
    final input = await plan(revision);
    final record = await AutomationPlanRecord.fromTrustedJson(
      input,
      revision: revision,
    );
    expect(record.toJson(), input);
    expect(record.serverRevision, '2');
    expect(record.connectionRevision, '1');
    expect(record.trustRevision, '2');
    await expectLater(
      AutomationPlanRecord.fromJson(input, revision: revision),
      throwsFormatException,
    );
    await record.validateCurrentObservations([
      ManagedResourceObservationRecord.fromTrustedJson(observation()),
    ], now: DateTime.parse(planned.created));
    // A later confirmation invalidates current evidence, while retained history
    // continues to decode against its own captured target and original digest.
    final changed = {
      ...observation(),
      'targetRevision': '3',
      'trustRevision': '3',
    };
    await expectLater(
      record.validateCurrentObservations([
        ManagedResourceObservationRecord.fromTrustedJson(changed),
      ], now: DateTime.parse(planned.created)),
      throwsFormatException,
    );
    expect(
      (await AutomationPlanRecord.fromTrustedJson(
        input,
        revision: revision,
      )).toJson(),
      input,
    );
  });

  test(
    'old equal-counter history and digests stay byte-identical across modes',
    () async {
      final value = observed.observation();
      final oldObservation = ManagedResourceObservationRecord.fromJson(value);
      final trustedObservation =
          ManagedResourceObservationRecord.fromTrustedJson(value);
      expect(
        jsonEncode(trustedObservation.toJson()),
        jsonEncode(oldObservation.toJson()),
      );
      expect(
        await trustedObservation.fingerprint(),
        await oldObservation.fingerprint(),
      );
      final revision = await planned.revision();
      final input = await planned.plan(revision);
      final oldPlan = await AutomationPlanRecord.fromJson(
        input,
        revision: revision,
      );
      final trustedPlan = await AutomationPlanRecord.fromTrustedJson(
        input,
        revision: revision,
      );
      expect(jsonEncode(trustedPlan.toJson()), jsonEncode(oldPlan.toJson()));
      expect(trustedPlan.toJson()['digest'], oldPlan.toJson()['digest']);
      expect(trustedPlan.preflight!.toJson(), oldPlan.preflight!.toJson());
    },
  );

  test('both schema3 captured targets reject reversed, zero and overflowing epochs', () async {
    final revision = await planned.revision();
    final input = await plan(revision);
    for (final change in <Map<String, Object?>>[
      {'connectionRevision': '3'},
      {'trustRevision': '3'},
      {'accessRevision': '3'},
      {'connectionRevision': '2', 'trustRevision': '1'},
      {'connectionRevision': '0'},
      {'trustRevision': '9223372036854775808'},
      {'trustRevision': 2},
      {'schemaVersion': 3},
    ]) {
      expect(
        () => ManagedResourceObservationRecord.fromTrustedJson({
          ...observation(),
          ...change,
        }),
        throwsFormatException,
      );
      await expectLater(
        AutomationPlanRecord.fromTrustedJson(
          await planned.signPlan({...input, ...change}),
          revision: revision,
        ),
        throwsFormatException,
      );
    }
  });
}
