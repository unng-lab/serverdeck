import 'dart:ui' show PointerDeviceKind, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/automation/automation_panel.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/profiles/profile_list.dart';
import 'package:serverdeck/servers/server_sections.dart';
import 'package:serverdeck/servers/server_compositions.dart';
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/software/software_panel.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck/ui/deck_page.dart';
import 'package:serverdeck_protocol/models.dart';

import '../contract/profile_controller_test.dart' as model_fixture;
import '../support/design_host.dart' show loadDesignFonts;
import '../support/design_host.dart' as design;
import '../support/design_scenarios.dart';
import '../support/design_stock_paint_support.dart' show stockTabTo;

Finder _item(FoundationSection section) =>
    find.byKey(ValueKey('foundation-navigation-${section.name}'));

Widget _app({
  bool dark = false,
  double scale = 1,
  double keyboard = 0,
  double safeBottom = 0,
}) => MaterialApp(
  theme: dark ? BrandTheme.dark : BrandTheme.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      viewInsets: EdgeInsets.only(bottom: keyboard),
      viewPadding: EdgeInsets.only(bottom: safeBottom),
      padding: EdgeInsets.only(bottom: keyboard == 0 ? safeBottom : 0),
    ),
    child: child!,
  ),
  home: const FoundationShell(
    state: ReadinessState.ready,
    targetName: 'Длинная цель сервера 東京 пример рабочей группы',
    targetAddress: 'server-with-a-long-name.example.invalid:2222',
    servers: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [TextField(key: ValueKey('layout-draft'))],
      ),
    ),
  ),
);

void _setFrame(WidgetTester tester, Size frame) {
  tester.view.physicalSize = frame;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

double _sideWidth(WidgetTester tester) =>
    tester.getSize(find.byKey(const ValueKey('foundation-sidebar'))).width;

String _selectedLabel(WidgetTester tester) {
  final shell = tester.state(find.byType(FoundationShell));
  // Inspect semantic state of the real navigation control, independent of pages.
  for (final section in FoundationSection.values) {
    if (tester
            .getSemantics(_item(section))
            .getSemanticsData()
            .flagsCollection
            .isSelected ==
        Tristate.isTrue)
      return section.label;
  }
  throw StateError('No selected navigation control in $shell');
}

Widget _denseApp(
  Widget child, {
  required bool dark,
  bool ownScroll = false,
  bool modal = false,
}) => MaterialApp(
  theme: Motion.theme(dark ? BrandTheme.dark : BrandTheme.light, true),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: const TextScaler.linear(2), disableAnimations: true),
    child: child!,
  ),
  home: modal
      ? Scaffold(body: child)
      : FoundationShell(
          state: ReadinessState.ready,
          targetName: 'Синтетическая цель 例',
          targetAddress: 'server.example.invalid:2222',
          servers: ownScroll ? child : SingleChildScrollView(child: child),
        ),
);

Map<String, Object?> _effects(DesignScenarioHarness harness) => {
  'callbacks': harness.counters.values,
  'reads': harness.client.reads.length,
  'refreshes': harness.client.refreshes,
  'mutations': harness.client.mutations.length,
  'status': harness.client.statusRequests.length,
};

void _expectVerticalPages(WidgetTester tester) {
  for (final element in find.byType(Scrollable).evaluate()) {
    final widget = element.widget as Scrollable;
    final horizontal =
        widget.axisDirection == AxisDirection.left ||
        widget.axisDirection == AxisDirection.right;
    final boundedTabs =
        element.findAncestorWidgetOfExactType<DeckTabs>() != null;
    expect(
      horizontal &&
          element.findAncestorWidgetOfExactType<EditableText>() == null &&
          !boundedTabs,
      isFalse,
      reason: 'Whole pages, lists and cards must wrap horizontally',
    );
    if (boundedTabs) {
      expect(
        tester.getSize(find.byWidget(widget)).width,
        lessThanOrEqualTo(tester.view.physicalSize.width),
      );
    }
  }
}

