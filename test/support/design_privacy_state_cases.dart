import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/app.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/profiles/credential_input.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/profiles/profile_delete.dart';
import 'package:serverdeck/profiles/profile_form.dart';
import 'package:serverdeck/profiles/profile_list.dart';
import 'package:serverdeck/profiles/recovery_view.dart';
import 'package:serverdeck/settings/settings_form.dart';
import 'package:serverdeck/settings/settings_view.dart' as settings;
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/shell/private_session.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck/ui/deck_components.dart';
import 'package:serverdeck_protocol/models.dart';

import '../contract/profile_controller_test.dart' as fixture;
import 'design_host.dart' show loadDesignFonts;
import 'design_privacy_bodies.dart';
import 'design_state_capture.dart';

const _oldName = 'PRIVATE retired root profile';
const _oldAddress = 'private-retired.example';
const _draft = 'PRIVATE unsaved profile draft';
const _password = 'PRIVATE unsaved masked password';
const _receiptId = '55555555-5555-4555-8555-555555555555';
const _nextGeneration = '66666666-6666-4666-8666-666666666666';
const _newName = 'Current authorized root profile';

const _local = <String, String>{
  'empty-root-create': '04-empty-workspace',
  'profile-root': '05-server-list',
  'create-root': '07-profile-create',
  'edit-root': '08-profile-edit',
  'delete-root': '09-profile-delete',
  'credential-nested': '12-credential-input',
  'mutation-in-form': '13-mutation-conflict',
  'mutation-pending': '13-mutation-conflict',
  'history-root': '31-recent-operations',
  'settings-root': '84-settings',
  'settings-form-root': '85-settings-form',
  'credential-picker': '12-credential-input',
};

enum _Loss {
  unavailable,
  storageBlocked,
  incompatible,
  connecting,
  disconnected,
  closed,
  unauthorized,
  rapidRecovery,
}

class _Variant {
  const _Variant(this.size, this.scale, this.dark);
  final Size size;
  final double scale;
  final bool dark;
  String get theme => dark ? 'dark' : 'light';
  String get suffix =>
      '$theme-${size.width.toInt()}x${size.height.toInt()}-${(scale * 100).toInt()}';
}

