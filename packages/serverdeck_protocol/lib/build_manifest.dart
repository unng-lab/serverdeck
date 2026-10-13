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
