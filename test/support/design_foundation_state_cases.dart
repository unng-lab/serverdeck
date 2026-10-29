import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/profiles/credential_input.dart';
import 'package:serverdeck/profiles/mutation_controller.dart';
import 'package:serverdeck/profiles/mutation_status.dart';
import 'package:serverdeck/profiles/profile_delete.dart';
import 'package:serverdeck/profiles/profile_form.dart';
import 'package:serverdeck/profiles/profile_list.dart';
import 'package:serverdeck/profiles/recovery_view.dart';
import 'package:serverdeck/settings/settings_form.dart';
import 'package:serverdeck/settings/settings_view.dart' as settings;
import 'package:serverdeck/shell/error_view.dart';
import 'package:serverdeck/servers/server_compositions.dart';
import 'package:serverdeck/shell/readiness_view.dart' as readiness;
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck/ui/deck_components.dart';
import 'package:serverdeck/ui/deck_page.dart';
import 'package:serverdeck_protocol/models.dart';

import '../contract/profile_controller_test.dart' as model_fixture;
import 'design_host.dart' show loadDesignFonts;
import 'design_scenario_harness.dart';
import 'design_state_capture.dart';
import 'design_state_matrix.dart';

final _hostKey = GlobalKey<_StateHostState>();

class _StateHost extends StatefulWidget {
  const _StateHost({
    super.key,
    required this.child,
    required this.frame,
    required this.dark,
  });
  final Widget child;
  final _Frame frame;
  final bool dark;
  @override
  State<_StateHost> createState() => _StateHostState();
}

class _StateHostState extends State<_StateHost> {
  late bool dark = widget.dark;
  late double scale = widget.frame.scale;
  void restyle(bool nextDark, double nextScale) => setState(() {
    dark = nextDark;
    scale = nextScale;
  });
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: designStateCaptureBoundaryKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: Motion.theme(dark ? BrandTheme.dark : BrandTheme.light, true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Scaffold(body: widget.child),
    ),
  );
}

enum _Form {
  profileEdit('08-profile-edit', 'Сохранить'),
  profileDelete('09-profile-delete', 'Удалить профиль'),
  settings('85-settings-form', 'Сохранить настройки');

  const _Form(this.origin, this.submit);
  final String origin, submit;
  String get reload =>
      this == settings ? 'Перечитать настройки' : 'Перечитать профиль';
  String get pendingRead => this == settings
      ? 'Чтение актуальных настроек'
      : 'Чтение актуального профиля';
}

class _Frame {
  const _Frame(this.size, this.scale);
  final Size size;
  final double scale;
  String get suffix => '${size.width.toInt()}-${(scale * 100).toInt()}';
}

Finder _dialogText(String text) {
  final exact = find.descendant(
    of: find.byType(Dialog),
    matching: find.text(text),
  );
  if (text == 'Сохранить' && exact.evaluate().isEmpty)
    return find.descendant(
      of: find.byType(Dialog),
      matching: find.text('Сохранить без подключения'),
    );
  return exact;
}

Finder _dialogButton(String text) => find
    .ancestor(
      of: _dialogText(text),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    )
    .first;

Future<void> _click(
  WidgetTester tester,
  String label, {
  bool inDialog = true,
}) async {
  final text = inDialog ? _dialogText(label) : find.text(label);
  final button = find
      .ancestor(
        of: text,
        matching: find.byWidgetPredicate(
          (widget) => widget is ButtonStyleButton,
        ),
      )
      .first;
  await tester.pumpAndSettle();
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  expect(tester.widget<ButtonStyleButton>(button).onPressed, isNotNull);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _mount(
  WidgetTester tester,
  Widget child,
  _Frame frame,
  bool dark,
) async {
  tester.view.physicalSize = frame.size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    _StateHost(key: _hostKey, child: child, frame: frame, dark: dark),
  );
  await tester.pumpAndSettle();
}

Future<void> _keyboardClick(WidgetTester tester, String label) async {
  await tester.ensureVisible(_dialogButton(label));
  for (var tab = 0; tab < 24; tab++) {
    if (Focus.of(tester.element(_dialogText(label))).hasPrimaryFocus) break;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
  }
  expect(Focus.of(tester.element(_dialogText(label))).hasPrimaryFocus, isTrue);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

Future<void> _openForm(
  WidgetTester tester,
  DesignScenarioHarness harness,
  _Form form,
  _Frame frame,
  bool dark, {
  bool creating = false,
}) async {
  final initial = harness.profiles.profiles.single;
  await _mount(
    tester,
    Builder(
      builder: (context) => OutlinedButton(
        onPressed: () => showMotionDialog<void>(
          context: context,
          builder: (_) => switch (form) {
            _Form.profileEdit => ProfileForm(
              model: harness.profiles,
              initial: creating ? null : initial,
            ),
            _Form.profileDelete => ProfileDelete(
              model: harness.profiles,
              initial: initial,
            ),
            _Form.settings => SettingsForm(model: harness.profiles),
          },
        ),
        child: const Text('Открыть форму состояния'),
      ),
    ),
    frame,
    dark,
  );
  await _click(tester, 'Открыть форму состояния', inDialog: false);
  if (form == _Form.profileEdit) {
    await tester.enterText(
      find.byKey(const ValueKey('profile-name')),
      'Retained draft',
    );
    await tester.pumpAndSettle();
    if (creating) {
      await tester.enterText(
        find.byKey(const ValueKey('profile-address')),
        'example.test',
      );
      await tester.enterText(
        find.byKey(const ValueKey('profile-user')),
        'operator',
      );
      await tester.pumpAndSettle();
    }
  } else if (form == _Form.settings) {
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
  } else if (form == _Form.profileDelete) {
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
  }
}

void _expectDraft(WidgetTester tester, _Form form) {
  if (form == _Form.profileEdit) {
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('profile-name')))
          .controller!
          .text,
      'Retained draft',
    );
  } else if (form == _Form.settings) {
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
  } else {
    expect(_dialogText('Saved profile · 192.0.2.1:22'), findsOneWidget);
  }
}

void _expectDisabledSubmit(WidgetTester tester, _Form form) => expect(
  tester.widget<ButtonStyleButton>(_dialogButton(form.submit)).onPressed,
  isNull,
);

Finder _typedNotice(ErrorCode code) => find.descendant(
  of: find.byType(Dialog),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is ServerStatusBody &&
        widget.title == ReadErrorView.category(code),
  ),
);

void _expectTypedError(WidgetTester tester, ErrorCode code) {
  expect(
    _dialogText(ReadErrorView.category(code)),
    findsWidgets,
    reason: 'The actual open dialog must explain the guarded read error, not only disable its submit',
  );
  expect(_typedNotice(code), findsOneWidget);
  expect(
    tester.widget<ServerStatusBody>(_typedNotice(code)).tone,
    code == ErrorCode.timeout ? DeckTone.unavailable : DeckTone.warning,
  );
  if (code == ErrorCode.timeout) {
    expect(_dialogText('Повторить чтение'), findsOneWidget);
  } else {
    expect(_dialogText('Повторить чтение'), findsNothing);
    expect(_dialogText('Повторить проверку службы'), findsNothing);
    expect(
      _dialogText(
        code == ErrorCode.forbidden
            ? 'Проверьте права доступа к локальной службе.'
            : 'Используйте версию клиента с поддержкой этой функции.',
      ),
      findsOneWidget,
    );
  }
}

void _publishCurrent(DesignScenarioHarness harness) {
  final source = model_fixture.snapshot(revision: '3');
  harness.client.events.add(
    ClientSnapshot(
      ApiReply(harness.client.generationId, {
        ...source.profiles.result,
        'profiles': [
          {
            ...((source.profiles.result['profiles'] as List).single
                as Map<String, Object?>),
            'name': 'Current server value',
            'revision': '2',
          },
        ],
      }),
      ApiReply(harness.client.generationId, {
        ...source.settings.result,
        'settings': {
          ...(source.settings.result['settings'] as Map<String, Object?>),
          'revision': '2',
        },
      }),
    ),
  );
}

Future<void> _openHistory(
  WidgetTester tester,
  DesignScenarioHarness harness,
  _Frame frame,
  bool dark,
) async {
  await _mount(
    tester,
    RecentOperationsButton(recovery: harness.recovery),
    frame,
    dark,
  );
  final launcher = find.byTooltip('Недавние подтверждённые операции');
  expect(launcher, findsOneWidget);
  await tester.tap(launcher);
  await tester.pumpAndSettle();
  expect(find.byType(Dialog), findsOneWidget);
}

