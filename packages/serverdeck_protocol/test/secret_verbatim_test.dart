import 'dart:convert';

import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/profile_validation.dart';
import 'package:test/test.dart';

void main() {
  test('wire encoding and credential validation preserve byte-different secrets', () {
    const secret = ' e\u0301 secret ';
    const key =
        '-----BEGIN PRIVATE KEY-----\r\nYWJj\r\n-----END PRIVATE KEY-----\r\n';
    final codec = StrictCodec();
    final wire = codec.decode(
      codec.encode({
        'name': 'e\u0301',
        'credential': {
          'action': 'replace',
          'kind': 'privateKey',
          'privateKey': key,
          'passphrase': secret,
        },
      }),
    );
    expect(wire['name'], '\u00e9');
    final action = normalizeCredential(
      wire['credential'] as Map<String, Object?>,
    );
    expect(action['privateKey'], key);
    expect(action['passphrase'], secret);
    expect(
      normalizeCredential({
        'action': 'replace',
        'kind': 'password',
        'password': secret,
      })['password'],
      secret,
    );
    expect(
      codec.canonical({'password': 'e\u0301'}),
      isNot(codec.canonical({'password': '\u00e9'})),
    );
    expect(
      utf8.decode(codec.canonical({'password': secret})),
      contains(secret),
    );
    expect(
      () => normalizeCredential({
        'action': 'replace',
        'kind': 'password',
        'password': '\ud800',
      }),
      throwsFormatException,
    );
  });
}
