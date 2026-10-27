import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../codec.dart';
import '../validation.dart';
import 'values.dart';

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) invalidAutomationValue();
  return value;
}

String _text(Object? value, {int min = 0, int max = 4096}) {
  final result = automationText(value, min: min, max: max, multiline: true);
  if (['{{', '{%', '{#'].any(result.contains)) invalidAutomationValue();
  return result;
}

int _integer(Object? value, int min, int max) {
  if (value is! int || value < min || value > max) invalidAutomationValue();
  return value;
}

/// Trusted field schemas. Target ownership, registry digests, installed recipes,
/// memory budgets and recipe/resource conflicts still require remote preflight.
final class _Field {
  const _Field.integer(this.minimum, this.maximum)
    : type = 'integer',
      values = null;
  const _Field.text({this.minimum = 0, this.maximum = 4096, this.values})
    : type = 'string';
  const _Field.boolean()
    : type = 'boolean',
      minimum = 0,
      maximum = 0,
      values = null;
  final String type;
  final int minimum, maximum;
  final Set<String>? values;

  Object validate(Object? value) {
    switch (type) {
      case 'integer':
        return _integer(value, minimum, maximum);
      case 'boolean':
        if (value is! bool) invalidAutomationValue();
        return value;
      default:
        final text = _text(value, min: minimum, max: maximum);
        if (values != null && !values!.contains(text)) invalidAutomationValue();
        return text;
    }
  }

  void accepts(_Parameter parameter) {
    if (parameter.type == 'enum') {
      for (final value in parameter.values!) {
        validate(value);
      }
    } else if (type != parameter.type ||
        (type == 'integer' &&
            (parameter.minimum < minimum || parameter.maximum > maximum)) ||
        (type == 'string' &&
            (minimum != 0 || values != null || parameter.maximum > maximum))) {
      invalidAutomationValue();
    }
  }
}

final class _Parameter {
  _Parameter(
    this.type,
    this.defaultValue,
    this.minimum,
    this.maximum,
    this.values,
  );
  factory _Parameter.parse(Object? raw) {
    final value = _object(raw);
    final type = value['type'];
    switch (type) {
      case 'boolean':
        requireFields(value, {'type', 'default'});
        final result = const _Field.boolean().validate(value['default']);
        return _Parameter('boolean', result, 0, 0, null);
      case 'integer':
        requireFields(value, {'type', 'minimum', 'maximum', 'default'});
        final min = _integer(value['minimum'], 0, 1000000);
        final max = _integer(value['maximum'], min, 1000000);
        return _Parameter(
          'integer',
          _integer(value['default'], min, max),
          min,
          max,
          null,
        );
      case 'enum':
        requireFields(value, {'type', 'values', 'default'});
        final rawValues = value['values'];
        if (rawValues is! List || rawValues.isEmpty || rawValues.length > 32)
          invalidAutomationValue();
        final values = rawValues.map((v) => _text(v, min: 1, max: 64)).toSet();
        if (values.length != rawValues.length ||
            !values.contains(value['default']))
          invalidAutomationValue();
        return _Parameter(
          'enum',
          value['default'] as String,
          0,
          64,
          Set.unmodifiable(values),
        );
      case 'string':
        requireFields(value, {'type', 'maxLength', 'default'});
        final max = _integer(value['maxLength'], 1, 4096);
        return _Parameter(
          'string',
          _text(value['default'], max: max),
          0,
          max,
          null,
        );
      default:
        invalidAutomationValue();
    }
  }
  final String type;
  final Object defaultValue;
  final int minimum, maximum;
  final Set<String>? values;

  Object validate(Object? value) {
    if (type == 'enum') {
      if (value is! String || !values!.contains(value))
        invalidAutomationValue();
      return value;
    }
    final field = switch (type) {
      'integer' => _Field.integer(minimum, maximum),
      'boolean' => const _Field.boolean(),
      _ => _Field.text(maximum: maximum),
    };
    return field.validate(value);
  }
}

const _configFields = <String, Map<String, _Field>>{
  'system.motd': {'text': _Field.text()},
  'postgresql.settings': {
    'max_connections': _Field.integer(10, 1000),
    'shared_buffers_mb': _Field.integer(16, 16384),
  },
  'clickhouse.settings': {
    'max_connections': _Field.integer(10, 10000),
    'max_server_memory_usage_mb': _Field.integer(128, 1048576),
  },
};
const _serviceState = _Field.text(
  minimum: 1,
  maximum: 9,
  values: {'started', 'stopped', 'restarted'},
);

