import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

abstract interface class UserProtection {
  Future<List<int>> protect(List<int> cleartext, List<int> entropy);
  Future<List<int>> unprotect(List<int> ciphertext, List<int> entropy);
}

final _advapi = DynamicLibrary.open('advapi32.dll');
final _kernel = DynamicLibrary.open('kernel32.dll');
final _processId = _kernel
    .lookupFunction<Uint32 Function(Pointer), int Function(Pointer)>(
      'GetProcessId',
    );
final _sidToText = _advapi
    .lookupFunction<
      Int32 Function(Pointer, Pointer<Pointer<Utf16>>),
      int Function(Pointer, Pointer<Pointer<Utf16>>)
    >('ConvertSidToStringSidW');
final _textToDescriptor = _advapi
    .lookupFunction<
      Int32 Function(Pointer<Utf16>, Uint32, Pointer<Pointer>, Pointer<Uint32>),
      int Function(Pointer<Utf16>, int, Pointer<Pointer>, Pointer<Uint32>)
    >('ConvertStringSecurityDescriptorToSecurityDescriptorW');
final _descriptorToText = _advapi
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
final _getFileSecurity = _advapi
    .lookupFunction<
      Int32 Function(Pointer<Utf16>, Uint32, Pointer, Uint32, Pointer<Uint32>),
      int Function(Pointer<Utf16>, int, Pointer, int, Pointer<Uint32>)
    >('GetFileSecurityW');

String processUserSid(HANDLE process) {
  final token = calloc<Pointer>();
  final length = calloc<Uint32>();
  Pointer<Uint8> buffer = nullptr;
  try {
    if (!OpenProcessToken(process, TOKEN_QUERY, token).value) {
      throw StateError('IDENTITY_UNAVAILABLE');
    }
    GetTokenInformation(HANDLE(token.value), TokenUser, null, 0, length);
    if (length.value == 0 || length.value > 65536) {
      throw StateError('IDENTITY_UNAVAILABLE');
    }
    buffer = calloc<Uint8>(length.value);
    if (!GetTokenInformation(
      HANDLE(token.value),
      TokenUser,
      buffer,
      length.value,
      length,
    ).value) {
      throw StateError('IDENTITY_UNAVAILABLE');
    }
    final sid = buffer.cast<Pointer>().value;
    final text = calloc<Pointer<Utf16>>();
    try {
      if (_sidToText(sid, text) == 0) {
        throw StateError('IDENTITY_UNAVAILABLE');
      }
      return text.value.toDartString();
    } finally {
      if (text.value != nullptr) {
        LocalFree(HLOCAL(text.value));
      }
      calloc.free(text);
    }
  } finally {
    if (token.value != nullptr) {
      CloseHandle(HANDLE(token.value));
    }
    if (buffer != nullptr) {
      calloc.free(buffer);
    }
    calloc.free(length);
    calloc.free(token);
  }
}

String currentUserSid() => processUserSid(GetCurrentProcess());

/// Must stay on the pipe worker that owns its native handle.
class RetainedProcessIdentity {
  RetainedProcessIdentity._(
    this.handle,
    this.pid,
    this.sid,
    this.imagePath,
    this.creationTime,
  );
  factory RetainedProcessIdentity.open(int pid) {
    if (pid <= 0) {
      throw StateError('IDENTITY_UNAVAILABLE');
    }
    final opened = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
    if (!opened.value.isValid) {
      throw StateError('IDENTITY_UNAVAILABLE');
    }
    try {
      final handle = opened.value;
      final identity = RetainedProcessIdentity._(
        handle,
        pid,
        processUserSid(handle),
        _image(handle),
        _creation(handle),
      );
      identity.revalidate();
      return identity;
    } catch (_) {
      CloseHandle(opened.value);
      rethrow;
    }
  }
  final HANDLE handle;
  final int pid;
  final String sid, imagePath, creationTime;
  bool _closed = false;
  void revalidate() {
    if (_closed) {
      throw StateError('IDENTITY_UNAVAILABLE');
    }
    final exitCode = calloc<Uint32>();
    try {
      if (!GetExitCodeProcess(handle, exitCode).value ||
          exitCode.value != 259 ||
          _processId(handle) != pid ||
          processUserSid(handle) != sid ||
          _image(handle) != imagePath ||
          _creation(handle) != creationTime) {
        throw StateError('IDENTITY_UNAVAILABLE');
      }
    } finally {
      calloc.free(exitCode);
    }
  }

  void close() {
    if (!_closed) {
      _closed = true;
      CloseHandle(handle);
    }
  }

  static String _image(HANDLE handle) {
    final buffer = calloc<Uint16>(32768);
    final size = calloc<Uint32>()..value = 32768;
    try {
      if (!QueryFullProcessImageName(
            handle,
            PROCESS_NAME_FORMAT(0),
            PWSTR(buffer.cast()),
            size,
          ).value ||
          size.value == 0 ||
          size.value >= 32768) {
        throw StateError('IDENTITY_UNAVAILABLE');
      }
      return buffer.cast<Utf16>().toDartString(length: size.value);
    } finally {
      calloc.free(buffer);
      calloc.free(size);
    }
  }

