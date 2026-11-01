import 'package:serverdeck_protocol/automation/direct_ssh_dispatch.dart';
import 'package:test/test.dart';

Map<String, Object?> dispatch({
  String state = 'authorized',
  int issued = 1000,
  int expires = 6000,
}) => {
  'format': 1,
  'stepId': 'e1',
  'stepDigest': 'a' * 64,
  'token': '12345678-1234-4234-9234-123456789abc',
  'bootIdHash': 'b' * 64,
  'issuedUptimeMs': issued,
  'expiresUptimeMs': expires,
  'authorityBindingDigest': 'c' * 64,
  'targetBindingDigest': 'd' * 64,
  'authorizedAt': '2026-11-01T00:00:00.000Z',
  'grantRevision': null,
  'grantExpiresAt': null,
  'state': state,
};

void main() {
  test('permit uses one exact boot, identity and bounded uptime window', () {
    final input = dispatch();
    final permit = DirectSshDispatch.fromJson(input);
    input['token'] = null;
    expect(permit.canStartAt('b' * 64, 1000), isTrue);
    expect(permit.canStartAt('b' * 64, 6000), isTrue);
    expect(permit.canStartAt('b' * 64, 6001), isFalse);
    expect(permit.canStartAt('b' * 64, 999), isFalse);
    expect(permit.canStartAt('e' * 64, 1000), isFalse);
    expect(permit.token, '12345678-1234-4234-9234-123456789abc');
    expect(permit.toJson(), dispatch());
  });

  test('malformed or renewed permits cannot enter the closed schema', () {
    for (final patch in <Map<String, Object?>>[
      {'format': 1.0},
      {'stepId': '../e1'},
      {'stepDigest': 'a' * 63},
      {'token': 'not-a-token'},
      {'issuedUptimeMs': -1},
      {'issuedUptimeMs': 1000.0},
      {'expiresUptimeMs': 6001},
      {'expiresUptimeMs': 1000},
      {'expiresUptimeMs': 999},
      {'authorityBindingDigest': null},
      {'state': 'retry'},
      {'authorizedAt': 'not-a-time'},
      {'grantRevision': 1},
      {'grantExpiresAt': '2026-11-01T01:00:00.000Z'},
      {'grantRevision': 0, 'grantExpiresAt': '2026-11-01T01:00:00.000Z'},
      {'grantRevision': 1, 'grantExpiresAt': '2026-11-01T00:00:00.000Z'},
      {'grantRevision': 1, 'grantExpiresAt': '2026-11-01T00:00:04.999Z'},
      {'unexpected': 'secret'},
    ]) {
      expect(
        () => DirectSshDispatch.fromJson({...dispatch(), ...patch}),
        throwsFormatException,
      );
    }
  });

  test(
    'an existing token may only advance without changing its permission',
    () {
      final authorized = DirectSshDispatch.fromJson(dispatch());
      final sent = DirectSshDispatch.fromJson(dispatch(state: 'sent'));
      final unknown = DirectSshDispatch.fromJson(dispatch(state: 'unknown'));
      final completed = DirectSshDispatch.fromJson(
        dispatch(state: 'completed'),
      );
      authorized.validateTransitionTo(sent);
      sent.validateTransitionTo(unknown);
      unknown.validateTransitionTo(completed);
      completed.validateTransitionTo(completed);
      expect(
        () => sent.validateTransitionTo(authorized),
        throwsFormatException,
      );
      expect(() => unknown.validateTransitionTo(sent), throwsFormatException);
      expect(
        () => completed.validateTransitionTo(unknown),
        throwsFormatException,
      );
      expect(
        () => sent.validateTransitionTo(
          DirectSshDispatch.fromJson({
            ...dispatch(state: 'sent'),
            'expiresUptimeMs': 5999,
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => sent.validateTransitionTo(
          DirectSshDispatch.fromJson({
            ...dispatch(state: 'sent'),
            'targetBindingDigest': 'e' * 64,
          }),
        ),
        throwsFormatException,
      );
      expect(completed.canStartAt('b' * 64, 2000), isFalse);
      expect(unknown.canStartAt('b' * 64, 2000), isFalse);
    },
  );
}
