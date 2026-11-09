import 'dart:convert';

import 'package:flutter/services.dart';

final class SchemaFailure implements Exception {
  const SchemaFailure(this.path);
  final String path;
}

final class ToolSchemas {
  ToolSchemas(Map<String, dynamic> registry)
    : tools = List<Map<String, dynamic>>.from(registry['tools'] as List) {
    if (tools.length != names.length ||
        tools.map((t) => t['name']).toSet().length != names.length ||
        tools.map((t) => t['name']).toSet().difference(names).isNotEmpty)
      throw StateError('Invalid bundled tool registry');
  }
  static const names = {
    'profiles.list',
    'profiles.get',
    'profiles.create',
    'profiles.update',
    'connections.connect',
    'connections.get',
    'connections.provide_passphrase',
    'connections.cancel',
    'connections.disconnect',
    'trust.get',
    'trust.accept',
    'trust.replace',
    'trust.retain',
    'console.profiles',
    'console.list',
    'console.open',
    'console.read',
    'console.acquire',
    'console.release',
    'console.write',
    'console.close',
    'software.list',
    'software.get',
    'software.save',
    'software.delete',
    'software.history.list',
    'software.history.add',
  };
  final List<Map<String, dynamic>> tools;
  static Future<ToolSchemas> load() async => ToolSchemas(
    jsonDecode(await rootBundle.loadString('assets/mcp/tools.json'))
        as Map<String, dynamic>,
  );
  Map<String, dynamic> tool(String name) =>
      tools.firstWhere((t) => t['name'] == name);
  Map<String, dynamic> arguments(String name, Map<String, dynamic> input) {
    final schema = tool(name)['inputSchema'] as Map<String, dynamic>;
    if (name.startsWith('software.')) {
      for (final field in ['limit', 'expectedRevision']) {
        if (input.containsKey(field) && input[field] is! int)
          _bad(r'$.' + field);
      }
    }
    _check(input, schema, schema, r'$', 0);
    if (name.startsWith('software.')) return input;
    return _integers(input) as Map<String, dynamic>;
  }

  void output(String name, Map<String, Object?> value) {
    final s = tool(name)['outputSchema'] as Map<String, dynamic>;
    _check(value, s, s, r'$', 0);
  }

  Object? _integers(Object? value) {
    if (value is double && value.isFinite && value == value.truncateToDouble())
      return value.toInt();
    if (value is Map)
      return value.map((k, v) => MapEntry(k as String, _integers(v)));
    if (value is List) return value.map(_integers).toList();
    return value;
  }

  Never _bad(String path) =>
      throw SchemaFailure(path.length > 128 ? r'$' : path);
  void _check(
    Object? v,
    Object? raw,
    Map<String, dynamic> root,
    String path,
    int depth,
  ) {
    if (depth > 40) _bad(path);
    if (raw == true) return;
    if (raw == false) _bad(path);
    final s = raw as Map<String, dynamic>;
    if (s.containsKey(r'$ref')) {
      final ref = s[r'$ref'] as String;
      if (!ref.startsWith('#/\u0024defs/')) _bad(path);
      _check(
        v,
        (root[r'$defs'] as Map)[ref.substring(8)],
        root,
        path,
        depth + 1,
      );
      return;
    }
    for (final key in ['oneOf', 'anyOf']) {
      if (s.containsKey(key)) {
        var matches = 0;
        for (final option in s[key] as List) {
          try {
            _check(v, option, root, path, depth + 1);
            matches++;
          } on SchemaFailure {}
        }
        if (matches == 0 || (key == 'oneOf' && matches != 1)) _bad(path);
      }
    }
    if (s.containsKey('const') && v != s['const']) _bad(path);
    if (s.containsKey('enum') && !(s['enum'] as List).contains(v)) _bad(path);
    final type = s['type'];
    bool isType(String t) => switch (t) {
      'object' => v is Map,
      'array' => v is List,
      'string' => v is String,
      'boolean' => v is bool,
      'null' => v == null,
      'number' => v is num && v.isFinite,
      'integer' =>
        v is num &&
            v.isFinite &&
            v == v.truncateToDouble() &&
            v.abs() <= 9007199254740991,
      _ => false,
    };
    if (type is String && !isType(type)) _bad(path);
    if (type is List && !type.any((t) => isType(t as String))) _bad(path);
    if (v is String) {
      final length = v.runes.length;
      if (s['minLength'] != null && length < (s['minLength'] as num))
        _bad(path);
      if (s['maxLength'] != null && length > (s['maxLength'] as num))
        _bad(path);
      if (s['pattern'] != null && !RegExp(s['pattern'] as String).hasMatch(v))
        _bad(path);
    }
    if (v is num) {
      if (s['minimum'] != null && v < (s['minimum'] as num)) _bad(path);
      if (s['maximum'] != null && v > (s['maximum'] as num)) _bad(path);
    }
    if (v is Map) {
      final p = s['properties'] as Map? ?? const {};
      for (final key in s['required'] as List? ?? const []) {
        if (!v.containsKey(key)) _bad('$path.$key');
      }
      if (s['minProperties'] != null && v.length < (s['minProperties'] as num))
        _bad(path);
      if (s['additionalProperties'] == false &&
          v.keys.any((key) => !p.containsKey(key)))
        _bad(path);
      for (final key in v.keys) {
        if (key is! String) _bad(path);
        if (p.containsKey(key))
          _check(v[key], p[key], root, '$path.$key', depth + 1);
      }
    }
    if (v is List) {
      if (s['minItems'] != null && v.length < (s['minItems'] as num))
        _bad(path);
      if (s['maxItems'] != null && v.length > (s['maxItems'] as num))
        _bad(path);
      for (var i = 0; i < v.length; i++) {
        if (s['items'] != null)
          _check(v[i], s['items'], root, '$path[$i]', depth + 1);
      }
    }
  }
}
