import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck/ui/deck_components.dart';
import 'package:serverdeck_protocol/automation/profile_records.dart';
import 'package:serverdeck_protocol/models.dart';

import '../support/design_automation_fixtures.dart';
import '../support/design_host.dart' show expectDesignVisible, loadDesignFonts;
import '../support/design_server_fixtures.dart';

const _frames = [
  Size(1100, 760),
  Size(800, 600),
  Size(390, 800),
  Size(360, 800),
];
const _targetName = 'Архивный сервер 例 — данные отдела и резервные копии';
const _automationName =
    'Приветствие 例 — утверждённая версия для архивного сервера';
const _otherId = '00000000-0000-4000-8000-000000000203';
const _otherName = 'Другой выбранный сервер';
const _missingTarget = 'Название и адрес целевого сервера недоступны';
const _changedContext =
    'Контекст цели изменился. Закройте окно и заново проверьте действие.';
const _actions = AutomationActionAvailability(
  read: true,
  mutate: true,
  select: true,
);

ProfileView _target({
  String id = DesignServerFixtures.serverId,
  String name = _targetName,
  String address = '2001:db8:1234:5678::44',
  int port = 2222,
  String revision = '2',
  String connectionRevision = '2',
  String credentialRevision = '1',
  String trustRevision = '2',
}) => ProfileView(
  id: id,
  revision: revision,
  name: name,
  address: address,
  port: port,
  sshUser: 'synthetic',
  tags: const [],
  credentialRevision: credentialRevision,
  connectionRevision: connectionRevision,
  trustRevision: trustRevision,
  createdAt: DesignServerFixtures.observedAt,
  updatedAt: DesignServerFixtures.observedAt,
  credentialKind: CredentialKind.password,
  credentialConfigured: true,
);

AutomationProfileRecord _profile({
  String id = DesignAutomationFixtures.profileId,
  String workspaceId = DesignAutomationFixtures.workspaceId,
  String name = _automationName,
  int headRevision = 8,
}) => AutomationProfileRecord.fromJson({
  ...DesignAutomationFixtures.profile().toJson(),
  'id': id,
  'workspaceId': workspaceId,
  'name': name,
  'headRevision': headRevision,
});

Map<String, Object?> _copyPlan(Map<String, Object?> plan) =>
    jsonDecode(jsonEncode(plan)) as Map<String, Object?>;

Widget _app(
  Widget child, {
  bool dark = false,
  double scale = 1,
  bool section = false,
}) => MaterialApp(
  theme: Motion.theme(dark ? BrandTheme.dark : BrandTheme.light, true),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(disableAnimations: true, textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: section
        ? SingleChildScrollView(padding: const EdgeInsets.all(16), child: child)
        : child,
  ),
);

void _frame(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder _value(String label) => find
    .descendant(
      of: find.byWidgetPredicate(
        (widget) => widget is DeckKeyValue && widget.label == label,
      ),
      matching: find.byWidgetPredicate(
        (widget) => widget is SelectableText || widget is Text,
      ),
    )
    .last;

Finder _button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
);

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await Scrollable.ensureVisible(tester.element(finder), alignment: .05);
  await tester.pumpAndSettle();
  expectDesignVisible(tester, finder);
  expect(finder.hitTestable(), findsOneWidget);
  final text = tester.widget(finder);
  if (text is Text) {
    final paragraph = tester.renderObject<RenderParagraph>(finder);
    expect(paragraph.didExceedMaxLines, isFalse);
    final content = text.data ?? text.textSpan!.toPlainText();
    expect(
      paragraph.getBoxesForSelection(
        TextSelection(
          baseOffset: content.length - 1,
          extentOffset: content.length,
        ),
      ),
      isNotEmpty,
    );
  }
}

Future<void> _tap(WidgetTester tester, String label) async {
  final button = _button(label);
  await _reveal(tester, button);
  final size = tester.getSize(button);
  expect(size.width, greaterThanOrEqualTo(44));
  expect(size.height, greaterThanOrEqualTo(44));
  await tester.tap(button);
  await tester.pumpAndSettle();
}

bool _canConfirm(WidgetTester tester) =>
    tester.widget<FilledButton>(_button('Подтвердить план')).onPressed != null;

