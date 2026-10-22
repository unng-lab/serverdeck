/// Shared description of the verified development bundle, without file access.
class BuildManifest {
  factory BuildManifest.fromJson(Object? value, {bool testOnly = false}) {
    const fields = {
      'format',
      'buildId',
      'configuration',
      'testOnly',
      'appRoot',
      'sha256',
    };
    const files = {'serverdeck.exe', 'locald.exe', 'libisar.dll'};
    const invalid = FormatException('INVALID_BUILD_MANIFEST');
    if (value is! Map<String, Object?> ||
        value.length != fields.length ||
        !value.keys.toSet().containsAll(fields) ||
        value['format'] is! int ||
        value['format'] != 1 ||
        value['testOnly'] != testOnly)
      throw invalid;
    final buildId = value['buildId'];
    final configuration = value['configuration'];
    final appRoot = value['appRoot'];
    final hashes = value['sha256'];
    if (buildId is! String ||
        configuration is! String ||
        !{'Debug', 'Release'}.contains(configuration) ||
        !RegExp('^[0-9a-f]{40}\\+$configuration\\+[0-9a-f]{64}\$')
            .hasMatch(buildId) ||
        appRoot is! String ||
        appRoot.isEmpty ||
        appRoot.length > 32767 ||
        appRoot.contains('\u0000') ||
        hashes is! Map<String, Object?> ||
        hashes.length != files.length ||
        !hashes.keys.toSet().containsAll(files))
      throw invalid;
    final checked = <String, String>{};
    for (final name in files) {
      final hash = hashes[name];
      if (hash is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash))
        throw invalid;
      checked[name] = hash;
    }
    return BuildManifest._(
      buildId,
      configuration,
      testOnly,
      appRoot,
      Map.unmodifiable(checked),
    );
  }

  BuildManifest._(
    this.buildId,
    this.configuration,
    this.testOnly,
    this.appRoot,
    this.sha256,
  );
  final String buildId, configuration, appRoot;
  final bool testOnly;
  final Map<String, String> sha256;
}

/// Operational API1.1 bundle metadata. Deliberately separate from legacy format1
/// so the old role-less bootstrap cannot accidentally activate a new bundle.
class McpBuildManifest {
  factory McpBuildManifest.fromJson(Object? value, {bool testOnly = false}) {
    final fields = _OperationalBuildFields.fromJson(
      value,
      format: 2,
      schema: 2,
      testOnly: testOnly,
      invalidCode: 'INVALID_MCP_BUILD_MANIFEST',
    );
    return McpBuildManifest._(
      fields.buildId,
      fields.configuration,
      fields.testOnly,
      fields.appRoot,
      fields.sha256,
    );
  }

  McpBuildManifest._(
    this.buildId,
    this.configuration,
    this.testOnly,
    this.appRoot,
    this.sha256,
  );
  final String buildId, configuration, appRoot;
  final bool testOnly;
  final Map<String, String> sha256;
  int get apiMajor => 1;
  int get apiMinor => 1;
  int get workspaceSchema => 2;
}

/// Remote schema3 bundle metadata. Its explicit entry cannot create format2
/// metadata/proofs or silently select a new mode in older clients.
final class TrustedBuildManifest {
  factory TrustedBuildManifest.fromJson(
    Object? value, {
    bool testOnly = false,
  }) {
    final fields = _OperationalBuildFields.fromJson(
      value,
      format: 3,
      schema: 3,
      testOnly: testOnly,
      invalidCode: 'INVALID_TRUSTED_BUILD_MANIFEST',
    );
    return TrustedBuildManifest._(
      fields.buildId,
      fields.configuration,
      fields.testOnly,
      fields.appRoot,
      fields.sha256,
    );
  }
  TrustedBuildManifest._(
    this.buildId,
    this.configuration,
    this.testOnly,
    this.appRoot,
    this.sha256,
  );
  final String buildId, configuration, appRoot;
  final bool testOnly;
  final Map<String, String> sha256;
  int get apiMajor => 1;
  int get apiMinor => 1;
  int get workspaceSchema => 3;
}

// Shared closed-field validation; only the two explicit constructors above
// choose their constant format/schema. No input option selects a parser mode.
final class _OperationalBuildFields {
  factory _OperationalBuildFields.fromJson(
    Object? value, {
    required int format,
    required int schema,
    required bool testOnly,
    required String invalidCode,
  }) {
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
    const files = {'serverdeck.exe', 'locald.exe', 'mcp.exe', 'libisar.dll'};
    final invalid = FormatException(invalidCode);
    if (value is! Map<String, Object?> ||
        value.length != fields.length ||
        !value.keys.toSet().containsAll(fields) ||
        value['format'] is! int ||
        value['format'] != format ||
        value['product'] != 'serverdeck-next' ||
        value['apiMajor'] is! int ||
        value['apiMajor'] != 1 ||
        value['apiMinor'] is! int ||
        value['apiMinor'] != 1 ||
        value['workspaceSchema'] is! int ||
        value['workspaceSchema'] != schema ||
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
        !{'Debug', 'Release'}.contains(configuration) ||
        !RegExp('^[0-9a-f]{40}\\+$configuration\\+[0-9a-f]{64}\$')
            .hasMatch(buildId) ||
        appRoot is! String ||
        appRoot.isEmpty ||
        appRoot.length > 32767 ||
        appRoot.contains('\u0000') ||
        hashes is! Map<String, Object?> ||
        hashes.length != files.length ||
        !hashes.keys.toSet().containsAll(files)) {
      throw invalid;
    }
    final checked = <String, String>{};
    for (final name in files) {
      final hash = hashes[name];
      if (hash is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash))
        throw invalid;
      checked[name] = hash;
    }
    return _OperationalBuildFields._(
      buildId,
      configuration,
      testOnly,
      appRoot,
      Map.unmodifiable(checked),
    );
  }

  _OperationalBuildFields._(
    this.buildId,
    this.configuration,
    this.testOnly,
    this.appRoot,
    this.sha256,
  );
  final String buildId, configuration, appRoot;
  final bool testOnly;
  final Map<String, String> sha256;
}
