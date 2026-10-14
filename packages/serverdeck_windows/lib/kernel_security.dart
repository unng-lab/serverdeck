import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'security.dart';

final _advapi = DynamicLibrary.open('advapi32.dll');
final _getKernelSecurity = _advapi
    .lookupFunction<
      Int32 Function(Pointer, Uint32, Pointer, Uint32, Pointer<Uint32>),
      int Function(Pointer, int, Pointer, int, Pointer<Uint32>)
    >('GetKernelObjectSecurity');

void requireKernelOwnerAcl(HANDLE handle, String sid, String rights) {
  final length = calloc<Uint32>();
  Pointer<Uint8> descriptor = nullptr;
  try {
    _getKernelSecurity(handle, 5, nullptr, 0, length);
    if (length.value == 0 || length.value > 65536) {
      throw StateError('UNSAFE_ENDPOINT');
    }
    descriptor = calloc<Uint8>(length.value);
    if (_getKernelSecurity(handle, 5, descriptor, length.value, length) == 0 ||
        !matchesOwnerOnlyAclDescriptor(descriptor, sid, rights)) {
      throw StateError('UNSAFE_ENDPOINT');
    }
  } finally {
    if (descriptor != nullptr) {
      calloc.free(descriptor);
    }
    calloc.free(length);
  }
}
