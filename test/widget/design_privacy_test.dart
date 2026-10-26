import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/app.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/profiles/credential_input.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/profiles/profile_form.dart';
import 'package:serverdeck/profiles/profile_list.dart';
import 'package:serverdeck/shell/private_session.dart';
import 'package:serverdeck_protocol/models.dart';

import '../contract/profile_controller_test.dart' as fixture;
import '../support/design_privacy_state_cases.dart';

export '../support/design_privacy_state_cases.dart'
    show registerDesignPrivacyStateCases;

const _oldTarget = 'PRIVATE retired profile';
const _oldAddress = 'retired-private.example';
const _draft = 'PRIVATE unsaved form draft';
const _secret = 'PRIVATE password never persisted';
const _currentTarget = 'Current authorized profile';
const _currentGeneration = '33333333-3333-4333-8333-333333333333';

/// This is the real FoundationApp/ProfileController/ProfileList/ProfileForm
/// composition. The existing LocalApiClient snapshot seam supplies synthetic
/// DTOs; this suite does not claim native transport, disk storage, SSH, or
/// TrustedApiClient authority. Other private modal families and picker races
/// are additional T037 work, not acceptance inferred from this representative.
void main() {
  registerDesignPrivacyStateCases();
  for (final loss in _Loss.values) {
    testWidgets('${loss.name} retires the real edit form and masked draft', (
      tester,
    ) async {
      final harness = await _Harness.open(tester);
      try {
        await harness.openEdit();
        final previousForm = tester.state(find.byType(ProfileForm));
        final previousCredential = tester.state<CredentialInputState>(
          find.byType(CredentialInput),
        );
        final previousTile = tester.state(
          find.byType(ExpansionTile, skipOffstage: false),
        );
        final route = ModalRoute.of(tester.element(find.byType(ProfileForm)))!;
        final originalEpoch = _session(tester).epoch;
        final fixtureStoreBefore = harness.client.fixtureStore;
        final readsBefore = harness.client.recentReads;

        // An allowed model refresh is deliberately still in flight at loss.
        // Finishing it later must not recreate a form or overwrite current data.
        final delayedRead = Completer<void>();
        harness.client.refreshGate = delayedRead;
        final refresh = harness.model.refresh();
        final refreshesBeforeLoss = harness.client.refreshes;

        switch (loss) {
          case _Loss.unavailable:
            harness.bootstrap.show(ReadinessState.unavailable);
          case _Loss.storageBlocked:
            harness.bootstrap.show(ReadinessState.storageBlocked);
          case _Loss.incompatible:
            harness.bootstrap.show(ReadinessState.incompatible);
          case _Loss.connecting:
            harness.client.visibilityStates.add(
              ClientConnectionState.connecting,
            );
          case _Loss.disconnected:
            harness.client.visibilityStates.add(
              ClientConnectionState.disconnected,
            );
          case _Loss.closed:
            harness.client.visibilityStates.add(ClientConnectionState.closed);
          case _Loss.unauthorized:
            harness.client.readErrors.add(ErrorCode.unauthorized);
          case _Loss.rapidLossAndCurrentRecovery:
            harness.client.readErrors.add(ErrorCode.unauthorized);
            // Both events precede the next Flutter frame. The existing DTO owner
            // accepts this current snapshot, but the old State must still die.
            harness.client.events.add(
              _snapshot(
                name: _currentTarget,
                address: 'current-authorized.example',
                revision: '2',
              ),
            );
        }

        await tester.pump();
        _expectRetired(tester);
        expect(previousForm.mounted, isFalse);
        expect(previousCredential.mounted, isFalse);
        expect(previousTile.mounted, isFalse);
        expect(_session(tester).epoch, greaterThan(originalEpoch));
        await tester.pumpAndSettle();
        expect(route.isActive, isFalse);

        delayedRead.complete();
        await refresh;
        harness.client.refreshGate = null;
        await tester.pumpAndSettle();
        _expectRetired(tester);
        expect(harness.client.refreshes, refreshesBeforeLoss);

        if (loss == _Loss.closed) {
          // Even a well-formed current-generation DTO cannot reopen a closed
          // client. A new connection plus an authorized current DTO is required.
          harness.client.events.add(
            _snapshot(name: _currentTarget, revision: '2'),
          );
          await tester.pumpAndSettle();
          expect(find.byType(ProfileList), findsNothing);
          expect(_session(tester).authorized, isFalse);
          _expectRetired(tester);
          harness.client.visibilityStates.add(ClientConnectionState.connected);
        }

        // A fresh generation makes the late retired response unambiguously old.
        // The production ProfileController, not a fake root, must reject it.
        harness.client.generationId = _currentGeneration;
        harness.bootstrap.show(ReadinessState.ready);
        final profilesBeforeLateSnapshot = harness.model.profiles;
        harness.client.events.add(_snapshot(revision: '50'));
        await tester.pumpAndSettle();
        _expectRetired(tester);
        expect(harness.model.profiles, same(profilesBeforeLateSnapshot));

        harness.client.events.add(
          _snapshot(
            name: _currentTarget,
            address: 'current-authorized.example',
            revision: '3',
            generation: _currentGeneration,
          ),
        );
        await tester.pumpAndSettle();
        expect(_session(tester).authorized, isTrue);
        expect(harness.model.selected!.name, _currentTarget);
        expect(find.text(_currentTarget), findsWidgets);
        expect(find.byType(ProfileForm, skipOffstage: false), findsNothing);
        expect(find.byType(CredentialInput, skipOffstage: false), findsNothing);
        expect(
          tester.state(find.byType(ExpansionTile)),
          isNot(same(previousTile)),
        );
        expect(find.text('Редактировать профиль'), findsNothing);
        _expectRetired(tester);

        // Inspect the newly opened production form: consent and secret buffers
        // are fresh, while persisted fixture data was never cleared by the UI.
        await tester.tap(find.text(_currentTarget).last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Редактировать профиль'));
        await tester.tap(find.text('Редактировать профиль'));
        await tester.pumpAndSettle();
        final currentCredential = tester.state<CredentialInputState>(
          find.byType(CredentialInput),
        );
        expect(currentCredential, isNot(same(previousCredential)));
        expect(currentCredential.choice, CredentialChoice.keep);
        expect(currentCredential.password.text, isEmpty);
        expect(currentCredential.keyInput.text, isEmpty);
        expect(currentCredential.passphrase.text, isEmpty);
        expect(currentCredential.revealed, isFalse);
        expect(currentCredential.picking, isFalse);
        _expectRetired(tester, allowCurrentForm: true);
        expect(harness.client.fixtureStore, same(fixtureStoreBefore));
        expect(harness.client.fixtureStore.single['name'], _oldTarget);
        expect(harness.client.mutations, 0);
        expect(harness.client.connections, 0);
        expect(harness.client.otherReads, isEmpty);
        expect(harness.bootstrap.retries, 0);
        // Only an actual bootstrap ready transition starts the existing model
        // refresh/history cycle. UI-only client/auth retirement starts no read.
        final readyCycles = switch (loss) {
          _Loss.unavailable || _Loss.storageBlocked || _Loss.incompatible => 1,
          _ => 0,
        };
        expect(harness.client.refreshes, refreshesBeforeLoss + readyCycles);
        expect(harness.client.recentReads, readsBefore + readyCycles);
        expect(tester.takeException(), isNull);
      } finally {
        await harness.close();
      }
    });
  }

  testWidgets(
    'theme and resize preserve the real edit route, State and secret',
    (tester) async {
      final harness = await _Harness.open(tester);
      try {
        await harness.openEdit();
        final form = tester.state(find.byType(ProfileForm));
        final credential = tester.state<CredentialInputState>(
          find.byType(CredentialInput),
        );
        final tile = tester.state(
          find.byType(ExpansionTile, skipOffstage: false),
        );
        final route = ModalRoute.of(tester.element(find.byType(ProfileForm)))!;
        final epoch = _session(tester).epoch;
        final refreshes = harness.client.refreshes;
        final recentReads = harness.client.recentReads;
        tester.view.physicalSize = const Size(390, 800);
        harness.client.events.add(_snapshot(theme: ThemePreference.light));
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(ProfileForm)), same(form));
        expect(tester.state(find.byType(CredentialInput)), same(credential));
        expect(
          tester.state(find.byType(ExpansionTile, skipOffstage: false)),
          same(tile),
        );
        expect(
          ModalRoute.of(tester.element(find.byType(ProfileForm))),
          same(route),
        );
        expect(route.isActive, isTrue);
        expect(route.isCurrent, isTrue);
        expect(_session(tester).epoch, epoch);
        expect(_session(tester).authorized, isTrue);
        expect(_field(tester, 'profile-name').controller!.text, _draft);
        expect(credential.password.text, _secret);
        expect(credential.revealed, isFalse);
        expect(_passwordEditor(tester).obscureText, isTrue);
        expect(harness.client.refreshes, refreshes);
        expect(harness.client.recentReads, recentReads);
        expect(harness.client.mutations, 0);
        expect(harness.client.connections, 0);
        expect(harness.client.otherReads, isEmpty);
        expect(harness.bootstrap.retries, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await harness.close();
      }
    },
  );
}

