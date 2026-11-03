import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/api.dart';

import 'models.dart';

/// Root-owned ephemeral store key. No projection or plaintext payload is retained.
/// This is not an actor credential: current authorization precedes receipt lookup.
final class ReceiptSigner {
  ReceiptSigner(Uint8List key) : _key = Uint8List.fromList(key) {
    if (key.length != 32) {
      dispose();
      throw const OperationFailure(FailureCode.storageUnavailable);
    }
  }
  final Uint8List _key;
  bool _disposed = false;

  Uint8List sign(String method, Map<String, Object?> payload) {
    if (_disposed) {
      throw const OperationFailure(FailureCode.storageUnavailable);
    }
    final bytes = Uint8List.fromList(
      utf8.encode(_canonical({'method': method, 'payload': payload}, 0)),
    );
    try {
      final hmac = HMac(SHA256Digest(), 64)..init(KeyParameter(_key));
      return hmac.process(bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  void dispose() {
    _key.fillRange(0, _key.length, 0);
    _disposed = true;
  }

  @override
  String toString() => 'ReceiptSigner(redacted)';
}

/// Length is public and fixed; compare every digest byte for equal-size inputs.
bool sameReceiptHmac(List<int> left, List<int> right) {
  if (left.length != 32 || right.length != 32) return false;
  var different = 0;
  for (var i = 0; i < 32; i++) {
    different |= left[i] ^ right[i];
  }
  return different == 0;
}

String _canonical(Object? value, int depth) {
  const invalid = OperationFailure(
    FailureCode.invalidArgument,
    field: OperationField.request,
  );
  if (depth > 16) throw invalid;
  if (value == null || value is bool || value is int) return jsonEncode(value);
  if (value is String) {
    if (!isWellFormedUnicode(value)) throw invalid;
    return jsonEncode(value);
  }
  if (value is List<Object?>) {
    return '[${value.map((v) => _canonical(v, depth + 1)).join(',')}]';
  }
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return '{${keys.map((k) => '${_canonical(k, depth + 1)}:${_canonical(value[k], depth + 1)}').join(',')}}';
  }
  throw invalid;
}
