import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/domain/mutation_receipts.dart';

Uint8List key(int value) => Uint8List.fromList(List.filled(32, value));
void main() {
  test('matches independent HMAC-SHA256 canonical-message vector', () {
    // Independent expected result is computed from Python stdlib hmac for this
    // fixed canonical byte string, not from the production canonicalizer.
    final signer = ReceiptSigner(key(0x0b));
    final actual = signer.sign('createProfile', {'password': 'Hi There'});
    expect(
      base64.encode(actual),
      'QBkRo9ukobtvcmmyPJ15L4R/9YgTYuGL7UKQ8K2d+VY=',
    );
    signer.dispose();
  });
  test(
    'sorts object keys recursively but retains array order and exact strings',
    () {
      final signer = ReceiptSigner(key(7));
      final first = signer.sign('createProfile', {
        'z': {'b': 2, 'a': 1},
        'password': ' secret ',
        'items': [true, null, 2],
      });
      final reordered = signer.sign('createProfile', {
        'items': [true, null, 2],
        'password': ' secret ',
        'z': {'a': 1, 'b': 2},
      });
      expect(sameReceiptHmac(first, reordered), isTrue);
      expect(
        sameReceiptHmac(
          first,
          signer.sign('createProfile', {
            'z': {'a': 1, 'b': 2},
            'password': 'secret',
            'items': [true, null, 2],
          }),
        ),
        isFalse,
      );
      expect(
        sameReceiptHmac(
          first,
          signer.sign('createProfile', {
            'z': {'a': 1, 'b': 2},
            'password': ' secret ',
            'items': [null, true, 2],
          }),
        ),
        isFalse,
      );
      signer.dispose();
    },
  );
  test('method, key, absent fields and Unicode spelling stay distinct', () {
    final a = ReceiptSigner(key(1)), b = ReceiptSigner(key(2));
    final digest = a.sign('createProfile', {'password': '\u00e9'});
    expect(
      sameReceiptHmac(digest, b.sign('createProfile', {'password': '\u00e9'})),
      isFalse,
    );
    expect(
      sameReceiptHmac(digest, a.sign('updateProfile', {'password': '\u00e9'})),
      isFalse,
    );
    expect(
      sameReceiptHmac(digest, a.sign('createProfile', {'password': 'e\u0301'})),
      isFalse,
    );
    expect(
      sameReceiptHmac(
        digest,
        a.sign('createProfile', {'password': '\u00e9', 'port': 22}),
      ),
      isFalse,
    );
    a.dispose();
    b.dispose();
  });
  test(
    'rejects floats, malformed Unicode, non-JSON types and excessive depth',
    () {
      final signer = ReceiptSigner(key(3));
      Object nested = 1;
      for (var i = 0; i < 20; i++) {
        nested = [nested];
      }
      for (final value in [
        1.0,
        String.fromCharCode(0xd800),
        Object(),
        nested,
      ]) {
        expect(
          () => signer.sign('createProfile', {'value': value}),
          throwsA(isA<OperationFailure>()),
        );
      }
      signer.dispose();
    },
  );
  test(
    'key is owned and disposal fails closed; comparison enforces digest bounds',
    () {
      final original = key(4);
      final signer = ReceiptSigner(original);
      final digest = signer.sign('createProfile', {});
      original.fillRange(0, original.length, 0);
      expect(signer.sign('createProfile', {}), digest);
      expect(signer.toString(), 'ReceiptSigner(redacted)');
      expect(sameReceiptHmac(digest, Uint8List(31)), isFalse);
      expect(sameReceiptHmac(Uint8List(33), Uint8List(33)), isFalse);
      signer.dispose();
      signer.dispose();
      expect(
        () => signer.sign('createProfile', {}),
        throwsA(isA<OperationFailure>()),
      );
      expect(
        () => ReceiptSigner(Uint8List(31)),
        throwsA(isA<OperationFailure>()),
      );
    },
  );
}
