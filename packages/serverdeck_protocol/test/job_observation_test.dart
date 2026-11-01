import 'package:serverdeck_protocol/automation/job_observation.dart';
import 'package:test/test.dart';

const generation = '12345678-1234-4234-9234-123456789001';
const attempt = '12345678-1234-4234-9234-123456789002';
Map<String, Object?> view() => {
  'generation': generation,
  'attemptId': attempt,
  'state': 'detached',
  'lastSequence': null,
  'observedAt': null,
};

void main() {
  test('observation distinguishes detached unsampled from retained sample without changing job data', () {
    expect(LocalJobObservationView.fromJson(view()).toJson(), view());
    for (final state in JobObservationState.values) {
      final input = {
        ...view(),
        'state': state.name,
        'lastSequence': 0,
        'observedAt': '2026-10-31T10:00:00.000Z',
      };
      expect(LocalJobObservationView.fromJson(input).toJson(), input);
    }
  });
  test('observation captures fields and exports independent data', () {
    final input = {
      ...view(),
      'state': 'attached',
      'lastSequence': 7,
      'observedAt': '2026-10-31T10:00:00.000Z',
    };
    final captured = LocalJobObservationView.fromJson(input);
    input['state'] = 'stale';
    captured.toJson()['state'] = 'stale';
    expect(captured.state, JobObservationState.attached);
    expect(captured.lastSequence, 7);
  });
  final bad = <String, Map<String, Object?>>{
    'missing': {...view()}..remove('state'),
    'extra': {...view(), 'permission': true},
    'generation': {...view(), 'generation': 'old'},
    'attempt': {
      ...view(),
      'attemptId': generation.replaceFirst('-4234-', '-5234-'),
    },
    'state': {...view(), 'state': 'succeeded'},
    'attached unsampled': {...view(), 'state': 'attached'},
    'stale unsampled': {...view(), 'state': 'stale'},
    'partial sample': {...view(), 'lastSequence': 1},
    'partial time': {...view(), 'observedAt': '2026-10-31T10:00:00.000Z'},
    'negative': {
      ...view(),
      'lastSequence': -1,
      'observedAt': '2026-10-31T10:00:00.000Z',
    },
    'fractional': {
      ...view(),
      'lastSequence': 1.5,
      'observedAt': '2026-10-31T10:00:00.000Z',
    },
    'timestamp': {
      ...view(),
      'lastSequence': 1,
      'observedAt': '2026-10-31T10:00:00Z',
    },
  };
  for (final entry in bad.entries) {
    test('closed observation refuses ${entry.key}', () {
      expect(
        () => LocalJobObservationView.fromJson(entry.value),
        throwsFormatException,
      );
    });
  }
}
