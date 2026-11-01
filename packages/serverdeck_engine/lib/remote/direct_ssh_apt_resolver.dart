import 'dart:convert';

import 'package:cryptography/dart.dart';

import 'direct_ssh.dart';
import 'direct_ssh_apt_index.dart';
import 'direct_ssh_apt_targets.dart';
import 'direct_ssh_packages.dart';

Never _bad() => throw DirectSshFailure('QUALIFICATION_REQUIRED');
Never _limit() => throw DirectSshFailure('RESOURCE_LIMIT');
Never _stale() => throw DirectSshFailure('PLAN_STALE');
bool _protected(String name) =>
    name == 'netbird' || name.startsWith('netbird-');
String _hash(String value) => const DartSha256()
    .hashSync(utf8.encode(value))
    .bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

/// Effective apt-get target-release data, not a source/signature certificate.
/// argv[0]=apt-get makes APT apply Binary::apt-get overrides before the reset.
final class DirectAptPolicy {
  DirectAptPolicy._(this._raw, this.defaultRelease);
  factory DirectAptPolicy.capture(DirectSshOutput output) =>
      DirectAptPolicy._parse(output.textRows({'policy'})['policy']!);
  factory DirectAptPolicy._parse(String raw) {
    if (utf8.encode(raw).length > 1024) _limit();
    if (raw.isEmpty || raw == '\n') return DirectAptPolicy._(raw, null);
    if (!raw.endsWith('\n')) _bad();
    final value = raw.substring(0, raw.length - 1);
    if (value.isEmpty ||
        value.length > 256 ||
        value.codeUnits.any((c) => c < 32 || c == 127))
      _bad();
    return DirectAptPolicy._(raw, value);
  }
  final String _raw;
  final String? defaultRelease;
  String get digest => _hash(_raw);
  static const executables = [
    '/usr/bin/env',
    '/usr/bin/bash',
    '/usr/bin/base64',
    '/usr/bin/apt-config',
    '/usr/bin/timeout',
    '/usr/bin/head',
  ];

  // Keep Default-Release while resetting operational APT subtrees used by
  // apt-config's read-only architecture/compressor setup. Binary::apt-get has
  // already been moved to the root before this fixed -c stream is parsed.
  static final _configuration = DirectAptTargetsCommand.configuration
      .replaceFirst(
        '#clear APT;',
        '#clear APT::Architecture;\n#clear APT::Architectures;\n'
            '#clear APT::Compressor;\n#clear APT::System;',
      );
  static String get _read =>
      '/usr/bin/env -i PATH=/usr/bin:/bin LC_ALL=C TZ=UTC0 HOME=/ '
          '/usr/bin/bash --noprofile --norc -o pipefail -c \'' +
      r'''printf %s "$1" | /usr/bin/timeout --kill-after=1 5 /usr/bin/bash --noprofile --norc -c "exec -a apt-get /usr/bin/apt-config -c /dev/stdin --format %v%n dump APT::Default-Release" | /usr/bin/head -c 1025
''' +
      "' sdssh-apt '$_configuration'";
  static String get nativeBody =>
      r'''value=$( ''' +
      _read +
      r''' && printf '.') || fail QUALIFICATION_REQUIRED
value=${value%.}
text policy "$value"
''';
  @override
  String toString() => 'DirectAptPolicy';
}

final class _Selections {
  _Selections(this.digest, this.names, this.held);
  factory _Selections.parse(String raw) {
    if (utf8.encode(raw).length > 4 * 1024 * 1024) _limit();
    if (raw.isEmpty) _bad();
    final lines = raw.split('\n');
    if (lines.length > 16384) _limit();
    final canonical = <String, String>{}, names = <String>{}, held = <String>{};
    for (final line in lines) {
      final match = RegExp(
        r'^([a-z0-9][a-z0-9+.-]{0,127})(?::([a-z0-9][a-z0-9-]{0,31}))?[ \t]+(install|hold|deinstall|purge)$',
      ).firstMatch(line);
      if (match == null) _bad();
      final identity = match[1]! + ':' + (match[2] ?? 'amd64');
      if (canonical.containsKey(identity)) _bad();
      canonical[identity] = match[3]!;
      names.add(match[1]!);
      if (match[3] == 'hold') held.add(match[1]!);
    }
    final keys = canonical.keys.toList()..sort();
    return _Selections(
      _hash(keys.map((k) => '$k\t${canonical[k]}\n').join()),
      names,
      held,
    );
  }
  final String digest;
  final Set<String> names, held;
}

/// Read-only install simulation. Not a signed archive, supported recipe or
/// permission: catalog must also bind all additions to stable source and index
/// custody, actual signed archives, pinning and supported maintainer variants.
final class DirectAptResolveRequest {
  DirectAptResolveRequest._(this.roots, this.policy);
  factory DirectAptResolveRequest(
    List<DirectAptPackageKey> roots,
    DirectAptPolicy policy,
  ) {
    if (roots.isEmpty) _bad();
    if (roots.length > 256) _limit();
    final names = <String>{};
    for (final root in roots) {
      if (_protected(root.name) || !names.add(root.name)) _bad();
    }
    return DirectAptResolveRequest._(
      List.unmodifiable(
        [...roots]..sort((a, b) => a.identity.compareTo(b.identity)),
      ),
      policy,
    );
  }
  final List<DirectAptPackageKey> roots;
  final DirectAptPolicy policy;
  static const executables = [
    ...DirectAptPolicy.executables,
    '/usr/bin/dpkg-query',
    '/usr/bin/dpkg',
    '/usr/bin/apt-get',
  ];

