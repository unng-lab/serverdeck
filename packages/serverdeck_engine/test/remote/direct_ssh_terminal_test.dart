import 'dart:convert';

import 'package:serverdeck_engine/remote/direct_ssh.dart';
import 'package:serverdeck_engine/remote/direct_ssh_records.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:test/test.dart';

import '../storage/actual_state_store_test.dart' as actual;
import '../support/direct_ssh_byte_peer.dart' show directOutput;
import 'direct_ssh_worker_test.dart' show dispatched;

String record(String kind, Map<String, String> fields) =>
    ascii.decode(DirectHostRecord.create(kind, fields).encode());
Map<String, String> completed(DirectSshStep step) => {
  'intent': ascii.decode(step.intent.encode()),
  'start': record('step', {...step.intent.fields, 'state': 'started'}),
  'result': record('step', {
    ...step.intent.fields,
    'state': 'succeeded',
    'exitCode': '0',
    'checkDigest': step.checksDigest(true),
  }),
  'baseline': step.baselineJson,
  'checks': step.checksJson(true),
  'workerDigest': step.workerDigest,
  'bootHash': step.dispatch.bootIdHash,
  'cgroup': 'absent',
  'unit': 'Id=' + step.unit + '\nLoadState=loaded\nActiveState=active\nSubState=exited\nMainPID=0\nControlPID=0\nControlGroup=\nTransient=yes\nFragmentPath=\nType=oneshot\nRemainAfterExit=yes',
};
Map<String, String> attemptRows(
  DirectSshStep step, {
  bool terminal = false,
  String planState = 'pending',
  bool foreign = false,
}) => {
  'presence': 'present',
  'disposition': 'snapshot',
  'owner': record(
    'owner',
    foreign
        ? {
            ...step.attempt.identity,
            'jobId': actual.id(300),
            'attemptId': actual.id(301),
            'planDigest': '0' * 64,
          }
        : step.attempt.identity,
  ),
  'admission': record('admission', step.attempt.identity),
  'plan': record('plan', {
    'planDigest': step.attempt.planDigest,
    'attemptId': step.attempt.attemptId,
    'terminal': planState,
  }),
  'stop': '',
  'terminal': terminal
      ? record('terminal', {
          ...step.attempt.identity,
          'state': 'succeeded',
          'checksDigest': step.checksDigest(true),
        })
      : '',
};

void main() {
  test('terminal metadata re-proves checks and preserves every completed durable prefix', () async {
    final (job, plan, baseline) = await dispatched();
    final step = await DirectSshStep.capture(job, plan, baseline);
    final receipt = await DirectStepSnapshot.capture(
      job,
      plan,
      directOutput(completed(step)),
    );
    final observed = ManagedResourceObservationRecord.fromTrustedJson({
      ...baseline.toJson(),
      'value': {
        'exists': true,
        'fileDigest': step.desiredDigest,
        'baselineDigest': 'e' * 64,
        'values': {'text': 'actual unit storage\n'},
      },
    });
    for (final prefix in [
      (false, 'pending'),
      (true, 'pending'),
      (true, 'succeeded'),
    ]) {
      final snapshot = DirectAttemptSnapshot.fromOutput(
        step.attempt,
        directOutput(
          attemptRows(step, terminal: prefix.$1, planState: prefix.$2),
        ),
      );
      final proof = DirectFinalization.capture(
        snapshot,
        receipt,
        observed,
        at: actual.now(),
      );
      expect(proof.historicalOnly, isFalse);
      final command = DirectSshCommand.finalizeAttempt(proof);
      expect(command.mutates, isTrue);
      expect(command.requiresApply, isFalse);
      expect(command.script, isNot(contains('/usr/bin/systemd-run')));
      expect(
        command.script,
        isNot(contains(r'/usr/bin/mv -T -- "$temporary" /etc/motd')),
      );
      expect(command.script, contains('publish_terminal'));
      expect(command.script, contains(r'/usr/bin/rm -- "$root/owner"'));
    }
    final released = DirectAttemptSnapshot.fromOutput(
      step.attempt,
      directOutput(
        attemptRows(
          step,
          terminal: true,
          planState: 'succeeded',
          foreign: true,
        ),
      ),
    );
    final historical = await DirectStepSnapshot.capture(
      job,
      plan,
      directOutput({...completed(step), 'bootHash': '0' * 64}),
    );
    final proof = DirectFinalization.capture(
      released,
      historical,
      null,
      at: actual.now(),
    );
    expect(proof.historicalOnly, isTrue);
    expect(proof.outcome.effects, 'confirmed');
    expect(proof.terminal.fields['state'], 'succeeded');
  });
  test('incomplete terminal prefixes and missing current factual proof cannot release an owner', () async {
    final (job, plan, baseline) = await dispatched();
    final step = await DirectSshStep.capture(job, plan, baseline);
    final receipt = await DirectStepSnapshot.capture(
      job,
      plan,
      directOutput(completed(step)),
    );
    final snapshot = DirectAttemptSnapshot.fromOutput(
      step.attempt,
      directOutput(attemptRows(step)),
    );
    expect(
      () =>
          DirectFinalization.capture(snapshot, receipt, null, at: actual.now()),
      throwsA(isA<DirectSshFailure>()),
    );
    final impossible = DirectAttemptSnapshot.fromOutput(
      step.attempt,
      directOutput(attemptRows(step, terminal: true, foreign: true)),
    );
    expect(
      () => DirectFinalization.capture(
        impossible,
        receipt,
        null,
        at: actual.now(),
      ),
      throwsA(isA<DirectSshFailure>()),
    );
  });
}
