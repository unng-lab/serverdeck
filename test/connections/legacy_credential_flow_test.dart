import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/connections/ssh_transport.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/profiles/key_envelope.dart';

import '../fixtures/feature_harness.dart';

void main() {
  for (final name in ['rsa2048', 'rsa-pem-plain', 'rsa-pem-aes-256-cbc']) {
    final encrypted = name.contains('-cbc');
    for (final dropMetadata in [false, true]) {
      test(
        'current $name import preserves original bytes; missing metadata=$dropMetadata fails closed',
        () async {
          final h = FeatureHarness();
          final original = File('test/fixtures/ssh/$name.txt')
              .readAsBytesSync();
          final input = PrivateKeyInput(
            original,
            passphrase: encrypted ? 'serverdeck-unit-passphrase' : null,
          );
          try {
            final result = await h.profiles.createProfile(
              h.actors.ui,
              ProfileDraft(
                displayName: 'Legacy fixture',
                host: 'host.invalid',
                username: 'root',
                authentication: input,
              ),
              mutationId: h.newId(),
            );
            expect(result.error, isNull);
            final id = result.value!.entityId;
            final profile = h.repository.state.profiles[id]!;
            final stored =
                h.repository.state.credentials[profile.credentialId]!;
            // FeatureProtector is a synthetic identity adapter; this assertion is not a DPAPI claim.
            expect(stored.protectedBytes, original);
            expect(stored.publicKeyBytes, isNotNull);
            expect(
              readPublicKeyHint(
                original,
                publicKeyBytes: stored.publicKeyBytes!,
              ).inspection.encrypted,
              encrypted,
            );
            final detached = h.repository.read(
              (r) => r.credential(stored.credentialId)!,
            );
            detached.publicKeyBytes![0] ^= 1;
            expect(detached.publicKeyBytes, isNot(stored.publicKeyBytes));
            if (dropMetadata) stored.publicKeyBytes = null;
            await h.connections.connect(h.actors.ui, id, expectedRevision: 1);
            await featureTurns();
            if (dropMetadata) {
              expect(h.sessions, isEmpty);
              expect(
                h.connections.connection(id).failureCode,
                FailureCode.storageUnavailable,
              );
            } else {
              final credential =
                  h.sessions.single.options.credential as PrivateKeyCredential;
              expect(credential.publicHint.encoded, stored.publicKeyBytes);
              expect(credential.inspection.encrypted, encrypted);
              expect(credential.bytes, original);
            }
          } finally {
            input.dispose();
            await h.dispose();
          }
        },
      );
    }
  }
}