/// Actual widget/controller journeys. Registry descriptors alone never execute
/// these cases or establish runtime/native acceptance. No capture files are
/// written, and no production owner, trusted transport or authority is faked.
void registerDesignFoundationStateCases({bool fullAdaptive = false}) {
  setUpAll(loadDesignFonts);
  _registerRegistryCases(fullAdaptive);
  for (final dark in [false, true]) {
    for (final frame in const [
      _Frame(Size(360, 800), 2),
      _Frame(Size(1100, 760), 1),
    ]) {
      final suffix = '${dark ? 'dark' : 'light'}-${frame.suffix}';
      for (final form in _Form.values) {
        testWidgets(
          '[state-${form.origin}-loading] foundation-reload-${form.name}-$suffix',
          (tester) async {
            final harness = await DesignScenarioHarness.create();
            try {
              await _openForm(tester, harness, form, frame, dark);
              await _click(tester, form.submit);
              expect(harness.client.mutations, hasLength(1));
              expect(harness.client.statusRequests, isEmpty);
              // Conflict submission performs its existing automatic snapshot
              // refresh. Start the explicit-reload gate only after it finishes.
              harness.showReadError(ErrorCode.timeout);
              await tester.pumpAndSettle();
              final previousReload = tester
                  .widget<ButtonStyleButton>(_dialogButton(form.reload))
                  .onPressed!;
              final beforeTypedRead = harness.client.refreshes;
              harness.client.refreshGate = Completer<void>();
              await _keyboardClick(tester, 'Повторить чтение');
              expect(harness.client.refreshes, beforeTypedRead + 1);
              _expectDraft(tester, form);
              _expectDisabledSubmit(tester, form);
              expect(
                tester
                    .widget<ButtonStyleButton>(_dialogButton(form.reload))
                    .onPressed,
                isNull,
                reason: 'A typed read retry must disable the concurrent CAS read action',
              );
              final cas = _dialogButton(form.reload);
              await tester.ensureVisible(cas);
              await tester.tap(cas);
              previousReload();
              await tester.pumpAndSettle();
              expect(harness.client.refreshes, beforeTypedRead + 1);
              expect(harness.client.mutations, hasLength(1));
              await _checkpoint(
                tester,
                designStateCasesById['state-${form.origin}-loading']!,
                'baseline-mixed-read-pending',
                frame,
                dark,
                _counts(harness),
                [
                  'Typed timeout read retry retains conflict status and RAM draft',
                  'Keyboard starts typed retry; concurrent CAS read button and stale callback cannot start another read',
                  'One explicit read, one original mutation and zero status checks',
                ],
              );
              _publishCurrent(harness);
              harness.client.refreshGate!.complete();
              await tester.pumpAndSettle();
              _expectDraft(tester, form);
              expect(
                tester
                    .widget<ButtonStyleButton>(_dialogButton(form.reload))
                    .onPressed,
                isNotNull,
              );
              final before = harness.client.refreshes;
              harness.client.refreshGate = Completer<void>();
              await _click(tester, form.reload);
              expect(harness.client.refreshes, before + 1);
              _expectDraft(tester, form);
              _expectDisabledSubmit(tester, form);
              expect(
                _dialogText(form.pendingRead),
                findsOneWidget,
                reason: 'Explicit conflict reload must explain its pending read stage',
              );
              final pending = find.descendant(
                of: find.byType(Dialog),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is DeckStatus && widget.label == form.pendingRead,
                ),
              );
              expect(tester.widget<DeckStatus>(pending).pending, isTrue);
              expect(
                _dialogText(form.reload).evaluate().isEmpty ||
                    tester
                            .widget<ButtonStyleButton>(
                              _dialogButton(form.reload),
                            )
                            .onPressed ==
                        null,
                isTrue,
              );
              expect(harness.client.mutations, hasLength(1));
              await _checkpoint(
                tester,
                designStateCasesById['state-${form.origin}-loading']!,
                'baseline-reload-pending',
                frame,
                dark,
                _counts(harness),
                [
                  'Actual explicit CAS reload stage, disabled submit and retained draft',
                  'One explicit refresh after existing conflict read; one mutation and zero status checks',
                ],
              );
              _publishCurrent(harness);
              harness.client.refreshGate!.complete();
              await tester.pumpAndSettle();
              expect(_dialogText(form.pendingRead), findsNothing);
              expect(
                tester
                    .widget<ButtonStyleButton>(_dialogButton(form.submit))
                    .onPressed,
                form == _Form.profileDelete ? isNull : isNotNull,
              );
              expect(harness.client.mutations, hasLength(1));
              expect(harness.client.statusRequests, isEmpty);
              expect(harness.client.refreshes, before + 1);
              expect(tester.takeException(), isNull);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              await harness.close();
            }
          },
        );

        for (final code in [
          ErrorCode.timeout,
          ErrorCode.forbidden,
          ErrorCode.unsupported,
        ]) {
          final category = code == ErrorCode.forbidden
              ? 'denied'
              : code == ErrorCode.unsupported
              ? 'unsupported'
              : 'loading';
          testWidgets(
            '[state-${form.origin}-$category] foundation-read-error-${form.name}-${code.name}-$suffix',
            (tester) async {
              final harness = await DesignScenarioHarness.create();
              try {
                await _openForm(tester, harness, form, frame, dark);
                final credential = form == _Form.profileEdit
                    ? tester.state<CredentialInputState>(
                        find.byType(CredentialInput),
                      )
                    : null;
                final before = harness.client.refreshes;
                harness.showReadError(code);
                await tester.pumpAndSettle();
                _expectDraft(tester, form);
                _expectDisabledSubmit(tester, form);
                expect(harness.client.mutations, isEmpty);
                expect(harness.client.statusRequests, isEmpty);
                expect(harness.client.refreshes, before);
                _expectTypedError(tester, code);
                await _checkpoint(
                  tester,
                  designStateCasesById['state-${form.origin}-$category']!,
                  'baseline-initialized-${code.name}',
                  frame,
                  dark,
                  _counts(harness),
                  [
                    'Actual typed guarded error inside initialized production form',
                    'Draft retained, submit disabled and zero mutations/status checks',
                  ],
                );
                if (code == ErrorCode.timeout) {
                  harness.client.refreshGate = Completer<void>();
                  final previousRetry = tester
                      .widget<ButtonStyleButton>(
                        _dialogButton('Повторить чтение'),
                      )
                      .onPressed!;
                  await _keyboardClick(tester, 'Повторить чтение');
                  expect(harness.client.refreshes, before + 1);
                  _expectDraft(tester, form);
                  expect(
                    _dialogText(form.pendingRead),
                    findsOneWidget,
                    reason: 'Typed read retry must expose its own pending stage without replacing the RAM draft',
                  );
                  expect(
                    tester
                        .widget<ButtonStyleButton>(
                          _dialogButton('Повторить чтение'),
                        )
                        .onPressed,
                    isNull,
                  );
                  await _reveal(tester, _dialogButton('Повторить чтение'));
                  await tester.tap(_dialogButton('Повторить чтение'));
                  previousRetry();
                  await tester.pumpAndSettle();
                  await _passiveRebuilds(
                    tester,
                    frame,
                    dark,
                    () => _counts(harness),
                  );
                  expect(harness.client.refreshes, before + 1);
                  expect(harness.client.mutations, isEmpty);
                  await _checkpoint(
                    tester,
                    designStateCasesById['state-${form.origin}-loading']!,
                    'baseline-typed-read-pending',
                    frame,
                    dark,
                    _counts(harness),
                    [
                      'Precise read-retry pending stage distinct from CAS reload',
                      'Keyboard starts retry; disabled pointer/stale callback and theme/resize add no read or mutation; RAM draft retained',
                    ],
                  );
                  _publishCurrent(harness);
                  await tester.pumpAndSettle();
                  expect(
                    _dialogText(form.pendingRead),
                    findsOneWidget,
                    reason: 'A current snapshot must not end the local read-pending stage before its Future settles',
                  );
                  _expectDisabledSubmit(tester, form);
                  harness.client.refreshGate!.complete();
                  await tester.pumpAndSettle();
                  _expectDraft(tester, form);
                  expect(_typedNotice(code), findsNothing);
                  if (credential != null)
                    expect(
                      tester.state<CredentialInputState>(
                        find.byType(CredentialInput),
                      ),
                      same(credential),
                    );
                }
                expect(harness.client.mutations, isEmpty);
                expect(harness.client.statusRequests, isEmpty);
                expect(tester.takeException(), isNull);
              } finally {
                await tester.pumpWidget(const SizedBox.shrink());
                await harness.close();
              }
            },
          );
        }
      }

      for (final code in [
        ErrorCode.timeout,
        ErrorCode.forbidden,
        ErrorCode.unsupported,
      ]) {
        final category = code == ErrorCode.forbidden
            ? 'denied'
            : code == ErrorCode.unsupported
            ? 'unsupported'
            : 'loading';
        testWidgets(
          '[state-31-recent-operations-$category] foundation-history-error-${code.name}-$suffix',
          (tester) async {
            final harness = await DesignScenarioHarness.create();
            try {
              await _openHistory(tester, harness, frame, dark);
              final before = harness.client.reads.length;
              harness.client.recentGate = Completer<ApiReply>();
              await _click(tester, 'Обновить список');
              expect(harness.client.reads.length, before + 1);
              expect(
                _dialogText('Проверка текущих данных и недавних операций'),
                findsOneWidget,
              );
              harness.client.recentGate!.completeError(LocalApiException(code));
              await tester.pumpAndSettle();
              expect(harness.recovery.error, code);
              expect(harness.recovery.loaded, isFalse);
              expect(harness.client.mutations, isEmpty);
              expect(harness.client.statusRequests, isEmpty);
              _expectTypedError(tester, code);
              await _checkpoint(
                tester,
                designStateCasesById['state-31-recent-operations-$category']!,
                'baseline-history-${code.name}',
                frame,
                dark,
                _counts(harness),
                [
                  'Actual typed recent-read failure inside open history',
                  'No false empty or mutation/status request',
                ],
              );
              expect(
                _dialogText('Подтверждённых записей в выборке нет'),
                findsNothing,
              );
              if (code == ErrorCode.timeout) {
                harness.client.recentGate = Completer<ApiReply>();
                await _click(tester, 'Повторить чтение');
                expect(harness.client.reads.length, before + 2);
                harness.client.recentGate!.complete(
                  ApiReply(harness.client.generationId, {
                    'receipts': <Object?>[],
                    'truncated': false,
                  }),
                );
                await tester.pumpAndSettle();
                expect(
                  _dialogText('Подтверждённых записей в выборке нет'),
                  findsOneWidget,
                );
              }
              expect(harness.client.mutations, isEmpty);
              await _click(tester, 'Закрыть');
              expect(find.byType(Dialog), findsNothing);
              expect(tester.takeException(), isNull);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              await harness.close();
            }
          },
        );
      }

      for (final state in ['loading', 'empty', 'data']) {
        final id = state == 'empty'
            ? 'state-04-empty-workspace-successfulEmpty'
            : 'state-05-server-list-${state == 'loading' ? 'loading' : 'data'}';
        testWidgets('[$id] foundation-workspace-$state-$suffix', (
          tester,
        ) async {
          final harness = await DesignScenarioHarness.create(
            options: DesignFixtureOptions(
              loaded: state != 'loading',
              empty: state == 'empty',
            ),
          );
          try {
            await _mount(
              tester,
              ProfileList(controller: harness.profiles),
              frame,
              dark,
            );
            expect(
              find.text(
                state == 'loading'
                    ? 'Загрузка локальных профилей'
                    : state == 'empty'
                    ? 'Все серверы.\nОдин центр управления.'
                    : 'Saved profile',
              ),
              findsOneWidget,
            );
            if (state == 'loading') {
              expect(harness.profiles.loaded, isFalse);
              expect(
                find.text('Все серверы.\nОдин центр управления.'),
                findsNothing,
              );
            } else {
              expect(harness.profiles.loaded, isTrue);
              expect(
                harness.profiles.profiles.length,
                state == 'empty' ? 0 : 1,
              );
            }
            expect(harness.client.mutations, isEmpty);
            expect(harness.client.statusRequests, isEmpty);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await harness.close();
          }
        });
      }

      testWidgets(
        '[state-13-mutation-conflict-unknown] foundation-exact-retry-readback-$suffix',
        (tester) async {
          final harness = await DesignScenarioHarness.create();
          try {
            harness.client.mutationError = ErrorCode.timeout;
            await _openForm(tester, harness, _Form.profileEdit, frame, dark);
            await _click(tester, _Form.profileEdit.submit);
            expect(_dialogText('Сохранение не подтверждено'), findsOneWidget);
            final original = harness.client.mutations.single;
            await _click(tester, 'Проверить результат');
            expect(harness.client.statusRequests.single, same(original));
            expect(harness.client.mutations, hasLength(1));
            expect(
              _dialogText('Запрос не найден; можно повторить тот же запрос'),
              findsOneWidget,
            );
            harness.client.mutationGate = Completer<ApiReply>();
            await _click(tester, 'Повторить тот же запрос');
            expect(harness.client.mutations, hasLength(2));
            expect(harness.client.mutations.last, same(original));
            _expectDisabledSubmit(tester, _Form.profileEdit);
            expect(_dialogText('Сохранение'), findsOneWidget);
            expect(_dialogText('Повторить тот же запрос'), findsNothing);
            harness.client.mutationGate!.complete(
              ApiReply(harness.client.generationId, {
                'entityId': model_fixture.profileId,
                'entityRevision': '2',
                'storeRevision': '3',
                'deleted': false,
              }),
            );
            await tester.pumpAndSettle();
            expect(
              _dialogText('Сохранено; ожидается чтение актуального состояния'),
              findsOneWidget,
            );
            expect(
              find.byWidgetPredicate(
                (widget) =>
                    widget is Text &&
                    widget.key == const ValueKey('mutation-current-status') &&
                    widget.data == 'Сохранено',
              ),
              findsNothing,
            );
            _expectDraft(tester, _Form.profileEdit);
            _publishCurrent(harness);
            await tester.pumpAndSettle();
            expect(
              find.byWidgetPredicate(
                (widget) =>
                    widget is Text &&
                    widget.key == const ValueKey('mutation-current-status') &&
                    widget.data == 'Сохранено',
              ),
              findsOneWidget,
            );
            _expectDraft(tester, _Form.profileEdit);
            expect(harness.client.mutations, hasLength(2));
            expect(harness.client.statusRequests, hasLength(1));
            await _click(tester, 'Закрыть');
            expect(find.byType(Dialog), findsNothing);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await harness.close();
          }
        },
      );

      for (final empty in [true, false]) {
        final category = empty ? 'successfulEmpty' : 'incomplete';
        testWidgets(
          '[state-31-recent-operations-$category] foundation-history-${empty ? 'empty' : 'truncated20'}-$suffix',
          (tester) async {
            final harness = await DesignScenarioHarness.create();
            try {
              harness.publishSnapshot(revision: '20');
              harness.client.receipts = empty
                  ? []
                  : [
                      for (var revision = 20; revision >= 1; revision--)
                        {
                          'requestId':
                              '33333333-3333-4333-8333-${revision.toString().padLeft(12, '0')}',
                          'operation': 'settings.update',
                          'profileId': null,
                          'committedAt': '2026-10-11T00:00:00.000Z',
                          'result': {
                            'entityId': null,
                            'entityRevision': '$revision',
                            'storeRevision': '$revision',
                            'deleted': false,
                          },
                        },
                    ];
              harness.client.receiptsTruncated = !empty;
              await harness.recovery.reload();
              await _openHistory(tester, harness, frame, dark);
              if (empty) {
                expect(
                  _dialogText('Подтверждённых записей в выборке нет'),
                  findsOneWidget,
                );
              } else {
                expect(
                  _dialogText('Показана часть сохранённых записей'),
                  findsOneWidget,
                );
                expect(
                  find.byWidgetPredicate(
                    (widget) => widget.key is RecentOperationReceiptKey,
                  ),
                  findsNWidgets(20),
                );
                expect(
                  find.byKey(
                    const RecentOperationReceiptKey(
                      '33333333-3333-4333-8333-000000000020',
                    ),
                  ),
                  findsOneWidget,
                );
                expect(
                  find.byKey(
                    const RecentOperationReceiptKey(
                      '33333333-3333-4333-8333-000000000001',
                    ),
                  ),
                  findsOneWidget,
                );
                expect(
                  _dialogText('Подтверждённых записей в выборке нет'),
                  findsNothing,
                );
              }
              expect(harness.client.mutations, isEmpty);
              expect(harness.client.statusRequests, isEmpty);
              expect(
                harness.client.reads
                    .where((method) => method == ApiMethod.mutationsRecent)
                    .length,
                2,
              );
              await _click(tester, 'Закрыть');
              expect(tester.takeException(), isNull);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              await harness.close();
            }
          },
        );
      }
    }
  }
}

