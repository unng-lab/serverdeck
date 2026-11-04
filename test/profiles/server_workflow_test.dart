import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/actor.dart';
import 'package:serverdeck/domain/app_operations.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/profiles/profile_form.dart';
import 'package:serverdeck/profiles/profile_view.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_components.dart';

const epoch = '00000001-0000-4000-8000-000000000000';
const profileId = '00000002-0000-4000-8000-000000000000';

final class WorkflowOperations extends Fake implements AppOperations {
  ProfileView? profile;
  ConnectionView connection = const ConnectionView(
    state: ConnectionState.disconnected,
  );
  TrustChallenge? challenge;
  String? pin;
  TrustKind? connectTrustKind;
  ConnectionState challengeState = ConnectionState.needTrust;
  bool connectBeforeSaveReturns = false;
  bool changed = false,
      requirePhrase = false,
      failSave = false,
      failConnect = false,
      holdConnecting = false;
  int connects = 0, accepts = 0, replacements = 0, cancels = 0, phrases = 0;
  int retentions = 0;
  int creates = 0, updates = 0, deletes = 0;
  String nonce = 'synthetic-nonce';
  Completer<void>? connectReply, detailReply;
  bool delayDetailsAfterConnect = false;
  OperationResult<T> ok<T extends PublicValue>(T value) =>
      OperationResult.success(
        value,
        const OperationMeta(dataRevision: 1, ownerEpoch: epoch),
      );
  TrustView get trust => TrustView(
    trustRevision: 1,
    observationRevision: changed ? 2 : 1,
    changed: changed,
    acceptedFingerprint: pin,
    observedFingerprint: changed ? 'SHA256:new-public' : null,
    challenge: challenge,
  );
  ProfileView make({
    String name = 'Synthetic server',
    int revision = 1,
    String host = 'server.invalid',
    int port = 22,
    String user = 'root',
    AuthKind kind = AuthKind.password,
  }) => ProfileView(
    profileId: profileId,
    revision: revision,
    connectionRevision: 1,
    displayName: name,
    host: host,
    port: port,
    username: user,
    authKind: kind,
    hasCredential: true,
    endpointId: 'synthetic-endpoint',
  );
  @override
  Future<OperationResult<ProfilesPage>> listProfiles(
    Actor actor, {
    int limit = 50,
    String? cursor,
  }) async => ok(
    ProfilesPage(items: [if (profile != null) profile!], snapshotRevision: 1),
  );
  bool failConnectionRead = false;
  bool failTrustRead = false;
  @override
  Future<OperationResult<ConnectionView>> getConnection(
    Actor actor,
    String id,
  ) async => failConnectionRead
      ? const OperationResult.failure(
          OperationFailure(FailureCode.storageUnavailable),
        )
      : ok(connection);
  @override
  Future<OperationResult<TrustView>> getTrust(Actor actor, String id) async =>
      failTrustRead
      ? const OperationResult.failure(
          OperationFailure(FailureCode.storageUnavailable),
        )
      : ok(trust);
  @override
  Future<OperationResult<ProfileDetails>> getProfile(
    Actor actor,
    String id,
  ) async {
    await detailReply?.future;
    return profile == null
        ? const OperationResult.failure(
            OperationFailure(FailureCode.profileNotFound),
          )
        : ok(
            ProfileDetails(
              profile: profile!,
              connection: connection,
              trust: trust,
            ),
          );
  }

  @override
  Future<OperationResult<MutationValue>> createProfile(
    Actor actor,
    ProfileDraft draft, {
    required String mutationId,
  }) async {
    creates++;
    if (failSave)
      return const OperationResult.failure(
        OperationFailure(FailureCode.storageUnavailable),
      );
    profile = make(
      name: draft.displayName,
      host: draft.host,
      port: draft.port ?? 22,
      user: draft.username,
    );
    if (connectBeforeSaveReturns) {
      await connect(actor, profileId, expectedRevision: 1);
    }
    return ok(const MutationValue(entityId: profileId, revision: 1));
  }

  @override
  Future<OperationResult<MutationValue>> updateProfile(
    Actor actor,
    String id,
    ProfilePatch patch, {
    required int expectedRevision,
    required String mutationId,
  }) async {
    updates++;
    final previous = profile!;
    profile = make(
      name: patch.displayName ?? previous.displayName,
      host: patch.host ?? previous.host,
      port: patch.port ?? previous.port,
      user: patch.username ?? previous.username,
      revision: previous.revision + 1,
    );
    return ok(MutationValue(entityId: id, revision: profile!.revision));
  }

