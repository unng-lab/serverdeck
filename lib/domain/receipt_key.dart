import 'dart:typed_data';

import '../storage/domain_repository.dart';
import 'models.dart';
import 'mutation_receipts.dart';

/// Called once after store open, before domain/pipe admission. Never regenerates
/// an unreadable key: that would destroy existing idempotency history.
Future<ReceiptSigner> loadReceiptSigner(
  DomainRepository repository,
  Future<Uint8List> Function(Uint8List bytes, String purpose) unprotect,
) async {
  Uint8List? ciphertext, plaintext;
  try {
    final protected = repository.read<Uint8List>((r) {
      final bytes = r.security.protectedReceiptHmacKey;
      if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024)
        throw const OperationFailure(FailureCode.storageUnavailable);
      return Uint8List.fromList(bytes);
    });
    ciphertext = protected;
    plaintext = await unprotect(protected, 'receipt-hmac.v1');
    if (plaintext.length != 32)
      throw const OperationFailure(FailureCode.storageUnavailable);
    return ReceiptSigner(plaintext);
  } catch (_) {
    throw const OperationFailure(
      FailureCode.storageUnavailable,
      retryable: true,
    );
  } finally {
    ciphertext?.fillRange(0, ciphertext.length, 0);
    plaintext?.fillRange(0, plaintext.length, 0);
  }
}
