import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/process.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:test/test.dart';

void main() {
  test(
    'protected chunk copy supports64MiB bound and never overwrites targets',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'serverdeck-migration-files-',
      );
      final path = p.normalize(p.absolute(root.path));
      final sid = currentUserSid(), folder = p.join(path, 'private');
      final source = p.join(folder, 'источник.isar'),
          target = p.join(folder, 'copy.isar');
      try {
        createProtectedDirectory(path, folder, sid);
        await createProtectedEmptyFile(path, source, sid);
        final file = await File(source).open(mode: FileMode.write);
        try {
          final chunk = List<int>.generate(1024 * 1024, (i) => i % 251);
          for (var i = 0; i < 33; i++) {
            await file.writeFrom(chunk);
          }
          await file.flush();
        } finally {
          await file.close();
        }
        final original = fileSha256(source);
        await copyProtectedFile(path, source, target, sid);
        expect(File(target).lengthSync(), 33 * 1024 * 1024);
        expect(fileSha256(target), original);
        expect(fileSha256(source), original);
        requireOwnerOnlyFileAcl(target, sid);
        await expectLater(
          copyProtectedFile(path, source, target, sid),
          throwsA(isA<FileSystemException>()),
        );
        expect(fileSha256(target), original);
        final limited = p.join(folder, 'limited.isar');
        await expectLater(
          copyProtectedFile(
            path,
            source,
            limited,
            sid,
            maxBytes: 32 * 1024 * 1024,
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(File(limited).existsSync(), isFalse);
        await requireProtectedDiskSpace(path, folder, sid, minimumBytes: 1);
        await expectLater(
          requireProtectedDiskSpace(
            path,
            folder,
            sid,
            minimumBytes: 0x7fffffffffffffff,
          ),
          throwsA(isA<FileSystemException>()),
        );
        await expectLater(
          copyProtectedFile(
            path,
            source,
            p.join(path, '..', 'escape.isar'),
            sid,
          ),
          throwsA(isA<FileSystemException>()),
        );
      } finally {
        if (!p.isWithin(
              p.normalize(p.absolute(Directory.systemTemp.path)),
              path,
            ) ||
            !p.basename(path).startsWith('serverdeck-migration-files-'))
          throw StateError('UNSAFE_FIXTURE');
        root.deleteSync(recursive: true);
      }
    },
    testOn: 'windows',
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
