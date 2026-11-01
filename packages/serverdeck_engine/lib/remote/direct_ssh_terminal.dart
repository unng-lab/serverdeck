part of 'direct_ssh.dart';

/// Only local immutable cancellation evidence. Remote absence and custody are
/// re-proven under the permanent lock by the closed metadata command.
final class DirectUndispatchedCancellation {
  DirectUndispatchedCancellation._(
    this.attempt,
    this.terminal,
    this.units,
    this.historicalOnly,
  );
  factory DirectUndispatchedCancellation.capture(
    AutomationJobRecord job,
    AutomationPlanRecord plan,
    DirectAttemptSnapshot snapshot,
  ) {
    if (!job.cancelRequested || job.sshDispatch != null)
      _fail('UNKNOWN_OUTCOME');
    final attempt = DirectSshAttempt.fromRecords(job, plan);
    if (snapshot.admission == null ||
        snapshot.stop == null ||
        attempt.identity.entries.any(
          (entry) => snapshot.admission!.fields[entry.key] != entry.value,
        ) ||
        snapshot.stop!.fields['attemptId'] != attempt.attemptId ||
        snapshot.stop!.fields['planDigest'] != attempt.planDigest)
      _fail('UNKNOWN_OUTCOME');
    final terminal = DirectHostRecord.create('terminal', {
      ...attempt.identity,
      'state': 'cancelled',
      'checksDigest': directBindingDigest(<Object?>[]),
    });
    if (snapshot.terminal != null &&
        base64.encode(snapshot.terminal!.encode()) !=
            base64.encode(terminal.encode()))
      _fail('UNKNOWN_OUTCOME');
    final planState = snapshot.plan?.fields['terminal'];
    final historical =
        snapshot.terminal != null &&
        planState == 'cancelled' &&
        snapshot.owner == null;
    if (!historical &&
        (snapshot.owner == null ||
            !{'pending', 'cancelled'}.contains(planState) ||
            planState == 'cancelled' && snapshot.terminal == null))
      _fail('UNKNOWN_OUTCOME');
    final effects = (plan.toJson()['effects'] as List)
        .cast<Map<String, Object?>>();
    final units = <String>[];
    for (final effect in effects) {
      final id = effect['id'];
      if (id is! String ||
          !RegExp(r'^[a-zA-Z][a-zA-Z0-9_-]{0,63}$').hasMatch(id))
        _fail('VALIDATION');
      units.add(
        'serverdeck-ssh-' +
            attempt.attemptId.replaceAll('-', '') +
            '-' +
            id +
            '.service',
      );
    }
    if (units.isEmpty ||
        units.length > 128 ||
        units.toSet().length != units.length)
      _fail('VALIDATION');
    return DirectUndispatchedCancellation._(
      attempt,
      terminal,
      List.unmodifiable(units),
      historical,
    );
  }
  final DirectSshAttempt attempt;
  final DirectHostRecord terminal;
  final List<String> units;
  final bool historicalOnly;
  AutomationJobOutcome get outcome => AutomationJobOutcome.fromJson({
    'effects': 'none',
    'checks': <Object?>[],
    'safeCode': 'CANCELLED',
  });
}

