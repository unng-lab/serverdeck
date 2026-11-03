import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/domain/receipt_key.dart';

import '../fixtures/profile_harness.dart';

void main() {
  late ProfileHarness h;
  setUp(() => h = ProfileHarness());
  tearDown(() => h.dispose());
  test('unprotect uses fixed purpose, owns signer key and clears both temporary buffers', () async {
    late Uint8List retained;
    final key = Uint8List.fromList(List.filled(32, 7));
    final signer = await loadReceiptSigner(h.repository, (
      bytes,
      purpose,
    ) async {
      expect(purpose, 'receipt-hmac.v1');
      expect(bytes, [1]);
      retained = bytes;
      return key;
    });
    expect(retained, [0]);
    expect(key.every((b) => b == 0), isTrue);
    expect(h.repository.state.security.protectedReceiptHmacKey, [1]);
    expect(signer.sign('create', {}), h.signer.sign('create', {}));
    signer.dispose();
    expect(() => signer.sign('create', {}), throwsA(isA<OperationFailure>()));
  });
  test(
    'unprotect failure never replaces canonical key or leaks native error',
    () async {
      late Uint8List retained;
      await expectLater(
        loadReceiptSigner(h.repository, (bytes, _) async {
          retained = bytes;
          throw StateError('SYNTHETIC_SECRET');
        }),
        throwsA(
          isA<OperationFailure>()
              .having((e) => e.code, 'code', FailureCode.storageUnavailable)
              .having(
                (e) => e.toString(),
                'message',
                isNot(contains('SYNTHETIC_SECRET')),
              ),
        ),
      );
      expect(retained, [0]);
      expect(h.repository.state.security.protectedReceiptHmacKey, [1]);
    },
  );
  for (final length in [0, 31, 33]) {
    test(
      'invalid plaintext key length$length clears returned bytes and fails closed',
      () async {
        final key = Uint8List.fromList(List.filled(length, 7));
        await expectLater(
          loadReceiptSigner(h.repository, (_, purpose) async => key),
          throwsA(isA<OperationFailure>()),
        );
        expect(key.every((b) => b == 0), isTrue);
        expect(h.repository.state.security.protectedReceiptHmacKey, [1]);
      },
    );
  }
  test(
    'invalid ciphertext bounds reject before unprotect without regeneration',
    () async {
      var calls = 0;
      for (final bytes in [<int>[], List.filled(2 * 1024 * 1024 + 1, 1)]) {
        h.repository.state.security.protectedReceiptHmacKey = bytes;
        await expectLater(
          loadReceiptSigner(h.repository, (_, purpose) async {
            calls++;
            return Uint8List(32);
          }),
          throwsA(isA<OperationFailure>()),
        );
        expect(
          h.repository.state.security.protectedReceiptHmacKey,
          same(bytes),
        );
      }
      expect(calls, 0);
    },
  );
}
