import 'package:serverdeck_engine/automation/authority_commands.dart';
import 'package:serverdeck_engine/automation/job_commands.dart';
import 'package:serverdeck_engine/automation/plan_commands.dart';
import 'package:serverdeck_engine/automation/profile_commands.dart';
import 'package:test/test.dart';

const request = '12345678-1234-4234-9234-123456789a11';
const target = '12345678-1234-4234-9234-123456789a12';
const profile = '12345678-1234-4234-9234-123456789a13';

void main() {
  test('captured commands cannot acquire origin or execution identity from supplied fields', () {
    final input = <String, Object?>{
      'requestId': request,
      'serverId': target,
      'profileId': profile,
      'revision': 1,
      'parameters': <String, Object?>{'count': 3},
    };
    final plan = PlanCreateCommand.fromJson(input);
    (input['parameters'] as Map)['count'] = 4;
    expect(plan.parameters, {'count': 3});
    plan.parameters.clear();
    expect(plan.parameters, {'count': 3});
    expect(
      () => PlanCreateCommand.fromJson({...input, 'owner': true}),
      throwsFormatException,
    );
    expect(
      () => PlanCreateCommand.fromJson({
        ...input,
        'parameters': {'text': '{{ execute }}'},
      }),
      throwsFormatException,
    );
    final job = JobMutationCommand.parse('job.apply', {
      'requestId': request,
      'planId': target,
    });
    expect(job.canonicalRequest(null), {
      'operation': 'job.apply',
      'originGrantId': null,
      'params': {'planId': target},
    });
    expect(
      () => JobMutationCommand.parse('job.apply', {
        'requestId': request,
        'planId': target,
        'hostAttemptId': profile,
      }),
      throwsFormatException,
    );
  });

  test(
    'owner-only approval intent and authored bodies remain captured data',
    () {
      final approval = AutomationAuthorityCommand.parse('approval.decide', {
        'requestId': request,
        'approvalId': target,
        'planDigest': 'a' * 64,
        'decision': 'approved',
      });
      expect(approval.ownerOnly, isTrue);
      expect(
        () => AutomationAuthorityCommand.parse('approval.decide', {
          ...approval.toJson(),
          'originGrantId': profile,
        }),
        throwsFormatException,
      );
      final body = <String, Object?>{
        'format': 1,
        'environment': 'ubuntu24.04-amd64-systemd',
        'parameters': <String, Object?>{},
        'steps': <Object?>[],
      };
      final command = AutomationProfileCommand.parse('profile.create', {
        'requestId': request,
        'name': 'unit authored profile',
        'body': body,
      });
      body['format'] = 999;
      expect(command.body!.toJson()['format'], 1);
      expect(command.profileId, isNull);
      expect(command.canonicalRequest(null)['originGrantId'], isNull);
    },
  );
}
