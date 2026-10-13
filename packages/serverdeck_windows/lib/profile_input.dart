import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:serverdeck_protocol/profile_validation.dart';
import 'package:win32/win32.dart';

final _idn = DynamicLibrary.open('normaliz.dll')
    .lookupFunction<
      Int32 Function(Uint32, Pointer<Utf16>, Int32, Pointer<Utf16>, Int32),
      int Function(int, Pointer<Utf16>, int, Pointer<Utf16>, int)
    >('IdnToAscii');
final _dialogError = DynamicLibrary.open('comdlg32.dll')
    .lookupFunction<Uint32 Function(), int Function()>('CommDlgExtendedError');

/// OS IDNA/STD3 conversion, bounded independently from the profile validator.
String domainToAscii(String value) {
  final text = normalizeText(value, trim: true);
  if (text.isEmpty || text.runes.length > 253) {
    throw const FormatException('VALIDATION');
  }
  return using((arena) {
    final input = text.toNativeUtf16(allocator: arena);
    final output = arena<Uint16>(254).cast<Utf16>();
    final count = _idn(2, input, text.length, output, 253);
    if (count < 1 || count > 253) throw const FormatException('VALIDATION');
    return output.toDartString(length: count).toLowerCase();
  });
}

/// Only the caller's explicit selected file is read. Path is never returned.
Future<String> readSelectedPrivateKey(String path) async {
  final handle = await File(path).open();
  try {
    final bytes = await handle.read(65537);
    try {
      if (bytes.length > 65536) throw const FormatException('VALIDATION');
      return utf8.decode(bytes, allowMalformed: false);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  } finally {
    await handle.close();
  }
}

/// Blocking Windows dialog runs off the Flutter isolate. It opens only when
/// explicitly requested; no implicit SSH directory or persisted recent path.
Future<String?> pickPrivateKey() => Isolate.run(() async {
  final path = using((arena) {
    final dialog = arena<OPENFILENAME>();
    final file = arena<Uint16>(32768).cast<Utf16>();
    dialog.ref
      ..lStructSize = sizeOf<OPENFILENAME>()
      ..lpstrFile = PWSTR(file)
      ..nMaxFile = 32768
      ..lpstrTitle = PWSTR(
        'Выберите приватный ключ'.toNativeUtf16(allocator: arena),
      )
      ..Flags =
          OFN_EXPLORER |
          OFN_FILEMUSTEXIST |
          OFN_PATHMUSTEXIST |
          OFN_NOCHANGEDIR |
          OFN_DONTADDTORECENT;
    if (!GetOpenFileName(dialog)) {
      if (_dialogError() != 0) throw const FormatException('INTERNAL');
      return null;
    }
    return file.toDartString();
  });
  return path == null ? null : readSelectedPrivateKey(path);
});
