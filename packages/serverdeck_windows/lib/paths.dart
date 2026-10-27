import 'dart:io';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import 'security.dart';
import 'native_attributes.dart';

String validateLocalPath(String localAppData, String target) {
  final root = p.normalize(p.absolute(localAppData));
  final resolved = p.normalize(p.absolute(target));
  if (!Platform.isWindows ||
      root.startsWith(r'\\') ||
      resolved.startsWith(r'\\') ||
      !RegExp(r'^[A-Za-z]:\\').hasMatch(root) ||
      (!p.equals(root, resolved) && !p.isWithin(root, resolved))) {
    throw const FileSystemException('UNSAFE_PATH');
  }
  return resolved;
}

void requireSafePath(String localAppData, String target) {
  final resolved = validateLocalPath(localAppData, target);
  final volume = p.rootPrefix(resolved).toNativeUtf16();
  try {
    final driveType = GetDriveType(PCWSTR(volume));
    if (driveType != 3) {
      throw FileSystemException(
        'UNSAFE_PATH',
        '',
        OSError('WIN32_DRIVE_TYPE', driveType),
      );
    }
  } finally {
    calloc.free(volume);
  }
  var component = p.rootPrefix(resolved);
  for (final segment in p.split(resolved).skip(1)) {
    component = p.join(component, segment);
    final attributes = queryLocalAttributes(component);
    if (attributes != null && (attributes & 0x400) != 0) {
      throw const FileSystemException(
        'UNSAFE_PATH',
        '',
        OSError('WIN32_REPARSE_POINT', 0x400),
      );
    }
  }
}

void createProtectedDirectory(String localAppData, String target, String sid) {
  requireSafePath(localAppData, target);
  if (Directory(target).existsSync()) {
    requireOwnerOnlyFileAcl(target, sid);
    return;
  }
  final attributes = SecurityAttributes(ownerOnlySddl(sid));
  final input = target.toNativeUtf16();
  try {
    if (!CreateDirectory(PCWSTR(input), attributes.pointer).value) {
      throw const FileSystemException('PROTECTION_UNAVAILABLE');
    }
    requireSafePath(localAppData, target);
    requireOwnerOnlyFileAcl(target, sid);
  } finally {
    attributes.close();
    calloc.free(input);
  }
}

Future<void> writeNewProtectedFile(
  String localAppData,
  String target,
  String sid,
  List<int> bytes,
) =>
    Isolate.run(() => _writeNewProtectedFile(localAppData, target, sid, bytes));

/// Precreate Isar data/lock files with explicit ACL before native initialization.
Future<void> createProtectedEmptyFile(
  String localAppData,
  String target,
  String sid,
) => Isolate.run(
  () => _writeNewProtectedFile(localAppData, target, sid, [], allowEmpty: true),
);

void _writeNewProtectedFile(
  String localAppData,
  String target,
  String sid,
  List<int> bytes, {
  bool allowEmpty = false,
}) {
  if ((!allowEmpty && bytes.isEmpty) || bytes.length > 32 * 1024 * 1024) {
    throw const FileSystemException('RESOURCE_LIMIT');
  }
  requireSafePath(localAppData, target);
  requireOwnerOnlyFileAcl(p.dirname(target), sid);
  final attributes = SecurityAttributes(ownerOnlySddl(sid));
  final input = target.toNativeUtf16();
  final buffer = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
  final written = calloc<Uint32>();
  HANDLE? handle;
  try {
    final created = CreateFile(
      PCWSTR(input),
      0x40000000,
      FILE_SHARE_MODE(0),
      attributes.pointer,
      CREATE_NEW,
      FILE_FLAGS_AND_ATTRIBUTES(0x00200000 | 0x80000000),
      null,
    );
    if (!created.value.isValid) {
      throw const FileSystemException('PROTECTION_UNAVAILABLE');
    }
    handle = created.value;
    requireOwnerOnlyFileAcl(target, sid);
    buffer.asTypedList(bytes.length).setAll(0, bytes);
    if ((bytes.isNotEmpty &&
            (!WriteFile(handle, buffer, bytes.length, written, null).value ||
                written.value != bytes.length)) ||
        !FlushFileBuffers(handle).value) {
      throw const FileSystemException('STORAGE_BLOCKED');
    }
  } finally {
    if (handle != null) {
      CloseHandle(handle);
    }
    buffer.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
    calloc.free(buffer);
    calloc.free(written);
    calloc.free(input);
    attributes.close();
  }
}

