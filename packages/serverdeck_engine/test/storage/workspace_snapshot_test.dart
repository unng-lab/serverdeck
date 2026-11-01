import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:serverdeck_engine/credentials/mcp_credential_files.dart';
import 'package:serverdeck_engine/credentials/mcp_credentials.dart';
import 'package:serverdeck_engine/platform/ports.dart';
import 'package:serverdeck_engine/storage/key_custody.dart';
import 'package:serverdeck_engine/storage/models.dart';
import 'package:serverdeck_engine/storage/records.dart';
import 'package:serverdeck_engine/storage/workspace_rows.dart';
import 'package:serverdeck_engine/storage/workspace_snapshot.dart';
import 'package:test/test.dart';

import '../support/memory_platform.dart' show Files, Protection;
import '../support/schema3_fixture.dart' as fixture;

Matcher blocked([String code = 'STORAGE_BLOCKED']) =>
    throwsA(isA<StateError>().having((e) => e.message, 'safe code', code));

const collections = [
  'StoredWorkspace',
  'StoredSettings',
  'StoredProfile',
  'StoredCredential',
  'StoredReceipt',
  'StoredHostTrust',
  'StoredMcpGrant',
  'StoredDelegation',
  'StoredAutomationProfile',
  'StoredAutomationRevision',
  'StoredAutomationPlan',
  'StoredAutomationApproval',
  'StoredAutomationJob',
  'StoredDesiredState',
  'StoredAutomationEvent',
  'StoredAutomationReceipt',
];

final class Lease implements WorkspaceLease {
  @override
  String ownerIdentity = fixture.owner;
  @override
  String workspaceSlot = 'default';
  @override
  String get name => 'unit-memory-lease';
  @override
  bool isHeld = true;
  @override
  bool acquired = true;
  int closes = 0;
  @override
  Future<void> close() async {
    closes++;
    isHeld = false;
  }
}

final class Rows implements WorkspaceRowSource {
  Rows(this.directory);
  @override
  String name = 'workspace';
  @override
  String directory;
  final data = <String, List<StoredRow>>{
    for (final name in collections) name: [],
  };
  final counts = <String, int>{};
  final reads = <String, int>{};
  bool reading = false;
  int transactions = 0;
  void Function(String)? afterCount;
  void Function()? afterTransaction;
  @override
  Future<T> readTransaction<T>(Future<T> Function() read) async {
    expect(reading, isFalse);
    transactions++;
    reading = true;
    try {
      return await read();
    } finally {
      reading = false;
      afterTransaction?.call();
    }
  }

  @override
  Future<int> count(String collection) async {
    expect(reading, isTrue);
    afterCount?.call(collection);
    return counts[collection] ?? data[collection]!.length;
  }

  @override
  Future<List<StoredRow>> read(String collection, {required int limit}) async {
    expect(reading, isTrue);
    reads[collection] = limit;
    return data[collection]!.take(limit).toList();
  }
}