String _cancelUndispatched(DirectUndispatchedCancellation proof) =>
    _attemptBindings(proof.attempt) +
    _hostReadFunctions +
    _hostWriteFunctions +
    "expected_terminal='" +
    base64.encode(proof.terminal.encode()) +
    "'\n" +
    "expected_terminal_plan='" +
    _record64('plan', {
      'attemptId': proof.attempt.attemptId,
      'planDigest': proof.attempt.planDigest,
      'terminal': 'cancelled',
    }) +
    "'\n" +
    'allow_incomplete=' +
    (proof.historicalOnly ? '0' : '1') +
    '\n' +
    "units='" +
    proof.units.join(' ') +
    "'\n" +
    r'''
ancestors
check_layout
open_lock
safe_dir "$attempt_dir" private
matches "$expected_admission" "$attempt_dir/admission" || fail UNKNOWN_OUTCOME
matches "$expected_stop" "$stop_file" || fail UNKNOWN_OUTCOME
no_step_inputs() {
  if [ -e "$attempt_dir/steps" ] || [ -L "$attempt_dir/steps" ]; then
    safe_dir "$attempt_dir/steps" private
    children=$(/usr/bin/timeout 5 /usr/bin/find "$attempt_dir/steps" -mindepth 1 -maxdepth 1 -printf x -quit) || fail UNKNOWN_OUTCOME
    [ -z "$children" ] || fail UNKNOWN_OUTCOME
  fi
}
no_step_inputs
has_terminal=0
if [ -e "$attempt_dir/terminal" ] || [ -L "$attempt_dir/terminal" ]; then
  matches "$expected_terminal" "$attempt_dir/terminal" || fail UNKNOWN_OUTCOME
  has_terminal=1
fi
if matches "$expected_terminal_plan" "$plan_file"; then
  [ "$has_terminal" = 1 ] || fail UNKNOWN_OUTCOME
  if [ ! -e "$root/owner" ] && [ ! -L "$root/owner" ]; then snapshot existing; exit 0; fi
  if ! matches "$expected_owner" "$root/owner"; then snapshot existing; exit 0; fi
else matches "$expected_pending" "$plan_file" || fail UNKNOWN_OUTCOME; fi
[ "$allow_incomplete" = 1 ] || fail UNKNOWN_OUTCOME
matches "$expected_owner" "$root/owner" || fail UNKNOWN_OUTCOME
boot=$(/usr/bin/cat /proc/sys/kernel/random/boot_id) || fail UNKNOWN_OUTCOME
digest=$(printf '%s' "$boot" | /usr/bin/sha256sum) || fail UNKNOWN_OUTCOME
[ "$digest" = "$expected_boot  -" ] || fail UNKNOWN_OUTCOME
for unit in $units; do
  value=$(/usr/bin/timeout 5 /usr/bin/systemctl show "$unit" --no-pager --all --property=LoadState,ActiveState,SubState,MainPID,ControlPID,ControlGroup,FragmentPath) || fail UNKNOWN_OUTCOME
  [ "${#value}" -le 8192 ] || fail RESOURCE_LIMIT
  printf '%s\n' "$value" | /usr/bin/awk -F= '
    { if(NF!=2 || seen[$1]++ || index("|LoadState|ActiveState|SubState|MainPID|ControlPID|ControlGroup|FragmentPath|","|" $1 "|")==0) exit 1; v[$1]=$2; n++ }
    END { if(n!=7 || v["LoadState"]!="not-found" || v["ActiveState"]!="inactive" || v["SubState"]!="dead" ||
      v["MainPID"]!="0" || v["ControlPID"]!="0" || v["ControlGroup"]!="" || v["FragmentPath"]!="") exit 1 }
  ' || fail UNKNOWN_OUTCOME
  for parent in /sys /sys/fs /sys/fs/cgroup /sys/fs/cgroup/system.slice; do safe_dir "$parent" public; done
  cgroup=/sys/fs/cgroup/system.slice/$unit
  [ ! -e "$cgroup" ] && [ ! -L "$cgroup" ] || fail UNKNOWN_OUTCOME
done
''' +
    _terminalRelease;

/// Captured evidence for metadata journaling only. Live native/session/object
/// authorization is separately required by the caller through first SSH write.
final class DirectFinalization {
  DirectFinalization._(
    this.receipt,
    this.terminal,
    this.historicalOnly,
    this.outcome,
  );
  factory DirectFinalization.capture(
    DirectAttemptSnapshot attempt,
    DirectStepSnapshot receipt,
    ManagedResourceObservationRecord? observation, {
    required DateTime at,
  }) {
    final step = receipt.step, identity = receipt.step.attempt.identity;
    if (!receipt.inputVerified ||
        !const {'succeeded', 'failed', 'stopped'}.contains(receipt.state) ||
        attempt.admission == null ||
        identity.entries.any(
          (entry) => attempt.admission!.fields[entry.key] != entry.value,
        ))
      _fail('UNKNOWN_OUTCOME');
    final result = receipt.records['result']!;
    final state = receipt.state == 'succeeded'
        ? 'succeeded'
        : receipt.state == 'stopped' && result.fields['exitCode'] == '0'
        ? 'cancelled'
        : 'failed';
    final terminal = DirectHostRecord.create('terminal', {
      ...identity,
      'state': state,
      'checksDigest': directBindingDigest(receipt.checks),
    });
    if (attempt.terminal != null &&
        base64.encode(attempt.terminal!.encode()) !=
            base64.encode(terminal.encode()))
      _fail('UNKNOWN_OUTCOME');
    final planState = attempt.plan?.fields['terminal'];
    final historical =
        attempt.terminal != null && planState == state && attempt.owner == null;
    if (!historical) {
      if (attempt.owner == null ||
          !{'pending', state}.contains(planState) ||
          planState == state && attempt.terminal == null ||
          !receipt.hasCompleteReceipt)
        _fail('UNKNOWN_OUTCOME');
      if (receipt.state != 'stopped') {
        if (observation == null ||
            !observation.isFreshAt(at) ||
            observation.resourceId != step.resourceId ||
            observation.hostId != identity['hostId'] ||
            observation.serverId != step.baseline.serverId ||
            observation.workspaceId != identity['workspaceId'] ||
            observation.resourceRegistryDigest !=
                step.baseline.resourceRegistryDigest)
          _fail('UNKNOWN_OUTCOME');
        final facts = observation.toJson()['value'] as Map<String, Object?>;
        final passed =
            facts['exists'] == true &&
            facts['fileDigest'] == step.desiredDigest;
        if (directBindingDigest(jsonDecode(step.checksJson(passed))) !=
            result.fields['checkDigest'])
          _fail('UNKNOWN_OUTCOME');
      }
    }
    return DirectFinalization._(
      receipt,
      terminal,
      historical,
      AutomationJobOutcome.fromJson({
        'effects': receipt.records['start'] == null ? 'none' : 'confirmed',
        'checks': receipt.checks,
        'safeCode': state == 'succeeded'
            ? null
            : state == 'cancelled'
            ? 'CANCELLED'
            : receipt.state == 'stopped'
            ? 'PLAN_STALE'
            : 'CHECK_FAILED',
      }),
    );
  }
  final DirectStepSnapshot receipt;
  final DirectHostRecord terminal;
  final bool historicalOnly;
  final AutomationJobOutcome outcome;
  @override
  String toString() => 'DirectFinalization';
}

