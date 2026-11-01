part of 'direct_ssh.dart';

/// Immutable compiler input for one retained dispatch. It does not issue a
/// permit, obtain a native gate, prove current facts or permit a second launch.
final class DirectSshStep {
  DirectSshStep._(
    this.attempt,
    this.dispatch,
    this._baseline,
    this._effectJson,
    this.checkId,
    this.intent,
    this.packageDigest,
  );
  static Future<DirectSshStep> capture(
    AutomationJobRecord job,
    AutomationPlanRecord plan,
    ManagedResourceObservationRecord baseline,
  ) => _capture(job, plan, baseline);
  static Future<DirectSshStep> reference(
    AutomationJobRecord job,
    AutomationPlanRecord plan,
  ) => _capture(job, plan, null);
  static Future<DirectSshStep> _capture(
    AutomationJobRecord job,
    AutomationPlanRecord plan,
    ManagedResourceObservationRecord? baseline,
  ) async {
    final attempt = DirectSshAttempt.fromRecords(job, plan),
        dispatch = job.sshDispatch;
    if (dispatch == null) _fail('VALIDATION');
    final effects = (plan.toJson()['effects'] as List)
        .cast<Map<String, Object?>>();
    final matches = effects
        .where((row) => row['id'] == dispatch.stepId)
        .toList();
    if (matches.length != 1 ||
        dispatch.stepDigest != directBindingDigest(matches.single) ||
        dispatch.targetBindingDigest != directTargetBinding(plan) ||
        dispatch.bootIdHash != attempt.identity['bootIdHash'])
      _fail('VALIDATION');
    final effect = matches.single;
    // Database workers require the separate durable qualification/recipe path.
    if (effects.length != 1 ||
        effect['kind'] != 'config_file' ||
        effect['resourceId'] != 'system.motd') {
      _fail('QUALIFICATION_REQUIRED');
    }
    if (baseline != null &&
        (baseline.status != 'known' ||
            baseline.workspaceId != plan.workspaceId ||
            baseline.serverId != plan.serverId ||
            baseline.hostId != plan.hostId ||
            baseline.targetRevision != plan.serverRevision ||
            baseline.connectionRevision != plan.connectionRevision ||
            baseline.accessRevision != plan.accessRevision ||
            baseline.trustRevision != plan.trustRevision ||
            baseline.resourceRegistryDigest != plan.registryDigest ||
            baseline.resourceId != effect['resourceId'] ||
            await baseline.fingerprint() !=
                plan.baseObservations[baseline.resourceId]))
      _fail('PLAN_STALE');
    final checks = (plan.toJson()['checks'] as List)
        .cast<Map<String, Object?>>();
    if (checks.length != 1 ||
        checks.single['effectId'] != dispatch.stepId ||
        checks.single['kind'] != 'file_digest' ||
        checks.single['digest'] != effect['renderedDigest'])
      _fail('VALIDATION');
    final fields = <String, String>{
      'attemptId': attempt.attemptId,
      'planDigest': attempt.planDigest,
      'stepId': dispatch.stepId,
      'stepDigest': dispatch.stepDigest,
      'token': dispatch.token,
      'bootIdHash': dispatch.bootIdHash,
      'issuedUptimeMs': dispatch.issuedUptimeMs.toString(),
      'expiresUptimeMs': dispatch.expiresUptimeMs.toString(),
      'authorityBindingDigest': dispatch.authorityBindingDigest,
      'targetBindingDigest': dispatch.targetBindingDigest,
      'state': 'reserved',
      'exitCode': 'unknown',
      'checkDigest': 'unknown',
    };
    return DirectSshStep._(
      attempt,
      dispatch,
      baseline,
      jsonEncode(effect),
      checks.single['id'] as String,
      DirectHostRecord.create('step', fields),
      plan.preflight!.toJson()['packageSnapshotDigest'] as String,
    );
  }

