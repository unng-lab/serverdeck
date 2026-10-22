import 'dart:convert';
import 'dart:typed_data';

import 'codec.dart';
import 'errors.dart';
import 'models.dart';
import 'validation.dart';
import 'wire.dart' show validateMethodResult;
import 'mcp/readiness.dart';

enum SshTransportCode {
  VALIDATION_ERROR,
  RESOURCE_LIMIT,
  TRUST_CHANGED,
  AUTHENTICATION_FAILED,
  CONNECTION_FAILED,
  TIMEOUT,
  CANCELLED,
  SERVICE_UNAVAILABLE,
}

final class SshTransportFailure implements Exception {
  const SshTransportFailure(this.code);
  final SshTransportCode code;
  @override
  String toString() => 'SshTransportFailure(${code.name})';
}

Never _invalid() =>
    throw const SshTransportFailure(SshTransportCode.VALIDATION_ERROR);

final class SshHostPin {
  factory SshHostPin.fromJson(Map<String, Object?> value) {
    requireFields(value, {'format', 'fingerprint'});
    if (value['format'] is! String || value['fingerprint'] is! String) {
      _invalid();
    }
    return SshHostPin(
      value['format'] as String,
      value['fingerprint'] as String,
    );
  }
  factory SshHostPin(String format, String fingerprint) {
    if (!_formats.contains(format) ||
        !RegExp(r'^SHA256:[A-Za-z0-9+/]{43}$').hasMatch(fingerprint)) {
      _invalid();
    }
    try {
      final bytes = base64.decode('${fingerprint.substring(7)}=');
      if (bytes.length != 32 ||
          'SHA256:${base64.encode(bytes).replaceAll('=', '')}' != fingerprint) {
        _invalid();
      }
    } on FormatException {
      _invalid();
    }
    return SshHostPin._(format, fingerprint);
  }
  factory SshHostPin.fromCallback(String algorithm, Uint8List fingerprint) {
    try {
      final format = switch (algorithm) {
        'rsa-sha2-256' || 'rsa-sha2-512' => 'ssh-rsa',
        'ssh-ed25519' ||
        'ecdsa-sha2-nistp256' ||
        'ecdsa-sha2-nistp384' ||
        'ecdsa-sha2-nistp521' => algorithm,
        _ => throw const FormatException(),
      };
      return SshHostPin(format, utf8.decode(fingerprint));
    } catch (_) {
      throw const SshTransportFailure(SshTransportCode.TRUST_CHANGED);
    }
  }
  const SshHostPin._(this.format, this.fingerprint);
  static const _formats = {
    'ssh-ed25519',
    'ssh-rsa',
    'ecdsa-sha2-nistp256',
    'ecdsa-sha2-nistp384',
    'ecdsa-sha2-nistp521',
  };
  final String format;
  final String fingerprint;
  Map<String, Object?> toJson() => {
    'format': format,
    'fingerprint': fingerprint,
  };
  @override
  bool operator ==(Object other) =>
      other is SshHostPin &&
      format == other.format &&
      fingerprint == other.fingerprint;
  @override
  int get hashCode => Object.hash(format, fingerprint);
  @override
  String toString() => 'SshHostPin';
}

Never _bad() => throw const FormatException('VALIDATION');
Map<String, Object?> _map(Object? value) =>
    value is Map<String, Object?> ? value : _bad();
String _time(Object? value) {
  if (value is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$')
          .hasMatch(value) ||
      DateTime.tryParse(value)?.toIso8601String() != value) {
    _bad();
  }
  return value;
}

enum HostTrustStatus { trusted, revoked }

