import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/app_operations.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/domain/receipt_book.dart';

import '../fixtures/domain_repository.dart';
import '../fixtures/profile_harness.dart';

void main() {
  late ProfileHarness h;
  setUp(() {
    h = ProfileHarness();
  });
  tearDown(() => h.dispose());

  test(
    'receipt lookup inside close admission closes the last pre-admission race',
    () async {
      final id = (await h.create(actor: h.mcp)).value!.entityId;
      final entered = Completer<void>(), release = Completer<void>();
      var admissions = 0;
      h.connections.beforeCloseAdmission = () {
        admissions++;
        if (admissions == 1) {
          entered.complete();
          return release.future;
        }
        return Future.value();
      };
      final delayed = h.owner.updateProfile(
        h.mcp,
        id,
        const ProfilePatch(username: 'other'),
        expectedRevision: 1,
        mutationId: 'same-update',
      );
      await entered.future;
      expect(
        (await h.owner.updateProfile(
          h.mcp,
          id,
          const ProfilePatch(username: 'other'),
          expectedRevision: 1,
          mutationId: 'same-update',
        )).ok,
        isTrue,
      );
      release.complete();
      final replay = await delayed;
      expect(replay.value!.replayed, isTrue);
      expect(replay.value!.revision, 2);
      expect(h.connections.closeCalls, 1);
      expect(h.repository.state.profiles[id]!.username, 'other');
    },
  );

  for (final afterDelete in [false, true]) {
    test(
      'delayed duplicate secret update replays before close, deleted=$afterDelete',
      () async {
        final id = (await h.create(actor: h.mcp)).value!.entityId;
        final entered = Completer<void>(), release = Completer<void>();
        var preparations = 0;
        h.protector.beforeReturn = () {
          preparations++;
          if (preparations == 1) {
            entered.complete();
            return release.future;
          }
          return Future.value();
        };
        final delayed = h.owner.updateProfile(
          h.mcp,
          id,
          ProfilePatch(authentication: PasswordInput('replacement')),
          expectedRevision: 1,
          mutationId: 'same-update',
        );
        await entered.future;
        final first = await h.owner.updateProfile(
          h.mcp,
          id,
          ProfilePatch(authentication: PasswordInput('replacement')),
          expectedRevision: 1,
          mutationId: 'same-update',
        );
        expect(first.value!.revision, 2);
        if (afterDelete) {
          expect(
            (await h.owner.deleteProfile(
              h.actors.ui,
              id,
              expectedRevision: 2,
              confirmed: true,
            )).ok,
            isTrue,
          );
        }
        final closes = h.connections.closeCalls;
        release.complete();
        final replay = await delayed;
        expect(replay.ok, isTrue);
        expect(replay.value!.replayed, isTrue);
        expect(replay.value!.entityId, id);
        expect(replay.value!.revision, 2);
        expect(h.connections.closeCalls, closes);
        expect(h.repository.state.receipts.length, 2);
        expect(h.repository.state.profiles.length, afterDelete ? 0 : 1);
        if (!afterDelete)
          expect(h.repository.state.profiles[id]!.profileRevision, 2);
      },
    );
  }

  test(
    'late duplicate protection failure resolves the already committed update',
    () async {
      final id = (await h.create(actor: h.mcp)).value!.entityId;
      final entered = Completer<void>(), release = Completer<void>();
      var preparations = 0;
      h.protector.beforeReturn = () {
        preparations++;
        if (preparations == 1) {
          entered.complete();
          return release.future;
        }
        return Future.value();
      };
      final delayed = h.owner.updateProfile(
        h.mcp,
        id,
        ProfilePatch(authentication: PasswordInput('replacement')),
        expectedRevision: 1,
        mutationId: 'same-update',
      );
      await entered.future;
      expect(
        (await h.owner.updateProfile(
          h.mcp,
          id,
          ProfilePatch(authentication: PasswordInput('replacement')),
          expectedRevision: 1,
          mutationId: 'same-update',
        )).ok,
        isTrue,
      );
      h.protector.fail = true;
      release.complete();
      final replay = await delayed;
      expect(replay.value!.replayed, isTrue);
      expect(replay.value!.revision, 2);
      expect(h.connections.closeCalls, 1);
      expect(h.repository.state.profiles[id]!.profileRevision, 2);
    },
  );

  test('same client mutation ID conflicts across methods while other client is separate', () async {
    final id = (await h.create(actor: h.mcp)).value!.entityId;
    final update = await h.owner.updateProfile(
      h.mcp,
      id,
      const ProfilePatch(displayName: 'new'),
      expectedRevision: 1,
      mutationId: 'create-1',
    );
    expect(update.error!.code, FailureCode.conflict);
    expect(h.repository.state.profiles[id]!.profileRevision, 1);
    final other = h.actors.mcp(clientId: fixtureId(3), grantVersion: 1);
    expect((await h.create(actor: other)).ok, isTrue);
    expect(h.repository.state.profiles.length, 2);
    expect(h.repository.state.receipts.length, 2);
  });

  test('current rotated grant can replay old committed receipt but stale grant cannot', () async {
    final id = (await h.create(actor: h.mcp)).value!.entityId;
    h.state.canonicalGrantVersion = 2;
    expect(
      (await h.create(actor: h.mcp)).error!.code,
      FailureCode.accessRevoked,
    );
    final rotated = h.actors.mcp(clientId: fixtureId(2), grantVersion: 2);
    final replay = await h.create(actor: rotated);
    expect(replay.value!.entityId, id);
    expect(replay.value!.replayed, isTrue);
    expect(h.protector.calls, 1);
  });

  test('new owner reads saved snapshot, starts disconnected and preserves MCP receipts', () async {
    final id = (await h.create(actor: h.mcp)).value!.entityId;
    final next = ProfileHarness(epoch: fixtureId(3));
    try {
      next.repository.state = h.repository.state.clone();
      final detail = await next.owner.getProfile(next.actors.ui, id);
      expect(detail.ok, isTrue);
      expect(detail.value!.profile.hasCredential, isTrue);
      expect(detail.value!.connection.state, ConnectionState.disconnected);
      expect(
        (await next.owner.getProfile(h.actors.ui, id)).error!.code,
        FailureCode.authRequired,
      );
      final replay = await next.create(actor: next.mcp);
      expect(replay.value!.entityId, id);
      expect(replay.value!.replayed, isTrue);
      expect(next.protector.calls, 0);
    } finally {
      await next.dispose();
    }
  });

  test('name length is checked after trimming while receipt keeps original spelling', () async {
    final result = await h.owner.createProfile(
      h.mcp,
      h.draft(name: '  ${'n' * 100}  '),
      mutationId: 'long',
    );
    expect(result.ok, isTrue);
    expect(h.repository.state.profiles.values.single.displayName, 'n' * 100);
  });

  test('create atomically stores protected credential, endpoint and safe projections', () async {
    final draft = h.draft();
    final result = await h.owner.createProfile(
      h.actors.ui,
      draft,
      mutationId: 'create',
    );
    expect(result.ok, isTrue);
    final id = result.value!.entityId;
    final stored = h.repository.state.profiles[id]!;
    expect(stored.displayName, 'Server');
    expect(stored.originalHost, 'EXAMPLE.test.');
    expect(stored.normalizedHost, 'example.test');
    expect(stored.port, 22);
    expect(stored.username, 'Root');
    expect(h.repository.state.endpoints[stored.endpointId]!.profileRefCount, 1);
    expect(
      h.repository.state.credentials[stored.credentialId]!.protectedBytes.first,
      0xde,
    );
    expect(h.protector.purposes.single, 'credential.v1:${stored.credentialId}');
    expect(h.protector.retainedInput!.every((b) => b == 0), isTrue);
    expect(
      () => (draft.authentication as PasswordInput).password,
      throwsStateError,
    );
    expect(h.repository.state.receipts.length, 1);
    expect(h.repository.state.settings.dataRevision, 2);
    final view = await h.owner.getProfile(h.actors.ui, id);
    final json = jsonEncode(view.toJson());
    expect(json, isNot(contains('SYNTHETIC')));
    expect(json, isNot(contains('protectedBytes')));
    expect(view.value!.profile.hasCredential, isTrue);
  });

  test(
    'key import protects original encrypted file and stores only key metadata',
    () async {
      final original = File('test/fixtures/ssh/ed25519-encrypted.txt')
          .readAsBytesSync();
      final input = PrivateKeyInput(
        original,
        passphrase: 'serverdeck-unit-passphrase',
      );
      final result = await h.owner.createProfile(
        h.actors.ui,
        ProfileDraft(
          displayName: 'key',
          host: 'key.test',
          username: 'user',
          authentication: input,
        ),
        mutationId: 'key',
      );
      expect(result.ok, isTrue);
      final credential = h.repository.state.credentials.values.single;
      expect(credential.kind, 'privateKey');
      expect(credential.publicKeyType, 'ssh-ed25519');
      expect(credential.publicKeyBits, 256);
      expect(
        credential.protectedBytes.skip(1).map((b) => b ^ 0xaa).toList(),
        original,
      );
      expect(h.inspector.calls, 1);
      expect(() => input.bytes, throwsStateError);
    },
  );

  test(
    'MCP create replay has one effect, and changed exact payload conflicts',
    () async {
      final first = await h.create(actor: h.mcp);
      final replay = await h.create(actor: h.mcp);
      expect(replay.value!.replayed, isTrue);
      expect(replay.value!.entityId, first.value!.entityId);
      expect(h.repository.state.profiles.length, 1);
      expect(h.protector.calls, 1);
      final conflict = await h.owner.createProfile(
        h.mcp,
        h.draft(name: 'Server'),
        mutationId: 'create-1',
      );
      expect(conflict.error!.code, FailureCode.conflict);
      expect(h.repository.state.profiles.length, 1);
      final portPresence = await h.owner.createProfile(
        h.mcp,
        h.draft(port: 22),
        mutationId: 'create-1',
      );
      expect(portPresence.error!.code, FailureCode.conflict);
      final password = await h.owner.createProfile(
        h.mcp,
        h.draft(password: 'SYNTHETIC'),
        mutationId: 'create-1',
      );
      expect(password.error!.code, FailureCode.conflict);
    },
  );

  test('UI namespace is separate and MCP cannot invoke UI delete', () async {
    await h.create();
    await h.create(actor: h.mcp);
    expect(h.repository.state.profiles.length, 2);
    expect(h.repository.state.receipts.length, 2);
    expect(h.repository.state.endpoints.values.single.profileRefCount, 2);
    dynamic owner = h.owner;
    expect(
      () => owner.deleteProfile(
        h.mcp,
        h.repository.state.profiles.keys.first,
        expectedRevision: 1,
        confirmed: true,
      ),
      throwsA(isA<TypeError>()),
    );
    expect(h.repository.state.profiles.length, 2);
  });

  test('replay after UI deletion returns committed IDs without resurrection or close', () async {
    final created = await h.create(actor: h.mcp);
    final id = created.value!.entityId;
    expect(
      (await h.owner.deleteProfile(
        h.actors.ui,
        id,
        expectedRevision: 1,
        confirmed: true,
      )).ok,
      isTrue,
    );
    final replay = await h.create(actor: h.mcp);
    expect(replay.value!.entityId, id);
    expect(replay.value!.replayed, isTrue);
    expect(h.repository.state.profiles, isEmpty);
    expect(h.repository.state.credentials, isEmpty);
    expect(h.repository.state.endpoints, isEmpty);
    expect(h.connections.closeCalls, 1);
    expect(h.protector.calls, 1);
  });

  test(
    'receipt expiry at24h permits a new create and prunes expired unique key',
    () async {
      final first = await h.create(actor: h.mcp);
      h.now += ReceiptBook.lifetimeMs;
      final again = await h.create(actor: h.mcp);
      expect(again.ok, isTrue);
      expect(again.value!.replayed, isFalse);
      expect(again.value!.entityId, isNot(first.value!.entityId));
      expect(h.repository.state.profiles.length, 2);
      expect(h.repository.state.receipts.length, 1);
    },
  );

  test('rename preserves credential, connection revision, live session and trust warning', () async {
    final id = (await h.create()).value!.entityId;
    final old = copyProfile(h.repository.state.profiles[id]!);
    final e = h.repository.state.endpoints[old.endpointId]!
      ..changed = true
      ..acceptedFingerprint = 'SHA256:${'A' * 43}'
      ..observedFingerprint = 'SHA256:${'B' * 43}';
    h.connections.views[id] = ConnectionView(
      state: ConnectionState.connected,
      sessionId: fixtureId(80),
    );
    final updated = await h.owner.updateProfile(
      h.actors.ui,
      id,
      const ProfilePatch(displayName: ' Renamed '),
      expectedRevision: 1,
      mutationId: 'rename',
    );
    expect(updated.value!.revision, 2);
    expect(h.connections.closeCalls, 0);
    final current = h.repository.state.profiles[id]!;
    expect(current.displayName, 'Renamed');
    expect(current.connectionRevision, 1);
    expect(current.credentialId, old.credentialId);
    final detail = await h.owner.getProfile(h.actors.ui, id);
    expect(detail.value!.connection.state, ConnectionState.connected);
    expect(detail.value!.trust.changed, isTrue);
    expect(detail.value!.trust.observedFingerprint, e.observedFingerprint);
  });

  test('connection-affecting update closes outside gate before atomic secret replacement', () async {
    final id = (await h.create()).value!.entityId;
    final old = copyProfile(h.repository.state.profiles[id]!);
    h.connections.onClose = () async {
      expect(h.repository.state.profiles[id]!.username, 'Root');
      expect(
        h.repository.state.credentials.containsKey(old.credentialId),
        isTrue,
      );
      expect((await h.owner.listProfiles(h.actors.ui)).ok, isTrue);
    };
    final result = await h.owner.updateProfile(
      h.actors.ui,
      id,
      ProfilePatch(
        username: 'other',
        authentication: PasswordInput(' exact new '),
      ),
      expectedRevision: 1,
      mutationId: 'secret',
    );
    expect(result.ok, isTrue);
    expect(h.connections.closeCalls, 1);
    final current = h.repository.state.profiles[id]!;
    expect(current.profileRevision, 2);
    expect(current.connectionRevision, 2);
    expect(current.credentialId, isNot(old.credentialId));
    expect(current.endpointId, old.endpointId);
    expect(
      h.repository.state.credentials.containsKey(old.credentialId),
      isFalse,
    );
    expect(h.repository.state.credentials.values.single.secretRevision, 2);
  });

  test(
    'endpoint moves retain shared old trust and last deletion removes it',
    () async {
      final a = (await h.create(mutation: 'a')).value!.entityId;
      final b = (await h.create(mutation: 'b')).value!.entityId;
      final oldEndpoint = h.repository.state.profiles[a]!.endpointId;
      h.repository.state.endpoints[oldEndpoint]!
        ..changed = true
        ..acceptedFingerprint = 'SHA256:${'A' * 43}';
      expect(
        (await h.owner.updateProfile(
          h.actors.ui,
          a,
          const ProfilePatch(host: 'new.test'),
          expectedRevision: 1,
          mutationId: 'move',
        )).ok,
        isTrue,
      );
      final nextEndpoint = h.repository.state.profiles[a]!.endpointId;
      expect(h.repository.state.endpoints[oldEndpoint]!.profileRefCount, 1);
      expect(h.repository.state.endpoints[oldEndpoint]!.changed, isTrue);
      expect(
        h.repository.state.endpoints[nextEndpoint]!.acceptedFingerprint,
        isNull,
      );
      expect(h.repository.state.endpoints[nextEndpoint]!.changed, isFalse);
      expect(
        (await h.owner.deleteProfile(
          h.actors.ui,
          b,
          expectedRevision: 1,
          confirmed: true,
        )).ok,
        isTrue,
      );
      expect(h.repository.state.endpoints.containsKey(oldEndpoint), isFalse);
      expect(h.repository.state.profiles.containsKey(a), isTrue);
      await h.create(mutation: 'fresh-old');
      expect(
        h.repository.state.endpoints[oldEndpoint]!.acceptedFingerprint,
        isNull,
      );
    },
  );

  test('invalid, stale and empty updates preserve data without protecting or closing', () async {
    final id = (await h.create()).value!.entityId;
    for (final patch in [
      const ProfilePatch(),
      const ProfilePatch(port: 0),
      const ProfilePatch(username: 'bad user'),
    ]) {
      final result = await h.owner.updateProfile(
        h.actors.ui,
        id,
        patch,
        expectedRevision: 1,
        mutationId: 'invalid',
      );
      expect(result.error!.code, FailureCode.invalidArgument);
    }
    final stale = await h.owner.updateProfile(
      h.actors.ui,
      id,
      ProfilePatch(authentication: PasswordInput('new')),
      expectedRevision: 2,
      mutationId: 'stale',
    );
    expect(stale.error!.code, FailureCode.conflict);
    expect(h.protector.calls, 1);
    expect(h.connections.closeCalls, 0);
    expect(h.repository.state.profiles[id]!.profileRevision, 1);
    expect(h.repository.state.receipts.length, 1);
    expect(
      (await h.owner.deleteProfile(
        h.actors.ui,
        id,
        expectedRevision: 1,
        confirmed: false,
      )).error!.code,
      FailureCode.invalidArgument,
    );
  });

  test(
    'protection failure cannot create or replace the old credential',
    () async {
      h.protector.fail = true;
      expect((await h.create()).error!.code, FailureCode.protectionUnavailable);
      expect(h.repository.state.profiles, isEmpty);
      h.protector.fail = false;
      final id = (await h.create()).value!.entityId;
      final old = h.repository.state.profiles[id]!.credentialId;
      h.protector.fail = true;
      final update = await h.owner.updateProfile(
        h.actors.ui,
        id,
        ProfilePatch(authentication: PasswordInput('new')),
        expectedRevision: 1,
        mutationId: 'fail',
      );
      expect(update.error!.code, FailureCode.protectionUnavailable);
      expect(h.repository.state.profiles[id]!.credentialId, old);
      expect(h.connections.closeCalls, 0);
    },
  );

  test('revocation during protection denies late commit and expired actors cannot replay', () async {
    h.protector.beforeReturn = () async {
      h.state.revoked = true;
    };
    expect(
      (await h.create(actor: h.mcp)).error!.code,
      FailureCode.accessRevoked,
    );
    expect(h.repository.state.profiles, isEmpty);
    expect(h.protector.retainedInput!.every((b) => b == 0), isTrue);
    h.protector.beforeReturn = null;
    h.state.revoked = false;
    await h.create(actor: h.mcp);
    h.state.expired = true;
    expect(
      (await h.create(actor: h.mcp)).error!.code,
      FailureCode.grantExpired,
    );
    expect(h.repository.state.profiles.length, 1);
  });

  test('revocation after commit suppresses response while retaining durable receipt', () async {
    h.state.beforeAuthorize = (point) async {
      if (point == AuthorizationPoint.response &&
          h.repository.state.profiles.isNotEmpty)
        h.state.revoked = true;
    };
    final result = await h.create(actor: h.mcp);
    expect(result.error!.code, FailureCode.accessRevoked);
    expect(h.repository.state.profiles.length, 1);
    expect(h.repository.state.receipts.length, 1);
    h.state.beforeAuthorize = null;
    h.state.revoked = false;
    expect((await h.create(actor: h.mcp)).value!.replayed, isTrue);
    expect(h.protector.calls, 1);
  });

  test(
    'shutdown during protection discards result and drains preparation',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      h.protector.beforeReturn = () {
        entered.complete();
        return release.future;
      };
      final creating = h.create();
      await entered.future;
      await h.owner.stopAdmission();
      await h.owner.cancelPending();
      release.complete();
      expect((await creating).error!.code, FailureCode.shuttingDown);
      await h.owner.drain();
      expect(h.repository.state.profiles, isEmpty);
      expect(h.protector.retainedInput!.every((b) => b == 0), isTrue);
      expect(
        (await h.create(mutation: 'after-stop')).error!.code,
        FailureCode.shuttingDown,
      );
    },
  );

  test(
    'failed close quarantines endpoint; rename and other endpoints stay usable',
    () async {
      final id = (await h.create()).value!.entityId;
      h.connections.failClose = true;
      final update = await h.owner.updateProfile(
        h.actors.ui,
        id,
        const ProfilePatch(username: 'other'),
        expectedRevision: 1,
        mutationId: 'close',
      );
      expect(update.error!.code, FailureCode.cleanupRequired);
      expect(h.repository.state.profiles[id]!.username, 'Root');
      expect(
        (await h.owner.updateProfile(
          h.actors.ui,
          id,
          const ProfilePatch(displayName: 'rename'),
          expectedRevision: 1,
          mutationId: 'rename',
        )).ok,
        isTrue,
      );
      expect(
        (await h.owner.deleteProfile(
          h.actors.ui,
          id,
          expectedRevision: 2,
          confirmed: true,
        )).error!.code,
        FailureCode.cleanupRequired,
      );
      expect(h.connections.closeCalls, 1);
      expect(
        (await h.create(mutation: 'same')).error!.code,
        FailureCode.cleanupRequired,
      );
      expect(
        (await h.create(mutation: 'other', host: 'other.test')).ok,
        isTrue,
      );
    },
  );

  test(
    'list order/cursor are stable and mutation invalidates the old cursor',
    () async {
      final ids = <String>[];
      for (var i = 0; i < 3; i++) {
        ids.add((await h.create(mutation: 'create-$i')).value!.entityId);
      }
      final first = await h.owner.listProfiles(h.actors.ui, limit: 1);
      expect(first.value!.items.single.profileId, ids.first);
      final second = await h.owner.listProfiles(
        h.actors.ui,
        limit: 1,
        cursor: first.value!.nextCursor,
      );
      expect(second.value!.items.single.profileId, ids[1]);
      await h.owner.updateProfile(
        h.actors.ui,
        ids.first,
        const ProfilePatch(displayName: 'new'),
        expectedRevision: 1,
        mutationId: 'rename',
      );
      expect(
        (await h.owner.listProfiles(
          h.actors.ui,
          cursor: first.value!.nextCursor,
        )).error!.code,
        FailureCode.conflict,
      );
      expect(
        (await h.owner.listProfiles(h.actors.ui, limit: 0)).error!.code,
        FailureCode.invalidArgument,
      );
      expect(
        (await h.owner.listProfiles(
          h.actors.ui,
          cursor: 'not-a-cursor',
        )).error!.code,
        FailureCode.invalidArgument,
      );
    },
  );

  test('missing credential is storage error and unknown profile is not empty success', () async {
    final id = (await h.create()).value!.entityId;
    h.repository.state.credentials.clear();
    expect(
      (await h.owner.listProfiles(h.actors.ui)).error!.code,
      FailureCode.storageUnavailable,
    );
    expect(
      (await h.owner.getProfile(h.actors.ui, id)).error!.code,
      FailureCode.storageUnavailable,
    );
    expect(
      (await h.owner.getProfile(h.actors.ui, fixtureId(90))).error!.code,
      FailureCode.profileNotFound,
    );
    expect(
      (await h.owner.getProfile(h.actors.ui, 'bad')).error!.code,
      FailureCode.invalidArgument,
    );
  });

  test(
    'profile and retained-receipt capacity reject before any committed changes',
    () async {
      final id = (await h.create()).value!.entityId;
      final source = h.repository.state.profiles[id]!;
      for (var i = 0; i < 999; i++) {
        final p = copyProfile(source)
          ..profileId = fixtureId(2000 + i)
          ..credentialId = fixtureId(4000 + i);
        h.repository.state.profiles[p.profileId] = p;
        h.repository.state.credentials[p.credentialId] =
            copyCredential(h.repository.state.credentials[source.credentialId]!)
              ..credentialId = p.credentialId
              ..profileId = p.profileId;
      }
      h.repository.state.endpoints[source.endpointId]!.profileRefCount = 1000;
      expect(
        (await h.create(mutation: 'full')).error!.code,
        FailureCode.resourceExhausted,
      );
      expect(h.repository.state.profiles.length, 1000);
      h.repository.state.profiles.removeWhere((k, v) => k != id);
      h.repository.state.credentials.removeWhere(
        (k, v) => k != source.credentialId,
      );
      h.repository.state.endpoints[source.endpointId]!.profileRefCount = 1;
      h.repository.receiptCountOverride = ReceiptBook.maxReceipts;
      expect(
        (await h.create(mutation: 'receipts-full')).error!.code,
        FailureCode.resourceExhausted,
      );
      expect(h.repository.state.profiles.length, 1);
      expect(
        h.repository.state.endpoints[source.endpointId]!.profileRefCount,
        1,
      );
      expect(h.repository.state.settings.dataRevision, 2);
      expect(h.repository.state.receipts.length, 1);
    },
  );

  for (var step = 1; step <= 5; step++) {
    test(
      'create rollback after record write $step leaves all collections unchanged',
      () async {
        h.repository.failAfterWrite = step;
        expect((await h.create()).error!.code, FailureCode.storageUnavailable);
        expect(h.repository.state.profiles, isEmpty);
        expect(h.repository.state.credentials, isEmpty);
        expect(h.repository.state.endpoints, isEmpty);
        expect(h.repository.state.receipts, isEmpty);
        expect(h.repository.state.settings.dataRevision, 1);
        expect(h.repository.state.settings.profilesListRevision, 1);
      },
    );
  }
  for (var step = 1; step <= 7; step++) {
    test(
      'update rollback after record write $step preserves old credential and endpoint',
      () async {
        final id = (await h.create()).value!.entityId;
        final old = copyProfile(h.repository.state.profiles[id]!);
        h.repository.failAfterWrite = step;
        final result = await h.owner.updateProfile(
          h.actors.ui,
          id,
          ProfilePatch(
            host: 'new.test',
            authentication: PasswordInput('replacement'),
          ),
          expectedRevision: 1,
          mutationId: 'update',
        );
        expect(result.error!.code, FailureCode.storageUnavailable);
        final current = h.repository.state.profiles[id]!;
        expect(current.profileRevision, 1);
        expect(current.credentialId, old.credentialId);
        expect(current.endpointId, old.endpointId);
        expect(h.repository.state.endpoints.length, 1);
        expect(h.repository.state.credentials.length, 1);
        expect(h.repository.state.receipts.length, 1);
        expect(h.repository.state.settings.dataRevision, 2);
      },
    );
  }
  for (var step = 1; step <= 4; step++) {
    test(
      'delete rollback after record write $step preserves profile and last trust',
      () async {
        final id = (await h.create()).value!.entityId;
        h.repository.failAfterWrite = step;
        expect(
          (await h.owner.deleteProfile(
            h.actors.ui,
            id,
            expectedRevision: 1,
            confirmed: true,
          )).error!.code,
          FailureCode.storageUnavailable,
        );
        expect(h.repository.state.profiles.length, 1);
        expect(h.repository.state.credentials.length, 1);
        expect(h.repository.state.endpoints.values.single.profileRefCount, 1);
        expect(h.repository.state.settings.dataRevision, 2);
      },
    );
  }

  test(
    'commit failure rolls back receipt and same mutation can be retried',
    () async {
      h.repository.failCommit = true;
      expect(
        (await h.create(actor: h.mcp)).error!.code,
        FailureCode.storageUnavailable,
      );
      expect(h.repository.state.receipts, isEmpty);
      expect((await h.create(actor: h.mcp)).ok, isTrue);
      expect(h.repository.state.profiles.length, 1);
    },
  );

  test(
    'concurrent same create shares one effect despite duplicate preparation',
    () async {
      final both = Completer<void>(), release = Completer<void>();
      var prepared = 0;
      h.protector.beforeReturn = () {
        prepared++;
        if (prepared == 2) both.complete();
        return release.future;
      };
      final a = h.create(actor: h.mcp), b = h.create(actor: h.mcp);
      await both.future;
      release.complete();
      final results = await Future.wait([a, b]);
      expect(results.every((r) => r.ok), isTrue);
      expect(results.map((r) => r.value!.entityId).toSet().length, 1);
      expect(results.where((r) => r.value!.replayed).length, 1);
      expect(h.repository.state.profiles.length, 1);
      expect(h.repository.state.endpoints.values.single.profileRefCount, 1);
      expect(h.repository.state.settings.dataRevision, 2);
    },
  );

  test(
    'concurrent updates with one expected revision commit only one change',
    () async {
      final id = (await h.create()).value!.entityId;
      final results = await Future.wait([
        h.owner.updateProfile(
          h.actors.ui,
          id,
          const ProfilePatch(displayName: 'A'),
          expectedRevision: 1,
          mutationId: 'a',
        ),
        h.owner.updateProfile(
          h.actors.ui,
          id,
          const ProfilePatch(displayName: 'B'),
          expectedRevision: 1,
          mutationId: 'b',
        ),
      ]);
      expect(results.where((r) => r.ok).length, 1);
      expect(
        results.where((r) => r.error?.code == FailureCode.conflict).length,
        1,
      );
      expect(h.repository.state.profiles[id]!.profileRevision, 2);
    },
  );

  test('receipt ID validation and disposed tickets fail closed', () async {
    expect(
      (await h.owner.createProfile(
        h.mcp,
        h.draft(),
        mutationId: 'bad id',
      )).error!.code,
      FailureCode.invalidArgument,
    );
    final ticket = h.owner.receipts.ticket(
      h.mcp,
      ReceiptMethod.createProfile,
      'valid',
      {},
    )..dispose();
    await expectLater(
      h.gate.prepare(
        h.mcp,
        (context) => h.repository.read(
          (r) => h.owner.receipts.lookup(context, r, ticket),
        ),
      ),
      throwsA(isA<OperationFailure>()),
    );
    expect(h.repository.state.profiles, isEmpty);
  });
}
