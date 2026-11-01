import 'direct_ssh.dart';
import 'direct_ssh_apt_files.dart';
import 'direct_ssh_apt_metadata.dart';
import 'direct_ssh_apt_release.dart';
import 'direct_ssh_apt_targets.dart';

Never _bad() => throw DirectSshFailure('QUALIFICATION_REQUIRED');
Never _limit() => throw DirectSshFailure('RESOURCE_LIMIT');

/// Exact resolver selection, before an archive checksum has been established.
/// This is never a package argument supplied through the public API.
final class DirectAptPackageKey {
  DirectAptPackageKey._(this.name, this.architecture, this.version);
  factory DirectAptPackageKey(
    String name,
    String architecture,
    String version,
  ) {
    if (!RegExp(r'^[a-z0-9][a-z0-9+.-]{0,127}$').hasMatch(name) ||
        !const {'amd64', 'all'}.contains(architecture) ||
        !RegExp(r'^[A-Za-z0-9.+:~\-]{1,256}$').hasMatch(version) ||
        version.toLowerCase() == 'latest')
      _bad();
    return DirectAptPackageKey._(name, architecture, version);
  }
  final String name, architecture, version;
  String get identity => '$name\t$architecture\t$version';
  @override
  String toString() => 'DirectAptPackageKey';
}

/// One existing Packages index read, bound to its complete decoded hash/size.
/// Native libapt decodes the actual cached filename; compressed-file hashes
/// alone are never substituted for the Release's uncompressed MetaKey digest.
final class DirectAptIndexRequest {
  DirectAptIndexRequest._(this.target, this.packages, this._files);
  factory DirectAptIndexRequest(
    DirectAptIndexTarget target,
    List<DirectAptPackageKey> packages,
  ) {
    if (packages.isEmpty) _bad();
    if (packages.length > 256) _limit();
    final selected = [...packages]
      ..sort((a, b) => a.identity.compareTo(b.identity));
    if (selected.map((p) => p.identity).toSet().length != selected.length)
      _bad();
    return DirectAptIndexRequest._(
      target,
      List.unmodifiable(selected),
      DirectAptFileSet({target.filename: 512 * 1024 * 1024}),
    );
  }
  final DirectAptIndexTarget target;
  final List<DirectAptPackageKey> packages;
  final DirectAptFileSet _files;
  static const executables = [
    '/usr/bin/base64',
    '/usr/bin/env',
    '/usr/bin/bash',
    '/usr/bin/timeout',
    '/usr/bin/stat',
    '/usr/bin/sha256sum',
    '/usr/bin/wc',
    '/usr/bin/head',
    '/usr/bin/awk',
    '/usr/lib/apt/apt-helper',
  ];

  /// Only selected paragraphs are buffered. An oversized irrelevant paragraph
  /// cannot allocate an unbounded buffer. The decoder stream is capped at
  /// 512MiB+1 and the selection at256 paragraphs/4MiB/128KiB each.
  String get _filter =>
      'BEGIN {\n' +
      packages
          .map(
            (p) =>
                '  wanted["${p.name}" SUBSEP "${p.architecture}" SUBSEP "${p.version}"]=1;\n',
          )
          .join() +
      r'''}
function finish() {
  if ((p SUBSEP a SUBSEP v) in wanted) {
    if (large || ++count > 256 || total + bytes + 1 > 4194304) exit 42;
    printf "%s\n", buffer;
    total += bytes + 1;
  }
  p=""; a=""; v=""; buffer=""; bytes=0; large=0;
}
{
  sub(/\r$/, "");
  if ($0 == "") { finish(); next; }
  bytes += length($0) + 1;
  if (length($0) > 8192 || bytes > 131072) large=1;
  if (!large) buffer = buffer $0 "\n";
  if ($0 !~ /^[ \t]/) {
    colon=index($0, ":");
    if (colon > 1) {
      field=tolower(substr($0, 1, colon-1));
      value=substr($0, colon+1);
      sub(/^[ \t]*/, "", value); sub(/[ \t]*$/, "", value);
      if (field == "package") p=value;
      if (field == "architecture") a=value;
      if (field == "version") v=value;
    }
  }
}
END { finish(); }
''';