/// Structural metadata only. Current owner authorization, target binding and
/// complete retained graph validation belong to the native schema3 service.
final class PublicHostTrustRecord {
  factory PublicHostTrustRecord.fromJson(Map<String, Object?> value) {
    StrictCodec().encode(value, maxBytes: 4096);
    requireFields(value, {
      'profileId',
      'revision',
      'connectionRevision',
      'status',
      'key',
      'createdAt',
      'updatedAt',
    });
    final profile = requireUuid(value['profileId']);
    final revision = requireRevision(value['revision']);
    final connection = requireRevision(value['connectionRevision']);
    if (BigInt.parse(connection) > BigInt.parse(revision)) _bad();
    final status = switch (value['status']) {
      'trusted' => HostTrustStatus.trusted,
      'revoked' => HostTrustStatus.revoked,
      _ => _bad(),
    };
    SshHostPin key;
    try {
      key = SshHostPin.fromJson(_map(value['key']));
    } on SshTransportFailure {
      _bad();
    }
    final createdAt = _time(value['createdAt']);
    final updatedAt = _time(value['updatedAt']);
    if (createdAt.compareTo(updatedAt) > 0) _bad();
    return PublicHostTrustRecord._(
      profile,
      revision,
      connection,
      status,
      key,
      createdAt,
      updatedAt,
    );
  }
  const PublicHostTrustRecord._(
    this.profileId,
    this.revision,
    this.connectionRevision,
    this.status,
    this.key,
    this.createdAt,
    this.updatedAt,
  );
  final String profileId, revision, connectionRevision, createdAt, updatedAt;
  final HostTrustStatus status;
  final SshHostPin key;
  Map<String, Object?> toJson() => {
    'profileId': profileId,
    'revision': revision,
    'connectionRevision': connectionRevision,
    'status': status.name,
    'key': key.toJson(),
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
  @override
  String toString() => 'PublicHostTrustRecord';
}

final class HostTrustRecord extends PublicHostTrustRecord {
  factory HostTrustRecord.fromJson(Map<String, Object?> value) {
    StrictCodec().encode(value, maxBytes: 4096);
    requireFields(value, {
      'workspaceId',
      'profileId',
      'revision',
      'connectionRevision',
      'status',
      'key',
      'createdAt',
      'updatedAt',
    });
    final workspace = requireUuid(value['workspaceId']);
    final public = PublicHostTrustRecord.fromJson(
      Map.of(value)..remove('workspaceId'),
    );
    return HostTrustRecord._(workspace, public);
  }
  HostTrustRecord._(this.workspaceId, PublicHostTrustRecord value)
    : super._(
        value.profileId,
        value.revision,
        value.connectionRevision,
        value.status,
        value.key,
        value.createdAt,
        value.updatedAt,
      );
  final String workspaceId;
  @override
  Map<String, Object?> toJson() => {
    'workspaceId': workspaceId,
    ...super.toJson(),
  };
  Map<String, Object?> toPublicJson() => super.toJson();
  @override
  String toString() => 'HostTrustRecord';
}

/// Format3 only. The legacy LocalError/ErrorCode parser is deliberately intact.
final class TrustedLocalError {
  factory TrustedLocalError(String code, {String? field}) {
    if (!codes.contains(code) ||
        (field != null &&
            (code != 'VALIDATION' || !LocalError.fields.contains(field)))) {
      throw const FormatException('INVALID_TRUST_ERROR');
    }
    return TrustedLocalError._(code, field);
  }
  factory TrustedLocalError.fromJson(Map<String, Object?> value) {
    StrictCodec().encode(value, maxBytes: 512);
    requireFields(value, {'code', 'boundary', 'retry'}, {'field'});
    if (value['code'] is! String ||
        value['boundary'] != 'local' ||
        (value.containsKey('field') && value['field'] is! String)) {
      throw const FormatException('INVALID_TRUST_ERROR');
    }
    final parsed = TrustedLocalError(
      value['code'] as String,
      field: value['field'] as String?,
    );
    if (value['retry'] != parsed.toJson()['retry']) {
      throw const FormatException('INVALID_TRUST_ERROR');
    }
    return parsed;
  }
  factory TrustedLocalError.fromTransport(SshTransportCode code) =>
      TrustedLocalError(
        code == SshTransportCode.VALIDATION_ERROR ? 'VALIDATION' : code.name,
      );
  const TrustedLocalError._(this.code, this.field);
  static final Set<String> codes = Set.unmodifiable({
    for (final code in ErrorCode.values) code.wireName,
    'TRUST_REQUIRED',
    'TRUST_CHANGED',
    'HOST_BUSY',
    'AUTHENTICATION_FAILED',
    'CONNECTION_FAILED',
    'CANCELLED',
  });
  final String code;
  final String? field;
  ErrorCode? get _foundationCode {
    for (final candidate in ErrorCode.values) {
      if (candidate.wireName == code) return candidate;
    }
    return null;
  }