  @override
  Future<OperationResult<MutationValue>> deleteProfile(
    Actor actor,
    String id, {
    required int expectedRevision,
    required bool confirmed,
  }) async {
    deletes++;
    profile = null;
    return ok(MutationValue(entityId: id, revision: expectedRevision));
  }

  @override
  Future<OperationResult<ConnectionView>> connect(
    Actor actor,
    String id, {
    required int expectedRevision,
  }) async {
    connects++;
    if (failConnect) {
      connection = const ConnectionView(
        state: ConnectionState.failed,
        failureCode: FailureCode.networkError,
      );
    } else if (holdConnecting) {
      connection = const ConnectionView(
        state: ConnectionState.connecting,
        attemptId: 'attempt',
      );
    } else {
      challenge = TrustChallenge(
        kind:
            connectTrustKind ?? (changed ? TrustKind.replace : TrustKind.first),
        nonce: nonce,
        attemptId: 'attempt',
        endpointId: 'synthetic-endpoint',
        profileRevision: profile!.revision,
        trustRevision: 1,
        observationRevision: changed ? 2 : 1,
        fingerprint: connectTrustKind == TrustKind.retain
            ? pin!
            : changed
            ? 'SHA256:new-public'
            : 'SHA256:first-public',
        oldFingerprint: changed ? pin : null,
        expiresAt: 1900000000000,
        host: profile!.host,
        port: profile!.port,
        keyType: 'ssh-ed25519',
      );
      connection = ConnectionView(
        state: challengeState,
        attemptId: challengeState == ConnectionState.connected
            ? null
            : 'attempt',
        sessionId: challengeState == ConnectionState.connected
            ? 'session'
            : null,
        failureCode: challengeState == ConnectionState.failed
            ? FailureCode.hostKeyChanged
            : null,
        challenge: challengeState == ConnectionState.needTrust
            ? challenge
            : null,
      );
    }
    final admitted = connection;
    if (delayDetailsAfterConnect) detailReply = Completer<void>();
    await connectReply?.future;
    return ok(admitted);
  }

  @override
  Future<OperationResult<MutationValue>> acceptTrust(
    Actor actor,
    TrustDecision decision,
  ) async {
    accepts++;
    if (profile == null || decision.nonce != challenge?.nonce)
      return const OperationResult.failure(
        OperationFailure(FailureCode.conflict),
      );
    pin = decision.fingerprint;
    challenge = null;
    connection = requirePhrase
        ? const ConnectionView(
            state: ConnectionState.needPassphrase,
            attemptId: 'attempt',
            pendingInput: PendingInput(
              nonce: 'phrase-nonce',
              attemptId: 'attempt',
              expiresAt: 1900000000000,
            ),
          )
        : const ConnectionView(
            state: ConnectionState.connected,
            sessionId: 'session',
          );
    return ok(const MutationValue(entityId: profileId, revision: 1));
  }

  @override
  Future<OperationResult<MutationValue>> replaceTrust(
    Actor actor,
    ReplacementDecision decision,
  ) async {
    replacements++;
    pin = decision.newFingerprint;
    changed = false;
    challenge = null;
    connection = const ConnectionView(state: ConnectionState.disconnected);
    return ok(const MutationValue(entityId: profileId, revision: 1));
  }

  @override
  Future<OperationResult<MutationValue>> retainTrust(
    Actor actor,
    RetentionDecision decision,
  ) async {
    expect(decision.confirmed, isTrue);
    expect(decision.nonce, challenge!.nonce);
    expect(decision.acceptedFingerprint, pin);
    retentions++;
    changed = false;
    challenge = null;
    return ok(const MutationValue(entityId: profileId, revision: 1));
  }

  @override
  Future<OperationResult<ConnectionView>> cancelConnection(
    Actor actor,
    String id, {
    required String attemptId,
  }) async {
    if (profile == null ||
        connection.attemptId != attemptId ||
        connection.sessionId != null) {
      return const OperationResult.failure(
        OperationFailure(FailureCode.conflict),
      );
    }
    cancels++;
    challenge = null;
    connection = const ConnectionView(state: ConnectionState.cancelled);
    return ok(connection);
  }

  @override
  Future<OperationResult<ConnectionView>> providePassphrase(
    Actor actor,
    String id, {
    required String attemptId,
    required String nonce,
    required String passphrase,
  }) async {
    expect(passphrase, 'synthetic-phrase');
    phrases++;
    connection = const ConnectionView(
      state: ConnectionState.connected,
      sessionId: 'session',
    );
    return ok(connection);
  }
}