String _finalizeAttempt(DirectFinalization proof) {
  final step = proof.receipt.step, records = proof.receipt.records;
  final terminalPlan = _record64('plan', {
    'attemptId': step.attempt.attemptId,
    'planDigest': step.attempt.planDigest,
    'terminal': proof.terminal.fields['state']!,
  });
  return _stepBindings(step) +
      _hostReadFunctions +
      _hostWriteFunctions +
      _inputReadFunctions +
      "expected_terminal='" +
      base64.encode(proof.terminal.encode()) +
      "'\n" +
      "expected_terminal_plan='" +
      terminalPlan +
      "'\n" +
      "expected_result='" +
      base64.encode(records['result']!.encode()) +
      "'\n" +
      "expected_start='" +
      (records['start'] == null
          ? ''
          : base64.encode(records['start']!.encode())) +
      "'\n" +
      "expected_checks='" +
      base64.encode(utf8.encode(jsonEncode(proof.receipt.checks))) +
      "'\n" +
      "expected_baseline_digest='" +
      step.baselineDigest +
      "'\n" +
      "expected_boot='" +
      step.dispatch.bootIdHash +
      "'\n" +
      "desired_digest='" +
      step.desiredDigest +
      "'\n" +
      'allow_incomplete=' +
      (proof.historicalOnly ? '0' : '1') +
      '\n' +
      'expected_passed=' +
      (proof.receipt.checks.isNotEmpty &&
              proof.receipt.checks.single['result'] == 'passed'
          ? '1'
          : '0') +
      '\n' +
      "expected_packages='" +
      step.packageDigest +
      "'\n" +
      _packageGuard +
      'collect_proof() {\n' +
      _unitProof +
      '\n}\n' +
      r'''
ancestors
check_layout
open_lock
safe_dir "$attempt_dir" private
safe_dir "$attempt_dir/steps" private
safe_dir "$step_dir" private
matches "$expected_admission" "$attempt_dir/admission" || fail UNKNOWN_OUTCOME
matches "$expected_intent" "$step_dir/intent" || fail UNKNOWN_OUTCOME
matches "$expected_result" "$step_dir/result" || fail UNKNOWN_OUTCOME
if [ -n "$expected_start" ]; then matches "$expected_start" "$step_dir/start" || fail UNKNOWN_OUTCOME
else [ ! -e "$step_dir/start" ] && [ ! -L "$step_dir/start" ] || fail UNKNOWN_OUTCOME; fi
matches "$expected_checks" "$step_dir/checks.json" || fail UNKNOWN_OUTCOME
input_matches "$expected_worker_digest" "$step_dir/worker.sh" || fail UNKNOWN_OUTCOME
input_matches "$expected_baseline_digest" "$step_dir/baseline.json" || fail UNKNOWN_OUTCOME
digest_data=$(printf '%s' "$expected_worker_digest" | /usr/bin/base64 -w0) || fail UNKNOWN_OUTCOME
matches "$digest_data" "$step_dir/worker.sha256" || fail UNKNOWN_OUTCOME
has_terminal=0
if [ -e "$attempt_dir/terminal" ] || [ -L "$attempt_dir/terminal" ]; then
  matches "$expected_terminal" "$attempt_dir/terminal" || fail UNKNOWN_OUTCOME
  has_terminal=1
fi
if matches "$expected_terminal_plan" "$plan_file"; then
  [ "$has_terminal" = 1 ] || fail UNKNOWN_OUTCOME
  if [ ! -e "$root/owner" ] && [ ! -L "$root/owner" ]; then snapshot existing; exit 0; fi
  if ! matches "$expected_owner" "$root/owner"; then snapshot existing; exit 0; fi
else matches "$expected_pending" "$plan_file" || fail UNKNOWN_OUTCOME; fi
[ "$allow_incomplete" = 1 ] || fail UNKNOWN_OUTCOME
matches "$expected_owner" "$root/owner" || fail UNKNOWN_OUTCOME
collect_proof >/dev/null
[ "${digest%% *}" = "$expected_boot" ] || fail UNKNOWN_OUTCOME
printf '%s\n' "$before" | /usr/bin/awk -F= -v unit="$unit" '
  { if(NF!=2 || seen[$1]++ || length($2)>1024 ||
       index("|Id|LoadState|ActiveState|SubState|MainPID|ControlPID|ControlGroup|Transient|FragmentPath|Type|RemainAfterExit|","|" $1 "|")==0) exit 1; v[$1]=$2; n++ }
  END { if(n!=11 || v["Id"]!=unit || v["LoadState"]!="loaded" || v["Transient"]!="yes" ||
    v["Type"]!="oneshot" || v["RemainAfterExit"]!="yes" || v["MainPID"]!="0" || v["ControlPID"]!="0" ||
    (v["ControlGroup"]!="" && v["ControlGroup"]!="/system.slice/" unit) ||
    (v["FragmentPath"]!="" && v["FragmentPath"]!="/run/systemd/transient/" unit) ||
    (v["ActiveState"] ":" v["SubState"] !~ /^(active:exited|inactive:dead|failed:failed)$/)) exit 1 }
' || fail UNKNOWN_OUTCOME
if [ "$cgroup_value" != absent ]; then
  [ "${#cgroup_value}" -le 256 ] || fail UNKNOWN_OUTCOME
  printf '%s\n' "$cgroup_value" | /usr/bin/awk '
    { if(NF!=2 || $1 !~ /^(populated|frozen)$/ || $2 !~ /^[01]$/ || seen[$1]++) exit 1; v[$1]=$2; n++ }
    END { if(n!=2 || v["populated"]!="0") exit 1 }
  ' || fail UNKNOWN_OUTCOME
fi
if [ -n "$expected_start" ]; then
  package_baseline || fail UNKNOWN_OUTCOME
  safe_dir /etc public
  [ ! -L /etc/motd ] || fail UNKNOWN_OUTCOME
  passed=0
  if [ -e /etc/motd ]; then
    [ -f /etc/motd ] && [ "$(/usr/bin/stat -c %u:%g:%a:%h -- /etc/motd)" = 0:0:644:1 ] || fail UNKNOWN_OUTCOME
    value=$(/usr/bin/timeout 5 /usr/bin/sha256sum -- /etc/motd) || fail UNKNOWN_OUTCOME
    if [ "$value" = "$desired_digest  /etc/motd" ]; then passed=1; fi
  fi
  [ "$passed" = "$expected_passed" ] || fail UNKNOWN_OUTCOME
fi
''' +
      _terminalRelease;
}

