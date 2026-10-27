import 'dart:convert';

import '../codec.dart';
import '../validation.dart';
import 'models.dart' show AutomationRevisionKey, requireAutomationRevision;
import 'values.dart';

const _int64max = 9223372036854775807;
const automationSafeCodes = {
  'VALIDATION',
  'FORBIDDEN',
  'REVISION_CONFLICT',
  'RESOURCE_LIMIT',
  'TIMEOUT',
  'STORAGE_BLOCKED',
  'INTERNAL',
  'TRUST_REQUIRED',
  'TRUST_CHANGED',
  'APPROVAL_REQUIRED',
  'PLAN_EXPIRED',
  'PLAN_STALE',
  'HOST_BUSY',
  'EXECUTOR_UNAVAILABLE',
  'RUNTIME_INCOMPATIBLE',
  'UNKNOWN_OUTCOME',
  'UNSUPPORTED',
  'CHECK_FAILED',
  'CANCELLED',
  'DISCONNECTED',
};
const automationCheckResults = {
  'passed',
  'failed',
  'unknown',
  'unsupported',
  'denied',
  'timeout',
};

Map<String, Object?> _object(Object? value) =>
    value is Map<String, Object?> ? value : invalidAutomationValue();
String _choice(Object? value, Set<String> choices) =>
    value is String && choices.contains(value)
    ? value
    : invalidAutomationValue();
String? _nullableCode(Object? value) =>
    value == null ? null : _choice(value, automationSafeCodes);
String? _nullableId(Object? value) => value == null ? null : requireUuid(value);
int _integer(Object? value, {int minimum = 0}) =>
    value is int && value >= minimum && value <= _int64max
    ? value
    : invalidAutomationValue();
String _digest(Object? value) {
  if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value))
    invalidAutomationValue();
  return value;
}

void _bool(Object? value) {
  if (value is! bool) invalidAutomationValue();
}

void _document(
  Map<String, Object?> value,
  Set<String> fields, {
  int maximum = 256 * 1024,
}) {
  try {
    StrictCodec().encode(value, maxBytes: maximum);
  } on FormatException {
    invalidAutomationValue();
  }
  requireFields(value, fields);
}

bool _same(Object? left, Object? right) =>
    utf8.decode(StrictCodec().canonical(left)) ==
    utf8.decode(StrictCodec().canonical(right));
Object? _freeze(Object? value) {
  if (value is Map<String, Object?>)
    return Map<String, Object?>.unmodifiable(
      value.map((key, child) => MapEntry(key, _freeze(child))),
    );
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  return value;
}

/// Immutable structural metadata only. The locald loader must resolve actual
/// entities/plan digests and the coordinator must check current live policy.
abstract base class _Record {
  _Record(Map<String, Object?> input)
    : _json = utf8.decode(StrictCodec().canonical(input)) {
    _value = _freeze(jsonDecode(_json)) as Map<String, Object?>;
  }
  final String _json;
  late final Map<String, Object?> _value;
  Map<String, Object?> toJson() => jsonDecode(_json) as Map<String, Object?>;
}

final class AutomationAuthorityRef extends _Record {
  AutomationAuthorityRef._(super.value);
  factory AutomationAuthorityRef.fromJson(Map<String, Object?> value) {
    _document(value, {'kind', 'id', 'revision'}, maximum: 4096);
    final kind = _choice(value['kind'], {'delegation', 'approval'});
    requireUuid(value['id']);
    final revision = requireAutomationRevision(value['revision']);
    if (kind == 'approval' && revision != 1) invalidAutomationValue();
    return AutomationAuthorityRef._(value);
  }
  String get kind => _value['kind'] as String;
  String get id => _value['id'] as String;
  int get revision => _value['revision'] as int;
  bool sameAs(AutomationAuthorityRef other) =>
      kind == other.kind && id == other.id && revision == other.revision;
}

