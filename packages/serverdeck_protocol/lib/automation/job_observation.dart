import '../validation.dart';
import 'values.dart';

enum JobObservationState { attached, detached, stale }

/// Runtime read data only. A sample is never permission or a durable job result.
final class LocalJobObservationView {
  LocalJobObservationView._(
    this.generation,
    this.attemptId,
    this.state,
    this.lastSequence,
    this.observedAt,
  );

  factory LocalJobObservationView.fromJson(Map<String, Object?> value) {
    requireFields(value, {
      'generation',
      'attemptId',
      'state',
      'lastSequence',
      'observedAt',
    });
    final sequence = value['lastSequence'], time = value['observedAt'];
    final state = JobObservationState.values
        .where((s) => s.name == value['state'])
        .firstOrNull;
    if (state == null ||
        (sequence == null) != (time == null) ||
        sequence != null &&
            (sequence is! int ||
                sequence < 0 ||
                sequence > 9223372036854775807) ||
        state != JobObservationState.detached && sequence == null) {
      invalidAutomationValue();
    }
    return LocalJobObservationView._(
      requireUuid(value['generation']),
      requireUuid(value['attemptId']),
      state,
      sequence as int?,
      time == null ? null : automationTimestamp(time),
    );
  }

  final String generation, attemptId;
  final JobObservationState state;
  final int? lastSequence;
  final DateTime? observedAt;
  Map<String, Object?> toJson() => {
    'generation': generation,
    'attemptId': attemptId,
    'state': state.name,
    'lastSequence': lastSequence,
    'observedAt': observedAt?.toIso8601String(),
  };
}
