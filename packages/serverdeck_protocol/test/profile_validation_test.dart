import 'package:serverdeck_protocol/profile_validation.dart';
import 'package:test/test.dart';

Map<String, Object?> fields({String address = 'example.test'}) => {
  'name': '  Cafe\u0301  ',
  'address': address,
  'sshUser': ' user ',
};
void main() {
  test('traditional encrypted RSA PEM is preserved with passphrase', () {
    const key =
        '-----BEGIN RSA PRIVATE KEY-----\n'
        'Proc-Type: 4,ENCRYPTED\n'
        'DEK-Info: AES-256-CBC,000102030405060708090A0B0C0D0E0F\n\n'
        'YWJj\n-----END RSA PRIVATE KEY-----\n';
    expect(
      normalizeCredential({
        'action': 'replace',
        'kind': 'privateKey',
        'privateKey': key,
        'passphrase': ' secret ',
      })['privateKey'],
      key,
    );
    expect(
      () => normalizeCredential({
        'action': 'replace',
        'kind': 'privateKey',
        'privateKey': key.replaceFirst('Proc-Type:', 'Unknown:'),
        'passphrase': null,
      }),
      throwsFormatException,
    );
  });
  test('NFC trim/defaults, scalar lengths, address and port boundaries', () {
    expect(normalizeProfileFields(fields()), {
      'name': 'Café',
      'address': 'example.test',
      'sshUser': 'user',
      'port': 22,
      'tags': <String>[],
    });
    for (final address in [
      '127.0.0.1',
      '::1',
      '2001:db8::1',
      'xn--e1afmkfd.xn--p1ai',
    ]) {
      expect(
        normalizeProfileFields(fields(address: address))['address'],
        address,
      );
    }
    for (final address in [
      'https://host',
      'host:22',
      '[::1]',
      'bad host',
      '999.999.999.999',
      'пример.рф',
    ]) {
      expect(
        () => normalizeProfileFields(fields(address: address)),
        throwsFormatException,
      );
    }
    for (final port in [0, 65536, 22.0, '22', null]) {
      expect(
        () => normalizeProfileFields({...fields(), 'port': port}),
        throwsFormatException,
      );
    }
    expect(
      normalizeProfileFields({...fields(), 'name': '😀' * 128})['name'],
      '😀' * 128,
    );
    expect(
      () => normalizeProfileFields({...fields(), 'name': '😀' * 129}),
      throwsFormatException,
    );
    expect(
      () => normalizeProfileFields({
        ...fields(),
        'tags': ['é', 'e\u0301'],
      }),
      throwsFormatException,
    );
    expect(
      () => normalizeProfileFields({...fields(), 'sshUser': 'user name'}),
      throwsFormatException,
    );
    expect(
      () => normalizeProfileFields({...fields(), 'name': 'a\u0085b'}),
      throwsFormatException,
    );
  });
  test('credential union types, byte limits, exact envelope, no secret trim', () {
    expect(
      normalizeCredential({
        'action': 'replace',
        'kind': 'password',
        'password': ' secret ',
      })['password'],
      ' secret ',
    );
    for (final password in ['', 'x' * 4097, 'bad\ntext']) {
      expect(
        () => normalizeCredential({
          'action': 'replace',
          'kind': 'password',
          'password': password,
        }),
        throwsFormatException,
      );
    }
    expect(
      () => normalizeCredential({'action': 'keep'}, creating: true),
      throwsFormatException,
    );
    const key =
        '-----BEGIN OPENSSH PRIVATE KEY-----\nYWJj\n-----END OPENSSH PRIVATE KEY-----';
    expect(
      normalizeCredential({
        'action': 'replace',
        'kind': 'privateKey',
        'privateKey': key,
        'passphrase': null,
      })['privateKey'],
      key,
    );
    expect(
      () => normalizeCredential({
        'action': 'replace',
        'kind': 'privateKey',
        'privateKey': 'BEGIN fake',
        'passphrase': null,
      }),
      throwsFormatException,
    );
    expect(
      () => normalizeCredential({'action': 'remove', 'password': 'secret'}),
      throwsFormatException,
    );
  });
}