/// Actual root/private-epoch journeys. Public remote bodies are rendered in a
/// real authorized showMotionDialog, without a fake native/TrustedApiClient.
/// Callback counters prove only this presentation boundary. The local model,
/// form and history use FoundationApp's actual ProfileController and routes.
void registerDesignPrivacyStateCases({bool fullAdaptive = false}) {
  setUpAll(loadDesignFonts);
  final sizes = fullAdaptive
      ? const [Size(1100, 760), Size(800, 600), Size(390, 800), Size(360, 800)]
      : const [Size(1100, 760), Size(360, 800)];
  final variants = <_Variant>[
    for (final dark in [false, true])
      for (final size in sizes)
        for (final scale
            in fullAdaptive ? [1.0, 2.0] : [size.width == 1100 ? 1.0 : 2.0])
          _Variant(size, scale, dark),
  ];
  final families = [..._local.keys, ...DesignPrivacyRemoteBody.families];
  for (final variant in variants) {
    for (final family in families) {
      final origin = _local[family] ?? _remoteOrigin(family);
      final id = 'state-$origin-localUnavailable';
      for (final loss in _Loss.values) {
        testWidgets('[$id] privacy-$family-${loss.name}-${variant.suffix}', (
          tester,
        ) async {
          final root = await _Root.open(tester, family, variant);
          try {
            await root.prepareBody();
            final probe = root.probe();
            root.expectOwnMarkers();
            final epoch = root.session.epoch;
            final fixtureSource = jsonEncode(root.client.fixtureStore);
            final before = root.counts;
            final refreshGate = Completer<void>();
            root.client.refreshGate = refreshGate;
            final refresh = root.model.refresh();
            final afterAllowedRead = root.client.refreshes;
            Completer<ApiReply>? historyGate;
            if (family == 'history-root') {
              historyGate = Completer<ApiReply>();
              root.client.recentGate = historyGate;
              await _click(tester, 'Обновить список');
              expect(root.client.recentReads, before['recentReads']! + 1);
            }
            final picker = root.picker;
            root.retire(loss);
            await tester.pump();
            root.expectRetired();
            probe.expectUnmounted();
            expect(root.session.epoch, greaterThan(epoch));
            await tester.pumpAndSettle();
            if (probe.route case final route?) expect(route.isActive, isFalse);

            if (root.client.mutationGate case final gate?
                when !gate.isCompleted) {
              // One prior explicit save is already in flight. Its late durable
              // receipt must hit the real disposed MutationController guard.
              gate.complete(root.client.mutationReply());
            }

            // Complete real allowed local read/picker work after owner loss.
            refreshGate.complete();
            await refresh;
            root.client.refreshGate = null;
            if (historyGate != null) {
              historyGate.complete(root.client.historyReply());
              root.client.recentGate = null;
            }
            if (picker != null && !picker.isCompleted) {
              if (loss == _Loss.unauthorized || loss == _Loss.closed) {
                picker.completeError(
                  StateError('PRIVATE retired selected path'),
                );
              } else {
                picker.complete('PRIVATE late picked key must not render');
              }
            }
            await tester.pumpAndSettle();
            root.expectRetired();
            // StartupRecovery._read accepts the pending history reply while
            // bootstrap remains ready after unauthorized. ProfileController
            // has cleared its DTO, so the existing readback requests one
            // model.refresh. ModelClient publishes no DTO from that Future;
            // the read remains controlled until our authorized recovery below.
            final historyReadback =
                family == 'history-root' && loss == _Loss.unauthorized ? 1 : 0;
            expect(root.client.refreshes, afterAllowedRead + historyReadback);
            root.expectEffectsUnchanged(before);
            await root.checkpoint(id, '$family-${_slug(loss.name)}-retired', [
              'Actual $family body and its own markers are absent from render/offstage/semantics/tooltips',
              probe.route != null
                  ? 'Production body Elements/State and its actual private modal route retired; delayed allowed work did not restore them'
                  : 'Production inline body Elements/State retired; this journey has no private modal route',
              'Zero additional UI mutation/connect/apply/consent callbacks',
              if (historyReadback == 1) 'Existing StartupRecovery._read -> !loaded -> model.refresh adds exactly one owner readback after the delayed receipt; it publishes no snapshot in this seam',
            ]);

            if (loss == _Loss.closed) {
              root.client.events.add(root.snapshot(current: true));
              await tester.pumpAndSettle();
              expect(root.session.authorized, isFalse);
              root.expectRetired();
              root.client.visibility.add(ClientConnectionState.connected);
            }
            root.client.generationId = _nextGeneration;
            root.bootstrap.show(ReadinessState.ready);
            final beforeLateSnapshot = root.model.profiles;
            root.client.events.add(root.snapshot(revision: '99'));
            await tester.pumpAndSettle();
            expect(root.model.profiles, same(beforeLateSnapshot));
            root.expectRetired();
            root.client.events.add(
              root.snapshot(
                current: true,
                generation: _nextGeneration,
                revision: '3',
              ),
            );
            await tester.pumpAndSettle();
            expect(root.session.authorized, isTrue);
            expect(root.model.loaded, isTrue);
            expect(root.model.selected?.name, _newName);
            root.expectRetired();
            expect(probe.elements.every((element) => !element.mounted), isTrue);
            expect(
              jsonEncode(root.client.fixtureStore),
              fixtureSource,
              reason: 'Only in-memory fixture source non-mutation; not disk persistence',
            );
            root.expectEffectsUnchanged(before);
            final readyCycles = switch (loss) {
              _Loss.unavailable ||
              _Loss.storageBlocked ||
              _Loss.incompatible => 1,
              _ => 0,
            };
            expect(
              root.client.refreshes,
              afterAllowedRead + historyReadback + readyCycles,
            );
            expect(
              root.client.recentReads,
              before['recentReads']! +
                  readyCycles +
                  (historyGate == null ? 0 : 1),
            );
            if (root.secretState case final old?) {
              expect(old.mounted, isFalse);
              expect(old.password.text, isEmpty);
              expect(old.keyInput.text, isEmpty);
              expect(old.passphrase.text, isEmpty);
            }
            await root.checkpoint(id, '$family-${_slug(loss.name)}-recovered', [
              'Current authorized generation accepted; old-generation reply ignored',
              'Retired production body, secret/consent and old markers did not return',
              'In-memory fixture source unchanged; expected owner reads counted separately',
            ]);
            expect(tester.takeException(), isNull);
          } finally {
            await root.close();
          }
        });
      }
      testWidgets('[$id] privacy-$family-positive-${variant.suffix}', (
        tester,
      ) async {
        final root = await _Root.open(tester, family, variant);
        try {
          await root.prepareBody();
          final probe = root.probe();
          root.expectOwnMarkers();
          final before = root.counts;
          final epoch = root.session.epoch;
          final secret = root.secretState;
          final settingsDraft = family == 'settings-form-root'
              ? tester
                    .widget<MotionDropdown<bool>>(
                      find.byWidgetPredicate(
                        (widget) => widget is MotionDropdown<bool>,
                      ),
                    )
                    .initialValue
              : null;
          final next = _Variant(
            variant.size.width == 1100
                ? const Size(360, 800)
                : const Size(1100, 760),
            variant.scale == 1 ? 2 : 1,
            !variant.dark,
          );
          root.variant = next;
          root.applyPlatform();
          root.client.events.add(
            root.snapshot(
              empty: family == 'empty-root-create' || family == 'create-root',
            ),
          );
          await tester.pumpAndSettle();
          root.expectOwnMarkers();
          expect(root.session.authorized, isTrue);
          expect(root.session.epoch, epoch);
          probe.expectRetained(root.bodyFinder);
          if (secret != null) {
            expect(root.secretState, same(secret));
            expect(
              secret.password.text,
              family == 'credential-picker' ? isEmpty : _password,
            );
            expect(secret.revealed, isFalse);
          }
          if (settingsDraft != null) {
            expect(
              tester
                  .widget<MotionDropdown<bool>>(
                    find.byWidgetPredicate(
                      (widget) => widget is MotionDropdown<bool>,
                    ),
                  )
                  .initialValue,
              settingsDraft,
            );
          }
          expect(root.counts, before);
          await root.checkpoint(
            id,
            '$family-positive-${variant.suffix}-retained',
            [
              probe.route != null
                  ? 'Ordinary theme/resize retained actual body Element/State, modal route and draft'
                  : 'Ordinary theme/resize retained actual inline body Element/State; this journey has no private modal route',
              'Same authorized UI epoch, no additional reads or effects',
            ],
          );
          expect(tester.takeException(), isNull);
        } finally {
          await root.close();
        }
      });
    }
  }
}

