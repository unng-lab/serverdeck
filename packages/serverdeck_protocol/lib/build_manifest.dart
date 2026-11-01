import 'dart:convert';

import 'codec.dart';

/// The single-executable application bundle. Parsing metadata does not attest a
/// running process or grant an owner/MCP role. No older format is selected here.
final class EmbeddedBuildManifest {
  factory EmbeddedBuildManifest.fromJson(
    Object? value, {
    bool testOnly = false,
  }) {
    const invalid = FormatException('INVALID_EMBEDDED_BUILD_MANIFEST');
    const fields = {
      'format',
      'product',
      'buildId',
      'configuration',
      'testOnly',
      'appRoot',
      'apiMajor',
      'apiMinor',
      'workspaceSchema',
      'sha256',
    };
    if (value is! Map<String, Object?> ||
        value.length != fields.length ||
        !value.keys.toSet().containsAll(fields) ||
        value['format'] is! int ||
        value['format'] != 4 ||
        value['product'] != 'serverdeck-next' ||
        value['apiMajor'] is! int ||
        value['apiMajor'] != 1 ||
        value['apiMinor'] is! int ||
        value['apiMinor'] != 1 ||
        value['workspaceSchema'] is! int ||
        value['workspaceSchema'] != 3 ||
        value['testOnly'] is! bool ||
        value['testOnly'] != testOnly) {
      throw invalid;
    }
    final buildId = value['buildId'],
        configuration = value['configuration'],
        appRoot = value['appRoot'],
        hashes = value['sha256'];
    if (buildId is! String ||
        configuration is! String ||
        !const {'Debug', 'Release'}.contains(configuration) ||
        !RegExp('^[a-f0-9]{40}\\+$configuration\\+[a-f0-9]{64}\$')
            .hasMatch(buildId) ||
        appRoot is! String ||
        appRoot.isEmpty ||
        appRoot.length > 32767 ||
        appRoot.contains('\u0000') ||
        hashes is! Map<String, Object?>) {
      throw invalid;
    }
    final files = <String>{'serverdeck.exe', 'libisar.dll'};
    if (hashes.containsKey('executor-release.json'))
      files.add('executor-release.json');
    if (hashes.length != files.length ||
        !hashes.keys.toSet().containsAll(files))
      throw invalid;
    final checked = <String, String>{};
    for (final name in files) {
      final hash = hashes[name];
      if (hash is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash))
        throw invalid;
      checked[name] = hash;
    }
    try {
      StrictCodec().canonical(
        value,
      ); // Reject non-JSON values/malformed Unicode.
      if (utf8.encode(jsonEncode(value)).length > 16 * 1024) throw invalid;
    } on FormatException {
      throw invalid;
    }
    return EmbeddedBuildManifest._(
      buildId,
      configuration,
      testOnly,
      appRoot,
      Map.unmodifiable(checked),
    );
  }
  EmbeddedBuildManifest._(
    this.buildId,
    this.configuration,
    this.testOnly,
    this.appRoot,
    this.sha256,
  );
  final String buildId, configuration, appRoot;
  final bool testOnly;
  final Map<String, String> sha256;
  int get format => 4;
  int get apiMajor => 1;
  int get apiMinor => 1;
  int get workspaceSchema => 3;
  Map<String, Object?> toJson() => {
    'format': format,
    'product': 'serverdeck-next',
    'buildId': buildId,
    'configuration': configuration,
    'testOnly': testOnly,
    'appRoot': appRoot,
    'apiMajor': apiMajor,
    'apiMinor': apiMinor,
    'workspaceSchema': workspaceSchema,
    'sha256': Map<String, String>.of(sha256),
  };
}
