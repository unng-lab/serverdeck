import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/src/hostkey/hostkey_ed25519.dart';
import 'package:dartssh2/src/hostkey/hostkey_rsa.dart';
import 'package:dartssh2/src/ssh_message.dart';

import '../domain/models.dart';

final class KeyInspection {
  const KeyInspection({
    required this.keyType,
    required this.bits,
    required this.encrypted,
  });
  final String keyType;
  final int bits;
  final bool encrypted;
}

/// Count UTF-8 bytes without allocating an extra plaintext password buffer.
bool isKeyPassphraseBounded(String value) {
  if (value.length > 65536) return false;
  var bytes = 0;
  for (final scalar in value.runes) {
    if (scalar >= 0xd800 && scalar <= 0xdfff) return false;
    bytes += scalar <= 0x7f
        ? 1
        : scalar <= 0x7ff
        ? 2
        : scalar <= 0xffff
        ? 3
        : 4;
    if (bytes > 65536) return false;
  }
  return true;
}

const _unsupported = OperationFailure(
  FailureCode.unsupportedKey,
  field: OperationField.authentication,
);

bool sameKeyBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}

/// Only public data survives the envelope's disposal. No private-key math here.
final class PublicKeyHint {
  PublicKeyHint._(Uint8List bytes, this.inspection)
    : encoded = Uint8List.fromList(bytes).asUnmodifiableView();
  final Uint8List encoded;
  final KeyInspection inspection;
  SSHHostKey toPublicKey() => _decodePublic(Uint8List.fromList(encoded));
}

SSHHostKey _decodePublic(Uint8List bytes) =>
    switch (SSHHostKey.getType(bytes)) {
      'ssh-ed25519' => SSHEd25519PublicKey.decode(bytes),
      'ssh-rsa' => SSHRsaPublicKey.decode(bytes),
      _ => throw _unsupported,
    };

PublicKeyHint readPublicKeyHint(Uint8List original) {
  final envelope = OpenSshEnvelope.read(original);
  try {
    return envelope.hint;
  } finally {
    envelope.dispose();
  }
}

/// Owns decoded private-file storage; callers must dispose on every path.
final class OpenSshEnvelope {
  OpenSshEnvelope._(
    this._decoded,
    this.privateBlob,
    this.cipher,
    this.salt,
    this.rounds,
    this.hint,
  );
  final Uint8List _decoded, privateBlob, salt;
  final SSHCipherType? cipher;
  final int rounds;
  final PublicKeyHint hint;
  bool get encrypted => cipher != null;
  int get blockSize => cipher?.blockSize ?? 8;
  void dispose() => _decoded.fillRange(0, _decoded.length, 0);

  factory OpenSshEnvelope.read(Uint8List original) {
    Uint8List? decoded;
    try {
      if (original.isEmpty || original.length > 1024 * 1024) throw _unsupported;
      final text = utf8.decode(original).trim();
      const header = '-----BEGIN OPENSSH PRIVATE KEY-----';
      const footer = '-----END OPENSSH PRIVATE KEY-----';
      if (!text.startsWith(header) ||
          !text.endsWith(footer) ||
          header.allMatches(text).length != 1 ||
          footer.allMatches(text).length != 1)
        throw _unsupported;
      final pem = SSHPem.decode(text);
      decoded = pem.content;
      if (pem.type != 'OPENSSH PRIVATE KEY' || pem.headers.isNotEmpty)
        throw _unsupported;
      final reader = SSHMessageReader(decoded);
      final magic = utf8.encode('openssh-key-v1\x00');
      if (!sameKeyBytes(reader.readBytes(magic.length), magic))
        throw _unsupported;
      final cipherName = reader.readUtf8(), kdfName = reader.readUtf8();
      final options = reader.readString();
      // Validate before any list allocation driven by the file's key count.
      if (reader.readUint32() != 1) throw _unsupported;
      final publicBlob = reader.readString(), privateBlob = reader.readString();
      if (!reader.isDone || privateBlob.isEmpty) throw _unsupported;
      final publicKey = _decodePublic(publicBlob);
      final int bits;
      if (publicKey is SSHEd25519PublicKey) {
        if (publicKey.key.length != 32) throw _unsupported;
        bits = 256;
      } else if (publicKey is SSHRsaPublicKey) {
        if (publicKey.n.bitLength < 2048 ||
            !publicKey.n.isOdd ||
            publicKey.e < BigInt.from(3) ||
            !publicKey.e.isOdd ||
            publicKey.n <= publicKey.e)
          throw _unsupported;
        bits = publicKey.n.bitLength;
      } else {
        throw _unsupported;
      }
      if (!sameKeyBytes(publicKey.encode(), publicBlob)) throw _unsupported;
      SSHCipherType? cipher;
      var salt = Uint8List(0), rounds = 0;
      if (cipherName == 'none') {
        if (kdfName != 'none' || options.isNotEmpty) throw _unsupported;
      } else {
        const supported = {
          'aes128-ctr',
          'aes192-ctr',
          'aes256-ctr',
          'aes128-cbc',
          'aes192-cbc',
          'aes256-cbc',
        };
        if (!supported.contains(cipherName) || kdfName != 'bcrypt')
          throw _unsupported;
        for (final candidate in SSHCipherType.values) {
          if (candidate.name == cipherName) cipher = candidate;
        }
        if (cipher == null) throw _unsupported;
        final kdf = SSHMessageReader(options);
        salt = kdf.readString();
        rounds = kdf.readUint32();
        if (!kdf.isDone || salt.isEmpty || rounds == 0) throw _unsupported;
      }
      if (privateBlob.length % (cipher?.blockSize ?? 8) != 0)
        throw _unsupported;
      final hint = PublicKeyHint._(
        publicBlob,
        KeyInspection(
          keyType: SSHHostKey.getType(publicBlob),
          bits: bits,
          encrypted: cipher != null,
        ),
      );
      final result = OpenSshEnvelope._(
        decoded,
        privateBlob,
        cipher,
        salt,
        rounds,
        hint,
      );
      decoded = null;
      return result;
    } on OperationFailure {
      rethrow;
    } catch (_) {
      throw _unsupported;
    } finally {
      decoded?.fillRange(0, decoded.length, 0);
    }
  }
}