const _terminalRelease = r'''
capacity 2048
publish_terminal() {
  exclusive_record "$expected_terminal" "$attempt_dir/terminal" "$attempt_dir"
  if ! matches "$expected_terminal_plan" "$plan_file"; then
    matches "$expected_pending" "$plan_file" || fail UNKNOWN_OUTCOME
    old_inode=$(/usr/bin/stat -c %d:%i -- "$plan_file") || fail UNKNOWN_OUTCOME
    [ ! -e "$root/.pending" ] && [ ! -L "$root/.pending" ] || fail UNKNOWN_OUTCOME
    ( set -C; printf '%s' "$expected_terminal_plan" | /usr/bin/base64 -d > "$root/.pending" ) || fail UNKNOWN_OUTCOME
    /usr/bin/chgrp -- 0 "$root/.pending" || fail UNKNOWN_OUTCOME
    safe_file "$root/.pending"
    /usr/bin/sync -f -- "$root/.pending" || fail UNKNOWN_OUTCOME
    matches "$expected_pending" "$plan_file" || fail UNKNOWN_OUTCOME
    [ "$(/usr/bin/stat -c %d:%i -- "$plan_file")" = "$old_inode" ] || fail UNKNOWN_OUTCOME
    /usr/bin/mv -T -- "$root/.pending" "$plan_file" || fail UNKNOWN_OUTCOME
    matches "$expected_terminal_plan" "$plan_file" || fail UNKNOWN_OUTCOME
    /usr/bin/sync -f -- "$plan_file" || fail UNKNOWN_OUTCOME
    /usr/bin/sync -f -- "$root/plans" || fail UNKNOWN_OUTCOME
  fi
  matches "$expected_owner" "$root/owner" || fail UNKNOWN_OUTCOME
  /usr/bin/rm -- "$root/owner" || fail UNKNOWN_OUTCOME
  /usr/bin/sync -f -- "$root" || fail UNKNOWN_OUTCOME
}
publish_terminal
snapshot snapshot
''';
