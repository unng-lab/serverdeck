import 'dart:convert';

import 'automation/profile_body.dart';
import 'codec.dart';
import 'validation.dart';

const executorMethods = {
  'hello',
  'observe',
  'recipes',
  'preflight',
  'preflight_get',
  'submit',
  'status',
  'authorize_step',
  'cancel',
  'reconcile',
};
const executorCodes = {
  'VALIDATION',
  'INVALID_FRAME',
  'FORBIDDEN',
  'INCOMPATIBLE',
  'CONFLICT',
  'NOT_FOUND',
  'RESOURCE_LIMIT',
  'TIMEOUT',
  'EXECUTOR_UNAVAILABLE',
  'TRUST_CHANGED',
  'HOST_BUSY',
  'PREFLIGHT_FAILED',
  'QUALIFICATION_REQUIRED',
  'RECOVERY_REQUIRED',
  'HEALTH_CHECK_FAILED',
  'POSTCHECK_FAILED',
  'STEP_FAILED',
  'UNKNOWN_OUTCOME',
  'UNSUPPORTED',
  'INTERNAL',
  'CANCELLED',
};
Never _bad() => throw const FormatException('VALIDATION');
Map<String, Object?> _object(Object? value) =>
    value is Map<String, Object?> ? value : _bad();
void _digest(Object? value) {
  if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) _bad();
}

void _integer(Object? value, int min, int max) {
  if (value is! int || value < min || value > max) _bad();
}

void _target(Map<String, Object?> target) {
  requireFields(target, {
    'workspaceId',
    'serverId',
    'targetRevision',
    'connectionRevision',
    'accessRevision',
    'trustRevision',
  });
  requireUuid(target['workspaceId']);
  requireUuid(target['serverId']);
  for (final field in [
    'targetRevision',
    'connectionRevision',
    'accessRevision',
    'trustRevision',
  ]) {
    requireRevision(target[field]);
  }
  final revision = BigInt.parse(target['targetRevision'] as String);
  final connection = BigInt.parse(target['connectionRevision'] as String);
  final trust = BigInt.parse(target['trustRevision'] as String);
  if (connection > trust ||
      trust > revision ||
      BigInt.parse(target['accessRevision'] as String) > revision)
    _bad();
}

/// Immutable strict input, never evidence or permission to execute a step.
/// Only locald's enrolled/admitted service may send this over its private SSH.
final class ExecutorRequest {
  factory ExecutorRequest.capture(
    String method,
    Map<String, Object?> params, {
    required String requestId,
  }) {
    if (!executorMethods.contains(method)) _bad();
    requireUuid(requestId);
    final codec = StrictCodec();
    final copy = codec.decode(
      codec.encode(params, maxBytes: 256 * 1024),
      maxBytes: 256 * 1024,
    );
    switch (method) {
      case 'hello':
        requireFields(copy, {'controllerId', 'workspaceId'});
      case 'observe':
        requireFields(copy, {'resourceId', 'target', 'expectedHostId'});
        if (!const {
          'system.motd',
          'postgresql.service',
          'postgresql.settings',
          'clickhouse.service',
          'clickhouse.settings',
        }.contains(copy['resourceId']))
          _bad();
        _target(_object(copy['target']));
      case 'recipes':
        requireFields(copy, {'target', 'expectedHostId'});
        _target(_object(copy['target']));
      case 'preflight':
        requireFields(copy, {
          'operationId',
          'profileBody',
          'profileDigest',
          'parameters',
          'expectedHostId',
          'target',
        });
        _target(_object(copy['target']));
      case 'preflight_get':
        requireFields(copy, {'operationId'});
      case 'submit':
        requireFields(copy, {
          'jobId',
          'attemptId',
          'planDigest',
          'profileId',
          'profileRevision',
          'profileBody',
          'profileDigest',
          'parameters',
          'preflightDigest',
          'expectedHostId',
          'controllerId',
          'workspaceId',
        });
        _integer(copy['profileRevision'], 1, 2147483647);
      case 'status':
        requireFields(copy, {'attemptId'}, {'afterSequence', 'limit'});
        if (copy.containsKey('afterSequence'))
          _integer(copy['afterSequence'], 0, 0x7fffffffffffffff);
        if (copy.containsKey('limit')) _integer(copy['limit'], 1, 100);
      case 'authorize_step':
        requireFields(copy, {
          'attemptId',
          'stepId',
          'planDigest',
          'challenge',
          'authorizationEpoch',
          'expiresAt',
        });
        if (copy['stepId'] is! String ||
            !RegExp(r'^[a-z][a-z0-9_]{0,31}$')
                .hasMatch(copy['stepId'] as String))
          _bad();
        final challenge = copy['challenge'];
        if (challenge is! String ||
            !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(challenge))
          _bad();
        try {
          final raw = base64Url.decode('$challenge=');
          if (raw.length != 32 ||
              base64Url.encode(raw).replaceAll('=', '') != challenge)
            _bad();
        } on FormatException {
          _bad();
        }
        _integer(copy['authorizationEpoch'], 1, 2147483647);
        final expires = copy['expiresAt'];
        if (expires is! String ||
            !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$')
                .hasMatch(expires) ||
            DateTime.tryParse(expires)?.toIso8601String() != expires)
          _bad();
      case 'cancel':
        requireFields(copy, {'attemptId', 'requestId'});
      case 'reconcile':
        requireFields(copy, {'attemptId'});
    }
    for (final field in [
      'operationId',
      'controllerId',
      'workspaceId',
      'jobId',
      'attemptId',
      'profileId',
      'expectedHostId',
      'requestId',
    ]) {
      if (copy.containsKey(field)) requireUuid(copy[field]);
    }
    for (final field in ['planDigest', 'profileDigest', 'preflightDigest']) {
      if (copy.containsKey(field)) _digest(copy[field]);
    }
    if (copy.containsKey('profileBody')) {
      final body = AutomationBody.fromJson(_object(copy['profileBody']));
      body.resolveParameters(_object(copy['parameters']));
    }
    final bytes = codec.encode({
      'v': 1,
      'id': requestId,
      'method': method,
      'params': copy,
    }, maxBytes: 256 * 1024);
    return ExecutorRequest._(method, requestId, utf8.decode(bytes));
  }
  const ExecutorRequest._(this.method, this.id, this._json);
  final String method, id, _json;
  List<int> get bytes => utf8.encode(_json);
}

final class ExecutorRemoteError implements Exception {
  const ExecutorRemoteError._(this.code, this.retry);
  final String code;
  final bool retry;
  @override
  String toString() => 'ExecutorRemoteError($code)';
}

Map<String, Object?> captureExecutorResponse(
  ExecutorRequest request,
  Map<String, Object?> value,
) {
  StrictCodec().encode(value, maxBytes: 8 * 1024 * 1024);
  if (value['id'] != request.id) _bad();
  if (value.containsKey('error')) {
    requireFields(value, {'id', 'error'});
    final error = _object(value['error']);
    requireFields(error, {'code', 'retry'});
    if (!executorCodes.contains(error['code']) || error['retry'] is! bool)
      _bad();
    throw ExecutorRemoteError._(
      error['code'] as String,
      error['retry'] as bool,
    );
  }
  requireFields(value, {'id', 'result'});
  return _freeze(_object(value['result'])) as Map<String, Object?>;
}

Object? _freeze(Object? value) => switch (value) {
  Map<String, Object?>() => Map<String, Object?>.unmodifiable({
    for (final entry in value.entries) entry.key: _freeze(entry.value),
  }),
  List() => List<Object?>.unmodifiable(value.map(_freeze)),
  _ => value,
};