Map<String, Object?> _counts(DesignScenarioHarness harness) => {
  'mutations': harness.client.mutations.length,
  'statusRequests': harness.client.statusRequests.length,
  'snapshotRefreshes': harness.client.refreshes,
  'recentReads': harness.client.reads
      .where((method) => method == ApiMethod.mutationsRecent)
      .length,
};

Future<void> _passiveRebuilds(
  WidgetTester tester,
  _Frame frame,
  bool dark,
  Map<String, Object?> Function() counters,
) async {
  final before = counters();
  tester.view.physicalSize = frame.size.width == 360
      ? const Size(1100, 760)
      : const Size(360, 800);
  _hostKey.currentState!.restyle(!dark, frame.scale == 2 ? 1 : 2);
  await tester.pumpAndSettle();
  expect(
    counters(),
    before,
    reason: 'Theme/resize cannot initiate a new owner action',
  );
  tester.view.physicalSize = frame.size;
  _hostKey.currentState!.restyle(dark, frame.scale);
  await tester.pumpAndSettle();
  expect(counters(), before);
}

Future<void> _checkpoint(
  WidgetTester tester,
  DesignStateCase scenario,
  String phase,
  _Frame frame,
  bool dark,
  Map<String, Object?> counters,
  List<String> assertions, {
  String? scopeOverride,
}) => captureDesignState(
  tester,
  family: 'foundation',
  caseIds: [scenario.caseId],
  phase: '${scenario.caseId}-$phase'.toLowerCase(),
  theme: dark ? 'dark' : 'light',
  scale: frame.scale,
  counters: counters,
  assertions: assertions,
  scope: scopeOverride ?? scenario.scope.name,
  limitations: const [
    'Actual production presentation and local model/mutation owner through synthetic existing-protocol seams. This checkpoint does not establish native authority, persistence, transport, SSH or private-epoch acceptance.',
    'Case descriptors remain planned contracts; this capture and its enclosing test exit/independent visual review are separate evidence.',
  ],
);

void _registerRegistryCases(bool fullAdaptive) {
  final cases = designStateCases
      .where((scenario) => scenario.taskId == 'T034')
      .toList();
  // Every planned foundation case dispatches to its actual owning component;
  // an unsupported origin/category fails instead of falling back to a smoke.
  for (final scenario in cases) {
    for (final dark in [false, true]) {
      for (final frame
          in fullAdaptive
              ? const [
                  _Frame(Size(1100, 760), 1),
                  _Frame(Size(1100, 760), 2),
                  _Frame(Size(800, 600), 1),
                  _Frame(Size(800, 600), 2),
                  _Frame(Size(390, 800), 1),
                  _Frame(Size(390, 800), 2),
                  _Frame(Size(360, 800), 1),
                  _Frame(Size(360, 800), 2),
                ]
              : const [_Frame(Size(360, 800), 2), _Frame(Size(1100, 760), 1)]) {
        testWidgets(
          '[${scenario.caseId}] T034-owner-${dark ? 'dark' : 'light'}-${frame.suffix}',
          (tester) async {
            if ({
              '01-startup',
              '02-service-unavailable',
              '03-storage-blocked',
            }.contains(scenario.originId)) {
              await _registryReadiness(tester, scenario, frame, dark);
            } else if ({
              '04-empty-workspace',
              '05-server-list',
              '84-settings',
            }.contains(scenario.originId)) {
              await _registrySnapshot(tester, scenario, frame, dark);
            } else if (scenario.originId == '31-recent-operations') {
              await _registryHistory(tester, scenario, frame, dark);
            } else if ({
              '07-profile-create',
              '08-profile-edit',
              '09-profile-delete',
              '12-credential-input',
              '13-mutation-conflict',
              '85-settings-form',
            }.contains(scenario.originId)) {
              await _registryForm(tester, scenario, frame, dark);
            } else {
              fail('No actual T034 provider for ${scenario.caseId}');
            }
            expect(tester.takeException(), isNull, reason: scenario.caseId);
          },
        );
      }
    }
  }
}

