import 'dart:convert';

import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:test/test.dart';

const workspace = '12345678-1234-4234-9234-123456789abc';
const receiptKeyId = '12345678-1234-4234-9234-123456789abd';
const foreignId = '12345678-1234-4234-9234-123456789abe';

void main() {
  test(
    'receipt key survives CurrentUser reopen without encrypting metadata',
    () async {
      final custody = KeyCustody(DpapiProtection(), currentUserSid());
      final material = await custody.createReceiptKey(workspace, receiptKeyId);
      ReceiptKeyMaterial? reopened;
      ReceiptKeyMaterial? independent;
      try {
        reopened = await custody.openReceiptKey(
          material.wrapper,
          workspace,
          receiptKeyId,
        );
        independent = await custody.createReceiptKey(workspace, receiptKeyId);
        final input = <String, Object?>{
          'method': 'profiles.create',
          'params': {'password': ' synthetic marker ', 'name': 'Synthetic'},
        };
        final digest = await custody.receiptDigest(material, input);
        final decomposedDigest = await custody.receiptDigest(material, {
          'password': 'e\u0301',
        });
        expect(
          await custody.receiptDigest(material, {'password': '\u00e9'}),
          isNot(decomposedDigest),
        );
        expect(base64.decode(digest), hasLength(32));
        expect(await custody.receiptDigest(reopened, input), digest);
        expect(await custody.receiptDigest(independent, input), isNot(digest));
        expect(
          await custody.receiptDigest(material, {
            'params': input['params'],
            'method': 'profiles.create',
          }),
          digest,
        );
        expect(
          await custody.receiptDigest(material, {
            ...input,
            'method': 'profiles.update',
          }),
          isNot(digest),
        );
        await expectLater(
          custody.openReceiptKey(material.wrapper, foreignId, receiptKeyId),
          throwsStateError,
        );
        await expectLater(
          custody.openReceiptKey(material.wrapper, workspace, foreignId),
          throwsStateError,
        );
        await expectLater(
          custody.openReceiptKey([1, 2, 3], workspace, receiptKeyId),
          throwsStateError,
        );
        await expectLater(
          custody.openReceiptKey(
            List.filled(16385, 0),
            workspace,
            receiptKeyId,
          ),
          throwsStateError,
        );
        final manifest = await custody.createWorkspaceManifest(material);
        expect(manifest.keys.toSet(), {
          'product',
          'schema',
          'workspaceId',
          'receiptKeyId',
          'ownerSid',
        });
        expect(
          utf8.decode(utf8.encode(jsonEncode(manifest))),
          contains(workspace),
        );
        await custody.verifyWorkspaceManifest(manifest, reopened);
        await expectLater(
          custody.verifyWorkspaceManifest({
            ...manifest,
            'workspaceId': foreignId,
          }, reopened),
          throwsStateError,
        );
        await expectLater(
          custody.verifyWorkspaceManifest({
            ...manifest,
            'mac': 'old-format',
          }, reopened),
          throwsStateError,
        );
        material.close();
        await expectLater(
          custody.receiptDigest(material, input),
          throwsStateError,
        );
      } finally {
        material.close();
        reopened?.close();
        independent?.close();
      }
    },
    testOn: 'windows',
  );
}
