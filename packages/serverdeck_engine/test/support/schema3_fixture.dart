import 'dart:convert';

import 'package:serverdeck_engine/automation/snapshot.dart';
import 'package:serverdeck_engine/storage/host_trust_models.dart';
import 'package:serverdeck_engine/storage/models.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:test/test.dart';

const workspace = '12345678-1234-4234-9234-123456789a01';
const receiptKey = '12345678-1234-4234-9234-123456789a02';
const profile = '12345678-1234-4234-9234-123456789a03';
const credential = '12345678-1234-4234-9234-123456789a04';
const request1 = '12345678-1234-4234-9234-123456789a05';
const request2 = '12345678-1234-4234-9234-123456789a06';
const grant = '12345678-1234-4234-9234-123456789a07';
const secretRef = '12345678-1234-4234-9234-123456789a08';
const grantRequest = '12345678-1234-4234-9234-123456789a09';
const owner = 'S-1-5-21-1-2-3-1001';
const first = '2026-10-30T10:00:00.000Z';
const second = '2026-10-30T10:00:01.000Z';
final digest = base64.encode(List.filled(32, 7));
final blob = base64.encode(List.generate(32, (index) => index));

Matcher blocked([String code = 'STORAGE_BLOCKED']) => throwsA(
  isA<StateError>().having((error) => error.message, 'safe code', code),
);

Map<String, Object?> receipt(String id, String operation, String revision) => {
  'requestId': id,
  'inputDigest': digest,
  'operation': operation,
  'profileId': profile,
  'result': {
    'entityId': profile,
    'entityRevision': revision,
    'storeRevision': revision,
    'deleted': false,
  },
  'committedAt': revision == '1' ? first : second,
};

Map<String, Object?> document() => {
  'schemaVersion': 3,
  'workspaceId': workspace,
  'receiptKeyId': receiptKey,
  'ownerSid': owner,
  'storeRevision': '2',
  'profiles': {
    profile: <String, Object?>{
      'id': profile,
      'revision': '2',
      'name': 'unit host',
      'address': 'unit.invalid',
      'port': 22,
      'sshUser': 'unit_user',
      'tags': ['unit'],
      'credentialRef': credential,
      'credentialRevision': '1',
      'connectionRevision': '1',
      'trustRevision': '2',
      'createdAt': first,
      'updatedAt': second,
    },
  },
  'credentials': {
    credential: {
      'id': credential,
      'revision': '1',
      'profileId': profile,
      'kind': 'password',
      'protectedBlob': blob,
      'createdAt': first,
      'updatedAt': first,
    },
  },
  'settings': {
    'revision': '1',
    'theme': 'dark',
    'reduceMotion': true,
    'selectedProfileId': profile,
  },
  'receipts': {
    request1: receipt(request1, 'profiles.create', '1'),
    request2: receipt(request2, 'servers.trust.confirm', '2'),
  },
};

WorkspaceState parse(Map<String, Object?> value, {String sid = owner}) =>
    WorkspaceState.fromJson(
      value,
      workspaceId: workspace,
      receiptKeyId: receiptKey,
      ownerSid: sid,
    );

Map<String, Object?> trustDocument() => {
  'workspaceId': workspace,
  'profileId': profile,
  'revision': '2',
  'connectionRevision': '1',
  'status': 'trusted',
  'key': {
    'format': 'ssh-ed25519',
    'fingerprint':
        'SHA256:${base64.encode(List.filled(32, 1)).replaceAll('=', '')}',
  },
  'createdAt': second,
  'updatedAt': second,
};

HostTrustState trusted() => HostTrustState.fromRecords(parse(document()), {
  profile: HostTrustRecord.fromJson(trustDocument()),
});

Map<String, Object?> grantDocument() => {
  'id': grant,
  'workspaceId': workspace,
  'label': 'unit history',
  'revision': 1,
  'scopes': ['read'],
  'serverIds': [profile],
  'createdAt': second,
  'issuedAt': second,
  'expiresAt': '2026-10-30T18:00:01.000Z',
  'revokedAt': null,
  'secretRef': secretRef,
};

Map<String, List<AutomationSnapshotRow>> collections() => {
  for (final name in [
    'grants',
    'delegations',
    'profiles',
    'revisions',
    'plans',
    'approvals',
    'jobs',
    'desired',
    'events',
    'receipts',
  ])
    name: <AutomationSnapshotRow>[],
};

Map<String, List<AutomationSnapshotRow>> grantGraph() {
  final result = collections();
  result['grants']!.add(
    AutomationSnapshotRow(17, grant, jsonEncode(grantDocument())),
  );
  result['receipts']!.add(
    AutomationSnapshotRow(
      29,
      grantRequest,
      jsonEncode({
        'workspaceId': workspace,
        'requestId': grantRequest,
        'originGrantId': null,
        'objectGrantId': null,
        'canonicalDigest': 'b' * 64,
        'operation': 'grant.create',
        'result': {'grantId': grant, 'revision': 1},
        'createdAt': second,
      }),
    ),
  );
  return result;
}
