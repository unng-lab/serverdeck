part of 'direct_ssh.dart';

/// Captured immutable job identity only. Constructing this value never proves
/// current authority, remote ownership or an absence of effects.
final class DirectSshAttempt {
  DirectSshAttempt._(this.identity);
  factory DirectSshAttempt.fromRecords(
    AutomationJobRecord job,
    AutomationPlanRecord plan,
  ) {
    try {
      if (plan.status != 'runnable' || plan.preflight?.isDirectSsh != true) {
        _fail('VALIDATION');
      }
      job.validatePlanIdentity(
        workspaceId: plan.workspaceId,
        planId: plan.id,
        digest: plan.toJson()['digest'] as String,
        profileKey: plan.key,
        originGrantId: plan.toJson()['originGrantId'] as String?,
      );
      final identity = DirectHostRecord.create('owner', {
        'workspaceId': job.workspaceId,
        'jobId': job.id,
        'attemptId': job.hostAttemptId,
        'planDigest': job.planDigest,
        'hostId': plan.hostId!,
        'bootIdHash': plan.preflight!.toJson()['bootIdHash'] as String,
      });
      return DirectSshAttempt._(identity.fields);
    } on DirectSshFailure {
      rethrow;
    } catch (_) {
      _fail('VALIDATION');
    }
  }
  final Map<String, String> identity;
  String get attemptId => identity['attemptId']!;
  String get jobId => identity['jobId']!;
  String get planDigest => identity['planDigest']!;
  @override
  String toString() => 'DirectSshAttempt';
}

/// Correlated bounded metadata, never proof of worker/cgroup termination,
/// actual checks or authorization to launch/release an owner.
final class DirectAttemptSnapshot {
  DirectAttemptSnapshot._(
    this.disposition,
    this.records,
    this.foreignOwnerPresent,
  );
  factory DirectAttemptSnapshot.fromOutput(
    DirectSshAttempt attempt,
    DirectSshOutput output,
  ) {
    if (output.bytes.length > 128 * 1024) _fail('RESOURCE_LIMIT');
    final rows = output.textRows(const {
      'presence',
      'disposition',
      'owner',
      'admission',
      'plan',
      'stop',
      'terminal',
    });
    final present = rows['presence'];
    final disposition = rows['disposition']!;
    if (!const {'absent', 'present'}.contains(present) ||
        !const {
          'absent',
          'snapshot',
          'reserved',
          'existing',
          'stopped',
        }.contains(disposition) ||
        (present == 'absent') != (disposition == 'absent'))
      _fail('UNKNOWN_OUTCOME');
    final records = <String, DirectHostRecord>{};
    var foreignOwnerPresent = false;
    for (final kind in ['owner', 'admission', 'plan', 'stop', 'terminal']) {
      final value = rows[kind]!;
      if (value.isEmpty) continue;
      if (present == 'absent') _fail('UNKNOWN_OUTCOME');
      final record = DirectHostRecord.parse(
        utf8.encode(value),
        expectedKind: kind,
      );
      final expected = const {'owner', 'admission', 'terminal'}.contains(kind)
          ? attempt.identity
          : {'attemptId': attempt.attemptId, 'planDigest': attempt.planDigest};
      if (expected.entries.any(
        (entry) => record.fields[entry.key] != entry.value,
      )) {
        if (kind == 'owner' &&
            record.fields['hostId'] == attempt.identity['hostId'] &&
            record.fields['attemptId'] != attempt.attemptId &&
            record.fields['planDigest'] != attempt.planDigest &&
            (record.fields['workspaceId'] != attempt.identity['workspaceId'] ||
                record.fields['jobId'] != attempt.jobId)) {
          // Current host occupancy is separate from the requested history.
          // Keep only its presence, never expose B's tuple as A's own owner.
          foreignOwnerPresent = true;
          continue;
        }
        _fail('UNKNOWN_OUTCOME');
      }
      records[kind] = record;
    }
    if (disposition == 'reserved' &&
            (records['owner'] == null ||
                records['admission'] == null ||
                records['plan']?.fields['terminal'] != 'pending' ||
                records['stop'] != null ||
                records['terminal'] != null) ||
        disposition == 'stopped' && records['stop'] == null ||
        disposition == 'existing' &&
            records['plan'] == null &&
            records['stop'] == null ||
        records['terminal'] != null &&
            !{
              'pending',
              records['terminal']!.fields['state'],
            }.contains(records['plan']?.fields['terminal'])) {
      _fail('UNKNOWN_OUTCOME');
    }
    return DirectAttemptSnapshot._(
      disposition,
      Map.unmodifiable(records),
      foreignOwnerPresent,
    );
  }
  final String disposition;
  final Map<String, DirectHostRecord> records;
  final bool foreignOwnerPresent;