Future<List<int>> readProtectedFile(
  String localAppData,
  String target,
  String sid, {
  int maxBytes = 32 * 1024 * 1024,
}) => Isolate.run(() {
  final reader = ProtectedSnapshotReader.open(
    localAppData,
    target,
    sid,
    maxBytes: maxBytes,
  );
  try {
    return reader.read();
  } finally {
    reader.close();
  }
});

/// Copy a retained protected regular file in64KiB chunks into a new protected
/// file. Never overwrites, follows reparses, or grants a broader destination ACL.
/// Caller owns the sole-writer lease and verifies source/target content digests.
/// A failure may leave a partial destination for explicit staged recovery.
Future<void> copyProtectedFile(
  String localAppData,
  String source,
  String destination,
  String sid, {
  int maxBytes = 64 * 1024 * 1024,
}) => Isolate.run(() {
  if (maxBytes < 1 || maxBytes > 64 * 1024 * 1024)
    throw const FileSystemException('RESOURCE_LIMIT');
  final sourcePath = validateLocalPath(localAppData, source);
  final targetPath = validateLocalPath(localAppData, destination);
  if (p.equals(sourcePath, targetPath))
    throw const FileSystemException('UNSAFE_PATH');
  requireSafePath(localAppData, targetPath);
  requireOwnerOnlyFileAcl(p.dirname(targetPath), sid);
  final reader = ProtectedSnapshotReader.open(
    localAppData,
    sourcePath,
    sid,
    maxBytes: maxBytes,
  );
  try {
    using((arena) {
      final size = arena<Int64>(), after = arena<Int64>();
      final count = arena<Uint32>(), written = arena<Uint32>();
      final buffer = arena<Uint8>(65536);
      if (!GetFileSizeEx(reader._handle, size).value || size.value < 0)
        throw const FileSystemException('STORAGE_BLOCKED');
      if (size.value > maxBytes)
        throw const FileSystemException('RESOURCE_LIMIT');
      final expected = size.value;
      final attributes = SecurityAttributes(ownerOnlySddl(sid));
      HANDLE? target;
      try {
        final opened = CreateFile(
          PCWSTR(targetPath.toNativeUtf16(allocator: arena)),
          0x40000000,
          FILE_SHARE_MODE(0),
          attributes.pointer,
          CREATE_NEW,
          FILE_FLAGS_AND_ATTRIBUTES(0x00200000 | 0x80000000),
          null,
        );
        if (!opened.value.isValid)
          throw const FileSystemException('STORAGE_BLOCKED');
        target = opened.value;
        requireOwnerOnlyFileHandleAcl(target, sid);
        var total = 0;
        while (true) {
          if (!ReadFile(reader._handle, buffer, 65536, count, null).value ||
              count.value > 65536)
            throw const FileSystemException('STORAGE_BLOCKED');
          if (count.value == 0) break;
          total += count.value;
          if (total > maxBytes)
            throw const FileSystemException('RESOURCE_LIMIT');
          if (!WriteFile(target, buffer, count.value, written, null).value ||
              written.value != count.value)
            throw const FileSystemException('STORAGE_BLOCKED');
        }
        if (total != expected ||
            !GetFileSizeEx(reader._handle, after).value ||
            after.value != expected ||
            !FlushFileBuffers(target).value)
          throw const FileSystemException('STORAGE_BLOCKED');
      } finally {
        buffer.asTypedList(65536).fillRange(0, 65536, 0);
        attributes.close();
        if (target != null && !CloseHandle(target).value)
          throw const FileSystemException('STORAGE_BLOCKED');
      }
    });
    requireSafePath(localAppData, targetPath);
    requireOwnerOnlyFileAcl(targetPath, sid);
  } finally {
    reader.close();
  }
});

