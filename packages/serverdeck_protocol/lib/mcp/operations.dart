import 'dart:convert';

import '../automation/values.dart';
import '../codec.dart';
import '../validation.dart';
import 'catalog.dart';
import 'wire.dart';

const mcpMaxToolResultBytes = mcpMaxResponseBytes - 4096;
const mcpDomainCodes = {
  'UNSUPPORTED',
  'UNAUTHORIZED',
  'FORBIDDEN',
  'INCOMPATIBLE',
  'NOT_READY',
  'STORAGE_BLOCKED',
  'VALIDATION',
  'NOT_FOUND',
  'ALREADY_EXISTS',
  'REVISION_CONFLICT',
  'IDEMPOTENCY_CONFLICT',
  'RESOURCE_LIMIT',
  'TIMEOUT',
  'SERVICE_UNAVAILABLE',
  'INTERNAL',
  'TRUST_REQUIRED',
  'TRUST_CHANGED',
  'APPROVAL_REQUIRED',
  'PLAN_EXPIRED',
  'PLAN_STALE',
  'HOST_BUSY',
  'EXECUTOR_UNAVAILABLE',
  'RUNTIME_INCOMPATIBLE',
  'CURSOR_EXPIRED',
  'UNKNOWN_OUTCOME',
};
Never _invalid() => throw const FormatException('VALIDATION');
Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) _invalid();
  return value;
}

List<int> _encode(Map<String, Object?> value, int limit) {
  try {
    return List.unmodifiable(encodeMcpMessage(value, maxBytes: limit));
  } catch (_) {
    _invalid();
  }
}

Object? _freeze(Object? value) => switch (value) {
  Map<String, Object?> value => Map<String, Object?>.unmodifiable(
    value.map((k, v) => MapEntry(k, _freeze(v))),
  ),
  List value => List<Object?>.unmodifiable(value.map(_freeze)),
  _ => value,
};
bool _equal(Object? a, Object? b) {
  if (a is Map && b is Map)
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && _equal(a[k], b[k]));
  if (a is List && b is List)
    return a.length == b.length &&
        Iterable<int>.generate(a.length).every((i) => _equal(a[i], b[i]));
  if (a is num && b is num && (a is int) != (b is int)) return false;
  return a == b;
}

enum McpInvokeKind { catalog, request, poll, cancel }

/// A strict immutable wire input, never session/target authority.
final class McpInvokeInput {
  McpInvokeInput._(
    this.kind,
    this.name,
    this.arguments,
    this.operationId,
    this._bytes,
  );
  factory McpInvokeInput.decode(List<int> bytes) {
    try {
      return McpInvokeInput.fromJson(
        StrictCodec().decode(bytes, maxBytes: mcpMaxRequestBytes),
      );
    } catch (_) {
      _invalid();
    }
  }
  factory McpInvokeInput.fromJson(Object? raw) {
    try {
      final bytes = _encode(_object(raw), mcpMaxRequestBytes);
      final value = StrictCodec().decode(bytes, maxBytes: mcpMaxRequestBytes);
      if (value.length != 1) _invalid();
      final kind = McpInvokeKind.values
          .where((k) => k.name == value.keys.single)
          .single;
      final body = _object(value[kind.name]);
      String? name, id;
      Map<String, Object?>? args;
      switch (kind) {
        case McpInvokeKind.catalog:
          requireFields(body, {});
        case McpInvokeKind.request:
          requireFields(body, {'name', 'arguments'});
          if (body['name'] is! String ||
              (body['name'] as String).runes.isEmpty ||
              (body['name'] as String).runes.length > 256)
            _invalid();
          name = body['name'] as String;
          args = _freeze(_object(body['arguments'])) as Map<String, Object?>;
        case McpInvokeKind.poll || McpInvokeKind.cancel:
          requireFields(body, {'operationId'});
          id = requireUuid(body['operationId']);
      }
      return McpInvokeInput._(kind, name, args, id, bytes);
    } catch (_) {
      _invalid();
    }
  }
  final McpInvokeKind kind;
  final String? name, operationId;
  final Map<String, Object?>? arguments;
  final List<int> _bytes;
  Map<String, Object?> toJson() =>
      StrictCodec().decode(_bytes, maxBytes: mcpMaxRequestBytes);
}

/// Catalog's closed schema vocabulary. No runtime schemas/plugins are accepted.
void validateMcpArguments(McpToolDefinition tool, Map<String, Object?> input) {
  try {
    _encode({'arguments': input}, mcpMaxRequestBytes);
    final schema = tool.inputSchema;
    if (!_matches(
      schema,
      input,
      schema[r'$defs'] as Map<String, Object?>? ?? {},
      0,
      {},
    ))
      _invalid();
  } catch (_) {
    _invalid();
  }
}

