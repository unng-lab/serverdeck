import 'package:isar_community/isar.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/models.dart';
import 'package:serverdeck_locald/storage/records.dart';
import 'package:serverdeck_locald/storage/state_store.dart';

import '../models_test.dart' as fixture;

/// Repository snapshots, not application CRUD or CAS: the future coordinator
/// must produce these states from requests. Exercise real custody and persisted
/// rows independently so a RAM-only roundtrip cannot hide orphaned native rows.
Future<void> verifyCredentialSnapshots(
  Future<StateStore> Function() open,
  KeyCustody custody,
) async {
  StateStore? store = await open();
  final codec = StrictCodec();
  void check(bool value) {
    if (!value) throw StateError('CREDENTIAL_SNAPSHOT_ASSERTION');
  }

  bool equal(Object? left, Object? right) =>
      codec.canonical(left).join(',') == codec.canonical(right).join(',');

  Future<void> persist(
    Map<String, Object?> value,
    String operation,
    String entityRevision, {
    bool deleted = false,
  }) async {
    final revision = nextRevision(store!.state.storeRevision);
    final request =
        '42345678-1234-4234-8234-${int.parse(revision).toRadixString(16).padLeft(12, '0')}';
    value['storeRevision'] = revision;
    (value['receipts'] as Map)[request] = {
      ...fixture.receipt(),
      'requestId': request,
      'operation': operation,
      'profileId': operation == 'settings.update' ? null : fixture.profileId,
      'result': {
        'entityId': operation == 'settings.update' ? null : fixture.profileId,
        'entityRevision': entityRevision,
        'storeRevision': revision,
        'deleted': deleted,
      },
    };
    final next = WorkspaceState.fromJson(
      value,
      workspaceId: fixture.workspace,
      receiptKeyId: fixture.receiptKeyId,
      ownerSid: custody.ownerSid,
    );
    await store!.commit(next);
    check(equal(store!.state.toJson(), next.toJson()));
    await store!.close();
    store = null;
    store = await open();
    check(equal(store!.state.toJson(), next.toJson()));
    final native = Isar.getInstance('workspace')!;
    final credentials = await native.storedCredentials.where().findAll();
    final profiles = await native.storedProfiles.where().findAll();
    check(credentials.length == next.credentials.length);
    check(profiles.length == next.profiles.length);
    check(
      equal(
        credentials.map((row) => row.entityId).toList()..sort(),
        next.credentials.keys.toList()..sort(),
      ),
    );
    check((await native.storedReceipts.count()) == int.parse(revision));
    for (final credential in store!.state.credentials.values) {
      final secret = await custody.openCredential(
        credential.protectedBlob,
        fixture.workspace,
        fixture.profileId,
        credential.id,
      );
      check(secret['kind'] == credential.kind.name);
    }
  }

  Map<String, Object?> snapshot() => store!.state.toJson();
  Map<String, Object?> profile() =>
      store!.state.profiles[fixture.profileId]!.toJson();

  Future<void> replace(String id, Map<String, Object?> action) async {
    final current = profile();
    final credentialRevision = nextRevision(
      current['credentialRevision'] as String,
    );
    final entityRevision = nextRevision(current['revision'] as String);
    final blob = await custody.wrapCredential(
      fixture.workspace,
      fixture.profileId,
      id,
      action,
    );
    final value = snapshot();
    (value['profiles'] as Map)[fixture.profileId] = {
      ...current,
      'revision': entityRevision,
      'credentialRevision': credentialRevision,
      'credentialRef': id,
    };
    value['credentials'] = {
      id: {
        'id': id,
        'revision': credentialRevision,
        'profileId': fixture.profileId,
        'kind': action['kind'],
        'protectedBlob': blob,
        'createdAt': fixture.time,
        'updatedAt': fixture.time,
      },
    };
    await persist(value, 'profiles.update', entityRevision);
    final reopened = store!.state.credentials[id]!;
    check(reopened.revision == credentialRevision);
    final secret = await custody.openCredential(
      reopened.protectedBlob,
      fixture.workspace,
      fixture.profileId,
      id,
    );
    for (final field in ['password', 'privateKey', 'passphrase']) {
      if (action.containsKey(field)) check(secret[field] == action[field]);
    }
  }

  try {
    final created = snapshot();
    (created['profiles'] as Map)[fixture.profileId] = fixture.profile();
    await persist(created, 'profiles.create', '1');
    check(profile()['credentialRevision'] == '1');
    check(profile()['credentialRef'] == null);

    const first = '52345678-1234-4234-8234-000000000001';
    const second = '52345678-1234-4234-8234-000000000002';
    const third = '52345678-1234-4234-8234-000000000003';
    await replace(first, {
      'action': 'replace',
      'kind': 'password',
      'password': ' synthetic-e\u0301-password ',
    });
    check(profile()['credentialRevision'] == '2');
    final removed = snapshot();
    (removed['profiles'] as Map)[fixture.profileId] = {
      ...profile(),
      'revision': '3',
      'credentialRevision': '3',
      'credentialRef': null,
    };
    removed['credentials'] = <String, Object?>{};
    await persist(removed, 'profiles.update', '3');
    check(store!.state.credentials.isEmpty);
    await replace(second, {
      'action': 'replace',
      'kind': 'privateKey',
      'privateKey': '-----BEGIN PRIVATE KEY-----\r\nQUFB\r\n-----END PRIVATE KEY-----\r\n',
      'passphrase': ' synthetic-e\u0301-passphrase ',
    });
    check(profile()['credentialRevision'] == '4');
    check(profile()['credentialRef'] != first);

    // Replacing a nonempty credential must remove the prior native row too.
    await replace(third, {
      'action': 'replace',
      'kind': 'password',
      'password': 'synthetic-third',
    });
    check(!store!.state.credentials.containsKey(second));
    final retained = store!.state.credentials[third]!.toJson();
    final kept = snapshot();
    (kept['profiles'] as Map)[fixture.profileId] = {
      ...profile(),
      'revision': '6',
      'name': 'Renamed synthetic',
      'tags': ['kept'],
    };
    await persist(kept, 'profiles.update', '6');
    check(equal(store!.state.credentials[third]!.toJson(), retained));
    check(profile()['credentialRevision'] == '5');
    check(profile()['connectionRevision'] == '1');
    check(profile()['trustRevision'] == '1');
    final selected = snapshot();
    selected['settings'] = {
      ...store!.state.settings.toJson(),
      'revision': '2',
      'selectedProfileId': fixture.profileId,
    };
    await persist(selected, 'settings.update', '2');
    final deleted = snapshot();
    deleted['profiles'] = <String, Object?>{};
    deleted['credentials'] = <String, Object?>{};
    deleted['settings'] = {
      ...store!.state.settings.toJson(),
      'revision': '3',
      'selectedProfileId': null,
    };
    await persist(deleted, 'profiles.delete', '6', deleted: true);
    check(store!.state.profiles.isEmpty && store!.state.credentials.isEmpty);
    check(store!.state.settings.revision == '3');
    check(store!.state.settings.toJson()['selectedProfileId'] == null);
    check(store!.state.receipts.length == 8);
  } finally {
    await store?.close();
  }
}
