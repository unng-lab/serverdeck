import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck_protocol/errors.dart';
import 'package:serverdeck_protocol/models.dart';

import '../../packages/serverdeck_locald/lib/api/diagnostics.dart';

void main() {
  test('safe error allowlist and field rejection', () {
    for (final code in ErrorCode.values) {
      final value = LocalError(code).toJson();
      expect(value.keys.toSet(), {'code', 'boundary', 'retry'});
      expect(value['code'], code.wireName);
      expect(value['boundary'], 'local');
      expect(
        value['retry'],
        isIn([
          'none',
          'retry-same-request',
          'reload',
          'reconnect',
          'manual-recovery',
        ]),
      );
    }
    expect(
      LocalError(ErrorCode.validation, field: 'port').toJson()['field'],
      'port',
    );
    expect(
      () => LocalError(ErrorCode.validation, field: 'private-marker').toJson(),
      throwsArgumentError,
    );
    expect(
      () => LocalError(ErrorCode.internal, field: 'port').toJson(),
      throwsArgumentError,
    );
  });
  test('diagnostic output has only structured allowlisted fields', () {
    final event = DiagnosticEvent(
      timestamp: DateTime.utc(2026, 10, 10),
      code: ErrorCode.timeout,
      stage: DiagnosticStage.request,
      duration: const Duration(milliseconds: 12),
      requestId: '12345678-1234-4234-9234-123456789abc',
    );
    expect(event.toJson(), {
      'timestamp': '2026-10-10T00:00:00.000Z',
      'code': 'TIMEOUT',
      'stage': 'request',
      'duration': 12,
      'requestId': '12345678-1234-4234-9234-123456789abc',
    });
    expect(
      () => DiagnosticEvent(
        timestamp: DateTime.utc(2026),
        code: ErrorCode.internal,
        stage: DiagnosticStage.request,
        duration: Duration.zero,
        requestId: 'secret',
      ).toJson(),
      throwsArgumentError,
    );
  });
}
