import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:test/test.dart';

const workspace = '12345678-1234-4234-9234-123456789abc';
const receiptKeyId = '12345678-1234-4234-9234-123456789abd';
const profileId = '12345678-1234-4234-9234-123456789abe';
const credentialId = '12345678-1234-4234-9234-123456789abf';
void main() {
  test('real CurrentUser credentials have independent identity and preserve secret input', () async {
    final custody = KeyCustody(DpapiProtection(), currentUserSid());
    const decomposed = ' e\u0301 secret ';
    final unicodeBlob = await custody.wrapCredential(
      workspace,
      profileId,
      credentialId,
      {'action': 'replace', 'kind': 'password', 'password': decomposed},
    );
    expect(
      (await custody.openCredential(
        unicodeBlob,
        workspace,
        profileId,
        credentialId,
      ))['password'],
      decomposed,
    );
    final blob = await custody.wrapCredential(
      workspace,
      profileId,
      credentialId,
      {
        'action': 'replace',
        'kind': 'password',
        'password': ' synthetic-private-marker ',
      },
    );
    final secret = await custody.openCredential(
      blob,
      workspace,
      profileId,
      credentialId,
    );
    expect(secret['password'], ' synthetic-private-marker ');
    const pem =
        '-----BEGIN RSA PRIVATE KEY-----\nProc-Type: 4,ENCRYPTED\n'
        'DEK-Info: AES-256-CBC,000102030405060708090A0B0C0D0E0F\n\n'
        'YWJj\n-----END RSA PRIVATE KEY-----\n';
    final keyBlob = await custody.wrapCredential(
      workspace,
      profileId,
      credentialId,
      {
        'action': 'replace',
        'kind': 'privateKey',
        'privateKey': pem,
        'passphrase': ' test ',
      },
    );
    final recoveredKey = await custody.openCredential(
      keyBlob,
      workspace,
      profileId,
      credentialId,
    );
    expect(recoveredKey, {
      'kind': 'privateKey',
      'privateKey': pem,
      'passphrase': ' test ',
    });
    await expectLater(
      custody.openCredential(blob, workspace, profileId, receiptKeyId),
      throwsStateError,
    );
    await expectLater(
      custody.openCredential(blob, workspace, receiptKeyId, credentialId),
      throwsStateError,
    );
    await expectLater(
      custody.openCredential('corrupt', workspace, profileId, credentialId),
      throwsStateError,
    );
  }, testOn: 'windows');
}