  final DirectSshAttempt attempt;
  final DirectSshDispatch dispatch;
  final ManagedResourceObservationRecord? _baseline;
  ManagedResourceObservationRecord get baseline =>
      _baseline ?? _fail('VALIDATION');
  final String _effectJson, checkId;
  final DirectHostRecord intent;
  final String packageDigest;
  String get resourceId => 'system.motd';
  String get unit =>
      'serverdeck-ssh-' +
      attempt.attemptId.replaceAll('-', '') +
      '-' +
      dispatch.stepId +
      '.service';
  String get directory =>
      '/var/lib/serverdeck/ssh-v1/attempts/' +
      attempt.attemptId +
      '/steps/' +
      dispatch.stepId;
  Map<String, Object?> get _effect =>
      jsonDecode(_effectJson) as Map<String, Object?>;
  String get desiredDigest => _effect['renderedDigest'] as String;
  String get baselineJson => jsonEncode(baseline.toJson());
  String get baselineDigest => _workerHash(utf8.encode(baselineJson));
  String checksJson(bool passed) => jsonEncode([
    {
      'checkId': checkId,
      'result': passed ? 'passed' : 'failed',
      'safeCode': passed ? null : 'CHECK_FAILED',
      'stepId': dispatch.stepId,
    },
  ]);
  String checksDigest(bool passed) =>
      directBindingDigest(jsonDecode(checksJson(passed)));
  late final String workerBase64 = base64.encode(
    utf8.encode(_workerScript(this)),
  );
  late final String workerDigest = _workerHash(base64.decode(workerBase64));
  @override
  String toString() => 'DirectSshStep';
}

String _workerHash(List<int> bytes) => const DartSha256()
    .hashSync(bytes)
    .bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();

List<String> _workerTools(String kind) => [
  '/usr/bin/base64',
  '/usr/bin/id',
  '/usr/bin/stat',
  '/usr/bin/flock',
  '/usr/bin/cmp',
  '/usr/bin/cat',
  '/usr/bin/sha256sum',
  '/usr/bin/systemctl',
  '/usr/bin/head',
  if (kind != 'step-status') ...[
    '/usr/bin/dpkg-query',
    '/usr/bin/sort',
    '/usr/bin/systemd-run',
    '/usr/bin/mkdir',
    '/usr/bin/chgrp',
    '/usr/bin/mv',
    '/usr/bin/chmod',
    '/usr/bin/sync',
    '/usr/bin/find',
    '/usr/bin/timeout',
    '/usr/bin/awk',
  ],
];

String _stepBindings(DirectSshStep step, {bool worker = false}) {
  final attempt = step.attempt;
  return 'root=/var/lib/serverdeck/ssh-v1\n' +
      r'attempt_dir=$root/attempts/' +
      attempt.attemptId +
      '\n' +
      'step_dir=' +
      step.directory +
      '\n' +
      r'plan_file=$root/plans/' +
      attempt.planDigest +
      '\n' +
      r'stop_file=$root/stops/' +
      attempt.planDigest +
      '\n' +
      "unit='" +
      step.unit +
      "'\n" +
      "expected_owner='" +
      _record64('owner', attempt.identity) +
      "'\n" +
      "expected_admission='" +
      _record64('admission', attempt.identity) +
      "'\n" +
      "expected_pending='" +
      _record64('plan', {
        'planDigest': attempt.planDigest,
        'attemptId': attempt.attemptId,
        'terminal': 'pending',
      }) +
      "'\n" +
      "expected_stop='" +
      _record64('stop', {
        'attemptId': attempt.attemptId,
        'planDigest': attempt.planDigest,
      }) +
      "'\n" +
      "expected_intent='" +
      base64.encode(step.intent.encode()) +
      "'\n" +
      (worker ? '' : "expected_worker_digest='" + step.workerDigest + "'\n");
}

const _stepReady = r'''
ancestors
check_layout
open_lock
safe_dir "$attempt_dir" private
matches "$expected_owner" "$root/owner" || fail HOST_BUSY
matches "$expected_admission" "$attempt_dir/admission" || fail UNKNOWN_OUTCOME
matches "$expected_pending" "$plan_file" || fail UNKNOWN_OUTCOME
''';