void _expectReadinessTabs(WidgetTester tester, ReadinessState state) {
  final tabs = find.byType(DeckTabs);
  if (state == ReadinessState.storageBlocked) {
    expect(tabs, findsNothing);
    return;
  }
  final stages = const {
    ReadinessState.starting: 'Запуск',
    ReadinessState.recovering: 'Восстановление',
    ReadinessState.stopping: 'Завершение',
  };
  final labels = stages.containsKey(state)
      ? stages
      : const {
          ReadinessState.unavailable: 'Недоступна',
          ReadinessState.incompatible: 'Несовместимая версия',
        };
  final presentation = tester.widget<DeckTabs>(tabs);
  expect(presentation.labels, labels.values.toList());
  expect(presentation.selected, labels.keys.toList().indexOf(state));
  expect(
    presentation.onSelected,
    isNull,
    reason: 'The local service owns readiness; variant labels cannot synthesize a transition',
  );
  final controls = find.descendant(
    of: tabs,
    matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
  );
  expect(controls, findsNWidgets(labels.length));
  for (final element in controls.evaluate()) {
    expect((element.widget as ButtonStyleButton).onPressed, isNull);
  }
}

Future<void> _registryReadiness(
  WidgetTester tester,
  DesignStateCase scenario,
  _Frame frame,
  bool dark,
) async {
  var retries = 0;
  final base = scenario.originId == '01-startup'
      ? ReadinessState.starting
      : scenario.originId == '02-service-unavailable'
      ? ReadinessState.unavailable
      : ReadinessState.storageBlocked;
  final reasons = switch (scenario.category) {
    DesignStateCategory.validation => [ErrorCode.validation],
    DesignStateCategory.denied => [ErrorCode.forbidden, ErrorCode.unauthorized],
    DesignStateCategory.unsupported => [ErrorCode.unsupported],
    DesignStateCategory.localUnavailable => [
      ErrorCode.serviceUnavailable,
      ErrorCode.storageBlocked,
      ErrorCode.incompatible,
    ],
    DesignStateCategory.loading => <ErrorCode>[],
    _ => throw StateError('Readiness does not own ${scenario.caseId}'),
  };
  if (scenario.category == DesignStateCategory.loading) {
    final states = base == ReadinessState.starting
        ? [
            ReadinessState.starting,
            ReadinessState.recovering,
            ReadinessState.stopping,
          ]
        : [base];
    for (final state in states) {
      await _mount(
        tester,
        readiness.ReadinessView(
          state: state,
          retryInProgress: state == base && base != ReadinessState.starting,
          onRetry: () => retries++,
        ),
        frame,
        dark,
      );
      final presentation = tester.widget<readiness.ReadinessView>(
        find.byType(readiness.ReadinessView),
      );
      expect(presentation.state, state);
      _expectReadinessTabs(tester, state);
      expect(
        presentation.retryInProgress ||
            const {
              ReadinessState.starting,
              ReadinessState.recovering,
              ReadinessState.stopping,
            }.contains(presentation.state),
        isTrue,
      );
      expect(find.text('Состояние и следующие шаги'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final retry = find.widgetWithText(FilledButton, 'Повторить запуск');
      if (retry.evaluate().isNotEmpty)
        expect(tester.widget<FilledButton>(retry).onPressed, isNull);
      await _passiveRebuilds(tester, frame, dark, () => {'onRetry': retries});
      expect(retries, 0);
      await _checkpoint(
        tester,
        scenario,
        state.name.toLowerCase(),
        frame,
        dark,
        {'onRetry': retries},
        [
          'Actual readiness pending stage and static running symbol',
          'Pending retry absent/disabled; rebuilds invoke no retry',
        ],
      );
    }
  } else {
    for (final reason in reasons) {
      final state = scenario.category == DesignStateCategory.localUnavailable
          ? reason == ErrorCode.storageBlocked
                ? ReadinessState.storageBlocked
                : reason == ErrorCode.incompatible
                ? ReadinessState.incompatible
                : ReadinessState.unavailable
          : base;
      await _mount(
        tester,
        readiness.ReadinessView(
          state: state,
          reason: reason,
          onRetry: () => retries++,
        ),
        frame,
        dark,
      );
      final expected = {
        ErrorCode.validation: 'Локальная служба отклонила некорректный запрос.',
        ErrorCode.forbidden: 'Локальная служба не разрешила это действие.',
        ErrorCode.unauthorized:
            'Не удалось подтвердить доступ к локальной службе.',
        ErrorCode.unsupported: 'Эта функция локальной службы пока недоступна.',
        ErrorCode.serviceUnavailable:
            'Не удалось связаться с локальной службой.',
        ErrorCode.storageBlocked: 'Доступ к локальному хранилищу заблокирован. Требуется проверка локального пространства.',
        ErrorCode.incompatible:
            'Версии клиента и локальной службы несовместимы.',
      }[reason]!;
      expect(find.text(expected), findsWidgets);
      final presentation = tester.widget<readiness.ReadinessView>(
        find.byType(readiness.ReadinessView),
      );
      expect(presentation.state, state);
      expect(presentation.reason, reason);
      _expectReadinessTabs(tester, state);
      expect(find.text('Состояние и следующие шаги'), findsOneWidget);
      expect(find.byType(ProfileForm), findsNothing);
      expect(find.textContaining('plaintext'), findsNothing);
      final before = retries;
      final retry = find.widgetWithText(FilledButton, 'Повторить запуск');
      if (state == ReadinessState.starting) {
        expect(retry, findsNothing);
      } else {
        await tester.ensureVisible(retry);
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(retries, before + 1);
        await _mount(
          tester,
          readiness.ReadinessView(
            state: state,
            reason: reason,
            retryInProgress: true,
            onRetry: () => retries++,
          ),
          frame,
          dark,
        );
        expect(tester.widget<FilledButton>(retry).onPressed, isNull);
      }
      await _passiveRebuilds(tester, frame, dark, () => {'onRetry': retries});
      await _checkpoint(
        tester,
        scenario,
        reason.name.toLowerCase(),
        frame,
        dark,
        {'onRetry': retries},
        [
          'Actual typed readiness reason and state role',
          'Existing explicit retry only; busy duplicate disabled; private form absent',
        ],
      );
    }
  }
  await tester.pumpWidget(const SizedBox.shrink());
}

Future<void> _registrySnapshot(
  WidgetTester tester,
  DesignStateCase scenario,
  _Frame frame,
  bool dark,
) async {
  final loading = scenario.category == DesignStateCategory.loading;
  final empty = scenario.category == DesignStateCategory.successfulEmpty;
  final harness = await DesignScenarioHarness.create(
    options: DesignFixtureOptions(loaded: !loading, empty: empty),
  );
  try {
    await _mount(
      tester,
      ListenableBuilder(
        listenable: harness.profiles,
        builder: (context, _) => scenario.originId == '84-settings'
            ? settings.SettingsView(controller: harness.profiles)
            : ProfileList(controller: harness.profiles),
      ),
      frame,
      dark,
    );
    final before = _counts(harness);
    if (loading) {
      harness.client.events.add(
        model_fixture.snapshot(gen: '99999999-9999-4999-8999-999999999999'),
      );
      await tester.pumpAndSettle();
      expect(harness.profiles.loaded, isFalse);
      expect(
        find.text(
          scenario.originId == '84-settings'
              ? 'Загрузка настроек'
              : 'Загрузка локальных профилей',
        ),
        findsOneWidget,
      );
      expect(find.text('Все серверы.\nОдин центр управления.'), findsNothing);
      await _passiveRebuilds(tester, frame, dark, () => _counts(harness));
      await _checkpoint(
        tester,
        scenario,
        'pending-current-snapshot',
        frame,
        dark,
        _counts(harness),
        [
          'Old generation ignored by actual ProfileController',
          'Missing coherent snapshot is pending, not empty/default settings',
        ],
      );
    } else if (empty || scenario.category == DesignStateCategory.data) {
      expect(harness.profiles.loaded, isTrue);
      if (empty) {
        expect(harness.profiles.profiles, isEmpty);
        expect(
          find.text('Все серверы.\nОдин центр управления.'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Добавить сервер'),
              )
              .onPressed,
          isNotNull,
        );
      } else {
        expect(find.textContaining('Saved profile'), findsOneWidget);
        expect(find.textContaining('192.0.2.1:22'), findsOneWidget);
        if (scenario.originId == '84-settings') {
          expect(find.text('Включено'), findsOneWidget);
        } else {
          final surface = find
              .ancestor(
                of: find.text('Saved profile'),
                matching: find.byType(DeckSurface),
              )
              .first;
          expect(harness.profiles.selected?.id, harness.initialProfile.id);
          expect(
            tester.widget<DeckSurface>(surface).selected,
            isFalse,
            reason: 'A selected local profile does not prove an observed SSH connection',
          );
        }
      }
      await _passiveRebuilds(tester, frame, dark, () => _counts(harness));
      expect(_counts(harness), before);
      await _checkpoint(
        tester,
        scenario,
        empty ? 'loaded-empty' : 'current-data',
        frame,
        dark,
        _counts(harness),
        [
          'Coherent actual model ${empty ? 'empty collection with create action' : 'current metadata and selected context'}',
          'No UI-triggered reads/mutations/connect on render/theme/resize',
        ],
      );
    } else {
      final codes = switch (scenario.category) {
        DesignStateCategory.validation => [ErrorCode.validation],
        DesignStateCategory.denied => [
          ErrorCode.forbidden,
          ErrorCode.unauthorized,
        ],
        DesignStateCategory.unsupported => [ErrorCode.unsupported],
        _ => throw StateError('No snapshot state ${scenario.caseId}'),
      };
      for (final code in codes) {
        harness.showReadError(code);
        await tester.pumpAndSettle();
        expect(find.text(ReadErrorView.category(code)), findsWidgets);
        expect(
          tester.widget<ReadErrorView>(find.byType(ReadErrorView)).code,
          code,
        );
        expect(harness.profiles.loaded, isFalse);
        expect(find.text('Все серверы.\nОдин центр управления.'), findsNothing);
        expect(find.text('Повторить чтение'), findsNothing);
        expect(
          find.text('Повторить проверку службы'),
          code == ErrorCode.unauthorized ? findsOneWidget : findsNothing,
        );
        await _passiveRebuilds(tester, frame, dark, () => _counts(harness));
        expect(_counts(harness), before);
        await _checkpoint(
          tester,
          scenario,
          code.name.toLowerCase(),
          frame,
          dark,
          _counts(harness),
          [
            'Actual guarded snapshot error category and permitted guidance',
            'Error is not successful empty; no automatic retry or permission handler',
          ],
        );
      }
    }
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await harness.close();
  }
}

_Form _formFor(String origin) => origin == '09-profile-delete'
    ? _Form.profileDelete
    : origin == '85-settings-form'
    ? _Form.settings
    : _Form.profileEdit;

MutationController _activeMutation(WidgetTester tester) =>
    tester.widget<MutationStatus>(find.byType(MutationStatus)).controller;

String _actualFormId(WidgetTester tester, _Form form) =>
    form == _Form.profileEdit
    ? (tester.state(find.byType(ProfileForm)) as dynamic).id as String
    : model_fixture.profileId;

Map<String, Object?> _formReceipt(_Form form, String id, bool creating) => {
  'entityId': form == _Form.settings ? null : id,
  'entityRevision': form == _Form.profileDelete || creating ? '1' : '2',
  'storeRevision': '3',
  'deleted': form == _Form.profileDelete,
};

void _publishFormCurrent(
  DesignScenarioHarness harness,
  _Form form,
  String id,
  bool creating,
) {
  // The readback can include a later ordinary edit at4, after this intent's
  // commit at3. Its changed display fields must not replace the RAM draft.
  final base = model_fixture.snapshot(revision: '4');
  final old = Map<String, Object?>.from(
    (base.profiles.result['profiles'] as List).single as Map,
  );
  final profiles = form == _Form.profileDelete
      ? <Map<String, Object?>>[]
      : form == _Form.settings
      ? [old]
      : [
          if (creating) old,
          {
            ...old,
            'id': id,
            'name': 'Current server value',
            'revision': creating ? '2' : '3',
            if (creating) 'credential': {'kind': 'none', 'configured': false},
          },
        ];
  harness.client.events.add(
    ClientSnapshot(
      ApiReply(harness.client.generationId, {
        ...base.profiles.result,
        'profiles': profiles,
      }),
      ApiReply(harness.client.generationId, {
        ...base.settings.result,
        'settings': {
          ...(base.settings.result['settings'] as Map<String, Object?>),
          'revision': form == _Form.profileDelete
              ? '2'
              : form == _Form.settings
              ? '3'
              : '1',
          'selectedProfileId': form == _Form.profileDelete
              ? null
              : model_fixture.profileId,
        },
      }),
    ),
  );
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
}

Future<void> _registryForm(
  WidgetTester tester,
  DesignStateCase scenario,
  _Frame frame,
  bool dark,
) async {
  if (scenario.category == DesignStateCategory.unknown) {
    // UNAUTHORIZED is uncertain under the actual owner; it is not a fabricated
    // definitive rejection. No private-epoch retirement is claimed here.
    for (final error in [ErrorCode.timeout, ErrorCode.unauthorized]) {
      await _registryUnknown(tester, scenario, frame, dark, error);
    }
    return;
  }
  final form = _formFor(scenario.originId);
  final creating = {
    '07-profile-create',
    '12-credential-input',
  }.contains(scenario.originId);
  final harness = await DesignScenarioHarness.create();
  try {
    await _openForm(tester, harness, form, frame, dark, creating: creating);
    final before = _counts(harness);
    _expectDraft(tester, form);
    final id = _actualFormId(tester, form);
    if (scenario.category == DesignStateCategory.data) {
      expect(
        tester.widget<ButtonStyleButton>(_dialogButton(form.submit)).onPressed,
        isNotNull,
      );
      if (form == _Form.profileEdit) {
        final credential = tester.state<CredentialInputState>(
          find.byType(CredentialInput),
        );
        expect(credential.password.text, isEmpty);
        expect(credential.keyInput.text, isEmpty);
        expect(credential.action(), {'action': creating ? 'remove' : 'keep'});
      }
      final ownerState = tester.state(
        find.byType(
          form == _Form.settings
              ? SettingsForm
              : form == _Form.profileDelete
              ? ProfileDelete
              : ProfileForm,
        ),
      );
      await _passiveRebuilds(tester, frame, dark, () => _counts(harness));
      expect(
        tester.state(
          find.byType(
            form == _Form.settings
                ? SettingsForm
                : form == _Form.profileDelete
                ? ProfileDelete
                : ProfileForm,
          ),
        ),
        same(ownerState),
      );
      _expectDraft(tester, form);
      expect(_counts(harness), before);
      if (scenario.originId == '13-mutation-conflict') {
        harness.client.mutationGate = Completer<ApiReply>();
        await _click(tester, form.submit);
        harness.client.mutationGate!.complete(
          ApiReply(
            harness.client.generationId,
            _formReceipt(form, id, creating),
          ),
        );
        await tester.pumpAndSettle();
        expect(_activeMutation(tester).state, MutationPresentation.committed);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.key == const ValueKey('mutation-current-status') &&
                widget.data == 'Сохранено',
          ),
          findsNothing,
        );
        _publishFormCurrent(harness, form, id, creating);
        await tester.pumpAndSettle();
        expect(_activeMutation(tester).state, MutationPresentation.succeeded);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.key == const ValueKey('mutation-current-status') &&
                widget.data == 'Сохранено',
          ),
          findsOneWidget,
        );
      }
      await _checkpoint(
        tester,
        scenario,
        'current-draft-or-confirmed-result',
        frame,
        dark,
        _counts(harness),
        [
          'Actual ${scenario.owner} values and retained mounted owner through theme/resize',
          'No existing secret is read into the draft; success only after coherent readback',
        ],
      );
    } else if (scenario.category == DesignStateCategory.loading) {
      harness.client.mutationGate = Completer<ApiReply>();
      await _click(tester, form.submit);
      expect(_activeMutation(tester).state, MutationPresentation.submitting);
      expect(_activeMutation(tester).busy, isTrue);
      _expectDisabledSubmit(tester, form);
      _expectDraft(tester, form);
      expect(harness.client.mutations, hasLength(1));
      expect(harness.client.statusRequests, isEmpty);
      final stage = form == _Form.profileDelete ? 'Удаление' : 'Сохранение';
      expect(_dialogText(stage), findsOneWidget);
      await _passiveRebuilds(tester, frame, dark, () => _counts(harness));
      _expectDraft(tester, form);
      await _reveal(tester, _dialogText(stage));
      await _checkpoint(
        tester,
        scenario,
        'submitting',
        frame,
        dark,
        _counts(harness),
        [
          'Actual pending mutation stage with disabled submit',
          'Exactly one explicit mutation; zero result checks/duplicates on theme/resize',
        ],
      );
      // Completing a definitive failure only releases the test's real pending
      // owner before disposal. It never starts a new mutation.
      harness.client.mutationGate!.completeError(
        const LocalApiException(ErrorCode.validation),
      );
      await tester.pumpAndSettle();
    } else if (scenario.category == DesignStateCategory.validation) {
      if (form == _Form.profileEdit) {
        await tester.enterText(find.byKey(const ValueKey('profile-name')), '');
        await _click(tester, form.submit);
        expect(find.text('Проверьте значение поля'), findsOneWidget);
        expect(harness.client.mutations, isEmpty);
        expect(
          tester
              .widget<TextFormField>(find.byKey(const ValueKey('profile-name')))
              .controller!
              .text,
          isEmpty,
        );
        await _checkpoint(
          tester,
          scenario,
          'field-validation',
          frame,
          dark,
          _counts(harness),
          [
            'Actual keyed TextFormField validation blocks mutate',
            'Invalid draft retained; no invented text fields for delete/settings',
          ],
        );
        await tester.enterText(
          find.byKey(const ValueKey('profile-name')),
          'Retained draft',
        );
      }
      harness.client.mutationError = ErrorCode.validation;
      await _click(tester, form.submit);
      expect(harness.client.mutations, hasLength(1));
      expect(_activeMutation(tester).state, MutationPresentation.failed);
      expect(
        _dialogText(ReadErrorView.category(ErrorCode.validation)),
        findsWidgets,
      );
      _expectDraft(tester, form);
      await _checkpoint(
        tester,
        scenario,
        'service-validation',
        frame,
        dark,
        _counts(harness),
        [
          'Existing typed service VALIDATION response to one explicit legal UI intent',
          'No forced invalid values in restricted controls; draft retained',
        ],
      );
      await _click(
        tester,
        form == _Form.profileDelete
            ? 'Вернуться к подтверждению'
            : 'Исправить ввод',
      );
      if (!creating) {
        harness.client.mutationError = ErrorCode.revisionConflict;
        await _click(tester, form.submit);
        expect(_activeMutation(tester).state, MutationPresentation.conflict);
        _expectDraft(tester, form);
        final priorRead = harness.client.refreshes;
        harness.client.refreshGate = Completer<void>();
        await _click(tester, form.reload);
        expect(harness.client.refreshes, priorRead + 1);
        expect(_dialogText(form.pendingRead), findsOneWidget);
        _expectDisabledSubmit(tester, form);
        _expectDraft(tester, form);
        await _checkpoint(
          tester,
          scenario,
          'cas-reread-pending',
          frame,
          dark,
          _counts(harness),
          [
            'Actual captured-revision CAS conflict is not observation stale',
            'Explicit reread stage; duplicate action absent and draft retained while pending',
          ],
        );
        _publishCurrent(harness);
        harness.client.refreshGate!.complete();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ButtonStyleButton>(_dialogButton(form.submit))
              .onPressed,
          form == _Form.profileDelete ? isNull : isNotNull,
        );
        expect(harness.client.mutations, hasLength(2));
      }
    } else if (scenario.category == DesignStateCategory.denied ||
        scenario.category == DesignStateCategory.unsupported) {
      final code = scenario.category == DesignStateCategory.denied
          ? ErrorCode.forbidden
          : ErrorCode.unsupported;
      harness.client.mutationError = code;
      await _click(tester, form.submit);
      expect(harness.client.mutations, hasLength(1));
      expect(_activeMutation(tester).state, MutationPresentation.failed);
      expect(_dialogText(ReadErrorView.category(code)), findsWidgets);
      expect(_dialogText('Проверить результат'), findsNothing);
      expect(_dialogText('Повторить тот же запрос'), findsNothing);
      _expectDraft(tester, form);
      await _passiveRebuilds(tester, frame, dark, () => _counts(harness));
      expect(harness.client.mutations, hasLength(1));
      await _reveal(tester, _dialogText(ReadErrorView.category(code)));
      await _checkpoint(
        tester,
        scenario,
        'definitive-${code.name}',
        frame,
        dark,
        _counts(harness),
        [
          'Actual owner definitive rejection, not unknown; preserved RAM draft',
          'Only existing correction action; zero automatic retry',
        ],
      );
      await _click(
        tester,
        form == _Form.profileDelete
            ? 'Вернуться к подтверждению'
            : 'Исправить ввод',
      );
      final readCode = scenario.category == DesignStateCategory.denied
          ? ErrorCode.unauthorized
          : code;
      harness.showReadError(readCode);
      await tester.pumpAndSettle();
      expect(_dialogText(ReadErrorView.category(readCode)), findsWidgets);
      _expectDisabledSubmit(tester, form);
      _expectDraft(tester, form);
      expect(harness.client.mutations, hasLength(1));
      await _reveal(tester, _dialogText(ReadErrorView.category(readCode)));
      await _checkpoint(
        tester,
        scenario,
        'initialized-read-${readCode.name}',
        frame,
        dark,
        _counts(harness),
        [
          'Separate guarded read error remains visible inside initialized form',
          'Read failure never becomes a definitive unauthorized-write claim or synthetic permissions handler',
        ],
      );
    } else {
      fail('No form state for ${scenario.caseId}');
    }
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await harness.close();
  }
  if (scenario.originId == '12-credential-input' &&
      scenario.category == DesignStateCategory.data) {
    await _registryCredentialModes(tester, scenario, frame, dark);
  }
  if (scenario.originId == '12-credential-input' &&
      scenario.category == DesignStateCategory.loading) {
    await _registryCredentialPicker(tester, scenario, frame, dark);
  }
}