final class AutomationJobCheck extends _Record {
  AutomationJobCheck._(super.value);
  factory AutomationJobCheck.fromJson(Map<String, Object?> value) {
    _document(value, {
      'checkId',
      'stepId',
      'result',
      'safeCode',
    }, maximum: 4096);
    automationIdentifier(value['checkId']);
    automationIdentifier(value['stepId']);
    _choice(value['result'], automationCheckResults);
    _nullableCode(value['safeCode']);
    return AutomationJobCheck._(value);
  }
  String get checkId => _value['checkId'] as String;
  String get stepId => _value['stepId'] as String;
  String get result => _value['result'] as String;
  String? get safeCode => _value['safeCode'] as String?;
}

final class AutomationJobOutcome extends _Record {
  AutomationJobOutcome._(super.value, this.checks);
  factory AutomationJobOutcome.fromJson(Map<String, Object?> value) {
    _document(value, {'effects', 'checks', 'safeCode'});
    _choice(value['effects'], {'none', 'confirmed', 'uncertain'});
    _nullableCode(value['safeCode']);
    final raw = value['checks'];
    if (raw is! List || raw.length > 32) invalidAutomationValue();
    final checks = <AutomationJobCheck>[], unique = <String>{};
    for (final item in raw) {
      final check = AutomationJobCheck.fromJson(_object(item));
      if (!unique.add('${check.stepId}:${check.checkId}'))
        invalidAutomationValue();
      checks.add(check);
    }
    return AutomationJobOutcome._(value, List.unmodifiable(checks));
  }
  String get effects => _value['effects'] as String;
  String? get safeCode => _value['safeCode'] as String?;
  final List<AutomationJobCheck> checks;
  void validateForState(String state) {
    switch (state) {
      case 'succeeded':
        if (effects == 'uncertain' ||
            safeCode != null ||
            checks.any((check) => check.result != 'passed'))
          invalidAutomationValue();
      case 'failed':
        if (effects == 'uncertain' || safeCode == null)
          invalidAutomationValue();
      case 'cancelled':
        if (effects == 'uncertain' || safeCode != 'CANCELLED')
          invalidAutomationValue();
      case 'unknown':
        if (effects != 'uncertain' || safeCode != 'UNKNOWN_OUTCOME')
          invalidAutomationValue();
      default:
        invalidAutomationValue();
    }
  }
}

