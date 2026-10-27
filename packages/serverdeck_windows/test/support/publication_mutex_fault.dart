import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:cryptography/dart.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:win32/win32.dart';

final _create = DynamicLibrary.open('kernel32.dll')
    .lookupFunction<
      Pointer Function(Pointer<SECURITY_ATTRIBUTES>, Int32, Pointer<Utf16>),
      Pointer Function(Pointer<SECURITY_ATTRIBUTES>, int, Pointer<Utf16>)
    >('CreateMutexW');
final _set = DynamicLibrary.open('advapi32.dll')
    .lookupFunction<
      Int32 Function(Pointer, Uint32, Pointer),
      int Function(Pointer, int, Pointer)
    >('SetKernelObjectSecurity');

/// Owned fixture namespace only. Deny a new native worker's mutex open, while
/// retaining the handle needed to restore its original owner-only descriptor.
final class PublicationMutexFault {
  PublicationMutexFault(String root, String generation)
    : sid = currentUserSid() {
    root = p.normalize(p.absolute(root));
    if (!p.isWithin(p.normalize(p.absolute(Directory.systemTemp.path)), root) ||
        !p.basename(root).startsWith('serverdeck-mcp-bundle-'))
      throw StateError('UNSAFE_FIXTURE');
    requireUuid(generation);
    final digest = const DartSha256()
        .hashSync(
          utf8.encode(
            'serverdeck-next-publication-v1\n$sid\n${root.toLowerCase()}\n$generation',
          ),
        )
        .bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final name = 'Global\\ServerDeckNext.v1.$digest'.toNativeUtf16();
    final security = SecurityAttributes(ownerOnlySddl(sid));
    try {
      handle = HANDLE(_create(security.pointer, 0, name));
      if (!handle.isValid) throw StateError('FAULT_SETUP_FAILED');
    } finally {
      security.close();
      calloc.free(name);
    }
  }
  final String sid;
  late final HANDLE handle;
  void descriptor(String sddl) {
    final security = SecurityAttributes(sddl);
    try {
      if (_set(handle, 4, security.pointer.ref.lpSecurityDescriptor) == 0)
        throw StateError('FAULT_SETUP_FAILED');
    } finally {
      security.close();
    }
  }

  void deny() => descriptor('O:${sid}D:P(A;;RC;;;$sid)(A;;FA;;;SY)');
  void restore() => descriptor(ownerOnlySddl(sid));
  void close() {
    restore();
    CloseHandle(handle);
  }
}