Future<void> _registryUnknown(
  WidgetTester tester,
  DesignStateCase scenario,
  _Frame frame,
  bool dark,
  ErrorCode error,
) async {
  final form = _formFor(scenario.originId);
  final creating = {
    '07-profile-create',
    '12-credential-input',
  }.contains(scenario.originId);
  final harness = await DesignScenarioHarness.create();
  try {
    harness.client.mutationError = error;
    await _openForm(tester, harness, form, frame, dark, creating: creating);
    final id = _actualFormId(tester, form);
    await _click(tester, form.submit);
    final original = harness.client.mutations.single;
    final requestId = original.id;
    expect(_activeMutation(tester).state, MutationPresentation.unknown);
    expect(
      _dialogText(
        form == _Form.profileDelete
            ? 'Удаление не подтверждено'
            : 'Сохранение не подтверждено',
      ),
      findsOneWidget,
    );
    expect(_dialogText('Повторить тот же запрос'), findsNothing);
    _expectDraft(tester, form);
    _expectDisabledSubmit(tester, form);
    await _passiveRebuilds(tester, frame, dark, () => _counts(harness));
    await _checkpoint(
      tester,
      scenario,
      'unknown-${error.name}',
      frame,
      dark,
      _counts(harness),
      [
        'Actual uncertain owner state after ${error.wireName}, not definitive failure or empty result',
        'No automatic retry; retained original request and RAM draft',
      ],
    );
    harness.showReadError(ErrorCode.timeout);
    await tester.pumpAndSettle();
    harness.client.refreshGate = Completer<void>();
    final beforeUnknownRead = harness.client.refreshes;
    await _click(tester, 'Повторить чтение');
    expect(harness.client.refreshes, beforeUnknownRead + 1);
    expect(_activeMutation(tester).state, MutationPresentation.unknown);
    expect(
      _dialogText(
        form == _Form.profileDelete
            ? 'Удаление не подтверждено'
            : 'Сохранение не подтверждено',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ButtonStyleButton>(_dialogButton('Проверить результат'))
          .onPressed,
      isNotNull,
    );
    expect(harness.client.mutations, hasLength(1));
    expect(harness.client.statusRequests, isEmpty);
    await _checkpoint(
      tester,
      scenario,
      'unknown-typed-read-pending-${error.name}',
      frame,
      dark,
      _counts(harness),
      [
        'Typed read retry retains durable unknown notice and independent check-result control',
        'Exactly one explicit snapshot read, no automatic mutation or status request',
      ],
    );
    harness.publishSnapshot();
    harness.client.refreshGate!.complete();
    await tester.pumpAndSettle();
    harness.client.refreshGate = null;
    for (final status in ['queued', 'running', 'not-found']) {
      harness.client.statusGate = Completer<ApiReply>();
      final beforeChecks = harness.client.statusRequests.length;
      await _click(tester, 'Проверить результат');
      expect(_activeMutation(tester).busy, isTrue);
      expect(harness.client.statusRequests.length, beforeChecks + 1);
      expect(harness.client.statusRequests.last, same(original));
      expect(_dialogText('Проверить результат'), findsNothing);
      expect(_dialogText('Повторить тот же запрос'), findsNothing);
      expect(harness.client.mutations, hasLength(1));
      await _passiveRebuilds(tester, frame, dark, () => _counts(harness));
      await _checkpoint(
        tester,
        scenario,
        'checking-$status-${error.name}',
        frame,
        dark,
        _counts(harness),
        [
          'One actual mutationStatus check for the identical intent',
          'Busy check and mutation retry are absent; rebuilds do not duplicate checks',
        ],
      );
      harness.client.statusGate!.complete(
        ApiReply(harness.client.generationId, {
          'state': status,
          'result': null,
        }),
      );
      await tester.pumpAndSettle();
      harness.client.statusGate = null;
      expect(_activeMutation(tester).busy, isFalse);
      expect(
        _activeMutation(tester).state,
        status == 'not-found'
            ? MutationPresentation.retryAllowed
            : MutationPresentation.waiting,
      );
      expect(
        _dialogText(
          status == 'not-found'
              ? 'Запрос не найден; можно повторить тот же запрос'
              : 'Операция ещё выполняется',
        ),
        findsOneWidget,
      );
      expect(harness.client.mutations, hasLength(1));
      await _checkpoint(
        tester,
        scenario,
        '$status-${error.name}',
        frame,
        dark,
        _counts(harness),
        [
          'Actual owner $status status; no invented confirmed outcome',
          'Retry allowed only after explicit not-found, never queued/running',
        ],
      );
    }
    harness.client.mutationGate = Completer<ApiReply>();
    await _click(tester, 'Повторить тот же запрос');
    expect(harness.client.mutations, hasLength(2));
    expect(harness.client.mutations.last, same(original));
    expect(harness.client.mutations.last.id, requestId);
    expect(_activeMutation(tester).state, MutationPresentation.submitting);
    _expectDisabledSubmit(tester, form);
    expect(_dialogText('Повторить тот же запрос'), findsNothing);
    await _checkpoint(
      tester,
      scenario,
      'identical-retry-${error.name}',
      frame,
      dark,
      _counts(harness),
      [
        'Exactly one explicit retry of the same MutationIntent object/request ID',
        'Pending submit prevents another retry and preserves draft',
      ],
    );
    harness.client.mutationGate!.complete(
      ApiReply(harness.client.generationId, _formReceipt(form, id, creating)),
    );
    await tester.pumpAndSettle();
    expect(_activeMutation(tester).state, MutationPresentation.committed);
    final success = form == _Form.profileDelete ? 'Удалено' : 'Сохранено';
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.key == const ValueKey('mutation-current-status') &&
            widget.data == success,
      ),
      findsNothing,
    );
    _expectDraft(tester, form);
    await _checkpoint(
      tester,
      scenario,
      'committed-await-current-${error.name}',
      frame,
      dark,
      _counts(harness),
      [
        'Receipt confirms the write but old coherent snapshot is below committed revision',
        'No success before actual current readback',
      ],
    );
    final previousReadback = tester
        .widget<ButtonStyleButton>(_dialogButton('Перечитать состояние'))
        .onPressed!;
    harness.showReadError(ErrorCode.timeout);
    await tester.pumpAndSettle();
    harness.client.refreshGate = Completer<void>();
    final beforeCommittedRead = harness.client.refreshes;
    await _click(tester, 'Повторить чтение');
    expect(_activeMutation(tester).state, MutationPresentation.committed);
    expect(
      _dialogText(
        form == _Form.profileDelete
            ? 'Удаление выполнено; ожидается чтение актуального состояния'
            : 'Сохранено; ожидается чтение актуального состояния',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ButtonStyleButton>(_dialogButton('Перечитать состояние'))
          .onPressed,
      isNull,
    );
    previousReadback();
    await tester.pumpAndSettle();
    expect(harness.client.refreshes, beforeCommittedRead + 1);
    expect(harness.client.mutations, hasLength(2));
    await _checkpoint(
      tester,
      scenario,
      'committed-typed-read-pending-${error.name}',
      frame,
      dark,
      _counts(harness),
      [
        'Typed read retry preserves confirmed committed notice and current-readback requirement',
        'Readback button and its stale callback cannot duplicate snapshot read',
      ],
    );
    harness.publishSnapshot();
    harness.client.refreshGate!.complete();
    await tester.pumpAndSettle();
    harness.client.refreshGate = null;
    expect(_activeMutation(tester).state, MutationPresentation.committed);
    expect(
      tester
          .widget<ButtonStyleButton>(_dialogButton('Перечитать состояние'))
          .onPressed,
      isNotNull,
    );
    _publishFormCurrent(harness, form, id, creating);
    await tester.pumpAndSettle();
    expect(_activeMutation(tester).state, MutationPresentation.succeeded);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.key == const ValueKey('mutation-current-status') &&
            widget.data == success,
      ),
      findsOneWidget,
    );
    _expectDraft(tester, form);
    expect(harness.client.mutations, hasLength(2));
    expect(harness.client.statusRequests, hasLength(3));
    expect(harness.client.mutations.last, same(original));
    await _checkpoint(
      tester,
      scenario,
      'confirmed-current-${error.name}',
      frame,
      dark,
      _counts(harness),
      [
        'Success only after actual ProfileController accepted coherent current snapshot',
        'Two explicit sends, three explicit status checks, same original identity; no automatic write',
      ],
    );
    await _click(tester, 'Закрыть');
    expect(find.byType(Dialog), findsNothing);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await harness.close();
  }
}

