import 'dart:convert';
import 'dart:io';

import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:test/test.dart';

void main() {
  test(
    'retained process identity rechecks SID image creation and liveness',
    () {
      final identity = RetainedProcessIdentity.open(pid);
      try {
        expect(identity.sid, currentUserSid());
        // Dart 3.13's launcher reports dart.exe but runs this suite in dartvm.exe.
        expect(File(identity.imagePath).existsSync(), isTrue);
        expect(
          File(identity.imagePath).parent.path.toLowerCase(),
          File(Platform.resolvedExecutable).parent.path.toLowerCase(),
        );
        expect(BigInt.parse(identity.creationTime), greaterThan(BigInt.zero));
        identity.revalidate();
      } finally {
        identity.close();
        identity.close();
      }
      expect(identity.revalidate, throwsA(isA<StateError>()));
      expect(() => RetainedProcessIdentity.open(0), throwsA(isA<StateError>()));
    },
    testOn: 'windows',
  );
  test('current process SID is queried without impersonation', () {
    final sid = currentUserSid();
    expect(sid, startsWith('S-1-5-'));
    expect(currentUserSid(), sid);
  }, testOn: 'windows');
  test(
    'CurrentUser DPAPI roundtrip and entropy separation fail closed',
    () async {
      final provider = DpapiProtection();
      final input = utf8.encode('synthetic-DPAPI-marker');
      final protected = await provider.protect(
        input,
        utf8.encode('synthetic-root'),
      );
      expect(protected, isNot(input));
      expect(
        await provider.unprotect(protected, utf8.encode('synthetic-root')),
        input,
      );
      await expectLater(
        provider.unprotect(protected, utf8.encode('synthetic-discovery')),
        throwsA(isA<StateError>()),
      );
      final damaged = [...protected];
      damaged[damaged.length ~/ 2] ^= 255;
      await expectLater(
        provider.unprotect(damaged, utf8.encode('synthetic-root')),
        throwsA(isA<StateError>()),
      );
      // A failure does not poison the caller or change its identity.
      expect(
        await provider.unprotect(protected, utf8.encode('synthetic-root')),
        input,
      );
    },
    testOn: 'windows',
  );
}
