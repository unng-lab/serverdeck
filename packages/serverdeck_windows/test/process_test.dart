import 'dart:io';

import 'package:serverdeck_windows/process.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:test/test.dart';

void main() {
  test(
    'CNG SHA256 matches standard vector and process approval fails closed',
    () {
      final root = Directory.systemTemp.createTempSync('serverdeck-sha-');
      final identity = RetainedProcessIdentity.open(pid);
      try {
        final file = File('${root.path}/vector')..writeAsStringSync('abc');
        expect(
          fileSha256(file.path),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
        );
        final hash = fileSha256(identity.imagePath);
        verifyProcessImage(
          identity,
          currentUserSid(),
          identity.imagePath,
          hash,
        );
        expect(
          () => verifyProcessImage(identity, currentUserSid(), file.path, hash),
          throwsStateError,
        );
        expect(
          () => verifyProcessImage(
            identity,
            currentUserSid(),
            identity.imagePath,
            '0' * 64,
          ),
          throwsStateError,
        );
        identity.close();
        expect(
          () => verifyProcessImage(
            identity,
            currentUserSid(),
            identity.imagePath,
            hash,
          ),
          throwsStateError,
        );
      } finally {
        identity.close();
        root.deleteSync(recursive: true);
      }
    },
    testOn: 'windows',
  );
}
