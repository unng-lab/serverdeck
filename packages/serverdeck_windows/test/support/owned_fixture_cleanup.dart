import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

const _retryableDeleteErrors = {5, 32, 33, 145};
const _maximumDeadline = Duration(seconds: 5);
const _retryDelay = Duration(milliseconds: 25);

/// Deletes only an owned MCP bundle fixture after its native users have joined.
/// A short Windows file lock may outlive the joined processes; other failures
/// remain immediate failures, and an expired lock still fails the teardown.
Future<void> deleteOwnedFixtureDirectory(
  Directory directory, {
  Duration deadline = _maximumDeadline,
}) async {
  if (deadline <= Duration.zero || deadline > _maximumDeadline) {
    throw ArgumentError.value(deadline, 'deadline', 'must be > 0 and <= 5s');
  }
  final elapsed = Stopwatch()..start();
  while (true) {
    final checkedDirectory = _checkedOwnedFixtureDirectory(directory);
    try {
      checkedDirectory.deleteSync(recursive: true);
      if (FileSystemEntity.typeSync(
            checkedDirectory.path,
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound) {
        throw StateError('FIXTURE_NOT_REMOVED');
      }
      return;
    } on FileSystemException catch (error) {
      final remaining = deadline - elapsed.elapsed;
      if (!_retryableDeleteErrors.contains(error.osError?.errorCode) ||
          remaining <= Duration.zero) {
        rethrow;
      }
      await Future<void>.delayed(
        remaining < _retryDelay ? remaining : _retryDelay,
      );
      if (elapsed.elapsed >= deadline) rethrow;
    }
  }
}

Directory _checkedOwnedFixtureDirectory(Directory directory) {
  final absolute = p.normalize(p.absolute(directory.path));
  final configuredTemp = p.normalize(p.absolute(Directory.systemTemp.path));
  final actualTemp = p.normalize(
    Directory.systemTemp.resolveSymbolicLinksSync(),
  );
  if (!p.isAbsolute(directory.path) ||
      (!p.equals(p.dirname(absolute), configuredTemp) &&
          !p.equals(p.dirname(absolute), actualTemp)) ||
      !p.basename(absolute).startsWith('serverdeck-mcp-bundle-') ||
      FileSystemEntity.typeSync(absolute, followLinks: false) !=
          FileSystemEntityType.directory) {
    throw StateError('UNSAFE_FIXTURE');
  }
  if (Platform.isWindows) {
    final native = absolute.toNativeUtf16();
    try {
      final attributes = GetFileAttributes(PCWSTR(native));
      if (attributes.value == 0xffffffff) {
        throw FileSystemException(
          'Could not inspect owned fixture',
          absolute,
          OSError('WIN32_ATTRIBUTES', attributes.error.toInt()),
        );
      }
      if ((attributes.value & 0x400) != 0) {
        throw StateError('UNSAFE_FIXTURE');
      }
    } finally {
      calloc.free(native);
    }
  }
  final resolved = p.normalize(directory.resolveSymbolicLinksSync());
  if (!p.equals(resolved, p.join(actualTemp, p.basename(absolute)))) {
    throw StateError('UNSAFE_FIXTURE');
  }
  return Directory(resolved);
}