void _expectParagraphsInWidth(WidgetTester tester, double width) {
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    if (!paragraph.hasSize || paragraph.size.isEmpty) continue;
    if (element.findAncestorWidgetOfExactType<DeckTabs>() != null) {
      expect(paragraph.didExceedMaxLines, isFalse);
      continue; // Canonical tab strips expose whole labels by their own scroll.
    }
    final bounds = MatrixUtils.transformRect(
      paragraph.getTransformTo(null),
      Offset.zero & paragraph.size,
    );
    expect(bounds.left, greaterThanOrEqualTo(-.1));
    expect(
      bounds.right,
      lessThanOrEqualTo(width + .1),
      reason: paragraph.text.toPlainText(),
    );
  }
}

void _expectFullText(WidgetTester tester, String value, double width) {
  final finder = find.text(value);
  expect(finder, findsWidgets);
  for (final element in finder.evaluate()) {
    final widget = element.widget as Text;
    expect(widget.maxLines, isNull);
    expect(widget.overflow, isNot(TextOverflow.ellipsis));
    final paragraph = element.renderObject! as RenderParagraph;
    expect(paragraph.didExceedMaxLines, isFalse);
    final last = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: value.length - 1, extentOffset: value.length),
    );
    expect(last, isNotEmpty);
    expect(last.last.right, lessThanOrEqualTo(paragraph.size.width + .1));
    expect(
      paragraph.localToGlobal(Offset(paragraph.size.width, 0)).dx,
      lessThanOrEqualTo(width),
    );
  }
}

