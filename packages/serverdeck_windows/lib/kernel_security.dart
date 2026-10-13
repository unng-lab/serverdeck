import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

final _advapi = DynamicLibrary.open('advapi32.dll');
final _getKernelSecurity = _advapi
    .lookupFunction<
      Int32 Function(Pointer, Uint32, Pointer, Uint32, Pointer<Uint32>),
      int Function(Pointer, int, Pointer, int, Pointer<Uint32>)
    >('GetKernelObjectSecurity');
final _toText = _advapi
    .lookupFunction<
      Int32 Function(
        Pointer,
        Uint32,
        Uint32,
        Pointer<Pointer<Utf16>>,
        Pointer<Uint32>,
      ),
      int Function(Pointer, int, int, Pointer<Pointer<Utf16>>, Pointer<Uint32>)
    >('ConvertSecurityDescriptorToStringSecurityDescriptorW');

void requireKernelOwnerAcl(HANDLE handle, String sid, String rights) {
  final length = calloc<Uint32>();
  final text = calloc<Pointer<Utf16>>();
  Pointer<Uint8> descriptor = nullptr;
  try {
    _getKernelSecurity(handle, 5, nullptr, 0, length);
    if (length.value == 0 || length.value > 65536) {
      throw StateError('UNSAFE_ENDPOINT');
    }
    descriptor = calloc<Uint8>(length.value);
    if (_getKernelSecurity(handle, 5, descriptor, length.value, length) == 0 ||
        _toText(descriptor, 1, 5, text, nullptr) == 0) {
      throw StateError('UNSAFE_ENDPOINT');
    }
    final sddl = text.value.toDartString();
    final first = 'O:${sid}D:P(A;;$rights;;;$sid)(A;;$rights;;;SY)';
    final second = 'O:${sid}D:P(A;;$rights;;;SY)(A;;$rights;;;$sid)';
    if (sddl != first && sddl != second) {
      throw StateError('UNSAFE_ENDPOINT');
    }
  } finally {
    if (text.value != nullptr) {
      LocalFree(HLOCAL(text.value));
    }
    if (descriptor != nullptr) {
      calloc.free(descriptor);
    }
    calloc.free(length);
    calloc.free(text);
  }
}
