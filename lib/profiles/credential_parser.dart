import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/src/hostkey/hostkey_ed25519.dart';
import 'package:dartssh2/src/hostkey/hostkey_rsa.dart';
import 'package:dartssh2/src/ssh_message.dart';
import 'package:dartssh2/src/utils/bcrypt.dart';
import 'package:dartssh2/src/utils/cipher_ext.dart';

import '../domain/models.dart';
import 'key_envelope.dart';
export 'key_envelope.dart' show KeyInspection;

/// Private attempt material, never an operation projection or persistent record.
final class ParsedPrivateKey {
  ParsedPrivateKey._(this._key, this.inspection);
  SSHKeyPair? _key;
  final KeyInspection inspection;
  SSHKeyPair get key => _key ?? (throw StateError('Private material cleared'));
  void dispose() {
    _clearKey(_key);
    _key = null;
  }

  @override
  String toString() => 'ParsedPrivateKey(redacted)';
}

void _clearKey(SSHKeyPair? key) {
  if (key is OpenSSHEd25519KeyPair)
    key.privateKey.fillRange(0, key.privateKey.length, 0);
  // BigInt/private library internals are immutable: no claim of GC-wide wiping.
}

const _unsupported = OperationFailure(
  FailureCode.unsupportedKey,
  field: OperationField.authentication,
);

/// Pure parser unit. Production calls it only in an owned, cancellable isolate.
/// Never serializes a parsed key; the caller protects the ORIGINAL input bytes.
ParsedPrivateKey parseOpenSshKey(Uint8List original, {String? passphrase}) {
  Uint8List? plaintext, passwordBytes, derived;
  OpenSshEnvelope? envelope;
  SSHKeyPair? owned;
  try {
    if (original.isEmpty || original.length > 1024 * 1024) throw _unsupported;
    if (passphrase != null && !isKeyPassphraseBounded(passphrase))
      throw _unsupported;
    envelope = OpenSshEnvelope.read(original);
    final publicBlob = envelope.hint.encoded;
    final type = envelope.hint.inspection.keyType;
    final encrypted = envelope.encrypted;
    final blockSize = envelope.blockSize;
    if (!encrypted) {
      plaintext = Uint8List.fromList(envelope.privateBlob);
    } else {
      final cipher = envelope.cipher!;
      if (passphrase == null)
        throw const OperationFailure(
          FailureCode.passphraseRequired,
          field: OperationField.passphrase,
        );
      if (passphrase.isEmpty)
        throw const OperationFailure(
          FailureCode.passphraseInvalid,
          field: OperationField.passphrase,
        );
      passwordBytes = utf8.encode(passphrase);
      derived = Uint8List(cipher.keySize + cipher.ivSize);
      if (bcrypt_pbkdf(
            passwordBytes,
            passwordBytes.length,
            envelope.salt,
            envelope.salt.length,
            derived,
            derived.length,
            envelope.rounds,
          ) !=
          0)
        throw _unsupported;
      plaintext = cipher
          .createCipher(
            Uint8List.sublistView(derived, 0, cipher.keySize),
            Uint8List.sublistView(derived, cipher.keySize),
            forEncryption: false,
          )
          .processAll(envelope.privateBlob);
    }
    if (plaintext.length % blockSize != 0) throw _unsupported;
    final body = SSHMessageReader(plaintext);
    if (body.readUint32() != body.readUint32()) {
      if (encrypted)
        throw const OperationFailure(
          FailureCode.passphraseInvalid,
          field: OperationField.passphrase,
        );
      throw _unsupported;
    }
    if (body.readUtf8() != type) throw _unsupported;
    late final int bits;
    if (type == 'ssh-rsa') {
      final rsa = OpenSSHRsaKeyPair.readFrom(body);
      if (rsa.n.bitLength < 2048 ||
          !rsa.n.isOdd ||
          rsa.e < BigInt.from(3) ||
          !rsa.e.isOdd ||
          rsa.p <= BigInt.one ||
          rsa.q <= BigInt.one ||
          rsa.p * rsa.q != rsa.n ||
          rsa.d <= BigInt.one ||
          (rsa.q * rsa.iqmp) % rsa.p != BigInt.one)
        throw _unsupported;
      owned = rsa;
      bits = rsa.n.bitLength;
    } else {
      final ed = OpenSSHEd25519KeyPair.readFrom(body);
      if (ed.publicKey.length != 32 || ed.privateKey.length != 64)
        throw _unsupported;
      owned = OpenSSHEd25519KeyPair(
        Uint8List.fromList(ed.publicKey),
        Uint8List.fromList(ed.privateKey),
        ed.comment,
      );
      bits = 256;
    }
    final padding = body.readToEnd();
    if (padding.length >= blockSize) throw _unsupported;
    for (var i = 0; i < padding.length; i++) {
      if (padding[i] != i + 1) throw _unsupported;
    }
    if (!_equal(owned.toPublicKey().encode(), publicBlob)) throw _unsupported;
    final proof = Uint8List.fromList(
      utf8.encode('ServerDeck private key validation v1'),
    );
    final signature = owned.sign(proof);
    final publicKey = owned.toPublicKey();
    final verifies = switch (publicKey) {
      SSHEd25519PublicKey() => publicKey.verify(
        proof,
        signature as SSHEd25519Signature,
      ),
      SSHRsaPublicKey() => publicKey.verify(
        proof,
        signature as SSHRsaSignature,
      ),
      _ => false,
    };
    if (!verifies) throw _unsupported;
    final result = ParsedPrivateKey._(
      owned,
      KeyInspection(keyType: type, bits: bits, encrypted: encrypted),
    );
    owned = null;
    return result;
  } on OperationFailure {
    rethrow;
  } catch (_) {
    throw _unsupported;
  } finally {
    for (final bytes in [plaintext, passwordBytes, derived]) {
      bytes?.fillRange(0, bytes.length, 0);
    }
    _clearKey(owned);
    envelope?.dispose();
  }
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}