void main() {
  setUpAll(loadDesignFonts);

  for (final width in [360.0, 390.0]) {
    for (final dark in [false, true]) {
      for (final id in const [
        '06-server-overview',
        '13-mutation-conflict',
        '16-install-catalog',
        '17-recipe-detail',
        '18-install-preflight',
        '22-server-logs',
        '27-job-list',
        '28-job-detail',
        '29-job-unknown',
        '30-job-cancel',
        '31-recent-operations',
        '32-automation-profiles',
        '34-profile-revisions',
        '36-ai-grants',
        '38-mcp-client-config',
        '94-plan-invalidated',
      ]) {
        testWidgets('dense production $id width=$width dark=$dark scale=2', (
          tester,
        ) async {
          final host = await design.mountDesignFixture(
            tester,
            designBindings.singleWhere((binding) => binding.screenId == id),
            frame: Size(width, 800),
            theme: dark ? ThemeMode.dark : ThemeMode.light,
            textScale: 2,
            currentBase: true,
            options: const DesignFixtureOptions(longText: true),
          );
          try {
            final before = _effects(host.harness);
            expect(host.harness.profiles.loaded, isTrue);
            expect(host.harness.profiles.profiles, hasLength(1));
            _expectVerticalPages(tester);
            _expectParagraphsInWidth(tester, width);
            expect(find.byType(FoundationShell), findsOneWidget);
            expect(
              host.harness.profiles.selected?.id,
              host.harness.initialProfile.id,
            );
            // Each section exposes its own captured target; shell-wide text no longer duplicates it.
            expect(
              find.byKey(const ValueKey('foundation-feature-slot')),
              findsOneWidget,
            );
            await tester.pump(const Duration(milliseconds: 200));
            expect(_effects(host.harness), before);
            expect(tester.takeException(), isNull);
          } finally {
            await host.close(tester);
          }
        });
      }

      testWidgets(
        'maximum profile values wrap width=$width dark=$dark scale=2',
        (tester) async {
          _setFrame(tester, Size(width, 800));
          final harness = await DesignScenarioHarness.create();
          try {
            final original = model_fixture.snapshot();
            final row = Map<String, Object?>.of(
              (original.profiles.result['profiles'] as List).single
                  as Map<String, Object?>,
            );
            final name = List.filled(12, 'Профиль例').join().padRight(128, 'Я');
            final address = List.filled(4, 'a' * 62).join('.');
            final tags = [
              for (var index = 0; index < 16; index++)
                'метка例_${index}_${'я' * 50}',
            ];
            row.addAll({
              'name': name,
              'address': address,
              'sshUser': 'u' * 64,
              'tags': tags,
            });
            harness.client.events.add(
              ClientSnapshot(
                ApiReply(harness.client.generationId, {
                  'storeRevision': '1',
                  'profiles': [row],
                }),
                original.settings,
              ),
            );
            await tester.pumpWidget(
              _denseApp(
                ProfileList(controller: harness.profiles),
                dark: dark,
                ownScroll: true,
              ),
            );
            final before = _effects(harness);
            final tile = find.byKey(const ValueKey(model_fixture.profileId));
            expect(harness.profiles.loaded, isTrue);
            expect(harness.profiles.profiles, hasLength(1));
            await tester.scrollUntilVisible(
              tile,
              150,
              scrollable: find
                  .descendant(
                    of: find.byType(ProfileList),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            for (final value in [name, '$address:22', ...tags]) {
              _expectFullText(tester, value, width);
            }
            final open = find.widgetWithText(FilledButton, 'Открыть сервер');
            await tester.ensureVisible(open);
            await tester.tap(open);
            await tester.pumpAndSettle();
            _expectFullText(tester, name, width);
            _expectFullText(tester, '$address:22', width);
            _expectFullText(tester, 'Пользователь SSH: ${'u' * 64}', width);
            _expectVerticalPages(tester);
            _expectParagraphsInWidth(tester, width);
            expect(harness.profiles.profiles, hasLength(1));
            expect(harness.profiles.profiles.single.tags, tags);
            expect(_effects(harness), before);
            var choices = 0;
            await tester.pumpWidget(
              _denseApp(
                SoftwareServerSelector(
                  profiles: harness.profiles.profiles,
                  selectedId: harness.profiles.profiles.single.id,
                  onChoose: () => choices++,
                ),
                dark: dark,
              ),
            );
            final selectedAddress = '$address:22';
            final selectedTarget = '$name · $selectedAddress';
            _expectFullText(tester, selectedTarget, width);
            final fullTarget = find.text(selectedTarget);
            await tester.ensureVisible(fullTarget);
            await tester.pumpAndSettle();
            final semantics = tester.ensureSemantics();
            expect(
              tester.getSemantics(fullTarget).getSemanticsData().label,
              contains(selectedTarget),
            );
            semantics.dispose();
            final choose = find.widgetWithText(TextButton, 'Изменить сервер');
            await tester.ensureVisible(choose);
            await tester.pumpAndSettle();
            expect(choose.hitTestable(), findsOneWidget);
            await tester.tap(choose);
            await tester.pumpAndSettle();
            expect(choices, 1);
            expect(_effects(harness), before);
            _expectVerticalPages(tester);
            _expectParagraphsInWidth(tester, width);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await harness.close();
          }
        },
      );

      testWidgets(
        'full log text has inner scroll and context width=$width dark=$dark scale=2',
        (tester) async {
          _setFrame(tester, Size(width, 800));
          final message = List.filled(
            30,
            'Синтетическая запись 例 /usr/bin/command-with-a-long-argument '
            'SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n',
          ).join();
          final profile = ProfileView(
            id: DesignServerFixtures.serverId,
            revision: '2',
            name: List.filled(8, 'Целевой сервер 例').join(' '),
            address: '${'a' * 63}.${'b' * 63}.example',
            port: 2222,
            sshUser: 'synthetic',
            tags: const [],
            credentialRevision: '1',
            connectionRevision: '1',
            trustRevision: '2',
            createdAt: DesignServerFixtures.observedAt,
            updatedAt: DesignServerFixtures.observedAt,
            credentialKind: CredentialKind.password,
            credentialConfigured: true,
          );
          const recordTime = '2026-10-24T07:08:09.000Z';
          final logs = DesignServerFixtures.logs(
            records: [
              DesignServerFixtures.record(
                timestamp: recordTime,
                message: message,
              ),
            ],
          );
          final contextText = [
            profile.name,
            '${profile.address}:${profile.port}',
            'journald',
            '$recordTime UTC',
            '${DesignServerFixtures.observedAt} UTC',
          ];
          var closed = 0;
          await tester.pumpWidget(
            _denseApp(
              ServerLogRecordDialog(
                recordContext: ServerLogRecordContext.capture(profile, logs),
                record:
                    (logs['records'] as List).single as Map<String, Object?>,
                onClose: () => closed++,
              ),
              dark: dark,
              modal: true,
            ),
          );
          final text = find.byWidgetPredicate(
            (widget) => widget is SelectableText && widget.data == message,
          );
          expect(text, findsOneWidget);
          final rawScroll = find
              .ancestor(of: text, matching: find.byType(SingleChildScrollView))
              .first;
          final semantics = tester.ensureSemantics();
          for (final value in contextText) {
            final label = find.text(value);
            expect(label, findsOneWidget);
            final editable = tester.widget<EditableText>(label);
            expect(editable.controller.text, value);
            expect(editable.readOnly, isTrue);
            expect(editable.maxLines, isNull);
            final render = tester
                .state<EditableTextState>(label)
                .renderEditable;
            final last = render.getBoxesForSelection(
              TextSelection(
                baseOffset: value.length - 1,
                extentOffset: value.length,
              ),
            );
            expect(last, isNotEmpty);
            expect(last.last.right, lessThanOrEqualTo(render.size.width + .1));
            final bounds = tester.getRect(label);
            expect(bounds.left, greaterThanOrEqualTo(0));
            expect(bounds.right, lessThanOrEqualTo(width));
            await tester.ensureVisible(label);
            await tester.pumpAndSettle();
            // Very long readonly facts may exceed a phone viewport at 200%.
            // The outer page exposes them without truncating the actual value.
            final visible = tester.getRect(label);
            expect(visible.right, lessThanOrEqualTo(width));
            expect(visible.left, greaterThanOrEqualTo(0));
            expect(visible.bottom, greaterThan(0));
            expect(visible.top, lessThan(800));
            expect(tester.getSemantics(label).getSemanticsData().value, value);
            final row = find
                .ancestor(
                  of: label,
                  matching: find.byWidgetPredicate(
                    (widget) => widget.key is ServerFactRowKey,
                  ),
                )
                .first;
            final factLabel = find.descendant(
              of: row,
              matching: find.byType(Text),
            );
            expect(factLabel, findsOneWidget);
            expect(
              tester.getSemantics(factLabel).getSemanticsData().label,
              contains(tester.widget<Text>(factLabel).data!),
            );
          }
          semantics.dispose();
          await tester.ensureVisible(rawScroll);
          await tester.pumpAndSettle();
          final before = {
            for (final value in contextText)
              value: tester.getRect(find.text(value)),
          };
          final position = tester
              .state<ScrollableState>(
                find
                    .descendant(
                      of: rawScroll,
                      matching: find.byType(Scrollable),
                    )
                    .first,
              )
              .position;
          final offsetBefore = position.pixels;
          await tester.drag(rawScroll, const Offset(0, -360));
          await tester.pumpAndSettle();
          expect(position.pixels, greaterThan(offsetBefore));
          for (final value in contextText) {
            expect(tester.getRect(find.text(value)), before[value]);
          }
          _expectVerticalPages(tester);
          _expectParagraphsInWidth(tester, width);
          expect(closed, 0);
          expect(tester.takeException(), isNull);
        },
      );
      testWidgets(
        'full MCP command and labels width=$width dark=$dark scale=2',
        (tester) async {
          _setFrame(tester, Size(width, 800));
          final name = List.filled(10, 'Клиент例').join();
          final command =
              r'C:\Synthetic\' +
              List.filled(12, 'длинныйкаталог例').join(r'\') +
              r'\serverdeck-mcp.exe';
          final configuration = {
            'command': command,
            'args': [
              '--app-root',
              r'C:\Synthetic\Рабочая область例',
              '--grant-id',
              DesignAutomationFixtures.grantId,
            ],
          };
          final counters = DesignCallbackCounters();
          await tester.pumpWidget(
            _denseApp(
              AutomationGrantsSection(
                grants: [
                  AutomationGrantPresentation(
                    value: {...DesignAutomationFixtures.grant(), 'label': name},
                    current: true,
                  ),
                ],
                loaded: true,
                actions: const AutomationActionAvailability(
                  read: true,
                  mutate: true,
                  select: true,
                ),
                launchConfiguration: configuration,
                onRefresh: counters.callback('refresh'),
                onCreate: counters.callback('create'),
                onConfigure: counters.change('configure'),
                onEdit: counters.change('edit'),
                onRevoke: counters.change('revoke'),
                onCopyConfiguration: counters.callback('copy'),
              ),
              dark: dark,
            ),
          );
          await tester.pumpAndSettle();
          _expectFullText(tester, name, width);
          final commandValue = find.descendant(
            of: find.byWidgetPredicate(
              (widget) =>
                  widget is AutomationExactValue && widget.label == 'Команда',
            ),
            matching: find.byType(EditableText),
          );
          final editor = tester.widget<EditableText>(commandValue);
          expect(editor.controller.text, command);
          expect(editor.readOnly, isTrue);
          expect(editor.maxLines, isNull);
          await tester.ensureVisible(commandValue);
          await tester.pumpAndSettle();
          final commandRender = tester
              .state<EditableTextState>(commandValue)
              .renderEditable;
          final lastGlyph = commandRender.getBoxesForSelection(
            TextSelection(
              baseOffset: command.length - 1,
              extentOffset: command.length,
            ),
          );
          expect(lastGlyph, isNotEmpty);
          expect(
            lastGlyph.last.right,
            lessThanOrEqualTo(commandRender.size.width + .1),
          );
          final semantics = tester.ensureSemantics();
          expect(
            tester.getSemantics(commandValue).getSemanticsData().value,
            command,
          );
          semantics.dispose();
          final title = find.text('Команда и аргументы MCP');
          await tester.ensureVisible(title);
          await tester.pumpAndSettle();
          final expansion = find
              .ancestor(of: title, matching: find.byType(ExpansionTile))
              .first;
          await stockTabTo(tester, expansion);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          final details = find.ancestor(
            of: title,
            matching: find.byType(AutomationJsonView),
          );
          final json = tester
              .widget<SelectableText>(
                find.descendant(
                  of: details,
                  matching: find.byType(SelectableText),
                ),
              )
              .data!;
          expect(json, contains('длинныйкаталог例'));
          expect(json, contains('serverdeck-mcp.exe'));
          expect(json, contains(DesignAutomationFixtures.grantId));
          expect(counters.values, isEmpty);
          final copy = find.widgetWithText(
            FilledButton,
            'Скопировать конфигурацию',
          );
          await tester.ensureVisible(copy);
          await tester.pumpAndSettle();
          expect(copy.hitTestable(), findsOneWidget);
          await tester.tap(copy);
          await tester.pumpAndSettle();
          expect(counters.values, {'copy': 1});
          _expectVerticalPages(tester);
          _expectParagraphsInWidth(tester, width);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'job event bound and pagination width=$width dark=$dark scale=2',
        (tester) async {
          _setFrame(tester, Size(width, 800));
          final counters = DesignCallbackCounters();
          final job = DesignAutomationFixtures.job();
          await tester.pumpWidget(
            _denseApp(
              AutomationJobsSection(
                serverId: DesignAutomationFixtures.serverId,
                jobs: [
                  {'job': job},
                ],
                job: job,
                events: DesignAutomationFixtures.events(
                  count: 200,
                  dropped: 13,
                ),
                loaded: true,
                hasMore: true,
                droppedEvents: 13,
                canCancel: true,
                canReconcile: false,
                actions: const AutomationActionAvailability(
                  read: true,
                  mutate: true,
                  select: true,
                ),
                onRefresh: counters.callback('refresh'),
                onRefreshAuthorities: counters.callback('authorities'),
                onSelect: counters.change('select'),
                onMore: counters.callback('more'),
                onShowPlan: counters.callback('plan'),
                onCancel: counters.callback('cancel'),
                onReconcile: counters.callback('reconcile'),
              ),
              dark: dark,
            ),
          );
          expect(
            find.text('Получено событий: 200. Пропущено в источнике: 13'),
            findsOneWidget,
          );
          final title = find.text('Ход выполнения');
          final events = find
              .ancestor(of: title, matching: find.byType(DeckPanel))
              .first;
          final eventTimes = tester.widgetList<Tooltip>(
            find.descendant(of: events, matching: find.byType(Tooltip)),
          );
          expect(eventTimes, hasLength(200));
          expect(
            eventTimes.map((widget) => widget.message),
            DesignAutomationFixtures.events(
              count: 200,
              dropped: 13,
            ).map((event) => '${event['timestamp']} (UTC)'),
          );
          expect(
            tester
                .widget<AutomationJobsSection>(
                  find.byType(AutomationJobsSection),
                )
                .events,
            DesignAutomationFixtures.events(count: 200, dropped: 13),
          );
          expect(find.text('Пропущено событий: 13'), findsOneWidget);
          _expectVerticalPages(tester);
          _expectParagraphsInWidth(tester, width);
          expect(counters.values, isEmpty);
          final back = find.widgetWithText(TextButton, 'К заданиям');
          await tester.ensureVisible(back);
          await tester.tap(back);
          await tester.pumpAndSettle();
          final more = find.widgetWithText(OutlinedButton, 'Ещё задания');
          await tester.ensureVisible(more);
          await tester.tap(more);
          await tester.pumpAndSettle();
          expect(counters.values, {'more': 1});
          expect(tester.takeException(), isNull);
        },
      );
      testWidgets(
        'recipe raw details keep context width=$width dark=$dark scale=2',
        (tester) async {
          _setFrame(tester, Size(width, 800));
          var plans = 0;
          await tester.pumpWidget(
            _denseApp(
              AutomationPageFrame(
                title: 'Рецепт установки',
                screenId: '17-recipe-detail',
                catalog: true,
                section: 'catalog',
                onSelected: (_) {},
                child: AutomationRecipesSection(
                  catalog: DesignAutomationFixtures.catalog(),
                  serverId: DesignAutomationFixtures.serverId,
                  serverProfiles: [DesignServerFixtures.profile()],
                  canMutate: true,
                  onCreatePlan: (_) => plans++,
                ),
              ),
              dark: dark,
              ownScroll: true,
            ),
          );
          final choose = find.text('PostgreSQL 16');
          await tester.ensureVisible(choose);
          await tester.tap(choose);
          await tester.pumpAndSettle();
          final title = find.text(
            'Лицензии, начальные настройки и точные условия',
          );
          await tester.ensureVisible(title);
          await tester.pumpAndSettle();
          await tester.tap(title);
          await tester.pumpAndSettle();
          final details = find.ancestor(
            of: title,
            matching: find.byType(AutomationJsonView),
          );
          final text = find.descendant(
            of: details,
            matching: find.byType(SelectableText),
          );
          expect(
            tester.widget<SelectableText>(text).data,
            contains(DesignAutomationFixtures.hash),
          );
          final raw = find
              .ancestor(of: text, matching: find.byType(SingleChildScrollView))
              .first;
          final rawPosition = tester
              .state<ScrollableState>(
                find
                    .descendant(of: raw, matching: find.byType(Scrollable))
                    .first,
              )
              .position;
          expect(rawPosition.maxScrollExtent, greaterThan(0));
          await tester.ensureVisible(raw);
          await tester.pumpAndSettle();
          final targetValue =
              '${DesignServerFixtures.profile().name} · 192.0.2.44:2222';
          final target = find.text(targetValue);
          expect(target, findsOneWidget);
          _expectFullText(tester, targetValue, width);
          final targetBefore = tester.getRect(target);
          final offsetBefore = rawPosition.pixels;
          await tester.drag(raw, const Offset(0, -120));
          await tester.pumpAndSettle();
          expect(rawPosition.pixels, greaterThan(offsetBefore));
          expect(tester.getRect(target), targetBefore);
          // Context belongs to the page scroll, and remains reachable without
          // borrowing a fixed-height region from the body.
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          design.expectDesignVisible(tester, target);
          _expectVerticalPages(tester);
          _expectParagraphsInWidth(tester, width);
          expect(plans, 0);
          expect(tester.takeException(), isNull);
        },
      );
      testWidgets(
        'truncated log opens full value by keyboard and touch width=$width dark=$dark',
        (tester) async {
          _setFrame(tester, Size(width, 800));
          final message = List.filled(
            15,
            'Полная запись例 /usr/bin/long-command --option=значение ',
          ).join();
          final record = DesignServerFixtures.record(message: message);
          final filter = TextEditingController();
          final opened = <Map<String, Object?>>[];
          var reads = 0;
          try {
            await tester.pumpWidget(
              _denseApp(
                ServerLogsSection(
                  logs: DesignServerFixtures.logs(records: [record]),
                  filterController: filter,
                  busy: false,
                  onLoad: () => reads++,
                  onPrevious: () => reads++,
                  onOpenRecord: opened.add,
                ),
                dark: dark,
              ),
            );
            final summary = find.text(message);
            expect(
              tester.widget<Text>(summary).overflow,
              TextOverflow.ellipsis,
            );
            expect(
              tester.renderObject<RenderParagraph>(summary).didExceedMaxLines,
              isTrue,
            );
            final row = find.byKey(const ValueKey('server-log-row-0'));
            await tester.ensureVisible(row);
            await tester.pumpAndSettle();
            final focus = Focus.of(tester.element(summary));
            for (var tabs = 0; !focus.hasFocus && tabs < 30; tabs++) {
              await tester.sendKeyEvent(LogicalKeyboardKey.tab);
              await tester.pumpAndSettle();
            }
            expect(focus.hasFocus, isTrue);
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(opened, [record]);
            expect(opened.single['message'], message);
            await tester.ensureVisible(row);
            await tester.pumpAndSettle();
            expect(row.hitTestable(), findsOneWidget);
            await tester.tap(row);
            await tester.pumpAndSettle();
            expect(opened, [record, record]);
            expect(reads, 0);
            final source = tester
                .widgetList<ServerFactRows>(find.byType(ServerFactRows))
                .singleWhere(
                  (widget) => widget.facts['Источник'] == 'journald',
                );
            expect(source.facts['Источник'], 'journald');
            expect(find.text('journald'), findsOneWidget);
            expect(
              find.text('Наблюдение: ${DesignServerFixtures.observedAt} · UTC'),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            filter.dispose();
          }
        },
      );
    }
  }

  testWidgets('recipe target change cannot rebind retained plan callbacks', (
    tester,
  ) async {
    _setFrame(tester, const Size(390, 800));
    final catalog = DesignAutomationFixtures.catalog();
    final original = DesignServerFixtures.profile();
    final changedTargets = [
      DesignServerFixtures.profile(
        address: '192.0.2.99',
        connectionRevision: '3',
      ),
      DesignServerFixtures.profile(id: '00000000-0000-4000-8000-000000000203'),
    ];
    for (final changed in changedTargets) {
      final key = GlobalKey<AutomationRecipesSectionState>();
      final calls = <String>[];
      Future<void> mount(ProfileView target) async {
        await tester.pumpWidget(
          _denseApp(
            AutomationRecipesSection(
              key: key,
              catalog: catalog,
              canMutate: true,
              serverId: target.id,
              serverProfiles: [target],
              onCreatePlan: (digest) => calls.add('${target.id}:$digest'),
            ),
            dark: false,
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount(original);
      key.currentState!.selectFirst();
      await tester.pumpAndSettle();
      final plan = find.widgetWithText(OutlinedButton, 'Создать план');
      final retained = tester.widget<OutlinedButton>(plan).onPressed!;
      await mount(changed);
      retained();
      expect(calls, isEmpty);
      await mount(original);
      retained();
      expect(
        calls,
        isEmpty,
        reason: 'Restoring the old target does not revive an old intent',
      );
      expect(
        tester
            .widget<AutomationRecipesSection>(
              find.byType(AutomationRecipesSection),
            )
            .catalog,
        same(catalog),
      );
      expect(catalog, DesignAutomationFixtures.catalog());
      await tester.ensureVisible(plan);
      await tester.tap(plan);
      await tester.pumpAndSettle();
      expect(calls, [
        '${original.id}:${DesignAutomationFixtures.recipe()['digest']}',
      ]);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    expect(tester.takeException(), isNull);
  });

  for (final width in [520.0, 521.0, 1060.0, 1061.0]) {
    testWidgets('canonical shell boundary $width', (tester) async {
      _setFrame(tester, Size(width, 800));
      await tester.pumpWidget(_app());
      expect(
        _sideWidth(tester),
        width <= 520
            ? 0
            : width <= 1060
            ? 68
            : 210,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('foundation-topbar'))).height,
        width <= 520 ? 62 : 56,
      );
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).bottomNavigationBar !=
            null,
        width <= 520,
      );
      expect(find.byType(Drawer), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('keyboard hides phone navigation and retains draft owner', (
    tester,
  ) async {
    _setFrame(tester, const Size(390, 800));
    await tester.pumpWidget(_app(scale: 2, safeBottom: 24));
    final panel = find.byKey(const ValueKey('foundation-phone-navigation'));
    expect(tester.getRect(panel).bottom, 776);
    final field = find.byKey(const ValueKey('layout-draft'));
    await tester.enterText(field, 'RAM draft');
    final editable = find.descendant(
      of: field,
      matching: find.byType(EditableText),
    );
    final state = tester.state<EditableTextState>(editable);
    await tester.pumpWidget(_app(scale: 2, keyboard: 300, safeBottom: 24));
    expect(panel, findsNothing);
    expect(tester.state<EditableTextState>(editable), same(state));
    expect(state.widget.controller.text, 'RAM draft');
    await tester.pumpWidget(_app(scale: 2, safeBottom: 24));
    expect(panel, findsOneWidget);
    expect(tester.getRect(panel).bottom, 776);
    expect(tester.takeException(), isNull);
  });
  testWidgets('short desktop keeps every navigation target reachable', (
    tester,
  ) async {
    _setFrame(tester, const Size(1100, 240));
    await tester.pumpWidget(_app(scale: 2));
    for (final section in FoundationSection.values) {
      await tester.ensureVisible(_item(section));
      await tester.pumpAndSettle();
      expect(_item(section).hitTestable(), findsOneWidget);
      await tester.tap(_item(section));
      await tester.pumpAndSettle();
      expect(_selectedLabel(tester), section.label);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('breakpoint focus follows selected chrome without activation', (
    tester,
  ) async {
    _setFrame(tester, const Size(1100, 800));
    await tester.pumpWidget(_app());
    for (final width in [800.0, 390.0, 1100.0]) {
      tester
          .widget<TextButton>(_item(FoundationSection.jobs))
          .focusNode!
          .requestFocus();
      await tester.pumpAndSettle();
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(_item(FoundationSection.servers))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      expect(_selectedLabel(tester), 'Серверы');
      expect(find.byKey(const ValueKey('layout-draft')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('breakpoint keeps existing field focus and draft', (
    tester,
  ) async {
    _setFrame(tester, const Size(1100, 800));
    await tester.pumpWidget(_app());
    final field = find.byKey(const ValueKey('layout-draft'));
    await tester.enterText(field, 'Retained draft');
    final focus = FocusManager.instance.primaryFocus;
    for (final width in [800.0, 390.0, 1100.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(focus));
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: field, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        'Retained draft',
      );
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('rail exposes full names through hover focus and long press', (
    tester,
  ) async {
    _setFrame(tester, const Size(800, 600));
    await tester.pumpWidget(_app());
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    await pointer.moveTo(tester.getCenter(_item(FoundationSection.logs)));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.text('Журналы'), findsOneWidget);
    await pointer.removePointer();
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(find.text('Журналы'), findsNothing);
    tester
        .widget<TextButton>(_item(FoundationSection.jobs))
        .focusNode!
        .requestFocus();
    await tester.pumpAndSettle();
    expect(find.text('Задания'), findsOneWidget);
    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('Задания'), findsNothing);
    await tester.longPress(_item(FoundationSection.settings));
    await tester.pumpAndSettle();
    expect(find.text('Настройки'), findsOneWidget);
    expect(_selectedLabel(tester), 'Серверы');
    expect(tester.takeException(), isNull);
  });
  testWidgets('phone and rail support Enter and Space', (tester) async {
    _setFrame(tester, const Size(800, 600));
    await tester.pumpWidget(_app());
    for (final frame in [const Size(800, 600), const Size(390, 800)]) {
      tester.view.physicalSize = frame;
      await tester.pumpAndSettle();
      for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
        tester
            .widget<TextButton>(_item(FoundationSection.settings))
            .focusNode!
            .requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(_selectedLabel(tester), 'Настройки');
        await tester.tap(_item(FoundationSection.servers));
        await tester.pumpAndSettle();
      }
    }
    expect(tester.takeException(), isNull);
  });
}
