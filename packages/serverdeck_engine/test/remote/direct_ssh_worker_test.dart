import 'dart:convert';

import 'package:serverdeck_engine/remote/direct_ssh.dart';
import 'package:serverdeck_engine/remote/direct_ssh_records.dart';
import 'package:serverdeck_engine/storage/state_store.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/direct_ssh_runtime.dart';
import 'package:test/test.dart';

import '../storage/actual_state_store_test.dart' as actual;
import '../storage/actual_plan_job_store_test.dart' as commands;
import '../support/actual_plan_fixture.dart';
import '../support/schema3_fixture.dart' as foundation;
import '../support/direct_ssh_byte_peer.dart' show directOutput;

// Structural RAM metadata only: not actual host ownership or native permission.
Future<
  (AutomationJobRecord, AutomationPlanRecord, ManagedResourceObservationRecord)
>
dispatched({String message = 'actual unit storage'}) async {
  final setup = await actual.Setup.create(), store = await setup.open();
  final server = store.state.profiles[foundation.profile]!;
  final baseline = ManagedResourceObservationRecord.fromTrustedJson({
    'workspaceId': foundation.workspace,
    'serverId': server.id,
    'resourceId': 'system.motd',
    'targetRevision': server.revision,
    'connectionRevision': server.connectionRevision,
    'accessRevision': server.credentialRevision,
    'trustRevision': server.trustRevision,
    'hostId': actual.id(999),
    'resourceRegistryDigest': DirectSshRuntime.registryDigest,
    'observedAt': actual.now().toIso8601String(),
    'status': 'known',
    'value': {
      'exists': true,
      'fileDigest': 'c' * 64,
      'baselineDigest': 'd' * 64,
      'values': {'text': 'prior\n'},
    },
  });
  final fixture = await planFixture(
    store,
    40,
    directSsh: true,
    exactParameters: {'message': message},
    baselineFingerprints: {'system.motd': await baseline.fingerprint()},
  );
  await persist(store, fixture);
  await approve(store, fixture.$2, 50);
  final saved = await commands.job(
    store,
    'job.apply',
    60,
    fixture.$2.id,
    verifiedDigest: fixture.$2.toJson()['digest'] as String,
  );
  final job = await store.authorizeDirectSshStep(
    jobId: saved['jobId'] as String,
    expectedSequence: 2,
    stepId: 'e1',
    bootIdHash: fixture.$2.preflight!.toJson()['bootIdHash'] as String,
    observedUptimeMs: 1000,
    elapsedSinceProbe: () => Duration.zero,
    originGrantId: null,
    expectedGrantRevision: null,
    clock: actual.now,
    revalidate: () {},
  );
  return (job, fixture.$2, baseline);
}