List<Map<String, Object?>> _historyRows(int count) => [
  for (var revision = count; revision >= 1; revision--)
    {
      'requestId':
          '33333333-3333-4333-8333-${revision.toString().padLeft(12, '0')}',
      'operation': 'settings.update',
      'profileId': null,
      'committedAt': '2026-10-11T00:00:00.000Z',
      'result': {
        'entityId': null,
        'entityRevision': '$revision',
        'storeRevision': '$revision',
        'deleted': false,
      },
    },
];

Future<void> _registryHistory(
  WidgetTester tester,
  DesignStateCase scenario,
  _Frame frame,
  bool dark,
) async {
  if ({
    DesignStateCategory.validation,
    DesignStateCategory.denied,
    DesignStateCategory.unsupported,
  }.contains(scenario.category)) {
    final codes = scenario.category == DesignStateCategory.validation
        ? [ErrorCode.validation]
        : scenario.category == DesignStateCategory.denied
        ? [ErrorCode.forbidden, ErrorCode.unauthorized]
        : [ErrorCode.unsupported];
    for (final code in codes) {
      final harness = await DesignScenarioHarness.create();
      try {
        await _openHistory(tester, harness, frame, dark);
        final initialReads = harness.client.reads.length;
        harness.client.recentGate = Completer<ApiReply>();
        await _click(tester, 'Обновить список');
        expect(harness.client.reads.length, initialReads + 1);
        harness.client.recentGate!.completeError(LocalApiException(code));
        await tester.pumpAndSettle();
        expect(_dialogText(ReadErrorView.category(code)), findsWidgets);
        expect(harness.recovery.loaded, isFalse);
        expect(harness.recovery.error, code);
        expect(
          find.byWidgetPredicate(
            (widget) => widget.key is RecentOperationReceiptKey,
          ),
          findsNothing,
        );
        expect(
          _dialogText('Подтверждённых записей в выборке нет'),
          findsNothing,
        );
        expect(_dialogText('Повторить чтение'), findsNothing);
        expect(
          _dialogText('Повторить проверку службы'),
          code == ErrorCode.unauthorized ? findsOneWidget : findsNothing,
        );
        await _passiveRebuilds(tester, frame, dark, () => _counts(harness));
        expect(harness.client.reads.length, initialReads + 1);
        expect(harness.client.mutations, isEmpty);
        expect(harness.client.statusRequests, isEmpty);
        await _reveal(tester, _dialogText(ReadErrorView.category(code)));
        await _checkpoint(
          tester,
          scenario,
          code.name.toLowerCase(),
          frame,
          dark,
          _counts(harness),
          [
            'Actual StartupRecovery typed read failure inside the open production history dialog',
            'No stale rows/false empty or active fake read retry; no automatic mutation',
          ],
        );
        await _click(tester, 'Закрыть');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await harness.close();
      }
    }
    return;
  }
  final harness = await DesignScenarioHarness.create();
  try {
    if (scenario.category == DesignStateCategory.loading) {
      await _openHistory(tester, harness, frame, dark);
      final beforeReads = harness.client.reads.length;
      harness.client.recentGate = Completer<ApiReply>();
      await _click(tester, 'Обновить список');
      expect(harness.recovery.busy, isTrue);
      expect(
        _dialogText('Проверка текущих данных и недавних операций'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ButtonStyleButton>(_dialogButton('Обновить список'))
            .onPressed,
        isNull,
      );
      expect(_dialogText('Подтверждённых записей в выборке нет'), findsNothing);
      await _passiveRebuilds(tester, frame, dark, () => _counts(harness));
      expect(harness.client.reads.length, beforeReads + 1);
      await _checkpoint(
        tester,
        scenario,
        'history-read-pending',
        frame,
        dark,
        _counts(harness),
        [
          'Pending history refresh is distinct from successful empty',
          'No second refresh action or duplicate read while pending',
        ],
      );
      harness.client.recentGate!.complete(
        ApiReply(harness.client.generationId, {
          'receipts': _historyRows(3),
          'truncated': false,
        }),
      );
      await tester.pumpAndSettle();
      expect(harness.recovery.busy, isFalse);
      expect(harness.recovery.loaded, isFalse);
      expect(harness.recovery.error, isNull);
      expect(
        _dialogText('Проверка текущих данных и недавних операций'),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget.key is RecentOperationReceiptKey,
        ),
        findsNothing,
      );
      await _checkpoint(
        tester,
        scenario,
        'receipt-floor-pending',
        frame,
        dark,
        _counts(harness),
        [
          'Received receipt floor exceeds actual current snapshot; still pending after read completes',
          'No premature rows, success or incomplete/drop interpretation',
        ],
      );
      _publishCurrent(harness);
      await tester.pumpAndSettle();
      expect(harness.recovery.loaded, isTrue);
      expect(
        find.byWidgetPredicate(
          (widget) => widget.key is RecentOperationReceiptKey,
        ),
        findsNWidgets(3),
      );
      expect(harness.client.reads.length, beforeReads + 1);
      // A snapshot read can fail after the real history refresh/floor wait
      // has finished. Recovery.reload awaits that separate model read first.
      final previousRefresh = tester
          .widget<ButtonStyleButton>(_dialogButton('Обновить список'))
          .onPressed!;
      harness.showReadError(ErrorCode.timeout);
      await tester.pumpAndSettle();
      expect(
        _dialogText(ReadErrorView.category(ErrorCode.timeout)),
        findsWidgets,
      );
      harness.client.refreshGate = Completer<void>();
      harness.client.recentGate = null;
      final beforeSnapshotRetry = harness.client.refreshes;
      await _click(tester, 'Повторить чтение');
      expect(harness.client.refreshes, beforeSnapshotRetry + 1);
      expect(
        _dialogText('Проверка текущих данных и недавних операций'),
        findsOneWidget,
        reason: 'History must expose pending snapshot reread, not leave its typed read retry active',
      );
      expect(
        tester
            .widget<ButtonStyleButton>(_dialogButton('Повторить чтение'))
            .onPressed,
        isNull,
      );
      await _passiveRebuilds(tester, frame, dark, () => _counts(harness));
      expect(harness.client.refreshes, beforeSnapshotRetry + 1);
      await _checkpoint(
        tester,
        scenario,
        'history-snapshot-reread-pending',
        frame,
        dark,
        _counts(harness),
        [
          'Actual separate model refresh pending under open history',
          'Read retry disabled and exactly one explicit snapshot refresh; close remains available',
        ],
      );
      // The coherent snapshot can arrive before refreshSnapshot's Future
      // resolves. StartupRecovery starts its existing history read on that
      // model event, so loaded can become true while this local retry waits.
      final beforeEarlyHistoryRead = harness.client.reads.length;
      harness.client.recentGate = Completer<ApiReply>();
      _publishCurrent(harness);
      await tester.pumpAndSettle();
      expect(harness.recovery.busy, isTrue);
      expect(harness.client.reads.length, beforeEarlyHistoryRead + 1);
      harness.client.recentGate!.complete(
        ApiReply(harness.client.generationId, {
          'receipts': _historyRows(3),
          'truncated': false,
        }),
      );
      await tester.pumpAndSettle();
      harness.client.recentGate = null;
      expect(harness.recovery.loaded, isTrue);
      expect(harness.recovery.busy, isFalse);
      expect(harness.client.refreshGate!.isCompleted, isFalse);
      expect(
        find.byWidgetPredicate(
          (widget) => widget.key is RecentOperationReceiptKey,
        ),
        findsNWidgets(3),
      );
      expect(
        tester
            .widget<ButtonStyleButton>(_dialogButton('Обновить список'))
            .onPressed,
        isNull,
        reason: 'Early received records cannot re-enable refresh before the original local retry completes',
      );
      expect(
        _dialogText('Проверка текущих данных и недавних операций'),
        findsOneWidget,
      );
      expect(
        tester.widget<ButtonStyleButton>(_dialogButton('Закрыть')).onPressed,
        isNotNull,
      );
      final refreshesWhilePending = harness.client.refreshes;
      final readsWhilePending = harness.client.reads.length;
      await _reveal(tester, _dialogButton('Обновить список'));
      await tester.tap(_dialogButton('Обновить список'));
      previousRefresh();
      await tester.pumpAndSettle();
      await _passiveRebuilds(tester, frame, dark, () => _counts(harness));
      expect(harness.client.refreshes, refreshesWhilePending);
      expect(harness.client.reads.length, readsWhilePending);
      expect(harness.client.mutations, isEmpty);
      expect(harness.client.statusRequests, isEmpty);
      await _checkpoint(
        tester,
        scenario,
        'history-received-during-snapshot-retry',
        frame,
        dark,
        _counts(harness),
        [
          'Current snapshot and three actual received receipts precede the original snapshot Future completion',
          'Loaded rows remain honest alongside local pending; disabled refresh and captured stale callback add no read',
          'Close stays available; passive theme/resize adds no owner calls',
        ],
      );
      harness.client.refreshGate!.complete();
      await tester.pumpAndSettle();
      // The original reload resumes its existing owner read after the joined
      // snapshot Future. This is distinct from a duplicate presentation call.
      expect(harness.client.reads.length, readsWhilePending + 1);
      expect(harness.client.refreshes, refreshesWhilePending);
      expect(
        _dialogText('Проверка текущих данных и недавних операций'),
        findsNothing,
      );
      expect(
        tester
            .widget<ButtonStyleButton>(_dialogButton('Обновить список'))
            .onPressed,
        isNotNull,
      );
      harness.client.recentGate = Completer<ApiReply>();
      await _click(tester, 'Обновить список');
      expect(harness.recovery.busy, isTrue);
      expect(
        _dialogText('Проверка текущих данных и недавних операций'),
        findsOneWidget,
      );
      expect(
        tester.widget<ButtonStyleButton>(_dialogButton('Закрыть')).onPressed,
        isNotNull,
      );
      // The common close journey below now exits a real pending read. The
      // harness disposes the owner before resolving that late read in cleanup.
    } else {
      final empty = scenario.category == DesignStateCategory.successfulEmpty;
      final partial = scenario.category == DesignStateCategory.incomplete;
      if (!empty && !partial && scenario.category != DesignStateCategory.data)
        fail('No history provider for ${scenario.caseId}');
      harness.publishSnapshot(revision: '20');
      harness.client.receipts = _historyRows(
        empty
            ? 0
            : partial
            ? 20
            : 3,
      );
      harness.client.receiptsTruncated = partial;
      await harness.recovery.reload();
      await _openHistory(tester, harness, frame, dark);
      expect(harness.recovery.loaded, isTrue);
      final rows = find.byWidgetPredicate(
        (widget) => widget.key is RecentOperationReceiptKey,
      );
      expect(
        rows,
        findsNWidgets(
          empty
              ? 0
              : partial
              ? 20
              : 3,
        ),
      );
      expect(
        _dialogText('Подтверждённых записей в выборке нет'),
        empty ? findsOneWidget : findsNothing,
      );
      expect(
        _dialogText('Показана часть сохранённых записей'),
        partial ? findsOneWidget : findsNothing,
      );
      if (!empty) {
        final first = harness.client.receipts.first;
        expect(
          find.byKey(RecentOperationReceiptKey(first['requestId']! as String)),
          findsOneWidget,
        );
        expect(
          _dialogText('2026-10-11T00:00:00.000Z'),
          findsNWidgets(partial ? 20 : 3),
        );
      }
      expect(
        _dialogText(
          'Общие операции пространства, включая другие окна. До 20 последних подтверждённых записей. Отсутствие записи не доказывает исход потерянного запроса. Автоматический повтор не выполняется.',
        ),
        findsOneWidget,
      );
      await _passiveRebuilds(tester, frame, dark, () => _counts(harness));
      await _checkpoint(
        tester,
        scenario,
        empty
            ? 'confirmed-empty-sample'
            : partial
            ? 'truncated-twenty'
            : 'confirmed-receipts',
        frame,
        dark,
        _counts(harness),
        [
          'Actual bounded confirmed receipt sample with typed request keys, UTC and revision',
          'Empty/truncated/current sample does not resolve lost writes or jobs; no automatic action',
        ],
      );
    }
    expect(harness.client.mutations, isEmpty);
    expect(harness.client.statusRequests, isEmpty);
    await _click(tester, 'Закрыть');
    expect(find.byType(Dialog), findsNothing);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await harness.close();
  }
}