  String get nativeBody {
    // Every string inserted into a shell/awk literal has a closed ASCII
    // grammar. Configuration is a fixed argument to printf, never eval'd.
    final config = DirectAptTargetsCommand.configuration;
    final read =
        'printf %s "\$1" | /usr/bin/timeout --kill-after=1 8 '
        '/usr/lib/apt/apt-helper -c /dev/stdin cat-file "\$2" 2>/dev/null '
        '| /usr/bin/head -c 536870913';
    String stream(String name, String consumer, {bool filter = false}) =>
        "printf '$name\\t'\n" +
        '/usr/bin/env -i PATH=/usr/bin:/bin LC_ALL=C TZ=UTC0 HOME=/ '
            '/usr/bin/bash --noprofile --norc -o pipefail -c \'' +
        read +
        ' | ' +
        consumer +
        ' | /usr/bin/base64 -w0\n' +
        "' sdssh-apt '$config' '${target.filename}'" +
        (filter ? " '$_filter'" : '') +
        r''' || { printf '\n'; fail QUALIFICATION_REQUIRED; }
printf '\n'
''';
    return _files.nativeDefinition +
        r'''
before=$(snapshot) || fail QUALIFICATION_REQUIRED
text manifest "$before"
''' +
        stream('decodedHash', '/usr/bin/sha256sum') +
        stream('decodedSize', '/usr/bin/wc -c') +
        stream(
          'packages',
          r'''(ulimit -v 131072 && exec /usr/bin/awk "$3")''',
          filter: true,
        ) +
        r'''
after=$(snapshot) || fail QUALIFICATION_REQUIRED
[ "$before" = "$after" ] || fail PLAN_STALE
text afterManifest "$after"
''';
  }

  DirectAptIndexRead capture(
    DirectSshOutput output, {
    required DirectAptReleaseRead release,
  }) {
    final rows = output.textRows({
      'manifest',
      'afterManifest',
      'decodedHash',
      'decodedSize',
      'packages',
    });
    final files = _files.capture(rows['manifest']!, rows['afterManifest']!);
    final hashMatch = RegExp(r'^([a-f0-9]{64})  -\n$')
        .firstMatch(rows['decodedHash']!);
    final sizeText = rows['decodedSize']!;
    if (hashMatch == null ||
        !RegExp(r'^(0|[1-9][0-9]{0,8})\n$').hasMatch(sizeText))
      _bad();
    final size = int.tryParse(sizeText.trim());
    if (size == null || size < 1 || size > 512 * 1024 * 1024) _limit();
    final hash = hashMatch[1]!;
    if (!release.release.matchesIndex(target.metaKey, hash, size)) _bad();
    final stanzas = DirectAptDeb822.parse(
      rows['packages']!,
      maximumStanzas: 256,
    );
    final expected = {for (final p in packages) p.identity: p};
    final archives = <String, DirectAptArchive>{};
    for (final row in stanzas) {
      final key = DirectAptPackageKey(
        row['package'] ?? '',
        row['architecture'] ?? '',
        row['version'] ?? '',
      );
      if (!expected.containsKey(key.identity) ||
          archives.containsKey(key.identity))
        _bad();
      final sha = row['sha256'],
          filename = row['filename'],
          sizeText = row['size'];
      if (sha == null ||
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha) ||
          filename == null ||
          filename.length > 1024 ||
          !RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._%+:~/-]*\.deb$')
              .hasMatch(filename) ||
          Uri.tryParse(filename)?.hasScheme != false ||
          filename.split('/').any((p) => p.isEmpty || p == '.' || p == '..') ||
          sizeText == null ||
          !RegExp(r'^[1-9][0-9]{0,9}$').hasMatch(sizeText))
        _bad();
      final archiveSize = int.tryParse(sizeText);
      if (archiveSize == null || archiveSize > 8 * 1024 * 1024 * 1024) _limit();
      final multiArch = row['multi-arch'] ?? 'none';
      if (!const {
        'none',
        'no',
        'same',
        'foreign',
        'allowed',
      }.contains(multiArch))
        _bad();
      archives[key.identity] = DirectAptArchive._(
        key,
        sha.toLowerCase(),
        archiveSize,
        filename,
        multiArch == 'no' ? 'none' : multiArch,
      );
    }
    return DirectAptIndexRead._(
      files,
      hash,
      size,
      release.release.payloadDigest,
      Map.unmodifiable(archives),
    );
  }

  @override
  String toString() => 'DirectAptIndexRequest';
}

/// Signed-index archive facts only, not resolver closure, source/Signed-By
/// qualification, a supported maintainer-script variant or an install permit.
final class DirectAptArchive {
  DirectAptArchive._(
    this.package,
    this.sha256,
    this.size,
    this.filename,
    this.multiArch,
  );
  final DirectAptPackageKey package;
  final String sha256, filename;

  /// Retained privately for exact dpkg binary-name/post-install snapshots.
  final String multiArch;
  final int size;
  Map<String, Object?> toPin() => Map.unmodifiable({
    'name': package.name,
    'architecture': package.architecture,
    'version': package.version,
    'sha256': sha256,
  });
  @override
  String toString() => 'DirectAptArchive';
}

final class DirectAptIndexRead {
  DirectAptIndexRead._(
    this.files,
    this.sha256,
    this.size,
    this.releasePayloadDigest,
    this.archives,
  );
  final DirectAptFileSnapshot files;
  final String sha256, releasePayloadDigest;
  final int size;
  final Map<String, DirectAptArchive> archives;
  @override
  String toString() => 'DirectAptIndexRead';
}