bool _matches(
  Map<String, Object?> schema,
  Object? value,
  Map<String, Object?> definitions,
  int depth,
  Set<String> path,
) {
  if (depth > 64) return false;
  bool child(Map<String, Object?> s, Object? v) =>
      _matches(s, v, definitions, depth + 1, path);
  if (schema[r'$ref'] case final String reference) {
    if (schema.length != 1 ||
        !RegExp(r'^#/\$defs/s[0-9]+$').hasMatch(reference) ||
        path.contains(reference))
      return false;
    final target = definitions[reference.substring('#/\$defs/'.length)];
    return target is Map<String, Object?> &&
        _matches(target, value, definitions, depth + 1, {...path, reference});
  }
  if (schema.keys.any(
    (k) => !const {
      'type',
      'const',
      'enum',
      'oneOf',
      'properties',
      'required',
      'additionalProperties',
      'propertyNames',
      'minLength',
      'maxLength',
      'pattern',
      'format',
      'minimum',
      'maximum',
      'minItems',
      'maxItems',
      'uniqueItems',
      'items',
      'maxProperties',
      'description',
      'default',
      r'$defs',
    }.contains(k),
  ))
    return false;
  if (schema.containsKey('const') && !_equal(schema['const'], value))
    return false;
  if (schema['enum'] case final List choices) {
    if (!choices.any((v) => _equal(v, value))) return false;
  }
  if (schema['oneOf'] case final List branches) {
    if (branches.where((b) => child(_object(b), value)).length != 1)
      return false;
  }
  switch (schema['type']) {
    case 'object':
      if (value is! Map<String, Object?>) return false;
      if (schema['maxProperties'] case final int max) {
        if (value.length > max) return false;
      }
      final properties = schema['properties'] as Map<String, Object?>? ?? {};
      final required = schema['required'] as List? ?? [];
      if (required.any((k) => !value.containsKey(k))) return false;
      for (final entry in value.entries) {
        if (schema['propertyNames'] case final Map<String, Object?> names) {
          if (!child(names, entry.key)) return false;
        }
        final definition =
            properties[entry.key] ?? schema['additionalProperties'];
        if (definition == false) return false;
        if (definition is Map<String, Object?> &&
            !child(definition, entry.value))
          return false;
      }
    case 'array':
      if (value is! List) return false;
      if (schema['minItems'] case final int min) {
        if (value.length < min) return false;
      }
      if (schema['maxItems'] case final int max) {
        if (value.length > max) return false;
      }
      if (schema['uniqueItems'] == true) {
        for (var i = 0; i < value.length; i++) {
          for (var j = 0; j < i; j++) {
            if (_equal(value[i], value[j])) return false;
          }
        }
      }
      if (schema['items'] case final Map<String, Object?> item) {
        if (value.any((v) => !child(item, v))) return false;
      }
    case 'string':
      if (value is! String) return false;
      final length = value.runes.length;
      if (schema['minLength'] case final int min) {
        if (length < min) return false;
      }
      if (schema['maxLength'] case final int max) {
        if (length > max) return false;
      }
      if (schema['pattern'] case final String pattern) {
        if (!RegExp(pattern).hasMatch(value)) return false;
      }
      if (schema['format'] == 'date-time') {
        try {
          automationTimestamp(value);
        } catch (_) {
          return false;
        }
      }
    case 'integer':
      if (value is! int) return false;
      if (schema['minimum'] case final int min) {
        if (value < min) return false;
      }
      if (schema['maximum'] case final int max) {
        if (value > max) return false;
      }
    case 'boolean':
      if (value is! bool) return false;
    case null:
      break;
    default:
      return false;
  }
  return true;
}