const _inputReadFunctions = r'''
safe_input() {
  [ ! -L "$1" ] && [ -f "$1" ] || fail UNKNOWN_OUTCOME
  [ "$(/usr/bin/stat -c %u:%g:%a:%h -- "$1")" = 0:0:600:1 ] || fail UNKNOWN_OUTCOME
  size=$(/usr/bin/stat -c %s -- "$1") || fail UNKNOWN_OUTCOME
  case "$size" in ''|*[!0-9]*|???????*) fail RESOURCE_LIMIT;; esac
  [ "$size" -le 262144 ] || fail RESOURCE_LIMIT
}
input_matches() {
  safe_input "$2"
  digest=$(/usr/bin/sha256sum -- "$2") || fail UNKNOWN_OUTCOME
  [ "$digest" = "$1  $2" ]
}
''';
const _inputWriteFunctions = r'''
exclusive_input() {
  [ ! -e "$2" ] && [ ! -L "$2" ] || fail UNKNOWN_OUTCOME
  [ ! -e "$root/.pending" ] && [ ! -L "$root/.pending" ] || fail UNKNOWN_OUTCOME
  ( set -C; printf '%s' "$1" | /usr/bin/base64 -d > "$root/.pending" ) || fail UNKNOWN_OUTCOME
  /usr/bin/chgrp -- 0 "$root/.pending" || fail UNKNOWN_OUTCOME
  safe_input "$root/.pending"
  /usr/bin/sync -f -- "$root/.pending" || fail UNKNOWN_OUTCOME
  inode=$(/usr/bin/stat -c %d:%i -- "$root/.pending") || fail UNKNOWN_OUTCOME
  /usr/bin/mv -T -n -- "$root/.pending" "$2" || fail UNKNOWN_OUTCOME
  [ ! -e "$root/.pending" ] && [ ! -L "$root/.pending" ] || fail UNKNOWN_OUTCOME
  safe_input "$2"
  [ "$(/usr/bin/stat -c %d:%i -- "$2")" = "$inode" ] || fail UNKNOWN_OUTCOME
  /usr/bin/sync -f -- "$2" || fail UNKNOWN_OUTCOME
  /usr/bin/sync -f -- "$step_dir" || fail UNKNOWN_OUTCOME
}
''';
const _inputFunctions = _inputReadFunctions + _inputWriteFunctions;

String _launchStep(DirectSshStep step) =>
    _stepBindings(step) +
    _hostReadFunctions +
    _hostWriteFunctions +
    _inputFunctions +
    _stepReady +
    "worker='" +
    step.workerBase64 +
    "'\n" +
    "baseline_data='" +
    base64.encode(utf8.encode(step.baselineJson)) +
    "'\n" +
    "expected_baseline_digest='" +
    step.baselineDigest +
    "'\n" +
    r'''
if [ -e "$stop_file" ] || [ -L "$stop_file" ]; then
  matches "$expected_stop" "$stop_file" || fail UNKNOWN_OUTCOME
  text disposition stopped
  exit 0
fi
if [ -e "$step_dir" ] || [ -L "$step_dir" ]; then
  safe_dir "$attempt_dir/steps" private
  safe_dir "$step_dir" private
  matches "$expected_intent" "$step_dir/intent" || fail UNKNOWN_OUTCOME
  input_matches "$expected_worker_digest" "$step_dir/worker.sh" || fail UNKNOWN_OUTCOME
  digest_data=$(printf '%s' "$expected_worker_digest" | /usr/bin/base64 -w0) || fail UNKNOWN_OUTCOME
  matches "$digest_data" "$step_dir/worker.sha256" || fail UNKNOWN_OUTCOME
  input_matches "$expected_baseline_digest" "$step_dir/baseline.json" || fail UNKNOWN_OUTCOME
  # An existing intent is never a permission to resend the systemd launch.
  text disposition existing
  exit 0
fi
capacity 524288
ensure_dir "$attempt_dir/steps" "$attempt_dir" private
ensure_dir "$step_dir" "$attempt_dir/steps" private
exclusive_record "$expected_intent" "$step_dir/intent" "$step_dir"
exclusive_input "$baseline_data" "$step_dir/baseline.json"
exclusive_input "$worker" "$step_dir/worker.sh"
digest_data=$(printf '%s' "$expected_worker_digest" | /usr/bin/base64 -w0) || fail UNKNOWN_OUTCOME
exclusive_record "$digest_data" "$step_dir/worker.sha256" "$step_dir"
input_matches "$expected_worker_digest" "$step_dir/worker.sh" || fail UNKNOWN_OUTCOME
# Let the worker acquire the permanent inode. A stop may win this gap; the
# worker must check its fence under the lock before its committed start.
/usr/bin/flock -u 9 || fail UNKNOWN_OUTCOME
exec 9<&-
/usr/bin/systemd-run --no-block --unit="$unit" --property=Type=oneshot --property=RemainAfterExit=yes \
  --property=Restart=no --property=User=root --property=Group=root --property=UMask=0077 \
  --property=WorkingDirectory=/ --property=TimeoutStartSec=infinity --property=TimeoutStopSec=infinity \
  --property=StandardInput=null --property=StandardOutput=null --property=StandardError=null \
  /bin/sh "$step_dir/worker.sh" >/dev/null 2>&1 || fail UNKNOWN_OUTCOME
text disposition launched
''';

