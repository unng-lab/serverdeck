import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/direct_ssh_runtime.dart';

import '../storage/models.dart';
import 'direct_ssh.dart';

String directObservationFailureStatus(String code) => switch (code) {
  'FORBIDDEN' => 'denied',
  'PREREQUISITE_UNAVAILABLE' ||
  'QUALIFICATION_REQUIRED' ||
  'UNSUPPORTED' => 'unsupported',
  'RESOURCE_LIMIT' => 'incomplete',
  _ => 'error',
};

String _hash(Object? value) => const DartSha256()
    .hashSync(StrictCodec().canonical(value))
    .bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();
String _fileHash(String value) => const DartSha256()
    .hashSync(utf8.encode(value))
    .bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();
Never _bad() => throw DirectSshFailure('UNKNOWN_OUTCOME');
Never _unsupported() => throw const FormatException('UNSUPPORTED');

/// Captured native metadata tuple, not authorization or resource qualification.
/// Raw public observations must never stand in for provenance/SQL/process proof
/// when a planner or effect driver decides whether DB writes are allowed.
final class DirectObservationTarget {
  DirectObservationTarget._(this._fields);
  factory DirectObservationTarget.capture(
    WorkspaceState state,
    String serverId,
  ) {
    final profile = state.profiles[serverId];
    if (profile == null) throw StateError('TRUST_CHANGED');
    return DirectObservationTarget._(
      Map.unmodifiable({
        'workspaceId': state.workspaceId,
        'serverId': profile.id,
        'targetRevision': profile.revision,
        'connectionRevision': profile.connectionRevision,
        'accessRevision': profile.credentialRevision,
        'trustRevision': profile.trustRevision,
      }),
    );
  }
  final Map<String, Object?> _fields;
  String get serverId => _fields['serverId'] as String;
  Map<String, Object?> toJson() => {..._fields};
  bool matches(WorkspaceState state) {
    final profile = state.profiles[serverId];
    return state.workspaceId == _fields['workspaceId'] &&
        profile != null &&
        profile.revision == _fields['targetRevision'] &&
        profile.connectionRevision == _fields['connectionRevision'] &&
        profile.credentialRevision == _fields['accessRevision'] &&
        profile.trustRevision == _fields['trustRevision'];
  }

  ManagedResourceObservationRecord unavailable(
    String resource,
    String status,
    DateTime at, {
    DirectSshIdentity? identity,
  }) {
    if (!const {
      'unknown',
      'denied',
      'unsupported',
      'incomplete',
      'error',
    }.contains(status)) {
      throw const FormatException('VALIDATION');
    }
    return _record(resource, identity, at, status, null);
  }

  ManagedResourceObservationRecord _record(
    String resource,
    DirectSshIdentity? identity,
    DateTime at,
    String status,
    Map<String, Object?>? value,
  ) {
    final document = {
      ..._fields,
      'resourceId': resource,
      'hostId': identity?.hostId,
      'resourceRegistryDigest': DirectSshRuntime.registryDigest,
      'observedAt': at.toIso8601String(),
      'status': status,
      'value': value,
    };
    if (utf8.encode(jsonEncode(document)).length > 128 * 1024) {
      return _record(resource, identity, at, 'incomplete', null);
    }
    return ManagedResourceObservationRecord.fromTrustedJson(document);
  }

  ManagedResourceObservationRecord parse(
    String resource,
    DirectSshIdentity identity,
    DirectSshOutput output,
    DateTime at,
  ) {
    if (!managedResourceIds.contains(resource))
      throw const FormatException('VALIDATION');
    if (output.truncated || output.bytes.length > 128 * 1024) {
      return unavailable(resource, 'incomplete', at, identity: identity);
    }
    try {
      final value = resource.endsWith('.service')
          ? _service(output)
          : _file(resource, output);
      return _record(resource, identity, at, 'known', value);
    } on DirectSshFailure catch (error) {
      return unavailable(
        resource,
        directObservationFailureStatus(error.code),
        at,
        identity: identity,
      );
    } on FormatException {
      return unavailable(resource, 'unsupported', at, identity: identity);
    }
  }
}

const _paths = {
  'system.motd': '/etc/motd',
  'postgresql.settings': '/etc/postgresql/16/main/conf.d/serverdeck.conf',
  'clickhouse.settings': '/etc/clickhouse-server/config.d/serverdeck.xml',
};
const _footer = '\nSDSSH_FILE_COMPLETE_V1\n';

