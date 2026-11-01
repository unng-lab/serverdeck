import 'dart:convert';

import 'package:serverdeck_engine/credentials/provider.dart';
import 'package:serverdeck_engine/platform/ports.dart';
import 'package:serverdeck_engine/profiles/host_trust.dart';
import 'package:serverdeck_engine/profiles/service.dart';
import 'package:serverdeck_engine/profiles/validation.dart';
import 'package:serverdeck_engine/storage/credential_validation.dart';
import 'package:serverdeck_engine/storage/host_trust_models.dart';
import 'package:serverdeck_engine/storage/key_custody.dart';
import 'package:serverdeck_engine/storage/models.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:test/test.dart';

const workspace = '12345678-1234-4234-9234-12345678aa01';
const keyId = '12345678-1234-4234-9234-12345678aa02';
const profile = '12345678-1234-4234-9234-12345678aa03';
const credential = '12345678-1234-4234-9234-12345678aa04';
const other = '12345678-1234-4234-9234-12345678aa05';
const owner = 'S-1-5-21-1-2-3-1001';
String time(int step) =>
    DateTime.utc(2026, 10, 30).add(Duration(seconds: step)).toIso8601String();
Matcher failure([String code = 'STORAGE_BLOCKED']) => throwsA(
  isA<StateError>().having((error) => error.message, 'safe code', code),
);

/// RAM-only tokens with entropy checks; no encryption or OS-vault claim.
final class MemoryProtection implements UserProtection {
  final records = <int, ({List<int> clear, String entropy})>{};
  final borrowed = <List<int>>[];
  bool unavailable = false;
  String? lastEntropy;
  @override
  Future<List<int>> protect(List<int> cleartext, List<int> entropy) async {
    borrowed.add(cleartext);
    lastEntropy = utf8.decode(entropy);
    if (unavailable) throw StateError('private-vault-diagnostic');
    final id = records.length + 1;
    records[id] = (clear: List.of(cleartext), entropy: lastEntropy!);
    return [id];
  }

  @override
  Future<List<int>> unprotect(List<int> ciphertext, List<int> entropy) async {
    final record = ciphertext.length == 1 ? records[ciphertext.single] : null;
    if (unavailable ||
        record == null ||
        record.entropy != utf8.decode(entropy)) {
      throw StateError('private-vault-diagnostic');
    }
    final clear = List<int>.of(record.clear);
    borrowed.add(clear);
    return clear;
  }

  void dispose() {
    for (final record in records.values) {
      record.clear.fillRange(0, record.clear.length, 0);
    }
    records.clear();
  }
}

HostTrustState initial() => HostTrustState.fromRecords(
  WorkspaceState.empty(
    workspaceId: workspace,
    receiptKeyId: keyId,
    ownerSid: owner,
  ),
  {},
);
ProfileService service(MemoryProtection vault) =>
    ProfileService(CredentialProvider(KeyCustody(vault, owner)));
Map<String, Object?> fields(
  HostTrustState state, {
  Map<String, Object?>? action,
  String? address,
  String? name,
}) {
  final old = state.foundation.profiles[profile];
  return {
    'profileId': profile,
    if (old != null) 'expectedRevision': old.revision,
    'name': name ?? old?.name ?? 'unit host',
    'address': address ?? old?.toJson()['address'] ?? 'unit.invalid',
    'port': 22,
    'sshUser': 'unit_user',
    'tags': <String>[],
    'credential':
        action ?? <String, Object?>{'action': old == null ? 'remove' : 'keep'},
  };
}