String _workerScript(DirectSshStep step) {
  final baseline = step.baseline.toJson()['value'] as Map<String, Object?>;
  final fields = step.intent.fields;
  final prefix = base64.encode(
    ascii.encode(
      'SDSSH1\nstep\n' +
          fields.entries.take(10).map((entry) => entry.value).join('\n') +
          '\n',
    ),
  );
  final start = _record64('step', {...fields, 'state': 'started'});
  final body = renderedConfiguration(
    'system.motd',
    step._effect['values'] as Map<String, Object?>,
  );
  return DirectSshCommand._prefix +
      DirectSshCommand._toolChecks(
        _workerTools('launch')
            .where(
              (path) =>
                  path != '/usr/bin/systemd-run' &&
                  path != '/usr/bin/systemctl' &&
                  path != '/usr/bin/head' &&
                  path != '/usr/bin/find',
            )
            .toList(),
      ) +
      _stepBindings(step, worker: true) +
      _hostReadFunctions +
      _hostWriteFunctions +
      _inputFunctions +
      _stepReady +
      "expected_start='" +
      start +
      "'\n" +
      "expected_baseline_digest='" +
      step.baselineDigest +
      "'\n" +
      "result_prefix='" +
      prefix +
      "'\n" +
      "expected_boot='" +
      step.dispatch.bootIdHash +
      "'\n" +
      'issued_uptime=' +
      step.dispatch.issuedUptimeMs.toString() +
      '\n' +
      'expires_uptime=' +
      step.dispatch.expiresUptimeMs.toString() +
      '\n' +
      'baseline_exists=' +
      (baseline['exists'] == true ? 'true' : 'false') +
      '\n' +
      "baseline_attributes='" +
      (baseline['baselineDigest'] as String) +
      "'\n" +
      "baseline_file='" +
      (baseline['fileDigest'] as String? ?? 'absent') +
      "'\n" +
      "desired_digest='" +
      step.desiredDigest +
      "'\n" +
      "desired_bytes='" +
      base64.encode(utf8.encode(body)) +
      "'\n" +
      "passed_checks='" +
      base64.encode(utf8.encode(step.checksJson(true))) +
      "'\n" +
      "failed_checks='" +
      base64.encode(utf8.encode(step.checksJson(false))) +
      "'\n" +
      "passed_digest='" +
      step.checksDigest(true) +
      "'\n" +
      "failed_digest='" +
      step.checksDigest(false) +
      "'\n" +
      "empty_digest='" +
      directBindingDigest(<Object?>[]) +
      "'\n" +
      "expected_packages='" +
      step.packageDigest +
      "'\n" +
      _packageGuard +
      r'''
matches "$expected_intent" "$step_dir/intent" || fail UNKNOWN_OUTCOME
safe_file "$step_dir/worker.sha256"
[ "$(/usr/bin/stat -c %s -- "$step_dir/worker.sha256")" = 64 ] || fail UNKNOWN_OUTCOME
expected_worker_digest=$(/usr/bin/cat "$step_dir/worker.sha256") || fail UNKNOWN_OUTCOME
[ "${#expected_worker_digest}" = 64 ] || fail UNKNOWN_OUTCOME
case "$expected_worker_digest" in *[!a-f0-9]*) fail UNKNOWN_OUTCOME;; esac
input_matches "$expected_worker_digest" "$step_dir/worker.sh" || fail UNKNOWN_OUTCOME
input_matches "$expected_baseline_digest" "$step_dir/baseline.json" || fail UNKNOWN_OUTCOME
[ ! -e "$step_dir/start" ] && [ ! -L "$step_dir/start" ] || fail UNKNOWN_OUTCOME
[ ! -e "$step_dir/result" ] && [ ! -L "$step_dir/result" ] || fail UNKNOWN_OUTCOME
record_result() {
  result_state=$1 result_code=$2 result_digest=$3 result_checks=$4
  exclusive_input "$result_checks" "$step_dir/checks.json"
  input_matches "$result_digest" "$step_dir/checks.json" || fail UNKNOWN_OUTCOME
  record=$( ( printf '%s' "$result_prefix" | /usr/bin/base64 -d
    printf '%s\n%s\n%s\n' "$result_state" "$result_code" "$result_digest" ) | /usr/bin/base64 -w0 ) || fail UNKNOWN_OUTCOME
  exclusive_record "$record" "$step_dir/result" "$step_dir"
}
no_start() { record_result stopped "$1" "$empty_digest" W10=; exit 0; }
if [ -e "$stop_file" ] || [ -L "$stop_file" ]; then
  matches "$expected_stop" "$stop_file" || fail UNKNOWN_OUTCOME
  no_start 0
fi
check_permit() {
boot=$(/usr/bin/cat /proc/sys/kernel/random/boot_id) || fail UNKNOWN_OUTCOME
boot_digest=$(printf '%s' "$boot" | /usr/bin/sha256sum) || fail UNKNOWN_OUTCOME
[ "$boot_digest" = "$expected_boot  -" ] || no_start 0
uptime_parts=$(/usr/bin/awk '
  NR==1 && NF==2 { n=split($1,a,".");
    if(n==2 && a[1] ~ /^[0-9]+$/ && length(a[1])<=16 &&
       (a[1]=="0" || substr(a[1],1,1)!="0") && a[2] ~ /^[0-9]+$/ && length(a[2])<=9) {
      seconds=a[1]; millis=substr(a[2] "000",1,3); valid=1 }
  }
  END { if(NR!=1 || !valid) exit 1; printf "%s %s",seconds,millis }
' /proc/uptime) || fail UNKNOWN_OUTCOME
set -- $uptime_parts
[ "$1" -le 9223372036854775 ] || no_start 0
milliseconds=$((1$2 - 1000))
[ "$1" -lt 9223372036854775 ] || [ "$milliseconds" -le 807 ] || no_start 0
current_uptime=$(($1 * 1000 + milliseconds))
[ "$current_uptime" -ge "$issued_uptime" ] && [ "$current_uptime" -le "$expires_uptime" ] || no_start 0
}
check_permit
motd_baseline() {
  safe_dir /etc public
  [ ! -L /etc/motd ] || return 1
  if [ -e /etc/motd ]; then
    [ "$baseline_exists" = true ] && [ -f /etc/motd ] || return 1
    attributes=$(/usr/bin/stat -c %u:%g:%a:%h:%s:%d:%i:%y:%z -- /etc/motd) || return 1
    case "$attributes" in 0:0:644:1:*) ;; *) return 1;; esac
    value=$(/usr/bin/timeout 5 /usr/bin/sha256sum -- /etc/motd) || return 1
    [ "$value" = "$baseline_file  /etc/motd" ] || return 1
  else
    [ "$baseline_exists" = false ] || return 1
    attributes=absent
  fi
  value=$(printf '{"attributes":"%s","path":"/etc/motd"}' "$attributes" | /usr/bin/sha256sum) || return 1
  [ "$value" = "$baseline_attributes  -" ]
}
motd_baseline || no_start 42
package_baseline || no_start 42
check_permit
exclusive_record "$expected_start" "$step_dir/start" "$step_dir"
apply_effect() {
  temporary=/etc/.serverdeck-''' +
      step.attempt.attemptId +
      '-' +
      step.dispatch.stepId +
      r'''.tmp
  [ ! -e "$temporary" ] && [ ! -L "$temporary" ] || return 1
  ( set -C; printf '%s' "$desired_bytes" | /usr/bin/base64 -d > "$temporary" ) || return $?
  /usr/bin/chgrp -- 0 "$temporary" || return $?
  safe_input "$temporary"
  /usr/bin/chmod 644 -- "$temporary" || return $?
  [ ! -L "$temporary" ] && [ "$(/usr/bin/stat -c %u:%g:%a:%h -- "$temporary")" = 0:0:644:1 ] || return 1
  value=$(/usr/bin/sha256sum -- "$temporary") || return $?
  [ "$value" = "$desired_digest  $temporary" ] || return 1
  /usr/bin/sync -f -- "$temporary" || return $?
  motd_baseline || return 42
  /usr/bin/mv -T -- "$temporary" /etc/motd || return $?
  /usr/bin/sync -f -- /etc/motd || return $?
  /usr/bin/sync -f -- /etc || return $?
}
code=0
apply_effect || code=$?
value=$(/usr/bin/sha256sum -- /etc/motd) || fail UNKNOWN_OUTCOME
if [ ! -L /etc/motd ] && [ -f /etc/motd ] &&
   [ "$(/usr/bin/stat -c %u:%g:%a:%h -- /etc/motd)" = 0:0:644:1 ] &&
   [ "$value" = "$desired_digest  /etc/motd" ]; then
  checks=$passed_checks digest=$passed_digest
else
  checks=$failed_checks digest=$failed_digest
  if [ "$code" = 0 ]; then code=1; fi
fi
if [ "$code" = 0 ]; then state=succeeded; else state=failed; fi
package_baseline || fail UNKNOWN_OUTCOME
record_result "$state" "$code" "$digest" "$checks"
''';
}