Map<String, Object?> _file(String resource, DirectSshOutput output) {
  final rows = output.textRows(const {
    'exists',
    'attributes',
    'afterAttributes',
    'digest',
    'file',
  });
  final path = _paths[resource]!;
  if (rows['exists'] == 'false') {
    if (rows['attributes'] != 'absent' ||
        rows['afterAttributes'] != 'absent' ||
        rows['digest'] != 'absent' ||
        rows['file'] != '')
      _bad();
    return {
      'exists': false,
      'fileDigest': null,
      'baselineDigest': _hash({'path': path, 'attributes': 'absent'}),
      'values': null,
    };
  }
  if (rows['exists'] != 'true' || rows['attributes'] != rows['afterAttributes'])
    _bad();
  final attributes = rows['attributes']!;
  final parsed = RegExp(
    r'^([0-9]{1,10}):([0-9]{1,10}):([0-7]{3,4}):([0-9]{1,10}):([0-9]{1,5}):([0-9]{1,20}):([0-9]{1,20}):([\x20-\x7e]{1,512})$',
  ).firstMatch(attributes);
  if (parsed == null) _bad();
  for (final field in [1, 2, 4, 5, 6, 7]) {
    final raw = parsed[field]!;
    if (raw.length > 1 && raw.startsWith('0')) _bad();
    if (BigInt.parse(raw) > BigInt.parse('18446744073709551615')) _bad();
  }
  final size = int.parse(parsed[5]!);
  if (parsed[1] != '0' ||
      parsed[4] != '1' ||
      BigInt.parse(parsed[2]!) > BigInt.from(4294967295) ||
      parsed[3] != (resource == 'postgresql.settings' ? '640' : '644') ||
      resource != 'postgresql.settings' && parsed[2] != '0') {
    throw DirectSshFailure('QUALIFICATION_REQUIRED');
  }
  final envelope = rows['file']!;
  if (!envelope.endsWith(_footer)) _bad();
  final content = envelope.substring(0, envelope.length - _footer.length);
  final bytes = utf8.encode(content);
  if (bytes.length > 65536) throw DirectSshFailure('RESOURCE_LIMIT');
  if (size != bytes.length) _bad();
  final digest = _fileHash(content);
  if (rows['digest'] != digest + '  ' + path) _bad();
  final Map<String, Object?> values;
  if (resource == 'system.motd') {
    values = {'text': content};
  } else if (resource == 'postgresql.settings') {
    final match = RegExp(
      r"^max_connections = ([0-9]{1,10})\nshared_buffers = '([0-9]{1,10})MB'\n$",
    ).firstMatch(content);
    if (match == null || match.end != content.length) _unsupported();
    if ([
      match[1]!,
      match[2]!,
    ].any((value) => value.length > 1 && value.startsWith('0')))
      _unsupported();
    values = {
      'max_connections': int.parse(match[1]!),
      'shared_buffers_mb': int.parse(match[2]!),
    };
  } else {
    final match = RegExp(
      r'^<clickhouse>\n  <max_connections>([0-9]{1,10})</max_connections>\n  <max_server_memory_usage>([0-9]{1,18})</max_server_memory_usage>\n</clickhouse>\n$',
    ).firstMatch(content);
    if (match == null || match.end != content.length) _unsupported();
    if ([
      match[1]!,
      match[2]!,
    ].any((value) => value.length > 1 && value.startsWith('0')))
      _unsupported();
    final memory = BigInt.parse(match[2]!);
    if (memory % BigInt.from(1048576) != BigInt.zero ||
        memory > BigInt.from(9223372036854775807))
      _unsupported();
    values = {
      'max_connections': int.parse(match[1]!),
      'max_server_memory_usage_mb': (memory ~/ BigInt.from(1048576)).toInt(),
    };
  }
  return {
    'exists': true,
    'fileDigest': digest,
    'baselineDigest': _hash({'path': path, 'attributes': attributes}),
    'values': values,
  };
}

Map<String, Object?> _service(DirectSshOutput output) {
  final data = output.textRows(const {'unit'})['unit']!;
  final fields = <String, String>{};
  const expected = {
    'LoadState',
    'ActiveState',
    'UnitFileState',
    'MainPID',
    'ControlPID',
    'ExecMainStartTimestampMonotonic',
    'ControlGroup',
    'FragmentPath',
  };
  if (data.length > 16 * 1024) _bad();
  for (final line in data.split('\n')) {
    final separator = line.indexOf('=');
    if (separator <= 0) _bad();
    final key = line.substring(0, separator),
        value = line.substring(separator + 1);
    if (!expected.contains(key) ||
        fields.containsKey(key) ||
        value.length > 1024 ||
        value.codeUnits.any((unit) => unit < 32 || unit > 126))
      _bad();
    fields[key] = value;
  }
  if (fields.length != expected.length) _bad();
  if (fields['LoadState'] != 'loaded') _unsupported();
  int integer(String key, int maximum) {
    final value = fields[key]!;
    if (!RegExp(r'^(?:0|[1-9][0-9]{0,18})$').hasMatch(value)) _bad();
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 0 || parsed > maximum) _bad();
    return parsed;
  }

  final pid = integer('MainPID', 2147483647);
  integer('ControlPID', 2147483647);
  final started = integer(
    'ExecMainStartTimestampMonotonic',
    9223372036854775807,
  );
  return {
    'activeState': fields['ActiveState'],
    'unitFileState': fields['UnitFileState'],
    'mainPid': pid,
    'startMonotonicUs': started.toString(),
    'baselineDigest': _hash(fields),
  };
}
