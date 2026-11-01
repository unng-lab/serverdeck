import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';
import 'package:serverdeck_engine/hosting/protected_mcp_discovery.dart';
import 'package:serverdeck_engine/platform/ports.dart';
import 'package:serverdeck_protocol/discovery.dart';

import 'engine_platform.dart';
import 'paths.dart';
import 'security.dart';

/// Fixed owner-derived metadata path; constructor allocates no native resource.
/// The Host's existing writer lease is borrowed, never acquired here.
final class WindowsMcpDiscoveryFile implements McpDiscoveryFile {
  WindowsMcpDiscoveryFile({required this.files, required this.requireOwner});
  final WindowsProtectedFiles files;
  final void Function() requireOwner;
  String get _directory =>
      p.join(files.root, 'ServerDeckNext', 'v1', 'runtime');
  String get _path => p.join(_directory, DiscoveryNamespace.fileName);
  final _pending = <Future<void>>{};
  bool _closing = false, _physicalCloseFailed = false;
  Future<void>? _closed;

  void _prepare() {
    requireOwner();
    if (_closing) throw StateError('STORAGE_BLOCKED');
    files.requireOwnerOnly(p.dirname(_directory));
    if (files.kind(_directory) == ProtectedPathKind.absent) {
      files.createDirectory(_directory);
    }
    files.requireOwnerOnly(_directory);
    if (files.kind(_directory) != ProtectedPathKind.directory) {
      throw StateError('STORAGE_BLOCKED');
    }
  }

  Future<T> _run<T>(Future<T> Function() operation) {
    if (_closing) return Future.error(StateError('STORAGE_BLOCKED'));
    final settled = Completer<void>();
    _pending.add(settled.future);
    return Future<T>.sync(() async {
      Object? result;
      try {
        _prepare();
        final value = await operation();
        result = value;
        requireOwner();
        return value;
      } catch (e) {
        if (result is List<int>) result.fillRange(0, result.length, 0);
        if ((e is FileSystemException &&
                e.message == 'PHYSICAL_CLOSE_UNCONFIRMED') ||
            e is RemoteError) {
          _physicalCloseFailed = true;
        }
        throw StateError('STORAGE_BLOCKED');
      } finally {
        _pending.remove(settled.future);
        settled.complete();
      }
    });
  }

  @override
  Future<List<int>?> read() => _run(() async {
    if (files.kind(_path) == ProtectedPathKind.absent) return null;
    // Use the concrete primitive so an unconfirmed native CloseHandle remains
    // distinguishable from an ordinary storage error until file.close drains.
    return readProtectedFile(
      files.root,
      _path,
      files.ownerIdentity,
      maxBytes: 16384,
    );
  });

  @override
  Future<void> replace(List<int> wrapped) => _run(() async {
    if (wrapped.isEmpty || wrapped.length > 16384)
      throw StateError('STORAGE_BLOCKED');
    final suffix = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final temporary = '$_path.$suffix.pending';
    await _replace(files.root, temporary, _path, files.ownerIdentity, wrapped);
  });

  @override
  Future<void> removeExact(List<int> wrapped) =>
      _run(() => _removeExact(files.root, _path, files.ownerIdentity, wrapped));

  @override
  Future<void> close() {
    if (_closed != null) return _closed!;
    final done = Completer<void>();
    _closed = done.future;
    done.future.ignore();
    _closing = true;
    () async {
      await Future.wait(_pending.toList());
      if (_physicalCloseFailed) throw StateError('STORAGE_BLOCKED');
    }().then<void>(
      done.complete,
      onError: (Object _, StackTrace __) =>
          done.completeError(StateError('STORAGE_BLOCKED')),
    );
    return done.future;
  }
}