const _metadataReadTools = [
  '/usr/bin/base64',
  '/usr/bin/id',
  '/usr/bin/stat',
  '/usr/bin/flock',
  '/usr/bin/cmp',
  '/usr/bin/cat',
  '/usr/bin/sha256sum',
];

String _stepStatus(DirectSshStep step, {bool historyOnly = false}) =>
    _stepBindings(step, worker: true) +
    _hostReadFunctions +
    _inputReadFunctions +
    r'''
ancestors
check_layout
open_lock
safe_dir "$attempt_dir" private
matches "$expected_admission" "$attempt_dir/admission" || fail UNKNOWN_OUTCOME
if [ -e "$attempt_dir/steps" ] || [ -L "$attempt_dir/steps" ]; then safe_dir "$attempt_dir/steps" private; fi
if [ -e "$step_dir" ] || [ -L "$step_dir" ]; then safe_dir "$step_dir" private; fi
for name in intent start result; do emit_record "$name" "$step_dir/$name"; done
if [ -e "$step_dir/baseline.json" ] || [ -L "$step_dir/baseline.json" ]; then
  safe_input "$step_dir/baseline.json"
  emit baseline /usr/bin/cat "$step_dir/baseline.json"
else text baseline ""; fi
if [ -e "$step_dir/checks.json" ] || [ -L "$step_dir/checks.json" ]; then
  safe_file "$step_dir/checks.json"
  emit checks /usr/bin/cat "$step_dir/checks.json"
else text checks ""; fi
if [ -e "$step_dir/worker.sh" ] || [ -L "$step_dir/worker.sh" ]; then
  safe_input "$step_dir/worker.sh"
  digest=$(/usr/bin/sha256sum -- "$step_dir/worker.sh") || fail UNKNOWN_OUTCOME
  digest=${digest%% *}
  digest_data=$(printf '%s' "$digest" | /usr/bin/base64 -w0) || fail UNKNOWN_OUTCOME
  matches "$digest_data" "$step_dir/worker.sha256" || fail UNKNOWN_OUTCOME
  text workerDigest "$digest"
else text workerDigest ""; fi
''' +
    (historyOnly
        ? 'text unit ""\ntext cgroup ""\ntext bootHash ""\n'
        : _unitProof);

