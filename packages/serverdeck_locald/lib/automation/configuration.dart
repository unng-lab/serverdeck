import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:serverdeck_protocol/automation/configuration_view.dart';
import 'package:serverdeck_protocol/automation/models.dart';

import 'compiler.dart';
import 'snapshot.dart';

/// Compares only a last successful immutable intent with an actual typed
/// observation. It never observes another source, rebases a plan or repairs.
Map<String, Object?> configurationView({
  required AutomationSnapshot graph,
  required ManagedResourceObservationRecord observation,
  required DateTime at,
}) {
  final desired = graph.desired.values
      .where(
        (row) =>
            row.serverId == observation.serverId &&
            row.resourceId == observation.resourceId,
      )
      .firstOrNull;
  final differences = <Map<String, Object?>>[];
  var status = 'unmanaged', basis = 'none', reason = 'no-desired';
  Map<String, Object?>? expected;
  DateTime? confirmedAt;
  if (desired != null) {
    final job = graph.jobs[desired.lastJobId]!,
        plan = graph.plans[job.immutablePlanId]!;
    confirmedAt = job.updatedAt;
    final effects = (plan.toJson()['effects'] as List)
        .cast<Map<String, Object?>>();
    final config = effects
        .where(
          (row) =>
              row['resourceId'] == observation.resourceId &&
              row['kind'] == 'config_file',
        )
        .firstOrNull;
    if (config != null) {
      basis = 'file';
      final values = Map<String, Object?>.of(
        config['values'] as Map<String, Object?>,
      );
      if (observation.resourceId == 'system.motd')
        values['text'] = renderedConfiguration(observation.resourceId, values);
      expected = {
        'kind': 'config_file',
        'fileDigest': config['renderedDigest'],
        'values': values,
      };
    } else {
      final services = effects
          .where(
            (row) =>
                row['resourceId'] == observation.resourceId &&
                const {
                  'service_state',
                  'service_enabled',
                }.contains(row['kind']),
          )
          .toList();
      if (services.isNotEmpty) {
        basis = 'service';
        final state = services
            .where((row) => row['kind'] == 'service_state')
            .firstOrNull;
        final enabled = services
            .where((row) => row['kind'] == 'service_enabled')
            .firstOrNull;
        expected = {
          'kind': 'service',
          'activeState': state == null
              ? null
              : state['state'] == 'stopped'
              ? 'inactive'
              : 'active',
          'unitFileState': enabled == null
              ? null
              : enabled['enabled'] == true
              ? 'enabled'
              : 'disabled',
        };
      } else {
        final recipe = plan.preflight!.recipes.singleWhere(
          (row) => row.ownedResources.contains(observation.resourceId),
        );
        basis = 'recipe';
        expected = {
          'kind': 'recipe',
          'id': recipe.id,
          'version': recipe.version,
          'recipeDigest': recipe.digest,
        };
        final initial = recipe.initialSettings;
        if (initial != null) {
          if (observation.resourceId.endsWith('.settings')) {
            basis = 'file';
            final rendered = renderedConfiguration(
              observation.resourceId,
              initial,
            );
            final hash = const DartSha256()
                .hashSync(utf8.encode(rendered))
                .bytes
                .map((value) => value.toRadixString(16).padLeft(2, '0'))
                .join();
            expected = {
              'kind': 'config_file',
              'fileDigest': hash,
              'values': initial,
            };
          } else {
            basis = 'service';
            expected = {
              'kind': 'service',
              'activeState': 'active',
              'unitFileState': 'enabled',
            };
          }
        }
      }
    }
    status = 'unknown';
    reason = 'observation-unavailable';
    if (observation.hostId != null &&
        (observation.hostId != plan.hostId ||
            observation.resourceRegistryDigest != plan.registryDigest ||
            observation.targetRevision != plan.serverRevision ||
            observation.connectionRevision != plan.connectionRevision ||
            observation.accessRevision != plan.accessRevision ||
            observation.trustRevision != plan.trustRevision)) {
      reason = 'target-changed';
    } else if (observation.status == 'stale' ||
        observation.status == 'known' && !observation.isFreshAt(at)) {
      status = 'stale';
      reason = 'stale-observation';
    } else if (observation.status == 'known') {
      final facts = observation.toJson()['value'] as Map<String, Object?>;
      void compare(String field, Object? wanted, Object? actual) {
        if (wanted != actual)
          differences.add({
            'field': field,
            'desired': wanted,
            'observed': actual,
          });
      }

      if (basis == 'file') {
        compare('exists', true, facts['exists']);
        compare('fileDigest', expected['fileDigest'], facts['fileDigest']);
        final actual = facts['values'] as Map<String, Object?>?;
        for (final field
            in (expected['values'] as Map<String, Object?>).entries)
          compare(field.key, field.value, actual?[field.key]);
      } else if (basis == 'service') {
        for (final field in ['activeState', 'unitFileState'])
          if (expected[field] != null)
            compare(field, expected[field], facts[field]);
      } else {
        // Recipe installation observations must come from its qualified fixed
        // defaults/evidence, not guessed package or configuration values.
        reason = 'recipe-evidence';
      }
      if (basis != 'recipe') {
        status = differences.isEmpty ? 'matched' : 'drift';
        reason = 'none';
      }
    }
  }
  return captureConfigurationView({
    'serverId': observation.serverId,
    'observation': observation.toJson(),
    'desired': desired?.toJson(),
    'expected': expected,
    'comparison': {
      'status': status,
      'basis': basis,
      'reason': reason,
      'observedAt': const {'known', 'stale'}.contains(observation.status)
          ? observation.observedAt.toIso8601String()
          : null,
      'confirmedAt': confirmedAt?.toIso8601String(),
      'comparedAt': at.toIso8601String(),
      'differences': differences,
    },
  });
}