  /// Matching owner only. Null is not evidence of a free host: another attempt
  /// can own it, as represented by [foreignOwnerPresent].
  DirectHostRecord? get owner => records['owner'];
  DirectHostRecord? get admission => records['admission'];
  DirectHostRecord? get plan => records['plan'];
  DirectHostRecord? get stop => records['stop'];
  DirectHostRecord? get terminal => records['terminal'];
}

String _record64(String kind, Map<String, String> fields) =>
    base64.encode(DirectHostRecord.create(kind, fields).encode());

String _attemptBindings(DirectSshAttempt attempt) {
  final owner = _record64('owner', attempt.identity);
  final admission = _record64('admission', attempt.identity);
  final pending = _record64('plan', {
    'planDigest': attempt.planDigest,
    'attemptId': attempt.attemptId,
    'terminal': 'pending',
  });
  final cancelled = _record64('plan', {
    'planDigest': attempt.planDigest,
    'attemptId': attempt.attemptId,
    'terminal': 'cancelled',
  });
  final stop = _record64('stop', {
    'attemptId': attempt.attemptId,
    'planDigest': attempt.planDigest,
  });
  final bindings =
      'root=/var/lib/serverdeck/ssh-v1\n' +
      "expected_boot='" +
      attempt.identity['bootIdHash']! +
      "'\n" +
      'attempt_dir=\$root/attempts/' +
      attempt.attemptId +
      '\n' +
      'plan_file=\$root/plans/' +
      attempt.planDigest +
      '\n' +
      'stop_file=\$root/stops/' +
      attempt.planDigest +
      '\n' +
      "expected_owner='" +
      owner +
      "'\n" +
      "expected_admission='" +
      admission +
      "'\n" +
      "expected_pending='" +
      pending +
      "'\n" +
      "expected_cancelled='" +
      cancelled +
      "'\n" +
      "expected_stop='" +
      stop +
      "'\n";
  return bindings;
}

String _hostCommand(DirectSshAttempt attempt, String kind) =>
    _attemptBindings(attempt) +
    _hostReadFunctions +
    (kind == 'status'
        ? _hostStatus
        : _hostWriteFunctions + (kind == 'reserve' ? _hostReserve : _hostStop));

const _hostReadFunctions = r'''
[ "$(/usr/bin/id -u)" = 0 ] || fail FORBIDDEN
safe_dir() {
  [ ! -L "$1" ] && [ -d "$1" ] || fail UNKNOWN_OUTCOME
  [ "$(/usr/bin/stat -c %u:%g -- "$1")" = 0:0 ] || fail UNKNOWN_OUTCOME
  mode=$(/usr/bin/stat -c %a -- "$1") || fail UNKNOWN_OUTCOME
  case "$mode" in
    [0-7]|[0-7][0-7]|[0-7][0-7][0-7]|[0-7][0-7][0-7][0-7]) ;;
    *) fail UNKNOWN_OUTCOME;;
  esac
  [ $((0$mode & 0022)) -eq 0 ] || fail UNKNOWN_OUTCOME
  if [ "$2" = private ]; then [ "$mode" = 700 ] || fail UNKNOWN_OUTCOME; fi
}
safe_file() {
  [ ! -L "$1" ] && [ -f "$1" ] || fail UNKNOWN_OUTCOME
  [ "$(/usr/bin/stat -c %u:%g:%a:%h -- "$1")" = 0:0:600:1 ] || fail UNKNOWN_OUTCOME
  size=$(/usr/bin/stat -c %s -- "$1") || fail UNKNOWN_OUTCOME
  case "$size" in ''|*[!0-9]*|??????*) fail RESOURCE_LIMIT;; esac
  [ "$size" -le 16384 ] || fail RESOURCE_LIMIT
}
ancestors() {
  safe_dir / public
  safe_dir /var public
  safe_dir /var/lib public
}
open_lock() {
  safe_file "$root/writer.lock"
  inode=$(/usr/bin/stat -c %d:%i -- "$root/writer.lock") || fail UNKNOWN_OUTCOME
  exec 9< "$root/writer.lock"
  /usr/bin/flock -n 9 || fail HOST_BUSY
  [ "$(/usr/bin/stat -Lc %d:%i -- /proc/self/fd/9)" = "$inode" ] || fail UNKNOWN_OUTCOME
  [ "$(/usr/bin/stat -c %d:%i -- "$root/writer.lock")" = "$inode" ] || fail UNKNOWN_OUTCOME
  [ ! -e "$root/.pending" ] && [ ! -L "$root/.pending" ] || fail UNKNOWN_OUTCOME
}
check_layout() {
  safe_dir /var/lib/serverdeck public
  safe_dir "$root" private
  safe_dir "$root/attempts" private
  safe_dir "$root/plans" private
  safe_dir "$root/stops" private
}
matches() {
  safe_file "$2"
  printf '%s' "$1" | /usr/bin/base64 -d | /usr/bin/cmp -s - "$2"
}
emit_record() {
  if [ -e "$2" ] || [ -L "$2" ]; then
    safe_file "$2"
    printf '%s\t' "$1"
    /usr/bin/base64 -w0 < "$2" || fail UNKNOWN_OUTCOME
    printf '\n'
  else
    text "$1" ""
  fi
}
snapshot() {
  text presence present
  text disposition "$1"
  emit_record owner "$root/owner"
  if [ -e "$attempt_dir" ] || [ -L "$attempt_dir" ]; then safe_dir "$attempt_dir" private; fi
  emit_record admission "$attempt_dir/admission"
  emit_record plan "$plan_file"
  emit_record stop "$stop_file"
  emit_record terminal "$attempt_dir/terminal"
}
''';