enum _Loss {
  unavailable,
  storageBlocked,
  incompatible,
  connecting,
  disconnected,
  closed,
  unauthorized,
  rapidLossAndCurrentRecovery,
}

PrivateSessionScope _session(WidgetTester tester) =>
    tester.widget<PrivateSessionScope>(find.byType(PrivateSessionScope));

TextFormField _field(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(ValueKey(key)));

EditableText _passwordEditor(WidgetTester tester) =>
    tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('credential-password')),
        matching: find.byType(EditableText),
      ),
    );

void _expectRetired(WidgetTester tester, {bool allowCurrentForm = false}) {
  for (final marker in [_oldTarget, _oldAddress, _draft, _secret]) {
    expect(
      find.textContaining(marker, findRichText: true, skipOffstage: false),
      findsNothing,
      reason: 'Private text must not survive in rendered or offstage routes',
    );
    expect(find.byTooltip(marker, skipOffstage: false), findsNothing);
    for (final tooltip in tester.widgetList<Tooltip>(
      find.byType(Tooltip, skipOffstage: false),
    )) {
      expect(
        '${tooltip.message ?? tooltip.richMessage?.toPlainText()}',
        isNot(contains(marker)),
      );
    }
    for (final editable in tester.widgetList<EditableText>(
      find.byType(EditableText, skipOffstage: false),
    )) {
      expect(editable.controller.text, isNot(contains(marker)));
    }
    expect(_semanticsTree(tester), isNot(contains(marker)));
  }
  if (!allowCurrentForm) {
    expect(find.byType(ProfileForm, skipOffstage: false), findsNothing);
    expect(find.byType(CredentialInput, skipOffstage: false), findsNothing);
    expect(
      find.text('Редактирование профиля', skipOffstage: false),
      findsNothing,
    );
    expect(find.text('Сохранить', skipOffstage: false), findsNothing);
  }
}

