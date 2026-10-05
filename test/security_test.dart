import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/data/credentials.dart';
import 'package:serverdeck/data/ssh.dart';

void main() {
  test('BR-P01 enrolled identity rejects changed key and key type', () {
    final identity = EnrolledIdentity(
      endpoint: 'fixture.invalid',
      port: 22,
      keyType: 'ssh-ed25519',
      fingerprint: 'SHA256:${'A' * 43}',
    );
    Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));
    expect(
      identity.accepts('ssh-ed25519', bytes('SHA256:${'A' * 43}')),
      isTrue,
    );
    expect(
      identity.accepts('ssh-ed25519', bytes('SHA256:${'B' * 43}')),
      isFalse,
    );
    expect(identity.accepts('ssh-rsa', bytes('SHA256:${'A' * 43}')), isFalse);
    expect(
      () => EnrolledIdentity(
        endpoint: 'fixture.invalid',
        port: 22,
        keyType: 'ssh-ed25519',
        fingerprint: '',
      ),
      throwsArgumentError,
    );
  });
  test('BR-P01 credential debug representation cannot reveal material', () {
    expect(
      const SshCredential.password('fixture-secret').toString(),
      isNot(contains('fixture-secret')),
    );
    expect(
      const SshCredential.key('fixture-key', passphrase: 'phrase').toString(),
      isNot(contains('phrase')),
    );
  });
}
