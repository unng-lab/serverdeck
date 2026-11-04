import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/src/hostkey/hostkey_rsa.dart';
import 'package:pointycastle/export.dart';

import '../domain/models.dart';

const _unsupported = OperationFailure(
  FailureCode.unsupportedKey,
  field: OperationField.authentication,
);
const _invalidPhrase = OperationFailure(
  FailureCode.passphraseInvalid,
  field: OperationField.passphrase,
);

/// Owned legacy PEM storage. Private arithmetic is called only in a parser worker.
final class LegacyPem {
  LegacyPem._(this.blob, this.iv, this.keySize, this.tripleDes);
  final Uint8List blob, iv;
  final int keySize;
  final bool tripleDes;
  bool get encrypted => keySize != 0;

  static bool recognizes(Uint8List bytes) {
    try {
      return utf8
          .decode(bytes)
          .trimLeft()
          .startsWith('-----BEGIN RSA PRIVATE KEY-----');
    } catch (_) {
      return false;
    }
  }

  factory LegacyPem.read(Uint8List original) {
    Uint8List? decoded;
    try {
      if (original.isEmpty || original.length > 1024 * 1024) throw _unsupported;
      final text = utf8.decode(original).trim();
      final lines = text.split(RegExp(r'\r?\n'));
      if (lines.length < 3 ||
          lines.first != '-----BEGIN RSA PRIVATE KEY-----' ||
          lines.last != '-----END RSA PRIVATE KEY-----' ||
          '-----BEGIN '.allMatches(text).length != 1 ||
          '-----END '.allMatches(text).length != 1)
        throw _unsupported;
      final headers = <String, String>{};
      final body = StringBuffer();
      var bodyStarted = false;
      for (final raw in lines.sublist(1, lines.length - 1)) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        if (line.contains(':')) {
          if (bodyStarted) throw _unsupported;
          final colon = line.indexOf(':');
          final name = line.substring(0, colon),
              value = line.substring(colon + 1).trim();
          if (headers.containsKey(name)) throw _unsupported;
          headers[name] = value;
        } else {
          if (!RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(line)) throw _unsupported;
          bodyStarted = true;
          body.write(line);
        }
      }
      decoded = base64.decode(body.toString());
      if (decoded.isEmpty) throw _unsupported;
      var iv = Uint8List(0), size = 0;
      var tripleDes = false;
      if (headers.isNotEmpty) {
        if (headers.length != 2 ||
            headers['Proc-Type'] != '4,ENCRYPTED' ||
            !headers.containsKey('DEK-Info'))
          throw _unsupported;
        final match = RegExp(
          r'^(AES-(128|192|256)-CBC|DES-EDE3-CBC),([0-9A-Fa-f]+)$',
        ).firstMatch(headers['DEK-Info']!);
        if (match == null) throw _unsupported;
        tripleDes = match[1] == 'DES-EDE3-CBC';
        size = tripleDes ? 24 : int.parse(match[2]!) ~/ 8;
        final hex = match[3]!, block = tripleDes ? 8 : 16;
        if (hex.length != block * 2 || decoded.length % block != 0)
          throw _unsupported;
        iv = Uint8List.fromList([
          for (var i = 0; i < hex.length; i += 2)
            int.parse(hex.substring(i, i + 2), radix: 16),
        ]);
      }
      final result = LegacyPem._(decoded, iv, size, tripleDes);
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

  Uint8List publicBytes() {
    if (encrypted) throw _unsupported;
    final reader = _Der.sequence(blob);
    if (_number(reader.integer()) != BigInt.zero) throw _unsupported;
    final n = _number(reader.integer()), e = _number(reader.integer());
    for (var i = 0; i < 6; i++) reader.integer(positive: true);
    if (!reader.done ||
        n.bitLength < 2048 ||
        !n.isOdd ||
        e < BigInt.from(3) ||
        !e.isOdd ||
        e >= n)
      throw _unsupported;
    return SSHRsaPublicKey(e, n).encode();
  }

  OpenSSHRsaKeyPair decode(String? passphrase) {
    Uint8List? plain, password, derived;
    try {
      if (encrypted) {
        if (passphrase == null)
          throw const OperationFailure(
            FailureCode.passphraseRequired,
            field: OperationField.passphrase,
          );
        if (passphrase.isEmpty) throw _invalidPhrase;
        password = Uint8List.fromList(utf8.encode(passphrase));
        derived = _derive(password);
        final cipher = CBCBlockCipher(tripleDes ? DESedeEngine() : AESEngine());
        cipher.init(false, ParametersWithIV(KeyParameter(derived), iv));
        plain = Uint8List(blob.length);
        for (var offset = 0; offset < blob.length; offset += cipher.blockSize) {
          cipher.processBlock(blob, offset, plain, offset);
        }
        final padding = plain.last;
        if (padding < 1 || padding > cipher.blockSize || padding > plain.length)
          throw _invalidPhrase;
        for (var i = plain.length - padding; i < plain.length; i++) {
          if (plain[i] != padding) throw _invalidPhrase;
        }
        return _private(
          Uint8List.sublistView(plain, 0, plain.length - padding),
        );
      }
      return _private(blob);
    } on OperationFailure catch (e) {
      if (encrypted && e.code == FailureCode.unsupportedKey)
        throw _invalidPhrase;
      rethrow;
    } catch (_) {
      if (encrypted) throw _invalidPhrase;
      throw _unsupported;
    } finally {
      for (final bytes in [plain, password, derived]) {
        bytes?.fillRange(0, bytes.length, 0);
      }
    }
  }

  Uint8List _derive(Uint8List password) {
    final result = Uint8List(keySize);
    var previous = Uint8List(0), offset = 0;
    try {
      while (offset < result.length) {
        final seed = Uint8List.fromList([
          ...previous,
          ...password,
          ...iv.take(8),
        ]);
        late Uint8List digest;
        try {
          digest = MD5Digest().process(seed);
        } finally {
          seed.fillRange(0, seed.length, 0);
        }
        previous.fillRange(0, previous.length, 0);
        previous = digest;
        for (var i = 0; i < digest.length && offset < result.length; i++) {
          result[offset++] = digest[i];
        }
      }
      return result;
    } catch (_) {
      result.fillRange(0, result.length, 0);
      rethrow;
    } finally {
      previous.fillRange(0, previous.length, 0);
    }
  }

  void dispose() {
    blob.fillRange(0, blob.length, 0);
    iv.fillRange(0, iv.length, 0);
  }
}

OpenSSHRsaKeyPair _private(Uint8List bytes) {
  final reader = _Der.sequence(bytes);
  final values = <BigInt>[_number(reader.integer())];
  for (var i = 0; i < 8; i++)
    values.add(_number(reader.integer(positive: true)));
  if (!reader.done || values[0] != BigInt.zero) throw _unsupported;
  final n = values[1],
      e = values[2],
      d = values[3],
      p = values[4],
      q = values[5],
      dp = values[6],
      dq = values[7],
      coefficient = values[8];
  if (n.bitLength < 2048 ||
      !n.isOdd ||
      e < BigInt.from(3) ||
      !e.isOdd ||
      e >= n ||
      d <= BigInt.one ||
      p <= BigInt.one ||
      q <= BigInt.one ||
      p == q ||
      p * q != n)
    throw _unsupported;
  final pm = p - BigInt.one, qm = q - BigInt.one, lcm = pm ~/ pm.gcd(qm) * qm;
  if ((e * d) % lcm != BigInt.one ||
      dp != d % pm ||
      dq != d % qm ||
      q * coefficient % p != BigInt.one)
    throw _unsupported;
  return OpenSSHRsaKeyPair(n, e, d, coefficient, p, q, '');
}

BigInt _number(Uint8List bytes) => BigInt.parse(
  bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
  radix: 16,
);

/// Fixed-depth DER grammar: exactly one SEQUENCE of nine primitive INTEGERs.
final class _Der {
  _Der(this.bytes);
  final Uint8List bytes;
  int offset = 0;
  bool get done => offset == bytes.length;
  factory _Der.sequence(Uint8List bytes) {
    final outer = _Der(bytes);
    final body = outer._value(0x30);
    if (!outer.done) throw _unsupported;
    return _Der(body);
  }
  Uint8List _value(int tag) {
    if (offset + 2 > bytes.length || bytes[offset++] != tag) throw _unsupported;
    var length = bytes[offset++];
    if (length >= 128) {
      final count = length & 127;
      if (count < 1 ||
          count > 4 ||
          offset + count > bytes.length ||
          bytes[offset] == 0)
        throw _unsupported;
      length = 0;
      for (var i = 0; i < count; i++) length = (length << 8) | bytes[offset++];
      if (length < 128) throw _unsupported;
    }
    if (length < 1 || length > bytes.length - offset) throw _unsupported;
    final value = Uint8List.sublistView(bytes, offset, offset + length);
    offset += length;
    return value;
  }

  Uint8List integer({bool positive = false}) {
    final value = _value(2);
    if ((value.first & 128) != 0 ||
        (value.length > 1 && value.first == 0 && (value[1] & 128) == 0) ||
        (positive && value.every((b) => b == 0)))
      throw _unsupported;
    return value;
  }
}
