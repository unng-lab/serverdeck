import 'security.dart';

import 'dart:ffi';
import 'dart:isolate';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

// dpapi.h CRYPTPROTECT_UI_FORBIDDEN; never include LOCAL_MACHINE.
const _uiForbidden = 0x1;

class DpapiProtection implements UserProtection {
  @override
  Future<List<int>> protect(List<int> cleartext, List<int> entropy) =>
      Isolate.run(() => _transform(cleartext, entropy, true));
  @override
  Future<List<int>> unprotect(List<int> ciphertext, List<int> entropy) =>
      Isolate.run(() => _transform(ciphertext, entropy, false));

  static List<int> _transform(
    List<int> input,
    List<int> entropy,
    bool encrypt,
  ) {
    if (!Platform.isWindows ||
        input.isEmpty ||
        input.length > 32 * 1024 * 1024 ||
        entropy.isEmpty ||
        entropy.length > 4096) {
      throw StateError('PROTECTION_UNAVAILABLE');
    }
    final source = calloc<CRYPT_INTEGER_BLOB>();
    final optionalEntropy = calloc<CRYPT_INTEGER_BLOB>();
    final output = calloc<CRYPT_INTEGER_BLOB>();
    final inputBuffer = calloc<Uint8>(input.length);
    final entropyBuffer = calloc<Uint8>(entropy.length);
    try {
      inputBuffer.asTypedList(input.length).setAll(0, input);
      entropyBuffer.asTypedList(entropy.length).setAll(0, entropy);
      source.ref
        ..cbData = input.length
        ..pbData = inputBuffer;
      optionalEntropy.ref
        ..cbData = entropy.length
        ..pbData = entropyBuffer;
      final result = encrypt
          ? CryptProtectData(
              source,
              null,
              optionalEntropy,
              null,
              _uiForbidden,
              output,
            )
          : CryptUnprotectData(
              source,
              null,
              optionalEntropy,
              null,
              _uiForbidden,
              output,
            );
      if (!result.value ||
          output.ref.cbData == 0 ||
          output.ref.cbData > 32 * 1024 * 1024 ||
          output.ref.pbData == nullptr) {
        throw StateError('PROTECTION_UNAVAILABLE');
      }
      return List<int>.of(output.ref.pbData.asTypedList(output.ref.cbData));
    } finally {
      inputBuffer.asTypedList(input.length).fillRange(0, input.length, 0);
      entropyBuffer.asTypedList(entropy.length).fillRange(0, entropy.length, 0);
      if (output.ref.pbData != nullptr) {
        output.ref.pbData
            .asTypedList(output.ref.cbData)
            .fillRange(0, output.ref.cbData, 0);
        LocalFree(HLOCAL(output.ref.pbData));
      }
      calloc.free(inputBuffer);
      calloc.free(entropyBuffer);
      calloc.free(source);
      calloc.free(optionalEntropy);
      calloc.free(output);
    }
  }
}
