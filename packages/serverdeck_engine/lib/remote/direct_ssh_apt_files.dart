import 'dart:convert';

import 'package:cryptography/dart.dart';

import 'direct_ssh.dart';

Never _bad() => throw DirectSshFailure('QUALIFICATION_REQUIRED');
Never _limit() => throw DirectSshFailure('RESOURCE_LIMIT');

/// Private root-file custody common to APT reads. A stable hash is not a
/// signature, source policy or package qualification. Paths are compiler data.
final class DirectAptFileSet {
  DirectAptFileSet._(this.limits, this._parents, this._worldReadable);

  factory DirectAptFileSet(
    Map<String, int> limits, {
    bool worldReadable = true,
  }) {
    if (limits.isEmpty) _bad();
    if (limits.length > 128) _limit();
    final parents = <String>{'/'};
    for (final entry in limits.entries) {
      final path = entry.key;
      if (path.length > 1024 ||
          !RegExp(r'^/[a-zA-Z0-9._%+:~/-]+$').hasMatch(path) ||
          path
              .substring(1)
              .split('/')
              .any((p) => p.isEmpty || p == '.' || p == '..') ||
          !const [
            '/var/lib/apt/lists/',
            '/etc/apt/',
            '/usr/share/keyrings/',
          ].any(path.startsWith) ||
          entry.value < 1 ||
          entry.value > 512 * 1024 * 1024)
        _bad();
      var parent = path.substring(0, path.lastIndexOf('/'));
      while (parent.isNotEmpty) {
        parents.add(parent);
        parent = parent.substring(0, parent.lastIndexOf('/'));
      }
    }
    return DirectAptFileSet._(
      Map.unmodifiable(limits),
      List.unmodifiable(parents.toList()..sort()),
      worldReadable,
    );
  }

  final Map<String, int> limits;
  final List<String> _parents;
  final bool _worldReadable;
  static const executables = [
    '/usr/bin/stat',
    '/usr/bin/sha256sum',
    '/usr/bin/timeout',
  ];

  /// Defines snapshot(), without starting any read itself. No temporary file,
  /// lock inode or directory is created. uid/mode/link checks are repeated in
  /// the local parser; before/after equality covers nanosecond metadata too.
  String get nativeDefinition =>
      'requiredDirectoryBit=${_worldReadable ? 1 : 0}\nrequiredFileBit=${_worldReadable ? 4 : 0}\n' +
      r'''
snapshot() {
''' +
      '  for path in ${_parents.map((p) => "'$p'").join(' ')}; do\n' +
      r'''
    [ ! -L "$path" ] && [ -d "$path" ] || fail QUALIFICATION_REQUIRED
    [ "$(/usr/bin/stat -c %u -- "$path")" = 0 ] || fail QUALIFICATION_REQUIRED
    mode=$(/usr/bin/stat -c %a -- "$path") || fail QUALIFICATION_REQUIRED
    case "$mode" in [0-7]|[0-7][0-7]|[0-7][0-7][0-7]|[0-7][0-7][0-7][0-7]) ;; *) fail QUALIFICATION_REQUIRED;; esac
    [ $((0$mode & 0022)) -eq 0 ] && [ $((0$mode & requiredDirectoryBit)) -eq "$requiredDirectoryBit" ] || fail QUALIFICATION_REQUIRED
    printf 'd\t%s\t' "$path"
    /usr/bin/stat --printf='%u\t%g\t%a\t%h\t%s\t%d\t%i\t%y\t%z\n' -- "$path" || fail QUALIFICATION_REQUIRED
  done
''' +
      '  for path in ${limits.keys.map((p) => "'$p'").join(' ')}; do\n' +
      r'''
    [ ! -L "$path" ] && [ -f "$path" ] && [ -r "$path" ] || fail QUALIFICATION_REQUIRED
    [ "$(/usr/bin/stat -c %u -- "$path")" = 0 ] && [ "$(/usr/bin/stat -c %h -- "$path")" = 1 ] || fail QUALIFICATION_REQUIRED
    mode=$(/usr/bin/stat -c %a -- "$path") || fail QUALIFICATION_REQUIRED
    case "$mode" in [0-7]|[0-7][0-7]|[0-7][0-7][0-7]|[0-7][0-7][0-7][0-7]) ;; *) fail QUALIFICATION_REQUIRED;; esac
    [ $((0$mode & 0022)) -eq 0 ] && [ $((0$mode & requiredFileBit)) -eq "$requiredFileBit" ] || fail QUALIFICATION_REQUIRED
    size=$(/usr/bin/stat -c %s -- "$path") || fail QUALIFICATION_REQUIRED
    case "$size" in ''|*[!0-9]*|??????????*) fail RESOURCE_LIMIT;; esac
    case "$path" in
''' +
      limits.entries
          .map((e) => "      '${e.key}') maximum=${e.value};;\n")
          .join() +
      r'''
      *) fail QUALIFICATION_REQUIRED;;
    esac
    [ "$size" -gt 0 ] && [ "$size" -le "$maximum" ] || fail RESOURCE_LIMIT
    hash=$(/usr/bin/timeout 3 /usr/bin/sha256sum -- "$path") || fail QUALIFICATION_REQUIRED
    hash=${hash%% *}
    printf 'f\t%s\t' "$path"
    /usr/bin/stat --printf='%u\t%g\t%a\t%h\t%s\t%d\t%i\t%y\t%z' -- "$path" || fail QUALIFICATION_REQUIRED
    printf '\t%s\n' "$hash"
  done
}
''';