  RetryAdvice get retry {
    final foundation = _foundationCode;
    if (foundation != null) return LocalError(foundation).retry;
    return code == 'CONNECTION_FAILED'
        ? RetryAdvice.reconnect
        : RetryAdvice.none;
  }

  Map<String, Object?> toJson() {
    final foundation = _foundationCode;
    if (foundation != null)
      return LocalError(foundation, field: field).toJson();
    return {
      'code': code,
      'boundary': 'local',
      'retry': retry == RetryAdvice.reconnect ? 'reconnect' : 'none',
    };
  }

  @override
  String toString() => 'TrustedLocalError($code)';
}

/// Closed format3 response. Existing validateResponseEnvelope stays format2.
void validateTrustedResponseEnvelope(Map<String, Object?> value) {
  requireFields(value, {'v', 'id', 'generation'}, {'result', 'error'});
  requireUuid(value['id']);
  requireUuid(value['generation']);
  if (value['v'] is! int ||
      value['v'] != 1 ||
      value.containsKey('result') == value.containsKey('error') ||
      (value['result'] ?? value['error']) is! Map<String, Object?>)
    throw const FormatException('INVALID_TRUST_RESPONSE');
  if (value.containsKey('error'))
    TrustedLocalError.fromJson(value['error'] as Map<String, Object?>);
}

/// Typed result boundary selected only by the verified format3 client/service.
/// It is neither route admission nor a version flag supplied over the wire.
Map<String, Object?> captureTrustedMethodResult(
  String method,
  Map<String, Object?> value,
) {
  if (hostTrustMethodFields.containsKey(method))
    return captureHostTrustResult(method, value);
  if (method == 'readiness.get') {
    return _freezeTrustResult(TrustedReadiness.fromJson(value).toJson())
        as Map<String, Object?>;
  }
  if (method != 'mutations.recent') {
    validateMethodResult(method, value);
    return _freezeTrustResult(value) as Map<String, Object?>;
  }
  requireFields(value, {'receipts', 'truncated'});
  final receipts = value['receipts'];
  if (receipts is! List || receipts.length > 100 || value['truncated'] is! bool)
    _bad();
  final ids = <String>{};
  String? previous;
  for (final item in receipts) {
    final body = _map(item);
    requireFields(body, {
      'requestId',
      'operation',
      'profileId',
      'result',
      'committedAt',
    });
    if (!ids.add(requireUuid(body['requestId']))) _bad();
    final operation = body['operation'];
    if (operation is! String ||
        (!const {
              'servers.trust.confirm',
              'servers.trust.revoke',
            }.contains(operation) &&
            !ApiMethod.values
                .where((m) => m.isMutation)
                .any((m) => m.wireName == operation)))
      _bad();
    if (operation == 'settings.update') {
      if (body['profileId'] != null) _bad();
    } else {
      requireUuid(body['profileId']);
    }
    final result = _map(body['result']);
    if (operation.startsWith('servers.trust.'))
      captureHostTrustResult(operation, result);
    else
      validateMethodResult(operation, result);
    if (result['entityId'] != body['profileId']) _bad();
    final timestamp = _time(body['committedAt']);
    if (previous != null && previous.compareTo(timestamp) < 0) _bad();
    previous = timestamp;
  }
  return _freezeTrustResult(value) as Map<String, Object?>;
}

String requireTrustFailureCode(Object? value) {
  if (value is! String || !TrustedLocalError.codes.contains(value)) _bad();
  return value;
}

void _capturedTrustCounters(Map<String, Object?> value, String revisionField) {
  final revision = BigInt.parse(requireRevision(value[revisionField]));
  final connection = BigInt.parse(requireRevision(value['connectionRevision']));
  final credential = BigInt.parse(requireRevision(value['credentialRevision']));
  final trust = BigInt.parse(requireRevision(value['trustRevision']));
  if (connection > trust || trust > revision || credential > revision) _bad();
}

/// A public snapshot, not current authority to connect or change the key.
final class HostTrustSnapshot {
  factory HostTrustSnapshot.fromJson(Map<String, Object?> value) {
    StrictCodec().encode(value);
    requireFields(value, {
      'profileId',
      'profileRevision',
      'connectionRevision',
      'credentialRevision',
      'trustRevision',
      'trust',
    });
    final profile = requireUuid(value['profileId']);
    _capturedTrustCounters(value, 'profileRevision');
    final trust = value['trust'] == null
        ? null
        : PublicHostTrustRecord.fromJson(_map(value['trust']));
    if (trust == null) {
      if (value['connectionRevision'] != value['trustRevision']) _bad();
    } else if (trust.profileId != profile ||
        trust.revision != value['trustRevision'] ||
        BigInt.parse(trust.connectionRevision) >
            BigInt.parse(value['connectionRevision'] as String) ||
        (trust.status == HostTrustStatus.trusted &&
            trust.connectionRevision != value['connectionRevision'])) {
      _bad();
    }
    return HostTrustSnapshot._(
      profile,
      value['profileRevision'] as String,
      value['connectionRevision'] as String,
      value['credentialRevision'] as String,
      value['trustRevision'] as String,
      trust,
    );
  }
  const HostTrustSnapshot._(
    this.profileId,
    this.profileRevision,
    this.connectionRevision,
    this.credentialRevision,
    this.trustRevision,
    this.trust,
  );
  final String profileId,
      profileRevision,
      connectionRevision,
      credentialRevision,
      trustRevision;
  final PublicHostTrustRecord? trust;
  Map<String, Object?> toJson() => {
    'profileId': profileId,
    'profileRevision': profileRevision,
    'connectionRevision': connectionRevision,
    'credentialRevision': credentialRevision,
    'trustRevision': trustRevision,
    'trust': trust?.toJson(),
  };
  @override
  String toString() => 'HostTrustSnapshot';
}

/// Display/correlation metadata only. Native owner/session/generation binding
/// and the actual monotonic expiry/consume check belong to the service.
final class HostTrustChallenge {
  factory HostTrustChallenge.fromJson(Map<String, Object?> value) {
    StrictCodec().encode(value);
    requireFields(value, {
      'challengeId',
      'profileId',
      'expectedRevision',
      'connectionRevision',
      'credentialRevision',
      'trustRevision',
      'key',
      'expiresAt',
    });
    final challenge = requireUuid(value['challengeId']);
    final profile = requireUuid(value['profileId']);
    _capturedTrustCounters(value, 'expectedRevision');
    SshHostPin key;
    try {
      key = SshHostPin.fromJson(_map(value['key']));
    } on SshTransportFailure {
      _bad();
    }
    return HostTrustChallenge._(
      challenge,
      profile,
      value['expectedRevision'] as String,
      value['connectionRevision'] as String,
      value['credentialRevision'] as String,
      value['trustRevision'] as String,
      key,
      _time(value['expiresAt']),
    );
  }
  const HostTrustChallenge._(
    this.challengeId,
    this.profileId,
    this.expectedRevision,
    this.connectionRevision,
    this.credentialRevision,
    this.trustRevision,
    this.key,
    this.expiresAt,
  );
  final String challengeId,
      profileId,
      expectedRevision,
      connectionRevision,
      credentialRevision,
      trustRevision,
      expiresAt;
  final SshHostPin key;
  Map<String, Object?> toJson() => {
    'challengeId': challengeId,
    'profileId': profileId,
    'expectedRevision': expectedRevision,
    'connectionRevision': connectionRevision,
    'credentialRevision': credentialRevision,
    'trustRevision': trustRevision,
    'key': key.toJson(),
    'expiresAt': expiresAt,
  };
  @override
  String toString() => 'HostTrustChallenge';
}

Object? _freezeTrustResult(Object? value) => switch (value) {
  Map<String, Object?>() => Map<String, Object?>.unmodifiable({
    for (final entry in value.entries)
      entry.key: _freezeTrustResult(entry.value),
  }),
  List() => List<Object?>.unmodifiable(value.map(_freezeTrustResult)),
  _ => value,
};

/// Exact ordinary owner response validation. Does not authorize a route or
/// select format3; verified native composition must do both before use.
Map<String, Object?> captureHostTrustResult(
  String method,
  Map<String, Object?> value,
) {
  StrictCodec().encode(value);
  Map<String, Object?> result;
  switch (method) {
    case 'servers.trust.get':
      result = HostTrustSnapshot.fromJson(value).toJson();
    case 'servers.trust.probe' || 'servers.trust.probeStatus':
      requireUuid(value['operationId']);
      switch (value['state']) {
        case 'running':
          requireFields(value, {'operationId', 'state'});
          result = Map.of(value);
        case 'succeeded' when method == 'servers.trust.probeStatus':
          requireFields(value, {'operationId', 'state', 'challenge'});
          result = {
            ...value,
            'challenge': HostTrustChallenge.fromJson(_map(value['challenge']))
                .toJson(),
          };
        case 'failed' when method == 'servers.trust.probeStatus':
          requireFields(value, {'operationId', 'state', 'code'});
          requireTrustFailureCode(value['code']);
          result = Map.of(value);
        default:
          _bad();
      }
    case 'servers.trust.probeCancel':
      requireFields(value, {'operationId', 'cancelled'});
      requireUuid(value['operationId']);
      if (value['cancelled'] is! bool) _bad();
      result = Map.of(value);
    case 'servers.trust.confirm' || 'servers.trust.revoke':
      validateMethodResult('profiles.update', value);
      final revision = BigInt.parse(value['entityRevision'] as String);
      if (revision < BigInt.two ||
          revision > BigInt.parse(value['storeRevision'] as String))
        _bad();
      result = Map.of(value);
    default:
      throw const FormatException('UNSUPPORTED');
  }
  return _freezeTrustResult(result) as Map<String, Object?>;
}

const hostTrustMethodFields = <String, Set<String>>{
  'servers.trust.get': {'profileId'},
  'servers.trust.probe': {'profileId', 'expectedRevision'},
  'servers.trust.probeStatus': {'operationId'},
  'servers.trust.probeCancel': {'operationId'},
  'servers.trust.confirm': {
    'profileId',
    'expectedRevision',
    'challengeId',
    'key',
  },
  'servers.trust.revoke': {'profileId', 'expectedRevision'},
};

/// Pure bounded capture, never an authorization or a source of native proof.
/// The owner adapter must gate before calling this on untrusted input.
Map<String, Object?> captureHostTrustParams(
  String method,
  Map<String, Object?> value,
) {
  final fields = hostTrustMethodFields[method];
  if (fields == null) throw const FormatException('UNSUPPORTED');
  StrictCodec().encode(value, maxBytes: 4096);
  requireFields(value, fields);
  for (final field in ['profileId', 'operationId', 'challengeId']) {
    if (value.containsKey(field)) requireUuid(value[field]);
  }
  if (value.containsKey('expectedRevision'))
    requireRevision(value['expectedRevision']);
  Map<String, Object?>? key;
  if (value.containsKey('key')) {
    try {
      key = SshHostPin.fromJson(_map(value['key'])).toJson();
    } on SshTransportFailure {
      _bad();
    }
  }
  return Map.unmodifiable({
    ...value,
    if (key != null) 'key': Map<String, Object?>.unmodifiable(key),
  });
}