String _remoteOrigin(String family) {
  const extras = {
    'revoke-trust': '10-host-trust',
    'revoke-executor': '40-executor-binding',
    'delegation-chooser': '39-delegations',
    'delegation-editor': '39-delegations',
    'revoke-grant': '36-ai-grants',
    'archive-profile': '32-automation-profiles',
  };
  const origins = {
    'server-overview': '06-server-overview',
    'trust': '10-host-trust',
    'software-catalog': '16-install-catalog',
    'recipe-detail': '17-recipe-detail',
    'preflight': '18-install-preflight',
    'plan-decision': '19-plan-approval',
    'logs': '22-server-logs',
    'log-record': '23-log-record',
    'job-list': '27-job-list',
    'job-detail': '28-job-detail',
    'job-unknown': '29-job-unknown',
    'job-cancel': '30-job-cancel',
    'automation-profiles': '32-automation-profiles',
    'authoring': '33-profile-authoring',
    'revisions': '34-profile-revisions',
    'parameters': '35-plan-parameters',
    'grants': '36-ai-grants',
    'grant-editor': '37-ai-grant-form',
    'mcp-config': '38-mcp-client-config',
    'delegations-list': '39-delegations',
    'executor': '40-executor-binding',
    'invalidated-plan': '94-plan-invalidated',
  };
  return extras[family] ?? origins[family]!;
}

