import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../codec.dart';
import '../validation.dart';
import 'models.dart' show AutomationRevisionKey, requireAutomationRevision;
import 'job_records.dart' show automationSafeCodes;
import 'observation_records.dart';
import 'profile_records.dart';
import 'values.dart';

/// Public catalog metadata, not a qualification certificate. Trusted runtime
/// membership, package signatures, compiler/probes and actual host evidence
/// must be checked separately before any recipe can be executed.
final class QualifiedRecipeDescriptor {
  QualifiedRecipeDescriptor._(
    this._json,
    this.id,
    this.version,
    this.revision,
    this.digest,
    List<String> ownedResources,
    List<String> aptIndexDigests,
  ) : ownedResources = List.unmodifiable(ownedResources),
      aptIndexDigests = List.unmodifiable(aptIndexDigests);

  static Future<QualifiedRecipeDescriptor> fromJson(
    Map<String, Object?> input,
  ) async {
    // Make a private, verbatim snapshot before any await. Canonicalization
    // validates Unicode/depth/types; field validation separately rejects NFC
    // and executable-text violations instead of silently normalizing them.
    StrictCodec().canonical(input);
    final json = jsonEncode(input);
    if (utf8.encode(json).length > 128 * 1024) invalidAutomationValue();
    final value = jsonDecode(json) as Map<String, Object?>;
    requireFields(value, {
      'format',
      'id',
      'version',
      'revision',
      'digest',
      'environment',
      'packagePins',
      'dependencyTransactionDigest',
      'repositoryFingerprints',
      'aptIndexDigests',
      'expectedAbsentPaths',
      'ownedResources',
      'prechecks',
      'postchecks',
      'licenseNotices',
    });
    if (value['format'] is! int ||
        value['format'] != 1 ||
        !const {'postgresql16', 'clickhouse'}.contains(value['id']) ||
        value['environment'] != 'ubuntu24.04-amd64-systemd') {
      invalidAutomationValue();
    }
    final id = value['id'] as String;
    final version = _version(value['version']);
    final revision = requireAutomationRevision(value['revision']);
    final digest = _digest(value['digest']);
    _digest(value['dependencyTransactionDigest']);
    final pins = _list(value['packagePins'], min: 1, max: 256);
    final pinKeys = <String>{};
    for (final raw in pins) {
      if (raw is! Map<String, Object?>) invalidAutomationValue();
      requireFields(raw, {'name', 'architecture', 'version', 'sha256'});
      final name = raw['name'];
      final architecture = raw['architecture'];
      if (name is! String ||
          !RegExp(r'^[a-z0-9][a-z0-9+.-]{0,127}$').hasMatch(name) ||
          !const {'amd64', 'all'}.contains(architecture) ||
          !pinKeys.add('$name:$architecture'))
        invalidAutomationValue();
      _version(raw['version']);
      _digest(raw['sha256']);
    }
    _uniqueStrings(value['repositoryFingerprints'], 1, 16, (raw) {
      if (raw is! String ||
          !RegExp(r'^(?:[a-f0-9]{40}|[a-f0-9]{64})$').hasMatch(raw)) {
        invalidAutomationValue();
      }
      return raw;
    });
    final indexes = _uniqueStrings(value['aptIndexDigests'], 1, 64, _digest);
    _uniqueStrings(value['expectedAbsentPaths'], 1, 32, (raw) {
      final path = _public(raw, max: 256);
      if (!path.startsWith('/') ||
          path.contains('\\') ||
          path
              .substring(1)
              .split('/')
              .any((part) => part.isEmpty || part == '.' || part == '..'))
        invalidAutomationValue();
      return path;
    });
    final resources = _uniqueStrings(value['ownedResources'], 2, 2, (raw) {
      if (raw is! String) invalidAutomationValue();
      return raw;
    });
    final prefix = id == 'postgresql16' ? 'postgresql' : 'clickhouse';
    if (!resources.toSet().containsAll({
      '$prefix.service',
      '$prefix.settings',
    })) {
      invalidAutomationValue();
    }
    for (final field in ['prechecks', 'postchecks']) {
      _uniqueStrings(value[field], 1, 32, automationIdentifier);
    }
    for (final notice in _list(value['licenseNotices'], min: 1, max: 16)) {
      _public(notice, max: 2000, multiline: true);
    }
    final hashInput = Map<String, Object?>.of(value)..remove('digest');
    final hash = await Sha256().hash(StrictCodec().canonical(hashInput));
    final computed = hash.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    if (computed != digest) invalidAutomationValue();
    return QualifiedRecipeDescriptor._(
      json,
      id,
      version,
      revision,
      digest,
      resources,
      indexes,
    );
  }

