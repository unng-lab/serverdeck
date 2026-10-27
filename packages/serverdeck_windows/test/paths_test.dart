import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:test/test.dart';

void main() {
  test(
    'retained protected reader permits atomic replacement and reads old object',
    () async {
      final parent = Directory.systemTemp.createTempSync(
        'serverdeck-shared-snapshot-',
      );
      final root = p.normalize(p.absolute(parent.path));
      if (!p.isWithin(
        p.normalize(p.absolute(Directory.systemTemp.path)),
        root,
      )) {
        throw StateError('UNSAFE_TEST_DIRECTORY');
      }
      final sid = currentUserSid(), folder = p.join(root, 'private');
      final target = p.join(folder, 'состояние-確認.discovery');
      ProtectedSnapshotReader? reader;
      try {
        createProtectedDirectory(root, folder, sid);
        await writeNewProtectedFile(root, target, sid, [1, 2, 3]);
        reader = ProtectedSnapshotReader.open(root, target, sid, maxBytes: 3);
        await replaceProtectedFile(root, target, sid, [4, 5]);
        expect(reader.read(), [1, 2, 3]);
        expect(await readProtectedFile(root, target, sid, maxBytes: 3), [4, 5]);
        expect(reader.read, throwsA(isA<FileSystemException>()));
        reader.close();
        reader.close();
        expect(reader.read, throwsA(isA<FileSystemException>()));
        reader = null;
        requireOwnerOnlyFileAcl(target, sid);
        expect(Directory(folder).listSync().length, 1);
      } finally {
        reader?.close();
        parent.deleteSync(recursive: true);
      }
    },
    testOn: 'windows',
  );
  test('protected snapshot read accepts 64MiB bound and rejects excess before read', () async {
    final parent = Directory.systemTemp.createTempSync(
      'serverdeck-snapshot-read-',
    );
    final root = p.normalize(p.absolute(parent.path));
    if (!p.isWithin(p.normalize(p.absolute(Directory.systemTemp.path)), root))
      throw StateError('UNSAFE_TEST_DIRECTORY');
    final sid = currentUserSid(), folder = p.join(root, 'private');
    final target = p.join(folder, 'workspace.isar');
    try {
      createProtectedDirectory(root, folder, sid);
      await createProtectedEmptyFile(root, target, sid);
      final writer = File(target).openSync(mode: FileMode.writeOnly);
      try {
        writer.truncateSync(32 * 1024 * 1024 + 1);
        writer.flushSync();
      } finally {
        writer.closeSync();
      }
      final bytes = await readProtectedFile(
        root,
        target,
        sid,
        maxBytes: 64 * 1024 * 1024,
      );
      expect(bytes.length, 32 * 1024 * 1024 + 1);
      await expectLater(
        readProtectedFile(root, target, sid, maxBytes: 32 * 1024 * 1024),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.message,
            'code',
            'RESOURCE_LIMIT',
          ),
        ),
      );
      await expectLater(
        readProtectedFile(root, target, sid, maxBytes: 64 * 1024 * 1024 + 1),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.message,
            'code',
            'RESOURCE_LIMIT',
          ),
        ),
      );
      requireOwnerOnlyFileAcl(target, sid);
    } finally {
      parent.deleteSync(recursive: true);
    }
  }, testOn: 'windows');
  test(
    'protected reader copies multiple native chunks and enforces exact bound',
    () async {
      final parent = Directory.systemTemp.createTempSync(
        'serverdeck-chunked-snapshot-',
      );
      final root = p.normalize(p.absolute(parent.path));
      if (!p.isWithin(
        p.normalize(p.absolute(Directory.systemTemp.path)),
        root,
      )) {
        throw StateError('UNSAFE_TEST_DIRECTORY');
      }
      final sid = currentUserSid(), folder = p.join(root, 'private');
      final target = p.join(folder, 'snapshot');
      final expected = List<int>.generate(131079, (index) => index % 251);
      try {
        createProtectedDirectory(root, folder, sid);
        await writeNewProtectedFile(root, target, sid, expected);
        expect(
          await readProtectedFile(root, target, sid, maxBytes: expected.length),
          expected,
        );
        await expectLater(
          readProtectedFile(root, target, sid, maxBytes: expected.length - 1),
          throwsA(
            isA<FileSystemException>().having(
              (error) => error.message,
              'safe code',
              'RESOURCE_LIMIT',
            ),
          ),
        );
        await replaceProtectedFile(root, target, sid, [9]);
        expect(await readProtectedFile(root, target, sid, maxBytes: 1), [9]);
      } finally {
        parent.deleteSync(recursive: true);
      }
    },
    testOn: 'windows',
  );
  // Native fixture roots are synthetic LOCALAPPDATA inputs. System temp need
  // not be a child of the real user's LOCALAPPDATA (for example on CI).
  test('empty native store file is protected at creation and cannot replace existing data', () async {
    final local = p.normalize(p.absolute(Directory.systemTemp.path));
    final parent = Directory.systemTemp.createTempSync(
      'serverdeck-synthetic-empty-',
    );
    final absolute = p.normalize(p.absolute(parent.path));
    if (!p.isWithin(
      p.normalize(p.absolute(Directory.systemTemp.path)),
      absolute,
    ))
      throw StateError('UNSAFE_TEST_DIRECTORY');
    final folder = p.join(absolute, 'private');
    final target = p.join(folder, 'aggregate.isar');
    final sid = currentUserSid();
    try {
      createProtectedDirectory(local, folder, sid);
      await createProtectedEmptyFile(local, target, sid);
      requireOwnerOnlyFileAcl(target, sid);
      expect(File(target).lengthSync(), 0);
      await expectLater(
        createProtectedEmptyFile(local, target, sid),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(target).lengthSync(), 0);
      await expectLater(
        writeNewProtectedFile(local, p.join(folder, 'secret-wrapper'), sid, []),
        throwsA(isA<FileSystemException>()),
      );
    } finally {
      parent.deleteSync(recursive: true);
    }
  }, testOn: 'windows');
  test('protected create flush read and atomic replace preserve ACL', () async {
    final local = p.normalize(p.absolute(Directory.systemTemp.path));
    final parent = Directory.systemTemp.createTempSync(
      'serverdeck-synthetic-file-',
    );
    final folder = '${parent.path}\\private';
    final target = '$folder\\wrapped.bin';
    final sid = currentUserSid();
    try {
      createProtectedDirectory(local, folder, sid);
      await writeNewProtectedFile(local, target, sid, [1, 2, 3]);
      expect(await readProtectedFile(local, target, sid), [1, 2, 3]);
      await expectLater(
        writeNewProtectedFile(local, target, sid, [4]),
        throwsA(isA<FileSystemException>()),
      );
      await replaceProtectedFile(local, target, sid, [4, 5]);
      expect(await readProtectedFile(local, target, sid), [4, 5]);
      requireOwnerOnlyFileAcl(target, sid);
    } finally {
      parent.deleteSync(recursive: true);
    }
  }, testOn: 'windows');
  test('private directory has explicit owner/SYSTEM ACL and rejects ordinary inherited ACL', () {
    final local = p.normalize(p.absolute(Directory.systemTemp.path));
    final parent = Directory.systemTemp.createTempSync(
      'serverdeck-synthetic-acl-',
    );
    final target = '${parent.path}\\private';
    final sid = currentUserSid();
    try {
      createProtectedDirectory(local, target, sid);
      requireOwnerOnlyFileAcl(target, sid);
      expect(
        () => requireOwnerOnlyFileAcl(parent.path, sid),
        throwsA(isA<StateError>()),
      );
    } finally {
      parent.deleteSync(recursive: true);
    }
  }, testOn: 'windows');
  test('declared local root rejects independent temp locations', () {
    const local = r'C:\synthetic-local-app-data';
    for (final target in [
      r'C:\synthetic-temp\private',
      r'D:\synthetic-temp\private',
    ]) {
      expect(
        () => validateLocalPath(local, target),
        throwsA(
          isA<FileSystemException>().having(
            (error) => error.message,
            'safe code',
            'UNSAFE_PATH',
          ),
        ),
      );
    }
  }, testOn: 'windows');
  test('reject UNC and escaping local app data', () {
    final local = Platform.environment['LOCALAPPDATA']!;
    expect(
      () => validateLocalPath(local, r'\\server\share\private'),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      () => validateLocalPath(local, r'C:\outside-private'),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      validateLocalPath(local, '$local\\ServerDeckNext\\v1'),
      endsWith('ServerDeckNext\\v1'),
    );
  }, testOn: 'windows');
  test(
    'protected directory read failure contains no private path or native text',
    () async {
      final local = p.normalize(p.absolute(Directory.systemTemp.path));
      final parent = Directory.systemTemp.createTempSync(
        'serverdeck-synthetic-reader-',
      );
      final absolute = p.normalize(p.absolute(parent.path));
      if (!p.isWithin(
        p.normalize(p.absolute(Directory.systemTemp.path)),
        absolute,
      )) {
        throw StateError('UNSAFE_TEST_DIRECTORY');
      }
      final folder = p.join(absolute, 'synthetic-private-path-marker');
      final directory = p.join(folder, 'directory');
      final sid = currentUserSid();
      try {
        createProtectedDirectory(local, folder, sid);
        createProtectedDirectory(local, directory, sid);
        await expectLater(
          readProtectedFile(local, directory, sid),
          throwsA(
            isA<FileSystemException>()
                .having((e) => e.path, 'path', isEmpty)
                .having((e) => e.osError, 'native error', isNull)
                .having((e) => e.message, 'safe code', 'STORAGE_BLOCKED')
                .having(
                  (e) => e.toString().contains('synthetic-private-path-marker'),
                  'private marker',
                  isFalse,
                ),
          ),
        );
      } finally {
        parent.deleteSync(recursive: true);
      }
    },
    testOn: 'windows',
  );
  test('rejects a real directory junction before creating private data', () {
    final local = p.normalize(p.absolute(Directory.systemTemp.path));
    final parent = Directory.systemTemp.createTempSync(
      'serverdeck-synthetic-junction-',
    );
    final absolute = p.normalize(p.absolute(parent.path));
    if (!p.isWithin(
          p.normalize(p.absolute(Directory.systemTemp.path)),
          absolute,
        ) ||
        !p.isWithin(p.normalize(p.absolute(local)), absolute)) {
      throw StateError('UNSAFE_TEST_DIRECTORY');
    }
    final target = Directory(p.join(absolute, 'target'))..createSync();
    final junction = Link(p.join(absolute, 'junction'));
    try {
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
        reason: 'Synthetic junction setup must succeed',
      );
      expect(
        FileSystemEntity.typeSync(junction.path, followLinks: false),
        FileSystemEntityType.link,
      );
      expect(
        () => requireSafePath(local, p.join(junction.path, 'private')),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        () => createProtectedDirectory(
          local,
          p.join(junction.path, 'private'),
          currentUserSid(),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(Directory(p.join(target.path, 'private')).existsSync(), isFalse);
    } finally {
      // Remove the junction itself before recursively cleaning the owned temp.
      if (FileSystemEntity.typeSync(junction.path, followLinks: false) ==
          FileSystemEntityType.link) {
        junction.deleteSync();
      }
      if (FileSystemEntity.typeSync(junction.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw StateError('TEST_JUNCTION_CLEANUP_FAILED');
      }
      parent.deleteSync(recursive: true);
    }
  }, testOn: 'windows');
}