const _hostStatus = r'''
ancestors
if [ ! -e /var/lib/serverdeck ] && [ ! -L /var/lib/serverdeck ]; then
  text presence absent
  text disposition absent
  for name in owner admission plan stop terminal; do text "$name" ""; done
  exit 0
fi
safe_dir /var/lib/serverdeck public
if [ ! -e "$root" ] && [ ! -L "$root" ]; then
  text presence absent
  text disposition absent
  for name in owner admission plan stop terminal; do text "$name" ""; done
  exit 0
fi
check_layout
open_lock
snapshot snapshot
''';

const _hostWriteFunctions = r'''
ensure_dir() {
  if [ ! -e "$1" ] && [ ! -L "$1" ]; then
    /usr/bin/mkdir -m 700 -- "$1" || fail UNKNOWN_OUTCOME
    /usr/bin/chgrp -- 0 "$1" || fail UNKNOWN_OUTCOME
    /usr/bin/sync -f -- "$1" || fail UNKNOWN_OUTCOME
    /usr/bin/sync -f -- "$2" || fail UNKNOWN_OUTCOME
  fi
  safe_dir "$1" "$3"
}
initialize() {
  ancestors
  ensure_dir /var/lib/serverdeck /var/lib public
  ensure_dir "$root" /var/lib/serverdeck private
  created_lock=0
  if [ ! -e "$root/writer.lock" ] && [ ! -L "$root/writer.lock" ]; then
    # Only a completely empty new root can acquire its permanent lock inode.
    entries=$(/usr/bin/find "$root" -mindepth 1 -maxdepth 1 -printf x -quit) || fail UNKNOWN_OUTCOME
    [ -z "$entries" ] || fail UNKNOWN_OUTCOME
    ( set -C; : > "$root/writer.lock" ) || fail HOST_BUSY
    /usr/bin/chgrp -- 0 "$root/writer.lock" || fail UNKNOWN_OUTCOME
    /usr/bin/sync -f -- "$root/writer.lock" || fail UNKNOWN_OUTCOME
    /usr/bin/sync -f -- "$root" || fail UNKNOWN_OUTCOME
    created_lock=1
  fi
  open_lock
  # Existing partial layouts are not silently repaired around a retained owner.
  if [ "$created_lock" = 1 ]; then
    ensure_dir "$root/attempts" "$root" private
    ensure_dir "$root/plans" "$root" private
    ensure_dir "$root/stops" "$root" private
  fi
  check_layout
}
capacity() {
  # Stream a bounded inventory. DONE is required, so find/timeout failure
  # cannot be concealed by a successful downstream awk.
  root_device=$(/usr/bin/stat -c %d -- "$root") || fail UNKNOWN_OUTCOME
  total=$(
    ( /usr/bin/timeout 5 /usr/bin/find "$root" -xdev -printf '%y:%U:%G:%m:%n:%s:%D\n' &&
      printf 'DONE\n' ) |
    /usr/bin/awk -F: -v device="$root_device" '
      $0=="DONE" { done=1; next }
      { if(done || ++n>250000 || NF!=7 || ("d" $7)!=("d" device) || $2!="0" || $3!="0") exit 1
        if($1=="d") { if($4!="700") exit 1 }
        else if($1=="f") {
          if($4!="600" || $5!="1" || $6 !~ /^[0-9]+$/ || length($6)>8) exit 1
          total+=$6
          if(total>67108864) exit 1
        } else exit 1
      }
      END { if(!done) exit 1; printf "%.0f",total }
    '
  ) || fail RESOURCE_LIMIT
  [ $((total + $1)) -le 67108864 ] || fail RESOURCE_LIMIT
}
attempt_capacity() {
  (
    /usr/bin/timeout 5 /usr/bin/find "$root/plans" "$root/stops" -regextype posix-extended -mindepth 1 -maxdepth 1 \
      \( -type f -regex '.*/[a-f0-9]{64}' -printf 'ENTRY:%f\n' \) -o -printf 'INVALID\n' &&
    printf 'DONE\n'
  ) | /usr/bin/awk '
    $0=="DONE" { done=1; next }
    { name=substr($0,7)
      if(done || substr($0,1,6)!="ENTRY:" || length(name)!=64 || name !~ /^[a-f0-9]+$/) exit 1
      if(!seen[name]++ && ++n>=1250) exit 1 }
    END { if(!done) exit 1 }
  ' || fail RESOURCE_LIMIT
}
exclusive_record() {
  if [ -e "$2" ] || [ -L "$2" ]; then
    matches "$1" "$2" || fail UNKNOWN_OUTCOME
    return
  fi
  [ ! -e "$root/.pending" ] && [ ! -L "$root/.pending" ] || fail UNKNOWN_OUTCOME
  ( set -C; printf '%s' "$1" | /usr/bin/base64 -d > "$root/.pending" ) || fail UNKNOWN_OUTCOME
  /usr/bin/chgrp -- 0 "$root/.pending" || fail UNKNOWN_OUTCOME
  safe_file "$root/.pending"
  /usr/bin/sync -f -- "$root/.pending" || fail UNKNOWN_OUTCOME
  inode=$(/usr/bin/stat -c %d:%i -- "$root/.pending") || fail UNKNOWN_OUTCOME
  /usr/bin/mv -T -n -- "$root/.pending" "$2" || fail UNKNOWN_OUTCOME
  [ ! -e "$root/.pending" ] && [ ! -L "$root/.pending" ] || fail UNKNOWN_OUTCOME
  safe_file "$2"
  [ "$(/usr/bin/stat -c %d:%i -- "$2")" = "$inode" ] || fail UNKNOWN_OUTCOME
  /usr/bin/sync -f -- "$2" || fail UNKNOWN_OUTCOME
  /usr/bin/sync -f -- "$3" || fail UNKNOWN_OUTCOME
}
''';