final class AutomationJobRecord extends _Record {
  AutomationJobRecord._(super.value);
  static const states = {
    'queued',
    'running',
    'cancel-requested',
    'succeeded',
    'failed',
    'cancelled',
    'unknown',
    'reconciling',
  };
  static const _edges = {
    'queued': {'running', 'cancelled'},
    'running': {
      'cancel-requested',
      'succeeded',
      'failed',
      'cancelled',
      'unknown',
    },
    'cancel-requested': {'succeeded', 'failed', 'cancelled', 'unknown'},
    'unknown': {'reconciling'},
    'reconciling': {'succeeded', 'failed', 'cancelled', 'unknown'},
  };
  static const _mutable = {
    'state',
    'nextSequence',
    'cancelRequested',
    'updatedAt',
    'outcome',
  };
  factory AutomationJobRecord.fromJson(Map<String, Object?> value) {
    _document(value, {
      'workspaceId',
      'id',
      'requestId',
      'immutablePlanId',
      'planDigest',
      'profileId',
      'profileRevision',
      'profileDigest',
      'grantId',
      'authorityRef',
      'hostAttemptId',
      'state',
      'nextSequence',
      'cancelRequested',
      'createdAt',
      'updatedAt',
      'outcome',
    });
    for (final name in [
      'workspaceId',
      'id',
      'requestId',
      'immutablePlanId',
      'hostAttemptId',
    ])
      requireUuid(value[name]);
    _digest(value['planDigest']);
    AutomationRevisionKey.fromJson({
      'profileId': value['profileId'],
      'revision': value['profileRevision'],
      'bodyDigest': value['profileDigest'],
    });
    final grantId = _nullableId(value['grantId']);
    final authority = AutomationAuthorityRef.fromJson(
      _object(value['authorityRef']),
    );
    if (grantId == null && authority.kind != 'approval')
      invalidAutomationValue();
    final state = _choice(value['state'], states);
    _integer(value['nextSequence'], minimum: 1);
    _bool(value['cancelRequested']);
    final cancel = value['cancelRequested'] as bool;
    if ((state == 'queued' || state == 'running') && cancel ||
        state == 'cancel-requested' && !cancel)
      invalidAutomationValue();
    if (automationTimestamp(value['updatedAt'])
        .isBefore(automationTimestamp(value['createdAt'])))
      invalidAutomationValue();
    if ({'succeeded', 'failed', 'cancelled', 'unknown'}.contains(state)) {
      AutomationJobOutcome.fromJson(_object(value['outcome']))
          .validateForState(state);
    } else if (value['outcome'] != null) {
      invalidAutomationValue();
    }
    return AutomationJobRecord._(value);
  }
  String get workspaceId => _value['workspaceId'] as String;
  String get id => _value['id'] as String;
  String get requestId => _value['requestId'] as String;
  String get immutablePlanId => _value['immutablePlanId'] as String;
  String get planDigest => _value['planDigest'] as String;
  String get hostAttemptId => _value['hostAttemptId'] as String;
  String? get grantId => _value['grantId'] as String?;
  String get state => _value['state'] as String;
  int get nextSequence => _value['nextSequence'] as int;
  bool get cancelRequested => _value['cancelRequested'] as bool;
  DateTime get createdAt => automationTimestamp(_value['createdAt']);
  DateTime get updatedAt => automationTimestamp(_value['updatedAt']);
  late final AutomationRevisionKey profileKey = AutomationRevisionKey.fromJson({
    'profileId': _value['profileId'],
    'revision': _value['profileRevision'],
    'bodyDigest': _value['profileDigest'],
  });
  late final AutomationAuthorityRef authority = AutomationAuthorityRef.fromJson(
    _object(_value['authorityRef']),
  );
  late final AutomationJobOutcome? outcome = _value['outcome'] == null
      ? null
      : AutomationJobOutcome.fromJson(_object(_value['outcome']));

  /// Structural previous→next check, not executor outcome proof or admission.
  void validateTransitionTo(AutomationJobRecord next) {
    Map<String, Object?> identity(AutomationJobRecord row) =>
        {...row._value}..removeWhere((key, _) => _mutable.contains(key));
    if (!_same(identity(this), identity(next)) ||
        (state != next.state &&
            !(_edges[state]?.contains(next.state) ?? false)) ||
        next.nextSequence < nextSequence ||
        next.updatedAt.isBefore(updatedAt) ||
        cancelRequested && !next.cancelRequested ||
        state == next.state &&
            !_same(_value['outcome'], next._value['outcome']))
      invalidAutomationValue();
  }

  /// The caller must supply an already fully validated immutable plan. These
  /// equalities alone do not validate that plan or grant a fresh effect.
  void validatePlanIdentity({
    required String workspaceId,
    required String planId,
    required String digest,
    required AutomationRevisionKey profileKey,
    required String? originGrantId,
  }) {
    if (this.workspaceId != workspaceId ||
        immutablePlanId != planId ||
        planDigest != digest ||
        this.profileKey != profileKey ||
        grantId != originGrantId)
      invalidAutomationValue();
  }
}