  final String _json;
  final String id, version, digest;
  final int revision;
  final List<String> ownedResources, aptIndexDigests;

  Map<String, Object?> toJson() => jsonDecode(_json) as Map<String, Object?>;

  /// Structural selection equality only. Does not qualify a caller's recipe.
  bool matchesSelection({
    required String recipeDigest,
    required String version,
  }) => digest == recipeDigest && this.version == version;
}

String _public(Object? value, {int max = 256, bool multiline = false}) {
  final text = automationText(value, min: 1, max: max, multiline: multiline);
  if (['{{', '{%', '{#'].any(text.contains)) invalidAutomationValue();
  return text;
}

String _version(Object? value) {
  final text = _public(value);
  if (text.toLowerCase() == 'latest') invalidAutomationValue();
  return text;
}

String _digest(Object? value) {
  if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    invalidAutomationValue();
  }
  return value;
}

List<Object?> _list(Object? value, {required int min, required int max}) {
  if (value is! List || value.length < min || value.length > max) {
    invalidAutomationValue();
  }
  return value;
}

List<String> _uniqueStrings(
  Object? value,
  int min,
  int max,
  String Function(Object?) validate,
) {
  final list = _list(value, min: min, max: max).map(validate).toList();
  if (list.toSet().length != list.length) invalidAutomationValue();
  return list;
}

Map<String, Object?> _object(Object? value) =>
    value is Map<String, Object?> ? value : invalidAutomationValue();

Map<String, Object?> _snapshot(Map<String, Object?> value) {
  StrictCodec().canonical(value);
  final json = jsonEncode(value);
  if (utf8.encode(json).length > 256 * 1024) invalidAutomationValue();
  return jsonDecode(json) as Map<String, Object?>;
}

Future<String> _hash(Object? value) async {
  final hash = await Sha256().hash(StrictCodec().canonical(value));
  return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

// Exact value equality: canonical digest normalization must not silently accept
// differently spelled executable text. Objects are unordered; arrays ordered.
bool _same(Object? left, Object? right) {
  if (left is Map<String, Object?> && right is Map<String, Object?>) {
    return left.length == right.length &&
        left.keys.every(
          (key) => right.containsKey(key) && _same(left[key], right[key]),
        );
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (!_same(left[i], right[i])) return false;
    }
    return true;
  }
  return left == right;
}

Map<String, String> _baselines(Object? value) {
  final result = <String, String>{};
  for (final raw in _list(value, min: 0, max: 5)) {
    final item = _object(raw);
    requireFields(item, {'resourceId', 'fingerprint'});
    final resource = item['resourceId'];
    if (resource is! String ||
        !managedResourceIds.contains(resource) ||
        result.containsKey(resource))
      invalidAutomationValue();
    result[resource] = _digest(item['fingerprint']);
  }
  return result;
}

/// Immutable structural preflight metadata. Actual baseline evidence remains
/// in the executor's durable cache/receipt; a caller's hashes do not attest it.
final class AutomationPreflightCapsule {
  AutomationPreflightCapsule._(
    this._json,
    this.operationId,
    this.hostId,
    this.profileDigest,
    this.inputDigest,
    this.registryDigest,
    this.digest,
    List<QualifiedRecipeDescriptor> recipes,
    Map<String, String> baselines,
  ) : recipes = List.unmodifiable(recipes),
      baseObservations = Map.unmodifiable(baselines);

  static Future<AutomationPreflightCapsule> fromJson(
    Map<String, Object?> input,
  ) async {
    final value = _snapshot(input);
    requireFields(value, {
      'format',
      'operationId',
      'hostId',
      'environment',
      'profileDigest',
      'inputDigest',
      'runtimeVersion',
      'runtimeLockDigest',
      'compilerDigest',
      'registryDigest',
      'bootIdHash',
      'packageSnapshotDigest',
      'expectedPackageSnapshotDigest',
      'netbirdSnapshotDigest',
      'aptIndexDigests',
      'recipes',
      'baseObservations',
    });
    if (value['format'] is! int ||
        value['format'] != 1 ||
        value['environment'] != 'ubuntu24.04-amd64-systemd') {
      invalidAutomationValue();
    }
    final operation = requireUuid(value['operationId']);
    final host = requireUuid(value['hostId']);
    for (final field in [
      'profileDigest',
      'inputDigest',
      'runtimeLockDigest',
      'compilerDigest',
      'registryDigest',
      'bootIdHash',
      'packageSnapshotDigest',
      'expectedPackageSnapshotDigest',
      'netbirdSnapshotDigest',
    ]) {
      _digest(value[field]);
    }
    _public(value['runtimeVersion'], max: 100);
    final indexes = _uniqueStrings(
      value['aptIndexDigests'],
      0,
      64,
      _digest,
    ).toSet();
    final baselines = _baselines(value['baseObservations']);
    final rawRecipes = _list(value['recipes'], min: 0, max: 2);
    final recipes = <QualifiedRecipeDescriptor>[];
    final ids = <String>{}, digests = <String>{};
    for (final raw in rawRecipes) {
      final recipe = await QualifiedRecipeDescriptor.fromJson(_object(raw));
      if (!ids.add(recipe.id) ||
          !digests.add(recipe.digest) ||
          !indexes.containsAll(recipe.aptIndexDigests))
        invalidAutomationValue();
      recipes.add(recipe);
    }
    return AutomationPreflightCapsule._(
      jsonEncode(value),
      operation,
      host,
      value['profileDigest'] as String,
      value['inputDigest'] as String,
      value['registryDigest'] as String,
      await _hash(value),
      recipes,
      baselines,
    );
  }

