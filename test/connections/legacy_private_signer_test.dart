import '../fixtures/key_material.dart';

import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/src/hostkey/hostkey_rsa.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/connections/private_signer.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/profiles/credential_parser.dart';
import 'package:serverdeck/profiles/key_envelope.dart';

Uint8List vector(String name) =>
    File('test/fixtures/ssh/$name.txt').readAsBytesSync();

void main() {
  for (final name in [
    'rsa-pem-plain',
    'rsa-pem-aes-128-cbc',
    'rsa-pem-aes-192-cbc',
    'rsa-pem-aes-256-cbc',
    'rsa-pem-des-ede3-cbc',
  ]) {
    for (final scheme in [
      PrivateSignatureScheme.rsa256,
      PrivateSignatureScheme.rsa512,
    ]) {
      test(
        '$name signs ${scheme.wire} in the owned worker with frozen public binding',
        () async {
          final signer = PrivateSigner();
          final expected = readPublicKeyHint(
            vector('rsa-pem-plain'),
            publicKeyBytes: fixturePublicBytes(vector('rsa2048')),
          );
          final challenge = Uint8List.fromList([3, 6, 9, 12]);
          try {
            final signature = await signer.sign(
              vector(name),
              scheme,
              challenge,
              expectedPublicKey: expected.encoded,
              passphrase: name == 'rsa-pem-plain'
                  ? null
                  : 'serverdeck-unit-passphrase',
            );
            expect(
              (expected.toPublicKey() as SSHRsaPublicKey).verify(
                challenge,
                signature as SSHRsaSignature,
              ),
              isTrue,
            );
            expect(signature.type, scheme.wire);
          } finally {
            await signer.dispose();
          }
        },
      );
    }
  }
  test('wrong public metadata produces no signature even for a valid PEM private file', () async {
    final signer = PrivateSigner();
    try {
      await expectLater(
        signer.sign(
          vector('rsa-pem-plain'),
          PrivateSignatureScheme.rsa256,
          Uint8List.fromList([1]),
          expectedPublicKey: readPublicKeyHint(
            vector('ed25519'),
            publicKeyBytes: fixturePublicBytes(vector('ed25519')),
          ).encoded,
        ),
        throwsA(
          isA<OperationFailure>().having(
            (e) => e.code,
            'code',
            FailureCode.unsupportedKey,
          ),
        ),
      );
    } finally {
      await signer.dispose();
    }
  });
  test('encrypted PEM identity uses stored public hint and requests phrase at signing only', () async {
    final file = vector('rsa-pem-aes-256-cbc');
    final parsed = parsePrivateKey(
      file,
      passphrase: 'serverdeck-unit-passphrase',
    );
    final inspection = parsed.inspection;
    parsed.dispose();
    final hint = readPublicKeyHint(
      file,
      publicKeyBytes: inspection.publicKeyBytes,
    );
    final signer = PrivateSigner();
    var prompts = 0;
    final identity = OwnedPrivateIdentity(
      file: file,
      credentialRevision: 1,
      expected: inspection,
      publicHint: hint,
      signer: signer,
      checkAdmission: (_) {},
      serverAlgorithms: () => ['rsa-sha2-512'],
      requestPassphrase: () async {
        prompts++;
        return 'serverdeck-unit-passphrase';
      },
      remainingBudget: () => const Duration(seconds: 30),
    );
    try {
      expect(identity.toPublicKey().encode(), hint.encoded);
      expect(prompts, 0);
      final challenge = Uint8List.fromList([5, 7, 9]);
      final signature = await identity.sign(challenge) as SSHRsaSignature;
      expect(prompts, 1);
      expect(
        (hint.toPublicKey() as SSHRsaPublicKey).verify(challenge, signature),
        isTrue,
      );
    } finally {
      identity.dispose();
      await signer.dispose();
    }
  });
}
