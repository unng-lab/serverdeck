import 'dart:async';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:win32/win32.dart';

import 'support/owned_fixture_cleanup.dart';

Directory _fixture() =>
    Directory.systemTemp.createTempSync('serverdeck-mcp-bundle-cleanup-');

Future<void> _cleanRemaining(Directory directory) async {
  if (FileSystemEntity.typeSync(directory.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    await deleteOwnedFixtureDirectory(directory);
  }
}

void _createDirectoryJunction(Link junction, Directory target) {
  final setup = Process.runSync(
    'powershell.exe',
    [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      'New-Item -ItemType Junction -Path \$env:SERVERDECK_TEST_JUNCTION -Target \$env:SERVERDECK_TEST_TARGET -ErrorAction Stop | Out-Null',
    ],
    environment: {
      'SERVERDECK_TEST_JUNCTION': junction.path,
      'SERVERDECK_TEST_TARGET': target.path,
    },
  );
  expect(
    setup.exitCode,
    0,
    reason: 'Owned fixture junction setup must succeed',
  );
  expect(
    FileSystemEntity.typeSync(junction.path, followLinks: false),
    FileSystemEntityType.link,
  );
}

final class _DeletionLock {
  _DeletionLock(File file) {
    final native = file.path.toNativeUtf16();
    try {
      final opened = CreateFile(
        PCWSTR(native),
        0x80000000, // GENERIC_READ.
        FILE_SHARE_MODE(3), // FILE_SHARE_READ | FILE_SHARE_WRITE, no DELETE.
        null,
        OPEN_EXISTING,
        FILE_FLAGS_AND_ATTRIBUTES(0),
        null,
      );
      if (!opened.value.isValid) {
        throw FileSystemException(
          'Could not lock owned fixture',
          file.path,
          OSError('WIN32_CREATE_FILE', opened.error.toInt()),
        );
      }
      _handle = opened.value;
    } finally {
      calloc.free(native);
    }
  }

  late final HANDLE _handle;
  bool isClosed = false;

  void close() {
    if (isClosed) return;
    final result = CloseHandle(_handle);
    if (!result.value) {
      throw StateError('FIXTURE_LOCK_CLOSE_FAILED');
    }
    isClosed = true;
  }
}

void main() {
  group('owned MCP bundle fixture cleanup', () {
    test('removes the real owned directory and nested files', () async {
      final root = _fixture();
      try {
        final nested = Directory(p.join(root.path, 'nested'))..createSync();
        File(p.join(nested.path, 'fixture.bin')).writeAsBytesSync([1, 2, 3]);
        await deleteOwnedFixtureDirectory(root);
        expect(
          FileSystemEntity.typeSync(root.path, followLinks: false),
          FileSystemEntityType.notFound,
        );
      } finally {
        await _cleanRemaining(root);
      }
    });

    test('retries a real delete lock released by a timer', () async {
      final root = _fixture();
      _DeletionLock? lock;
      Timer? release;
      try {
        final locked = File(p.join(root.path, 'locked.bin'))
          ..writeAsBytesSync([1]);
        final heldLock = _DeletionLock(locked);
        lock = heldLock;
        expect(
          locked.deleteSync,
          throwsA(
            isA<FileSystemException>().having(
              (error) => error.osError?.errorCode,
              'native sharing violation',
              32,
            ),
          ),
        );
        release = Timer(const Duration(milliseconds: 125), heldLock.close);
        await deleteOwnedFixtureDirectory(root);
        expect(heldLock.isClosed, isTrue);
        expect(root.existsSync(), isFalse);
      } finally {
        release?.cancel();
        lock?.close();
        await _cleanRemaining(root);
      }
    });

    test(
      'persistent real delete lock fails within the requested bound',
      () async {
        final root = _fixture();
        _DeletionLock? lock;
        try {
          final locked = File(p.join(root.path, 'locked.bin'))
            ..writeAsBytesSync([1]);
          final heldLock = _DeletionLock(locked);
          lock = heldLock;
          final elapsed = Stopwatch()..start();
          await expectLater(
            deleteOwnedFixtureDirectory(
              root,
              deadline: const Duration(milliseconds: 150),
            ),
            throwsA(
              isA<FileSystemException>().having(
                (error) => error.osError?.errorCode,
                'native delete lock failure',
                isIn([5, 32, 33, 145]),
              ),
            ),
          );
          expect(
            elapsed.elapsed,
            greaterThanOrEqualTo(const Duration(milliseconds: 150)),
          );
          expect(elapsed.elapsed, lessThan(const Duration(seconds: 2)));
          expect(root.existsSync(), isTrue);
          expect(locked.readAsBytesSync(), [1]);
          expect(heldLock.isClosed, isFalse);
        } finally {
          lock?.close();
          await _cleanRemaining(root);
        }
      },
    );

    test(
      'refuses a nested prefix-looking target and preserves its sentinel',
      () async {
        final root = _fixture();
        try {
          final outside = Directory(
            p.join(root.path, 'serverdeck-mcp-bundle-not-a-temp-root'),
          )..createSync();
          final sentinel = File(p.join(outside.path, 'sentinel'))
            ..writeAsStringSync('keep');
          await expectLater(
            deleteOwnedFixtureDirectory(outside),
            throwsA(isA<StateError>()),
          );
          expect(sentinel.readAsStringSync(), 'keep');
        } finally {
          await _cleanRemaining(root);
        }
      },
    );

    test('refuses a junction root and preserves its target sentinel', () async {
      final root = _fixture();
      final target = _fixture();
      final sentinel = File(p.join(target.path, 'sentinel'))
        ..writeAsStringSync('keep');
      await deleteOwnedFixtureDirectory(root);
      final link = Link(root.path);
      try {
        _createDirectoryJunction(link, target);
        await expectLater(
          deleteOwnedFixtureDirectory(root),
          throwsA(isA<StateError>()),
        );
        expect(sentinel.readAsStringSync(), 'keep');
      } finally {
        // This is the exact owned name just vacated above. Unlink without a
        // recursive traversal; the target is cleaned separately after proving
        // the refused operation preserved it.
        if (FileSystemEntity.typeSync(link.path, followLinks: false) ==
            FileSystemEntityType.link) {
          link.deleteSync();
        }
        await _cleanRemaining(root);
        await _cleanRemaining(target);
      }
    });

    test(
      'recursive cleanup does not follow a descendant directory junction',
      () async {
        final root = _fixture();
        final target = _fixture();
        try {
          final sentinel = File(p.join(target.path, 'sentinel'))
            ..writeAsStringSync('keep');
          _createDirectoryJunction(Link(p.join(root.path, 'outside')), target);
          await deleteOwnedFixtureDirectory(root);
          expect(root.existsSync(), isFalse);
          expect(sentinel.readAsStringSync(), 'keep');
        } finally {
          await _cleanRemaining(root);
          await _cleanRemaining(target);
        }
      },
    );

    test('rejects zero, negative, and over-five-second deadlines', () async {
      final root = _fixture();
      try {
        final sentinel = File(p.join(root.path, 'sentinel'))
          ..writeAsStringSync('keep');
        for (final deadline in [
          Duration.zero,
          const Duration(microseconds: -1),
          const Duration(seconds: 5, microseconds: 1),
        ]) {
          await expectLater(
            deleteOwnedFixtureDirectory(root, deadline: deadline),
            throwsArgumentError,
          );
          expect(sentinel.readAsStringSync(), 'keep');
        }
      } finally {
        await _cleanRemaining(root);
      }
    });
  }, testOn: 'windows');
}