final class TwoProfileOperations extends WorkflowOperations {
  static const secondaryId = '00000003-0000-4000-8000-000000000000';
  final secondary = ProfileView(
    profileId: secondaryId,
    revision: 1,
    connectionRevision: 1,
    displayName: 'Secondary server',
    host: 'secondary.invalid',
    port: 22,
    username: 'root',
    authKind: AuthKind.password,
    hasCredential: true,
    endpointId: 'secondary-endpoint',
  );
  final postSaveRefresh = Completer<void>();
  bool saved = false;
  int readsAfterSave = 0;
  TrustChallenge get secondaryChallenge => const TrustChallenge(
    kind: TrustKind.first,
    nonce: 'secondary-nonce',
    attemptId: 'secondary-attempt',
    endpointId: 'secondary-endpoint',
    profileRevision: 1,
    trustRevision: 1,
    observationRevision: 1,
    fingerprint: 'SHA256:secondary-public',
    expiresAt: 1900000000000,
    host: 'secondary.invalid',
    port: 22,
    keyType: 'ssh-ed25519',
  );
  TrustView get secondaryTrust => TrustView(
    trustRevision: 1,
    observationRevision: 1,
    changed: false,
    challenge: secondaryChallenge,
  );
  @override
  Future<OperationResult<ProfilesPage>> listProfiles(
    Actor actor, {
    int limit = 50,
    String? cursor,
  }) async => ok(
    ProfilesPage(
      items: [if (profile != null) profile!, secondary],
      snapshotRevision: 1,
    ),
  );
  @override
  Future<OperationResult<TrustView>> getTrust(Actor actor, String id) async =>
      ok(id == secondaryId ? secondaryTrust : trust);
  @override
  Future<OperationResult<ProfileDetails>> getProfile(
    Actor actor,
    String id,
  ) async {
    if (id == secondaryId)
      return ok(
        ProfileDetails(
          profile: secondary,
          connection: ConnectionView(
            state: ConnectionState.needTrust,
            attemptId: 'secondary-attempt',
            challenge: secondaryChallenge,
          ),
          trust: secondaryTrust,
        ),
      );
    if (saved && ++readsAfterSave == 2) await postSaveRefresh.future;
    return super.getProfile(actor, id);
  }

  @override
  Future<OperationResult<MutationValue>> updateProfile(
    Actor actor,
    String id,
    ProfilePatch patch, {
    required int expectedRevision,
    required String mutationId,
  }) async {
    final result = await super.updateProfile(
      actor,
      id,
      patch,
      expectedRevision: expectedRevision,
      mutationId: mutationId,
    );
    saved = true;
    return result;
  }
}