final class AutomationApprovalRecord extends _Record {
  AutomationApprovalRecord._(super.value);
  static const states = {
    'pending',
    'approved',
    'denied',
    'expired',
    'consumed',
  };
  static const _edges = {
    'pending': {'approved', 'denied', 'expired'},
    'approved': {'consumed', 'expired'},
  };
  factory AutomationApprovalRecord.fromJson(Map<String, Object?> value) {
    _document(value, {
      'workspaceId',
      'id',
      'planId',
      'planDigest',
      'grantId',
      'createdAt',
      'expiresAt',
      'state',
      'jobId',
    });
    for (final field in ['workspaceId', 'id', 'planId'])
      requireUuid(value[field]);
    _digest(value['planDigest']);
    _nullableId(value['grantId']);
    final created = automationTimestamp(value['createdAt']),
        expires = automationTimestamp(value['expiresAt']);
    if (!expires.isAfter(created) ||
        expires.difference(created) > const Duration(minutes: 5))
      invalidAutomationValue();
    final state = _choice(value['state'], states),
        job = _nullableId(value['jobId']);
    if ((state == 'consumed') != (job != null)) invalidAutomationValue();
    return AutomationApprovalRecord._(value);
  }
  String get workspaceId => _value['workspaceId'] as String;
  String get id => _value['id'] as String;
  String get planId => _value['planId'] as String;
  String get planDigest => _value['planDigest'] as String;
  String? get grantId => _value['grantId'] as String?;
  String? get jobId => _value['jobId'] as String?;
  String get state => _value['state'] as String;
  DateTime get createdAt => automationTimestamp(_value['createdAt']);
  DateTime get expiresAt => automationTimestamp(_value['expiresAt']);
  void validateTransitionTo(AutomationApprovalRecord next) {
    Map<String, Object?> identity(AutomationApprovalRecord row) =>
        {...row._value}
          ..remove('state')
          ..remove('jobId');
    if (!_same(identity(this), identity(next)) ||
        (state != next.state &&
            !(_edges[state]?.contains(next.state) ?? false)) ||
        state == next.state && jobId != next.jobId)
      invalidAutomationValue();
  }

  void validatePlanIdentity({
    required String workspaceId,
    required String planId,
    required String digest,
    required String? originGrantId,
    required DateTime planCreatedAt,
    required DateTime planExpiresAt,
  }) {
    requireAutomationInstant(planCreatedAt);
    requireAutomationInstant(planExpiresAt);
    if (this.workspaceId != workspaceId ||
        this.planId != planId ||
        planDigest != digest ||
        grantId != originGrantId ||
        createdAt.isBefore(planCreatedAt) ||
        expiresAt.isAfter(planExpiresAt))
      invalidAutomationValue();
  }
}

final class AutomationDesiredStateRecord extends _Record {
  AutomationDesiredStateRecord._(super.value);
  factory AutomationDesiredStateRecord.fromJson(Map<String, Object?> value) {
    _document(value, {
      'workspaceId',
      'id',
      'serverId',
      'resourceId',
      'desiredRevision',
      'bodyDigest',
      'inputDigest',
      'lastJobId',
      'observedRevision',
    });
    for (final field in ['workspaceId', 'id', 'serverId', 'lastJobId'])
      requireUuid(value[field]);
    final resource = value['resourceId'];
    if (resource is! String ||
        !RegExp(r'^[a-z][a-z0-9_.-]{0,63}$').hasMatch(resource))
      invalidAutomationValue();
    final revision = requireAutomationRevision(value['desiredRevision']);
    if (value['observedRevision'] != null &&
        requireAutomationRevision(value['observedRevision']) > revision)
      invalidAutomationValue();
    _digest(value['bodyDigest']);
    _digest(value['inputDigest']);
    return AutomationDesiredStateRecord._(value);
  }
  String get workspaceId => _value['workspaceId'] as String;
  String get id => _value['id'] as String;
  String get serverId => _value['serverId'] as String;
  String get resourceId => _value['resourceId'] as String;
  int get desiredRevision => _value['desiredRevision'] as int;
  int? get observedRevision => _value['observedRevision'] as int?;
  String get bodyDigest => _value['bodyDigest'] as String;
  String get inputDigest => _value['inputDigest'] as String;
  String get lastJobId => _value['lastJobId'] as String;
  void validateConfirmedJobIdentity(
    AutomationJobRecord job, {
    required String planId,
    required String planDigest,
    required String planServerId,
    required String resolvedInputDigest,
    required Set<String> ownedResources,
  }) {
    if (job.workspaceId != workspaceId ||
        job.id != lastJobId ||
        job.immutablePlanId != planId ||
        job.planDigest != planDigest ||
        job.state != 'succeeded' ||
        job.profileKey.bodyDigest != bodyDigest ||
        planServerId != serverId ||
        resolvedInputDigest != inputDigest ||
        !ownedResources.contains(resourceId))
      invalidAutomationValue();
  }
}

