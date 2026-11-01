import 'package:serverdeck_engine/remote/direct_ssh.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:test/test.dart';

import '../support/direct_ssh_byte_peer.dart' show directOutput;
import 'direct_ssh_terminal_test.dart' show attemptRows, record;
import 'direct_ssh_worker_test.dart' show dispatched;

void main() {
  test(
    'no-dispatch cancellation requires durable cancel and exact admitted stop',
    () async {
      final (issued, plan, baseline) = await dispatched();
      final step = await DirectSshStep.capture(issued, plan, baseline);
      final job = AutomationJobRecord.fromJson({
        ...issued.toJson(),
        'state': 'cancel-requested',
        'cancelRequested': true,
        'sshDispatch': null,
      });
      final rows = attemptRows(step);
      rows['stop'] = record('stop', {
        'attemptId': step.attempt.attemptId,
        'planDigest': step.attempt.planDigest,
      });
      for (final prefix in [0, 1, 2, 3]) {
        final snapshotRows = {...rows};
        if (prefix > 0)
          snapshotRows['terminal'] = record('terminal', {
            ...step.attempt.identity,
            'state': 'cancelled',
            'checksDigest': '4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',
          });
        if (prefix > 1)
          snapshotRows['plan'] = record('plan', {
            'attemptId': step.attempt.attemptId,
            'planDigest': step.attempt.planDigest,
            'terminal': 'cancelled',
          });
        if (prefix == 3) snapshotRows['owner'] = '';
        final proof = DirectUndispatchedCancellation.capture(
          job,
          plan,
          DirectAttemptSnapshot.fromOutput(
            step.attempt,
            directOutput(snapshotRows),
          ),
        );
        final command = DirectSshCommand.cancelUndispatched(proof);
        expect(command.mutates, isTrue);
        expect(command.requiresApply, isFalse);
        expect(command.maximumDuration, const Duration(seconds: 10));
        expect(proof.historicalOnly, prefix == 3);
        expect(proof.outcome.toJson()['effects'], 'none');
        expect(proof.outcome.checks, isEmpty);
        expect(command.script, contains('no_step_inputs'));
        expect(
          command.script,
          contains(
            'LoadState,ActiveState,SubState,MainPID,ControlPID,ControlGroup,FragmentPath',
          ),
        );
        expect(command.script, contains('publish_terminal'));
        expect(command.script, isNot(contains('/usr/bin/systemd-run')));
        expect(command.script, isNot(contains('/etc/motd')));
      }
      for (final fault in ['stop', 'admission', 'owner']) {
        final broken = {...rows, fault: ''};
        expect(
          () => DirectUndispatchedCancellation.capture(
            job,
            plan,
            DirectAttemptSnapshot.fromOutput(
              step.attempt,
              directOutput(broken),
            ),
          ),
          throwsA(isA<DirectSshFailure>()),
        );
      }
      expect(
        () => DirectUndispatchedCancellation.capture(
          issued,
          plan,
          DirectAttemptSnapshot.fromOutput(step.attempt, directOutput(rows)),
        ),
        throwsA(isA<DirectSshFailure>()),
      );
    },
  );
}
