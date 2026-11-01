part of 'direct_ssh.dart';

/// Correlated host data only. A complete receipt still needs independently
/// collected current postchecks and proven terminal metadata release. It never
/// supplies authority, a launch permit, or a reason to replay a missing effect.
final class DirectStepSnapshot {
  DirectStepSnapshot._(
    this.step,
    this.records,
    this._checksJson,
    this.childrenStopped,
    this.inputVerified,
  );
  static Future<DirectStepSnapshot> capture(
    AutomationJobRecord job,
    AutomationPlanRecord plan,
    DirectSshOutput output,
  ) async {
    try {
      return await _capture(job, plan, output);
    } on DirectSshFailure {
      rethrow;
    } catch (_) {
      _fail('UNKNOWN_OUTCOME');
    }
  }

  static Future<DirectStepSnapshot> _capture(
    AutomationJobRecord job,
    AutomationPlanRecord plan,
    DirectSshOutput output,
  ) async {
    if (output.bytes.length > 512 * 1024 || output.truncated)
      _fail('RESOURCE_LIMIT');
    final rows = output.textRows(const {
      'intent',
      'start',
      'result',
      'baseline',
      'checks',
      'workerDigest',
      'unit',
      'cgroup',
      'bootHash',
    });
    var step = await DirectSshStep.reference(job, plan);
    final records = <String, DirectHostRecord>{};
    for (final name in ['intent', 'start', 'result']) {
      final data = rows[name]!;
      if (data.isEmpty) continue;
      final record = DirectHostRecord.parse(
        utf8.encode(data),
        expectedKind: 'step',
      );
      if (step.intent.fields.entries
          .take(10)
          .any((entry) => record.fields[entry.key] != entry.value))
        _fail('UNKNOWN_OUTCOME');
      if (name == 'intent' && record.fields['state'] != 'reserved' ||
          name == 'start' && record.fields['state'] != 'started' ||
          name == 'result' &&
              !const {
                'succeeded',
                'failed',
                'stopped',
                'unknown',
              }.contains(record.fields['state']))
        _fail('UNKNOWN_OUTCOME');
      records[name] = record;
    }
    if (records['intent'] == null &&
        (records['start'] != null || records['result'] != null))
      _fail('UNKNOWN_OUTCOME');
    final result = records['result'];
    if (result != null &&
            const {'succeeded', 'failed'}.contains(result.fields['state']) &&
            records['start'] == null ||
        result?.fields['state'] == 'stopped' && records['start'] != null)
      _fail('UNKNOWN_OUTCOME');
    var inputVerified = false;
    final baseline = rows['baseline']!;
    if (baseline.isNotEmpty) {
      if (utf8.encode(baseline).length > 128 * 1024) _fail('RESOURCE_LIMIT');
      final raw = jsonDecode(baseline);
      if (raw is! Map<String, Object?>) _fail('UNKNOWN_OUTCOME');
      step = await DirectSshStep.capture(
        job,
        plan,
        ManagedResourceObservationRecord.fromTrustedJson(raw),
      );
      if (step.workerDigest != rows['workerDigest']) _fail('UNKNOWN_OUTCOME');
      inputVerified = true;
    } else if (result != null) {
      _fail('UNKNOWN_OUTCOME');
    }
    var checks = <Object?>[];
    final rawChecks = rows['checks']!;
    if (rawChecks.isNotEmpty) {
      if (utf8.encode(rawChecks).length > 4096) _fail('RESOURCE_LIMIT');
      final raw = jsonDecode(rawChecks);
      if (raw is! List || raw.length > 1) _fail('UNKNOWN_OUTCOME');
      final parsed = AutomationJobOutcome.fromJson({
        'effects': 'confirmed',
        'checks': raw,
        'safeCode': null,
      });
      for (final check in parsed.checks) {
        final doc = check.toJson();
        if (check.checkId != step.checkId ||
            check.stepId != step.dispatch.stepId ||
            !const {'passed', 'failed'}.contains(check.result) ||
            doc['safeCode'] !=
                (check.result == 'passed' ? null : 'CHECK_FAILED'))
          _fail('UNKNOWN_OUTCOME');
      }
      checks = raw.cast<Object?>();
    }
    if (result != null &&
        (rawChecks.isEmpty ||
            directBindingDigest(checks) != result.fields['checkDigest']))
      _fail('UNKNOWN_OUTCOME');
    if (result?.fields['state'] == 'succeeded' &&
            (checks.length != 1 ||
                (checks.single as Map)['result'] != 'passed') ||
        result?.fields['state'] == 'stopped' && checks.isNotEmpty)
      _fail('UNKNOWN_OUTCOME');
    if (result?.fields['state'] == 'failed' && checks.length != 1)
      _fail('UNKNOWN_OUTCOME');
    final boot = rows['bootHash']!;
    final unavailableProof =
        boot.isEmpty && rows['unit']!.isEmpty && rows['cgroup']!.isEmpty;
    if (!unavailableProof && !RegExp(r'^[a-f0-9]{64}$').hasMatch(boot))
      _fail('UNKNOWN_OUTCOME');
    final stopped =
        !unavailableProof &&
        _unitStopped(step, rows['unit']!, rows['cgroup']!) &&
        boot == step.dispatch.bootIdHash;
    return DirectStepSnapshot._(
      step,
      Map.unmodifiable(records),
      jsonEncode(checks),
      stopped,
      inputVerified,
    );
  }

