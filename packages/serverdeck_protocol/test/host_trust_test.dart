import 'dart:convert';
import 'dart:typed_data';

import 'package:serverdeck_protocol/errors.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:test/test.dart';

const workspace = '11111111-1111-4111-8111-111111111111';
const profile = '22222222-2222-4222-8222-222222222222';
const request = '33333333-3333-4333-8333-333333333333';
final fingerprint =
    'SHA256:${base64.encode(List.filled(32, 1)).replaceAll('=', '')}';
Map<String, Object?> key() => {
  'format': 'ssh-ed25519',
  'fingerprint': fingerprint,
};
Map<String, Object?> record() => {
  'workspaceId': workspace,
  'profileId': profile,
  'revision': '2',
  'connectionRevision': '1',
  'status': 'trusted',
  'key': key(),
  'createdAt': '2026-10-22T00:00:00.000Z',
  'updatedAt': '2026-10-22T00:00:00.000Z',
};

void main() {
  test(
    'shared canonical pin roundtrip preserves negotiated algorithm rules',
    () {
      final pin = SshHostPin.fromJson(key());
      expect(pin.toJson(), key());
      for (final algorithm in ['rsa-sha2-256', 'rsa-sha2-512']) {
        expect(
          SshHostPin.fromCallback(
            algorithm,
            Uint8List.fromList(utf8.encode(fingerprint)),
          ).format,
          'ssh-rsa',
        );
      }
      expect(
        () => SshHostPin.fromCallback(
          'ssh-rsa',
          Uint8List.fromList(utf8.encode(fingerprint)),
        ),
        throwsA(isA<SshTransportFailure>()),
      );
      expect(
        () => SshHostPin.fromJson({...key(), 'owner': true}),
        throwsFormatException,
      );
      expect(
        () => SshHostPin.fromJson({...key(), 'fingerprint': '$fingerprint='}),
        throwsA(isA<SshTransportFailure>()),
      );
      expect(pin.toString(), 'SshHostPin');
    },
  );

  test(
    'trust metadata is exact immutable and public view omits only workspace',
    () {
      final input = record();
      final parsed = HostTrustRecord.fromJson(input);
      (input['key'] as Map)['format'] = 'invalid';
      input['status'] = 'revoked';
      expect(parsed.toJson(), record());
      final output = parsed.toJson();
      (output['key'] as Map)['fingerprint'] = 'changed';
      expect(parsed.toJson(), record());
      expect(parsed.toPublicJson(), record()..remove('workspaceId'));
      expect(parsed.status, HostTrustStatus.trusted);
      expect(parsed.toString(), 'HostTrustRecord');
      final revoked = HostTrustRecord.fromJson({
        ...record(),
        'status': 'revoked',
        'revision': '4',
      });
      expect(revoked.status, HostTrustStatus.revoked);
      expect(
        HostTrustRecord.fromJson({
          ...record(),
          'revision': '9223372036854775807',
        }).revision,
        '9223372036854775807',
      );
    },
  );

  test(
    'impossible metadata bounds shapes and times fail without normalization',
    () {
      for (final patch in <Map<String, Object?>>[
        {'workspaceId': 'bad'},
        {'profileId': null},
        {'revision': '0'},
        {'revision': '9223372036854775808'},
        {'revision': 2},
        {'connectionRevision': '3'},
        {'status': 'unknown'},
        {'key': null},
        {
          'key': {...key(), 'path': '/private'},
        },
        {'createdAt': '2026-10-23T00:00:00.000Z'},
        {'updatedAt': '2026-02-30T00:00:00.000Z'},
        {'updatedAt': '2026-10-22T00:00:00Z'},
        {'extra': true},
        {
          'key': {'format': 'ssh-ed25519', 'fingerprint': 'x' * 5000},
        },
      ]) {
        expect(
          () => HostTrustRecord.fromJson({...record(), ...patch}),
          throwsFormatException,
        );
      }
    },
  );

  test('format3 errors preserve every legacy value and exact retry', () {
    expect(ErrorCode.values.length, 15);
    expect(TrustedLocalError.codes.length, 21);
    for (final code in ErrorCode.values) {
      final legacy = LocalError(code);
      final trusted = TrustedLocalError(code.wireName);
      expect(trusted.toJson(), legacy.toJson());
      expect(trusted.retry, legacy.retry);
      expect(
        TrustedLocalError.fromJson(trusted.toJson()).toJson(),
        trusted.toJson(),
      );
    }
    for (final code in [
      'TRUST_REQUIRED',
      'TRUST_CHANGED',
      'HOST_BUSY',
      'AUTHENTICATION_FAILED',
      'CANCELLED',
    ]) {
      final error = TrustedLocalError(code);
      expect(error.toJson(), {
        'code': code,
        'boundary': 'local',
        'retry': 'none',
      });
      expect(error.retry, RetryAdvice.none);
      expect(requireTrustFailureCode(code), code);
      expect(ErrorCode.values.any((value) => value.wireName == code), isFalse);
    }
    expect(TrustedLocalError('CONNECTION_FAILED').retry, RetryAdvice.reconnect);
    expect(
      TrustedLocalError('VALIDATION', field: 'profileId').toJson(),
      LocalError(ErrorCode.validation, field: 'profileId').toJson(),
    );
  });

  test('transport failures map exhaustively without raw code expansion', () {
    expect(SshTransportCode.values.length, 8);
    for (final code in SshTransportCode.values) {
      final error = TrustedLocalError.fromTransport(code);
      expect(
        error.code,
        code == SshTransportCode.VALIDATION_ERROR ? 'VALIDATION' : code.name,
      );
      expect(TrustedLocalError.fromJson(error.toJson()).code, error.code);
      expect(requireTrustFailureCode(error.code), error.code);
    }
    expect(() => TrustedLocalError.codes.add('fake'), throwsUnsupportedError);
  });

  test(
    'unknown codes invalid retry fields and error envelopes are rejected',
    () {
      for (final input in <Map<String, Object?>>[
        {'code': 'future', 'boundary': 'local', 'retry': 'none'},
        {'code': 'TRUST_REQUIRED', 'boundary': 'host', 'retry': 'none'},
        {
          'code': 'TRUST_CHANGED',
          'boundary': 'local',
          'retry': 'retry-same-request',
        },
        {'code': 'TIMEOUT', 'boundary': 'local', 'retry': 'none'},
        {
          'code': 'TRUST_REQUIRED',
          'boundary': 'local',
          'retry': 'none',
          'field': 'profileId',
        },
        {
          'code': 'VALIDATION',
          'boundary': 'local',
          'retry': 'none',
          'field': 'challengeId',
        },
        {
          'code': 'VALIDATION',
          'boundary': 'local',
          'retry': 'none',
          'field': null,
        },
        {
          'code': 'CONNECTION_FAILED',
          'boundary': 'local',
          'retry': 'reconnect',
          'message': 'private',
        },
      ]) {
        expect(() => TrustedLocalError.fromJson(input), throwsFormatException);
      }
      expect(
        () => requireTrustFailureCode('VALIDATION_ERROR'),
        throwsFormatException,
      );
      expect(() => requireTrustFailureCode(1), throwsFormatException);
    },
  );

  test(
    'owner command capture covers the closed six methods and stays immutable',
    () {
      final calls = <String, Map<String, Object?>>{
        'servers.trust.get': {'profileId': profile},
        'servers.trust.probe': {'profileId': profile, 'expectedRevision': '1'},
        'servers.trust.probeStatus': {'operationId': request},
        'servers.trust.probeCancel': {'operationId': request},
        'servers.trust.confirm': {
          'profileId': profile,
          'expectedRevision': '1',
          'challengeId': request,
          'key': key(),
        },
        'servers.trust.revoke': {'profileId': profile, 'expectedRevision': '2'},
      };
      for (final call in calls.entries) {
        final captured = captureHostTrustParams(call.key, call.value);
        expect(captured, call.value);
        expect(() => captured['owner'] = true, throwsUnsupportedError);
        expect(
          () =>
              captureHostTrustParams(call.key, {...call.value, 'owner': true}),
          throwsFormatException,
        );
      }
      final input = calls['servers.trust.confirm']!;
      final captured = captureHostTrustParams('servers.trust.confirm', input);
      (input['key'] as Map)['format'] = 'invalid';
      expect(captured['key'], key());
      expect(
        () => (captured['key'] as Map)['format'] = 'invalid',
        throwsUnsupportedError,
      );
    },
  );

  test(
    'owner command capture rejects coercion aliases and missing required keys',
    () {
      for (final value in [null, '0', '01', '9223372036854775808', 1.0]) {
        expect(
          () => captureHostTrustParams('servers.trust.revoke', {
            'profileId': profile,
            'expectedRevision': value,
          }),
          throwsFormatException,
        );
      }
      expect(
        () => captureHostTrustParams('servers.trust.probe', {
          'profileId': profile,
        }),
        throwsFormatException,
      );
      expect(
        () => captureHostTrustParams('servers.trust.probeStatus', {
          'operationId': 'bad',
        }),
        throwsFormatException,
      );
      expect(
        () => captureHostTrustParams('servers.trust.confirm', {
          'profileId': profile,
          'expectedRevision': '1',
          'challengeId': request,
          'key': {...key(), 'format': 'rsa-sha2-512'},
        }),
        throwsFormatException,
      );
      expect(
        () => captureHostTrustParams('servers.trust.shell', {}),
        throwsFormatException,
      );
    },
  );
}
