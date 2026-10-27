import 'dart:convert';

import '../codec.dart';

const mcpMaxRequestBytes = 256 * 1024;
const mcpMaxResponseBytes = 8 * 1024 * 1024;
const mcpMaxSafeInteger = 9007199254740991;

/// A client request/notification, not an authorization or lifecycle decision.
final class McpInbound {
  McpInbound._(this.id, this.method, this.params, this.isNotification);

  factory McpInbound.decode(List<int> bytes) {
    late final Object? parsed;
    try {
      parsed = StrictCodec().decodeValue(bytes, maxBytes: mcpMaxRequestBytes);
    } on FormatException {
      throw const McpProtocolException(-32700);
    }
    if (parsed is! Map<String, Object?>) {
      throw const McpProtocolException(-32600);
    }
    final value = parsed;
    if (value['jsonrpc'] != '2.0' ||
        value.keys.any(
          (k) => !{'jsonrpc', 'id', 'method', 'params'}.contains(k),
        ) ||
        value['method'] is! String ||
        (value['method'] as String).isEmpty ||
        (value['method'] as String).runes.length > 256 ||
        (value.containsKey('id') && !validMcpId(value['id'])) ||
        (value.containsKey('params') &&
            value['params'] is! Map<String, Object?>)) {
      throw const McpProtocolException(-32600);
    }
    final params =
        value['params'] as Map<String, Object?>? ?? <String, Object?>{};
    return McpInbound._(
      value['id'],
      value['method'] as String,
      Map.unmodifiable(params),
      !value.containsKey('id'),
    );
  }

  final Object? id;
  final String method;
  final Map<String, Object?> params;
  final bool isNotification;
}

bool validMcpId(Object? value) =>
    (value is String && value.isNotEmpty && value.runes.length <= 100) ||
    (value is int && value >= -mcpMaxSafeInteger && value <= mcpMaxSafeInteger);

final class McpProtocolException implements Exception {
  const McpProtocolException(this.code);
  final int code;

  String get message => switch (code) {
    -32700 => 'Parse error',
    -32600 => 'Invalid request',
    -32601 => 'Method not found',
    -32602 => 'Invalid params',
    _ => 'Internal error',
  };

  Map<String, Object?> response(Object? id) => {
    'jsonrpc': '2.0',
    'id': validMcpId(id) ? id : null,
    'error': {'code': code, 'message': message},
  };

  @override
  String toString() => 'McpProtocolException($code)';
}

Map<String, Object?> mcpSuccess(Object id, Map<String, Object?> result) {
  if (!validMcpId(id)) throw const McpProtocolException(-32600);
  return {'jsonrpc': '2.0', 'id': id, 'result': result};
}

/// MCP correlation IDs and observed text must be preserved verbatim. The
/// foundation's canonical encoder deliberately normalizes text for digests and
/// must not be used to serialize the external JSON-RPC transport.
List<int> encodeMcpMessage(
  Map<String, Object?> message, {
  int maxBytes = mcpMaxResponseBytes,
}) {
  _validateWireValue(message, 0);
  final bytes = utf8.encode(jsonEncode(message));
  if (bytes.length > maxBytes) throw const McpProtocolException(-32603);
  return bytes;
}

void _validateWireValue(Object? value, int depth) {
  if (depth > 16) throw const McpProtocolException(-32603);
  if (value == null || value is bool || value is int) return;
  if (value is double && value.isFinite) return;
  if (value is String) {
    for (var i = 0; i < value.length; i++) {
      final unit = value.codeUnitAt(i);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++i >= value.length ||
            value.codeUnitAt(i) < 0xdc00 ||
            value.codeUnitAt(i) > 0xdfff) {
          throw const McpProtocolException(-32603);
        }
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        throw const McpProtocolException(-32603);
      }
    }
    return;
  }
  if (value is Map<String, Object?>) {
    for (final entry in value.entries) {
      _validateWireValue(entry.key, depth + 1);
      _validateWireValue(entry.value, depth + 1);
    }
    return;
  }
  if (value is List) {
    for (final item in value) {
      _validateWireValue(item, depth + 1);
    }
    return;
  }
  throw const McpProtocolException(-32603);
}
