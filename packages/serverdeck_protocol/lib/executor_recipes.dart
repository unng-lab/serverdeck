import 'automation/plan_records.dart';
import 'codec.dart';
import 'validation.dart';

/// Bounded immutable catalog projection, not permission or a runnable plan.
Map<String, Object?> captureExecutorRecipes(Map<String, Object?> input) {
  final codec = StrictCodec();
  final value = codec.decode(
    codec.encode(input, maxBytes: 512 * 1024),
    maxBytes: 512 * 1024,
  );
  requireFields(value, {
    'hostId',
    'runtimeVersion',
    'registryDigest',
    'environment',
    'installEnabled',
    'recipes',
    'unavailable',
    'prerequisites',
  });
  requireUuid(value['hostId']);
  final version = value['runtimeVersion'], registry = value['registryDigest'];
  if (version is! String ||
      version.length > 100 ||
      !RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+\+[a-f0-9]{64}$').hasMatch(version) ||
      registry is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(registry) ||
      value['environment'] != 'ubuntu24.04-amd64-systemd' ||
      value['installEnabled'] is! bool)
    _bad();
  final recipes = value['recipes'], unavailable = value['unavailable'];
  if (recipes is! List ||
      recipes.length > 2 ||
      unavailable is! List ||
      unavailable.length > 2)
    _bad();
  final ids = <String>{}, missing = <String>{};
  for (final raw in recipes) {
    final recipe = QualifiedRecipeDescriptor.capture(_object(raw));
    if (!ids.add(recipe.id) || recipe.initialSettings == null) _bad();
  }
  for (final raw in unavailable) {
    final row = _object(raw);
    requireFields(row, {'id', 'code'});
    if (!const {'postgresql16', 'clickhouse'}.contains(row['id']) ||
        row['code'] != 'QUALIFICATION_REQUIRED' ||
        !missing.add(row['id'] as String))
      _bad();
  }
  final enabled = value['installEnabled'] == true;
  final expectedMissing = {
    'postgresql16',
    'clickhouse',
  }.difference(enabled ? ids : <String>{});
  if (enabled && ids.isEmpty ||
      missing.length != expectedMissing.length ||
      !missing.containsAll(expectedMissing))
    _bad();
  final prerequisites = _object(value['prerequisites']);
  requireFields(prerequisites, {
    'requiresFreshInstall',
    'requiresPreflight',
    'metadataRefresh',
  });
  if (prerequisites['requiresFreshInstall'] != true ||
      prerequisites['requiresPreflight'] != true ||
      prerequisites['metadataRefresh'] != false)
    _bad();
  return _freeze(value) as Map<String, Object?>;
}

Never _bad() => throw const FormatException('VALIDATION');
Map<String, Object?> _object(Object? value) =>
    value is Map<String, Object?> ? value : _bad();
Object? _freeze(Object? value) => switch (value) {
  Map<String, Object?>() => Map<String, Object?>.unmodifiable({
    for (final row in value.entries) row.key: _freeze(row.value),
  }),
  List() => List<Object?>.unmodifiable(value.map(_freeze)),
  _ => value,
};