final class Setup {
  Setup._(this.files, this.protection, this.custody, this.key, this.source);
  final Files files;
  final Protection protection;
  final KeyCustody custody;
  final ReceiptKeyMaterial key;
  final Rows source;
  final lease = Lease();
  static Future<Setup> create({
    bool populated = false,
    bool initial = false,
  }) async {
    final files = Files(), protection = Protection();
    final custody = KeyCustody(protection, fixture.owner);
    final key = await custody.createReceiptKey(
      fixture.workspace,
      fixture.receiptKey,
    );
    addTearDown(() {
      key.close();
      protection.dispose();
    });
    var directory = p.join(
      files.root,
      'ServerDeckNext',
      'v1',
      'workspaces',
      'default',
    );
    if (initial) {
      directory += '.creating';
      files.dirs.add(directory);
    }
    files.data[p.join(directory, 'workspace.isar')] = [];
    files.data[p.join(directory, 'workspace.isar-lck')] = [];
    final source = Rows(directory);
    final document = populated
        ? fixture.document()
        : WorkspaceState.empty(
            workspaceId: fixture.workspace,
            receiptKeyId: fixture.receiptKey,
            ownerSid: fixture.owner,
          ).toJson();
    if (populated) {
      ((document['credentials'] as Map)[fixture.credential]
          as Map)['protectedBlob'] = await custody.wrapCredential(
        fixture.workspace,
        fixture.profile,
        fixture.credential,
        {
          'action': 'replace',
          'kind': 'password',
          'password': 'unit-only-secret',
        },
      );
    }
    final state = fixture.parse(document),
        rows = WorkspaceRecords.fromState(state);
    source.data['StoredWorkspace'] = [StoredRow(1, rows.workspace.payload)];
    source.data['StoredSettings'] = [StoredRow(1, rows.settings.payload)];
    source.data['StoredProfile'] = [
      for (final row in rows.profiles)
        StoredRow(71, row.payload, entityId: row.entityId),
    ];
    source.data['StoredCredential'] = [
      for (final row in rows.credentials)
        StoredRow(83, row.payload, entityId: row.entityId),
    ];
    source.data['StoredReceipt'] = [
      for (var i = 0; i < rows.receipts.length; i++)
        StoredRow(
          101 - i,
          rows.receipts[i].payload,
          entityId: rows.receipts[i].entityId,
        ),
    ];
    final setup = Setup._(files, protection, custody, key, source);
    if (populated) {
      source.data['StoredHostTrust'] = [
        StoredRow(
          97,
          jsonEncode(fixture.trustDocument()),
          entityId: fixture.profile,
        ),
      ];
      final graph = fixture.grantGraph();
      for (final entry in {
        'grants': 'StoredMcpGrant',
        'receipts': 'StoredAutomationReceipt',
      }.entries) {
        source.data[entry.value] = [
          for (final row in graph[entry.key]!)
            StoredRow(row.nativeId, row.payload, entityId: row.entityId),
        ];
      }
      await setup.artifacts.stage(setup.binding);
    }
    files.writes = 0;
    return setup;
  }

  McpCredentialBinding get binding => McpCredentialBinding(
    workspaceId: fixture.workspace,
    grantId: fixture.grant,
    secretRef: fixture.secretRef,
    ownerSid: fixture.owner,
    issuedAt: fixture.second,
  );
  McpCredentialFiles get artifacts => McpCredentialFiles(
    protectedFiles: files,
    localAppData: files.root,
    workspaceId: fixture.workspace,
    ownerSid: fixture.owner,
    custody: McpCredentialCustody(protection),
  );
  Future<WorkspaceSnapshot> load({bool initial = false}) =>
      (initial ? readInitialWorkspace : readWorkspaceSnapshot)(
        source,
        key,
        custody,
        localAppData: files.root,
        lease: lease,
        protectedFiles: files,
      );
}

