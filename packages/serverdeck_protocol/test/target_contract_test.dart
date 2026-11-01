import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_protocol/wire.dart';
import 'package:test/test.dart';

const generation = '12345678-1234-4234-9234-123456789abc';
const workspace = '22345678-1234-4234-9234-123456789abc';

void main() {
  test(
    'target readiness uses the typed schema3 boundary and captured metadata',
    () {
      final input = TrustedReadiness(
        state: ReadinessState.ready,
        generation: generation,
        workspaceId: workspace,
      ).toJson();
      final result = captureTrustedMethodResult('readiness.get', input);
      expect(result, input);
      expect(result['storageSchema'], 3);
      expect(result['apiMinor'], 1);
      input['workspaceId'] = null;
      expect(result['workspaceId'], workspace);
      expect(() => result.clear(), throwsUnsupportedError);
    },
  );

  test('old readiness/schema payloads have no alternate common parser', () {
    final current = TrustedReadiness(
      state: ReadinessState.ready,
      generation: generation,
      workspaceId: workspace,
    ).toJson();
    for (final patch in [
      {'storageSchema': 1},
      {'storageSchema': 2},
      {'apiMinor': 0},
    ]) {
      final input = {...current, ...patch};
      expect(
        () => captureTrustedMethodResult('readiness.get', input),
        throwsFormatException,
      );
      expect(
        () => validateMethodResult('readiness.get', input),
        throwsFormatException,
      );
    }
  });

  test(
    'shared target settings retain strict revisions and immutable capture',
    () {
      final settings = SettingsView(
        revision: '2',
        theme: ThemePreference.dark,
        reduceMotion: true,
        selectedProfileId: null,
      ).toJson();
      final value = <String, Object?>{
        'storeRevision': '3',
        'settings': settings,
      };
      final captured = captureTrustedMethodResult('settings.get', value);
      settings['revision'] = '0';
      expect((captured['settings'] as Map)['revision'], '2');
      expect(
        () => (captured['settings'] as Map).clear(),
        throwsUnsupportedError,
      );
      expect(
        () => captureTrustedMethodResult('settings.get', value),
        throwsFormatException,
      );
    },
  );

  test('format3 responses keep trust errors and exact retry validation', () {
    final value = <String, Object?>{
      'v': 1,
      'id': workspace,
      'generation': generation,
      'error': TrustedLocalError('TRUST_CHANGED').toJson(),
    };
    validateTrustedResponseEnvelope(value);
    expect((value['error'] as Map)['retry'], 'none');
    value['error'] = {
      ...value['error'] as Map<String, Object?>,
      'retry': 'reconnect',
    };
    expect(() => validateTrustedResponseEnvelope(value), throwsFormatException);
    value['error'] = TrustedLocalError('TRUST_CHANGED').toJson();
    value['result'] = <String, Object?>{};
    expect(() => validateTrustedResponseEnvelope(value), throwsFormatException);
  });

  test(
    'current request structure admits no caller role or capability field',
    () {
      final input = <String, Object?>{
        'v': 1,
        'id': workspace,
        'sessionId': 'A' * 43,
        'method': 'session.ping',
        'params': <String, Object?>{},
      };
      // Shape validation is not authentication or route admission.
      validateRequestEnvelope(input);
      for (final field in ['role', 'capabilities', 'owner', 'appRoot']) {
        expect(
          () => validateRequestEnvelope({...input, field: 'caller-controlled'}),
          throwsFormatException,
        );
      }
    },
  );
}
