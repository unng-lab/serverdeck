import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/automation/direct_ssh_dispatch.dart';

import '../automation/compiler.dart' show renderedConfiguration;
import '../automation/direct_dispatch_binding.dart'
    show directBindingDigest, directTargetBinding;

import 'direct_ssh_records.dart';
import 'direct_ssh_apt_release.dart';
import 'direct_ssh_apt_targets.dart';
import 'direct_ssh_apt_index.dart';
import 'direct_ssh_apt_resolver.dart';

part 'direct_ssh_jobs.dart';
part 'direct_ssh_worker.dart';
part 'direct_ssh_step_snapshot.dart';
part 'direct_ssh_terminal.dart';

const directSshCodes = {
  'VALIDATION',
  'FORBIDDEN',
  'PREREQUISITE_UNAVAILABLE',
  'RESOURCE_LIMIT',
  'TIMEOUT',
  'HOST_BUSY',
  'PLAN_STALE',
  'TRUST_CHANGED',
  'QUALIFICATION_REQUIRED',
  'UNKNOWN_OUTCOME',
  'CHECK_FAILED',
  'CANCELLED',
};

final class DirectSshFailure implements Exception {
  factory DirectSshFailure(String code) {
    if (!directSshCodes.contains(code)) {
      return const DirectSshFailure._('UNKNOWN_OUTCOME');
    }
    return DirectSshFailure._(code);
  }
  const DirectSshFailure._(this.code);
  final String code;
  @override
  String toString() => 'DirectSshFailure(' + code + ')';
}

Never _fail(String code) => throw DirectSshFailure(code);

/// A closed compiler product, not a caller-supplied command string.
final class DirectSshCommand {
  DirectSshCommand._(
    this.kind,
    this.resourceId,
    String body, {
    List<String>? tools,
  }) : requiredExecutables = List.unmodifiable(
         tools ?? _tools(kind, resourceId),
       ),
       script =
           _prefix + _toolChecks(tools ?? _tools(kind, resourceId)) + body {
    if (utf8.encode(script).length > 256 * 1024) _fail('RESOURCE_LIMIT');
  }

  factory DirectSshCommand.inspect() => DirectSshCommand._('inspect', null, r'''
[ "$(/usr/bin/id -u)" = 0 ] || fail FORBIDDEN
emit machine /usr/bin/cat /etc/machine-id
emit boot /usr/bin/cat /proc/sys/kernel/random/boot_id
emit uptime /usr/bin/cat /proc/uptime
emit os /usr/bin/cat /usr/lib/os-release
emit architecture /usr/bin/uname -m
emit init /usr/bin/cat /proc/1/comm
emit uid /usr/bin/id -u
''');

  factory DirectSshCommand.packages() =>
      DirectSshCommand._('packages', null, r'''
emit packages /usr/bin/dpkg-query -W '-f=${binary:Package}\t${Architecture}\t${Version}\t${db:Status-Status}\n'
''');

  factory DirectSshCommand.aptRelease(DirectAptReleaseRequest request) =>
      DirectSshCommand._(
        'apt-release',
        null,
        request.nativeBody,
        tools: DirectAptReleaseRequest.executables,
      );

  factory DirectSshCommand.aptIndexTargets() => DirectSshCommand._(
    'apt-index-targets',
    null,
    DirectAptTargetsCommand.nativeBody,
    tools: DirectAptTargetsCommand.executables,
  );

  factory DirectSshCommand.aptIndex(DirectAptIndexRequest request) =>
      DirectSshCommand._(
        'apt-index',
        null,
        request.nativeBody,
        tools: DirectAptIndexRequest.executables,
      );

  factory DirectSshCommand.aptPolicy() => DirectSshCommand._(
    'apt-policy',
    null,
    DirectAptPolicy.nativeBody,
    tools: DirectAptPolicy.executables,
  );
  factory DirectSshCommand.aptResolve(DirectAptResolveRequest request) =>
      DirectSshCommand._(
        'apt-resolve',
        null,
        request.nativeBody,
        tools: DirectAptResolveRequest.executables,
      );

