import 'dart:convert';

import 'errors.dart';
import 'models.dart';

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _decimal = RegExp(r'^(0|[1-9][0-9]*)$');
final maxRevision = BigInt.parse('9223372036854775807');

const methodParamFields = <String, Set<String>>{
  'readiness.get': {},
  'session.ping': {},
  'session.close': {},
  'profiles.list': {},
  'profiles.get': {'profileId'},
  'profiles.create': {'profileId', 'name', 'address', 'sshUser'},
  'profiles.update': {
    'profileId',
    'expectedRevision',
    'name',
    'address',
    'port',
    'sshUser',
    'tags',
    'credential',
  },
  'profiles.delete': {'profileId', 'expectedRevision'},
  'settings.get': {},
  'settings.update': {
    'expectedRevision',
    'theme',
    'reduceMotion',
    'selectedProfileId',
  },
  'mutations.get': {'requestId'},
  'mutations.recent': {},
};

/// Called only after the router has verified the method's capability.
void validateMethodShape(String method, Map<String, Object?> params) {
  final fields = methodParamFields[method];
  if (fields == null) {
    throw const FormatException('UNSUPPORTED');
  }
  requireFields(
    params,
    fields,
    method == 'profiles.create'
        ? {'port', 'tags', 'credential'}
        : method == 'mutations.recent'
        ? {'limit'}
        : {},
  );
  for (final field in ['profileId', 'requestId']) {
    if (params.containsKey(field)) {
      requireUuid(params[field]);
    }
  }
  if (params.containsKey('expectedRevision')) {
    requireRevision(params['expectedRevision']);
  }
  if (params.containsKey('credential')) {
    final credential = params['credential'];
    if (credential is! Map<String, Object?>) {
      throw const FormatException('VALIDATION');
    }
    switch (credential['action']) {
      case 'keep':
        if (method != 'profiles.update') {
          throw const FormatException('VALIDATION');
        }
        requireFields(credential, {'action'});
      case 'remove':
        requireFields(credential, {'action'});
      case 'replace':
        if (credential['kind'] == 'password') {
          requireFields(credential, {'action', 'kind', 'password'});
        } else if (credential['kind'] == 'privateKey') {
          requireFields(credential, {
            'action',
            'kind',
            'privateKey',
            'passphrase',
          });
        } else {
          throw const FormatException('VALIDATION');
        }
      default:
        throw const FormatException('VALIDATION');
    }
  }
}

String requireUuid(Object? value) {
  if (value is! String || !_uuid.hasMatch(value)) {
    throw const FormatException('VALIDATION');
  }
  return value;
}

String requireRevision(Object? value, {bool allowZero = false}) {
  if (value is! String || !_decimal.hasMatch(value) || value.length > 19) {
    throw const FormatException('VALIDATION');
  }
  final revision = BigInt.parse(value);
  if (revision > maxRevision || (!allowZero && revision == BigInt.zero)) {
    throw const FormatException('VALIDATION');
  }
  return value;
}

void requireFields(
  Map<String, Object?> value,
  Set<String> required, [
  Set<String> optional = const {},
]) {
  if (!value.keys.toSet().containsAll(required) ||
      value.keys.any(
        (key) => !required.contains(key) && !optional.contains(key),
      )) {
    throw const FormatException('VALIDATION');
  }
}

void validateRequestEnvelope(Map<String, Object?> value) {
  requireFields(value, {'v', 'id', 'sessionId', 'method', 'params'});
  requireUuid(value['id']);
  if (value['v'] is! int ||
      value['v'] != 1 ||
      value['params'] is! Map<String, Object?> ||
      value['method'] is! String) {
    throw const FormatException('VALIDATION');
  }
  requireNonce(value['sessionId']);
}

void validateResponseEnvelope(Map<String, Object?> value) {
  requireFields(value, {'v', 'id', 'generation'}, {'result', 'error'});
  requireUuid(value['id']);
  requireUuid(value['generation']);
  if (value['v'] is! int ||
      value['v'] != 1 ||
      value.containsKey('result') == value.containsKey('error') ||
      (value['result'] ?? value['error']) is! Map<String, Object?>) {
    throw const FormatException('VALIDATION');
  }
  if (value.containsKey('error')) {
    validateError(value['error'] as Map<String, Object?>);
  }
}

/// Canonical, unpadded base64url encoding of exactly 256 bits.
void requireNonce(Object? value) {
  if (value is! String || !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value)) {
    throw const FormatException('VALIDATION');
  }
  final bytes = base64Url.decode('$value=');
  if (bytes.length != 32 ||
      base64Url.encode(bytes).replaceAll('=', '') != value) {
    throw const FormatException('VALIDATION');
  }
}

void validateError(Map<String, Object?> value) {
  requireFields(value, {'code', 'boundary', 'retry'}, {'field'});
  final codes = ErrorCode.values.where((e) => e.wireName == value['code']);
  if (codes.isEmpty || value['boundary'] != 'local') {
    throw const FormatException('VALIDATION');
  }
  final code = codes.single;
  final field = value['field'];
  if (value.containsKey('field') &&
      (code != ErrorCode.validation ||
          field is! String ||
          !LocalError.fields.contains(field))) {
    throw const FormatException('VALIDATION');
  }
  if (value['retry'] != LocalError(code).toJson()['retry']) {
    throw const FormatException('VALIDATION');
  }
}