class _Probe {
  _Probe(this.element, this.elements, this.state, this.route);
  final Element element;
  final List<Element> elements;
  final State? state;
  final ModalRoute? route;
  void expectUnmounted() {
    expect(element.mounted, isFalse);
    expect(elements.where((element) => element.mounted), isEmpty);
    if (state case final old?) expect(old.mounted, isFalse);
  }

  void expectRetained(Finder finder) {
    expect(finder.evaluate().single, same(element));
    expect(element.mounted, isTrue);
    if (state case final old?) expect(old.mounted, isTrue);
    if (route case final old?) {
      expect(ModalRoute.of(element), same(old));
      expect(old.isActive, isTrue);
    }
  }
}

class _Root {
  _Root(
    this.tester,
    this.family,
    this.variant,
    this.client,
    this.bootstrap,
    this.semantics,
  );
  final WidgetTester tester;
  final String family;
  _Variant variant;
  final _Client client;
  final _Bootstrap bootstrap;
  final SemanticsHandle semantics;
  late final ProfileController model;
  DesignPrivacyRemoteBody? remote;
  Completer<String?>? picker;
  CredentialInputState? secretState;
  Type bodyType = ProfileList;
  final _pickerKey = GlobalKey<CredentialInputState>();
  Future<void>? route;
  int pickerCalls = 0, pickerSubmits = 0;
  final List<String> _markers = [];
  Finder get bodyFinder => find.byType(bodyType, skipOffstage: false);
  PrivateSessionScope get session =>
      tester.widget<PrivateSessionScope>(find.byType(PrivateSessionScope));
  Map<String, int> get counts => {
    'refreshes': client.refreshes,
    'recentReads': client.recentReads,
    'mutations': client.mutations,
    'statusReads': client.statusReads,
    'connections': client.connections,
    'otherReads': client.otherReads,
    'retries': bootstrap.retries,
    'pickerCalls': pickerCalls,
    'pickerSubmits': pickerSubmits,
    ...?remote?.effects,
  };