Future<void> _replace(
  String root,
  String temporary,
  String destination,
  String sid,
  List<int> bytes,
) => Isolate.run(() {
  requireSafePath(root, temporary);
  requireSafePath(root, destination);
  requireOwnerOnlyFileAcl(p.dirname(destination), sid);
  if (FileSystemEntity.typeSync(destination, followLinks: false) !=
      FileSystemEntityType.notFound) {
    requireOwnerOnlyFileAcl(destination, sid);
  }
  using((arena) {
    final attributes = SecurityAttributes(ownerOnlySddl(sid));
    HANDLE? handle;
    var promoted = false;
    final buffer = arena<Uint8>(bytes.length);
    try {
      final opened = CreateFile(
        PCWSTR(temporary.toNativeUtf16(allocator: arena)),
        0xc0010000,
        FILE_SHARE_MODE(1),
        attributes.pointer,
        CREATE_NEW,
        FILE_FLAGS_AND_ATTRIBUTES(0x00200000 | 0x80000000),
        null,
      );
      if (!opened.value.isValid)
        throw const FileSystemException('STORAGE_BLOCKED');
      handle = opened.value;
      requireOwnerOnlyFileHandleAcl(handle, sid);
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      final written = arena<Uint32>();
      if (!WriteFile(handle, buffer, bytes.length, written, null).value ||
          written.value != bytes.length ||
          !FlushFileBuffers(handle).value)
        throw const FileSystemException('STORAGE_BLOCKED');
      final name = destination.codeUnits;
      if (name.isEmpty || name.length > 32766 || name.contains(0))
        throw const FileSystemException('STORAGE_BLOCKED');
      final nameOffset = sizeOf<IntPtr>() == 8 ? 20 : 12;
      final length = nameOffset + name.length * 2 + 2;
      final rename = arena<Uint8>(length);
      final data = ByteData.sublistView(rename.asTypedList(length));
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
        rename,
        length,
      ).value)
        throw const FileSystemException('STORAGE_BLOCKED');
      promoted = true;
    } finally {
      buffer.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
      attributes.close();
      if (handle != null) {
        try {
          if (!promoted) {
            // CREATE_NEW proves this retained object is ours even on partial
            // writes. Cleanup never reopens a potentially replaced path.
            final flags = arena<Uint32>()..value = 3;
            if (!SetFileInformationByHandle(
              handle,
              FileDispositionInfoEx,
              flags,
              sizeOf<Uint32>(),
            ).value) {
              throw const FileSystemException('STORAGE_BLOCKED');
            }
          }
        } finally {
          if (!CloseHandle(handle).value)
            throw const FileSystemException('PHYSICAL_CLOSE_UNCONFIRMED');
        }
      }
    }
  });
});

/// DELETE+READ on one regular protected object, no write/delete sharing. This
/// excludes replacement between comparison and disposition; there is no
/// delete-by-path, delete-first gap, readonly override, privilege or retry.
Future<void> _removeExact(
  String root,
  String path,
  String sid,
  List<int> expected,
) => Isolate.run(() {
  if (expected.isEmpty || expected.length > 16384)
    throw const FileSystemException('STORAGE_BLOCKED');
  requireSafePath(root, path);
  requireOwnerOnlyFileAcl(p.dirname(path), sid);
  using((arena) {
    final opened = CreateFile(
      PCWSTR(path.toNativeUtf16(allocator: arena)),
      0x80010000, // GENERIC_READ | DELETE (includes READ_CONTROL).
      FILE_SHARE_MODE(1), // READ only, permits protected snapshot readers.
      null,
      OPEN_EXISTING,
      FILE_FLAGS_AND_ATTRIBUTES(0x00200000),
      null,
    );
    if (!opened.value.isValid) {
      if (opened.error.toInt() == 2)
        return; // Missing filename, not denied path.
      throw const FileSystemException('STORAGE_BLOCKED');
    }
    final handle = opened.value;
    final buffer = arena<Uint8>(16385), count = arena<Uint32>();
    try {
      final information = arena<BY_HANDLE_FILE_INFORMATION>();
      if (!GetFileInformationByHandle(handle, information).value ||
          (information.ref.dwFileAttributes & 0x410) != 0 ||
          GetFileType(handle).value != 1)
        throw const FileSystemException('STORAGE_BLOCKED');
      requireOwnerOnlyFileHandleAcl(handle, sid);
      var total = 0, difference = 0;
      while (true) {
        final requested = 16385 - total;
        if (requested == 0) return; // Oversized different file, untouched.
        if (!ReadFile(handle, buffer + total, requested, count, null).value ||
            count.value > requested) {
          throw const FileSystemException('STORAGE_BLOCKED');
        }
        if (count.value == 0) break;
        total += count.value;
      }
      if (total != expected.length) return;
      for (var i = 0; i < total; i++) {
        difference |= buffer[i] ^ expected[i];
      }
      if (difference != 0) return;
      final flags = arena<Uint32>()..value = 3; // DELETE | POSIX_SEMANTICS.
      if (!SetFileInformationByHandle(
        handle,
        FileDispositionInfoEx,
        flags,
        sizeOf<Uint32>(),
      ).value) {
        throw const FileSystemException('STORAGE_BLOCKED');
      }
    } finally {
      buffer.asTypedList(16385).fillRange(0, 16385, 0);
      if (!CloseHandle(handle).value)
        throw const FileSystemException('PHYSICAL_CLOSE_UNCONFIRMED');
    }
  });
});