  final String _json;
  final String operationId,
      hostId,
      profileDigest,
      inputDigest,
      registryDigest,
      digest;
  final List<QualifiedRecipeDescriptor> recipes;
  final Map<String, String> baseObservations;
  Map<String, Object?> toJson() => jsonDecode(_json) as Map<String, Object?>;
}

/// A retained immutable plan, resolved against one exact stored revision.
/// Loading history does not check live permission, qualify a recipe/renderer,
/// trust remote facts or authorize any effect. Those are admission duties.
final class AutomationPlanRecord {
  AutomationPlanRecord._(
    this._json,
    this.key,
    this.workspaceId,
    this.id,
    this.serverId,
    this.serverRevision,
    this.connectionRevision,
    this.accessRevision,
    this.trustRevision,
    this.hostId,
    this.registryDigest,
    this.status,
    this.createdAt,
    this.expiresAt,
    this.preflight,
    Map<String, String> baselines,
  ) : baseObservations = Map.unmodifiable(baselines);

  static Future<AutomationPlanRecord> fromJson(
    Map<String, Object?> input, {
    required AutomationRevisionRecord revision,
  }) async {
    final value = _snapshot(input);
    requireFields(value, {
      'workspaceId',
      'id',
      'requestId',
      'profileId',
      'profileRevision',
      'profileDigest',
      'serverId',
      'serverRevision',
      'connectionRevision',
      'accessRevision',
      'trustRevision',
      'hostId',
      'registryDigest',
      'exactParams',
      'inputDigest',
      'desired',
      'baseObservations',
      'effects',
      'checks',
      'preflight',
      'preflightDigest',
      'status',
      'reasons',
      'createdAt',
      'expiresAt',
      'originGrantId',
      'digest',
    });
    final workspace = requireUuid(value['workspaceId']);
    final id = requireUuid(value['id']);
    requireUuid(value['requestId']);
    final server = requireUuid(value['serverId']);
    final key = AutomationRevisionKey.fromJson({
      'profileId': value['profileId'],
      'revision': value['profileRevision'],
      'bodyDigest': value['profileDigest'],
    });
    if (workspace != revision.workspaceId || key != revision.key) {
      invalidAutomationValue();
    }
    final serverRevision = requireRevision(value['serverRevision']);
    final connection = requireRevision(value['connectionRevision']);
    final access = requireRevision(value['accessRevision']);
    final trust = requireRevision(value['trustRevision']);
    if (connection != trust ||
        [connection, access, trust].any(
          (counter) => BigInt.parse(counter) > BigInt.parse(serverRevision),
        ))
      invalidAutomationValue();
    final created = automationTimestamp(value['createdAt']);
    final expires = automationTimestamp(value['expiresAt']);
    if (revision.createdAt.isAfter(created) ||
        expires.difference(created) != const Duration(minutes: 5)) {
      invalidAutomationValue();
    }
    if (value['originGrantId'] != null) requireUuid(value['originGrantId']);
    final parameters = _object(value['exactParams']);
    final resolved = revision.body.resolveParameters(parameters);
    if (!_same(parameters, resolved)) invalidAutomationValue();
    final desired = _list(value['desired'], min: 0, max: 32);
    if (!_same(desired, revision.body.resolveSteps(parameters)))
      invalidAutomationValue();
    final sourceIds = {for (final step in desired) _object(step)['id']};
    final status = value['status'];
    if (status != 'runnable' && status != 'blocked') invalidAutomationValue();
    final reasons = _list(value['reasons'], min: 0, max: 32);
    final reasonKeys = <String>{};
    for (final raw in reasons) {
      final reason = _object(raw);
      requireFields(reason, {'code', 'field', 'stepId'});
      if (!automationSafeCodes.contains(reason['code']) ||
          !const {
            'executor',
            'runtime',
            'trust',
            'recipe',
            'packages',
            'paths',
            'qualification',
            'memory',
            'step_limit',
            'observation',
          }.contains(reason['field']) ||
          (reason['stepId'] != null && !sourceIds.contains(reason['stepId'])) ||
          !reasonKeys.add(
            '${reason['code']}:${reason['field']}:${reason['stepId']}',
          )) {
        invalidAutomationValue();
      }
    }
    final effects = _list(value['effects'], min: 0, max: 32);
    final checks = _list(value['checks'], min: 0, max: 96);
    if (status == 'runnable'
        ? reasons.isNotEmpty
        : reasons.isEmpty || effects.isNotEmpty || checks.isNotEmpty) {
      invalidAutomationValue();
    }
    final baselines = _baselines(value['baseObservations']);
    final host = value['hostId'] == null ? null : requireUuid(value['hostId']);
    final registry = value['registryDigest'] == null
        ? null
        : _digest(value['registryDigest']);
    final inputDigest = _digest(value['inputDigest']);
    final planDigest = _digest(value['digest']);
    if (await _hash(parameters) != inputDigest) invalidAutomationValue();
    AutomationPreflightCapsule? preflight;
    if (value['preflight'] == null) {
      if (status == 'runnable' ||
          host != null ||
          registry != null ||
          value['preflightDigest'] != null ||
          baselines.isNotEmpty) {
        invalidAutomationValue();
      }
    } else {
      preflight = await AutomationPreflightCapsule.fromJson(
        _object(value['preflight']),
      );
      if (host != preflight.hostId ||
          registry != preflight.registryDigest ||
          key.bodyDigest != preflight.profileDigest ||
          inputDigest != preflight.inputDigest ||
          _digest(value['preflightDigest']) != preflight.digest ||
          !_same(
            value['baseObservations'],
            preflight.toJson()['baseObservations'],
          )) {
        invalidAutomationValue();
      }
      if (!desired.any((step) => _object(step)['kind'] == 'install_recipe')) {
        final facts = preflight.toJson();
        if (facts['packageSnapshotDigest'] !=
            facts['expectedPackageSnapshotDigest']) {
          invalidAutomationValue();
        }
      }
      if (status == 'runnable')
        _validateProgram(desired, effects, checks, preflight);
    }
    final hashInput = Map<String, Object?>.of(value)..remove('digest');
    if (await _hash(hashInput) != planDigest) invalidAutomationValue();
    return AutomationPlanRecord._(
      jsonEncode(value),
      key,
      workspace,
      id,
      server,
      serverRevision,
      connection,
      access,
      trust,
      host,
      registry,
      status as String,
      created,
      expires,
      preflight,
      baselines,
    );
  }