final class AutomationJobEventRecord extends _Record {
  AutomationJobEventRecord._(super.value);
  factory AutomationJobEventRecord.fromJson(Map<String, Object?> value) {
    _document(value, {
      'workspaceId',
      'jobId',
      'sequence',
      'timestamp',
      'kind',
      'stepId',
      'state',
      'safeCode',
      'checkResult',
      'droppedCount',
    }, maximum: 4096);
    requireUuid(value['workspaceId']);
    requireUuid(value['jobId']);
    _integer(value['sequence'], minimum: 1);
    automationTimestamp(value['timestamp']);
    final kind = _choice(value['kind'], {
      'state',
      'step',
      'check',
      'progress',
      'dropped',
    });
    if (value['stepId'] != null) automationIdentifier(value['stepId']);
    if (value['state'] != null)
      _choice(value['state'], AutomationJobRecord.states);
    if (value['checkResult'] != null)
      _choice(value['checkResult'], automationCheckResults);
    _nullableCode(value['safeCode']);
    final dropped = _integer(value['droppedCount']);
    final hasStep = value['stepId'] != null,
        hasState = value['state'] != null,
        hasCheck = value['checkResult'] != null;
    final valid = switch (kind) {
      'state' => hasState && !hasStep && !hasCheck && dropped == 0,
      'step' => hasStep && !hasState && !hasCheck && dropped == 0,
      'check' => hasStep && hasCheck && !hasState && dropped == 0,
      'progress' => !hasState && !hasCheck && dropped == 0,
      _ => !hasState && !hasStep && !hasCheck && dropped >= 1,
    };
    if (!valid) invalidAutomationValue();
    return AutomationJobEventRecord._(value);
  }
  String get workspaceId => _value['workspaceId'] as String;
  String get jobId => _value['jobId'] as String;
  int get sequence => _value['sequence'] as int;
  DateTime get timestamp => automationTimestamp(_value['timestamp']);
  String get kind => _value['kind'] as String;
  String? get stepId => _value['stepId'] as String?;
  String? get state => _value['state'] as String?;
  String? get safeCode => _value['safeCode'] as String?;
  String? get checkResult => _value['checkResult'] as String?;
  int get droppedCount => _value['droppedCount'] as int;
  void validateJobIdentity(
    AutomationJobRecord job, {
    int? previousSequence,
    DateTime? previousTimestamp,
  }) {
    if (previousSequence != null) _integer(previousSequence);
    if (previousTimestamp != null) requireAutomationInstant(previousTimestamp);
    if (job.workspaceId != workspaceId ||
        job.id != jobId ||
        sequence >= job.nextSequence ||
        previousSequence != null && sequence <= previousSequence ||
        previousTimestamp != null && timestamp.isBefore(previousTimestamp))
      invalidAutomationValue();
  }
}

