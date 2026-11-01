import 'package:serverdeck_protocol/automation/owner_operations.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';
import 'package:test/test.dart';

const id = '12345678-1234-4234-9234-123456789abc';
void main() {
  test('cancelled owner interest uses shared strict result and retains local none semantics', () {
    final value = captureOwnerAutomationResult('automation.status', {
      'operationId': id,
      'state': 'done',
      'kind': 'jobs.reconcile',
      'result': McpToolResult.failure('CANCELLED').toJson(),
    });
    final result = value['result'] as Map;
    expect(result['isError'], isTrue);
    expect((result['structuredContent'] as Map)['error'], {
      'code': 'CANCELLED',
      'boundary': 'local',
      'retry': 'none',
    });
    expect(
      () => (value['result'] as Map)['isError'] = false,
      throwsUnsupportedError,
    );
  });
  test('cancellation category does not open arbitrary codes or owner envelope fields', () {
    expect(
      () => McpToolResult.failure('CANCELLED_PRIVATE_TEXT'),
      throwsFormatException,
    );
    expect(
      () => captureOwnerAutomationResult('automation.cancel', {
        'operationId': id,
        'cancelled': true,
        'owner': true,
      }),
      throwsFormatException,
    );
    expect(
      captureOwnerAutomationResult('automation.cancel', {
        'operationId': id,
        'cancelled': true,
      }),
      {'operationId': id, 'cancelled': true},
    );
  });
}