  final String _json;
  final AutomationRevisionKey key;
  final String workspaceId, id, serverId, serverRevision;
  final String connectionRevision, accessRevision, trustRevision, status;
  final String? hostId, registryDigest;
  final DateTime createdAt, expiresAt;
  final AutomationPreflightCapsule? preflight;
  final Map<String, String> baseObservations;
  Map<String, Object?> toJson() => jsonDecode(_json) as Map<String, Object?>;

  bool isWithinLifetimeAt(DateTime now) {
    requireAutomationInstant(now);
    return !now.isBefore(createdAt) && now.isBefore(expiresAt);
  }

  /// Comparison only, never current permission or factual attestation. Callers
  /// separately check plan lifetime, live target/trust and authority at launch.
  Future<void> validateCurrentObservations(
    List<ManagedResourceObservationRecord> observations, {
    required DateTime now,
  }) async {
    requireAutomationInstant(now);
    if (status != 'runnable' || observations.length > 5)
      invalidAutomationValue();
    final byResource = <String, ManagedResourceObservationRecord>{};
    for (final item in List<ManagedResourceObservationRecord>.of(
      observations,
    )) {
      if (byResource.containsKey(item.resourceId)) invalidAutomationValue();
      byResource[item.resourceId] = item;
    }
    for (final entry in baseObservations.entries) {
      final item = byResource[entry.key];
      if (item == null ||
          !item.isFreshAt(now) ||
          item.workspaceId != workspaceId ||
          item.serverId != serverId ||
          item.targetRevision != serverRevision ||
          item.connectionRevision != connectionRevision ||
          item.accessRevision != accessRevision ||
          item.trustRevision != trustRevision ||
          item.hostId != hostId ||
          item.resourceRegistryDigest != registryDigest ||
          await item.fingerprint() != entry.value) {
        invalidAutomationValue();
      }
    }
  }
}