void main() {
  tearDown(() => expect(StateStore.hasOpenReservation, isFalse));
  test('worker transports literal shell-shaped text as data and retains the bounded permit', () async {
    const message = r'$(touch /tmp/serverdeck-injected); ${HOME} "quoted" & |';
    final (job, plan, baseline) = await dispatched(message: message);
    final step = await DirectSshStep.capture(job, plan, baseline);
    final worker = utf8.decode(base64.decode(step.workerBase64));
    expect(worker, isNot(contains(message)));
    expect(worker, contains(base64.encode(utf8.encode(message + '\n'))));
    expect(
      worker,
      contains('issued_uptime=' + job.sshDispatch!.issuedUptimeMs.toString()),
    );
    expect(
      worker,
      contains('expires_uptime=' + job.sshDispatch!.expiresUptimeMs.toString()),
    );
    expect(worker, contains('no_start 42'));
    expect(worker, contains('TZ=UTC0'));
    final status = DirectSshCommand.stepStatus(
      await DirectSshStep.reference(job, plan),
    );
    expect(status.script, isNot(contains('exclusive_input()')));
    expect(status.script, isNot(contains('/usr/bin/mv')));
    expect(status.script, isNot(contains('/usr/bin/systemd-run')));
    expect(status.outputLimit, 512 * 1024);
    expect(status.maximumDuration, const Duration(seconds: 10));
  });
  test('recovery reconstructs the exact worker from retained baseline without local preflight cache', () async {
    final (job, plan, baseline) = await dispatched();
    final step = await DirectSshStep.capture(job, plan, baseline);
    String record(String state) => ascii.decode(
      DirectHostRecord.create('step', {
        ...step.intent.fields,
        'state': state,
        if (state == 'succeeded') ...{
          'exitCode': '0',
          'checkDigest': step.checksDigest(true),
        },
      }).encode(),
    );
    final rows = <String, String>{
      'intent': ascii.decode(step.intent.encode()),
      'start': record('started'),
      'result': record('succeeded'),
      'baseline': step.baselineJson,
      'checks': step.checksJson(true),
      'workerDigest': step.workerDigest,
      'bootHash': step.dispatch.bootIdHash,
      'cgroup': 'absent',
      'unit':
          'Id=' +
          step.unit +
          '\nLoadState=loaded\nActiveState=active\nSubState=exited\n'
              'MainPID=0\nControlPID=0\nControlGroup=\nTransient=yes\n'
              'FragmentPath=/run/systemd/transient/' +
          step.unit +
          '\nType=oneshot\nRemainAfterExit=yes',
    };
    final recovered = AutomationJobRecord.fromJson({
      ...job.toJson(),
      'sshDispatch': {...job.sshDispatch!.toJson(), 'state': 'unknown'},
    });
    final reference = await DirectSshStep.reference(recovered, plan);
    expect(
      () => DirectSshCommand.launchStep(reference),
      throwsA(isA<DirectSshFailure>()),
    );
    final snapshot = await DirectStepSnapshot.capture(
      recovered,
      plan,
      directOutput(rows),
    );
    expect(snapshot.hasCompleteReceipt, isTrue);
    expect(snapshot.step.workerDigest, step.workerDigest);
    expect(snapshot.state, 'succeeded');
    final active = await DirectStepSnapshot.capture(
      recovered,
      plan,
      directOutput({...rows, 'cgroup': 'populated 1\nfrozen 0'}),
    );
    expect(active.hasCompleteReceipt, isFalse);
    final reboot = await DirectStepSnapshot.capture(
      recovered,
      plan,
      directOutput({...rows, 'bootHash': 'e' * 64}),
    );
    expect(reboot.hasCompleteReceipt, isFalse);
    for (final mutation in [
      {...rows, 'workerDigest': '0' * 64},
      {...rows, 'result': ''},
      {...rows, 'baseline': ''},
      {...rows, 'checks': '[]'},
    ]) {
      try {
        final incomplete = await DirectStepSnapshot.capture(
          recovered,
          plan,
          directOutput(mutation),
        );
        expect(incomplete.hasCompleteReceipt, isFalse);
      } on DirectSshFailure {
        /* Malformed input is also an explicit refusal. */
      }
    }
  });
  test('one closed effect binds exact retained dispatch and baseline, never caller shell', () async {
    final (job, plan, baseline) = await dispatched();
    final step = await DirectSshStep.capture(job, plan, baseline);
    final command = DirectSshCommand.launchStep(step);
    expect(command.mutates, isTrue);
    expect(command.kind, 'launch');
    expect(command.script, isNot(contains('serverdeck-executor')));
    expect(command.script, isNot(contains('ansible')));
    expect(command.script, isNot(contains('python')));
    expect(utf8.encode(command.script).length, lessThanOrEqualTo(256 * 1024));
    expect(command.script, contains('/usr/bin/systemd-run --no-block'));
    expect(command.script, contains('StandardInput=null'));
    expect(command.script, contains('StandardOutput=null'));
    expect(command.script, contains('StandardError=null'));
    expect(command.script, contains('/usr/bin/flock -u 9'));
    expect(step.unit, contains(job.hostAttemptId.replaceAll('-', '')));
    expect(step.intent.fields['token'], job.sshDispatch!.token);
    expect(step.intent.fields['stepDigest'], job.sshDispatch!.stepDigest);
    final worker = utf8.decode(base64.decode(step.workerBase64));
    expect(worker, contains('open_lock'));
    expect(
      worker.indexOf(r'exclusive_record "$expected_start"'),
      lessThan(worker.indexOf('apply_effect')),
    );
    expect(worker, contains('current_uptime'));
    expect(worker, contains('expires_uptime'));
    expect(worker, contains('/proc/sys/kernel/random/boot_id'));
    expect(worker, contains(r'/usr/bin/mv -T -- "$temporary" /etc/motd'));
    expect(worker, isNot(contains('kill')));
    expect(worker, isNot(contains('systemctl stop')));
  });
  test('unknown dispatch is inspectable but cannot launch and mismatched baseline is refused', () async {
    final (job, plan, baseline) = await dispatched();
    final changed = AutomationJobRecord.fromJson({
      ...job.toJson(),
      'sshDispatch': {...job.sshDispatch!.toJson(), 'state': 'unknown'},
    });
    final step = await DirectSshStep.capture(changed, plan, baseline);
    expect(
      () => DirectSshCommand.launchStep(step),
      throwsA(isA<DirectSshFailure>()),
    );
    expect(DirectSshCommand.stepStatus(step).mutates, isFalse);
    final foreign = ManagedResourceObservationRecord.fromTrustedJson({
      ...baseline.toJson(),
      'hostId': actual.id(998),
    });
    await expectLater(
      DirectSshStep.capture(job, plan, foreign),
      throwsA(isA<DirectSshFailure>()),
    );
  });
}