  factory DirectSshCommand.observation(String resource) {
    final unit = switch (resource) {
      'postgresql.service' => 'postgresql@16-main.service',
      'clickhouse.service' => 'clickhouse-server.service',
      _ => null,
    };
    if (unit != null) {
      return DirectSshCommand._(
        'observation',
        resource,
        'emit unit /usr/bin/systemctl show ' + unit + ' --no-pager --property=LoadState,ActiveState,UnitFileState,MainPID,ControlPID,ExecMainStartTimestampMonotonic,ControlGroup,FragmentPath\n',
      );
    }
    final path = switch (resource) {
      'system.motd' => '/etc/motd',
      'postgresql.settings' => '/etc/postgresql/16/main/conf.d/serverdeck.conf',
      'clickhouse.settings' => '/etc/clickhouse-server/config.d/serverdeck.xml',
      _ => _fail('VALIDATION'),
    };
    return DirectSshCommand._(
      'observation',
      resource,
      'file=' +
          path +
          '\nparents="' +
          (switch (resource) {
            'system.motd' => '/ /etc',
            'postgresql.settings' => '/ /etc /etc/postgresql /etc/postgresql/16 /etc/postgresql/16/main /etc/postgresql/16/main/conf.d',
            _ =>
              '/ /etc /etc/clickhouse-server /etc/clickhouse-server/config.d',
          }) +
          '"\n' +
          r'''
absent() {
  text exists false
  text attributes absent
  text afterAttributes absent
  text digest absent
  text file ""
}
for parent in $parents; do
  [ ! -L "$parent" ] || fail QUALIFICATION_REQUIRED
  if [ ! -e "$parent" ]; then absent; exit 0; fi
  [ -d "$parent" ] && [ "$(/usr/bin/stat -c %u -- "$parent")" = 0 ] || fail QUALIFICATION_REQUIRED
  mode=$(/usr/bin/stat -c %a -- "$parent") || fail QUALIFICATION_REQUIRED
  case "$mode" in [0-7]|[0-7][0-7]|[0-7][0-7][0-7]|[0-7][0-7][0-7][0-7]) ;; *) fail QUALIFICATION_REQUIRED;; esac
  [ $((0$mode & 0022)) -eq 0 ] || fail QUALIFICATION_REQUIRED
done
[ ! -L "$file" ] || fail QUALIFICATION_REQUIRED
if [ ! -e "$file" ]; then absent; exit 0; fi
[ -f "$file" ] && [ -r "$file" ] || fail FORBIDDEN
format=%u:%g:%a:%h:%s:%d:%i:%y:%z
before=$(/usr/bin/stat -c "$format" -- "$file") || fail QUALIFICATION_REQUIRED
size=$(/usr/bin/stat -c %s -- "$file") || fail QUALIFICATION_REQUIRED
case "$size" in ''|*[!0-9]*|??????*) fail RESOURCE_LIMIT;; esac
[ "$size" -le 65536 ] || fail RESOURCE_LIMIT
text attributes "$before"
digest=$(/usr/bin/timeout 5 /usr/bin/sha256sum -- "$file") || fail TIMEOUT
text digest "$digest"
text exists true
printf 'file\t'
# Footer exists only after a complete no-follow bounded read. A pipeline failure
# cannot impersonate a valid empty file; the local parser also verifies hash/size.
( /usr/bin/timeout 5 /usr/bin/dd if="$file" iflag=nofollow,count_bytes count=65537 status=none &&
  printf '\nSDSSH_FILE_COMPLETE_V1\n' ) | /usr/bin/base64 -w0 || fail QUALIFICATION_REQUIRED
printf '\n'
[ ! -L "$file" ] && [ -f "$file" ] || fail QUALIFICATION_REQUIRED
emit afterAttributes /usr/bin/stat -c "$format" -- "$file"
''',
    );
  }