/// Supplies the coordinator-owned receipt only as setup for the next pure unit
/// preparation. This does not exercise a transaction, authorization or storage.
HostTrustState asNextSnapshot(
  PreparedMutation prepared,
  String operation,
  int step,
) {
  final request =
      '12345678-1234-4234-9234-${step.toRadixString(16).padLeft(12, '0')}';
  (prepared.value['receipts'] as Map)[request] = {
    'requestId': request,
    'inputDigest': base64.encode(List.filled(32, 0)),
    'operation': operation,
    'profileId': prepared.result.entityId,
    'result': prepared.result.toJson(),
    'committedAt': time(step),
  };
  return HostTrustState.fromRecords(
    WorkspaceState.fromJson(
      prepared.value,
      workspaceId: workspace,
      receiptKeyId: keyId,
      ownerSid: owner,
    ),
    prepared.trust,
  );
}

Future<HostTrustState> prepare(
  ProfileService profiles,
  HostTrustState state,
  ApiMethod method,
  Map<String, Object?> params,
  int step,
) async => asNextSnapshot(
  await profiles.prepare(
    state,
    method,
    validateMutationInput(method, params),
    time(step),
  ),
  method.wireName,
  step,
);

void main() {
  test(
    'receipt custody preserves entropy, canonical HMAC and reopened material',
    () async {
      final vault = MemoryProtection();
      addTearDown(vault.dispose);
      final custody = KeyCustody(vault, owner);
      final issued = await custody.createReceiptKey(workspace, keyId);
      final independent = await custody.createReceiptKey(workspace, keyId);
      final reopened = await custody.openReceiptKey(
        issued.wrapper,
        workspace,
        keyId,
      );
      try {
        expect(
          vault.lastEntropy,
          'ServerDeckNext\nv1\ndefault\n$owner\nreceipt',
        );
        final proof = await custody.receiptDigest(issued, {'z': 1, 'a': true});
        expect(custody.receiptDigestSync(reopened, {'a': true, 'z': 1}), proof);
        expect(
          await custody.receiptDigest(independent, {'z': 1, 'a': true}),
          isNot(proof),
        );
        expect(
          await custody.receiptDigest(reopened, {'z': 2, 'a': true}),
          isNot(proof),
        );
        expect(vault.borrowed, everyElement(everyElement(0)));
        expect(() => issued.wrapper[0] = 99, throwsUnsupportedError);
        reopened.close();
        await expectLater(custody.receiptDigest(reopened, {}), failure());
        expect(() => custody.receiptDigestSync(reopened, {}), failure());
      } finally {
        issued.close();
        independent.close();
        reopened.close();
      }
    },
  );

  test('credential wrappers retain exact workspace/profile/ID entropy without reset', () async {
    final vault = MemoryProtection();
    addTearDown(vault.dispose);
    final custody = KeyCustody(vault, owner);
    final blob = await custody.wrapCredential(workspace, profile, credential, {
      'action': 'replace',
      'kind': 'password',
      'password': 'unit-only-password',
    });
    expect(
      vault.lastEntropy,
      'ServerDeckNext\nv1\n$workspace\n$profile\n$credential\ncredential',
    );
    expect(await custody.openCredential(blob, workspace, profile, credential), {
      'kind': 'password',
      'password': 'unit-only-password',
    });
    await expectLater(
      custody.openCredential(blob, workspace, other, credential),
      failure(),
    );
    await expectLater(
      custody.openCredential(blob, other, profile, credential),
      failure(),
    );
    await expectLater(
      custody.openCredential(blob, workspace, profile, other),
      failure(),
    );
    expect(vault.records, hasLength(1));
    expect(vault.borrowed, everyElement(everyElement(0)));
  });

  test(
    'the sole manifest helper emits and verifies only target schema3',
    () async {
      final vault = MemoryProtection();
      addTearDown(vault.dispose);
      final custody = KeyCustody(vault, owner);
      final material = await custody.createReceiptKey(workspace, keyId);
      addTearDown(material.close);
      final manifest = await custody.createWorkspaceManifest(material);
      expect(manifest, {
        'product': 'serverdeck-next',
        'format': 3,
        'schema': 3,
        'workspaceId': workspace,
        'receiptKeyId': keyId,
        'ownerSid': owner,
      });
      await custody.verifyWorkspaceManifest(manifest, material);
      await expectLater(
        custody.verifyWorkspaceManifest({...manifest, 'schema': 1}, material),
        failure('INCOMPATIBLE'),
      );
      await expectLater(
        custody.verifyWorkspaceManifest({...manifest, 'schema': 2}, material),
        failure('INCOMPATIBLE'),
      );
      await expectLater(
        custody.verifyWorkspaceManifest({
          ...manifest,
          'workspaceId': other,
        }, material),
        failure(),
      );
      await expectLater(
        custody.openReceiptKey(material.wrapper, workspace, other),
        failure(),
      );
      material.close();
      await expectLater(custody.createWorkspaceManifest(material), failure());
    },
  );

  test(
    'credential keep replace and remove preserve immutable previous snapshots',
    () async {
      final vault = MemoryProtection();
      addTearDown(vault.dispose);
      final profiles = service(vault), empty = initial();
      final created = await prepare(
        profiles,
        empty,
        ApiMethod.profilesCreate,
        fields(
          empty,
          action: {
            'action': 'replace',
            'kind': 'password',
            'password': 'first-unit-password',
          },
        ),
        1,
      );
      final original = created.foundation.profiles[profile]!.credentialRef!;
      await validateWorkspaceCredentials(
        created.foundation,
        KeyCustody(vault, owner),
      );
      // The OS vault owns the user boundary; the workspace gate checks SID
      // metadata without changing the persisted credential entropy or blob.
      await expectLater(
        validateWorkspaceCredentials(
          created.foundation,
          KeyCustody(vault, 'S-1-5-21-9-9-9-1001'),
        ),
        failure(),
      );
      final kept = await prepare(
        profiles,
        created,
        ApiMethod.profilesUpdate,
        fields(created, name: 'renamed'),
        2,
      );
      expect(kept.foundation.profiles[profile]!.credentialRef, original);
      expect(kept.foundation.profiles[profile]!.credentialRevision, '1');
      final replaced = await prepare(
        profiles,
        kept,
        ApiMethod.profilesUpdate,
        fields(
          kept,
          action: {
            'action': 'replace',
            'kind': 'password',
            'password': 'second-unit-password',
          },
        ),
        3,
      );
      expect(
        replaced.foundation.profiles[profile]!.credentialRef,
        isNot(original),
      );
      expect(replaced.foundation.credentials.containsKey(original), isFalse);
      expect(replaced.foundation.profiles[profile]!.credentialRevision, '2');
      expect(created.foundation.credentials.containsKey(original), isTrue);
      final removed = await prepare(
        profiles,
        replaced,
        ApiMethod.profilesUpdate,
        fields(replaced, action: {'action': 'remove'}),
        4,
      );
      expect(removed.foundation.credentials, isEmpty);
      expect(removed.foundation.profiles[profile]!.credentialRevision, '3');
      expect(empty.foundation.isInitialEmpty, isTrue);
    },
  );

  test('host trust survives cosmetic changes and is revoked by connection changes', () async {
    final vault = MemoryProtection();
    addTearDown(vault.dispose);
    final profiles = service(vault), empty = initial();
    final created = await prepare(
      profiles,
      empty,
      ApiMethod.profilesCreate,
      fields(empty),
      1,
    );
    final confirmed = asNextSnapshot(
      prepareHostTrustMutation(created, 'servers.trust.confirm', {
        'profileId': profile,
        'expectedRevision': '1',
        'challengeId': other,
        'key': {
          'format': 'ssh-ed25519',
          'fingerprint':
              'SHA256:${base64.encode(List.filled(32, 1)).replaceAll('=', '')}',
        },
      }, time(2)),
      'servers.trust.confirm',
      2,
    );
    expect(confirmed.trust[profile]!.status, HostTrustStatus.trusted);
    final renamed = await prepare(
      profiles,
      confirmed,
      ApiMethod.profilesUpdate,
      fields(confirmed, name: 'cosmetic'),
      3,
    );
    expect(renamed.trust[profile]!.revision, '2');
    expect(renamed.foundation.profiles[profile]!.connectionRevision, '1');
    final changed = await prepare(
      profiles,
      renamed,
      ApiMethod.profilesUpdate,
      fields(renamed, address: 'changed.invalid'),
      4,
    );
    expect(changed.trust[profile]!.status, HostTrustStatus.revoked);
    expect(changed.trust[profile]!.connectionRevision, '1');
    expect(changed.foundation.profiles[profile]!.connectionRevision, '2');
    expect(changed.foundation.profiles[profile]!.trustRevision, '3');
    await expectLater(
      profiles.prepare(
        changed,
        ApiMethod.profilesUpdate,
        validateMutationInput(ApiMethod.profilesUpdate, {
          ...fields(changed),
          'expectedRevision': '1',
        }),
        time(5),
      ),
      failure('REVISION_CONFLICT'),
    );
  });

  test('settings CAS and delete clear selection, credentials and trust together', () async {
    final vault = MemoryProtection();
    addTearDown(vault.dispose);
    final profiles = service(vault), empty = initial();
    final created = await prepare(
      profiles,
      empty,
      ApiMethod.profilesCreate,
      fields(
        empty,
        action: {
          'action': 'replace',
          'kind': 'password',
          'password': 'unit-only-password',
        },
      ),
      1,
    );
    final confirmed = asNextSnapshot(
      prepareHostTrustMutation(created, 'servers.trust.confirm', {
        'profileId': profile,
        'expectedRevision': '1',
        'challengeId': other,
        'key': {
          'format': 'ssh-ed25519',
          'fingerprint':
              'SHA256:${base64.encode(List.filled(32, 1)).replaceAll('=', '')}',
        },
      }, time(2)),
      'servers.trust.confirm',
      2,
    );
    final selected = await prepare(
      profiles,
      confirmed,
      ApiMethod.settingsUpdate,
      {
        'expectedRevision': '1',
        'theme': 'dark',
        'reduceMotion': true,
        'selectedProfileId': profile,
      },
      3,
    );
    await expectLater(
      profiles.prepare(selected, ApiMethod.settingsUpdate, {
        'expectedRevision': '1',
      }, time(4)),
      failure('REVISION_CONFLICT'),
    );
    final deleted = await prepare(
      profiles,
      selected,
      ApiMethod.profilesDelete,
      {'profileId': profile, 'expectedRevision': '2'},
      4,
    );
    expect(deleted.foundation.profiles, isEmpty);
    expect(deleted.foundation.credentials, isEmpty);
    expect(deleted.trust, isEmpty);
    expect(deleted.foundation.settings.selectedProfileId, isNull);
    expect(deleted.foundation.settings.revision, '3');
    expect(selected.foundation.settings.selectedProfileId, profile);
    expect(
      () => profiles.get(deleted.foundation, profile),
      failure('NOT_FOUND'),
    );
  });

  test(
    'unavailable vault fails safely without publishing a new profile or key',
    () async {
      final vault = MemoryProtection()..unavailable = true;
      addTearDown(vault.dispose);
      final custody = KeyCustody(vault, owner), empty = initial();
      await expectLater(custody.createReceiptKey(workspace, keyId), failure());
      await expectLater(
        service(vault).prepare(
          empty,
          ApiMethod.profilesCreate,
          validateMutationInput(
            ApiMethod.profilesCreate,
            fields(
              empty,
              action: {
                'action': 'replace',
                'kind': 'password',
                'password': 'unit-only-password',
              },
            ),
          ),
          time(1),
        ),
        failure(),
      );
      expect(vault.records, isEmpty);
      expect(vault.borrowed, everyElement(everyElement(0)));
      expect(empty.foundation.isInitialEmpty, isTrue);
    },
  );
}