void main() {
  test(
    'one transaction captures all16 collections and retains exact IDs/payloads',
    () async {
      final setup = await Setup.create(populated: true);
      final before = {
        for (final entry in setup.source.data.entries)
          entry.key:
              entry.value
                  .map((r) => (r.nativeId, r.entityId, r.payload))
                  .toList()
                ..sort((a, b) => a.$1.compareTo(b.$1)),
      };
      expect(
        await setup.artifacts.readLookupForRecovery(fixture.grant),
        isNull,
      );
      final snapshot = await setup.load();
      expect(setup.source.transactions, 1);
      expect(setup.source.reads.keys.toSet(), collections.toSet());
      expect(setup.source.reads['StoredMcpGrant'], 33);
      expect(setup.source.reads['StoredAutomationEvent'], 10001);
      expect(setup.source.reads['StoredDesiredState'], 6);
      expect({
        for (final e in snapshot.rows.entries)
          e.key: e.value
              .map((r) => (r.nativeId, r.entityId, r.payload))
              .toList(),
      }, before);
      expect(snapshot.foundation.trust[fixture.profile]!.revision, '2');
      expect(snapshot.automation.grants.keys, [fixture.grant]);
      expect(
        (await setup.artifacts.readLookupForRecovery(fixture.grant))!
            .binding
            .secretRef,
        fixture.secretRef,
      );
      expect(setup.lease.closes, 0);
      expect(() => snapshot.rows.clear(), throwsUnsupportedError);
      expect(
        () => snapshot.rows['StoredProfile']!.clear(),
        throwsUnsupportedError,
      );
      setup.source.data['StoredProfile']!.clear();
      expect(snapshot.rows['StoredProfile'], hasLength(1));
    },
  );

  test(
    'count bounds and incomplete source views fail before snapshot publication',
    () async {
      for (final count in [-1, 2, 251]) {
        final setup = await Setup.create();
        setup.source.counts['StoredProfile'] = count;
        await expectLater(setup.load(), blocked());
        expect(setup.files.writes, 0);
        expect(setup.lease.closes, 0);
      }
    },
  );

  test('singleton IDs, duplicate native/entity IDs and schema selectors are refused', () async {
    final wrongId = await Setup.create();
    final old = wrongId.source.data['StoredWorkspace']!.single;
    wrongId.source.data['StoredWorkspace'] = [StoredRow(2, old.payload)];
    await expectLater(wrongId.load(), blocked());
    for (final schema in [1, 2, 4]) {
      final setup = await Setup.create();
      final value = jsonDecode(
        setup.source.data['StoredWorkspace']!.single.payload,
      ) as Map<String, dynamic>;
      value['schemaVersion'] = schema;
      setup.source.data['StoredWorkspace'] = [StoredRow(1, jsonEncode(value))];
      await expectLater(setup.load(), blocked('INCOMPATIBLE'));
      expect(setup.files.writes, 0);
    }
    final duplicate = await Setup.create(populated: true);
    duplicate.source.data['StoredProfile']!.add(
      duplicate.source.data['StoredProfile']!.single,
    );
    await expectLater(duplicate.load(), blocked());
    expect(duplicate.files.writes, 0);
  });

  test(
    'each automation family is captured and invalid rows cannot be discarded',
    () async {
      for (final name in collections.skip(6)) {
        final setup = await Setup.create();
        setup.source.data[name] = [
          StoredRow(19, '{}', entityId: fixture.grant),
        ];
        await expectLater(setup.load(), blocked());
        expect(setup.files.writes, 0);
      }
    },
  );

  test('writer/owner loss across async reads prevents publication without closing lease', () async {
    final setup = await Setup.create(populated: true);
    setup.source.afterCount = (_) => setup.lease.isHeld = false;
    await expectLater(setup.load(), blocked());
    expect(setup.source.reads, isEmpty);
    expect(setup.files.writes, 0);
    expect(setup.lease.closes, 0);
    final wrongOwner = await Setup.create();
    wrongOwner.lease.ownerIdentity = 'another-owner';
    await expectLater(wrongOwner.load(), blocked());
    expect(wrongOwner.source.transactions, 0);
  });

  test(
    'custody failure after coherent capture never repairs MCP lookup',
    () async {
      final setup = await Setup.create(populated: true);
      setup.source.afterTransaction = setup.protection.records.clear;
      await expectLater(setup.load(), blocked());
      expect(setup.source.reads, hasLength(16));
      expect(setup.files.writes, 0);
      expect(
        await setup.artifacts.readLookupForRecovery(fixture.grant),
        isNull,
      );
    },
  );

  test(
    'fresh stage accepts only empty graph and exact path/file custody',
    () async {
      final setup = await Setup.create(initial: true);
      final snapshot = await setup.load(initial: true);
      expect(snapshot.foundation.foundation.isInitialEmpty, isTrue);
      expect(setup.files.writes, 0);
      await expectLater(setup.load(), blocked());
      final nonempty = await Setup.create(initial: true, populated: true);
      await expectLater(nonempty.load(initial: true), blocked());
      expect(nonempty.files.writes, 0);
      final missingFile = await Setup.create();
      missingFile.files.data.remove(
        p.join(missingFile.source.directory, 'workspace.isar-lck'),
      );
      await expectLater(missingFile.load(), blocked());
      expect(missingFile.source.transactions, 0);
    },
  );
}
