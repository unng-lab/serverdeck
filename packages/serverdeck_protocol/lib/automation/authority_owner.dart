import '../codec.dart';
import '../validation.dart';
import 'models.dart';

const automationAuthorityMutations = {
  'delegations.create': 'delegation.create',
  'delegations.revoke': 'delegation.revoke',
  'approvals.request': 'approval.request',
  'approvals.decide': 'approval.decide',
};
const automationAuthorityOwnerMethods = {
  'delegations.create',
  'delegations.revoke',
  'approvals.request',
  'approvals.decide',
  'delegations.list',
  'delegations.get',
  'approvals.list',
  'approvals.get',
};
const automationAuthorityFailureCodes = {'PLAN_EXPIRED', 'PLAN_STALE'};

/// Closed format3 owner result boundary. Structural records confer no authority.
Map<String, Object?> captureAutomationAuthorityOwnerResult(
  String method,
  Map<String, Object?> value,
) {
  final copy = StrictCodec().decode(
    StrictCodec().encode(value, maxBytes: 2 * 1024 * 1024),
    maxBytes: 2 * 1024 * 1024,
  );
  if (!automationAuthorityOwnerMethods.contains(method))
    throw const FormatException('UNSUPPORTED');
  // Domain failures remain data; the native Local API error vocabulary stays
  // unchanged. Only these authority-domain additions need this representation.
  if (copy.containsKey('failure')) {
    requireFields(copy, {'failure'});
    final failure = copy['failure'];
    if (failure is! Map<String, Object?>)
      throw const FormatException('VALIDATION');
    requireFields(failure, {'code'});
    if (!automationAuthorityFailureCodes.contains(failure['code']))
      throw const FormatException('VALIDATION');
    return _freeze(copy) as Map<String, Object?>;
  }
  if (method.endsWith('.list')) {
    requireFields(copy, {'items', 'nextOffset'});
    final items = copy['items'], next = copy['nextOffset'];
    if (items is! List ||
        items.length > 50 ||
        next != null && (next is! int || next < 1 || next > 1000))
      throw const FormatException('VALIDATION');
    for (final raw in items) _record(method, raw);
  } else if (method.endsWith('.get')) {
    final field = method.startsWith('delegations.') ? 'delegation' : 'approval';
    requireFields(copy, {field});
    _record(method, copy[field]);
  } else if (method.startsWith('delegations.')) {
    requireFields(copy, {'delegationId', 'revision'});
    requireUuid(copy['delegationId']);
    if (copy['revision'] != (method.endsWith('.create') ? 1 : 2))
      throw const FormatException('VALIDATION');
  } else {
    requireFields(copy, {
      'approvalId',
      'planId',
      'planDigest',
    }, method.endsWith('.decide') ? {'decision'} : {});
    requireUuid(copy['approvalId']);
    requireUuid(copy['planId']);
    if (copy['planDigest'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(copy['planDigest'] as String) ||
        method.endsWith('.decide') &&
            !const {'approved', 'denied'}.contains(copy['decision']))
      throw const FormatException('VALIDATION');
    if (method.endsWith('.decide') && !copy.containsKey('decision'))
      throw const FormatException('VALIDATION');
  }
  return _freeze(copy) as Map<String, Object?>;
}

void _record(String method, Object? raw) {
  if (raw is! Map<String, Object?>) throw const FormatException('VALIDATION');
  if (method.startsWith('delegations.')) {
    DelegationRecord.fromJson(raw);
  } else {
    AutomationApprovalRecord.fromJson(raw);
  }
}

Object? _freeze(Object? value) => switch (value) {
  Map<String, Object?> value => Map<String, Object?>.unmodifiable({
    for (final entry in value.entries) entry.key: _freeze(entry.value),
  }),
  List value => List<Object?>.unmodifiable(value.map(_freeze)),
  _ => value,
};