/// Validated public result; callers cannot retain a mutable data buffer in it.
final class McpToolResult {
  McpToolResult._(this._bytes);
  factory McpToolResult.success(Map<String, Object?> data) =>
      McpToolResult._build({'ok': true, 'data': data});
  factory McpToolResult.failure(
    String code, {
    String boundary = 'local',
    String retry = 'none',
    String? requestId,
  }) => McpToolResult._build({
    'ok': false,
    'error': {'code': code, 'boundary': boundary, 'retry': retry},
    if (requestId != null) 'requestId': requestId,
  });
  factory McpToolResult._build(Map<String, Object?> result) {
    try {
      _encode(result, mcpMaxToolResultBytes);
      return McpToolResult.fromJson({
        'content': [
          {'type': 'text', 'text': jsonEncode(result)},
        ],
        'structuredContent': result,
        'isError': result['ok'] == false,
      });
    } catch (_) {
      _invalid();
    }
  }
  factory McpToolResult.fromJson(Object? raw) {
    try {
      final bytes = _encode(_object(raw), mcpMaxToolResultBytes);
      final value = StrictCodec().decode(
        bytes,
        maxBytes: mcpMaxToolResultBytes,
      );
      // Reserve nesting for done.result and the Local API response envelope.
      _encode({
        'result': {'result': value},
      }, mcpMaxResponseBytes);
      requireFields(value, {'content', 'structuredContent', 'isError'});
      final result = _object(value['structuredContent']);
      if (result['ok'] == true) {
        requireFields(result, {'ok', 'data'});
        _object(result['data']);
      } else if (result['ok'] == false) {
        requireFields(result, {'ok', 'error'}, {'requestId'});
        final error = _object(result['error']);
        requireFields(error, {'code', 'boundary', 'retry'});
        if (!mcpDomainCodes.contains(error['code']) ||
            !const {
              'local',
              'remote',
              'executor',
            }.contains(error['boundary']) ||
            !const {
              'none',
              'reload',
              'reconnect',
              'retry-same-request',
              'manual-recovery',
            }.contains(error['retry']))
          _invalid();
        if (result.containsKey('requestId')) requireUuid(result['requestId']);
      } else {
        _invalid();
      }
      if (value['isError'] is! bool ||
          value['isError'] != (result['ok'] == false))
        _invalid();
      final content = value['content'];
      if (content is! List || content.length != 1) _invalid();
      final text = _object(content.single);
      requireFields(text, {'type', 'text'});
      if (text['type'] != 'text' ||
          text['text'] is! String ||
          !_equal(
            StrictCodec().decode(
              utf8.encode(text['text'] as String),
              maxBytes: mcpMaxToolResultBytes,
            ),
            result,
          ))
        _invalid();
      return McpToolResult._(bytes);
    } catch (_) {
      _invalid();
    }
  }
  final List<int> _bytes;
  Map<String, Object?> toJson() =>
      StrictCodec().decode(_bytes, maxBytes: mcpMaxToolResultBytes);
}

enum McpInvokeReplyKind { catalog, pending, done, invalidParams, cancelled }

final class McpInvokeReply {
  McpInvokeReply._(this.kind, this._bytes);
  factory McpInvokeReply.catalog(Iterable<McpToolDefinition> definitions) =>
      McpInvokeReply.fromJson({
        'tools': definitions.map((d) => d.toJson()).toList(),
      });
  factory McpInvokeReply.pending(String id) =>
      McpInvokeReply.fromJson({'done': false, 'operationId': id});
  factory McpInvokeReply.done(McpToolResult result) =>
      McpInvokeReply.fromJson({'done': true, 'result': result.toJson()});
  factory McpInvokeReply.invalidParams() => McpInvokeReply.fromJson({
    'done': true,
    'protocolError': {'code': -32602},
  });
  factory McpInvokeReply.cancelled() =>
      McpInvokeReply.fromJson({'cancelled': true});
  factory McpInvokeReply.fromJson(Object? raw) {
    try {
      final bytes = _encode(_object(raw), mcpMaxResponseBytes - 2048);
      final value = StrictCodec().decode(bytes, maxBytes: mcpMaxResponseBytes);
      _encode({'result': value}, mcpMaxResponseBytes);
      late final McpInvokeReplyKind kind;
      if (value.containsKey('tools')) {
        requireFields(value, {'tools'});
        final tools = value['tools'];
        if (tools is! List || tools.length > 24) _invalid();
        final names = <String>{};
        for (final raw in tools) {
          final tool = _object(raw);
          final name = tool['name'];
          if (name is! String || !names.add(name)) _invalid();
          final expected = mcpTool(name);
          if (expected == null || !_equal(tool, expected.toJson())) _invalid();
        }
        kind = McpInvokeReplyKind.catalog;
      } else if (value['done'] == false) {
        requireFields(value, {'done', 'operationId'});
        requireUuid(value['operationId']);
        kind = McpInvokeReplyKind.pending;
      } else if (value['done'] == true) {
        if (value.containsKey('protocolError')) {
          requireFields(value, {'done', 'protocolError'});
          final error = _object(value['protocolError']);
          requireFields(error, {'code'});
          if (error['code'] is! int || error['code'] != -32602) _invalid();
          kind = McpInvokeReplyKind.invalidParams;
        } else {
          requireFields(value, {'done', 'result'});
          McpToolResult.fromJson(value['result']);
          kind = McpInvokeReplyKind.done;
        }
      } else {
        requireFields(value, {'cancelled'});
        if (value['cancelled'] != true) _invalid();
        kind = McpInvokeReplyKind.cancelled;
      }
      return McpInvokeReply._(kind, bytes);
    } catch (_) {
      _invalid();
    }
  }
  final McpInvokeReplyKind kind;
  final List<int> _bytes;
  Map<String, Object?> toJson() =>
      StrictCodec().decode(_bytes, maxBytes: mcpMaxResponseBytes);
}
