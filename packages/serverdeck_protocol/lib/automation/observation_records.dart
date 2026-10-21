import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../codec.dart';
import '../validation.dart';
import 'profile_body.dart';
import 'values.dart';

const managedResourceIds = {
  'system.motd',
  'postgresql.service',
  'postgresql.settings',
  'clickhouse.service',
  'clickhouse.settings',
};

/// An immutable observation of public data. Shape/fingerprint/freshness alone
/// never establish current target identity, trust, qualification or authority.
final class ManagedResourceObservationRecord {
  ManagedResourceObservationRecord._(
    this._json,
    this.workspaceId,
    this.serverId,
    this.resourceId,
    this.targetRevision,
    this.connectionRevision,
    this.accessRevision,
    this.trustRevision,
    this.hostId,
    this.resourceRegistryDigest,
    this.observedAt,
    this.status,
  );

  factory ManagedResourceObservationRecord.fromJson(
    Map<String, Object?> value,
  ) {
    // Validate Unicode, tree depth and JSON types, but do not store canonical
    // bytes: observed text is data and must retain its original normalization.
    StrictCodec().canonical(value);
    final json = jsonEncode(value);
    if (utf8.encode(json).length > 128 * 1024) invalidAutomationValue();
    requireFields(value, {
      'workspaceId',
      'serverId',
      'resourceId',
      'targetRevision',
      'connectionRevision',
      'accessRevision',
      'trustRevision',
      'hostId',
      'resourceRegistryDigest',
      'observedAt',
      'status',
      'value',
    });
    final workspace = requireUuid(value['workspaceId']);
    final server = requireUuid(value['serverId']);
    final resource = value['resourceId'];
    if (resource is! String || !managedResourceIds.contains(resource)) {
      invalidAutomationValue();
    }
    final target = requireRevision(value['targetRevision']);
    final connection = requireRevision(value['connectionRevision']);
    final access = requireRevision(value['accessRevision']);
    final trust = requireRevision(value['trustRevision']);
    if (connection != trust ||
        [
          connection,
          access,
          trust,
        ].any((counter) => BigInt.parse(counter) > BigInt.parse(target))) {
      invalidAutomationValue();
    }
    final host = value['hostId'] == null ? null : requireUuid(value['hostId']);
    final registry = value['resourceRegistryDigest'] == null
        ? null
        : _digest(value['resourceRegistryDigest']);
    final observed = automationTimestamp(value['observedAt']);
    final status = value['status'];
    if (status is! String ||
        !const {
          'known',
          'stale',
          'unknown',
          'unsupported',
          'denied',
          'incomplete',
          'error',
        }.contains(status))
      invalidAutomationValue();
    if (status == 'known' || status == 'stale') {
      if (host == null || registry == null) invalidAutomationValue();
      final facts = _object(value['value']);
      if (resource.endsWith('.service')) {
        _service(facts);
      } else {
        _config(resource, facts);
      }
    } else if (value['value'] != null) {
      invalidAutomationValue();
    }
    return ManagedResourceObservationRecord._(
      json,
      workspace,
      server,
      resource,
      target,
      connection,
      access,
      trust,
      host,
      registry,
      observed,
      status,
    );
  }

  final String _json;
  final String workspaceId, serverId, resourceId, targetRevision;
  final String connectionRevision, accessRevision, trustRevision;
  final String? hostId, resourceRegistryDigest;
  final DateTime observedAt;
  final String status;

  Map<String, Object?> toJson() => jsonDecode(_json) as Map<String, Object?>;

  bool isFreshAt(DateTime now) {
    requireAutomationInstant(now);
    final age = now.difference(observedAt);
    return status == 'known' &&
        !age.isNegative &&
        age <= const Duration(seconds: 15);
  }

  Future<String> fingerprint() async {
    if (status != 'known' && status != 'stale') invalidAutomationValue();
    final facts = toJson()
      ..remove('status')
      ..remove('observedAt');
    final hash = await Sha256().hash(StrictCodec().canonical(facts));
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) invalidAutomationValue();
  return value;
}

String _digest(Object? value) {
  if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    invalidAutomationValue();
  }
  return value;
}

void _config(String resource, Map<String, Object?> facts) {
  requireFields(facts, {'exists', 'fileDigest', 'baselineDigest', 'values'});
  _digest(facts['baselineDigest']);
  final exists = facts['exists'];
  if (exists is! bool) invalidAutomationValue();
  if (!exists) {
    if (facts['fileDigest'] != null || facts['values'] != null) {
      invalidAutomationValue();
    }
    return;
  }
  _digest(facts['fileDigest']);
  final values = _object(facts['values']);
  if (resource == 'system.motd') {
    requireFields(values, {'text'});
    final text = values['text'];
    if (text is! String || utf8.encode(text).length > 65536) {
      invalidAutomationValue();
    }
    // Unicode validity was checked on the whole document. Raw controls and
    // template tokens are intentionally permitted in observed file contents.
    return;
  }
  // Observations contain literal settings only, never author parameter refs.
  if (values.values.any((v) => v is! int)) invalidAutomationValue();
  AutomationBody.fromJson({
    'format': 1,
    'environment': 'ubuntu24.04-amd64-systemd',
    'parameters': <String, Object?>{},
    'steps': [
      {
        'id': 'observed',
        'kind': 'config_file',
        'resourceId': resource,
        'values': values,
      },
    ],
  });
}

void _service(Map<String, Object?> facts) {
  requireFields(facts, {
    'activeState',
    'unitFileState',
    'mainPid',
    'startMonotonicUs',
    'baselineDigest',
  });
  if (!const {
        'active',
        'inactive',
        'failed',
        'activating',
        'deactivating',
        'reloading',
      }.contains(facts['activeState']) ||
      !const {
        'enabled',
        'enabled-runtime',
        'disabled',
        'static',
        'masked',
        'masked-runtime',
        'indirect',
        'generated',
        'transient',
        'linked',
        'linked-runtime',
        'alias',
        'bad',
      }.contains(facts['unitFileState']))
    invalidAutomationValue();
  final pid = facts['mainPid'];
  if (pid is! int || pid < 0 || pid > 2147483647) invalidAutomationValue();
  requireRevision(facts['startMonotonicUs'], allowZero: true);
  _digest(facts['baselineDigest']);
}
