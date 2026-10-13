import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'security.dart';

final _bcrypt = DynamicLibrary.open('bcrypt.dll');
final _open = _bcrypt
    .lookupFunction<
      Int32 Function(Pointer<Pointer>, Pointer<Utf16>, Pointer, Uint32),
      int Function(Pointer<Pointer>, Pointer<Utf16>, Pointer, int)
    >('BCryptOpenAlgorithmProvider');
final _create = _bcrypt
    .lookupFunction<
      Int32 Function(
        Pointer,
        Pointer<Pointer>,
        Pointer<Uint8>,
        Uint32,
        Pointer<Uint8>,
        Uint32,
        Uint32,
      ),
      int Function(
        Pointer,
        Pointer<Pointer>,
        Pointer<Uint8>,
        int,
        Pointer<Uint8>,
        int,
        int,
      )
    >('BCryptCreateHash');
final _update = _bcrypt
    .lookupFunction<
      Int32 Function(Pointer, Pointer<Uint8>, Uint32, Uint32),
      int Function(Pointer, Pointer<Uint8>, int, int)
    >('BCryptHashData');
final _finish = _bcrypt
    .lookupFunction<
      Int32 Function(Pointer, Pointer<Uint8>, Uint32, Uint32),
      int Function(Pointer, Pointer<Uint8>, int, int)
    >('BCryptFinishHash');
final _destroy = _bcrypt
    .lookupFunction<Int32 Function(Pointer), int Function(Pointer)>(
      'BCryptDestroyHash',
    );
final _close = _bcrypt
    .lookupFunction<
      Int32 Function(Pointer, Uint32),
      int Function(Pointer, int)
    >('BCryptCloseAlgorithmProvider');

/// Synchronous bounded-buffer hash; call only from a bootstrap/pipe worker.
String fileSha256(String path) {
  final algorithm = calloc<Pointer>(), hash = calloc<Pointer>();
  final input = calloc<Uint8>(65536), output = calloc<Uint8>(32);
  final name = 'SHA256'.toNativeUtf16();
  RandomAccessFile? file;
  try {
    if (!p.isAbsolute(path) ||
        _open(algorithm, name, nullptr, 0) < 0 ||
        _create(algorithm.value, hash, nullptr, 0, nullptr, 0, 0) < 0) {
      throw StateError('IDENTITY_UNAVAILABLE');
    }
    file = File(path).openSync();
    while (true) {
      final count = file.readIntoSync(input.asTypedList(65536));
      if (count == 0) break;
      if (_update(hash.value, input, count, 0) < 0) {
        throw StateError('IDENTITY_UNAVAILABLE');
      }
    }
    if (_finish(hash.value, output, 32, 0) < 0) {
      throw StateError('IDENTITY_UNAVAILABLE');
    }
    return output
        .asTypedList(32)
        .map((v) => v.toRadixString(16).padLeft(2, '0'))
        .join();
  } catch (_) {
    throw StateError('IDENTITY_UNAVAILABLE');
  } finally {
    try {
      file?.closeSync();
    } finally {
      if (hash.value != nullptr) _destroy(hash.value);
      if (algorithm.value != nullptr) _close(algorithm.value, 0);
      input.asTypedList(65536).fillRange(0, 65536, 0);
      output.asTypedList(32).fillRange(0, 32, 0);
      calloc.free(algorithm);
      calloc.free(hash);
      calloc.free(input);
      calloc.free(output);
      calloc.free(name);
    }
  }
}

void verifyProcessImage(
  RetainedProcessIdentity identity,
  String ownerSid,
  String expectedPath,
  String expectedSha256,
) {
  identity.revalidate();
  if (identity.sid != ownerSid ||
      !p.isAbsolute(expectedPath) ||
      !p.equals(p.normalize(identity.imagePath), p.normalize(expectedPath)) ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedSha256) ||
      fileSha256(identity.imagePath) != expectedSha256) {
    throw StateError('IDENTITY_UNAVAILABLE');
  }
  identity.revalidate();
}