Future<void> _chooseCredential(
  WidgetTester tester,
  String current,
  String target,
) async {
  await _reveal(tester, find.text(current).first);
  await tester.tap(find.text(current).first);
  await tester.pumpAndSettle();
  await _reveal(tester, find.text(target).last);
  await tester.tap(find.text(target).last);
  await tester.pumpAndSettle();
}

Future<void> _registryCredentialModes(
  WidgetTester tester,
  DesignStateCase scenario,
  _Frame frame,
  bool dark,
) async {
  final key = GlobalKey<CredentialInputState>();
  var submissions = 0;
  await _mount(
    tester,
    SingleChildScrollView(
      child: CredentialInput(
        key: key,
        creating: false,
        enabled: true,
        onSubmit: () => submissions++,
      ),
    ),
    frame,
    dark,
  );
  expect(key.currentState!.action(), {'action': 'keep'});
  expect(key.currentState!.password.text, isEmpty);
  await _chooseCredential(tester, 'Сохранить существующий', 'Новый пароль');
  const secret = ' synthetic e\u0301 password ';
  await tester.enterText(
    find.byKey(const ValueKey('credential-password')),
    secret,
  );
  expect(key.currentState!.action()['password'], secret);
  expect(
    tester
        .widget<TextField>(
          find.descendant(
            of: find.byKey(const ValueKey('credential-password')),
            matching: find.byType(TextField),
          ),
        )
        .obscureText,
    isTrue,
  );
  final password = key.currentState!.password;
  await _passiveRebuilds(
    tester,
    frame,
    dark,
    () => {'submissions': submissions},
  );
  expect(key.currentState!.password, same(password));
  expect(password.text, secret);
  await _checkpoint(
    tester,
    scenario,
    'masked-password-mode',
    frame,
    dark,
    {'submissions': submissions},
    [
      'Actual password replace mode preserves verbatim draft and masking through theme/resize',
      'Existing keep mode never reads a stored secret',
    ],
    scopeOverride: 'productionPresentation',
  );
  await _chooseCredential(tester, 'Новый пароль', 'Новый приватный ключ');
  expect(password.text, isEmpty);
  await _reveal(tester, find.text('Показать введённый секрет'));
  await tester.tap(find.text('Показать введённый секрет'));
  await tester.pumpAndSettle();
  const syntheticPem =
      '-----BEGIN PRIVATE KEY-----\r\nAQID\r\n-----END PRIVATE KEY-----\r\n';
  await tester.enterText(
    find.byKey(const ValueKey('credential-private-key')),
    syntheticPem,
  );
  await tester.enterText(
    find.byKey(const ValueKey('credential-passphrase')),
    ' synthetic passphrase ',
  );
  final body = key.currentState!.action();
  expect(body['privateKey'], syntheticPem);
  expect(body['passphrase'], ' synthetic passphrase ');
  await _reveal(tester, find.text('Показать введённый секрет'));
  await tester.tap(find.text('Показать введённый секрет'));
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<TextField>(
          find.descendant(
            of: find.byKey(const ValueKey('credential-private-key')),
            matching: find.byType(TextField),
          ),
        )
        .obscureText,
    isTrue,
  );
  expect(
    tester
        .widget<TextField>(
          find.descendant(
            of: find.byKey(const ValueKey('credential-passphrase')),
            matching: find.byType(TextField),
          ),
        )
        .obscureText,
    isTrue,
  );
  await _checkpoint(
    tester,
    scenario,
    'masked-private-key-and-passphrase',
    frame,
    dark,
    {'submissions': submissions},
    [
      'Actual private key/passphrase replace mode is selectable and masked with exact RAM values',
      'No submission during mode changes',
    ],
    scopeOverride: 'productionPresentation',
  );
  final keyText = key.currentState!.keyInput;
  await _chooseCredential(
    tester,
    'Новый приватный ключ',
    'Без секрета / удалить',
  );
  expect(keyText.text, isEmpty);
  expect(key.currentState!.passphrase.text, isEmpty);
  expect(key.currentState!.action(), {'action': 'remove'});
  expect(submissions, 0);
  await tester.pumpWidget(const SizedBox.shrink());
  expect(password.text, isEmpty);
  expect(keyText.text, isEmpty);
}