  final DirectSshStep step;
  final Map<String, DirectHostRecord> records;
  final String _checksJson;
  final bool childrenStopped, inputVerified;
  String get state =>
      records['result']?.fields['state'] ??
      (records['start'] == null ? 'reserved' : 'started');
  bool get hasCompleteReceipt =>
      inputVerified &&
      records['intent'] != null &&
      childrenStopped &&
      const {'succeeded', 'failed', 'stopped'}.contains(state);
  List<Map<String, Object?>> get checks =>
      (jsonDecode(_checksJson) as List).cast<Map<String, Object?>>();
  @override
  String toString() => 'DirectStepSnapshot';
}

bool _unitStopped(DirectSshStep step, String unit, String cgroup) {
  if (unit.length > 16 * 1024 || cgroup.length > 256) _fail('RESOURCE_LIMIT');
  const fields = {
    'Id',
    'LoadState',
    'ActiveState',
    'SubState',
    'MainPID',
    'ControlPID',
    'ControlGroup',
    'Transient',
    'FragmentPath',
    'Type',
    'RemainAfterExit',
  };
  final values = <String, String>{};
  for (final row in unit.split('\n')) {
    final index = row.indexOf('=');
    if (index < 1) _fail('UNKNOWN_OUTCOME');
    final name = row.substring(0, index), value = row.substring(index + 1);
    if (!fields.contains(name) ||
        values.containsKey(name) ||
        value.length > 1024 ||
        value.codeUnits.any((char) => char < 32 || char > 126))
      _fail('UNKNOWN_OUTCOME');
    values[name] = value;
  }
  if (values.length != fields.length || values['Id'] != step.unit)
    _fail('UNKNOWN_OUTCOME');
  for (final key in ['MainPID', 'ControlPID']) {
    final value = values[key]!;
    if (!RegExp(r'^(?:0|[1-9][0-9]{0,9})$').hasMatch(value) ||
        int.parse(value) > 2147483647)
      _fail('UNKNOWN_OUTCOME');
  }
  var empty = cgroup == 'absent';
  if (!empty) {
    final events = <String, String>{};
    for (final row in cgroup.split('\n')) {
      final match = RegExp(r'^(populated|frozen) ([01])$').firstMatch(row);
      if (match == null || events.containsKey(match[1]))
        _fail('UNKNOWN_OUTCOME');
      events[match[1]!] = match[2]!;
    }
    if (events.length != 2) _fail('UNKNOWN_OUTCOME');
    empty = events['populated'] == '0';
  }
  return values['LoadState'] == 'loaded' &&
      values['Transient'] == 'yes' &&
      values['Type'] == 'oneshot' &&
      values['RemainAfterExit'] == 'yes' &&
      const {
        'active:exited',
        'inactive:dead',
        'failed:failed',
      }.contains(values['ActiveState']! + ':' + values['SubState']!) &&
      values['MainPID'] == '0' &&
      values['ControlPID'] == '0' &&
      {'', '/system.slice/' + step.unit}.contains(values['ControlGroup']) &&
      {
        '',
        '/run/systemd/transient/' + step.unit,
      }.contains(values['FragmentPath']) &&
      empty;
}
