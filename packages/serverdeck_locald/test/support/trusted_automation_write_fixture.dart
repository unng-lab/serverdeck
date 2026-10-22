import 'dart:async';
import 'dart:convert';

import 'package:isar_community/isar.dart';
import 'package:serverdeck_locald/automation/profile_commands.dart';
import 'package:serverdeck_locald/storage/automation_records.dart';
import 'package:serverdeck_locald/storage/grant_write_probe.dart';
import 'package:serverdeck_locald/storage/host_trust_models.dart';
import 'package:serverdeck_locald/storage/host_trust_records.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/models.dart';
import 'package:serverdeck_locald/storage/native_failure.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_locald/mcp/grants.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_windows/mcp_credential_files.dart';
import 'package:serverdeck_windows/mcp_credentials.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/security.dart';

import 'grant_transaction_scenarios.dart' show grantCreate;
import 'profile_catalog_storage_scenarios.dart'
    show createCatalogCommand, catalogBody;
import '../automation/snapshot_test.dart' as g;
import 'mcp_runtime_actor.dart' show check, refusal;
import 'trusted_schema_child.dart' as raw;

final class _KeyProtection implements UserProtection {
  _KeyProtection(this.actual);
  final UserProtection actual;
  bool pause = false, deny = false;
  final entered = Completer<void>(), release = Completer<void>();
  final cleartexts = <List<int>>[];
  @override
  Future<List<int>> protect(List<int> bytes, List<int> entropy) =>
      actual.protect(bytes, entropy);
  @override
  Future<List<int>> unprotect(List<int> bytes, List<int> entropy) async {
    final mcp = utf8.decode(entropy).contains('serverdeck-next-mcp-client-v1');
    if (mcp && deny) throw StateError('OWNED_KEY_DENIED');
    final clear = await actual.unprotect(bytes, entropy);
    cleartexts.add(clear);
    if (mcp && pause) {
      pause = false;
      entered.complete();
      await release.future;
    }
    return clear;
  }
}