  factory DirectSshCommand.reserveAttempt(DirectSshAttempt attempt) =>
      DirectSshCommand._('reserve', null, _hostCommand(attempt, 'reserve'));
  factory DirectSshCommand.stopAttempt(DirectSshAttempt attempt) =>
      DirectSshCommand._('stop', null, _hostCommand(attempt, 'stop'));
  factory DirectSshCommand.attemptStatus(DirectSshAttempt attempt) =>
      DirectSshCommand._('status', null, _hostCommand(attempt, 'status'));

  factory DirectSshCommand.launchStep(DirectSshStep step) {
    if (step.dispatch.state != 'authorized' || step._baseline == null)
      _fail('UNKNOWN_OUTCOME');
    return DirectSshCommand._('launch', step.resourceId, _launchStep(step));
  }
  factory DirectSshCommand.stepStatus(
    DirectSshStep step, {
    bool historyOnly = false,
  }) => DirectSshCommand._(
    'step-status',
    step.resourceId,
    _stepStatus(step, historyOnly: historyOnly),
    tools: historyOnly ? _metadataReadTools : _workerTools('step-status'),
  );
  factory DirectSshCommand.finalizeAttempt(DirectFinalization proof) =>
      DirectSshCommand._(
        'terminal',
        proof.receipt.step.resourceId,
        _finalizeAttempt(proof),
        tools: proof.historicalOnly
            ? _metadataReadTools
            : _tools('terminal', null),
      );

  factory DirectSshCommand.cancelUndispatched(
    DirectUndispatchedCancellation proof,
  ) => DirectSshCommand._(
    'terminal',
    null,
    _cancelUndispatched(proof),
    tools: [
      ..._metadataReadTools,
      '/usr/bin/timeout',
      '/usr/bin/find',
      if (!proof.historicalOnly) ...[
        '/usr/bin/cat',
        '/usr/bin/sha256sum',
        '/usr/bin/systemctl',
        '/usr/bin/awk',
        '/usr/bin/chgrp',
        '/usr/bin/mv',
        '/usr/bin/sync',
        '/usr/bin/rm',
      ],
    ],
  );

  static const _prefix = r'''#!/bin/sh
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
LC_ALL=C
TZ=UTC0
export PATH LC_ALL TZ
umask 077
fail() { printf 'SDSSH_ERROR\t%s\n' "$1"; exit 1; }
text() {
  printf '%s\t' "$1"
  printf '%s' "$2" | /usr/bin/base64 -w0
  printf '\n'
}
emit() {
  name=$1
  shift
  value=$("$@" 2>/dev/null) || fail PREREQUISITE_UNAVAILABLE
  text "$name" "$value"
}
''';

  static List<String> _tools(String kind, String? resource) {
    if (kind == 'terminal')
      return [
        ..._workerTools('launch')
            .where((tool) => tool != '/usr/bin/systemd-run'),
        '/usr/bin/rm',
      ];
    if (kind == 'launch' || kind == 'step-status') return _workerTools(kind);
    if (kind == 'packages')
      return const ['/usr/bin/base64', '/usr/bin/dpkg-query'];
    if (const {'reserve', 'stop', 'status'}.contains(kind)) {
      return [
        '/usr/bin/base64',
        '/usr/bin/id',
        '/usr/bin/stat',
        '/usr/bin/flock',
        '/usr/bin/cmp',
        if (kind == 'reserve') ...['/usr/bin/cat', '/usr/bin/sha256sum'],
        if (kind != 'status') ...[
          '/usr/bin/mkdir',
          '/usr/bin/chgrp',
          '/usr/bin/mv',
          '/usr/bin/sync',
          '/usr/bin/find',
          '/usr/bin/timeout',
          '/usr/bin/awk',
        ],
      ];
    }
    if (kind == 'inspect') {
      return const [
        '/usr/bin/base64',
        '/usr/bin/id',
        '/usr/bin/cat',
        '/usr/bin/uname',
      ];
    }
    if (resource != null && resource.endsWith('.service')) {
      return const ['/usr/bin/base64', '/usr/bin/systemctl'];
    }
    return const [
      '/usr/bin/base64',
      '/usr/bin/stat',
      '/usr/bin/sha256sum',
      '/usr/bin/dd',
      '/usr/bin/timeout',
    ];
  }

