import 'dart:convert';
import 'dart:typed_data';

import 'package:serverdeck_engine/remote/direct_ssh.dart';
import 'package:serverdeck_engine/remote/direct_ssh_records.dart';
import 'package:test/test.dart';

import '../remote/ssh_io_policy_test.dart' as bytes;
import 'direct_ssh_byte_peer.dart';

/// Declared RAM OS files/unit facts at the SSH byte boundary. This does not run
/// or verify Linux shell/systemd. Actual APIs, authority, native-gate ownership,
/// local compiler, record parsers, job transitions and storage stay production.
final class DirectHostBytePeer {
  final reads = DirectSshBytePeer();
  final records = <String, String>{};
  final inputs = <String, String>{};
  final requests = <DirectSshCommand>[];
  final _attemptRecords = <String, Map<String, String>>{};
  final _attemptInputs = <String, Map<String, String>>{};
  final _attemptUnits = <String, String?>{};
  String? _selectedAttempt;
  int effects = 0;
  int launches = 0;
  bool stopBeforeStart = false;
  bool failPostcheck = false;
  bool dropReserveAck = false, dropLaunchAck = false, dropTerminalAck = false;
  Future<void> Function(DirectSshCommand, bytes.Session)? beforeReply;
  Map<String, String> Function(DirectSshCommand, Map<String, String>)?
  alterReply;
  String? unit;
  void _selectAttempt(String script) {
    final admission = DirectHostRecord.parse(
      utf8.encode(_binding(script, 'expected_admission')),
      expectedKind: 'admission',
    );
    final next = admission.fields['attemptId']!;
    if (next == _selectedAttempt) return;
    final owner = records['owner'];
    if (_selectedAttempt case final previous?) {
      _attemptRecords[previous] = {...records}..remove('owner');
      _attemptInputs[previous] = {...inputs};
      _attemptUnits[previous] = unit;
    }
    records
      ..clear()
      ..addAll(_attemptRecords[next] ?? {});
    if (owner != null) records['owner'] = owner;
    inputs
      ..clear()
      ..addAll(_attemptInputs[next] ?? {});
    unit = _attemptUnits[next];
    _selectedAttempt = next;
  }

  String _binding(String script, String name) {
    final match = RegExp(
      '^' + name + r"='([A-Za-z0-9+/=]*)'$",
      multiLine: true,
    ).firstMatch(script);
    if (match == null) throw StateError('UNDECLARED_RAM_BINDING_' + name);
    return utf8.decode(base64.decode(match[1]!));
  }

  Map<String, String> _attempt(String disposition) => {
    'presence': 'present',
    'disposition': disposition,
    for (final name in ['owner', 'admission', 'plan', 'stop', 'terminal'])
      name: records[name] ?? '',
  };
  void attach(bytes.Session session, DirectSshCommand command) {
    requests.add(command);
    if (const {'inspect', 'packages', 'observation'}.contains(command.kind)) {
      reads.attach(session, command);
      return;
    }
    session.onInput = (data) async {
      final script = utf8.decode(data);
      expect(script, command.script);
      _selectAttempt(script);
      final Map<String, String> rows;
      switch (command.kind) {
        case 'reserve':
          records['owner'] = _binding(script, 'expected_owner');
          records['admission'] = _binding(script, 'expected_admission');
          records['plan'] = _binding(script, 'expected_pending');
          rows = _attempt('reserved');
        case 'status':
          rows = _attempt('snapshot');
        case 'stop':
          records['stop'] = _binding(script, 'expected_stop');
          rows = _attempt('stopped');
        case 'launch':
          launches++;
          if (records['intent'] != null) {
            rows = {'disposition': 'existing'};
            break;
          }
          final worker = _binding(script, 'worker');
          inputs['baseline'] = _binding(script, 'baseline_data');
          inputs['workerDigest'] = bytesHash(worker);
          records['intent'] = _binding(script, 'expected_intent');
          final intent = DirectHostRecord.parse(
            utf8.encode(records['intent']!),
            expectedKind: 'step',
          );
          if (!stopBeforeStart) {
            records['start'] = _binding(worker, 'expected_start');
            reads.files['system.motd'] = _binding(worker, 'desired_bytes');
            effects++;
            if (failPostcheck)
              reads.files['system.motd'] = 'RAM drift after effect\n';
          }
          inputs['checks'] = stopBeforeStart
              ? '[]'
              : _binding(
                  worker,
                  failPostcheck ? 'failed_checks' : 'passed_checks',
                );
          records['result'] = ascii.decode(
            DirectHostRecord.create('step', {
              ...intent.fields,
              'state': stopBeforeStart
                  ? 'stopped'
                  : failPostcheck
                  ? 'failed'
                  : 'succeeded',
              'exitCode': failPostcheck && !stopBeforeStart ? '1' : '0',
              'checkDigest': bytesHash(inputs['checks']!),
            }).encode(),
          );
          unit = RegExp(
            r"^unit='([^']+)'$",
            multiLine: true,
          ).firstMatch(script)![1]!;
          rows = {'disposition': 'launched'};
        case 'step-status':
          rows = {
            for (final name in ['intent', 'start', 'result'])
              name: records[name] ?? '',
            for (final name in ['baseline', 'workerDigest', 'checks'])
              name: inputs[name] ?? '',
            'bootHash': reads.identity.bootIdHash,
            'cgroup': 'absent',
            'unit': 'Id=' + unit! + '\nLoadState=loaded\nActiveState=active\nSubState=exited\nMainPID=0\nControlPID=0\nControlGroup=\nTransient=yes\nFragmentPath=\nType=oneshot\nRemainAfterExit=yes',
          };
          if (script.contains(
            'text unit ""\ntext cgroup ""\ntext bootHash ""',
          )) {
            rows['unit'] = '';
            rows['cgroup'] = '';
            rows['bootHash'] = '';
          }
        case 'terminal':
          if (script.contains('no_step_inputs()')) {
            expect(records['intent'], isNull);
            expect(records['start'], isNull);
            expect(records['result'], isNull);
            expect(unit, isNull);
            expect(records['stop'], _binding(script, 'expected_stop'));
          } else {
            expect(records['result'], _binding(script, 'expected_result'));
          }
          final terminal = _binding(script, 'expected_terminal');
          final terminalPlan = _binding(script, 'expected_terminal_plan');
          if (records['terminal'] == terminal &&
              records['plan'] == terminalPlan &&
              records['owner'] != _binding(script, 'expected_owner')) {
            // Fully released history is not permission to release owner B.
            rows = _attempt('existing');
            break;
          }
          expect(records['owner'], _binding(script, 'expected_owner'));
          records['terminal'] = terminal;
          records['plan'] = terminalPlan;
          records.remove('owner');
          rows = _attempt('snapshot');
        default:
          throw StateError('UNDECLARED_RAM_COMMAND_' + command.kind);
      }
      await beforeReply?.call(command, session);
      if (command.kind == 'reserve' && dropReserveAck ||
          command.kind == 'launch' && dropLaunchAck ||
          command.kind == 'terminal' && dropTerminalAck) {
        dropReserveAck = false;
        dropLaunchAck = false;
        dropTerminalAck = false;
        if (session.autoClose) {
          session.finish().ignore();
        } else {
          // Logical SSH failure with the native channel still physically owned.
          session.output.addError(StateError('RAM_LOST_ACK'));
          session.close();
        }
        return;
      }
      session.output.add(
        Uint8List.fromList(
          directOutput(alterReply?.call(command, rows) ?? rows).bytes,
        ),
      );
      if (session.autoClose) session.finish().ignore();
    };
  }
}