  DirectAptFileSnapshot capture(String before, String after) {
    if (utf8.encode(before).length > 128 * 1024 ||
        utf8.encode(after).length > 128 * 1024)
      _limit();
    if (before != after) throw DirectSshFailure('PLAN_STALE');
    final lines = before.split('\n'), files = limits.keys.toList();
    if (lines.length != _parents.length + files.length) _bad();
    final hashes = <String, String>{};
    for (var i = 0; i < lines.length; i++) {
      final columns = lines[i].split('\t');
      final directory = i < _parents.length;
      final path = directory ? _parents[i] : files[i - _parents.length];
      if (columns.length != (directory ? 11 : 12) ||
          columns[0] != (directory ? 'd' : 'f') ||
          columns[1] != path ||
          columns[2] != '0')
        _bad();
      for (final index in [3, 5, 6, 7, 8]) {
        if (!RegExp(r'^(0|[1-9][0-9]{0,18})$').hasMatch(columns[index])) _bad();
      }
      if (!RegExp(r'^[0-7]{1,4}$').hasMatch(columns[4])) _bad();
      final mode = int.parse(columns[4], radix: 8),
          links = int.tryParse(columns[5]);
      if (mode & 0x12 != 0 ||
          _worldReadable && mode & (directory ? 1 : 4) == 0 ||
          links == null ||
          links < 1)
        _bad();
      for (final index in [9, 10]) {
        if (!RegExp(
          r'^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{9} \+0000$',
        ).hasMatch(columns[index]))
          _bad();
      }
      if (!directory) {
        final size = int.tryParse(columns[6]);
        if (columns[5] != '1' ||
            size == null ||
            size < 1 ||
            size > limits[path]! ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(columns[11]))
          _bad();
        hashes[path] = columns[11];
      }
    }
    final digest = const DartSha256()
        .hashSync(utf8.encode(before))
        .bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return DirectAptFileSnapshot._(Map.unmodifiable(hashes), digest);
  }

  @override
  String toString() => 'DirectAptFileSet';
}

final class DirectAptFileSnapshot {
  DirectAptFileSnapshot._(this.digests, this.bindingDigest);
  final Map<String, String> digests;
  final String bindingDigest;
  @override
  String toString() => 'DirectAptFileSnapshot';
}
