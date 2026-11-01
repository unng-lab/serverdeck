import '../support/schema3_fixture.dart';

import 'dart:convert';

import 'package:serverdeck_engine/automation/snapshot.dart';
import 'package:serverdeck_engine/storage/host_trust_models.dart';
import 'package:serverdeck_engine/storage/models.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:test/test.dart';

void main() {
  test('target foundation preserves identities, wrappers, trust counters and receipt history', () {
    final input = document(), expected = jsonDecode(jsonEncode(document()));
    final state = parse(input);
    expect(state.toJson(), expected);
    expect(state.profiles[profile]!.connectionRevision, '1');
    expect(state.profiles[profile]!.trustRevision, '2');
    expect(state.credentials[credential]!.protectedBlob, blob);
    expect(state.receipts[request2]!.operation, 'servers.trust.confirm');
    ((input['profiles'] as Map)[profile]['tags'] as List).clear();
    ((input['credentials'] as Map)[credential] as Map)['protectedBlob'] =
        'changed';
    expect(state.toJson(), expected);
    expect(() => state.profiles.clear(), throwsUnsupportedError);
    ((state.toJson()['profiles'] as Map)[profile]['tags'] as List).clear();
    expect(state.toJson(), expected);
    expect(parse(state.toJson()).toJson(), expected);
    final empty = WorkspaceState.empty(
      workspaceId: workspace,
      receiptKeyId: receiptKey,
      ownerSid: owner,
    );
    expect(empty.schemaVersion, 3);
    expect(empty.isInitialEmpty, isTrue);
  });

  test('old and unknown schemas refuse without modifying caller data', () {
    for (final version in [1, 2, 4, 3.0, '3']) {
      final input = document()..['schemaVersion'] = version;
      final before = jsonEncode(input);
      expect(() => parse(input), blocked('INCOMPATIBLE'));
      expect(jsonEncode(input), before);
    }
    expect(() => parse(document(), sid: 'S-1-5-21-9-9-9-1001'), blocked());
  });

  test('foundation cannot lose receipts, borrow orphan credentials or reverse trust counters', () {
    final missingReceipt = document();
    (missingReceipt['receipts'] as Map).remove(request1);
    expect(() => parse(missingReceipt), blocked());
    final orphan = document();
    ((orphan['profiles'] as Map)[profile] as Map)['credentialRef'] = null;
    expect(() => parse(orphan), blocked());
    final reversed = document();
    ((reversed['profiles'] as Map)[profile] as Map)['connectionRevision'] = '2';
    ((reversed['profiles'] as Map)[profile] as Map)['trustRevision'] = '1';
    expect(() => parse(reversed), blocked());
    expect(
      () => nextRevision('9223372036854775807'),
      blocked('RESOURCE_LIMIT'),
    );
  });

  test('trust rows must bind the exact target workspace, profile and current counters', () {
    final state = parse(document());
    expect(() => HostTrustState.fromRecords(state, {}), blocked());
    final foreign = HostTrustRecord.fromJson({
      ...trustDocument(),
      'workspaceId': receiptKey,
    });
    expect(
      () => HostTrustState.fromRecords(state, {profile: foreign}),
      blocked(),
    );
    final stale = HostTrustRecord.fromJson({
      ...trustDocument(),
      'connectionRevision': '2',
    });
    expect(
      () => HostTrustState.fromRecords(state, {profile: stale}),
      blocked(),
    );
    expect(trusted().trust[profile]!.revision, '2');
  });

  test('graph captures all collections before await without restoring runtime authority', () async {
    final rows = grantGraph(), foundation = trusted();
    final pending = AutomationSnapshot.load(
      foundation: foundation,
      collections: rows,
    );
    rows['grants']!.clear();
    rows['receipts']!.clear();
    final graph = await pending;
    expect(graph.grants[grant]!.toJson(), grantDocument());
    expect(graph.receipts[grantRequest]!.operation, 'grant.create');
    expect(graph.jobs, isEmpty);
    expect(graph.events, isEmpty);
    expect(() => graph.grants.clear(), throwsUnsupportedError);
    final empty = await AutomationSnapshot.load(
      foundation: foundation,
      collections: collections(),
    );
    expect(empty.grants, isEmpty);
  });

  test('graph rejects missing families, native identity collisions and mismatched payload keys', () async {
    final foundation = trusted();
    final missing = collections()..remove('jobs');
    await expectLater(
      AutomationSnapshot.load(foundation: foundation, collections: missing),
      blocked(),
    );
    final duplicate = grantGraph();
    duplicate['grants']!.add(duplicate['grants']!.single);
    await expectLater(
      AutomationSnapshot.load(foundation: foundation, collections: duplicate),
      blocked(),
    );
    final wrongKey = grantGraph();
    wrongKey['grants'] = [
      AutomationSnapshotRow(17, receiptKey, jsonEncode(grantDocument())),
    ];
    await expectLater(
      AutomationSnapshot.load(foundation: foundation, collections: wrongKey),
      blocked(),
    );
    final invalidId = grantGraph();
    invalidId['grants'] = [
      AutomationSnapshotRow(0, grant, jsonEncode(grantDocument())),
    ];
    await expectLater(
      AutomationSnapshot.load(foundation: foundation, collections: invalidId),
      blocked(),
    );
  });

  test('graph requires receipt and workspace references before accepting retained grants', () async {
    final foundation = trusted();
    final noReceipt = grantGraph();
    noReceipt['receipts']!.clear();
    await expectLater(
      AutomationSnapshot.load(foundation: foundation, collections: noReceipt),
      blocked(),
    );
    final foreign = grantGraph();
    foreign['grants'] = [
      AutomationSnapshotRow(
        17,
        grant,
        jsonEncode({...grantDocument(), 'workspaceId': receiptKey}),
      ),
    ];
    await expectLater(
      AutomationSnapshot.load(foundation: foundation, collections: foreign),
      blocked(),
    );
    final excess = grantGraph();
    excess['grants'] = List.filled(33, excess['grants']!.single);
    await expectLater(
      AutomationSnapshot.load(foundation: foundation, collections: excess),
      blocked(),
    );
  });
}
