import 'dart:convert';

import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/automation/values.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:serverdeck_protocol/validation.dart';

/// Immutable public parameters only. Native actors derive origin separately.
final class AutomationAuthorityCommand {
  factory AutomationAuthorityCommand.parse(
    String operation,
    Map<String, Object?> value,
  ) {
    if (!const {
      'delegation.create',
      'delegation.revoke',
      'approval.request',
      'approval.decide',
    }.contains(operation))
      throw const FormatException('VALIDATION');
    final input = StrictCodec().decode(
      encodeMcpMessage(value, maxBytes: 256 * 1024),
      maxBytes: 256 * 1024,
    );
    requireFields(input, switch (operation) {
      'delegation.create' => {
        'requestId',
        'grantId',
        'serverIds',
        'profileRevisions',
        'predicates',
      },
      'delegation.revoke' => {'requestId', 'delegationId', 'expectedRevision'},
      'approval.request' => {'requestId', 'planId'},
      _ => {'requestId', 'approvalId', 'planDigest', 'decision'},
    }, operation == 'delegation.create' ? {'lifetimeSeconds'} : {});
    for (final key in [
      'requestId',
      'grantId',
      'delegationId',
      'planId',
      'approvalId',
    ]) {
      if (input.containsKey(key)) requireUuid(input[key]);
    }
    if (operation == 'delegation.create') {
      final targets = input['serverIds'],
          profiles = input['profileRevisions'],
          predicates = input['predicates'];
      if (targets is! List ||
          targets.isEmpty ||
          targets.length > 250 ||
          profiles is! List ||
          profiles.isEmpty ||
          profiles.length > 100 ||
          predicates is! Map<String, Object?> ||
          predicates.length > 32)
        throw const FormatException('VALIDATION');
      final ids = targets.map(requireUuid).toSet();
      if (ids.length != targets.length)
        throw const FormatException('VALIDATION');
      final tuples = <(String, int)>{};
      for (final raw in profiles) {
        if (raw is! Map<String, Object?>)
          throw const FormatException('VALIDATION');
        final key = AutomationRevisionKey.fromJson(raw);
        if (!tuples.add((key.profileId, key.revision)))
          throw const FormatException('VALIDATION');
      }
      for (final entry in predicates.entries) {
        automationIdentifier(entry.key);
        if (entry.value is! Map<String, Object?>)
          throw const FormatException('VALIDATION');
        ParameterConstraint.fromJson(entry.value as Map<String, Object?>);
      }
      final lifetime = input['lifetimeSeconds'] ?? 3600;
      if (lifetime is! int || lifetime < 300 || lifetime > 86400)
        throw const FormatException('VALIDATION');
      input['lifetimeSeconds'] = lifetime;
    }
    if (operation == 'delegation.revoke')
      requireAutomationRevision(input['expectedRevision']);
    if (operation == 'approval.decide' &&
        (input['planDigest'] is! String ||
            !RegExp(r'^[a-f0-9]{64}$')
                .hasMatch(input['planDigest'] as String) ||
            !const {'approved', 'denied'}.contains(input['decision'])))
      throw const FormatException('VALIDATION');
    return AutomationAuthorityCommand._(operation, jsonEncode(input));
  }
  const AutomationAuthorityCommand._(this.operation, this._json);
  final String operation, _json;
  Map<String, Object?> toJson() => jsonDecode(_json) as Map<String, Object?>;
  String get requestId => toJson()['requestId'] as String;
  bool get ownerOnly => operation != 'approval.request';
  Map<String, Object?> canonicalRequest(String? origin) => {
    'operation': operation,
    'originGrantId': origin,
    'params': {...toJson()}..remove('requestId'),
  };
}