Future<void> _registryCredentialPicker(
  WidgetTester tester,
  DesignStateCase scenario,
  _Frame frame,
  bool dark,
) async {
  final key = GlobalKey<CredentialInputState>();
  final gate = Completer<String?>();
  var picks = 0;
  int? epoch = 1;
  try {
    await _mount(
      tester,
      SingleChildScrollView(
        child: CredentialInput(
          key: key,
          creating: true,
          enabled: true,
          readReadyEpoch: () => epoch,
          pickKey: () {
            picks++;
            return gate.future;
          },
        ),
      ),
      frame,
      dark,
    );
    await _chooseCredential(
      tester,
      'Без секрета / удалить',
      'Новый приватный ключ',
    );
    await _click(tester, 'Выбрать файл ключа', inDialog: false);
    expect(picks, 1);
    expect(key.currentState!.picking, isTrue);
    expect(find.text('Чтение ключа'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Чтение ключа'),
          )
          .onPressed,
      isNull,
    );
    await _passiveRebuilds(tester, frame, dark, () => {'pickerCalls': picks});
    await _checkpoint(
      tester,
      scenario,
      'credential-picker-pending',
      frame,
      dark,
      {'pickerCalls': picks},
      [
        'Actual injected native-picker seam is pending, distinct from durable mutation',
        'One picker call; duplicate disabled; theme/resize does not restart picker',
      ],
      scopeOverride: 'productionPresentation',
    );
    epoch = 2;
    gate.complete('SYNTHETIC RETIRED KEY');
    await tester.pumpAndSettle();
    expect(key.currentState!.keyInput.text, isEmpty);
    expect(key.currentState!.picking, isFalse);
    expect(picks, 1);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    if (!gate.isCompleted) gate.complete(null);
  }
}
