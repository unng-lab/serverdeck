import 'dart:convert';

import 'package:serverdeck_locald/storage/credential_validation.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/models.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:test/test.dart';

import 'models_test.dart' as fixture;

WorkspaceState state(String sid, String blob, {String kind = 'password'}) {
  final value = fixture.populated()..['ownerSid'] = sid;
  (value['profiles'] as Map)[fixture.profileId] = fixture.profile(
    credential: fixture.credentialId,
  );
  value['credentials'] = {
    fixture.credentialId: {
      'id': fixture.credentialId,
      'revision': '1',
      'profileId': fixture.profileId,
      'kind': kind,
      'protectedBlob': blob,
      'createdAt': fixture.time,
      'updatedAt': fixture.time,
    },
  };
  return WorkspaceState.fromJson(
    value,
    workspaceId: fixture.workspace,
    receiptKeyId: fixture.receiptKeyId,
    ownerSid: sid,
  );
}

void main() {
  test('startup validates actual CurrentUser blobs and metadata kind without returning secrets', () async {
    final sid = currentUserSid();
    final custody = KeyCustody(DpapiProtection(), sid);
    await validateWorkspaceCredentials(
      WorkspaceState.empty(
        workspaceId: fixture.workspace,
        receiptKeyId: fixture.receiptKeyId,
        ownerSid: sid,
      ),
      custody,
    );
    final blob = await custody.wrapCredential(
      fixture.workspace,
      fixture.profileId,
      fixture.credentialId,
      {
        'action': 'replace',
        'kind': 'password',
        'password': ' synthetic marker ',
      },
    );
    final valid = state(sid, blob);
    final before = valid.toJson();
    await validateWorkspaceCredentials(valid, custody);
    expect(valid.toJson(), before);
    await expectLater(
      validateWorkspaceCredentials(
        state(sid, blob, kind: 'privateKey'),
        custody,
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'safe code',
          'STORAGE_BLOCKED',
        ),
      ),
    );
    await expectLater(
      validateWorkspaceCredentials(
        state(sid, base64.encode([1, 2, 3])),
        custody,
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'safe code',
          'STORAGE_BLOCKED',
        ),
      ),
    );
    final foreignOwner = KeyCustody(DpapiProtection(), fixture.sid);
    await expectLater(
      validateWorkspaceCredentials(valid, foreignOwner),
      throwsStateError,
    );
    final wrongIdentity = await custody.wrapCredential(
      fixture.workspace,
      fixture.profileId,
      fixture.receiptKeyId,
      {
        'action': 'replace',
        'kind': 'password',
        'password': ' synthetic marker ',
      },
    );
    await expectLater(
      validateWorkspaceCredentials(state(sid, wrongIdentity), custody),
      throwsStateError,
    );
  }, testOn: 'windows');
}
