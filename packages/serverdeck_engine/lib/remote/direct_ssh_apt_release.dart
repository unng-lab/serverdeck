import 'direct_ssh.dart';
import 'direct_ssh_apt_metadata.dart';
import 'direct_ssh_apt_files.dart';

Never _bad() => throw DirectSshFailure('QUALIFICATION_REQUIRED');
Never _limit() => throw DirectSshFailure('RESOURCE_LIMIT');

/// Closed read request, not caller-provided shell or evidence of APT trust.
/// Source/Signed-By selection and binding the index contents remain the
/// catalog collector's responsibility. Only existing binary keyrings are used.
final class DirectAptReleaseRequest {
  DirectAptReleaseRequest._(this.releasePath, this.keyrings, this._files);

  factory DirectAptReleaseRequest({
    required String releasePath,
    required List<String> keyrings,
  }) {
    if (!_path(releasePath, '/var/lib/apt/lists/', '_InRelease')) _bad();
    if (keyrings.isEmpty) _bad();
    if (keyrings.length > 16) _limit();
    final keys = keyrings.toSet().toList()..sort();
    if (keys.length != keyrings.length) _bad();
    for (final key in keys) {
      if (key != '/etc/apt/trusted.gpg' &&
          !const [
            '/etc/apt/keyrings/',
            '/etc/apt/trusted.gpg.d/',
            '/usr/share/keyrings/',
          ].any((root) => _path(key, root, '.gpg')))
        _bad();
    }
    return DirectAptReleaseRequest._(
      releasePath,
      List.unmodifiable(keys),
      DirectAptFileSet({
        releasePath: 4 * 1024 * 1024,
        for (final key in keys) key: 2 * 1024 * 1024,
      }),
    );
  }

  static bool _path(String path, String root, String suffix) {
    if (!path.startsWith(root)) return false;
    final name = path.substring(root.length);
    return name.length <= 240 &&
        RegExp(r'^[a-zA-Z0-9_:%][a-zA-Z0-9._%+:~-]*$').hasMatch(name) &&
        name.endsWith(suffix);
  }

  final String releasePath;
  final List<String> keyrings;
  final DirectAptFileSet _files;

  static const executables = [
    '/usr/bin/base64',
    '/usr/bin/stat',
    '/usr/bin/sha256sum',
    '/usr/bin/timeout',
    '/usr/bin/env',
    '/usr/bin/bash',
    '/usr/bin/gpgv',
  ];

  /// Consumed only by the closed DirectSshCommand factory. No file is created,
  /// no key is imported and no APT/native package-manager operation is started.
  String get nativeBody {
    final keyArgs = keyrings.map((path) => "--keyring '$path'").join(' ');
    // Signature-only first pass must omit --output entirely: enabling it
    // makes GnuPG emit PLAINTEXT records even for /dev/null. The second pass
    // requests stdout only, with no status stream mixed into the payload.
    final verify =
        '/usr/bin/env -i PATH=/usr/bin:/bin LC_ALL=C TZ=UTC0 HOME=/ '
            '/usr/bin/bash --noprofile --norc -o pipefail -c '
            "'/usr/bin/timeout 10 /usr/bin/gpgv --homedir / --weak-digest SHA1 "
            r'"$@" 2>/dev/null | /usr/bin/base64 -w0'
            "' sdssh-apt " +
        keyArgs;
    return _files.nativeDefinition +
        r'''
before=$(snapshot) || fail QUALIFICATION_REQUIRED
text manifest "$before"
printf 'status\t'
''' +
        verify +
        " --status-fd 1 '$releasePath' || { printf '\\n'; fail QUALIFICATION_REQUIRED; }\n" +
        r'''printf '\n'
printf 'payload\t'
''' +
        verify +
        " --output - '$releasePath' || { printf '\\n'; fail QUALIFICATION_REQUIRED; }\n" +
        r'''printf '\n'
after=$(snapshot) || fail QUALIFICATION_REQUIRED
[ "$before" = "$after" ] || fail PLAN_STALE
text afterManifest "$after"
''';
  }

  /// Captures only a completed result of this exact request. The result still
  /// does not certify source selection, Packages contents or an install recipe.
  DirectAptReleaseRead capture(
    DirectSshOutput output, {
    required DateTime now,
    Set<String> allowedFingerprints = const {},
  }) {
    if (output.bytes.length > 8 * 1024 * 1024) _limit();
    final rows = output.textRows({
      'manifest',
      'afterManifest',
      'status',
      'payload',
    });
    final snapshot = _files.capture(rows['manifest']!, rows['afterManifest']!);
    final status = rows['status']!, payload = rows['payload']!;
    final signatures = DirectAptSignatureFields.parse(
      status,
      now: now,
      allowedFingerprints: allowedFingerprints,
    );
    final release = DirectAptReleaseFields.parse(payload, now: now);
    return DirectAptReleaseRead._(release, signatures, snapshot.digests);
  }

  @override
  String toString() => 'DirectAptReleaseRequest';
}

/// Native verification evidence for one stable Release/keyring snapshot only.
/// Never a qualified candidate, package provenance or permission to install.
final class DirectAptReleaseRead {
  DirectAptReleaseRead._(this.release, this.signatures, this.fileDigests);
  final DirectAptReleaseFields release;
  final DirectAptSignatureFields signatures;
  final Map<String, String> fileDigests;
  @override
  String toString() => 'DirectAptReleaseRead';
}