/// Available bytes for the current caller, not the volume's unrestricted quota.
Future<void> requireProtectedDiskSpace(
  String localAppData,
  String directory,
  String sid, {
  required int minimumBytes,
}) => Isolate.run(() {
  if (minimumBytes < 0) throw const FileSystemException('RESOURCE_LIMIT');
  final resolved = validateLocalPath(localAppData, directory);
  requireSafePath(localAppData, resolved);
  requireOwnerOnlyFileAcl(resolved, sid);
  using((arena) {
    final available = arena<Uint64>();
    if (!GetDiskFreeSpaceEx(
      PCWSTR(resolved.toNativeUtf16(allocator: arena)),
      available,
      null,
      null,
    ).value)
      throw const FileSystemException('STORAGE_BLOCKED');
    if (available.value < minimumBytes)
      throw const FileSystemException('RESOURCE_LIMIT');
  });
});

/// A single bounded read of the retained file object. Delete sharing lets an
/// atomic publisher replace the name without invalidating this reader's bytes.
class ProtectedSnapshotReader {
  ProtectedSnapshotReader._(this._handle, this._maxBytes);
  final HANDLE _handle;
  final int _maxBytes;
  bool _closed = false, _consumed = false;

  factory ProtectedSnapshotReader.open(
    String localAppData,
    String target,
    String sid, {
    int maxBytes = 32 * 1024 * 1024,
  }) {
    if (maxBytes < 1 || maxBytes > 64 * 1024 * 1024) {
      throw const FileSystemException('RESOURCE_LIMIT');
    }
    requireSafePath(localAppData, target);
    requireOwnerOnlyFileAcl(p.dirname(target), sid);
    requireOwnerOnlyFileAcl(target, sid);
    return using((arena) {
      final opened = CreateFile(
        PCWSTR(target.toNativeUtf16(allocator: arena)),
        0x80000000, // GENERIC_READ, including READ_CONTROL.
        FILE_SHARE_MODE(7), // READ | WRITE | DELETE, no access grant.
        null,
        OPEN_EXISTING,
        FILE_FLAGS_AND_ATTRIBUTES(0x00200000), // OPEN_REPARSE_POINT.
        null,
      );
      if (!opened.value.isValid) {
        throw const FileSystemException('STORAGE_BLOCKED');
      }
      final handle = opened.value;
      try {
        final information = arena<BY_HANDLE_FILE_INFORMATION>();
        if (!GetFileInformationByHandle(handle, information).value ||
            (information.ref.dwFileAttributes & 0x410) != 0 ||
            GetFileType(handle).value != 1) {
          throw const FileSystemException('STORAGE_BLOCKED');
        }
        requireOwnerOnlyFileHandleAcl(handle, sid);
        return ProtectedSnapshotReader._(handle, maxBytes);
      } catch (_) {
        if (!CloseHandle(handle).value) {
          throw const FileSystemException('STORAGE_BLOCKED');
        }
        rethrow;
      }
    });
  }

  Uint8List read() {
    if (_closed || _consumed) {
      throw const FileSystemException('STORAGE_BLOCKED');
    }
    _consumed = true;
    return using((arena) {
      final size = arena<Int64>(), count = arena<Uint32>();
      final buffer = arena<Uint8>(65536);
      try {
        if (!GetFileSizeEx(_handle, size).value || size.value < 0) {
          throw const FileSystemException('STORAGE_BLOCKED');
        }
        if (size.value > _maxBytes) {
          throw const FileSystemException('RESOURCE_LIMIT');
        }
        final bytes =
            BytesBuilder(); // Copies before the native buffer is wiped.
        var total = 0;
        while (true) {
          final requested = (_maxBytes - total + 1).clamp(1, 65536);
          if (!ReadFile(_handle, buffer, requested, count, null).value ||
              count.value > requested) {
            throw const FileSystemException('STORAGE_BLOCKED');
          }
          if (count.value == 0) return bytes.takeBytes();
          total += count.value;
          if (total > _maxBytes) {
            throw const FileSystemException('RESOURCE_LIMIT');
          }
          bytes.add(buffer.asTypedList(count.value));
        }
      } finally {
        buffer.asTypedList(65536).fillRange(0, 65536, 0);
      }
    });
  }

  void close() {
    if (_closed) return;
    if (!CloseHandle(_handle).value) {
      throw const FileSystemException('STORAGE_BLOCKED');
    }
    _closed = true;
  }
}

