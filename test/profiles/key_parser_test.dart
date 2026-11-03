import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/profiles/credential_parser.dart';

Uint8List fixture(String name) =>
    File('test/fixtures/ssh/$name.txt').readAsBytesSync();

void main() {
  for (final type in ['ed25519', 'rsa2048']) {
    test('empty passphrase is invalid for supported encrypted $type', () {
      expect(
        () => parseOpenSshKey(fixture('$type-encrypted'), passphrase: ''),
        throwsA(
          isA<OperationFailure>()
              .having((e) => e.code, 'code', FailureCode.passphraseInvalid)
              .having((e) => e.field, 'field', OperationField.passphrase),
        ),
      );
    });
    for (final encrypted in [false, true]) {
      test(
        'parses $type encrypted=$encrypted and preserves original bytes',
        () {
          final original = fixture('$type${encrypted ? '-encrypted' : ''}');
          final saved = Uint8List.fromList(original);
          final key = parseOpenSshKey(
            original,
            passphrase: encrypted ? 'serverdeck-unit-passphrase' : null,
          );
          expect(
            key.inspection.keyType,
            type == 'ed25519' ? 'ssh-ed25519' : 'ssh-rsa',
          );
          expect(key.inspection.bits, type == 'ed25519' ? 256 : 2048);
          expect(key.inspection.encrypted, encrypted);
          expect(key.key.toPublicKey().encode(), isNotEmpty);
          expect(original, saved);
          expect(key.toString(), 'ParsedPrivateKey(redacted)');
          key.dispose();
          expect(() => key.key, throwsStateError);
        },
      );
    }
  }
  test(
    'encrypted key requires passphrase and rejects a wrong one without echo',
    () {
      final input = fixture('ed25519-encrypted');
      expect(
        () => parseOpenSshKey(input),
        throwsA(
          isA<OperationFailure>().having(
            (e) => e.code,
            'code',
            FailureCode.passphraseRequired,
          ),
        ),
      );
      expect(
        () => parseOpenSshKey(input, passphrase: 'SYNTHETIC_WRONG'),
        throwsA(
          isA<OperationFailure>()
              .having((e) => e.code, 'code', FailureCode.passphraseInvalid)
              .having(
                (e) => e.toString(),
                'message',
                isNot(contains('SYNTHETIC_WRONG')),
              ),
        ),
      );
    },
  );
  for (final unsupported in ['ecdsa', 'rsa-pkcs1', 'public-key']) {
    test('rejects $unsupported instead of falling back to another parser', () {
      expect(
        () => parseOpenSshKey(fixture(unsupported)),
        throwsA(
          isA<OperationFailure>().having(
            (e) => e.code,
            'code',
            FailureCode.unsupportedKey,
          ),
        ),
      );
    });
  }
  test('rejects multiple PEM blocks and malformed UTF8', () {
    final bytes = fixture('ed25519');
    expect(
      () => parseOpenSshKey(Uint8List.fromList([...bytes, ...bytes])),
      throwsA(isA<OperationFailure>()),
    );
    expect(
      () => parseOpenSshKey(Uint8List.fromList([0xff, 0xfe])),
      throwsA(isA<OperationFailure>()),
    );
  });
  test('rejects inconsistent public/private and invalid OpenSSH padding', () {
    final container = OpenSSHKeyPairs.decode(
      SSHPem.decode(utf8.decode(fixture('ed25519'))).content,
    );
    final public = Uint8List.fromList(container.publicKeys.single)..last ^= 1;
    final inconsistent = OpenSSHKeyPairs.unencrypted(
      publicKeys: [public],
      privateKeyBlob: container.privateKeyBlob,
    );
    expect(
      () => parseOpenSshKey(
        Uint8List.fromList(utf8.encode(inconsistent.toPem())),
      ),
      throwsA(isA<OperationFailure>()),
    );
    final private = Uint8List.fromList(container.privateKeyBlob)..last = 255;
    final malformed = OpenSSHKeyPairs.unencrypted(
      publicKeys: container.publicKeys,
      privateKeyBlob: private,
    );
    expect(
      () => parseOpenSshKey(Uint8List.fromList(utf8.encode(malformed.toPem()))),
      throwsA(isA<OperationFailure>()),
    );
  });
  test(
    'rejects container with more than one key before reading private data',
    () {
      final container = OpenSSHKeyPairs.decode(
        SSHPem.decode(utf8.decode(fixture('ed25519'))).content,
      );
      final multi = OpenSSHKeyPairs.unencrypted(
        publicKeys: [container.publicKeys.single, container.publicKeys.single],
        privateKeyBlob: container.privateKeyBlob,
      );
      expect(
        () => parseOpenSshKey(Uint8List.fromList(utf8.encode(multi.toPem()))),
        throwsA(isA<OperationFailure>()),
      );
    },
  );
}