  static String _toolChecks(List<String> paths) => paths
      .map((path) => '[ -x ' + path + ' ] || fail PREREQUISITE_UNAVAILABLE\n')
      .join();

  final String kind;
  final String? resourceId;
  final String script;
  final List<String> requiredExecutables;
  bool get privileged => true;
  bool get mutates =>
      const {'reserve', 'stop', 'launch', 'terminal'}.contains(kind);
  bool get requiresApply => const {'reserve', 'stop', 'launch'}.contains(kind);
  int get outputLimit =>
      const {
        'packages',
        'apt-release',
        'apt-index-targets',
        'apt-index',
        'apt-resolve',
      }.contains(kind)
      ? 8 * 1024 * 1024
      : kind == 'step-status'
      ? 512 * 1024
      : kind == 'inspect'
      ? 64 * 1024
      : 128 * 1024;
  Duration get maximumDuration =>
      const {
        'inspect',
        'stop',
        'status',
        'step-status',
        'terminal',
      }.contains(kind)
      ? const Duration(seconds: 10)
      : const Duration(seconds: 30);
  @override
  String toString() => 'DirectSshCommand(' + kind + ')';
}

/// Output owns a private immutable copy; raw bytes never enter diagnostics.
final class DirectSshOutput {
  DirectSshOutput(
    List<int> bytes, {
    required this.exitCode,
    required this.truncated,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView() {
    if (bytes.length > 8 * 1024 * 1024) _fail('RESOURCE_LIMIT');
  }
  final Uint8List bytes;
  final int? exitCode;
  final bool truncated;

  Map<String, String> textRows(Set<String> expected) {
    if (truncated || exitCode == null) _fail('UNKNOWN_OUTCOME');
    try {
      final source = ascii.decode(bytes);
      if (source.isEmpty || !source.endsWith('\n')) _fail('UNKNOWN_OUTCOME');
      final lines = source.substring(0, source.length - 1).split('\n');
      String? errorCode;
      if (exitCode != 0) {
        final error = RegExp(r'^SDSSH_ERROR\t([A-Z_]+)$')
            .firstMatch(lines.removeLast());
        if (error == null || !directSshCodes.contains(error[1])) {
          _fail('UNKNOWN_OUTCOME');
        }
        errorCode = error[1];
      }
      final result = <String, String>{};
      for (final line in lines) {
        final columns = line.split('\t');
        if (columns.length != 2 ||
            !expected.contains(columns[0]) ||
            result.containsKey(columns[0])) {
          _fail('UNKNOWN_OUTCOME');
        }
        final data = base64.decode(columns[1]);
        if (base64.encode(data) != columns[1]) _fail('UNKNOWN_OUTCOME');
        // dart:convert consumes a leading UTF8 BOM. These framed values are
        // literal file/payload bytes used for size and SHA256 verification,
        // so preserve the corresponding character instead of normalizing it.
        final bom =
            data.length >= 3 &&
            data[0] == 0xef &&
            data[1] == 0xbb &&
            data[2] == 0xbf;
        result[columns[0]] = (bom ? '\ufeff' : '') + utf8.decode(data);
      }
      if (errorCode != null) _fail(errorCode);
      if (result.length != expected.length) _fail('UNKNOWN_OUTCOME');
      return Map.unmodifiable(result);
    } on DirectSshFailure {
      rethrow;
    } catch (_) {
      _fail('UNKNOWN_OUTCOME');
    }
  }

  @override
  String toString() => 'DirectSshOutput';
}

final class DirectSshIdentity {
  DirectSshIdentity._(this.hostId, this.bootIdHash, this.uptimeMs);
  static const fields = {
    'machine',
    'boot',
    'uptime',
    'os',
    'architecture',
    'init',
    'uid',
  };

  factory DirectSshIdentity.capture(Map<String, String> rows) {
    if (rows.length != fields.length ||
        !rows.keys.toSet().containsAll(fields)) {
      _fail('PREREQUISITE_UNAVAILABLE');
    }
    if (rows['uid'] != '0') _fail('FORBIDDEN');
    const limits = {
      'machine': 32,
      'boot': 36,
      'uptime': 128,
      'os': 16384,
      'architecture': 16,
      'init': 64,
      'uid': 10,
    };
    for (final field in limits.entries) {
      if (rows[field.key]!.length > field.value) _fail('RESOURCE_LIMIT');
    }
    final machine = rows['machine']!;
    final boot = rows['boot']!;
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(machine) ||
        machine == '00000000000000000000000000000000' ||
        !RegExp(r'^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$')
            .hasMatch(boot) ||
        rows['architecture'] != 'x86_64' ||
        rows['init'] != 'systemd') {
      _fail('PREREQUISITE_UNAVAILABLE');
    }
    final os = <String, String>{};
    for (final line in rows['os']!.split('\n')) {
      if (line.isEmpty || line.startsWith('#')) continue;
      final separator = line.indexOf('=');
      if (separator < 1) _fail('PREREQUISITE_UNAVAILABLE');
      final key = line.substring(0, separator);
      var value = line.substring(separator + 1);
      if (os.containsKey(key)) _fail('PREREQUISITE_UNAVAILABLE');
      if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
        value = value.substring(1, value.length - 1);
      }
      os[key] = value;
    }
    if (os['ID'] != 'ubuntu' || os['VERSION_ID'] != '24.04') {
      _fail('PREREQUISITE_UNAVAILABLE');
    }
    final time = RegExp(
      r'^((?:0|[1-9][0-9]{0,15}))\.([0-9]{1,3}) [0-9]{1,20}(?:\.[0-9]{1,3})?$',
    ).firstMatch(rows['uptime']!);
    if (time == null) _fail('PREREQUISITE_UNAVAILABLE');
    final seconds = BigInt.tryParse(time[1]!);
    if (seconds == null) _fail('PREREQUISITE_UNAVAILABLE');
    final milliseconds =
        seconds * BigInt.from(1000) + BigInt.parse(time[2]!.padRight(3, '0'));
    if (milliseconds > BigInt.parse('9223372036854775807')) {
      _fail('RESOURCE_LIMIT');
    }
    final key = SecretKeyData(utf8.encode('ServerDeck/direct-ssh/host/v1'));
    final hash = Uint8List.fromList(
      DartHmac.sha256()
          .calculateMacSync(
            ascii.encode(machine),
            secretKeyData: key,
            nonce: const [],
          )
          .bytes
          .take(16)
          .toList(),
    );
    key.destroy();
    hash[6] = (hash[6] & 0x0f) | 0x40;
    hash[8] = (hash[8] & 0x3f) | 0x80;
    final hex = hash
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final host =
        hex.substring(0, 8) +
        '-' +
        hex.substring(8, 12) +
        '-' +
        hex.substring(12, 16) +
        '-' +
        hex.substring(16, 20) +
        '-' +
        hex.substring(20);
    final bootHash = const DartSha256()
        .hashSync(ascii.encode(boot))
        .bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return DirectSshIdentity._(host, bootHash, milliseconds.toInt());
  }

  final String hostId, bootIdHash;
  final int uptimeMs;
  @override
  String toString() => 'DirectSshIdentity';
}
