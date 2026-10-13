import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/errors.dart';

import 'dart:convert';

import 'package:test/test.dart';

void main() {
  test('integer version required through actual wire decode in both directions', () {
    final codec = StrictCodec();
    for (final version in ['1.0', '1e0', '"1"', 'true', 'null', '2']) {
      final request = codec.decode(
        utf8.encode(
          '{"v":$version,"id":"12345678-1234-4234-8234-123456789abc","sessionId":"${'A' * 43}","method":"session.ping","params":{}}',
        ),
      );
      final response = codec.decode(
        utf8.encode(
          '{"v":$version,"id":"12345678-1234-4234-8234-123456789abc","generation":"12345678-1234-4234-8234-123456789abd","result":{}}',
        ),
      );
      expect(() => validateRequestEnvelope(request), throwsFormatException);
      expect(() => validateResponseEnvelope(response), throwsFormatException);
    }
    validateRequestEnvelope({
      'v': 1,
      'id': '12345678-1234-4234-8234-123456789abc',
      'sessionId': 'A' * 43,
      'method': 'session.ping',
      'params': <String, Object?>{},
    });
  });
  test('unsupported category is defined for unknown methods', () {
    expect(ErrorCode.unsupported.wireName, 'UNSUPPORTED');
    expect(
      () => validateMethodShape('future.method', {}),
      throwsFormatException,
    );
  });
  test(
    'method schemas reject unknown fields and incorrect credential union',
    () {
      expect(
        () => validateMethodShape('profiles.list', {'private': 'synthetic'}),
        throwsFormatException,
      );
      expect(
        () => validateMethodShape('profiles.create', {
          'profileId': '12345678-1234-4234-8234-123456789abc',
          'name': 'synthetic',
          'address': 'synthetic.invalid',
          'sshUser': 'synthetic',
          'credential': {'action': 'keep'},
        }),
        throwsFormatException,
      );
      validateMethodShape('session.ping', {});
      expect(methodParamFields.length, 12);
    },
  );
  test('uuid must be lowercase v4 with RFC variant', () {
    expect(requireUuid('12345678-1234-4234-8234-123456789abc'), isNotEmpty);
    for (final value in [
      '12345678-1234-1234-8234-123456789abc',
      '12345678-1234-4234-8234-123456789ABC',
      'bad',
    ]) {
      expect(() => requireUuid(value), throwsFormatException);
    }
  });
  test('revisions exact uint63 strings without zero or leading zero', () {
    expect(requireRevision('9223372036854775807'), isNotEmpty);
    for (final value in ['0', '01', '-1', '9223372036854775808', 1]) {
      expect(() => requireRevision(value), throwsFormatException);
    }
    expect(requireRevision('0', allowZero: true), '0');
  });
  test('unknown and missing fields rejected', () {
    expect(
      () => requireFields({'extra': 1}, {'required'}),
      throwsFormatException,
    );
  });
  test('response must contain exactly one union arm', () {
    final header = {
      'v': 1,
      'id': '12345678-1234-4234-8234-123456789abc',
      'generation': '12345678-1234-4234-8234-123456789abd',
    };
    expect(
      () => validateResponseEnvelope({...header, 'result': {}, 'error': {}}),
      throwsFormatException,
    );
    expect(() => validateResponseEnvelope(header), throwsFormatException);
    validateResponseEnvelope({...header, 'result': <String, Object?>{}});
  });
  test('response error schema excludes secret fields and invalid advice', () {
    final header = <String, Object?>{
      'v': 1,
      'id': '12345678-1234-4234-8234-123456789abc',
      'generation': '12345678-1234-4234-8234-123456789abd',
    };
    for (final code in ErrorCode.values) {
      validateResponseEnvelope({...header, 'error': LocalError(code).toJson()});
    }
    for (final error in <Map<String, Object?>>[
      {},
      {'code': 'UNKNOWN', 'boundary': 'local', 'retry': 'none'},
      {...LocalError(ErrorCode.internal).toJson(), 'stack': 'marker'},
      {...LocalError(ErrorCode.timeout).toJson(), 'retry': 'none'},
      {...LocalError(ErrorCode.validation).toJson(), 'field': 'marker'},
      {...LocalError(ErrorCode.internal).toJson(), 'field': 'password'},
      {...LocalError(ErrorCode.validation).toJson(), 'field': null},
    ]) {
      expect(
        () => validateResponseEnvelope({...header, 'error': error}),
        throwsFormatException,
      );
    }
  });
  test('request session encoding rejects noncanonical base64url pad bits', () {
    final request = <String, Object?>{
      'v': 1,
      'id': '12345678-1234-4234-8234-123456789abc',
      'sessionId': 'a' * 43,
      'method': 'session.ping',
      'params': <String, Object?>{},
    };
    expect(() => validateRequestEnvelope(request), throwsFormatException);
  });
}
