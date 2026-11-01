import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:serverdeck_protocol/automation/profile_body.dart';
import 'package:serverdeck_protocol/automation/plan_records.dart';

/// Deterministic program only. Live authorization, actual root preflight and
/// qualified release/catalog verification remain the admission service's job.
final class CompiledAutomation {
  CompiledAutomation._(this._json);
  final String _json;
  Map<String, Object?> toJson() => jsonDecode(_json) as Map<String, Object?>;
}

String renderedConfiguration(
  String resource,
  Map<String, Object?> values,
) => switch (resource) {
  'system.motd' =>
    '${(values['text'] as String).replaceFirst(RegExp(r'\n+$'), '')}\n',
  'postgresql.settings' =>
    'max_connections = ${values['max_connections']}\n'
        "shared_buffers = '${values['shared_buffers_mb']}MB'\n",
  'clickhouse.settings' =>
    '<clickhouse>\n'
        '  <max_connections>${values['max_connections']}</max_connections>\n'
        '  <max_server_memory_usage>${(values['max_server_memory_usage_mb'] as int) * 1024 * 1024}</max_server_memory_usage>\n'
        '</clickhouse>\n',
  _ => throw const FormatException('VALIDATION'),
};

String _sha(String value) => const DartSha256()
    .hashSync(utf8.encode(value))
    .bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();

String _fingerprint(Map<String, String> baseline, String resource) {
  final value = baseline[resource];
  if (value == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value))
    throw StateError('PREFLIGHT_FAILED');
  return value;
}

CompiledAutomation compileAutomation({
  required AutomationBody body,
  required Map<String, Object?> parameters,
  required Map<String, String> baselineFingerprints,
  required Map<String, QualifiedRecipeDescriptor> qualifiedRecipes,
}) {
  final exact = body.resolveParameters(parameters);
  final desired = body.resolveSteps(exact);
  final effects = <Map<String, Object?>>[], checks = <Map<String, Object?>>[];
  final occupied = <String>{};
  Map<String, Object?> effect(
    String source,
    String kind,
    Map<String, Object?> fields,
  ) {
    if (effects.length >= 32) throw StateError('RESOURCE_LIMIT');
    final value = <String, Object?>{
      'id': 'e${effects.length + 1}',
      'sourceStepId': source,
      'kind': kind,
      ...fields,
    };
    effects.add(value);
    return value;
  }

  void check(
    Map<String, Object?> effect,
    String kind,
    Map<String, Object?> fields, {
    String? resource,
  }) {
    checks.add({
      'id': 'c${checks.length + 1}',
      'effectId': effect['id'],
      'resourceId': resource ?? effect['resourceId'],
      'kind': kind,
      ...fields,
    });
  }

  void service(String source, String resource, String state) {
    final baseline = _fingerprint(baselineFingerprints, resource);
    final item = effect(source, 'service_state', {
      'resourceId': resource,
      'state': state,
    });
    check(item, 'service_state', {
      'state': state == 'stopped' ? 'inactive' : 'active',
    });
    if (state == 'restarted')
      check(item, 'service_restarted', {'baselineFingerprint': baseline});
    if (state != 'stopped') check(item, 'sql', {'expected': 1});
  }

  for (final step in desired) {
    final source = step['id'] as String, kind = step['kind'] as String;
    if (kind == 'install_recipe') {
      final recipe = qualifiedRecipes[step['recipeDigest']];
      if (recipe == null || recipe.version != step['version'])
        throw StateError('QUALIFICATION_REQUIRED');
      if (recipe.ownedResources.any(occupied.contains))
        throw const FormatException('VALIDATION');
      occupied.addAll(recipe.ownedResources);
      final item = effect(source, kind, {
        'recipeDigest': recipe.digest,
        'version': recipe.version,
      });
      check(item, 'recipe', {
        'recipeDigest': recipe.digest,
      }, resource: 'recipe.${recipe.id}');
      continue;
    }
    final resource = step['resourceId'] as String;
    if (!occupied.add(resource)) throw const FormatException('VALIDATION');
    _fingerprint(baselineFingerprints, resource);
    if (kind == 'config_file') {
      final values = step['values'] as Map<String, Object?>;
      final rendered = _sha(renderedConfiguration(resource, values));
      final item = effect(source, kind, {
        'resourceId': resource,
        'values': values,
        'renderedDigest': rendered,
      });
      check(item, 'file_digest', {'digest': rendered});
      if (resource != 'system.motd') {
        check(item, 'settings', {'values': values});
        service(
          source,
          resource.replaceFirst('.settings', '.service'),
          'restarted',
        );
      }
    } else {
      service(source, resource, step['state'] as String);
      if (step.containsKey('enabled')) {
        final item = effect(source, 'service_enabled', {
          'resourceId': resource,
          'enabled': step['enabled'],
        });
        check(item, 'service_enabled', {'enabled': step['enabled']});
      }
    }
  }
  return CompiledAutomation._(
    jsonEncode({
      'parameters': exact,
      'desired': desired,
      'effects': effects,
      'checks': checks,
    }),
  );
}