const _hostReserve = r'''
reserve_attempt() {
  # A stale boot must fail before even initializing the metadata namespace.
  boot=$(/usr/bin/cat /proc/sys/kernel/random/boot_id) || fail PLAN_STALE
  boot_digest=$(printf '%s' "$boot" | /usr/bin/sha256sum) || fail PLAN_STALE
  [ "$boot_digest" = "$expected_boot  -" ] || fail PLAN_STALE
  initialize
  if [ -e "$stop_file" ] || [ -L "$stop_file" ]; then
    matches "$expected_stop" "$stop_file" || fail UNKNOWN_OUTCOME
    snapshot stopped
    return
  fi
  if [ -e "$plan_file" ] || [ -L "$plan_file" ]; then
    safe_file "$plan_file"
    snapshot existing
    return
  fi
  # Owner is committed first: a partial reservation cannot look like a free host.
  if [ -e "$root/owner" ] || [ -L "$root/owner" ]; then fail HOST_BUSY; fi
  if [ -e "$attempt_dir" ] || [ -L "$attempt_dir" ]; then fail UNKNOWN_OUTCOME; fi
  capacity 4096
  attempt_capacity
  exclusive_record "$expected_owner" "$root/owner" "$root"
  exclusive_record "$expected_pending" "$plan_file" "$root/plans"
  ensure_dir "$attempt_dir" "$root/attempts" private
  exclusive_record "$expected_admission" "$attempt_dir/admission" "$attempt_dir"
  snapshot reserved
}
reserve_attempt
''';

const _hostStop = r'''
initialize
# A scoped stop fence never releases or changes the current owner, including
# another attempt that is between steps while this plan's reserve is delayed.
if [ -e "$plan_file" ] || [ -L "$plan_file" ]; then
  if ! matches "$expected_pending" "$plan_file"; then snapshot existing; exit 0; fi
fi
if [ -e "$stop_file" ] || [ -L "$stop_file" ]; then
  matches "$expected_stop" "$stop_file" || fail UNKNOWN_OUTCOME
  snapshot stopped
  exit 0
fi
capacity 1024
if [ ! -e "$plan_file" ] && [ ! -L "$plan_file" ]; then attempt_capacity; fi
# Stop is keyed by plan as well as carrying attempt identity. Even a crash
# before its plan marker cannot permit a delayed reserve or a new attempt alias.
exclusive_record "$expected_stop" "$stop_file" "$root/stops"
if [ ! -e "$plan_file" ] && [ ! -L "$plan_file" ]; then
  exclusive_record "$expected_cancelled" "$plan_file" "$root/plans"
fi
snapshot stopped
''';