AutomationPlanDecisionDialog _decision({
  Key? key,
  Map<String, Object?>? plan,
  List<ProfileView>? targets,
  AutomationProfileRecord? profile,
  bool contextCurrent = true,
  bool approve = true,
  VoidCallback? onBack,
  VoidCallback? onConfirm,
}) => AutomationPlanDecisionDialog(
  now: DesignAutomationFixtures.presentationNow,
  key: key,
  plan: plan ?? DesignAutomationFixtures.plan(),
  serverProfiles: targets ?? [_target()],
  automationProfile: profile,
  contextCurrent: contextCurrent,
  approve: approve,
  onBack: onBack ?? () {},
  onConfirm: onConfirm ?? () {},
);

void main() {
  setUpAll(loadDesignFonts);

  for (final size in _frames) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('exact approval target and immutable version are readable '
            '${size.width.toInt()}x${size.height.toInt()} '
            '${dark ? 'dark' : 'light'} ${scale * 100}%', (tester) async {
          _frame(tester, size);
          var confirms = 0;
          var backs = 0;
          final plan = DesignAutomationFixtures.plan();
          await tester.pumpWidget(
            _app(
              _decision(
                plan: plan,
                targets: [
                  _target(id: _otherId, name: _otherName),
                  _target(),
                ],
                profile: _profile(),
                onBack: () => backs++,
                onConfirm: () => confirms++,
              ),
              dark: dark,
              scale: scale,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(_otherName), findsNothing);
          expect(_canConfirm(tester), isTrue);
          final scrollable = find.byType(Scrollable).first;
          final scroll = tester.state<ScrollableState>(scrollable).position;
          for (final entry in {
            'Сервер': _targetName,
            'Адрес': '[2001:db8:1234:5678::44]:2222',
            'Ansible-профиль': _automationName,
            'Версия профиля': '2',
            'Хеш версии профиля': plan['profileDigest'],
            'Действует до': '${plan['expiresAt']} (UTC)',
          }.entries) {
            final value = _value(entry.key);
            final widget = tester.widget(value);
            expect(
              widget is Text ? widget.data : (widget as SelectableText).data,
              entry.value,
            );
            await _reveal(tester, value);
          }
          expect(find.text('8'), findsNothing);
          expect(scroll.pixels, greaterThan(0));
          expect(confirms, 0);
          expect(backs, 0);
          await _tap(tester, 'Назад');
          expect(backs, 1);
          expect(confirms, 0);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets(
    'grant review lists every granted target, not the unrelated selection',
    (tester) async {
      _frame(tester, const Size(360, 800));
      final first = _target();
      final second = _target(
        id: _otherId,
        name: 'Почтовый сервер 例 — выделенная цель',
        address: 'mail.example.test',
        port: 22,
      );
      final unrelated = _target(
        id: '00000000-0000-4000-8000-000000000204',
        name: _otherName,
      );
      var effects = 0;
      final grant = {
        ...DesignAutomationFixtures.grant(),
        'serverIds': [first.id, second.id],
      };
      await tester.pumpWidget(
        _app(
          AutomationGrantsSection(
            grants: [AutomationGrantPresentation(value: grant, current: true)],
            serverProfiles: [unrelated, second, first],
            loaded: true,
            actions: _actions,
            onRefresh: () => effects++,
            onCreate: () => effects++,
            onConfigure: (_) => effects++,
            onEdit: (_) => effects++,
            onRevoke: (_) => effects++,
            onCopyConfiguration: () => effects++,
          ),
          scale: 2,
          section: true,
        ),
      );
      await tester.tap(find.text('Доступ ИИ рабочего пространства'));
      await tester.pumpAndSettle();
      expect(find.text(_otherName), findsNothing);
      for (final text in [
        first.name,
        '[2001:db8:1234:5678::44]:2222',
        second.name,
        'mail.example.test:22',
      ]) {
        await _reveal(tester, find.text(text));
      }
      final details = find.text('Идентификаторы целевых серверов');
      await _reveal(tester, details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      final raw = tester.widgetList<SelectableText>(
        find.byType(SelectableText),
      );
      expect(
        raw.any(
          (row) =>
              row.data!.contains(first.id) && row.data!.contains(second.id),
        ),
        isTrue,
      );
      expect(effects, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final field in [
    'serverRevision',
    'connectionRevision',
    'accessRevision',
    'trustRevision',
  ]) {
    for (final missing in [false, true]) {
      testWidgets(
        'approval refuses ${missing ? 'missing' : 'mismatched'} $field',
        (tester) async {
          final plan = _copyPlan(DesignAutomationFixtures.plan());
          if (missing) {
            plan.remove(field);
          } else {
            plan[field] = '9';
          }
          var confirms = 0;
          await tester.pumpWidget(
            _app(
              _decision(
                plan: plan,
                profile: _profile(),
                onConfirm: () => confirms++,
              ),
            ),
          );
          expect(find.text(_targetName), findsNothing);
          expect(find.text('[2001:db8:1234:5678::44]:2222'), findsNothing);
          expect(find.text(_missingTarget), findsOneWidget);
          expect(_canConfirm(tester), isFalse);
          await _tap(tester, 'Подтвердить план');
          expect(confirms, 0);
        },
      );
    }
  }

  for (final kind in ['parameters', 'delegation', 'grant']) {
    testWidgets(
      '$kind editor resolves actual target metadata before continuing',
      (tester) async {
        _frame(tester, const Size(360, 800));
        final input = TextEditingController(text: '{}');
        addTearDown(input.dispose);
        var continues = 0;
        var closes = 0;
        final preview = <String, Object?>{
          if (kind == 'grant') ...{
            'label': 'Доступ к архиву',
            'scopes': ['plan', 'apply'],
            'serverIds': [DesignServerFixtures.serverId],
          } else if (kind == 'delegation')
            'predicates': {
              'greeting': {
                'type': 'enum',
                'values': ['Привет'],
              },
            }
          else
            'greeting': 'Привет',
        };
        await tester.pumpWidget(
          _app(
            AutomationJsonEditorDialog(
              title: 'Проверка параметров',
              input: input,
              preview: preview,
              targetServerIds: kind == 'grant'
                  ? []
                  : [DesignServerFixtures.serverId],
              serverProfiles: [
                _target(id: _otherId, name: _otherName),
                _target(),
              ],
              onClose: () => closes++,
              onContinue: () => continues++,
            ),
            dark: true,
            scale: 2,
          ),
        );
        expect(find.text(_otherName), findsNothing);
        await _reveal(tester, find.text(_targetName));
        await _reveal(tester, find.text('[2001:db8:1234:5678::44]:2222'));
        expect(continues, 0);
        expect(closes, 0);
        await _tap(tester, 'Закрыть');
        expect(closes, 1);
        expect(continues, 0);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  final unavailableTargets = <String, List<ProfileView>>{
    'missing': [],
    'unrelated': [_target(id: _otherId, name: _otherName)],
    'duplicate': [_target(), _target(name: 'Дубликат 例')],
  };
  for (final entry in unavailableTargets.entries) {
    testWidgets('approval does not guess ${entry.key} server metadata', (
      tester,
    ) async {
      var confirms = 0;
      await tester.pumpWidget(
        _app(
          _decision(
            targets: entry.value,
            profile: _profile(),
            onConfirm: () => confirms++,
          ),
        ),
      );
      expect(find.text(_targetName), findsNothing);
      expect(find.text(_otherName), findsNothing);
      expect(find.text('Дубликат 例'), findsNothing);
      expect(find.text(_missingTarget), findsOneWidget);
      expect(_canConfirm(tester), isFalse);
      await _tap(tester, 'Подтвердить план');
      expect(confirms, 0);
    });
  }

  for (final entry in <String, AutomationProfileRecord?>{
    'missing': null,
    'wrong id': _profile(id: _otherId),
    'wrong workspace': _profile(workspaceId: _otherId),
  }.entries) {
    testWidgets('approval refuses ${entry.key} automation profile metadata', (
      tester,
    ) async {
      var confirms = 0;
      await tester.pumpWidget(
        _app(_decision(profile: entry.value, onConfirm: () => confirms++)),
      );
      expect(find.text(_automationName), findsNothing);
      expect(find.text('Название профиля недоступно'), findsOneWidget);
      expect(_canConfirm(tester), isFalse);
      await _tap(tester, 'Подтвердить план');
      expect(confirms, 0);
    });
  }

  final changedTargets = <String, List<ProfileView>>{
    'name': [_target(name: 'Подменённое имя 例')],
    'address': [_target(address: '192.0.2.99')],
    'port': [_target(port: 22)],
    'server revision': [_target(revision: '3')],
    'connection revision': [_target(connectionRevision: '3')],
    'access revision': [_target(credentialRevision: '2')],
    'trust revision': [_target(trustRevision: '3')],
    'removed target': [],
    'duplicate target': [_target(), _target(name: 'Дубликат 例')],
  };
  for (final entry in changedTargets.entries) {
    testWidgets(
      'open approval permanently retires after ${entry.key} changes',
      (tester) async {
        final key = GlobalKey();
        final plan = DesignAutomationFixtures.plan();
        final original = [_target()];
        final profile = _profile();
        var confirms = 0;
        Future<void> mount(List<ProfileView> targets) async {
          await tester.pumpWidget(
            _app(
              _decision(
                key: key,
                plan: plan,
                targets: targets,
                profile: profile,
                onConfirm: () => confirms++,
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await mount(original);
        final state = key.currentState;
        expect(_canConfirm(tester), isTrue);
        await mount(entry.value);
        expect(key.currentState, same(state));
        expect(find.text(_changedContext), findsOneWidget);
        expect(find.text('Подменённое имя 例'), findsNothing);
        expect(_canConfirm(tester), isFalse);
        await mount(original);
        expect(key.currentState, same(state));
        expect(find.text(_changedContext), findsOneWidget);
        expect(_canConfirm(tester), isFalse);
        await _tap(tester, 'Подтвердить план');
        expect(confirms, 0);
      },
    );
  }

  for (final field in [
    'serverId',
    'profileId',
    'profileRevision',
    'profileDigest',
    'digest',
  ]) {
    testWidgets('open approval permanently retires after plan $field changes', (
      tester,
    ) async {
      final key = GlobalKey();
      final original = DesignAutomationFixtures.plan();
      final changed = _copyPlan(original);
      changed[field] = switch (field) {
        'profileRevision' => 3,
        'serverId' || 'profileId' => _otherId,
        _ => List.filled(64, 'b').join(),
      };
      var confirms = 0;
      Future<void> mount(Map<String, Object?> plan) async {
        await tester.pumpWidget(
          _app(
            _decision(
              key: key,
              plan: plan,
              profile: _profile(),
              onConfirm: () => confirms++,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount(original);
      final state = key.currentState;
      expect(_canConfirm(tester), isTrue);
      await mount(changed);
      expect(_canConfirm(tester), isFalse);
      expect(find.text(_changedContext), findsOneWidget);
      await mount(_copyPlan(original));
      expect(key.currentState, same(state));
      expect(_canConfirm(tester), isFalse);
      await _tap(tester, 'Подтвердить план');
      expect(confirms, 0);
    });
  }

  for (final entry in <String, AutomationProfileRecord?>{
    'renamed': _profile(name: 'Другое название автоматизации 例'),
    'removed': null,
    'wrong workspace': _profile(workspaceId: _otherId),
    'new head': _profile(headRevision: 9),
  }.entries) {
    testWidgets(
      'open approval permanently retires after profile is ${entry.key}',
      (tester) async {
        final key = GlobalKey();
        final original = _profile();
        final plan = DesignAutomationFixtures.plan();
        var confirms = 0;
        Future<void> mount(AutomationProfileRecord? profile) async {
          await tester.pumpWidget(
            _app(
              _decision(
                key: key,
                plan: plan,
                profile: profile,
                onConfirm: () => confirms++,
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await mount(original);
        final state = key.currentState;
        expect(_canConfirm(tester), isTrue);
        await mount(entry.value);
        expect(find.text('Другое название автоматизации 例'), findsNothing);
        expect(_canConfirm(tester), isFalse);
        await mount(original);
        expect(key.currentState, same(state));
        expect(find.text(_changedContext), findsOneWidget);
        expect(_canConfirm(tester), isFalse);
        await _tap(tester, 'Подтвердить план');
        expect(confirms, 0);
      },
    );
  }

  testWidgets(
    'same metadata retains approval state across theme and resize without effects',
    (tester) async {
      _frame(tester, const Size(390, 800));
      final key = GlobalKey();
      final plan = DesignAutomationFixtures.plan();
      var confirms = 0;
      var backs = 0;
      Future<void> mount({bool dark = false, double scale = 2}) async {
        await tester.pumpWidget(
          _app(
            _decision(
              key: key,
              plan: _copyPlan(plan),
              targets: [_target()],
              profile: _profile(),
              onBack: () => backs++,
              onConfirm: () => confirms++,
            ),
            dark: dark,
            scale: scale,
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount();
      final state = key.currentState;
      await _reveal(tester, _value('Ansible-профиль'));
      for (final size in _frames) {
        tester.view.physicalSize = size;
        await mount(dark: true);
        expect(key.currentState, same(state));
        expect(_canConfirm(tester), isTrue);
        expect(find.text(_changedContext), findsNothing);
        expect(confirms, 0);
        expect(backs, 0);
      }
      await mount(scale: 1);
      final confirm = _button('Подтвердить план');
      await _reveal(tester, confirm);
      Focus.of(tester.element(find.text('Подтвердить план'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(confirms, 1);
      expect(backs, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('owner context loss cannot restore an old approval', (
    tester,
  ) async {
    final key = GlobalKey();
    final plan = DesignAutomationFixtures.plan();
    var confirms = 0;
    Future<void> mount(bool current) async {
      await tester.pumpWidget(
        _app(
          _decision(
            key: key,
            plan: plan,
            profile: _profile(),
            contextCurrent: current,
            onConfirm: () => confirms++,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await mount(true);
    expect(_canConfirm(tester), isTrue);
    await mount(false);
    expect(_canConfirm(tester), isFalse);
    await mount(true);
    expect(find.text(_changedContext), findsOneWidget);
    expect(_canConfirm(tester), isFalse);
    await _tap(tester, 'Подтвердить план');
    expect(confirms, 0);
  });

  testWidgets(
    'changing decision polarity permanently retires the old approval',
    (tester) async {
      final key = GlobalKey();
      final plan = DesignAutomationFixtures.plan();
      var confirms = 0;
      Future<void> mount(bool approve) async {
        await tester.pumpWidget(
          _app(
            _decision(
              key: key,
              plan: plan,
              profile: _profile(),
              approve: approve,
              onConfirm: () => confirms++,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount(true);
      final state = key.currentState;
      expect(_canConfirm(tester), isTrue);
      await mount(false);
      expect(_canConfirm(tester), isFalse);
      await mount(true);
      expect(key.currentState, same(state));
      expect(_canConfirm(tester), isFalse);
      await _tap(tester, 'Подтвердить план');
      expect(confirms, 0);
    },
  );

  testWidgets(
    'unrelated profile changes do not retire the exact valid target',
    (tester) async {
      final key = GlobalKey();
      final plan = DesignAutomationFixtures.plan();
      var confirms = 0;
      Future<void> mount(List<ProfileView> profiles) async {
        await tester.pumpWidget(
          _app(
            _decision(
              key: key,
              plan: _copyPlan(plan),
              targets: profiles,
              profile: _profile(),
              onConfirm: () => confirms++,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount([_target(), _target(id: _otherId, name: _otherName)]);
      final state = key.currentState;
      await mount([
        _target(id: _otherId, name: 'Изменённый несвязанный сервер 例'),
        _target(),
      ]);
      expect(key.currentState, same(state));
      expect(_canConfirm(tester), isTrue);
      await mount([_target()]);
      expect(key.currentState, same(state));
      expect(_canConfirm(tester), isTrue);
      expect(find.text(_changedContext), findsNothing);
      expect(confirms, 0);
      await _tap(tester, 'Подтвердить план');
      expect(confirms, 1);
    },
  );

  for (final mutation in ['nested plan', 'target list']) {
    testWidgets(
      'retained callback rejects changed $mutation before another frame',
      (tester) async {
        final plan = _copyPlan(DesignAutomationFixtures.plan());
        final targets = [_target()];
        var confirms = 0;
        await tester.pumpWidget(
          _app(
            _decision(
              plan: plan,
              targets: targets,
              profile: _profile(),
              onConfirm: () => confirms++,
            ),
          ),
        );
        final callback = tester
            .widget<FilledButton>(_button('Подтвердить план'))
            .onPressed;
        expect(callback, isNotNull);
        if (mutation == 'nested plan') {
          (plan['exactParams'] as Map<String, Object?>)['greeting'] = 'Подмена';
        } else {
          targets[0] = _target(address: '192.0.2.99');
        }
        callback!();
        expect(confirms, 0);
      },
    );
  }

  testWidgets(
    'a fresh review permits new consent after old state was retired',
    (tester) async {
      final key = GlobalKey();
      final plan = DesignAutomationFixtures.plan();
      var confirms = 0;
      Future<void> mount(List<ProfileView> targets) async {
        await tester.pumpWidget(
          _app(
            _decision(
              key: key,
              plan: _copyPlan(plan),
              targets: targets,
              profile: _profile(),
              onConfirm: () => confirms++,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount([_target()]);
      final originalState = key.currentState;
      expect(_canConfirm(tester), isTrue);
      await mount([]);
      await mount([_target()]);
      expect(_canConfirm(tester), isFalse);
      expect(confirms, 0);
      await tester.pumpWidget(const SizedBox());
      await mount([_target()]);
      expect(key.currentState, isNot(same(originalState)));
      expect(_canConfirm(tester), isTrue);
      expect(confirms, 0);
      await _tap(tester, 'Подтвердить план');
      expect(confirms, 1);
    },
  );
}