  String get nativeBody {
    final expected = base64.encode(utf8.encode(policy._raw));
    final target = base64.encode(utf8.encode(policy.defaultRelease ?? ''));
    final rootArgs = roots
        .map((p) => "'${p.name}:${p.architecture}=${p.version}'")
        .join(' ');
    return r'''
policy_read() {
''' +
        DirectAptPolicy._read +
        r'''
}
beforePolicy=$(policy_read && printf '.') || fail QUALIFICATION_REQUIRED
beforePolicy=${beforePolicy%.}
''' +
        r"expectedPolicy=$(printf %s '" +
        expected +
        r"' | /usr/bin/base64 -d && printf '.') || fail QUALIFICATION_REQUIRED" +
        '\n' +
        r'''expectedPolicy=${expectedPolicy%.}
[ "$beforePolicy" = "$expectedPolicy" ] || fail PLAN_STALE
emit beforePackages /usr/bin/dpkg-query -W '-f=${binary:Package}\t${Architecture}\t${Version}\t${db:Status-Status}\n'
emit beforeSelections /usr/bin/dpkg --get-selections '*'
text beforePolicy "$beforePolicy"
printf 'simulation\t'
/usr/bin/env -i PATH=/usr/bin:/bin LC_ALL=C TZ=UTC0 HOME=/ /usr/bin/bash --noprofile --norc -o pipefail -c '
configuration=$1
release=$(printf %s "$2" | /usr/bin/base64 -d) || exit 1
shift 2
if [ -n "$release" ]; then set -- -t "$release" install "$@"; else set -- install "$@"; fi
printf %s "$configuration" | /usr/bin/timeout --kill-after=1 25 /usr/bin/apt-get -c /dev/stdin --simulate --quiet=2 --assume-yes --no-remove --no-upgrade --no-install-recommends --no-install-suggests "$@" 2>/dev/null | /usr/bin/base64 -w0
''' +
        "' sdssh-apt '${DirectAptTargetsCommand.configuration}' '$target' $rootArgs" +
        r''' || { printf '\n'; fail QUALIFICATION_REQUIRED; }
printf '\n'
emit afterPackages /usr/bin/dpkg-query -W '-f=${binary:Package}\t${Architecture}\t${Version}\t${db:Status-Status}\n'
emit afterSelections /usr/bin/dpkg --get-selections '*'
afterPolicy=$(policy_read && printf '.') || fail QUALIFICATION_REQUIRED
afterPolicy=${afterPolicy%.}
[ "$beforePolicy" = "$afterPolicy" ] || fail PLAN_STALE
text afterPolicy "$afterPolicy"
''';
  }

  DirectAptResolution capture(
    DirectSshOutput output, {
    required DirectPackageSnapshot baseline,
  }) {
    final rows = output.textRows({
      'beforePackages',
      'afterPackages',
      'beforeSelections',
      'afterSelections',
      'beforePolicy',
      'afterPolicy',
      'simulation',
    });
    if (rows['beforePolicy'] != policy._raw ||
        rows['afterPolicy'] != policy._raw)
      _stale();
    final before = DirectPackageSnapshot.captureText(rows['beforePackages']!);
    final after = DirectPackageSnapshot.captureText(rows['afterPackages']!);
    if (before.digest != baseline.digest || after.digest != baseline.digest)
      _stale();
    final first = _Selections.parse(rows['beforeSelections']!),
        last = _Selections.parse(rows['afterSelections']!);
    if (first.digest != last.digest) _stale();
    final occupied = baseline.installedOrConfiguredNames;
    if (!first.names.containsAll(occupied)) _bad();
    final transcript = rows['simulation']!;
    if (utf8.encode(transcript).length > 4 * 1024 * 1024) _limit();
    if (transcript.isEmpty || !transcript.endsWith('\n')) _bad();
    final lines = transcript.substring(0, transcript.length - 1).split('\n');
    if (lines.length > 512) _limit();
    final additions = <String, DirectAptPackageKey>{}, configured = <String>{};
    for (final line in lines) {
      if (line.length > 4096) _limit();
      // Upgrades/reinstalls put the current-version bracket before '(' and
      // fail this grammar. RelStr cannot contain brackets/parentheses/controls.
      final match = RegExp(
        r'^(Inst|Conf) ([a-z0-9][a-z0-9+.-]{0,127})(?::(amd64|all))? \(([A-Za-z0-9.+:~\-]{1,256}) [^\[\]\r\n()\x00-\x1f\x7f]{0,2048} \[(amd64|all)\]\)$',
      ).firstMatch(line);
      if (match == null) _bad();
      final key = DirectAptPackageKey(match[2]!, match[5]!, match[4]!);
      if (_protected(key.name) ||
          occupied.contains(key.name) ||
          first.held.contains(key.name) ||
          match[3] == 'all' && key.architecture != 'all')
        _bad();
      if (match[1] == 'Inst') {
        if (additions.containsKey(key.name)) _bad();
        additions[key.name] = key;
      } else {
        if (additions[key.name]?.identity != key.identity ||
            !configured.add(key.name))
          _bad();
      }
    }
    if (additions.isEmpty || additions.length != configured.length) _bad();
    for (final root in roots) {
      if (additions[root.name]?.identity != root.identity) _bad();
    }
    final result = additions.values.toList()
      ..sort((a, b) => a.identity.compareTo(b.identity));
    return DirectAptResolution._(
      List.unmodifiable(result),
      baseline.digest,
      first.digest,
      policy.digest,
    );
  }

  @override
  String toString() => 'DirectAptResolveRequest';
}

final class DirectAptResolution {
  DirectAptResolution._(
    this.additions,
    this.packagesDigest,
    this.selectionsDigest,
    this.policyDigest,
  );
  final List<DirectAptPackageKey> additions;
  final String packagesDigest, selectionsDigest, policyDigest;
  @override
  String toString() => 'DirectAptResolution';
}
