import 'dart:convert';

import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/automation/values.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:serverdeck_protocol/validation.dart';

/// Captured original request, separate from resolved defaults and remote facts.
final class PlanCreateCommand {
  factory PlanCreateCommand.fromJson(Map<String, Object?> value) {
    final codec = StrictCodec();
    final copy = codec.decode(
      encodeMcpMessage(value, maxBytes: 256 * 1024),
      maxBytes: 256 * 1024,
    );
    requireFields(copy, {
      'requestId',
      'serverId',
      'profileId',
      'revision',
      'parameters',
    });
    requireUuid(copy['requestId']);
    requireUuid(copy['serverId']);
    requireUuid(copy['profileId']);
    requireAutomationRevision(copy['revision']);
    if (copy['parameters'] is! Map<String, Object?>)
      throw const FormatException('VALIDATION');
    final parameters = copy['parameters'] as Map<String, Object?>;
    if (parameters.length > 32) throw const FormatException('VALIDATION');
    for (final entry in parameters.entries) {
      automationIdentifier(entry.key);
      final item = entry.value;
      if (item is String) {
        automationText(item, max: 4096, multiline: true);
        if (['{{', '{%', '{#'].any(item.contains))
          throw const FormatException('VALIDATION');
      } else if (item is! bool &&
          (item is! int || item < 0 || item > 1000000)) {
        throw const FormatException('VALIDATION');
      }
    }
    return PlanCreateCommand._(jsonEncode(copy));
  }
  const PlanCreateCommand._(this._json);
  final String _json;
  Map<String, Object?> toJson() => jsonDecode(_json) as Map<String, Object?>;
  String get requestId => toJson()['requestId'] as String;
  String get serverId => toJson()['serverId'] as String;
  String get profileId => toJson()['profileId'] as String;
  int get revision => toJson()['revision'] as int;
  Map<String, Object?> get parameters =>
      toJson()['parameters'] as Map<String, Object?>;
  Map<String, Object?> canonicalRequest(String? origin) => {
    'operation': 'plan.create',
    'originGrantId': origin,
    'params': {...toJson()}..remove('requestId'),
  };
}
