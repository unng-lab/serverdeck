import 'package:serverdeck_protocol/executor_jobs.dart';
import 'package:test/test.dart';

const attempt = '12345678-1234-4234-9234-123456789001';
const other = '12345678-1234-4234-9234-123456789002';
Map<String, Object?> receipt() => {
  'attemptId': attempt,
  'state': 'unknown',
  'childrenStopped': false,
  'sequence': 0,
};
void main() {
  test('existing reconciliation DTO captures each state and both stopped values without granting terminal', () {
    for (final state in executorJobStates) {
      for (final stopped in [false, true]) {
        final input = {
          ...receipt(),
          'state': state,
          'childrenStopped': stopped,
          'sequence': 9223372036854775807,
        };
        final result = ExecutorReconcileResult.capture(
          input,
          attemptId: attempt,
        );
        expect(result.toJson(), input);
        expect(result.childrenStopped, stopped);
      }
    }
  });
  test('reconcile capture exports independent primitive data', () {
    final input = receipt();
    final captured = ExecutorReconcileResult.capture(input, attemptId: attempt);
    input['childrenStopped'] = true;
    captured.toJson()['childrenStopped'] = true;
    expect(captured.childrenStopped, isFalse);
    expect(captured.sequence, 0);
  });
  final bad = <String, Map<String, Object?>>{
    'missing': receipt()..remove('childrenStopped'),
    'extra': {...receipt(), 'proof': true},
    'foreign': {...receipt(), 'attemptId': other},
    'bad ID': {...receipt(), 'attemptId': 'bad'},
    'state': {...receipt(), 'state': 'PRIVATE_NOT_A_STATE'},
    'boolean text': {...receipt(), 'childrenStopped': 'true'},
    'boolean null': {...receipt(), 'childrenStopped': null},
    'negative': {...receipt(), 'sequence': -1},
    'text': {...receipt(), 'sequence': '1'},
    'boolean sequence': {...receipt(), 'sequence': true},
    'fractional': {...receipt(), 'sequence': 1.5},
  };
  for (final row in bad.entries) {
    test('reconcile refuses ${row.key} before evidence can be used', () {
      expect(
        () => ExecutorReconcileResult.capture(row.value, attemptId: attempt),
        throwsFormatException,
      );
    });
  }
}