Future<void> promoteProtectedPath(
  String localAppData,
  String source,
  String destination,
  String sid, {
  bool replace = false,
}) => Isolate.run(() {
  requireSafePath(localAppData, source);
  requireSafePath(localAppData, destination);
  requireOwnerOnlyFileAcl(source, sid);
  requireOwnerOnlyFileAcl(p.dirname(source), sid);
  requireOwnerOnlyFileAcl(p.dirname(destination), sid);
  if (FileSystemEntity.typeSync(destination) != FileSystemEntityType.notFound) {
    if (!replace) {
      throw const FileSystemException('STORAGE_BLOCKED');
    }
    requireOwnerOnlyFileAcl(destination, sid);
  }
  if (replace) {
    _replaceRetainedFile(source, destination, sid);
    requireOwnerOnlyFileAcl(destination, sid);
    return;
  }
  final oldPath = source.toNativeUtf16(), newPath = destination.toNativeUtf16();
  try {
    if (!MoveFileEx(
      PCWSTR(oldPath),
      PCWSTR(newPath),
      MOVE_FILE_FLAGS(replace ? 9 : 8),
    ).value) {
      throw const FileSystemException('STORAGE_BLOCKED');
    }
    requireOwnerOnlyFileAcl(destination, sid);
  } finally {
    calloc.free(oldPath);
    calloc.free(newPath);
  }
});

// FileRenameInfoEx gives an atomic name replacement while delete-sharing
// readers retain the old object. No delete-first gap, elevated access, retry
// loop, readonly override, or fallback to a different permission policy.
void _replaceRetainedFile(String source, String destination, String sid) {
  using((arena) {
    final opened = CreateFile(
      PCWSTR(source.toNativeUtf16(allocator: arena)),
      0x00030000, // DELETE | READ_CONTROL, existing owner/SYSTEM rights.
      FILE_SHARE_MODE(7),
      null,
      OPEN_EXISTING,
      FILE_FLAGS_AND_ATTRIBUTES(0x00200000),
      null,
    );
    if (!opened.value.isValid) {
      throw const FileSystemException('STORAGE_BLOCKED');
    }
    final handle = opened.value;
    try {
      final information = arena<BY_HANDLE_FILE_INFORMATION>();
      if (!GetFileInformationByHandle(handle, information).value ||
          (information.ref.dwFileAttributes & 0x410) != 0 ||
          GetFileType(handle).value != 1) {
        throw const FileSystemException('STORAGE_BLOCKED');
      }
      requireOwnerOnlyFileHandleAcl(handle, sid);
      final name = p.normalize(p.absolute(destination)).codeUnits;
      if (name.isEmpty || name.length > 32766 || name.contains(0)) {
        throw const FileSystemException('UNSAFE_PATH');
      }
      // FILE_RENAME_INFO: DWORD flags; aligned HANDLE root; DWORD byte length;
      // WCHAR trailing name. RootDirectory is NULL; filename is absolute.
      final nameOffset = sizeOf<IntPtr>() == 8 ? 20 : 12;
      final length = nameOffset + name.length * 2 + 2;
      final buffer = arena<Uint8>(length);
      final data = ByteData.sublistView(buffer.asTypedList(length));
      data.setUint32(
        0,
        3,
        Endian.little,
      ); // REPLACE_IF_EXISTS | POSIX_SEMANTICS.
      data.setUint32(nameOffset - 4, name.length * 2, Endian.little);
      for (var i = 0; i < name.length; i++) {
        data.setUint16(nameOffset + i * 2, name[i], Endian.little);
      }
      if (!SetFileInformationByHandle(
        handle,
        FileRenameInfoEx,
        buffer,
        length,
      ).value) {
        throw const FileSystemException('STORAGE_BLOCKED');
      }
    } finally {
      if (!CloseHandle(handle).value) {
        throw const FileSystemException('STORAGE_BLOCKED');
      }
    }
  });
}

Future<void> replaceProtectedFile(
  String localAppData,
  String target,
  String sid,
  List<int> bytes,
) async {
  final random = Random.secure();
  final suffix = List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final temporary = '$target.$suffix.pending';
  await writeNewProtectedFile(localAppData, temporary, sid, bytes);
  await promoteProtectedPath(
    localAppData,
    temporary,
    target,
    sid,
    replace: true,
  );
}