/// Validated format1 AST, containing no executable YAML or caller code.
/// The snapshot is private canonical JSON; every public result is a fresh copy.
final class AutomationBody {
  AutomationBody._(this._canonical, this._parameters);
  factory AutomationBody.fromJson(Map<String, Object?> input) {
    late final List<int> bytes;
    try {
      bytes = StrictCodec().encode(input, maxBytes: 128 * 1024);
    } on FormatException {
      invalidAutomationValue();
    }
    final copy = StrictCodec().decode(bytes, maxBytes: 128 * 1024);
    // Validate original strings before canonicalization can normalize them.
    _checkTree(input, 0);
    requireFields(copy, {'format', 'environment', 'parameters', 'steps'});
    if (copy['format'] is! int ||
        copy['format'] != 1 ||
        copy['environment'] != 'ubuntu24.04-amd64-systemd')
      invalidAutomationValue();
    final definitions = _object(copy['parameters']);
    if (definitions.length > 32) invalidAutomationValue();
    final parameters = <String, _Parameter>{};
    for (final entry in definitions.entries) {
      parameters[automationIdentifier(entry.key)] = _Parameter.parse(
        entry.value,
      );
    }
    final steps = copy['steps'];
    if (steps is! List || steps.length > 32) invalidAutomationValue();
    final ids = <String>{}, resources = <String>{};
    for (final raw in steps) {
      final step = _object(raw);
      if (!ids.add(automationIdentifier(step['id']))) invalidAutomationValue();
      switch (step['kind']) {
        case 'service':
          requireFields(
            step,
            {'id', 'kind', 'resourceId', 'state'},
            {'enabled'},
          );
          final resource = step['resourceId'];
          if (!const {
                'postgresql.service',
                'clickhouse.service',
              }.contains(resource) ||
              !resources.add(resource as String))
            invalidAutomationValue();
          _binding(step['state'], _serviceState, parameters);
          if (step.containsKey('enabled'))
            _binding(step['enabled'], const _Field.boolean(), parameters);
        case 'config_file':
          requireFields(step, {'id', 'kind', 'resourceId', 'values'});
          final resource = step['resourceId'];
          final fields = _configFields[resource];
          if (fields == null || !resources.add(resource as String))
            invalidAutomationValue();
          final values = _object(step['values']);
          requireFields(values, fields.keys.toSet());
          for (final entry in fields.entries) {
            _binding(values[entry.key], entry.value, parameters);
          }
        case 'install_recipe':
          requireFields(step, {'id', 'kind', 'recipeDigest', 'version'});
          final digest = step['recipeDigest'];
          if (digest is! String ||
              !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
              !resources.add('recipe:$digest'))
            invalidAutomationValue();
          _binding(
            step['version'],
            const _Field.text(minimum: 1, maximum: 256),
            parameters,
          );
        default:
          invalidAutomationValue();
      }
    }
    return AutomationBody._(utf8.decode(bytes), Map.unmodifiable(parameters));
  }

  final String _canonical;
  final Map<String, _Parameter> _parameters;
  Map<String, Object?> toJson() =>
      jsonDecode(_canonical) as Map<String, Object?>;

  Future<String> digest() async {
    final hash = await Sha256().hash(utf8.encode(_canonical));
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Map<String, Object?> resolveParameters(Map<String, Object?> input) {
    if (input.keys.any((key) => !_parameters.containsKey(key)))
      invalidAutomationValue();
    return {
      for (final entry in _parameters.entries)
        entry.key: input.containsKey(entry.key)
            ? entry.value.validate(input[entry.key])
            : entry.value.defaultValue,
    };
  }

  List<Map<String, Object?>> resolveSteps(Map<String, Object?> input) {
    final parameters = resolveParameters(input);
    Object? resolve(Object? value) {
      if (value is Map<String, Object?>) {
        if (value.keys.length == 1 && value.containsKey('param'))
          return parameters[value['param']];
        return value.map((key, child) => MapEntry(key, resolve(child)));
      }
      if (value is List) return value.map(resolve).toList();
      return value;
    }

    return (toJson()['steps'] as List)
        .map((s) => resolve(s) as Map<String, Object?>)
        .toList();
  }
}

void _binding(Object? value, _Field field, Map<String, _Parameter> parameters) {
  if (value is Map<String, Object?>) {
    requireFields(value, {'param'});
    final name = automationIdentifier(value['param']);
    final definition = parameters[name];
    if (definition == null) invalidAutomationValue();
    field.accepts(definition);
  } else {
    field.validate(value);
  }
}

void _checkTree(Object? value, int depth) {
  if (depth > 12) invalidAutomationValue();
  if (value is String) {
    // Whole-document byte limit applies; each field has its own tighter limit.
    _text(value, max: 128 * 1024);
  } else if (value is Map<String, Object?>) {
    for (final entry in value.entries) {
      _text(entry.key, max: 128 * 1024);
      _checkTree(entry.value, depth + 1);
    }
  } else if (value is List) {
    for (final child in value) {
      _checkTree(child, depth + 1);
    }
  }
}