Future<ProfileController> mount(
  WidgetTester tester,
  WorkflowOperations operations, {
  Future<void> Function()? applicationSettings,
}) async {
  var counter = 10;
  final controller = ProfileController(
    operations: operations,
    actor: ActorAuthority(epoch).ui,
    newId: () =>
        '${(++counter).toRadixString(16).padLeft(8, '0')}-0000-4000-8000-000000000000',
    poll: false,
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: BrandTheme.dark,
      home: Scaffold(
        body: ProfileViewPanel(
          controller: controller,
          pickKey: () async => null,
          onApplicationSettings: applicationSettings,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<void> saveNew(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Добавить сервер'));
  await tester.pumpAndSettle();
  final fields = find.descendant(
    of: find.byType(ProfileForm),
    matching: find.byType(TextField),
  );
  await tester.enterText(fields.at(0), 'Synthetic server');
  await tester.enterText(fields.at(1), 'server.invalid');
  await tester.enterText(fields.at(3), 'root');
  await tester.enterText(fields.at(4), 'synthetic-password');
  await tester.ensureVisible(find.text('Сохранить'));
  await tester.tap(find.text('Сохранить'));
  await tester.pumpAndSettle();
}

Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  for (final state in [
    ConnectionState.connected,
    ConnectionState.needPassphrase,
    ConnectionState.needTrust,
  ]) {
    testWidgets(
      'failed trust observation preserves canonical $state sidebar status',
      (tester) async {
        final ops = WorkflowOperations()..failTrustRead = true;
        ops.profile = ops.make();
        ops.connection = ConnectionView(
          state: state,
          sessionId: state == ConnectionState.connected ? 'session' : null,
        );
        await mount(tester, ops);
        final label = switch (state) {
          ConnectionState.connected => 'SSH: подключён',
          ConnectionState.needPassphrase => 'Ожидает passphrase',
          _ => 'Требуется проверка ключа',
        };
        expect(find.byTooltip(label), findsOneWidget);
        if (state != ConnectionState.needTrust)
          expect(find.byTooltip('Требуется проверка ключа'), findsNothing);
        await finish(tester);
      },
    );
  }
  testWidgets(
    'known unpinned badge cannot override a newer connected observation',
    (tester) async {
      final ops = WorkflowOperations()..profile = WorkflowOperations().make();
      final c = await mount(tester, ops);
      expect(find.byTooltip('Требуется проверка ключа'), findsOneWidget);
      ops.failTrustRead = true;
      ops.connection = const ConnectionView(
        state: ConnectionState.connected,
        sessionId: 'current-session',
      );
      await c.refresh();
      await tester.pumpAndSettle();
      expect(find.byTooltip('SSH: подключён'), findsOneWidget);
      expect(find.byTooltip('Требуется проверка ключа'), findsNothing);
      await finish(tester);
    },
  );
  test('disposed profile controller denies ordinary actions but permits exact owned cleanup', () async {
    final ops = WorkflowOperations();
    final c = ProfileController(
      operations: ops,
      actor: ActorAuthority(epoch).ui,
      newId: () => profileId,
      poll: false,
    );
    c.dispose();
    final input = PasswordInput('synthetic-only');
    final result = await c.create(
      ProfileDraft(
        displayName: 'Retired',
        host: 'retired.invalid',
        username: 'root',
        authentication: input,
      ),
      profileId,
    );
    input.dispose();
    expect(result!.code, FailureCode.shuttingDown);
    expect((await c.connect(ops.make()))!.code, FailureCode.shuttingDown);
    expect(
      (await c.delete(ops.make(), confirmed: true))!.code,
      FailureCode.shuttingDown,
    );
    expect(ops.creates + ops.updates + ops.deletes + ops.connects, 0);
    ops.profile = ops.make();
    ops.connection = const ConnectionView(
      state: ConnectionState.connecting,
      attemptId: 'owned-attempt',
    );
    await c.cancelOwnedAttempt(profileId, 'owned-attempt');
    expect(ops.cancels, 1);
  });
  for (final dialog in ['create', 'edit', 'delete']) {
    for (final rebind in [false, true]) {
      testWidgets(
        '$dialog route retires on ${rebind ? "same-id rebind" : "workspace removal"} without owner dispatch',
        (tester) async {
          final ops = WorkflowOperations();
          if (dialog != 'create') ops.profile = ops.make();
          final old = ProfileController(
            operations: ops,
            actor: ActorAuthority(epoch).ui,
            newId: () => profileId,
            poll: false,
          );
          final nextOps = WorkflowOperations()
            ..profile = WorkflowOperations().make();
          final next = ProfileController(
            operations: nextOps,
            actor: ActorAuthority(epoch).ui,
            newId: () => profileId,
            poll: false,
          );
          addTearDown(old.dispose);
          addTearDown(next.dispose);
          Widget view(ProfileController? owner) => MaterialApp(
            theme: BrandTheme.dark,
            home: Scaffold(
              body: owner == null
                  ? const Text('Retired host')
                  : ProfileViewPanel(
                      controller: owner,
                      pickKey: () async => null,
                    ),
            ),
          );
          await tester.pumpWidget(view(old));
          await tester.pumpAndSettle();
          if (dialog == 'create') {
            await tester.tap(find.byTooltip('Добавить сервер'));
          } else {
            await tester.tap(find.text('Synthetic server'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Настройки'));
            await tester.pumpAndSettle();
            await tester.ensureVisible(
              find.text(dialog == 'edit' ? 'Изменить' : 'Удалить'),
            );
            await tester.tap(
              find.text(dialog == 'edit' ? 'Изменить' : 'Удалить'),
            );
          }
          await tester.pumpAndSettle();
          if (dialog != 'delete') {
            await tester.enterText(
              find
                  .descendant(
                    of: find.byType(ProfileForm),
                    matching: find.byType(TextField),
                  )
                  .last,
              'synthetic-retired-credential',
            );
          }
          expect(find.byType(Dialog), findsOneWidget);
          if (rebind) await next.select(profileId);
          await tester.pumpWidget(view(rebind ? next : null));
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
          expect(find.byType(ProfileForm), findsNothing);
          expect(ops.creates + ops.updates + ops.deletes, 0);
          expect(nextOps.creates + nextOps.updates + nextOps.deletes, 0);
          expect(nextOps.profile, isNotNull);
          await finish(tester);
        },
      );
    }
  }
  for (final phrase in [false, true]) {
    for (final rebind in [false, true]) {
      testWidgets(
        'owned ${phrase ? "phrase" : "trust"} route retires on ${rebind ? "same-id controller rebind" : "workspace removal"}',
        (tester) async {
          final ops = WorkflowOperations()..requirePhrase = phrase;
          final old = ProfileController(
            operations: ops,
            actor: ActorAuthority(epoch).ui,
            newId: () => profileId,
            poll: false,
          );
          final nextOps = WorkflowOperations()
            ..profile = WorkflowOperations().make()
            ..pin = 'SHA256:new-public'
            ..connection = const ConnectionView(
              state: ConnectionState.connected,
              sessionId: 'new-session',
            );
          final next = ProfileController(
            operations: nextOps,
            actor: ActorAuthority(epoch).ui,
            newId: () => profileId,
            poll: false,
          );
          addTearDown(old.dispose);
          addTearDown(next.dispose);
          Widget view(ProfileController? owner) => MaterialApp(
            theme: BrandTheme.dark,
            home: Scaffold(
              body: owner == null
                  ? const Text('Retired host')
                  : ProfileViewPanel(
                      controller: owner,
                      pickKey: () async => null,
                    ),
            ),
          );
          await tester.pumpWidget(view(old));
          await tester.pumpAndSettle();
          await saveNew(tester);
          if (phrase) {
            await tester.tap(find.text('Принять ключ').last);
            await tester.pumpAndSettle();
            await tester.enterText(
              find.descendant(
                of: find.byType(Dialog),
                matching: find.byType(TextField),
              ),
              'synthetic-retired-phrase',
            );
          }
          expect(find.byType(Dialog), findsOneWidget);
          if (rebind) await next.select(profileId);
          await tester.pumpWidget(view(rebind ? next : null));
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
          expect(find.text('synthetic-retired-phrase'), findsNothing);
          expect(ops.accepts, phrase ? 1 : 0);
          expect(ops.phrases, 0);
          expect(nextOps.connection.sessionId, 'new-session');
          expect(nextOps.cancels, 0);
          await finish(tester);
        },
      );
    }
  }
  testWidgets(
    'global settings callback is available without profiles and preserves server context',
    (tester) async {
      final ops = WorkflowOperations();
      final closed = Completer<void>();
      var opens = 0;
      final c = await mount(
        tester,
        ops,
        applicationSettings: () {
          opens++;
          return closed.future;
        },
      );
      await tester.tap(find.text('Настройки приложения'));
      await tester.pump();
      expect(opens, 1);
      expect(c.selected, isNull);
      closed.complete();
      await tester.pumpAndSettle();
      ops.profile = ops.make();
      await c.refresh();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Synthetic server'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Задания'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Настройки приложения'));
      await tester.pumpAndSettle();
      expect(opens, 2);
      expect(c.selected, profileId);
      expect(tester.widget<DeckTabs>(find.byType(DeckTabs)).selected, 2);
      expect(ops.connects, 0);
      await finish(tester);
    },
  );
  testWidgets(
    'server selection scopes all four tabs, search does not select or connect',
    (tester) async {
      final ops = TwoProfileOperations()..profile = WorkflowOperations().make();
      final c = await mount(tester, ops);
      expect(find.text('Выберите сервер'), findsOneWidget);
      await tester.tap(find.text('Synthetic server'));
      await tester.pumpAndSettle();
      expect(
        find.text('Раздел пока недоступен для сервера «Synthetic server».'),
        findsOneWidget,
      );
      await tester.tap(find.text('Журналы'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Secondary server'));
      await tester.pumpAndSettle();
      expect(c.selected, TwoProfileOperations.secondaryId);
      expect(
        find.text('Раздел пока недоступен для сервера «Secondary server».'),
        findsOneWidget,
      );
      expect(tester.widget<DeckTabs>(find.byType(DeckTabs)).selected, 1);
      await tester.enterText(find.byType(TextField).first, 'Synthetic');
      await tester.pump();
      expect(c.selected, TwoProfileOperations.secondaryId);
      expect(ops.connects, 0);
      for (final section in ['ПО', 'Задания']) {
        await tester.tap(find.text(section));
        await tester.pumpAndSettle();
        expect(
          find.text('Раздел пока недоступен для сервера «Secondary server».'),
          findsOneWidget,
        );
      }
      await tester.tap(find.text('Настройки'));
      await tester.pumpAndSettle();
      expect(find.text('Изменить'), findsOneWidget);
      expect(find.text('Nginx'), findsNothing);
      await finish(tester);
    },
  );
  testWidgets(
    'unselected sidebar loss is distinct from manual disconnect and failed observation',
    (tester) async {
      final ops = WorkflowOperations()..pin = 'SHA256:public-pin';
      ops.profile = ops.make();
      ops.connection = const ConnectionView(
        state: ConnectionState.failed,
        failureCode: FailureCode.networkError,
      );
      final c = await mount(tester, ops);
      expect(c.selected, isNull);
      expect(find.text('Связь потеряна'), findsOneWidget);
      expect(
        tester.widget<DeckListItem>(find.byType(DeckListItem)).error,
        isTrue,
      );
      ops.connection = const ConnectionView(
        state: ConnectionState.disconnected,
      );
      await c.refresh();
      await tester.pumpAndSettle();
      expect(find.text('Связь потеряна'), findsNothing);
      expect(
        tester.widget<DeckListItem>(find.byType(DeckListItem)).error,
        isFalse,
      );
      expect(find.byTooltip('Не подключён'), findsOneWidget);
      ops.connection = const ConnectionView(
        state: ConnectionState.connected,
        sessionId: 'session',
      );
      await c.refresh();
      await tester.pumpAndSettle();
      expect(find.byTooltip('SSH: подключён'), findsOneWidget);
      ops.failConnectionRead = true;
      await c.refresh();
      await tester.pumpAndSettle();
      expect(find.byTooltip('SSH: подключён'), findsNothing);
      expect(
        find.byTooltip('Состояние подключения неизвестно'),
        findsOneWidget,
      );
      await finish(tester);
    },
  );
  testWidgets(
    'late save refresh A cannot enable automatic onboarding in another details session B',
    (tester) async {
      final ops = TwoProfileOperations();
      ops.profile = ops.make();
      final c = await mount(tester, ops);
      await tester.tap(find.text('Synthetic server'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Настройки'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Изменить'));
      await tester.tap(find.text('Изменить'));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(ProfileForm),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(1), 'changed.invalid');
      await tester.ensureVisible(find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(ops.readsAfterSave, 2);
      expect(ops.connects, 0);
      await tester.tap(find.byTooltip('Снять выбор сервера'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Secondary server'));
      await tester.tap(find.text('Secondary server'));
      await tester.pump();
      expect(c.selected, TwoProfileOperations.secondaryId);
      ops.postSaveRefresh.complete();
      await tester.pumpAndSettle();
      expect(c.details!.profile.profileId, TwoProfileOperations.secondaryId);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Подтверждаемый отпечаток'), findsNothing);
      expect(ops.connects, 0);
      expect(ops.accepts, 0);
      expect(ops.profile!.host, 'changed.invalid');
      await finish(tester);
    },
  );
  for (final lateState in ['pending', 'new-attempt', 'connected']) {
    testWidgets(
      'closing existing details cancels delayed onboarding admission safely: $lateState',
      (tester) async {
        final ops = WorkflowOperations()..holdConnecting = true;
        ops.profile = ops.make();
        final c = await mount(tester, ops);
        await tester.tap(find.text('Synthetic server'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Настройки'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Изменить'));
        await tester.tap(find.text('Изменить'));
        await tester.pumpAndSettle();
        final fields = find.descendant(
          of: find.byType(ProfileForm),
          matching: find.byType(TextField),
        );
        await tester.enterText(fields.at(1), 'changed.invalid');
        ops.connectReply = Completer<void>();
        await tester.ensureVisible(find.text('Сохранить'));
        await tester.tap(find.text('Сохранить'));
        await tester.pumpAndSettle();
        expect(c.pending, isTrue);
        expect(ops.connects, 1);
        expect(find.byType(Dialog), findsNothing);
        await tester.tap(find.byTooltip('Снять выбор сервера'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        if (lateState == 'new-attempt') {
          ops.connection = const ConnectionView(
            state: ConnectionState.connecting,
            attemptId: 'new-attempt',
          );
        } else if (lateState == 'connected') {
          ops.connection = const ConnectionView(
            state: ConnectionState.connected,
            attemptId: 'attempt',
            sessionId: 'established',
          );
        }
        ops.connectReply!.complete();
        await tester.pumpAndSettle();
        expect(c.pending, isFalse);
        expect(ops.cancels, lateState == 'pending' ? 1 : 0);
        expect(
          ops.connection.state,
          lateState == 'pending'
              ? ConnectionState.cancelled
              : lateState == 'connected'
              ? ConnectionState.connected
              : ConnectionState.connecting,
        );
        expect(find.byType(Dialog), findsNothing);
        await finish(tester);
      },
    );
  }
  testWidgets(
    'known onboarding attempt is cancelled while its details refresh is delayed',
    (tester) async {
      final ops = WorkflowOperations()..holdConnecting = true;
      ops.profile = ops.make();
      await mount(tester, ops);
      await tester.tap(find.text('Synthetic server'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Настройки'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Изменить'));
      await tester.tap(find.text('Изменить'));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(ProfileForm),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(1), 'changed.invalid');
      ops.delayDetailsAfterConnect = true;
      await tester.ensureVisible(find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(ops.detailReply, isNotNull);
      await tester.tap(find.byTooltip('Снять выбор сервера'));
      await tester.pumpAndSettle();
      expect(ops.cancels, 1);
      expect(ops.connection.state, ConnectionState.cancelled);
      ops.detailReply!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      await finish(tester);
    },
  );
  testWidgets(
    'an old prompt answer cannot accept a newer nonce and the new prompt stays serialized',
    (tester) async {
      final ops = WorkflowOperations();
      final c = await mount(tester, ops);
      await saveNew(tester);
      ops.nonce = 'new-synthetic-nonce';
      await ops.connect(c.actor, profileId, expectedRevision: 1);
      await c.refresh();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      await tester.tap(find.text('Принять ключ').last);
      await tester.pumpAndSettle();
      expect(ops.accepts, 1);
      expect(ops.pin, isNull);
      expect(find.byType(Dialog), findsOneWidget);
      await tester.tap(find.text('Отмена').last);
      await tester.pumpAndSettle();
      expect(ops.cancels, 1);
      await finish(tester);
    },
  );
  testWidgets(
    'successful save opens first trust immediately and repeated events do not duplicate it',
    (tester) async {
      final ops = WorkflowOperations();
      final c = await mount(tester, ops);
      await saveNew(tester);
      expect(ops.profile, isNotNull);
      expect(ops.connects, 1);
      expect(ops.accepts, 0);
      expect(find.text('Подтверждаемый отпечаток'), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await c.refresh();
        await tester.pumpAndSettle();
      }
      expect(find.byType(Dialog), findsOneWidget);
      await tester.tap(find.text('Принять ключ').last);
      await tester.pumpAndSettle();
      expect(ops.accepts, 1);
      expect(ops.pin, 'SHA256:first-public');
      expect(find.byType(Dialog), findsNothing);
      expect(find.byTooltip('Подключён'), findsOneWidget);
      await tester.tap(find.byTooltip('Снять выбор сервера'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(ops.cancels, 0);
      await finish(tester);
    },
  );
  testWidgets(
    'declining first trust preserves saved profile and does not reopen on refresh',
    (tester) async {
      final ops = WorkflowOperations();
      final c = await mount(tester, ops);
      await saveNew(tester);
      await tester.tap(find.text('Отмена').last);
      await tester.pumpAndSettle();
      await c.refresh();
      await tester.pumpAndSettle();
      expect(ops.profile, isNotNull);
      expect(ops.pin, isNull);
      expect(ops.accepts, 0);
      expect(ops.cancels, 1);
      expect(find.text('Подтверждаемый отпечаток'), findsNothing);
      await finish(tester);
    },
  );
  for (final kind in [TrustKind.replace, TrustKind.retain]) {
    for (final alreadyConnected
        in kind == TrustKind.retain ? [false, true] : [false]) {
      testWidgets(
        'onboarding offers terminal $kind challenge, already connected=$alreadyConnected',
        (tester) async {
          final ops = WorkflowOperations()
            ..changed = true
            ..pin = 'SHA256:old-public'
            ..connectTrustKind = kind
            ..challengeState = kind == TrustKind.replace
                ? ConnectionState.failed
                : ConnectionState.connected
            ..connectBeforeSaveReturns = alreadyConnected;
          final controller = await mount(tester, ops);
          await saveNew(tester);
          expect(find.text('Подтверждаемый отпечаток'), findsOneWidget);
          expect(find.byType(Dialog), findsOneWidget);
          expect(ops.replacements + ops.retentions, 0);
          for (var i = 0; i < 2; i++) {
            await controller.refresh();
            await tester.pumpAndSettle();
          }
          expect(find.byType(Dialog), findsOneWidget);
          await tester.tap(
            find
                .text(
                  kind == TrustKind.replace
                      ? 'Заменить ключ'
                      : 'Сохранить прежний ключ',
                )
                .last,
          );
          await tester.pumpAndSettle();
          expect(ops.replacements, kind == TrustKind.replace ? 1 : 0);
          expect(ops.retentions, kind == TrustKind.retain ? 1 : 0);
          expect(ops.connects, 1);
          expect(find.text('Подтверждаемый отпечаток'), findsNothing);
          await tester.tap(find.byTooltip('Снять выбор сервера'));
          await tester.pumpAndSettle();
          expect(ops.cancels, 0);
          if (kind == TrustKind.retain) {
            expect(ops.connection.sessionId, 'session');
          }
          await finish(tester);
        },
      );
    }
  }
  testWidgets(
    'failed save never starts verification, network failure does not undo a committed profile',
    (tester) async {
      final ops = WorkflowOperations()..failSave = true;
      await mount(tester, ops);
      await saveNew(tester);
      expect(ops.connects, 0);
      expect(ops.profile, isNull);
      expect(find.text('Не удалось сохранить'), findsOneWidget);
      await tester.ensureVisible(find.text('Отмена'));
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      ops.failSave = false;
      ops.failConnect = true;
      await saveNew(tester);
      expect(ops.connects, 1);
      expect(ops.profile, isNotNull);
      expect(find.byType(ProfileForm), findsNothing);
      await tester.tap(find.text('Настройки'));
      await tester.pumpAndSettle();
      expect(find.text('Состояние подключения'), findsOneWidget);
      expect(find.text('Подтверждаемый отпечаток'), findsNothing);
      await finish(tester);
    },
  );
  testWidgets(
    'changed pin is a list warning, ordinary selection opens details without an automatic prompt',
    (tester) async {
      final ops = WorkflowOperations();
      ops.profile = ops.make();
      ops.pin = 'SHA256:old-public';
      ops.changed = true;
      await mount(tester, ops);
      expect(find.text('Ключ сервера изменился'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      await tester.tap(find.text('Synthetic server'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(ops.connects, 0);
      expect(ops.replacements, 0);
      await tester.tap(find.text('Настройки'));
      await tester.pumpAndSettle();
      expect(find.textContaining('SHA256:old-public'), findsWidgets);
      await finish(tester);
    },
  );
  testWidgets(
    'name-only save retains connection and current modal instead of reconnecting',
    (tester) async {
      final ops = WorkflowOperations();
      ops.profile = ops.make();
      ops.pin = 'SHA256:first-public';
      ops.connection = const ConnectionView(
        state: ConnectionState.connected,
        sessionId: 'session',
      );
      await mount(tester, ops);
      await tester.tap(find.text('Synthetic server'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Настройки'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Изменить'));
      await tester.tap(find.text('Изменить'));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(ProfileForm),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.first, 'Renamed');
      await tester.ensureVisible(find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(ops.profile!.displayName, 'Renamed');
      expect(ops.connects, 0);
      expect(find.byType(Dialog), findsNothing);
      await finish(tester);
    },
  );
  testWidgets(
    'deleted profile closes both owned dialogs without accepting a late trust answer',
    (tester) async {
      final ops = WorkflowOperations();
      final c = await mount(tester, ops);
      await saveNew(tester);
      ops.profile = null;
      await c.refresh();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(ops.accepts, 0);
      expect(find.text('Серверов пока нет'), findsOneWidget);
      await finish(tester);
    },
  );
  testWidgets('closing onboarding details cancels only its pending attempt', (
    tester,
  ) async {
    final ops = WorkflowOperations()..holdConnecting = true;
    await mount(tester, ops);
    await saveNew(tester);
    await tester.tap(find.byTooltip('Снять выбор сервера'));
    await tester.pumpAndSettle();
    expect(ops.cancels, 1);
    expect(ops.profile, isNotNull);
    expect(ops.pin, isNull);
    await finish(tester);
  });
  testWidgets(
    'passphrase follows explicit trust and is never requested twice for one nonce',
    (tester) async {
      final ops = WorkflowOperations()..requirePhrase = true;
      final c = await mount(tester, ops);
      await saveNew(tester);
      await tester.tap(find.text('Принять ключ').last);
      await tester.pumpAndSettle();
      expect(find.text('Passphrase приватного ключа'), findsOneWidget);
      expect(ops.phrases, 0);
      await c.refresh();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(Dialog).last,
          matching: find.byType(TextField),
        ),
        'synthetic-phrase',
      );
      await tester.tap(find.text('Продолжить'));
      await tester.pumpAndSettle();
      expect(ops.phrases, 1);
      expect(find.byTooltip('Подключён'), findsOneWidget);
      await finish(tester);
    },
  );
}
