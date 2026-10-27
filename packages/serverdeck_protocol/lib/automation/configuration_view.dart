import '../codec.dart';
import '../mcp/wire.dart';
import '../validation.dart';
import 'models.dart';
import 'values.dart';

/// Public comparison data only. Capturing it neither proves a remote fact nor
/// authorizes a repair. Observed text keeps its original Unicode normalization.
Map<String, Object?> captureConfigurationView(Map<String, Object?> value) {
  final copy = StrictCodec().decode(
    encodeMcpMessage(value, maxBytes: 512 * 1024),
    maxBytes: 512 * 1024,
  );
  requireFields(copy, {
    'serverId',
    'observation',
    'desired',
    'expected',
    'comparison',
  });
  final server = requireUuid(copy['serverId']);
  final observation = ManagedResourceObservationRecord.fromTrustedJson(
    _object(copy['observation']),
  );
  if (observation.serverId != server) _bad();
  final raw = copy['desired'];
  final desired = raw == null
      ? null
      : AutomationDesiredStateRecord.fromJson(_object(raw));
  if (desired != null &&
      (desired.serverId != server ||
          desired.workspaceId != observation.workspaceId ||
          desired.resourceId != observation.resourceId))
    _bad();
  final comparison = _object(copy['comparison']);
  requireFields(comparison, {
    'status',
    'basis',
    'reason',
    'observedAt',
    'confirmedAt',
    'comparedAt',
    'differences',
  });
  final status = comparison['status'],
      basis = comparison['basis'],
      reason = comparison['reason'];
  if (!const {
        'unmanaged',
        'unknown',
        'stale',
        'matched',
        'drift',
      }.contains(status) ||
      !const {'none', 'file', 'service', 'recipe'}.contains(basis) ||
      !const {
        'none',
        'no-desired',
        'observation-unavailable',
        'stale-observation',
        'target-changed',
        'recipe-evidence',
      }.contains(reason))
    _bad();
  final at = automationTimestamp(comparison['comparedAt']);
  final observedAt = nullableAutomationTimestamp(comparison['observedAt']);
  final confirmedAt = nullableAutomationTimestamp(comparison['confirmedAt']);
  final known = const {'known', 'stale'}.contains(observation.status);
  if (known ? observedAt != observation.observedAt : observedAt != null) _bad();
  final differences = comparison['differences'];
  if (differences is! List || differences.length > 8) _bad();
  final fields = <String>{};
  for (final raw in differences) {
    final row = _object(raw);
    requireFields(row, {'field', 'desired', 'observed'});
    if (row['field'] is! String ||
        !const {
          'exists',
          'fileDigest',
          'text',
          'activeState',
          'unitFileState',
          'max_connections',
          'shared_buffers_mb',
          'max_server_memory_usage_mb',
        }.contains(row['field']) ||
        !fields.add(row['field'] as String))
      _bad();
    for (final item in [row['desired'], row['observed']]) {
      if (item != null && item is! bool && item is! int && item is! String)
        _bad();
    }
  }
  if (desired == null) {
    if (copy['expected'] != null ||
        status != 'unmanaged' ||
        basis != 'none' ||
        reason != 'no-desired' ||
        confirmedAt != null ||
        differences.isNotEmpty)
      _bad();
  } else {
    if (confirmedAt == null || basis == 'none' || status == 'unmanaged') _bad();
    final expected = _object(copy['expected']);
    switch (expected['kind']) {
      case 'config_file':
        requireFields(expected, {'kind', 'fileDigest', 'values'});
        _digest(expected['fileDigest']);
        if (basis != 'file' || observation.resourceId.endsWith('.service'))
          _bad();
        final values = _object(expected['values']);
        if (observation.resourceId == 'system.motd') {
          requireFields(values, {'text'});
          if (values['text'] is! String ||
              (values['text'] as String).runes.length > 4097)
            _bad();
        } else {
          final fields = observation.resourceId == 'postgresql.settings'
              ? {'max_connections', 'shared_buffers_mb'}
              : {'max_connections', 'max_server_memory_usage_mb'};
          requireFields(values, fields);
          if (values.values.any((item) => item is! int)) _bad();
        }
      case 'service':
        requireFields(expected, {'kind', 'activeState', 'unitFileState'});
        if (basis != 'service' ||
            !observation.resourceId.endsWith('.service') ||
            !const {
              null,
              'active',
              'inactive',
            }.contains(expected['activeState']) ||
            !const {
              null,
              'enabled',
              'disabled',
            }.contains(expected['unitFileState']) ||
            expected['activeState'] == null &&
                expected['unitFileState'] == null)
          _bad();
      case 'recipe':
        requireFields(expected, {'kind', 'id', 'version', 'recipeDigest'});
        if (basis != 'recipe' ||
            !const {'postgresql16', 'clickhouse'}.contains(expected['id']))
          _bad();
        automationText(expected['version'], min: 1, max: 256);
        _digest(expected['recipeDigest']);
      default:
        _bad();
    }
    if (const {'matched', 'drift'}.contains(status)) {
      if (reason != 'none' ||
          !observation.isFreshAt(at) ||
          basis == 'recipe' ||
          (status == 'matched' ? differences.isNotEmpty : differences.isEmpty))
        _bad();
    } else if (differences.isNotEmpty ||
        reason == 'none' ||
        reason == 'no-desired') {
      _bad();
    }
  }
  return _freeze(copy) as Map<String, Object?>;
}

Never _bad() => throw const FormatException('VALIDATION');
Map<String, Object?> _object(Object? value) =>
    value is Map<String, Object?> ? value : _bad();
void _digest(Object? value) {
  if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) _bad();
}

Object? _freeze(Object? value) => switch (value) {
  Map<String, Object?> value => Map<String, Object?>.unmodifiable({
    for (final entry in value.entries) entry.key: _freeze(entry.value),
  }),
  List value => List<Object?>.unmodifiable(value.map(_freeze)),
  _ => value,
};