String _semanticsTree(WidgetTester tester) {
  final trees = <String>[];
  void collect(PipelineOwner owner) {
    final root = owner.semanticsOwner?.rootSemanticsNode;
    if (root != null) trees.add(root.toStringDeep());
    owner.visitChildren(collect);
  }

  collect(tester.binding.rootPipelineOwner);
  expect(
    trees,
    isNotEmpty,
    reason: 'Privacy assertions require active semantics',
  );
  return trees.join('\n');
}

ClientSnapshot _snapshot({
  String name = _oldTarget,
  String address = _oldAddress,
  String revision = '1',
  String generation = fixture.fixtureGeneration,
  ThemePreference theme = ThemePreference.dark,
}) {
  final base = fixture.snapshot(revision: revision, gen: generation);
  final profile = Map<String, Object?>.of(
    (base.profiles.result['profiles'] as List).single as Map<String, Object?>,
  )..addAll({'name': name, 'address': address});
  return ClientSnapshot(
    ApiReply(generation, {
      'storeRevision': revision,
      'profiles': [profile],
    }),
    ApiReply(generation, {
      'storeRevision': revision,
      'settings': SettingsView(
        theme: theme,
        reduceMotion: true,
        selectedProfileId: fixture.profileId,
      ).toJson(),
    }),
  );
}

