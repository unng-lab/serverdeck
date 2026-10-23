import 'codec.dart';
import 'automation/configuration_view.dart';
import 'connections.dart';
import 'executor_enrollment.dart';
import 'executor_recipes.dart';
import 'host_trust.dart' show TrustedLocalError;
import 'mcp/operations.dart' show mcpDomainCodes;
import 'validation.dart';

const remoteReadOwnerMethods = {
  'servers.state',
  'servers.logs',
  'servers.configuration',
  'servers.executorInspect',
  'servers.recipes',
  'servers.readStatus',
  'servers.readCancel',
};

Never _bad() => throw const FormatException('VALIDATION');
Map<String, Object?> _object(Object? value) =>
    value is Map<String, Object?> ? value : _bad();
void _boolean(Object? value) {
  if (value is! bool) _bad();
}

void _count(Object? value, [int maximum = 0x7fffffffffffffff]) {
  if (value is! int || value < 0 || value > maximum) _bad();
}

void _time(Object? value, {bool nullable = false}) {
  if (value == null && nullable) return;
  if (value is! String || value.length > 64 || !value.endsWith('Z')) _bad();
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) _bad();
}

void _quality(Object? value) {
  if (!const {
    'known',
    'stale',
    'unknown',
    'unsupported',
    'denied',
    'incomplete',
    'error',
  }.contains(value))
    _bad();
}

Object? _freeze(Object? value) => switch (value) {
  Map<String, Object?>() => Map<String, Object?>.unmodifiable({
    for (final entry in value.entries) entry.key: _freeze(entry.value),
  }),
  List() => List<Object?>.unmodifiable(value.map(_freeze)),
  _ => value,
};

void _identity(Object? value, String server) {
  final identity = ConnectionIdentity.fromJson(_object(value));
  if (identity.profileId != server) _bad();
}

void _observation(Object? raw, String source) {
  final value = _object(raw);
  requireFields(
    value,
    {'source', 'observedAt', 'receivedAt', 'quality', 'value'},
    {'code', 'truncated', 'stale', 'parseErrors'},
  );
  final actualSource = switch (source) {
    'system' => 'ssh:os-release/uname/proc',
    'metrics' => 'ssh:proc/stat+meminfo+net/dev+df',
    'packages' => 'ssh:dpkg-query',
    'units' => 'ssh:systemctl',
    _ => _bad(),
  };
  if (value['source'] != 'ssh:$source' && value['source'] != actualSource)
    _bad();
  _quality(value['quality']);
  _time(value['observedAt'], nullable: true);
  _time(value['receivedAt']);
  if (value.containsKey('code') &&
      !TrustedLocalError.codes.contains(value['code']))
    _bad();
  for (final key in ['truncated', 'stale']) {
    if (value.containsKey(key)) _boolean(value[key]);
  }
  // Source payloads are bounded untrusted display data, never execution input.
  final payload = value['value'];
  if (payload != null) {
    if (source == 'packages' || source == 'units') {
      if (payload is! List || payload.length > 2048) _bad();
      for (final row in payload) {
        _object(row);
      }
    } else if (payload is! Map<String, Object?>) {
      _bad();
    }
  }
  if (value.containsKey('parseErrors')) _count(value['parseErrors']);
}

Map<String, Object?> captureRemoteReadPayload(
  String kind,
  Map<String, Object?> value,
) {
  StrictCodec().encode(value, maxBytes: 2 * 1024 * 1024);
  final server = requireUuid(value['serverId']);
  switch (kind) {
    case 'recipes':
      requireFields(value, {'serverId', 'catalog'});
      captureExecutorRecipes(_object(value['catalog']));
    case 'state':
      requireFields(value, {
        'serverId',
        'identity',
        'connection',
        'system',
        'metrics',
        'packages',
        'units',
        'history',
        'cacheDropped',
      });
      if (value['identity'] != null) _identity(value['identity'], server);
      final connection = ConnectionSnapshot.fromJson(
        _object(value['connection']),
      );
      if (connection.profileId != server) _bad();
      for (final source in ['system', 'metrics', 'packages', 'units']) {
        _observation(value[source], source);
      }
      _boolean(value['cacheDropped']);
      final history = value['history'];
      if (history is! List || history.length > 120) _bad();
      for (final point in history) {
        final row = _object(point);
        _time(row['receivedAt']);
      }
    case 'logs':
      requireFields(
        value,
        {
          'serverId',
          'identity',
          'source',
          'timezone',
          'observedAt',
          'quality',
          'records',
          'gaps',
          'dropped',
          'duplicates',
          'parseErrors',
          'truncated',
        },
        {'nextCursor'},
      );
      _identity(value['identity'], server);
      if (value['source'] != 'journald' || value['timezone'] != 'UTC') _bad();
      _quality(value['quality']);
      _time(value['observedAt']);
      for (final key in ['gaps', 'truncated']) {
        _boolean(value[key]);
      }
      for (final key in ['dropped', 'duplicates', 'parseErrors']) {
        _count(value[key]);
      }
      final records = value['records'];
      if (records is! List || records.length > 1000) _bad();
      for (final record in records) {
        final row = _object(record);
        _time(row['timestamp']);
        if (row['message'] is! String || row['cursor'] is! String) _bad();
      }
      if (value.containsKey('nextCursor') &&
          (value['nextCursor'] is! String ||
              (value['nextCursor'] as String).length > 256))
        _bad();
    case 'executorInspect':
      requireFields(value, {
        'serverId',
        'challengeId',
        'expiresAt',
        'enrollment',
      });
      requireUuid(value['challengeId']);
      _time(value['expiresAt']);
      final enrollment = ExecutorEnrollment.fromJson(
        _object(value['enrollment']),
      );
      if (enrollment.serverId != server) _bad();
    case 'configuration':
      // Managed configuration has its own exact observation parser. The owner
      // adapter must add the server field and never send arbitrary file bytes.
      captureConfigurationView(value);
    default:
      _bad();
  }
  return _freeze(value) as Map<String, Object?>;
}

Map<String, Object?> captureRemoteReadResult(
  String method,
  Map<String, Object?> value,
) {
  if (!remoteReadOwnerMethods.contains(method))
    throw const FormatException('UNSUPPORTED');
  StrictCodec().encode(value, maxBytes: 2 * 1024 * 1024 + 4096);
  requireUuid(value['operationId']);
  if (method == 'servers.readCancel') {
    requireFields(value, {'operationId', 'cancelled'});
    _boolean(value['cancelled']);
  } else {
    switch (value['state']) {
      case 'running':
        requireFields(value, {'operationId', 'state'});
      case 'succeeded' when method == 'servers.readStatus':
        requireFields(value, {'operationId', 'state', 'kind', 'result'});
        if (value['kind'] is! String) _bad();
        captureRemoteReadPayload(
          value['kind'] as String,
          _object(value['result']),
        );
      case 'failed' when method == 'servers.readStatus':
        requireFields(value, {'operationId', 'state', 'code'});
        if (!mcpDomainCodes.contains(value['code']) &&
            !TrustedLocalError.codes.contains(value['code']))
          _bad();
      default:
        _bad();
    }
  }
  return _freeze(value) as Map<String, Object?>;
}
