import 'dart:convert';

import 'automation/models.dart';
import 'automation/values.dart';
import 'codec.dart';
import 'executor.dart';
import 'validation.dart';

/// Structural response capture only. The driver must obtain it from its actual
/// enrolled root session and check native/current target before publication.
final class ExecutorJobStatus {
  factory ExecutorJobStatus.capture(
    Map<String, Object?> value, {
    required AutomationPlanRecord plan,
    required String attemptId,
  }) {
    final copy = StrictCodec().decode(
      StrictCodec().encode(value, maxBytes: 1024 * 1024),
      maxBytes: 1024 * 1024,
    );
    requireFields(copy, {
      'attemptId',
      'state',
      'stepIndex',
      'authorizationEpoch',
      'sequence',
      'events',
      'checks',
      'needsAuthorization',
      'failureCode',
      'droppedEvents',
    });
    if (copy['attemptId'] != requireUuid(attemptId)) _bad();
    final state = copy['state'];
    if (!const {
      'queued',
      'waiting',
      'running',
      'succeeded',
      'failed',
      'cancelled',
      'cancelled-partial',
      'unknown',
    }.contains(state))
      _bad();
    final doc = plan.toJson();
    final effects = (doc['effects'] as List).cast<Map<String, Object?>>();
    final checks = (doc['checks'] as List).cast<Map<String, Object?>>();
    final step = _integer(copy['stepIndex'], effects.length),
        epoch = _integer(copy['authorizationEpoch'], 2147483647);
    _integer(copy['sequence'], 9223372036854775807);
    _integer(copy['droppedEvents'], 9223372036854775807);
    _code(copy['failureCode']);
    if (state == 'succeeded' &&
        (step != effects.length || copy['failureCode'] != null))
      _bad();
    if (state == 'failed' && copy['failureCode'] == null) _bad();
    final rows = copy['checks'];
    if (rows is! List || rows.length > 32) _bad();
    final seen = <String>{};
    for (final row in rows) {
      if (row is! Map<String, Object?>) _bad();
      requireFields(row, {'checkId', 'passed'});
      if (row['passed'] is! bool ||
          row['checkId'] is! String ||
          !seen.add(row['checkId'] as String) ||
          !checks.any((check) => check['id'] == row['checkId']))
        _bad();
    }
    if (state == 'succeeded' &&
        (seen.length != checks.length ||
            rows.any((row) => (row as Map)['passed'] != true)))
      _bad();
    final events = copy['events'];
    if (events is! List || events.length > 100) _bad();
    var previous = 0;
    for (final event in events) {
      if (event is! Map<String, Object?>) _bad();
      requireFields(event, {'sequence', 'at', 'kind', 'stepId', 'code'});
      final seq = _integer(event['sequence'], copy['sequence'] as int);
      if (seq <= previous) _bad();
      previous = seq;
      automationTimestamp(event['at']);
      if (!const {
            'recovery',
            'waiting',
            'launch_committed',
            'step_exited',
            'uncertain',
            'terminal',
            'step_completed',
            'cancel_recorded',
            'cancel_requested',
            'session_lost',
            'apt_admitted',
          }.contains(event['kind']) ||
          event['stepId'] != null &&
              !effects.any((effect) => effect['id'] == event['stepId']))
        _bad();
      _code(event['code']);
    }
    final challenge = copy['needsAuthorization'];
    if (challenge != null) {
      if (challenge is! Map<String, Object?> ||
          state != 'waiting' ||
          step >= effects.length ||
          epoch >= 2147483647)
        _bad();
      requireFields(challenge, {
        'challenge',
        'stepId',
        'planDigest',
        'expiresAt',
      });
      if (challenge['planDigest'] != doc['digest'] ||
          challenge['stepId'] != effects[step]['id'])
        _bad();
      // Reuse the exact closed request parser, including canonical nonce/time.
      ExecutorRequest.capture('authorize_step', {
        'attemptId': attemptId,
        ...challenge,
        'authorizationEpoch': epoch + 1,
      }, requestId: attemptId);
    } else if (state == 'waiting') {
      _bad();
    }
    return ExecutorJobStatus._(jsonEncode(copy), plan);
  }
  const ExecutorJobStatus._(this._json, this.plan);
  final String _json;
  final AutomationPlanRecord plan;
  Map<String, Object?> toJson() => jsonDecode(_json) as Map<String, Object?>;
  String get state => toJson()['state'] as String;
  int get sequence => toJson()['sequence'] as int;
  int get authorizationEpoch => toJson()['authorizationEpoch'] as int;
  int get stepIndex => toJson()['stepIndex'] as int;
  Map<String, Object?>? get challenge =>
      toJson()['needsAuthorization'] as Map<String, Object?>?;
  bool get terminal => const {
    'succeeded',
    'failed',
    'cancelled',
    'cancelled-partial',
    'unknown',
  }.contains(state);
  String get localState => state == 'cancelled-partial' ? 'cancelled' : state;
  AutomationJobOutcome? outcome(String Function(String) domainCode) {
    if (!terminal) return null;
    final value = toJson();
    final declarations = (plan.toJson()['checks'] as List)
        .cast<Map<String, Object?>>();
    final checks = [
      for (final raw in value['checks'] as List)
        {
          'checkId': (raw as Map)['checkId'],
          'stepId': declarations.singleWhere(
            (item) => item['id'] == raw['checkId'],
          )['effectId'],
          'result': raw['passed'] == true ? 'passed' : 'failed',
          'safeCode': raw['passed'] == true ? null : 'CHECK_FAILED',
        },
    ];
    return AutomationJobOutcome.fromJson({
      'effects': state == 'unknown'
          ? 'uncertain'
          : (plan.toJson()['effects'] as List).isEmpty ||
                state == 'cancelled' && stepIndex == 0
          ? 'none'
          : 'confirmed',
      'checks': checks,
      'safeCode': state == 'unknown'
          ? 'UNKNOWN_OUTCOME'
          : localState == 'cancelled'
          ? 'CANCELLED'
          : state == 'failed'
          ? domainCode(value['failureCode'] as String? ?? 'STEP_FAILED')
          : null,
    });
  }
}

Never _bad() => throw const FormatException('RUNTIME_INCOMPATIBLE');
int _integer(Object? value, int maximum) =>
    value is int && value >= 0 && value <= maximum ? value : _bad();
void _code(Object? value) {
  if (value != null && !executorCodes.contains(value)) _bad();
}
