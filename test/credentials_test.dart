import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/data/credentials.dart';

void main() {
  test('password debug representation excludes material', () {
    expect(
      const SshCredential.password('synthetic-password').toString(),
      'SshCredential(password, protected)',
    );
  });
  test('key debug representation excludes material and passphrase', () {
    expect(
      const SshCredential.key(
        'synthetic-key',
        passphrase: 'synthetic-phrase',
      ).toString(),
      'SshCredential(key, protected)',
    );
  });
  test(
    'invalid references fail without including the supplied value',
    () async {
      final store = OsCredentialStore();
      for (final reference in ['', '../synthetic-secret', 'A', 'a' * 81]) {
        final invalid = isA<ArgumentError>().having(
          (e) => e.toString(),
          'diagnostic',
          isNot(contains('synthetic-secret')),
        );
        await expectLater(store.read(reference), throwsA(invalid));
        await expectLater(
          store.write(
            reference,
            const SshCredential.password('synthetic-secret'),
          ),
          throwsA(invalid),
        );
        await expectLater(store.delete(reference), throwsA(invalid));
      }
    },
    skip: !Platform.isWindows,
  );
}