Future<void> exerciseTrustedAutomationWrite(
  String root,
  KeyCustody originalCustody,
  ReceiptKeyMaterial key,
  MutexLease lease,
  String mode,
) async {
  final protection = _KeyProtection(originalCustody.protection);
  final custody = KeyCustody(protection, originalCustody.ownerSid);
  Future<StateStore> open() => StateStore.openTrustedOperational(
    localAppData: root,
    appRoot: root,
    custody: custody,
    receiptKey: key,
    lease: lease,
  );
  var store = await open();
  final clock = () => DateTime.utc(2026, 11, 30), gid = g.id(70001);
  final command = OwnerGrantCommand.parse(
    'grant.create',
    grantCreate(70000, 70001),
  );
  Future<Map<String, Object?>> grant(OwnerGrantCommand c) =>
      store.mutateTrustedOwnerGrant(c, clock: clock);
  Future<Map<String, Object?>> profile(
    AutomationProfileCommand c, {
    String? origin,
    int? revision,
  }) => store.mutateTrustedAutomationProfile(
    c,
    originGrantId: origin,
    expectedGrantRevision: revision,
    clock: clock,
  );
  final files = McpCredentialFiles(
    localAppData: root,
    workspaceId: key.workspaceId,
    ownerSid: key.ownerSid,
    custody: McpCredentialCustody(custody.protection),
  );
  HostTrustState foundation(String requestId, {bool confirm = false}) {
    final before = store.state, server = before.profiles.values.single;
    final p = {
      ...server.toJson(),
      'revision': '${int.parse(server.revision) + 1}',
      'name': confirm ? server.name : 'Mixed queue metadata',
      'trustRevision': confirm
          ? '${int.parse(server.trustRevision) + 1}'
          : server.trustRevision,
      'updatedAt': clock().toIso8601String(),
    };
    final revision = '${int.parse(before.storeRevision) + 1}',
        doc = before.toJson()..['storeRevision'] = revision;
    (doc['profiles'] as Map)[server.id] = p;
    (doc['receipts'] as Map)[requestId] = {
      'requestId': requestId,
      'inputDigest': custody.receiptDigestSync(key, {
        'fixtureRequest': requestId,
      }),
      'operation': confirm ? 'servers.trust.confirm' : 'profiles.update',
      'profileId': server.id,
      'result': {
        'entityId': server.id,
        'entityRevision': p['revision'],
        'storeRevision': revision,
        'deleted': false,
      },
      'committedAt': clock().toIso8601String(),
    };
    return HostTrustState.fromRecords(
      WorkspaceState.fromTrustedJson(
        doc,
        workspaceId: key.workspaceId,
        receiptKeyId: key.receiptKeyId,
        ownerSid: key.ownerSid,
      ),
      confirm
          ? {
              server.id: HostTrustRecord.fromJson({
                'workspaceId': key.workspaceId,
                'profileId': server.id,
                'revision': p['trustRevision'],
                'connectionRevision': server.connectionRevision,
                'status': 'trusted',
                'key': {
                  'format': 'ssh-ed25519',
                  'fingerprint':
                      'SHA256:${base64.encode(List.filled(32, 0)).replaceAll('=', '')}',
                },
                'createdAt': clock().toIso8601String(),
                'updatedAt': clock().toIso8601String(),
              }),
            }
          : store.trustedOperational.foundation.trust,
    );
  }

  Future<String> capture() async {
    final db = Isar.getInstance('workspace')!,
        trust = await db.storedHostTrusts.where().findAll();
    trust.sort((a, b) => a.id.compareTo(b.id));
    return '${await raw.capture(db)}\n${jsonEncode([
      for (final r in trust) [r.id, r.entityId, r.payload],
    ])}';
  }

  String cached() => jsonEncode({
    for (final e in store.trustedOperational.rows.entries)
      e.key: [
        for (final r in e.value) [r.nativeId, r.entityId, r.payload],
      ],
  });
  try {
    await store.commitTrustedFoundation(foundation(g.id(70050), confirm: true));
    final kind = mode == 'writer-automation'
        ? 'basic'
        : mode.substring('writer-automation-'.length);
    if (kind.startsWith('overflow-')) {
      await store.close();
      final db = await Isar.open(
        trustedWorkspaceSchemas,
        directory: files.directory,
        name: 'workspace',
        maxSizeMiB: 64,
        relaxedDurability: false,
        inspector: false,
      );
      try {
        await db.writeTxn(() async {
          Future<void> move<T>(
            IsarCollection<T> collection,
            void Function(T) setId,
          ) async {
            final rows = await collection.where().limit(1).findAll();
            final oldId = switch (rows.single) {
              StoredMcpGrant r => r.id,
              StoredAutomationReceipt r => r.id,
              StoredAutomationProfile r => r.id,
              StoredAutomationRevision r => r.id,
              _ => throw StateError('INVALID_FIXTURE_GROUP'),
            };
            check(await collection.delete(oldId));
            setId(rows.single);
            await collection.put(rows.single);
          }

          switch (kind) {
            case 'overflow-grants':
              await move(db.storedMcpGrants, (r) => r.id = 9223372036854775807);
            case 'overflow-receipts':
              await move(
                db.storedAutomationReceipts,
                (r) => r.id = 9223372036854775807,
              );
            case 'overflow-profiles':
              await move(
                db.storedAutomationProfiles,
                (r) => r.id = 9223372036854775807,
              );
            case 'overflow-revisions':
              await move(
                db.storedAutomationRevisions,
                (r) => r.id = 9223372036854775807,
              );
          }
        });
      } finally {
        check(await db.close());
      }
      store = await open();
    }
    final baseline = store.trustedOperational, before = await capture();
    Future<void> retained({bool metadata = false}) async {
      final now = store.trustedOperational;
      for (final name in baseline.rows.keys) {
        if (const {
              'StoredMcpGrant',
              'StoredAutomationProfile',
              'StoredAutomationRevision',
              'StoredAutomationReceipt',
            }.contains(name) ||
            metadata && name == 'StoredReceipt') {
          for (final old in baseline.rows[name]!) {
            final actual = now.rows[name]!.singleWhere(
              (r) => r.entityId == old.entityId,
            );
            check(
              actual.nativeId == old.nativeId && actual.payload == old.payload,
            );
          }
          continue;
        }
        if (metadata &&
            const {
              'StoredWorkspace',
              'StoredProfile',
              'StoredReceipt',
            }.contains(name))
          continue;
        check(
          jsonEncode([
                for (final r in baseline.rows[name]!)
                  [r.nativeId, r.entityId, r.payload],
              ]) ==
              jsonEncode([
                for (final r in now.rows[name]!)
                  [r.nativeId, r.entityId, r.payload],
              ]),
        );
      }
      check(store.isTrustedSnapshotLoaded && !store.isAutomationReady);
      final native =
          jsonDecode(await raw.capture(Isar.getInstance('workspace')!)) as Map;
      for (final entry in native.entries) {
        final actual = entry.value as List, expected = now.rows[entry.key]!;
        check(actual.length == expected.length);
        for (var i = 0; i < actual.length; i++) {
          final row = actual[i] as Map;
          check(
            row['nativeId'] == expected[i].nativeId &&
                row['entityId'] == expected[i].entityId &&
                utf8.decode(base64.decode(row['payloadBase64'] as String)) ==
                    expected[i].payload,
          );
        }
      }
      final pins = await Isar.getInstance('workspace')!.storedHostTrusts
          .where()
          .findAll();
      pins.sort((a, b) => a.id.compareTo(b.id));
      check(
        jsonEncode([
              for (final r in pins) [r.id, r.entityId, r.payload],
            ]) ==
            jsonEncode([
              for (final r in now.rows['StoredHostTrust']!)
                [r.nativeId, r.entityId, r.payload],
            ]),
      );
    }

    if (kind.startsWith('overflow-')) {
      final cacheBefore = cached();
      await refusal(
        () => kind == 'overflow-grants' || kind == 'overflow-receipts'
            ? grant(command)
            : profile(createCatalogCommand(70002)),
        'RESOURCE_LIMIT',
      );
      check(await capture() == before && cached() == cacheBefore);
      await retained();
      await store.close();
      store = await open();
      check(await capture() == before);
      await retained();
      return;
    }
    if (kind.startsWith('fault-') || kind == 'listener' || kind == 'corrupt') {
      final boundary = kind.startsWith('fault-')
          ? GrantWriteBoundary.values.byName(kind.substring(6))
          : GrantWriteBoundary.afterCommit;
      if (kind == 'listener') {
        store.onMcpGrantPublished((id, revision) {
          check(
            id == gid &&
                revision == 1 &&
                store.hasPendingMcpAuthorityPublication,
          );
          throw StateError('OWNED_LISTENER_FAILURE');
        });
      } else {
        GrantWriteProbe.install((at) async {
          if (at != boundary) return;
          if (kind == 'corrupt') {
            final db = Isar.getInstance('workspace')!;
            await db.writeTxn(
              () => db.storedAutomationEvents.put(
                StoredAutomationEvent()
                  ..entityId = '${g.id(79999)}:1'
                  ..payload = '{}',
              ),
            );
          } else {
            throw StateError('OWNED_BOUNDARY_FAILURE');
          }
        });
      }
      await refusal(() => grant(command), 'STORAGE_BLOCKED');
      check(!store.isTrustedSnapshotLoaded);
      await store.close();
      if (kind == 'corrupt') {
        await refusal(open, 'STORAGE_BLOCKED');
        final db = await Isar.open(
          trustedWorkspaceSchemas,
          directory: files.directory,
          name: 'workspace',
          maxSizeMiB: 64,
          relaxedDurability: false,
          inspector: false,
        );
        try {
          await db.writeTxn(
            () =>
                db.storedAutomationEvents.deleteByEntityId('${g.id(79999)}:1'),
          );
        } finally {
          check(await db.close());
        }
      }
      store = await open();
      final committed =
          kind == 'listener' ||
          kind == 'corrupt' ||
          boundary.index >= GrantWriteBoundary.afterCommit.index;
      check(
        store.trustedOperational.automation.receipts.containsKey(
              command.requestId,
            ) ==
            committed,
      );
      if (committed) {
        check((await grant(command))['grantId'] == gid);
      } else {
        check(await capture() == before);
      }
      await retained();
      return;
    }
    if (kind == 'closing') {
      final entered = Completer<void>(), release = Completer<void>();
      GrantWriteProbe.install((at) async {
        if (at == GrantWriteBoundary.beforeStage) {
          entered.complete();
          await release.future;
        }
      });
      final work = grant(command);
      work.ignore();
      await entered.future;
      final closing = store.close();
      closing.ignore();
      try {
        await refusal(
          () => grant(
            OwnerGrantCommand.parse('grant.create', grantCreate(74000, 74001)),
          ),
          'NOT_READY',
        );
        await refusal(() => profile(createCatalogCommand(74002)), 'NOT_READY');
        await refusal(
          () async => store.currentTrustedMcpGrant(gid, at: clock()),
          'STORAGE_BLOCKED',
        );
      } finally {
        release.complete();
      }
      check((await work)['grantId'] == gid);
      await closing;
      store = await open();
      check((await grant(command))['grantId'] == gid);
      await retained();
      return;
    }
    if (kind == 'queue') {
      final entered = Completer<void>(), release = Completer<void>();
      var paused = false;
      GrantWriteProbe.install((at) async {
        if (at == GrantWriteBoundary.beforeStage && !paused) {
          paused = true;
          entered.complete();
          await release.future;
        }
      });
      final first = grant(command);
      first.ignore();
      await entered.future;
      final pending = <Future<Object?>>[first];
      try {
        check(identical(first, grant(command)));
        await refusal(
          () => grant(
            OwnerGrantCommand.parse('grant.create', {
              ...grantCreate(70000, 70001),
              'label': 'changed',
            }),
          ),
          'IDEMPOTENCY_CONFLICT',
        );
        await refusal(
          () => profile(
            createCatalogCommand(70000),
            origin: g.grantId,
            revision: 1,
          ),
          'FORBIDDEN',
        );
        final metadata = foundation(g.id(70051));
        pending.add(store.commitTrustedFoundation(metadata));
        for (var n = 0; n < 30; n++) {
          final work = n.isEven
              ? profile(createCatalogCommand(71000 + n))
              : grant(
                  OwnerGrantCommand.parse(
                    'grant.create',
                    grantCreate(72000 + n, 73000 + n),
                  ),
                );
          work.ignore();
          pending.add(work);
        }
        await refusal(
          () => grant(
            OwnerGrantCommand.parse('grant.create', grantCreate(74000, 74001)),
          ),
          'RESOURCE_LIMIT',
        );
        await refusal(
          () => store.commitTrustedFoundation(metadata),
          'RESOURCE_LIMIT',
        );
      } finally {
        release.complete();
      }
      await Future.wait(pending);
      await retained(metadata: true);
      check(
        store.state.storeRevision ==
            '${int.parse(baseline.foundation.foundation.storeRevision) + 1}',
      );
    } else if (kind.startsWith('capacity-')) {
      final db = Isar.getInstance('workspace')!, cacheBefore = cached();
      final ready = Completer<void>(), release = Completer<void>();
      final reader = db.txn(() async {
        check(await db.storedSettings.get(1) != null);
        ready.complete();
        await release.future;
      });
      await ready.future;
      try {
        final original = (await db.storedSettings.get(1))!.payload;
        final parsed = jsonDecode(original) as Map;
        final alternate = jsonEncode({
          ...parsed,
          'reduceMotion': !(parsed['reduceMotion'] as bool),
        });
        var full = false;
        for (var n = 0; n < 20000; n++) {
          try {
            await db.writeTxn(() async {
              await db.storedSettings.put(
                StoredSettings()..payload = alternate,
              );
              await db.storedSettings.put(StoredSettings()..payload = original);
            });
          } catch (error) {
            if (!isNativeCapacityFailure(error)) rethrow;
            full = true;
            break;
          }
        }
        check(full && await capture() == before);
        await refusal(
          () => kind.endsWith('grant')
              ? grant(command)
              : profile(createCatalogCommand(70002)),
          'RESOURCE_LIMIT',
        );
        check(
          store.isTrustedSnapshotLoaded &&
              cached() == cacheBefore &&
              await capture() == before,
        );
      } finally {
        release.complete();
        await reader;
      }
      await (kind.endsWith('grant')
          ? grant(command)
          : profile(createCatalogCommand(70002)));
      await retained();
    } else {
      final result = await grant(command);
      check(result['grantId'] == gid);
      check(jsonEncode(result) == jsonEncode(await grant(command)));
      if (kind == 'key-race') {
        protection.pause = true;
        final opening = store.openTrustedMcpGrantKey(gid, clock: clock);
        opening.ignore();
        await protection.entered.future;
        try {
          await grant(
            OwnerGrantCommand.parse('grant.replace', {
              ...grantCreate(70003, 70001),
              'expectedRevision': 1,
            }),
          );
        } finally {
          protection.release.complete();
        }
        await refusal(() => opening, 'UNAUTHORIZED');
        check(protection.cleartexts.every((b) => b.every((n) => n == 0)));
        await retained();
        return;
      }
      if (kind == 'keyloss') {
        protection.deny = true;
        await refusal(
          () async => store.currentTrustedMcpGrant(g.id(79998), at: clock()),
          'UNAUTHORIZED',
        );
        check(store.isTrustedSnapshotLoaded);
        await refusal(
          () => store.openTrustedMcpGrantKey(gid, clock: clock),
          'STORAGE_BLOCKED',
        );
        check(!store.isTrustedSnapshotLoaded);
        protection.deny = false;
        await store.close();
        store = await open();
        await retained();
        return;
      }
      await refusal(
        () => store.mutateOwnerGrant(command, clock: clock),
        'STORAGE_BLOCKED',
      );
      await refusal(
        () => store.mutateAutomationProfile(
          createCatalogCommand(70002),
          originGrantId: null,
          expectedGrantRevision: null,
          clock: clock,
        ),
        'STORAGE_BLOCKED',
      );
      await refusal(
        () async => store.currentMcpGrant(gid, at: clock()),
        'STORAGE_BLOCKED',
      );
      await retained();
      final loaded = await files.readForBridge(gid),
          serverKey = await store.openTrustedMcpGrantKey(gid, clock: clock);
      try {
        check(
          await loaded.key.verify([
            1,
            2,
            3,
          ], await serverKey.key.mac([1, 2, 3])),
        );
      } finally {
        serverKey.close();
      }
      var revision = 1;
      for (var n = 0; n < 2; n++) {
        await grant(
          OwnerGrantCommand.parse('grant.replace', {
            ...grantCreate(70003 + n, 70001),
            'expectedRevision': revision,
          }),
        );
        revision++;
        final current = store.currentTrustedMcpGrant(gid, at: clock());
        check(
          current.revision == revision &&
              current.secretRef != loaded.binding.secretRef,
        );
        final private = await store.openTrustedMcpGrantKey(gid, clock: clock);
        try {
          check(
            !await private.key.verify([
              1,
              2,
              3,
            ], await loaded.key.mac([1, 2, 3])),
          );
        } finally {
          private.close();
        }
      }
      loaded.key.close();
      final create = createCatalogCommand(70002),
          ack = await profile(create),
          pid = ack['profileId'] as String;
      check(jsonEncode(await profile(create)) == jsonEncode(ack));
      final oldRevision = store
          .trustedOperational
          .rows['StoredAutomationRevision']!
          .singleWhere((r) => r.entityId == '$pid:1');
      final update = AutomationProfileCommand.parse('profile.update', {
        'requestId': g.id(70010),
        'profileId': pid,
        'expectedRevision': 1,
        'body': catalogBody(),
      });
      await refusal(
        () => profile(update, origin: gid, revision: 1),
        'FORBIDDEN',
      );
      await profile(update, origin: gid, revision: revision);
      await refusal(() => profile(update), 'FORBIDDEN');
      check(
        store.trustedOperational.rows['StoredAutomationRevision']!
                .singleWhere((r) => r.entityId == '$pid:1')
                .payload ==
            oldRevision.payload,
      );
      await profile(
        AutomationProfileCommand.parse('profile.archive', {
          'requestId': g.id(70011),
          'profileId': pid,
          'expectedRevision': 2,
        }),
      );
      await grant(
        OwnerGrantCommand.parse('grant.revoke', {
          'requestId': g.id(70012),
          'grantId': gid,
          'expectedRevision': revision,
        }),
      );
      await refusal(
        () async => store.currentTrustedMcpGrant(gid, at: clock()),
        'UNAUTHORIZED',
      );
      await refusal(() => files.readForBridge(gid), 'FORBIDDEN');
      await retained();
    }
    final durable = await capture(), snapshot = cached();
    await store.close();
    store = await open();
    check(await capture() == durable && cached() == snapshot);
    await retained(metadata: kind == 'queue');
  } finally {
    if (!protection.release.isCompleted) protection.release.complete();
    await store.close();
  }
}
