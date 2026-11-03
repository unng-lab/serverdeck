import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/profiles/credential_input.dart';

ProfileDraft draft({
  String name = ' Server ',
  String host = 'EXAMPLE.test.',
  int port = 22,
  String username = 'CaseSensitive',
}) => ProfileDraft(
  displayName: name,
  host: host,
  port: port,
  username: username,
  authentication: PasswordInput('synthetic'),
);

void main() {
  test('profile validation trims only name and canonicalizes endpoint', () {
    final result = validateProfileFields(draft());
    expect(result.displayName, 'Server');
    expect(result.originalHost, 'EXAMPLE.test.');
    expect(result.normalizedHost, 'example.test');
    expect(result.username, 'CaseSensitive');
    expect(result.port, 22);
    expect(
      result.endpointId,
      validateProfileFields(draft(host: 'example.test')).endpointId,
    );
    expect(
      result.endpointId,
      isNot(
        validateProfileFields(draft(host: 'example.test', port: 23)).endpointId,
      ),
    );
  });
  test(
    'IPv6 textual aliases use the same endpoint, DNS and IP stay separate',
    () {
      final expanded = validateProfileFields(
        draft(host: '2001:0db8:0:0:0:0:0:1'),
      );
      final short = validateProfileFields(draft(host: '2001:db8::1'));
      expect(expanded.endpointId, short.endpointId);
      expect(
        validateProfileFields(draft(host: '[2001:0db8::1]')).endpointId,
        short.endpointId,
      );
      expect(
        validateProfileFields(draft(host: '[::1]')).endpointId,
        validateProfileFields(draft(host: '::1')).endpointId,
      );
      expect(short.normalizedHost, '2001:db8::1');
      expect(
        validateProfileFields(draft(host: '127.0.0.1')).endpointId,
        isNot(validateProfileFields(draft(host: 'localhost')).endpointId),
      );
    },
  );
  for (final host in [
    'https://example.test',
    'user@example.test',
    'x:22',
    '127.0.0.1:22',
    '[::1]:22',
    '[fe80::1%12]',
    '[[::1]]',
    '[::1',
    '::1]',
    '[127.0.0.1]',
    '[example.test]',
    'example.test/path',
    ' example.test',
    'x..',
    '-x.test',
    'x_.test',
    'пример.рф',
    'fe80::1%12',
    'x\\path',
  ]) {
    test('invalid host rejected as a host field: $host', () {
      expect(
        () => validateProfileFields(draft(host: host)),
        throwsA(
          isA<OperationFailure>().having(
            (e) => e.field,
            'field',
            OperationField.host,
          ),
        ),
      );
    });
  }
  for (final name in ['', '  ', List.filled(101, 'я').join()]) {
    test('invalid display name length is field-specific (${name.length})', () {
      expect(
        () => validateProfileFields(draft(name: name)),
        throwsA(
          isA<OperationFailure>().having(
            (e) => e.field,
            'field',
            OperationField.displayName,
          ),
        ),
      );
    });
  }
  for (final username in [
    ' user',
    'user name',
    'user\n',
    'u\u0000',
    'u\u200b',
    List.filled(256, 'x').join(),
  ]) {
    test(
      'username is not trimmed and rejects space/control (${username.length})',
      () {
        expect(
          () => validateProfileFields(draft(username: username)),
          throwsA(
            isA<OperationFailure>().having(
              (e) => e.field,
              'field',
              OperationField.username,
            ),
          ),
        );
      },
    );
  }
  for (final port in [0, 65536]) {
    test('port $port is rejected before I/O', () {
      expect(
        () => validateProfileFields(draft(port: port)),
        throwsA(
          isA<OperationFailure>().having(
            (e) => e.field,
            'field',
            OperationField.port,
          ),
        ),
      );
    });
  }
  test('Unicode scalar limits and UTF8 secret identity do not silently replace data', () {
    expect(
      validateProfileFields(draft(name: List.filled(100, '😀').join()))
          .displayName
          .runes
          .length,
      100,
    );
    expect(() => PasswordInput('\ud800'), throwsA(isA<OperationFailure>()));
    expect(
      () => PrivateKeyInput(Uint8List.fromList([1]), passphrase: '\udc00'),
      throwsA(isA<OperationFailure>()),
    );
  });
}