void _validateProgram(
  List<Object?> desired,
  List<Object?> effects,
  List<Object?> checks,
  AutomationPreflightCapsule preflight,
) {
  var effectIndex = 0, checkIndex = 0;
  final effectIds = <String>{},
      checkIds = <String>{},
      selectedRecipes = <String>{};
  final owned = <String>{};
  for (final raw in desired) {
    final step = _object(raw);
    if (step['resourceId'] case final String resource) owned.add(resource);
  }
  Map<String, Object?> effect(
    Map<String, Object?> source,
    String kind,
    Map<String, Object?> fields,
  ) {
    if (effectIndex >= effects.length) invalidAutomationValue();
    final actual = _object(effects[effectIndex++]);
    final id = automationIdentifier(actual['id']);
    if (!effectIds.add(id)) invalidAutomationValue();
    final expected = {
      'id': id,
      'sourceStepId': source['id'],
      'kind': kind,
      ...fields,
    };
    if (!_same(actual, expected)) invalidAutomationValue();
    return actual;
  }

  void check(
    Map<String, Object?> effect,
    String resource,
    String kind,
    Map<String, Object?> fields,
  ) {
    if (checkIndex >= checks.length) invalidAutomationValue();
    final actual = _object(checks[checkIndex++]);
    final id = automationIdentifier(actual['id']);
    if (!checkIds.add(id) ||
        !_same(actual, {
          'id': id,
          'effectId': effect['id'],
          'resourceId': resource,
          'kind': kind,
          ...fields,
        }))
      invalidAutomationValue();
  }

  void service(Map<String, Object?> source, String resource, String state) {
    if (!preflight.baseObservations.containsKey(resource))
      invalidAutomationValue();
    final actual = effect(source, 'service_state', {
      'resourceId': resource,
      'state': state,
    });
    check(actual, resource, 'service_state', {
      'state': state == 'stopped' ? 'inactive' : 'active',
    });
    if (state == 'restarted') {
      check(actual, resource, 'service_restarted', {
        'baselineFingerprint': preflight.baseObservations[resource],
      });
    }
    if (state != 'stopped') check(actual, resource, 'sql', {'expected': 1});
  }

  for (final raw in desired) {
    final step = _object(raw);
    switch (step['kind']) {
      case 'config_file':
        final resource = step['resourceId'] as String;
        if (!preflight.baseObservations.containsKey(resource) ||
            effectIndex >= effects.length) {
          invalidAutomationValue();
        }
        final rendered = _digest(
          _object(effects[effectIndex])['renderedDigest'],
        );
        final actual = effect(step, 'config_file', {
          'resourceId': resource,
          'values': step['values'],
          'renderedDigest': rendered,
        });
        check(actual, resource, 'file_digest', {'digest': rendered});
        if (resource != 'system.motd') {
          check(actual, resource, 'settings', {'values': step['values']});
          service(
            step,
            resource.replaceFirst('.settings', '.service'),
            'restarted',
          );
        }
      case 'service':
        final resource = step['resourceId'] as String;
        service(step, resource, step['state'] as String);
        if (step.containsKey('enabled')) {
          final actual = effect(step, 'service_enabled', {
            'resourceId': resource,
            'enabled': step['enabled'],
          });
          check(actual, resource, 'service_enabled', {
            'enabled': step['enabled'],
          });
        }
      case 'install_recipe':
        final matching = preflight.recipes
            .where(
              (recipe) => recipe.matchesSelection(
                recipeDigest: step['recipeDigest'] as String,
                version: step['version'] as String,
              ),
            )
            .toList();
        if (matching.length != 1 ||
            !selectedRecipes.add(matching.single.digest)) {
          invalidAutomationValue();
        }
        final recipe = matching.single;
        for (final resource in recipe.ownedResources) {
          if (!owned.add(resource)) invalidAutomationValue();
        }
        final actual = effect(step, 'install_recipe', {
          'recipeDigest': recipe.digest,
          'version': recipe.version,
        });
        check(actual, 'recipe.${recipe.id}', 'recipe', {
          'recipeDigest': recipe.digest,
        });
      default:
        invalidAutomationValue();
    }
  }
  if (effectIndex != effects.length ||
      checkIndex != checks.length ||
      selectedRecipes.length != preflight.recipes.length)
    invalidAutomationValue();
}
