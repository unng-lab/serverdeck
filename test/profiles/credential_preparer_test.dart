import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/profiles/credential_input.dart';
import 'package:serverdeck/profiles/credential_parser.dart';
import 'package:serverdeck/profiles/key_parse_worker.dart';

const credentialId = '9308c17a-4fa6-45e3-baa8-6b6dd67dadbb';

final class Protector implements SecretProtector {
  Future<Uint8List> Function(Uint8List, String)? onProtect;
  @override
  Future<Uint8List> protect(Uint8List bytes, String purpose) =>
      onProtect!(bytes, purpose);
}

final class Inspector implements KeyInspector {
  Future<KeyInspection> Function(Uint8List, String?, CredentialCancellation?)?
  onInspect;
  @override
  Future<KeyInspection> inspect(
    Uint8List bytes, {
    String? passphrase,
    CredentialCancellation? cancellation,
    Duration timeout = const Duration(seconds: 30),
  }) => onInspect!(bytes, passphrase, cancellation);
}

Matcher protectionFailure = isA<OperationFailure>().having(
  (e) => e.code,
  'code',
  FailureCode.protectionUnavailable,
);

void main() {
  test(
    'password bytes remain exact; owned copies clear after protection',
    () async {
      final input = PasswordInput('  Синтетический\n');
      final protector = Protector();
      late Uint8List retainedPlain;
      final cipher = Uint8List.fromList([51, 52]);
      protector.onProtect = (bytes, purpose) async {
        retainedPlain = bytes;
        expect(bytes, utf8.encode(input.password));
        expect(purpose, 'credential.v1:$credentialId');
        return cipher;
      };
      final prepared = await CredentialPreparer(
        protector,
        Inspector(),
      ).prepare(input, credentialId: credentialId);
      expect(prepared.kind, AuthKind.password);
      expect(prepared.inspection, isNull);
      expect(prepared.ciphertext, [51, 52]);
      expect(retainedPlain.every((b) => b == 0), isTrue);
      expect(cipher, [0, 0]);
      final retainedCipher = prepared.ciphertext;
      prepared.dispose();
      expect(retainedCipher, [0, 0]);
      expect(() => prepared.ciphertext, throwsStateError);
      expect(input.password, '  Синтетический\n');
      input.dispose();
    },
  );

  test(
    'private key protection uses original file bytes and no passphrase',
    () async {
      final original = File('test/fixtures/ssh/ed25519-encrypted.txt')
          .readAsBytesSync();
      final input = PrivateKeyInput(
        original,
        passphrase: 'serverdeck-unit-passphrase',
      );
      final parser = CancellableKeyParser();
      final protector = Protector()
        ..onProtect = (bytes, purpose) async {
          expect(bytes, original);
          return Uint8List.fromList([72]);
        };
      final prepared = await CredentialPreparer(
        protector,
        parser,
      ).prepare(input, credentialId: credentialId);
      expect(prepared.inspection!.encrypted, isTrue);
      expect(prepared.inspection!.keyType, 'ssh-ed25519');
      expect(prepared.kind, AuthKind.privateKey);
      expect(input.bytes, original);
      prepared.dispose();
      input.dispose();
      await parser.dispose();
    },
  );

  test('cancellation after key validation prevents protection', () async {
    final cancel = CredentialCancellation();
    final inspector = Inspector()
      ..onInspect = (bytes, phrase, cancellation) async {
        expect(cancellation, same(cancel));
        cancel.cancel();
        return const KeyInspection(
          keyType: 'ssh-ed25519',
          bits: 256,
          encrypted: false,
        );
      };
    final input = PrivateKeyInput(Uint8List.fromList([1]));
    await expectLater(
      CredentialPreparer(
        Protector(),
        inspector,
      ).prepare(input, credentialId: credentialId, cancellation: cancel),
      throwsA(isA<CredentialCancelled>()),
    );
    input.dispose();
  });

  test(
    'late protection after cancel is discarded and all owned bytes cleared',
    () async {
      final cancel = CredentialCancellation();
      final complete = Completer<Uint8List>();
      late Uint8List plain;
      final protector = Protector()
        ..onProtect = (bytes, _) {
          plain = bytes;
          return complete.future;
        };
      final input = PasswordInput('synthetic');
      final expectation = expectLater(
        CredentialPreparer(
          protector,
          Inspector(),
        ).prepare(input, credentialId: credentialId, cancellation: cancel),
        throwsA(isA<CredentialCancelled>()),
      );
      cancel.cancel();
      final cipher = Uint8List.fromList([1, 2]);
      complete.complete(cipher);
      await expectation;
      expect(plain.every((b) => b == 0), isTrue);
      expect(cipher, [0, 0]);
      input.dispose();
    },
  );

  for (final mode in ['throw', 'empty', 'oversized']) {
    test('protection $mode is a fixed failure and clears plaintext', () async {
      late Uint8List plain;
      final protector = Protector()
        ..onProtect = (bytes, _) async {
          plain = bytes;
          if (mode == 'throw') throw StateError('SYNTHETIC_SECRET');
          return Uint8List(mode == 'empty' ? 0 : 2 * 1024 * 1024 + 1);
        };
      final input = PasswordInput('synthetic');
      await expectLater(
        CredentialPreparer(
          protector,
          Inspector(),
        ).prepare(input, credentialId: credentialId),
        throwsA(protectionFailure),
      );
      expect(plain.every((b) => b == 0), isTrue);
      input.dispose();
    });
  }

  test(
    'invalid credential ID and pre-cancelled input never reach adapters',
    () async {
      final input = PasswordInput('synthetic');
      final preparer = CredentialPreparer(Protector(), Inspector());
      await expectLater(
        preparer.prepare(input, credentialId: 'bad'),
        throwsA(isA<OperationFailure>()),
      );
      await expectLater(
        preparer.prepare(
          input,
          credentialId: credentialId,
          cancellation: CredentialCancellation()..cancel(),
        ),
        throwsA(isA<CredentialCancelled>()),
      );
      input.dispose();
    },
  );
}
