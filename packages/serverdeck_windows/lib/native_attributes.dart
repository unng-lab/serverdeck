import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

// Windows NT ABI. NTSTATUS is returned by the same native call that queries
// attributes: no thread-local GetLastError can be lost across FFI transitions.
final _query = DynamicLibrary.open('ntdll.dll')
    .lookupFunction<
      Int32 Function(Pointer<_ObjectAttributes>, Pointer<_BasicInformation>),
      int Function(Pointer<_ObjectAttributes>, Pointer<_BasicInformation>)
    >('NtQueryAttributesFile');

final class _ObjectAttributes extends Struct {
  @Uint32()
  external int length;
  external Pointer<Void> root;
  external Pointer<UNICODE_STRING> name;
  @Uint32()
  external int flags;
  external Pointer<Void> descriptor;
  external Pointer<Void> quality;
}

final class _BasicInformation extends Struct {
  @Int64()
  external int creation;
  @Int64()
  external int access;
  @Int64()
  external int write;
  @Int64()
  external int change;
  @Uint32()
  external int attributes;
}

/// Returns null only for a missing name/path. All other native failures block.
int? queryLocalAttributes(String absolute) {
  final name = r'\??\' + absolute;
  final length = name.length * 2;
  if (length > 65532 || name.contains('\u0000')) {
    throw const FileSystemException('UNSAFE_PATH');
  }
  final buffer = name.toNativeUtf16();
  final unicode = calloc<UNICODE_STRING>();
  final object = calloc<_ObjectAttributes>();
  final information = calloc<_BasicInformation>();
  try {
    unicode.ref
      ..Length = length
      ..MaximumLength = length + 2
      ..Buffer = PWSTR(buffer);
    object.ref
      ..length = sizeOf<_ObjectAttributes>()
      ..name = unicode
      ..flags = 0x40 | 0x1000; // CASE_INSENSITIVE | DONT_REPARSE
    final status = _query(object, information) & 0xffffffff;
    if (status == 0xc0000034 || status == 0xc000003a) return null;
    if (status != 0) {
      throw FileSystemException(
        'UNSAFE_PATH',
        '',
        OSError('NT_ATTRIBUTES_STATUS', status),
      );
    }
    return information.ref.attributes;
  } finally {
    calloc.free(information);
    calloc.free(object);
    calloc.free(unicode);
    calloc.free(buffer);
  }
}
