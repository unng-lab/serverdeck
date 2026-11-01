import 'dart:convert';
import 'dart:typed_data';

import 'package:serverdeck_protocol/automation/direct_ssh_dispatch.dart';
import 'package:serverdeck_protocol/validation.dart';

import 'direct_ssh.dart';

const _identityFields = [
  'workspaceId',
  'jobId',
  'attemptId',
  'planDigest',
  'hostId',
  'bootIdHash',
];
const _schemas = <String, List<String>>{
  'owner': _identityFields,
  'admission': _identityFields,
  'plan': ['planDigest', 'attemptId', 'terminal'],
  'step': [
    'attemptId',
    'planDigest',
    'stepId',
    'stepDigest',
    'token',
    'bootIdHash',
    'issuedUptimeMs',
    'expiresUptimeMs',
    'authorityBindingDigest',
    'targetBindingDigest',
    'state',
    'exitCode',
    'checkDigest',
  ],
  'stop': ['attemptId', 'planDigest'],
  'policy': ['attemptId', 'planDigest', 'ownership', 'fixedBytesDigest'],
  'terminal': [..._identityFields, 'state', 'checksDigest'],
  'resource': [
    'hostId',
    'resourceId',
    'product',
    'version',
    'recipeDigest',
    'registryDigest',
    'compilerDigest',
    'installAttemptId',
    'installStepId',
    'installStepDigest',
    'lastConfigAttemptId',
    'lastConfigStepId',
    'unitParentDigest',
    'managedFileDigest',
  ],
};

Never _invalid() => throw DirectSshFailure('VALIDATION');
bool _digest(String? value) =>
    value != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
int _uint(String value, int maximum) {
  if (!RegExp(r'^(?:0|[1-9][0-9]{0,18})$').hasMatch(value)) _invalid();
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < 0 || parsed > maximum) _invalid();
  return parsed;
}

/// Closed SDSSH1 data. A parsed record is not a host lock, current permission
/// or successful observation. Callers must correlate it with their actual job.
final class DirectHostRecord {
  DirectHostRecord._(this.kind, this.fields);

  factory DirectHostRecord.create(String kind, Map<String, String> fields) {
    try {
      final schema = _schemas[kind];
      if (schema == null ||
          fields.length != schema.length ||
          !fields.keys.toSet().containsAll(schema)) {
        _invalid();
      }
      final copied = <String, String>{
        for (final key in schema) key: fields[key]!,
      };
      _validate(kind, copied);
      return DirectHostRecord._(kind, Map.unmodifiable(copied));
    } on DirectSshFailure {
      rethrow;
    } catch (_) {
      _invalid();
    }
  }

  factory DirectHostRecord.parse(List<int> bytes, {String? expectedKind}) {
    if (bytes.length > 16384) throw DirectSshFailure('RESOURCE_LIMIT');
    try {
      final text = ascii.decode(bytes);
      if (!text.endsWith('\n')) _invalid();
      final rows = text.substring(0, text.length - 1).split('\n');
      if (rows.length < 2 || rows[0] != 'SDSSH1') _invalid();
      final kind = rows[1], schema = _schemas[rows[1]];
      if (schema == null ||
          rows.length != schema.length + 2 ||
          expectedKind != null && kind != expectedKind) {
        _invalid();
      }
      return DirectHostRecord.create(kind, {
        for (var index = 0; index < schema.length; index++)
          schema[index]: rows[index + 2],
      });
    } catch (_) {
      throw DirectSshFailure('UNKNOWN_OUTCOME');
    }
  }

  final String kind;
  final Map<String, String> fields;
  Uint8List encode() => Uint8List.fromList(
    ascii.encode('SDSSH1\n' + kind + '\n' + fields.values.join('\n') + '\n'),
  ).asUnmodifiableView();

  static void _validate(String kind, Map<String, String> fields) {
    for (final entry in fields.entries) {
      final name = entry.key, value = entry.value;
      if (value.isEmpty ||
          value.length > 256 ||
          value.codeUnits.any((unit) => unit < 33 || unit > 126)) {
        _invalid();
      }
      if (const {
        'workspaceId',
        'jobId',
        'attemptId',
        'hostId',
        'token',
        'installAttemptId',
        'lastConfigAttemptId',
      }.contains(name)) {
        requireUuid(value);
      } else if (name.endsWith('Digest') || name.endsWith('Hash')) {
        if (name == 'checkDigest' && value == 'unknown') continue;
        if (!_digest(value)) _invalid();
      } else if (const {
        'stepId',
        'installStepId',
        'lastConfigStepId',
      }.contains(name)) {
        if (!RegExp(r'^[a-z][a-z0-9_]{0,31}$').hasMatch(value)) _invalid();
      }
    }
    switch (kind) {
      case 'plan':
        if (!const {
          'pending',
          'succeeded',
          'failed',
          'cancelled',
          'unknown',
        }.contains(fields['terminal']))
          _invalid();
      case 'policy':
        if (!const {'created', 'reused'}.contains(fields['ownership']))
          _invalid();
      case 'terminal':
        if (!const {
          'succeeded',
          'failed',
          'cancelled',
        }.contains(fields['state']))
          _invalid();
      case 'step':
        DirectSshDispatch.validateWindow(
          issuedUptimeMs: _uint(fields['issuedUptimeMs']!, 9223372036854775807),
          expiresUptimeMs: _uint(
            fields['expiresUptimeMs']!,
            9223372036854775807,
          ),
        );
        final state = fields['state']!, exit = fields['exitCode']!;
        if (!const {
          'reserved',
          'started',
          'succeeded',
          'failed',
          'stopped',
          'unknown',
        }.contains(state))
          _invalid();
        final code = exit == 'unknown' ? null : _uint(exit, 255);
        if (state == 'succeeded' &&
                (code != 0 || !_digest(fields['checkDigest'])) ||
            state == 'failed' &&
                (code == null || !_digest(fields['checkDigest'])) ||
            const {'reserved', 'started'}.contains(state) &&
                (code != null || fields['checkDigest'] != 'unknown')) {
          _invalid();
        }
      case 'resource':
        if (fields['version']!.toLowerCase() == 'latest' ||
            ['{{', '{%', '{#'].any(fields['version']!.contains))
          _invalid();
        final product = fields['product'];
        final prefix = product == 'postgresql16'
            ? 'postgresql'
            : product == 'clickhouse'
            ? 'clickhouse'
            : null;
        if (prefix == null ||
            !{
              prefix + '.service',
              prefix + '.settings',
            }.contains(fields['resourceId']))
          _invalid();
    }
  }

  @override
  String toString() => 'DirectHostRecord(' + kind + ')';
}
