import 'package:serverdeck_locald/automation/job_session.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:test/test.dart';

import '../../../serverdeck_protocol/test/automation_plan_records_test.dart'
    as p;
import '../../../serverdeck_protocol/test/trusted_target_records_test.dart'
    as t;

void main() {
  late AutomationPlanRecord plan;
  late Map<String, Object?> target;
  late Object? boot;
  setUp(() async {
    final revision = await p.revision();
    plan = await AutomationPlanRecord.fromTrustedJson(
      await t.plan(revision),
      revision: revision,
    );
    target = {
      'workspaceId': plan.workspaceId,
      'serverId': plan.serverId,
      'targetRevision': plan.serverRevision,
      'connectionRevision': plan.connectionRevision,
      'accessRevision': plan.accessRevision,
      'trustRevision': plan.trustRevision,
    };
    boot = plan.preflight!.toJson()['bootIdHash'];
  });

  void validate(
    JobSessionUse use, {
    String? host,
    String? registry,
    Object? currentBoot,
  }) => validateJobSession(
    plan: plan,
    target: target,
    hostId: host ?? plan.hostId!,
    registryDigest: registry ?? plan.registryDigest!,
    bootIdHash: currentBoot ?? boot,
    use: use,
  );

  test(
    'confirmed same-host recovery permits new credential and trust epochs',
    () {
      target.addAll({
        'targetRevision': '7',
        'connectionRevision': '3',
        'accessRevision': '4',
        'trustRevision': '7',
      });
      validate(
        JobSessionUse.control,
        registry: 'b' * 64,
        currentBoot: 'c' * 64,
      );
      for (final use in [JobSessionUse.admission, JobSessionUse.effect]) {
        expect(() => validate(use), throwsStateError);
      }
    },
  );

  test(
    'recovery cannot substitute another workspace, profile or physical host',
    () {
      for (final field in ['workspaceId', 'serverId']) {
        final original = target[field];
        target[field] = p.profile;
        expect(() => validate(JobSessionUse.control), throwsStateError);
        target[field] = original;
      }
      expect(
        () => validate(JobSessionUse.control, host: p.profile),
        throwsStateError,
      );
    },
  );

  test(
    'new effect retains each original prerequisite after recovery is permitted',
    () {
      for (final field in [
        'targetRevision',
        'connectionRevision',
        'accessRevision',
        'trustRevision',
      ]) {
        final original = target[field];
        target[field] = '9';
        validate(JobSessionUse.control);
        expect(() => validate(JobSessionUse.effect), throwsStateError);
        expect(() => validate(JobSessionUse.admission), throwsStateError);
        target[field] = original;
      }
      expect(
        () => validate(JobSessionUse.effect, registry: 'b' * 64),
        throwsStateError,
      );
      validate(JobSessionUse.effect);
    },
  );

  test(
    'reboot invalidates admission while receipt observation remains possible',
    () {
      expect(
        () => validate(JobSessionUse.admission, currentBoot: 'b' * 64),
        throwsA(
          isA<StateError>().having((e) => e.message, 'code', 'PLAN_STALE'),
        ),
      );
      validate(JobSessionUse.control, currentBoot: 'b' * 64);
      validate(JobSessionUse.admission);
    },
  );
}