  static String _creation(HANDLE handle) {
    final times = calloc<FILETIME>(4);
    try {
      if (!GetProcessTimes(
        handle,
        times,
        times + 1,
        times + 2,
        times + 3,
      ).value) {
        throw StateError('IDENTITY_UNAVAILABLE');
      }
      return ((BigInt.from(times.ref.dwHighDateTime) << 32) |
              BigInt.from(times.ref.dwLowDateTime))
          .toString();
    } finally {
      calloc.free(times);
    }
  }
}

/// Caller owns this descriptor and attributes for the entire native call.
class SecurityAttributes {
  SecurityAttributes(String sddl) {
    final input = sddl.toNativeUtf16();
    final output = calloc<Pointer>();
    try {
      if (_textToDescriptor(input, 1, output, nullptr) == 0) {
        throw StateError('PROTECTION_UNAVAILABLE');
      }
      _descriptor = output.value;
      pointer = calloc<SECURITY_ATTRIBUTES>();
      pointer.ref
        ..nLength = sizeOf<SECURITY_ATTRIBUTES>()
        ..lpSecurityDescriptor = _descriptor
        ..bInheritHandle = false;
    } finally {
      calloc.free(input);
      calloc.free(output);
    }
  }
  late final Pointer _descriptor;
  late final Pointer<SECURITY_ATTRIBUTES> pointer;
  bool _closed = false;
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    calloc.free(pointer);
    LocalFree(HLOCAL(_descriptor));
  }
}

String ownerOnlySddl(String sid) {
  if (!RegExp(r'^S-1-[0-9]+(?:-[0-9]+)+$').hasMatch(sid)) {
    throw StateError('IDENTITY_UNAVAILABLE');
  }
  return 'O:${sid}D:P(A;;FA;;;$sid)(A;;FA;;;SY)';
}

/// Compare exact owner/protected DACL after Windows normalizes SID aliases.
/// This reads descriptors only; it never changes a token, owner, or ACL.
bool matchesOwnerOnlyAclDescriptor(
  Pointer descriptor,
  String sid,
  String rights,
) {
  final actual = calloc<Pointer<Utf16>>();
  try {
    ownerOnlySddl(sid);
    if (!const {'FA', '0x1f0001', '0x1f0003', '0x120083'}.contains(rights) ||
        _descriptorToText(descriptor, 1, 5, actual, nullptr) == 0) {
      return false;
    }
    final value = actual.value.toDartString();
    for (final acl in [
      '(A;;$rights;;;$sid)(A;;$rights;;;SY)',
      '(A;;$rights;;;SY)(A;;$rights;;;$sid)',
    ]) {
      final expected = SecurityAttributes('O:${sid}D:P$acl');
      final text = calloc<Pointer<Utf16>>();
      try {
        if (_descriptorToText(
              expected.pointer.ref.lpSecurityDescriptor,
              1,
              5,
              text,
              nullptr,
            ) ==
            0) {
          return false;
        }
        if (value == text.value.toDartString()) {
          return true;
        }
      } finally {
        if (text.value != nullptr) {
          LocalFree(HLOCAL(text.value));
        }
        calloc.free(text);
        expected.close();
      }
    }
    return false;
  } catch (_) {
    return false;
  } finally {
    if (actual.value != nullptr) {
      LocalFree(HLOCAL(actual.value));
    }
    calloc.free(actual);
  }
}

void requireOwnerOnlyFileAcl(String path, String sid) {
  final input = path.toNativeUtf16();
  try {
    _requireOwnerOnlyAcl(
      (descriptor, size, length) =>
          _getFileSecurity(input, 5, descriptor, size, length),
      sid,
    );
  } finally {
    calloc.free(input);
  }
}

final _getObjectSecurity = _advapi
    .lookupFunction<
      Int32 Function(Pointer, Uint32, Pointer<Uint8>, Uint32, Pointer<Uint32>),
      int Function(Pointer, int, Pointer<Uint8>, int, Pointer<Uint32>)
    >('GetKernelObjectSecurity');

/// Validate the retained object, even if its pathname has since been replaced.
/// OWNER+DACL requires READ_CONTROL, never SACL or SeSecurityPrivilege.
void requireOwnerOnlyFileHandleAcl(HANDLE handle, String sid) =>
    _requireOwnerOnlyAcl(
      (descriptor, size, length) =>
          _getObjectSecurity(handle, 5, descriptor, size, length),
      sid,
    );

void _requireOwnerOnlyAcl(
  int Function(Pointer<Uint8>, int, Pointer<Uint32>) read,
  String sid,
) {
  final length = calloc<Uint32>();
  Pointer<Uint8> descriptor = nullptr;
  try {
    read(nullptr, 0, length);
    if (length.value == 0 || length.value > 65536) {
      throw StateError('PROTECTION_UNAVAILABLE');
    }
    descriptor = calloc<Uint8>(length.value);
    if (read(descriptor, length.value, length) == 0 ||
        !matchesOwnerOnlyAclDescriptor(descriptor, sid, 'FA')) {
      throw StateError('PROTECTION_UNAVAILABLE');
    }
  } finally {
    if (descriptor != nullptr) {
      calloc.free(descriptor);
    }
    calloc.free(length);
  }
}
