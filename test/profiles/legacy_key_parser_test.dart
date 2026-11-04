import '../fixtures/key_material.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/profiles/credential_parser.dart';
import 'package:serverdeck/profiles/key_envelope.dart';
import 'package:serverdeck/storage/records.dart';

Uint8List vector(String name) =>
    File('test/fixtures/ssh/$name.txt').readAsBytesSync();
Matcher fails(FailureCode code) =>
    isA<OperationFailure>().having((e) => e.code, 'code', code);
Uint8List pem(Uint8List der) => Uint8List.fromList(
  utf8.encode(SSHPem('RSA PRIVATE KEY', {}, der).encode()),
);

void main() {
  for (final name in [
    'rsa-pem-plain',
    'rsa-pkcs1',
    'rsa-pem-aes-128-cbc',
    'rsa-pem-aes-192-cbc',
    'rsa-pem-aes-256-cbc',
    'rsa-pem-des-ede3-cbc',
  ]) {
    final encrypted = name.contains('-cbc');
    test('strict PKCS1 accepts $name and keeps original bytes', () {
      final bytes = vector(name), saved = Uint8List.fromList(vector(name));
      final key = parsePrivateKey(
        bytes,
        passphrase: encrypted ? 'serverdeck-unit-passphrase' : null,
      );
      try {
        expect(key.inspection.keyType, 'ssh-rsa');
        expect(key.inspection.bits, 2048);
        expect(key.inspection.encrypted, encrypted);
        expect(bytes, saved);
        expect(key.inspection.publicKeyBytes, key.key.toPublicKey().encode());
        final hint = readPublicKeyHint(
          bytes,
          publicKeyBytes: key.inspection.publicKeyBytes,
        );
        expect(hint.encoded, key.key.toPublicKey().encode());
      } finally {
        key.dispose();
      }
    });
    if (encrypted) {
      test('$name requires phrase and distinguishes wrong/empty phrase', () {
        expect(
          () => parsePrivateKey(vector(name)),
          throwsA(fails(FailureCode.passphraseRequired)),
        );
        for (final phrase in ['', 'synthetic-wrong']) {
          expect(
            () => parsePrivateKey(vector(name), passphrase: phrase),
            throwsA(fails(FailureCode.passphraseInvalid)),
          );
        }
        expect(
          () => readPublicKeyHint(
            vector(name),
            publicKeyBytes: fixturePublicBytes(vector(name)),
          ),
          throwsA(fails(FailureCode.unsupportedKey)),
        );
      });
    }
  }
  test('legacy CRLF and outer whitespace preserve the original file', () {
    final bytes = Uint8List.fromList(
      utf8.encode(
        ' \r\n${utf8.decode(vector('rsa-pem-plain')).replaceAll('\r\n', '\n').replaceAll('\n', '\r\n')}\r\n ',
      ),
    );
    final parsed = parsePrivateKey(bytes);
    parsed.dispose();
  });
  test('strict legacy outer envelope rejects ambiguous headers and blocks', () {
    final plain = utf8.decode(vector('rsa-pem-plain'));
    final encrypted = utf8.decode(vector('rsa-pem-aes-256-cbc'));
    for (final text in [
      '$plain$plain',
      plain.replaceAll('RSA PRIVATE KEY', 'PRIVATE KEY'),
      encrypted.replaceFirst(
        'Proc-Type: 4,ENCRYPTED',
        'Proc-Type: 4,ENCRYPTED\nProc-Type: 4,ENCRYPTED',
      ),
      encrypted.replaceFirst('AES-256-CBC', 'UNKNOWN-CIPHER'),
      encrypted.replaceFirst('DEK-Info:', 'Unexpected:'),
      encrypted.replaceFirst('01020304', 'xx'),
      plain.replaceFirst('\n', '\nProc-Type: 4,ENCRYPTED\n'),
    ]) {
      expect(
        () => parsePrivateKey(Uint8List.fromList(utf8.encode(text))),
        throwsA(fails(FailureCode.unsupportedKey)),
      );
    }
  });
  test('DER rejects trailing bytes, extra integers, version and inconsistent private fields', () {
    final der = SSHPem.decode(utf8.decode(vector('rsa-pem-plain'))).content;
    final fields = (ASN1Parser(der).nextObject() as ASN1Sequence).elements;
    Uint8List change(int index, BigInt value, {bool extra = false}) {
      final seq = ASN1Sequence();
      for (var i = 0; i < fields.length; i++)
        seq.add(i == index ? ASN1Integer(value) : fields[i]);
      if (extra) seq.add(ASN1Integer(BigInt.one));
      return Uint8List.fromList(seq.encodedBytes);
    }

    for (final bytes in [
      Uint8List.fromList([...der, 0]),
      change(0, BigInt.one),
      change(8, BigInt.one),
      change(6, BigInt.one),
      change(1, BigInt.from(17)),
      change(0, BigInt.zero, extra: true),
      Uint8List.fromList([0x30, 0x80, ...der.skip(4), 0, 0]),
      Uint8List.fromList([0x30, 0x83, 0, ...der.skip(2)]),
    ]) {
      expect(
        () => parsePrivateKey(pem(bytes)),
        throwsA(fails(FailureCode.unsupportedKey)),
      );
    }
  });
  test(
    'current metadata is explicit and must match the private file envelope',
    () {
      expect(Credential().publicKeyBytes, isNull);
      expect(CredentialSchema.properties['publicKeyBytes'], isNotNull);
      final old = vector('rsa2048-encrypted');
      final before = readPublicKeyHint(
        old,
        publicKeyBytes: fixturePublicBytes(old),
      );
      expect(
        readPublicKeyHint(old, publicKeyBytes: before.encoded).encoded,
        before.encoded,
      );
      expect(
        () => readPublicKeyHint(old, publicKeyBytes: []),
        throwsA(fails(FailureCode.unsupportedKey)),
      );
      expect(
        () => readPublicKeyHint(old, publicKeyBytes: [1, 2]),
        throwsA(fails(FailureCode.unsupportedKey)),
      );
      final public = readPublicKeyHint(
        vector('rsa-pem-plain'),
        publicKeyBytes: fixturePublicBytes(vector('rsa2048')),
      ).encoded;
      expect(
        () => public.fillRange(0, public.length, 0),
        throwsUnsupportedError,
      );
    },
  );
}
