import 'dart:convert';
import 'dart:typed_data';

import 'codec.dart';
import 'errors.dart';
import 'models.dart';
import 'validation.dart';

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
final class HostTrustRecord {
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
    return HostTrustRecord._(
      workspace,
      profile,
      revision,
      connection,
      status,
      key,
      createdAt,
      updatedAt,
    );
  }
  const HostTrustRecord._(
    this.workspaceId,
    this.profileId,
    this.revision,
    this.connectionRevision,
    this.status,
    this.key,
    this.createdAt,
    this.updatedAt,
  );
  final String workspaceId,
      profileId,
      revision,
      connectionRevision,
      createdAt,
      updatedAt;
  final HostTrustStatus status;
  final SshHostPin key;
  Map<String, Object?> toJson() => {
    'workspaceId': workspaceId,
    'profileId': profileId,
    'revision': revision,
    'connectionRevision': connectionRevision,
    'status': status.name,
    'key': key.toJson(),
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
  Map<String, Object?> toPublicJson() => toJson()..remove('workspaceId');
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

String requireTrustFailureCode(Object? value) {
  if (value is! String || !TrustedLocalError.codes.contains(value)) _bad();
  return value;
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