final class AutomationMutationReceiptRecord extends _Record {
  AutomationMutationReceiptRecord._(super.value);
  static const operations = {
    'grant.create',
    'grant.replace',
    'grant.revoke',
    'delegation.create',
    'delegation.revoke',
    'profile.create',
    'profile.update',
    'profile.archive',
    'plan.create',
    'approval.request',
    'approval.decide',
    'job.apply',
    'job.cancel',
    'job.reconcile',
  };
  factory AutomationMutationReceiptRecord.fromJson(Map<String, Object?> value) {
    _document(value, {
      'workspaceId',
      'requestId',
      'originGrantId',
      'objectGrantId',
      'canonicalDigest',
      'operation',
      'result',
      'createdAt',
    }, maximum: 8192);
    requireUuid(value['workspaceId']);
    requireUuid(value['requestId']);
    final origin = _nullableId(value['originGrantId']),
        object = _nullableId(value['objectGrantId']);
    _digest(value['canonicalDigest']);
    automationTimestamp(value['createdAt']);
    final operation = _choice(value['operation'], operations);
    final ownerOnly =
        operation.startsWith('grant.') ||
        operation.startsWith('delegation.') ||
        operation == 'approval.decide';
    final workspaceObject =
        operation.startsWith('grant.') || operation.startsWith('profile.');
    if (ownerOnly && origin != null ||
        workspaceObject && object != null ||
        operation.startsWith('delegation.') && object == null ||
        !workspaceObject && origin != null && origin != object)
      invalidAutomationValue();
    final result = _object(value['result']);
    final fields = switch (operation) {
      'grant.create' ||
      'grant.replace' ||
      'grant.revoke' => {'grantId', 'revision'},
      'delegation.create' ||
      'delegation.revoke' => {'delegationId', 'revision'},
      'profile.create' ||
      'profile.update' => {'profileId', 'revision', 'digest'},
      'profile.archive' => {'profileId', 'revision', 'archived'},
      'plan.create' => {'planId', 'planDigest'},
      'approval.request' => {'approvalId', 'planId', 'planDigest'},
      'approval.decide' => {'approvalId', 'planId', 'planDigest', 'decision'},
      'job.apply' => {'jobId', 'planId', 'planDigest', 'authorityRef'},
      _ => {'jobId'},
    };
    _document(result, fields, maximum: 4096);
    for (final field in [
      'grantId',
      'delegationId',
      'profileId',
      'planId',
      'approvalId',
      'jobId',
    ]) {
      if (result.containsKey(field)) requireUuid(result[field]);
    }
    if (result.containsKey('revision'))
      requireAutomationRevision(result['revision']);
    if (operation == 'profile.create' && result['revision'] != 1)
      invalidAutomationValue();
    for (final field in ['digest', 'planDigest'])
      if (result.containsKey(field)) _digest(result[field]);
    if (result.containsKey('archived') && result['archived'] != true)
      invalidAutomationValue();
    if (result.containsKey('decision'))
      _choice(result['decision'], {'approved', 'denied'});
    if (result.containsKey('authorityRef')) {
      final authority = AutomationAuthorityRef.fromJson(
        _object(result['authorityRef']),
      );
      if (object == null && authority.kind != 'approval')
        invalidAutomationValue();
    }
    return AutomationMutationReceiptRecord._(value);
  }
  String get workspaceId => _value['workspaceId'] as String;
  String get requestId => _value['requestId'] as String;
  String? get originGrantId => _value['originGrantId'] as String?;
  String? get objectGrantId => _value['objectGrantId'] as String?;
  String get canonicalDigest => _value['canonicalDigest'] as String;
  String get operation => _value['operation'] as String;
  DateTime get createdAt => automationTimestamp(_value['createdAt']);
  Map<String, Object?> get result => toJson()['result'] as Map<String, Object?>;

  /// Historical identity validation; current session/grant policy is separate.
  void validateApprovalIdentity(AutomationApprovalRecord approval) {
    final ack = result;
    if (!operation.startsWith('approval.') ||
        approval.workspaceId != workspaceId ||
        approval.id != ack['approvalId'] ||
        approval.grantId != objectGrantId ||
        approval.planId != ack['planId'] ||
        approval.planDigest != ack['planDigest'])
      invalidAutomationValue();
    if (operation == 'approval.decide') {
      final valid = ack['decision'] == 'denied'
          ? approval.state == 'denied'
          : {'approved', 'consumed', 'expired'}.contains(approval.state);
      if (!valid) invalidAutomationValue();
    }
  }

  /// Full plan validation and target policy must precede using this binding.
  void validateJobIdentity(AutomationJobRecord job) {
    final ack = result;
    if (!operation.startsWith('job.') ||
        job.workspaceId != workspaceId ||
        job.id != ack['jobId'] ||
        job.grantId != objectGrantId)
      invalidAutomationValue();
    if (operation == 'job.apply' &&
        (job.immutablePlanId != ack['planId'] ||
            job.planDigest != ack['planDigest'] ||
            !job.authority.sameAs(
              AutomationAuthorityRef.fromJson(_object(ack['authorityRef'])),
            )))
      invalidAutomationValue();
  }

  /// Equality only, not current target/scope policy or permission to disclose.
  bool matchesInitiator({
    required String workspaceId,
    required String? grantId,
  }) => this.workspaceId == workspaceId && originGrantId == grantId;
}