class _Harness {
  _Harness(this.tester, this.client, this.bootstrap, this.semantics);
  final WidgetTester tester;
  final _PrivacyClient client;
  final _PrivacyBootstrap bootstrap;
  final SemanticsHandle semantics;

  late final ProfileController model = tester
      .widget<ProfileList>(find.byType(ProfileList))
      .controller;

  static Future<_Harness> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    final client = _PrivacyClient();
    final bootstrap = _PrivacyBootstrap(client)..show(ReadinessState.ready);
    await tester.pumpWidget(FoundationApp(bootstrap: bootstrap));
    client.events.add(client.storedSnapshot);
    await tester.pumpAndSettle();
    expect(find.text(_oldTarget), findsWidgets);
    expect(client.refreshes, 1);
    expect(client.recentReads, 1);
    final harness = _Harness(tester, client, bootstrap, semantics);
    expect(harness.model.loaded, isTrue);
    return harness;
  }

  Future<void> close() async {
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await bootstrap.close();
    await client.visibilityStates.close();
    await client.events.close();
    await client.readErrors.close();
  }

  Future<void> openEdit() async {
    await tester.tap(find.text(_oldTarget).last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Редактировать профиль'));
    await tester.tap(find.text('Редактировать профиль'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileForm), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('profile-name')), _draft);
    final choice = find.text('Сохранить существующий');
    await tester.ensureVisible(choice);
    await tester.tap(choice);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новый пароль'));
    await tester.pumpAndSettle();
    final password = find.byKey(const ValueKey('credential-password'));
    await tester.ensureVisible(password);
    await tester.enterText(password, _secret);
    await tester.pumpAndSettle();
    expect(_passwordEditor(tester).obscureText, isTrue);
    expect(_field(tester, 'credential-password').controller!.text, _secret);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('credential-password')))
          .toStringDeep(),
      isNot(contains(_secret)),
    );
    expect(_field(tester, 'profile-name').controller!.text, _draft);
  }
}

class _PrivacyBootstrap extends fixture.ModelBootstrap {
  _PrivacyBootstrap(super.client);
  int retries = 0;
  @override
  Future<void> retry() async => retries++;
}

class _PrivacyClient extends fixture.ModelClient {
  final visibilityStates = StreamController<ClientConnectionState>.broadcast(
    sync: true,
  );
  final fixtureStore = List<Map<String, Object?>>.unmodifiable([
    Map<String, Object?>.unmodifiable(
      (_snapshot().profiles.result['profiles'] as List).single
          as Map<String, Object?>,
    ),
  ]);
  ClientSnapshot get storedSnapshot => ClientSnapshot(
    ApiReply(generationId, {'storeRevision': '1', 'profiles': fixtureStore}),
    _snapshot().settings,
  );
  int mutations = 0, connections = 0, recentReads = 0;
  final otherReads = <ApiMethod>[];

  @override
  Stream<ClientConnectionState> get states => visibilityStates.stream;

  @override
  Future<void> connect() async {
    connections++;
    throw StateError('This presentation fixture must never connect');
  }

  @override
  Future<ApiReply> mutate(MutationIntent intent) async {
    mutations++;
    throw StateError('This presentation fixture must never mutate');
  }

  @override
  Future<ApiReply> read(
    ApiMethod method, [
    Map<String, Object?> params = const {},
  ]) {
    if (method == ApiMethod.mutationsRecent) {
      recentReads++;
    } else {
      otherReads.add(method);
    }
    return super.read(method, params);
  }
}