const _packageGuard = r'''
package_baseline() {
  pkg_data=$(/usr/bin/timeout 5 /usr/bin/dpkg-query -W '-f=${binary:Package}\t${Architecture}\t${Version}\t${db:Status-Status}\n') || return 1
  [ "${#pkg_data}" -le 4194304 ] || return 1
  pkg_sorted=$(printf '%s\n' "$pkg_data" | /usr/bin/sort) || return 1
  pkg_canonical=$(printf '%s\n' "$pkg_sorted" | /usr/bin/awk -F '\t' '
    BEGIN { printf "[" }
    { if(NF!=4 || ++n>16384) { bad=1; exit 1 }
      k=split($1,p,":")
      if(k>2 || p[1] !~ /^[a-z0-9][a-z0-9+.-]*$/ || length(p[1])>128 ||
         (k==2 && (p[2]!=$2 || length(p[2])>32)) ||
         !($4=="not-installed" || $4=="installed" || $4=="config-files") ||
         !($4=="not-installed" && $2=="" || $2 ~ /^[a-z0-9][a-z0-9-]*$/ && length($2)<=32) ||
         !($4=="not-installed" && $3=="" || $3 ~ /^[0-9A-Za-z.+:~-]+$/ && length($3)<=256) ||
         seen[p[1] SUBSEP $2]++) { bad=1; exit 1 }
      if(n>1) printf ","
      printf "[\"%s\",\"%s\",\"%s\",\"%s\"]",$1,$2,$3,$4
    }
    END { if(bad || n<1) exit 1; printf "]" }
  ') || return 1
  pkg_hash=$(printf '%s' "$pkg_canonical" | /usr/bin/sha256sum) || return 1
  [ "$pkg_hash" = "$expected_packages  -" ]
}
''';

