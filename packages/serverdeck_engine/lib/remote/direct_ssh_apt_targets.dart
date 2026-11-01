import 'direct_ssh.dart';
import 'direct_ssh_apt_metadata.dart';

Never _bad() => throw DirectSshFailure('QUALIFICATION_REQUIRED');

/// Discovery only: APT's Trusted field can be overridden by a source entry and
/// is deliberately not treated as signature evidence. All URI/source values
/// remain private; the public catalog must project only qualified descriptors.
final class DirectAptIndexTarget {
  DirectAptIndexTarget._(
    this.filename,
    this.metaKey,
    this.repositoryUri,
    this.baseUri,
    this.architecture,
    this.aptTrusted,
    this.sourceFile,
    this.sourcePosition,
  );

  final String filename, metaKey;
  final String repositoryUri, baseUri;
  final String? architecture;
  final bool aptTrusted;
  final String sourceFile;

  /// One-based line for .list, stanza ordinal for .sources (APT2.7 semantics).
  final int sourcePosition;

  static List<DirectAptIndexTarget> capture(DirectSshOutput output) {
    final rows = output.textRows({'targets'});
    final stanzas = DirectAptDeb822.parse(rows['targets']!, maximumStanzas: 64);
    final result = <DirectAptIndexTarget>[], files = <String>{};
    for (final stanza in stanzas) {
      final file = stanza['filename'], meta = stanza['metakey'];
      final arch = stanza['architecture'], trusted = stanza['trusted'];
      final repo = stanza['repo-uri'], base = stanza['base-uri'];
      final reference = RegExp(r'^(.+):([1-9][0-9]{0,6})$')
          .firstMatch(stanza['sourcesentry'] ?? '');
      if (reference == null || !isDirectAptSourcePath(reference[1]!)) _bad();
      if (stanza['identifier'] != 'Packages' ||
          file == null ||
          !file.startsWith('/var/lib/apt/lists/') ||
          !RegExp(r'^[a-zA-Z0-9_:%][a-zA-Z0-9._%+:~-]{0,239}$')
              .hasMatch(file.substring('/var/lib/apt/lists/'.length)) ||
          !files.add(file) ||
          meta == null ||
          meta.length > 1024 ||
          !RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._+~/-]*$').hasMatch(meta) ||
          meta
              .split('/')
              .any((part) => part.isEmpty || part == '.' || part == '..') ||
          (meta != 'Packages' && !meta.endsWith('/Packages')) ||
          arch != null && arch != 'amd64' && arch != 'all' ||
          trusted != 'yes' && trusted != 'no')
        _bad();
      for (final uri in [repo, base]) {
        if (uri == null ||
            uri.length > 4096 ||
            uri.isEmpty ||
            RegExp(r'\s').hasMatch(uri))
          _bad();
        final parsed = Uri.tryParse(uri);
        if (parsed == null ||
            !parsed.hasScheme ||
            parsed.hasFragment ||
            !uri.endsWith('/'))
          _bad();
      }
      result.add(
        DirectAptIndexTarget._(
          file,
          meta,
          repo!,
          base!,
          arch,
          trusted == 'yes',
          reference[1]!,
          int.parse(reference[2]!),
        ),
      );
    }
    return List.unmodifiable(result);
  }

  @override
  String toString() => 'DirectAptIndexTarget';
}

bool isDirectAptSourcePath(String path) =>
    path == '/etc/apt/sources.list' ||
    RegExp(
      r'^/etc/apt/sources\.list\.d/[a-zA-Z0-9_-][a-zA-Z0-9_.-]{0,233}\.(list|sources)$',
    ).hasMatch(path);

/// Fixed, read-only libapt discovery. The -c stream is parsed after APT's
/// initial configuration load and before pkgInitSystem/command dispatch. Reset
/// operational namespaces so host hooks, compressor commands, alternate roots
/// and cache destinations cannot select programs or writes for this command.
/// Existing source entries and preferences stay at their stock host locations.
/// A malformed initial host configuration fails closed; no repair is attempted.
abstract final class DirectAptTargetsCommand {
  static const executables = [
    '/usr/bin/base64',
    '/usr/bin/env',
    '/usr/bin/bash',
    '/usr/bin/timeout',
    '/usr/bin/apt-get',
  ];

  static const configuration = r'''
#clear APT;
#clear Apt-Helper;
#clear AptCli;
#clear Acquire;
#clear Binary;
#clear Debug;
#clear Dir;
#clear DPkg;
#clear DSelect;
#clear OrderList;
#clear pkgCacheGen;
#clear pkgCacheFile;
#clear pkgPolicy;
#clear RootDir;
#clear quiet;
#clear help;
#clear version;
Dir "/";
Dir::Etc "/etc/apt";
Dir::Etc::sourcelist "/etc/apt/sources.list";
Dir::Etc::sourceparts "/etc/apt/sources.list.d";
Dir::Etc::preferences "/etc/apt/preferences";
Dir::Etc::preferencesparts "/etc/apt/preferences.d";
Dir::Etc::trusted "/etc/apt/trusted.gpg";
Dir::Etc::trustedparts "/etc/apt/trusted.gpg.d";
Dir::State "/var/lib/apt";
Dir::State::status "/var/lib/dpkg/status";
Dir::State::lists "/var/lib/apt/lists";
Dir::State::extended_states "/var/lib/apt/extended_states";
Dir::Cache::pkgcache "";
Dir::Cache::srcpkgcache "";
Dir::Log "/dev/null";
Dir::Bin::dpkg "/usr/bin/dpkg";
APT::Architecture "amd64";
APT::Architectures { "amd64"; };
APT::Cache-Start "25165824";
APT::Cache-Limit "536870912";
APT::Get::IndexTargets::ReleaseInfo "true";
APT::Get::IndexTargets::Format "";
Acquire::Languages "none";
Acquire::IndexTargets::deb::Packages {
  MetaKey "$(COMPONENT)/binary-$(ARCHITECTURE)/Packages";
  flatMetaKey "Packages";
  ShortDescription "Packages";
  Description "$(RELEASE)/$(COMPONENT) $(ARCHITECTURE) Packages";
  flatDescription "$(RELEASE) Packages";
  Optional "false";
};
Debug::NoLocking "true";
pkgCacheFile::Generate "true";
''';

  // printf supplies a pipe, never a temporary config file. APT_CONFIG cannot
  // serve this purpose: pkgInitConfig requires a regular file for that path.
  // -c uses ReadConfigFile/OpenConfigurationFileFd, which accepts the stream.
  static String get nativeBody =>
      """
printf 'targets\\t'
/usr/bin/env -i PATH=/usr/bin:/bin LC_ALL=C TZ=UTC0 HOME=/ /usr/bin/bash --noprofile --norc -o pipefail -c '
printf %s "\$1" | /usr/bin/timeout 25 /usr/bin/apt-get -c /dev/stdin indextargets "Identifier: Packages" 2>/dev/null | /usr/bin/base64 -w0
' sdssh-apt '$configuration' || { printf '\\n'; fail QUALIFICATION_REQUIRED; }
printf '\\n'
""";
}
