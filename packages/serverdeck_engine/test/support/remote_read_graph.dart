import 'dart:convert';

import 'package:serverdeck_engine/storage/workspace_rows.dart';

import '../storage/workspace_snapshot_test.dart' as snapshotFixture;
import 'schema3_fixture.dart' as fixture;

String profileId(int index) => index == 0
    ? fixture.profile
    : '23456789-1234-4234-9234-${index.toString().padLeft(12, '0')}';
String credentialId(int index) => index == 0
    ? fixture.credential
    : '33456789-1234-4234-9234-${index.toString().padLeft(12, '0')}';

/// Builds ordinary source rows, then Setup uses the real schema3/custody loader.
/// No snapshot/context/result constructors or native repository are bypassed.
Future<void> expandReadGraph(
  snapshotFixture.Setup data, {
  int profiles = 1,
  bool wide = false,
  List<String> scopes = const ['read'],
}) async {
  final baseProfile = jsonDecode(
    data.source.data['StoredProfile']!.single.payload,
  ) as Map<String, dynamic>;
  final baseCredential = jsonDecode(
    data.source.data['StoredCredential']!.single.payload,
  ) as Map<String, dynamic>;
  final profileRows = <StoredRow>[],
      credentials = <StoredRow>[],
      trust = <StoredRow>[];
  for (var i = 0; i < profiles; i++) {
    final id = profileId(i), key = credentialId(i);
    final blob = i == 0
        ? baseCredential['protectedBlob']
        : await data.custody.wrapCredential(fixture.workspace, id, key, {
            'action': 'replace',
            'kind': 'password',
            'password': 'unit-only-secret',
          });
    profileRows.add(
      StoredRow(
        71 + i,
        jsonEncode({
          ...baseProfile,
          'id': id,
          'credentialRef': key,
          if (i > 0) 'address': 'unit-$i.invalid',
          if (wide)
            'name': 'profile-${i.toString().padLeft(3, '0')}${'x' * 110}',
          if (wide)
            'tags': [
              for (var j = 0; j < 16; j++)
                '${j.toString().padLeft(2, '0')}${'t' * 62}',
            ],
        }),
        entityId: id,
      ),
    );
    credentials.add(
      StoredRow(
        83 + i,
        jsonEncode({
          ...baseCredential,
          'id': key,
          'profileId': id,
          'protectedBlob': blob,
        }),
        entityId: key,
      ),
    );
    trust.add(
      StoredRow(
        97 + i,
        jsonEncode({...fixture.trustDocument(), 'profileId': id}),
        entityId: id,
      ),
    );
  }
  data.source.data['StoredProfile'] = profileRows;
  data.source.data['StoredCredential'] = credentials;
  data.source.data['StoredHostTrust'] = trust;
  data.source.data['StoredMcpGrant'] = [
    StoredRow(
      17,
      jsonEncode({
        ...fixture.grantDocument(),
        'scopes': scopes,
        'serverIds': [for (var i = 0; i < profiles; i++) profileId(i)],
      }),
      entityId: fixture.grant,
    ),
  ];
  // Ordinary foundation history has one receipt per committed store revision.
  // Give each extra profile a create and trust confirmation, preserving its
  // own entity revisions1/2 and the full validated global revision chain.
  final receipts = data.source.data['StoredReceipt']!;
  for (var i = 1; i < profiles; i++) {
    for (var phase = 1; phase <= 2; phase++) {
      final revision = i * 2 + phase;
      final request =
          '43456789-1234-4234-9234-${revision.toString().padLeft(12, '0')}';
      final row = fixture.receipt(
        request,
        phase == 1 ? 'profiles.create' : 'servers.trust.confirm',
        '$phase',
      );
      row['profileId'] = profileId(i);
      row['result'] = {
        ...(row['result'] as Map<String, Object?>),
        'entityId': profileId(i),
        'storeRevision': '$revision',
      };
      receipts.add(
        StoredRow(1000 + revision, jsonEncode(row), entityId: request),
      );
    }
  }
  final workspace = data.source.data['StoredWorkspace']!.single;
  data.source.data['StoredWorkspace'] = [
    StoredRow(
      workspace.nativeId,
      jsonEncode({
        ...jsonDecode(workspace.payload) as Map<String, dynamic>,
        'storeRevision': '${profiles * 2}',
      }),
    ),
  ];
}