const _unitProof = r'''
properties=Id,LoadState,ActiveState,SubState,MainPID,ControlPID,ControlGroup,Transient,FragmentPath,Type,RemainAfterExit
before=$(/usr/bin/systemctl show "$unit" --no-pager --property="$properties") || fail UNKNOWN_OUTCOME
safe_dir /sys public
safe_dir /sys/fs public
safe_dir /sys/fs/cgroup public
safe_dir /sys/fs/cgroup/system.slice public
cgroup_path=/sys/fs/cgroup/system.slice/$unit
if [ -e "$cgroup_path" ] || [ -L "$cgroup_path" ]; then
  safe_dir "$cgroup_path" public
  [ ! -L "$cgroup_path/cgroup.events" ] && [ -f "$cgroup_path/cgroup.events" ] || fail UNKNOWN_OUTCOME
  [ "$(/usr/bin/stat -c %u:%g -- "$cgroup_path/cgroup.events")" = 0:0 ] || fail UNKNOWN_OUTCOME
  [ "$(/usr/bin/stat -c %h -- "$cgroup_path/cgroup.events")" = 1 ] || fail UNKNOWN_OUTCOME
  mode=$(/usr/bin/stat -c %a -- "$cgroup_path/cgroup.events") || fail UNKNOWN_OUTCOME
  case "$mode" in [0-7]|[0-7][0-7]|[0-7][0-7][0-7]|[0-7][0-7][0-7][0-7]) ;; *) fail UNKNOWN_OUTCOME;; esac
  [ $((0$mode & 0022)) -eq 0 ] || fail UNKNOWN_OUTCOME
  cgroup_value=$(/usr/bin/head -c 257 -- "$cgroup_path/cgroup.events") || fail UNKNOWN_OUTCOME
  text cgroup "$cgroup_value"
else cgroup_value=absent; text cgroup absent; fi
after=$(/usr/bin/systemctl show "$unit" --no-pager --property="$properties") || fail UNKNOWN_OUTCOME
[ "$before" = "$after" ] || fail UNKNOWN_OUTCOME
text unit "$before"
boot=$(/usr/bin/cat /proc/sys/kernel/random/boot_id) || fail UNKNOWN_OUTCOME
digest=$(printf '%s' "$boot" | /usr/bin/sha256sum) || fail UNKNOWN_OUTCOME
text bootHash "${digest%% *}"
''';
