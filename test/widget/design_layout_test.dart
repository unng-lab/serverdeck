import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/profiles/profile_list.dart';
import 'package:serverdeck/servers/server_sections.dart';
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/software/software_panel.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck/ui/deck_components.dart';
import 'package:serverdeck_protocol/models.dart';

import '../contract/profile_controller_test.dart' as model_fixture;
import '../support/design_host.dart' show loadDesignFonts;
import '../support/design_host.dart' as design;
import '../support/design_scenarios.dart';

const _frames = [
  Size(1100, 760),
  Size(800, 600),
  Size(390, 800),
  Size(360, 800),
];

Finder _item(FoundationSection section) =>
    find.widgetWithIcon(OutlinedButton, section.icon);

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

double _labelWidth(BuildContext context, String label, FontWeight weight) {
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: BrandTypography.caption.copyWith(fontWeight: weight),
    ),
    textDirection: Directionality.of(context),
    locale: Localizations.maybeLocaleOf(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final result = painter.width;
  painter.dispose();
  return result;
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
    expect(
      horizontal &&
          element.findAncestorWidgetOfExactType<EditableText>() == null,
      isFalse,
      reason: 'Whole pages, lists and cards must wrap horizontally',
    );
  }
}

void _expectParagraphsInWidth(WidgetTester tester, double width) {
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    if (!paragraph.hasSize || paragraph.size.isEmpty) continue;
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
  expect(finder, findsOneWidget);
  final widget = tester.widget<Text>(finder);
  expect(widget.maxLines, isNull);
  expect(widget.overflow, isNot(TextOverflow.ellipsis));
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  expect(paragraph.didExceedMaxLines, isFalse);
  final last = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: value.length - 1, extentOffset: value.length),
  );
  expect(last, isNotEmpty);
  expect(last.last.right, lessThanOrEqualTo(paragraph.size.width + .1));
  expect(tester.getRect(finder).right, lessThanOrEqualTo(width));
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
            options: const DesignFixtureOptions(longText: true),
          );
          try {
            final before = _effects(host.harness);
            expect(host.harness.profiles.loaded, isTrue);
            expect(host.harness.profiles.profiles, hasLength(1));
            _expectVerticalPages(tester);
            _expectParagraphsInWidth(tester, width);
            expect(find.byType(FoundationShell), findsOneWidget);
            final target = find.textContaining(
              host.harness.profiles.selected!.name,
            );
            expect(target, findsWidgets);
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
            final disclosure = find
                .descendant(of: tile, matching: find.byType(Icon))
                .first;
            await tester.ensureVisible(disclosure);
            await tester.pumpAndSettle();
            expect(disclosure.hitTestable(), findsOneWidget);
            await tester.tap(disclosure);
            await tester.pumpAndSettle();
            for (final value in [
              name,
              '$address:22',
              'Пользователь SSH: ${'u' * 64}',
              'Метки: ${tags.join(', ')}',
            ]) {
              _expectFullText(tester, value, width);
            }
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
            _expectFullText(tester, name, width);
            final selectedAddress = '$address:22';
            final fullAddress = find.text(selectedAddress);
            expect(
              tester.widget<EditableText>(fullAddress).controller.text,
              selectedAddress,
            );
            final choose = find.widgetWithText(
              OutlinedButton,
              'Изменить сервер',
            );
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
            'Источник: journald',
            'Время записи: $recordTime UTC',
            'Наблюдение: ${DesignServerFixtures.observedAt} UTC',
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
            _expectFullText(tester, value, width);
            final label = find.text(value);
            await tester.ensureVisible(label);
            await tester.pumpAndSettle();
            design.expectDesignVisible(tester, label);
            expect(find.bySemanticsLabel(value), findsOneWidget);
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
          final section = find.text('Доступ ИИ рабочего пространства');
          await tester.ensureVisible(section);
          await tester.pumpAndSettle();
          await tester.tap(section);
          await tester.pumpAndSettle();
          _expectFullText(tester, name, width);
          expect(
            tester.widget<EditableText>(find.text(command)).controller.text,
            command,
          );
          final title = find.text('Команда и аргументы MCP');
          await tester.ensureVisible(title);
          await tester.pumpAndSettle();
          final focus = Focus.of(tester.element(title));
          for (var tabs = 0; !focus.hasFocus && tabs < 30; tabs++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pumpAndSettle();
          }
          expect(focus.hasFocus, isTrue);
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
            OutlinedButton,
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
          expect(find.text('Ещё задания'), findsOneWidget);
          final title = find.text('Последние 200 полученных событий');
          await tester.ensureVisible(title);
          await tester.pumpAndSettle();
          await tester.tap(title);
          await tester.pumpAndSettle();
          final events = find.ancestor(
            of: title,
            matching: find.byType(ExpansionTile),
          );
          expect(
            find.descendant(of: events, matching: find.byType(DeckKeyValue)),
            findsNWidgets(200),
          );
          expect(find.text('Пропущено событий: 13'), findsOneWidget);
          _expectVerticalPages(tester);
          _expectParagraphsInWidth(tester, width);
          expect(counters.values, isEmpty);
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
              AutomationRecipesSection(
                catalog: DesignAutomationFixtures.catalog(),
                canMutate: true,
                onCreatePlan: (_) => plans++,
              ),
              dark: dark,
            ),
          );
          final title = find.text('Точный рецепт, параметры и условия');
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
          await tester.ensureVisible(title);
          await tester.pumpAndSettle();
          final target = find.text(
            'Синтетическая цель 例 · server.example.invalid:2222',
          );
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          design.expectDesignVisible(tester, target);
          final targetBefore = tester.getRect(target);
          final offsetBefore = rawPosition.pixels;
          await tester.drag(raw, const Offset(0, -120));
          await tester.pumpAndSettle();
          expect(rawPosition.pixels, greaterThan(offsetBefore));
          expect(tester.getRect(target), targetBefore);
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
            final row = find.ancestor(
              of: summary,
              matching: find.byType(ListTile),
            );
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
            expect(find.text('Источник: journald · UTC'), findsOneWidget);
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

  for (final width in [520.0, 521.0, 1060.0, 1061.0]) {
    testWidgets('production shell switches exactly at width $width', (
      tester,
    ) async {
      _setFrame(tester, Size(width, 800));
      await tester.pumpWidget(_app());
      final expectedWidth = width <= 520 ? 0.0 : (width <= 1060 ? 72.0 : 210.0);
      expect(_sideWidth(tester), expectedWidth);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.bottomNavigationBar != null, width <= 520);
      expect(find.byType(Drawer), findsNothing);
      expect(tester.getSize(find.byType(AppBar)).height, 56);
      expect(tester.takeException(), isNull);
    });
  }

  for (final frame in _frames) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('shell $frame dark=$dark scale=$scale', (tester) async {
          _setFrame(tester, frame);
          final semantics = tester.ensureSemantics();
          try {
            await tester.pumpWidget(_app(dark: dark, scale: scale));
            final phone = frame.width <= 520;
            final rail = frame.width > 520 && frame.width <= 1060;
            expect(_sideWidth(tester), phone ? 0 : (rail ? 72 : 210));
            expect(tester.getSize(find.byType(AppBar)).height, 56);
            final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
            expect(scaffold.bottomNavigationBar != null, phone);
            final contentRect = tester.getRect(find.byType(TextField));
            expect(
              contentRect.left - _sideWidth(tester) - (phone ? 0 : 1),
              phone ? 16 : 24,
            );
            expect(frame.width - contentRect.right, phone ? 16 : 24);

            for (final section in FoundationSection.values) {
              final button = _item(section);
              await tester.ensureVisible(button);
              expect(tester.getSize(button).width, greaterThanOrEqualTo(44));
              expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
              final node = tester.getSemantics(button);
              expect(node.label, section.label);
              expect(node.flagsCollection.isButton, isTrue);
              final label = find.descendant(
                of: button,
                matching: find.text(section.label),
              );
              expect(label, rail ? findsNothing : findsOneWidget);
              if (rail) {
                expect(find.byTooltip(section.label), findsOneWidget);
              }
              await tester.tap(button);
              await tester.pumpAndSettle();
              expect(
                tester.getSemantics(button).flagsCollection.isSelected,
                Tristate.isTrue,
              );
              final title = tester.widget<Text>(
                find.byKey(const ValueKey('foundation-page-title')),
              );
              expect(title.data, section.label);
              expect(title.style!.fontSize, 24);
              expect(title.style!.height! * title.style!.fontSize!, 32);
              expect(tester.takeException(), isNull);
            }
            if (phone) {
              final panel = tester.getRect(
                find.byKey(const ValueKey('foundation-phone-navigation')),
              );
              expect(contentRect.bottom, lessThanOrEqualTo(panel.top));
            }
          } finally {
            semantics.dispose();
          }
        });
      }
    }
  }

  for (final width in [360.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('phone Wrap measures full labels at $width scale=$scale', (
        tester,
      ) async {
        _setFrame(tester, Size(width, 800));
        await tester.pumpWidget(_app(scale: scale));
        final panelFinder = find.byKey(
          const ValueKey('foundation-phone-navigation'),
        );
        expect(panelFinder, findsOneWidget);
        final panel = tester.getRect(panelFinder);
        final wrap = tester.widget<Wrap>(
          find.descendant(of: panelFinder, matching: find.byType(Wrap)),
        );
        expect(wrap.spacing, 4);
        expect(wrap.runSpacing, 4);
        final context = tester.element(_item(FoundationSection.servers));
        final before = <Rect>[];
        for (final section in FoundationSection.values) {
          final normal = _labelWidth(context, section.label, FontWeight.w400);
          final selected = _labelWidth(context, section.label, FontWeight.w600);
          final expected = math.min(
            width - 8,
            math.max(44.0, math.max(normal, selected).ceilToDouble() + 8),
          );
          final rect = tester.getRect(_item(section));
          expect(rect.width, expected);
          final text = tester.widget<Text>(
            find.descendant(of: _item(section), matching: find.byType(Text)),
          );
          expect(text.maxLines, isNull);
          expect(text.overflow, isNot(TextOverflow.ellipsis));
          expect(text.style!.fontSize, 12);
          expect(text.style!.height! * text.style!.fontSize!, 16);
          final icon = tester.widget<Icon>(
            find.descendant(of: _item(section), matching: find.byType(Icon)),
          );
          expect(icon.size, 20);
          final iconRect = tester.getRect(
            find.descendant(of: _item(section), matching: find.byType(Icon)),
          );
          final labelRect = tester.getRect(
            find.descendant(of: _item(section), matching: find.byType(Text)),
          );
          expect(iconRect.top - rect.top, 8);
          expect(labelRect.top - iconRect.bottom, 4);
          expect(rect.bottom - labelRect.bottom, 8);
          expect(rect.left, greaterThanOrEqualTo(panel.left + 4));
          expect(rect.right, lessThanOrEqualTo(panel.right - 4));
          before.add(rect);
        }
        final rows = before.map((rect) => rect.top).toSet().toList()..sort();
        if (scale == 2) expect(rows.length, greaterThan(1));
        final lastBottom = before.map((rect) => rect.bottom).reduce(math.max);
        expect(before.first.top - panel.top, 8);
        expect(panel.bottom - lastBottom, 8);
        for (var i = 1; i < rows.length; i++) {
          final previousBottom = before
              .where((rect) => rect.top == rows[i - 1])
              .map((rect) => rect.bottom)
              .reduce(math.max);
          expect(rows[i] - previousBottom, 4);
        }
        await tester.tap(_item(FoundationSection.settings));
        await tester.pumpAndSettle();
        expect(
          FoundationSection.values.map(
            (section) => tester.getRect(_item(section)),
          ),
          before,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('keyboard hides and returns phone nav without losing draft', (
    tester,
  ) async {
    _setFrame(tester, const Size(390, 800));
    await tester.pumpWidget(_app(scale: 2, safeBottom: 24));
    final panel = find.byKey(const ValueKey('foundation-phone-navigation'));
    expect(panel, findsOneWidget);
    expect(tester.getRect(panel).bottom, 776);
    await tester.enterText(
      find.byKey(const ValueKey('layout-draft')),
      'RAM draft',
    );
    final editable = find.descendant(
      of: find.byKey(const ValueKey('layout-draft')),
      matching: find.byType(EditableText),
    );
    final state = tester.state<EditableTextState>(editable);
    await tester.pumpWidget(_app(scale: 2, keyboard: 300, safeBottom: 24));
    expect(panel, findsNothing);
    expect(find.byKey(const ValueKey('foundation-page-title')), findsOneWidget);
    expect(state.widget.controller.text, 'RAM draft');
    expect(tester.state<EditableTextState>(editable), same(state));
    await tester.pumpWidget(_app(scale: 2, safeBottom: 24));
    expect(panel, findsOneWidget);
    expect(tester.getRect(panel).bottom, 776);
    expect(
      tester
          .getSemantics(_item(FoundationSection.servers))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    expect(state.widget.controller.text, 'RAM draft');
    await tester.tap(_item(FoundationSection.settings));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app(scale: 2, keyboard: 300, safeBottom: 24));
    expect(panel, findsNothing);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('foundation-page-title')))
          .data,
      'Настройки',
    );
    await tester.pumpWidget(_app(scale: 2, safeBottom: 24));
    expect(panel, findsOneWidget);
    expect(
      tester
          .getSemantics(_item(FoundationSection.settings))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('short desktop sidebar scrolls every section into reach', (
    tester,
  ) async {
    _setFrame(tester, const Size(1100, 240));
    await tester.pumpWidget(_app(scale: 2));
    expect(_sideWidth(tester), 210);
    for (final section in FoundationSection.values) {
      await tester.ensureVisible(_item(section));
      await tester.pumpAndSettle();
      expect(_item(section).hitTestable(), findsOneWidget);
      await tester.tap(_item(section));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('foundation-page-title')))
            .data,
        section.label,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('phone caps oversized labels to panel width and wraps the text', (
    tester,
  ) async {
    _setFrame(tester, const Size(360, 2400));
    await tester.pumpWidget(_app(scale: 8));
    final item = _item(FoundationSection.settings);
    expect(tester.getSize(item).width, 352);
    final label = find.descendant(of: item, matching: find.byType(Text));
    expect(tester.getSize(label).height, greaterThan(16 * 8));
    expect(tester.widget<Text>(label).data, 'Настройки');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'breakpoint focus follows selected chrome without activating it',
    (tester) async {
      _setFrame(tester, const Size(1100, 800));
      await tester.pumpWidget(_app());
      for (final width in [800.0, 390.0, 1100.0]) {
        tester
            .widget<OutlinedButton>(_item(FoundationSection.jobs))
            .focusNode!
            .requestFocus();
        await tester.pumpAndSettle();
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<OutlinedButton>(_item(FoundationSection.servers))
              .focusNode!
              .hasFocus,
          isTrue,
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('foundation-page-title')))
              .data,
          'Серверы',
        );
        expect(find.byKey(const ValueKey('layout-draft')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'breakpoint leaves existing field focus and draft with its owner',
    (tester) async {
      _setFrame(tester, const Size(1100, 800));
      await tester.pumpWidget(_app());
      final field = find.byKey(const ValueKey('layout-draft'));
      await tester.enterText(field, 'Retained field draft');
      final focus = FocusManager.instance.primaryFocus;
      for (final width in [800.0, 390.0, 1100.0]) {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus, same(focus));
        expect(focus!.hasFocus, isTrue);
        final editable = find.descendant(
          of: field,
          matching: find.byType(EditableText),
        );
        expect(
          tester.widget<EditableText>(editable).controller.text,
          'Retained field draft',
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'rail tooltips expose full labels on hover focus and long press',
    (tester) async {
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
          .widget<OutlinedButton>(_item(FoundationSection.jobs))
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
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('foundation-page-title')))
            .data,
        'Серверы',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('phone and rail activate navigation with Enter and Space', (
    tester,
  ) async {
    _setFrame(tester, const Size(800, 600));
    await tester.pumpWidget(_app());
    for (final frame in [const Size(800, 600), const Size(390, 800)]) {
      tester.view.physicalSize = frame;
      await tester.pumpAndSettle();
      for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
        tester
            .widget<OutlinedButton>(_item(FoundationSection.settings))
            .focusNode!
            .requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('foundation-page-title')))
              .data,
          'Настройки',
        );
        await tester.tap(_item(FoundationSection.servers));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    }
  });
}