  static Future<_Root> open(
    WidgetTester tester,
    String family,
    _Variant variant,
  ) async {
    final semantics = tester.ensureSemantics();
    final client = _Client();
    final bootstrap = _Bootstrap(client)..show(ReadinessState.ready);
    final root = _Root(tester, family, variant, client, bootstrap, semantics);
    root.applyPlatform();
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      RepaintBoundary(
        key: designStateCaptureBoundaryKey,
        child: FoundationApp(bootstrap: bootstrap),
      ),
    );
    client.events.add(
      root.snapshot(
        empty: family == 'empty-root-create' || family == 'create-root',
      ),
    );
    await tester.pumpAndSettle();
    root.model = tester
        .widget<ProfileList>(find.byType(ProfileList))
        .controller;
    expect(root.model.loaded, isTrue);
    expect(client.refreshes, 1);
    expect(client.recentReads, 1);
    return root;
  }

  void applyPlatform() {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = variant.size;
    tester.platformDispatcher.platformBrightnessTestValue = variant.dark
        ? Brightness.dark
        : Brightness.light;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    tester.platformDispatcher.textScaleFactorTestValue = variant.scale;
  }

  ClientSnapshot snapshot({
    bool current = false,
    bool empty = false,
    String revision = '1',
    String generation = fixture.fixtureGeneration,
  }) {
    final row = Map<String, Object?>.of(client.fixtureStore.single)
      ..['name'] = current ? _newName : _oldName
      ..['address'] = current ? 'current-authorized.example' : _oldAddress;
    return ClientSnapshot(
      ApiReply(generation, {
        'storeRevision': revision,
        'profiles': empty ? <Object?>[] : [row],
      }),
      ApiReply(generation, {
        'storeRevision': revision,
        'settings': SettingsView(
          theme: variant.dark ? ThemePreference.dark : ThemePreference.light,
          reduceMotion: true,
          selectedProfileId: empty ? null : fixture.profileId,
        ).toJson(),
      }),
    );
  }

  Future<void> prepareBody() async {
    if (!_local.containsKey(family)) {
      remote = DesignPrivacyRemoteBody(family, model: model);
      bodyType = remote!.productionType;
      _markers.addAll(remote!.markers);
      route = showMotionDialog<void>(
        context: tester.element(find.byType(FoundationShell)),
        builder: (dialog) => remote!.build(dialog),
      );
      await tester.pumpAndSettle();
      if (family == 'software-catalog' || family == 'recipe-detail') {
        // The canonical catalog starts with loaded rows. Reach the selected
        // descriptor through its actual local action before probing retirement.
        final section = tester.widget<AutomationRecipesSection>(bodyFinder);
        final rows = (section.catalog['recipes']! as List)
            .cast<Map<String, Object?>>();
        expect(rows, isNotEmpty);
        final beforeSelection = Map<String, int>.of(counts);
        final loaded = find.descendant(
          of: bodyFinder,
          matching: find.text(automationRecipeTitle(rows.first)),
        );
        expect(loaded, findsOneWidget);
        await tester.ensureVisible(loaded);
        await tester.tap(loaded);
        await tester.pumpAndSettle();
        expect(
          tester
              .state<AutomationRecipesSectionState>(bodyFinder)
              .selectedRecipeTitle,
          automationRecipeTitle(rows.first),
        );
        expect(
          counts,
          beforeSelection,
          reason: 'Opening a loaded recipe is local and must not create a plan or read',
        );
      }
      await _expandAll(tester, bodyFinder);
      if (family == 'software-catalog' || family == 'recipe-detail') {
        final advanced = find.descendant(
          of: bodyFinder,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is AutomationJsonView &&
                widget.title ==
                    'Лицензии, начальные настройки и точные условия',
          ),
        );
        expect(advanced, findsOneWidget);
        final payload = tester.widget<EditableText>(
          find.descendant(of: advanced, matching: find.byType(EditableText)),
        );
        expect(payload.readOnly, isTrue);
        for (final marker in _markers) {
          expect(payload.controller.text, contains(marker));
        }
      }
      return;
    }
    if (family == 'credential-picker') {
      picker = Completer<String?>();
      bodyType = CredentialInput;
      _markers.add('PRIVATE pending picker passphrase');
      route = showMotionDialog<void>(
        context: tester.element(find.byType(FoundationShell)),
        builder: (dialog) => DeckDialogLayout(
          title: 'PRIVATE pending key editor',
          child: CredentialInput(
            key: _pickerKey,
            creating: false,
            enabled: true,
            readReadyEpoch: () => session.authorized ? session.epoch : null,
            pickKey: () {
              pickerCalls++;
              return picker!.future;
            },
            onSubmit: () => pickerSubmits++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _click(tester, 'Сохранить существующий');
      await _click(tester, 'Новый приватный ключ');
      await tester.enterText(
        find.byKey(const ValueKey('credential-passphrase')),
        'PRIVATE pending picker passphrase',
      );
      await _click(tester, 'Выбрать файл ключа');
      secretState = _pickerKey.currentState;
      expect(secretState!.picking, isTrue);
      return;
    }
    if (family == 'settings-root' || family == 'settings-form-root') {
      await _click(tester, 'Настройки');
      bodyType = settings.SettingsView;
      _markers.add(_oldName);
      if (family == 'settings-form-root') {
        await _click(tester, 'Изменить настройки');
        bodyType = SettingsForm;
        final motion = find.byWidgetPredicate(
          (widget) => widget is MotionDropdown<bool>,
        );
        await tester.ensureVisible(motion);
        await tester.tap(motion);
        await tester.pumpAndSettle();
        await _click(tester, 'Выключено');
        expect(
          tester.widget<MotionDropdown<bool>>(motion).initialValue,
          isFalse,
        );
      }
      return;
    }
    if (family == 'history-root') {
      await tester.tap(find.byTooltip('Недавние подтверждённые операции'));
      await tester.pumpAndSettle();
      bodyType = RecentOperationsView;
      _markers.add(_receiptId);
      expect(
        find.byKey(const RecentOperationReceiptKey(_receiptId)),
        findsOneWidget,
      );
      return;
    }
    if (family == 'empty-root-create' || family == 'create-root') {
      expect(model.profiles, isEmpty);
      expect(find.text('Все серверы.\nОдин центр управления.'), findsOneWidget);
      await _click(tester, 'Добавить сервер');
      bodyType = ProfileForm;
      await tester.enterText(
        find.byKey(const ValueKey('profile-address')),
        _oldAddress,
      );
      await tester.enterText(
        find.byKey(const ValueKey('profile-user')),
        'private-user',
      );
    } else {
      if (family == 'profile-root') {
        bodyType = ProfileList;
        _markers.addAll([_oldName, _oldAddress]);
        return;
      }
      await tester.ensureVisible(find.byTooltip('Действия профиля $_oldName'));
      await tester.tap(find.byTooltip('Действия профиля $_oldName'));
      await tester.pumpAndSettle();
      await _click(
        tester,
        family == 'delete-root' ? 'Удалить профиль' : 'Редактировать профиль',
      );
      bodyType = family == 'delete-root' ? ProfileDelete : ProfileForm;
      if (family == 'delete-root') {
        _markers.addAll([_oldName, _oldAddress]);
        return;
      }
    }
    await tester.enterText(find.byKey(const ValueKey('profile-name')), _draft);
    await _click(
      tester,
      family == 'empty-root-create' || family == 'create-root'
          ? 'Без секрета / удалить'
          : 'Сохранить существующий',
    );
    await _click(tester, 'Новый пароль');
    final passwordField = find.byKey(const ValueKey('credential-password'));
    await tester.ensureVisible(passwordField);
    await tester.enterText(passwordField, _password);
    await tester.pumpAndSettle();
    secretState = tester.state<CredentialInputState>(
      find.byType(CredentialInput),
    );
    expect(secretState!.password.text, _password);
    expect(secretState!.revealed, isFalse);
    final editable = tester.widget<EditableText>(
      find.descendant(of: passwordField, matching: find.byType(EditableText)),
    );
    expect(editable.obscureText, isTrue);
    _markers.addAll([_draft, _oldAddress]);
    if (family == 'mutation-in-form' || family == 'mutation-pending') {
      if (family == 'mutation-pending')
        client.mutationGate = Completer<ApiReply>();
      await _click(tester, 'Сохранить');
      expect(client.mutations, 1);
      if (family == 'mutation-pending') {
        expect(find.text('Сохранение'), findsWidgets);
      } else {
        expect(
          find.text(
            'Профиль изменён другим окном. Введённые данные сохранены в форме',
          ),
          findsWidgets,
        );
      }
    }
  }

  _Probe probe() {
    expect(bodyFinder, findsOneWidget);
    final element = bodyFinder.evaluate().single;
    final state = element is StatefulElement ? element.state : null;
    final elements = <Element>[element];
    void collect(Element child) {
      elements.add(child);
      child.visitChildren(collect);
    }

    element.visitChildren(collect);
    final candidate = ModalRoute.of(element);
    return _Probe(
      element,
      elements,
      state,
      candidate is DialogRoute ? candidate : null,
    );
  }

  void expectOwnMarkers() {
    expect(_markers, isNotEmpty);
    final descendants = <Widget>[];
    void collect(Element element) {
      descendants.add(element.widget);
      element.visitChildren(collect);
    }

    for (final element in bodyFinder.evaluate()) collect(element);
    final text = descendants
        .map(
          (widget) => switch (widget) {
            Text() => widget.data ?? widget.textSpan?.toPlainText() ?? '',
            RichText() => widget.text.toPlainText(),
            EditableText() => widget.controller.text,
            Tooltip() =>
              widget.message ?? widget.richMessage?.toPlainText() ?? '',
            _ => '',
          },
        )
        .join('\n');
    for (final marker in _markers) {
      expect(
        text,
        contains(marker),
        reason:
            'The actual $family production body must display its own marker before retirement',
      );
    }
  }

  void expectRetired() {
    final markers = {
      ..._markers,
      _oldName,
      _oldAddress,
      _draft,
      _password,
      'PRIVATE late picked key must not render',
      'PRIVATE pending key editor',
      'PRIVATE retired selected path',
    };
    final widgets = find
        .byWidgetPredicate((_) => true, skipOffstage: false)
        .evaluate()
        .map((e) => e.widget);
    final text = widgets
        .map(
          (widget) => switch (widget) {
            Text() => widget.data ?? widget.textSpan?.toPlainText() ?? '',
            RichText() => widget.text.toPlainText(),
            EditableText() => widget.controller.text,
            Tooltip() =>
              widget.message ?? widget.richMessage?.toPlainText() ?? '',
            _ => '',
          },
        )
        .join('\n');
    final trees = <String>[];
    void collect(PipelineOwner owner) {
      final node = owner.semanticsOwner?.rootSemanticsNode;
      if (node != null) trees.add(node.toStringDeep());
      owner.visitChildren(collect);
    }

    collect(tester.binding.rootPipelineOwner);
    expect(trees, isNotEmpty);
    for (final marker in markers) {
      expect(
        text,
        isNot(contains(marker)),
        reason: '$family private render/offstage/editor/tooltip retired',
      );
      expect(
        trees.join('\n'),
        isNot(contains(marker)),
        reason: '$family private semantics retired',
      );
    }
  }

  void expectEffectsUnchanged(Map<String, int> before) {
    final after = counts;
    for (final key in before.keys.where(
      (key) => key != 'refreshes' && key != 'recentReads',
    )) {
      expect(
        after[key],
        before[key],
        reason: 'Retirement/recovery must not invoke $key',
      );
    }
  }

  void retire(_Loss loss) {
    switch (loss) {
      case _Loss.unavailable:
        bootstrap.show(ReadinessState.unavailable);
      case _Loss.storageBlocked:
        bootstrap.show(ReadinessState.storageBlocked);
      case _Loss.incompatible:
        bootstrap.show(ReadinessState.incompatible);
      case _Loss.connecting:
        client.visibility.add(ClientConnectionState.connecting);
      case _Loss.disconnected:
        client.visibility.add(ClientConnectionState.disconnected);
      case _Loss.closed:
        client.visibility.add(ClientConnectionState.closed);
      case _Loss.unauthorized:
        client.readErrors.add(ErrorCode.unauthorized);
      case _Loss.rapidRecovery:
        client.readErrors.add(ErrorCode.unauthorized);
        client.events.add(snapshot(current: true, revision: '2'));
    }
  }

  Future<void> checkpoint(
    String id,
    String phase,
    List<String> assertions,
  ) => captureDesignState(
    tester,
    family: 'privacy',
    caseIds: [id],
    phase: phase,
    theme: variant.theme,
    scale: variant.scale,
    counters: counts,
    assertions: assertions,
    scope:
        'privateEpochComposition: actual FoundationApp epoch and actual $family body',
    limitations: [
      'Synthetic ModelClient and production UI composition; no native transport/SSH/TrustedApiClient or disk persistence proof.',
      if (remote != null) 'Remote body is opened via actual authorized showMotionDialog; counters prove body callbacks, not ServerPanel/AutomationPanel RPC dispatch.',
      if (family == 'credential-picker') 'Existing CredentialInput pickKey callback seam; not ProfileForm default Windows FFI picker.',
      'Test-owned external input controllers are disposed by test owner after route retirement, not falsely attributed to app lifecycle.',
    ],
  );

  Future<void> close() async {
    if (picker != null && !picker!.isCompleted) picker!.complete(null);
    if (client.refreshGate != null && !client.refreshGate!.isCompleted)
      client.refreshGate!.complete();
    if (client.recentGate != null && !client.recentGate!.isCompleted)
      client.recentGate!.complete(client.historyReply());
    final shell = find.byType(FoundationShell);
    if (shell.evaluate().isNotEmpty) {
      Navigator.of(tester.element(shell)).popUntil((route) => route.isFirst);
      await tester.pumpAndSettle();
    }
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    if (client.mutationGate case final gate? when !gate.isCompleted)
      gate.complete(client.mutationReply());
    if (route != null) await route;
    remote?.dispose();
    await bootstrap.close();
    await client.visibility.close();
    await client.events.close();
    await client.readErrors.close();
  }
}

Future<void> _click(WidgetTester tester, String label) async {
  await tester.pumpAndSettle();
  final candidates = label == 'Настройки'
      ? find.byKey(const ValueKey('foundation-navigation-settings'))
      : find.text(label);
  if (candidates.evaluate().isEmpty &&
      find.byType(ProfileList).evaluate().isNotEmpty) {
    // ProfileList is a real lazy ListView. At200% the header alone can fill
    // the phone viewport, so the profile row must first be built by scrolling.
    await tester.scrollUntilVisible(
      candidates,
      200,
      scrollable: find
          .descendant(
            of: find.byType(ProfileList),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  final text = candidates.last;
  await tester.ensureVisible(text);
  await tester.pumpAndSettle();
  await tester.tap(text);
  await tester.pumpAndSettle();
}

Future<void> _expandAll(WidgetTester tester, Finder body) async {
  for (var pass = 0; pass < 5; pass++) {
    var changed = false;
    for (final element
        in find
            .descendant(of: body, matching: find.byType(ExpansionTile))
            .evaluate()
            .toList()) {
      if (!element.mounted) continue;
      final tile = element.widget as ExpansionTile;
      final title = find.byWidget(tile.title);
      final expanded = ExpansibleController.of(tester.element(title))
          .isExpanded;
      if (!expanded) {
        await tester.ensureVisible(title);
        await tester.tap(title);
        await tester.pumpAndSettle();
        changed = true;
      }
    }
    if (!changed) return;
  }
}

String _slug(String value) =>
    value.replaceAllMapped(RegExp('[A-Z]'), (m) => '-${m[0]!.toLowerCase()}');

class _Bootstrap extends fixture.ModelBootstrap {
  _Bootstrap(super.client);
  int retries = 0;
  @override
  Future<void> retry() async {
    retries++;
  }
}

class _Client extends fixture.ModelClient {
  final visibility = StreamController<ClientConnectionState>.broadcast(
    sync: true,
  );
  final fixtureStore = List<Map<String, Object?>>.unmodifiable([
    Map<String, Object?>.unmodifiable({
      ...((fixture.snapshot().profiles.result['profiles'] as List).single
          as Map<String, Object?>),
      'name': _oldName,
      'address': _oldAddress,
    }),
  ]);
  int mutations = 0,
      statusReads = 0,
      connections = 0,
      recentReads = 0,
      otherReads = 0;
  Completer<ApiReply>? recentGate;
  Completer<ApiReply>? mutationGate;
  @override
  Stream<ClientConnectionState> get states => visibility.stream;
  @override
  Future<void> connect() async {
    connections++;
    throw StateError('No native connection in privacy fixture');
  }

  @override
  Future<ApiReply> mutate(MutationIntent intent) async {
    mutations++;
    if (mutationGate != null) return mutationGate!.future;
    throw const LocalApiException(ErrorCode.revisionConflict);
  }

  ApiReply mutationReply() => ApiReply(generationId, {
    'entityId': fixture.profileId,
    'entityRevision': '2',
    'storeRevision': '2',
    'deleted': false,
  });

  @override
  Future<ApiReply> mutationStatus(MutationIntent intent) async {
    statusReads++;
    throw StateError('No implicit result query');
  }

  ApiReply historyReply() => ApiReply(generationId, {
    'receipts': [
      {
        'requestId': _receiptId,
        'operation': 'profiles.update',
        'profileId': fixture.profileId,
        'committedAt': '2026-10-25T09:00:00.000Z',
        'result': {
          'entityId': fixture.profileId,
          'entityRevision': '1',
          'storeRevision': '1',
          'deleted': false,
        },
      },
    ],
    'truncated': false,
  });
  @override
  Future<ApiReply> read(
    ApiMethod method, [
    Map<String, Object?> params = const {},
  ]) async {
    if (method == ApiMethod.mutationsRecent) {
      recentReads++;
      return recentGate?.future ?? historyReply();
    }
    otherReads++;
    throw StateError('Unconfigured private fixture read');
  }
}
