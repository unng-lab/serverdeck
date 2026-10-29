import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/profiles/profile_list.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/shell/private_session.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_icon.dart';
import 'package:serverdeck/ui/deck_page.dart';
import 'package:serverdeck_protocol/models.dart';

import '../contract/mutation_controller_test.dart' show MutationClient;
import '../contract/profile_controller_test.dart' as fixtures;
import '../support/design_fonts.dart';

ClientSnapshot twoProfiles({
  String revision = '1',
  bool replaceTag = false,
  String? tag,
}) {
  final source = fixtures.snapshot(revision: revision);
  final alpha =
      Map<String, Object?>.from(
          (source.profiles.result['profiles'] as List).single as Map,
        )
        ..['name'] = 'alpha profile'
        ..['revision'] = revision;
  final beta = {
    ...alpha,
    'id': '33333333-3333-4333-8333-333333333333',
    'name': 'beta profile',
    'address': '192.0.2.2',
    'tags': [tag ?? (replaceTag ? 'replacement' : 'staging')],
  };
  return ClientSnapshot(
    ApiReply(fixtures.fixtureGeneration, {
      'storeRevision': revision,
      'profiles': [alpha, beta],
    }),
    source.settings,
  );
}

Future<void> choose(WidgetTester tester, String key, String value) async {
  final menu = find.byKey(ValueKey(key));
  await tester.ensureVisible(menu);
  await tester.tap(menu);
  await tester.pumpAndSettle();
  final item = find.byWidgetPredicate(
    (w) => w is PopupMenuItem<String> && w.value == value,
  );
  await tester.ensureVisible(item);
  await tester.tap(item);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadDesignFonts);
  for (final width in [1100.0, 800.0, 390.0, 360.0, 520.0, 521.0]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('T188 profile toolbar $width $dark $scale', (tester) async {
          tester.view.physicalSize = Size(width, 1400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final client = MutationClient();
          final owner = fixtures.ModelBootstrap(client)
            ..show(ReadinessState.ready);
          final model = ProfileController(bootstrap: owner);
          client.events.add(fixtures.snapshot());
          final reads = client.refreshes;
          final semantics = tester.ensureSemantics();
          try {
            await tester.pumpWidget(
              MaterialApp(
                theme: dark ? BrandTheme.dark : BrandTheme.light,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: DeckPageInsets(
                    padding: const EdgeInsets.all(16),
                    child: ListenableBuilder(
                      listenable: model,
                      builder: (context, _) => ProfileList(controller: model),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final field = find.byType(TextField);
            final rect = tester.getRect(field);
            final phone = width <= 520;
            expect(rect.height, math.max(44, 20 * scale + 16));
            expect(rect.width, math.min(360, width - 32));
            expect(
              tester.widget<TextField>(field).decoration!.labelText,
              'Поиск по имени, адресу или меткам',
            );
            final editor = tester.widget<EditableText>(
              find.byType(EditableText),
            );
            expect(editor.style.fontSize, phone ? 14 : 13);
            expect(
              tester.getSemantics(find.byType(EditableText)).rect.height,
              greaterThanOrEqualTo(44),
            );
            expect(
              tester.getTopLeft(find.byType(EditableText)).dx - rect.left,
              34,
            );
            expect(
              tester.getSize(
                find.descendant(of: field, matching: find.byType(DeckIcon)),
              ),
              const Size(15, 15),
            );
            final filters = find.widgetWithText(OutlinedButton, 'Фильтры');
            final ai = find.widgetWithText(OutlinedButton, 'ИИ-доступ');
            final a = tester.getRect(filters), b = tester.getRect(ai);
            expect(a.left + (phone ? 0 : 4), 16);
            if (phone && scale == 1) {
              expect(b.right, width - 16);
              expect(b.left - a.right, 8);
              expect(a.width, closeTo(b.width, .01));
            }
            await tester.ensureVisible(find.text('Найти сервер'));
            await tester.tap(find.text('Найти сервер'));
            await tester.pumpAndSettle();
            expect(editor.focusNode.hasFocus, isTrue);
            if (!phone && scale == 1) {
              for (final bottom in [false, true]) {
                editor.focusNode.unfocus();
                await tester.pumpAndSettle();
                await tester.pump(const Duration(milliseconds: 400));
                final target = tester.getRect(field);
                await tester.tapAt(
                  Offset(
                    target.center.dx,
                    bottom ? target.bottom - 1 : target.top + 1,
                  ),
                );
                await tester.pumpAndSettle();
                expect(editor.focusNode.hasFocus, isTrue);
              }
            }
            await tester.enterText(field, 'Saved');
            await tester.pumpAndSettle();
            expect(find.text('Saved profile'), findsOneWidget);
            final all = find.byKey(const ValueKey('profile-filter-all'));
            await tester.ensureVisible(all);
            await tester.tap(all);
            await tester.pumpAndSettle();
            expect(editor.controller.text, 'Saved');
            expect(client.sent, isEmpty);
            expect(client.queried, isEmpty);
            expect(client.refreshes, reads);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            semantics.dispose();
            model.dispose();
            await owner.close();
            await client.events.close();
            await client.readErrors.close();
          }
        });
      }
    }
  }
  testWidgets('T188 real query status tag reset sort and owner preservation', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 1400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = MutationClient();
    final owner = fixtures.ModelBootstrap(client)..show(ReadinessState.ready);
    final model = ProfileController(bootstrap: owner);
    client.events.add(twoProfiles());
    final reads = client.refreshes;
    var dark = false;
    late StateSetter rebuild;
    try {
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return MaterialApp(
              theme: dark ? BrandTheme.dark : BrandTheme.light,
              home: Scaffold(
                body: DeckPageInsets(
                  padding: const EdgeInsets.all(16),
                  child: ListenableBuilder(
                    listenable: model,
                    builder: (context, _) => ProfileList(controller: model),
                  ),
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byType(TextField);
      final status = find.byKey(const ValueKey('profile-filter-state'));
      final triggerState = tester.state(status);
      await tester.enterText(field, 'beta');
      await choose(tester, 'profile-filter-state', 'unknown');
      await choose(tester, 'profile-filter-tag', 'staging');
      expect(find.text('beta profile'), findsOneWidget);
      expect(find.text('alpha profile'), findsNothing);
      await choose(tester, 'profile-filter-state', 'connected');
      expect(find.text('Серверы не найдены'), findsOneWidget);
      final all = find.byKey(const ValueKey('profile-filter-all'));
      await tester.ensureVisible(all);
      await tester.tap(all);
      await tester.pumpAndSettle();
      expect(find.text('beta profile'), findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, 'beta');
      expect(find.text('Все 2'), findsOneWidget);
      await tester.ensureVisible(find.text('Найти сервер'));
      await tester.tap(find.text('Найти сервер'));
      await tester.pumpAndSettle();
      final editor = tester.widget<EditableText>(find.byType(EditableText));
      editor.controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 3,
      );
      rebuild(() => dark = true);
      tester.view.physicalSize = const Size(390, 1400);
      await tester.pumpAndSettle();
      final resized = tester.widget<EditableText>(find.byType(EditableText));
      expect(resized.controller, same(editor.controller));
      expect(resized.focusNode, same(editor.focusNode));
      expect(resized.focusNode.hasFocus, isTrue);
      expect(
        resized.controller.selection,
        const TextSelection(baseOffset: 1, extentOffset: 3),
      );
      expect(tester.state(status), same(triggerState));
      await tester.enterText(field, '');
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Фильтры'),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Фильтры'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('alpha profile')).dy,
        lessThan(tester.getTopLeft(find.text('beta profile')).dy),
      );
      await tester.ensureVisible(find.text('Имя: А–Я'));
      await tester.tap(find.text('Имя: А–Я'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('beta profile')).dy,
        lessThan(tester.getTopLeft(find.text('alpha profile')).dy),
      );
      await choose(tester, 'profile-filter-tag', 'staging');
      client.events.add(twoProfiles(revision: '2', replaceTag: true));
      await tester.pumpAndSettle();
      expect(find.text('Серверы не найдены'), findsOneWidget);
      final tag = find.byKey(const ValueKey('profile-filter-tag'));
      await tester.ensureVisible(tag);
      await tester.tap(tag);
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<PopupMenuItem<String>>(
              find.byType(PopupMenuItem<String>),
            )
            .map((w) => w.value),
        ['', 'production', 'replacement', 'staging'],
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Серверы не найдены'), findsOneWidget);
      final reset = find.widgetWithText(TextButton, 'Сбросить фильтры');
      await tester.ensureVisible(reset);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(find.text('alpha profile'), findsOneWidget);
      expect(find.text('beta profile'), findsOneWidget);
      expect(find.text('Имя: Я–А'), findsOneWidget);
      expect(model.selected!.id, fixtures.profileId);
      expect(client.sent, isEmpty);
      expect(client.queried, isEmpty);
      expect(client.refreshes, reads);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      await owner.close();
      await client.events.close();
      await client.readErrors.close();
    }
  });

  testWidgets('T188 selected maximum tag wraps completely at 200%', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = MutationClient();
    final owner = fixtures.ModelBootstrap(client)..show(ReadinessState.ready);
    final model = ProfileController(bootstrap: owner);
    final longTag = 'Ж' * 64;
    client.events.add(twoProfiles(tag: longTag));
    final reads = client.refreshes;
    try {
      for (final width in [390.0, 521.0]) {
        tester.view.physicalSize = Size(width, 1400);
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(width),
            theme: BrandTheme.dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: DeckPageInsets(
                padding: const EdgeInsets.all(16),
                child: ProfileList(controller: model),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await choose(tester, 'profile-filter-tag', longTag);
        final tag = find.byKey(const ValueKey('profile-filter-tag'));
        final text = find.descendant(of: tag, matching: find.text(longTag));
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(paragraph.maxLines, isNull);
        expect(paragraph.overflow, isNot(TextOverflow.ellipsis));
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.size.height, greaterThan(40));
        expect(tester.getRect(text).right, lessThanOrEqualTo(width - 16));
        expect(find.text('beta profile'), findsOneWidget);
        expect(find.text('alpha profile'), findsNothing);
        expect(client.sent, isEmpty);
        expect(client.queried, isEmpty);
        expect(client.refreshes, reads);
        expect(tester.takeException(), isNull);
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      await owner.close();
      await client.events.close();
      await client.readErrors.close();
    }
  });

  for (final reduced in [false, true]) {
    testWidgets('T188 native keyboard profile filters reduced=$reduced', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1100, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = MutationClient();
      final owner = fixtures.ModelBootstrap(client)..show(ReadinessState.ready);
      final model = ProfileController(bootstrap: owner);
      client.events.add(fixtures.snapshot());
      final reads = client.refreshes;
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: BrandTheme.dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: child!,
            ),
            home: Scaffold(
              body: DeckPageInsets(
                padding: const EdgeInsets.all(16),
                child: ProfileList(controller: model),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final field = find.byType(TextField);
        await tester.enterText(field, 'Saved');
        final status = find.byKey(const ValueKey('profile-filter-state'));
        final statusState = tester.state(status);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(
          Focus.of(
            tester.element(
              find.descendant(of: status, matching: find.text('Состояние')),
            ),
          ).hasFocus,
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        final unknown = find.widgetWithText(
          PopupMenuItem<String>,
          'Неизвестно',
        );
        final unknownText = find.descendant(
          of: unknown,
          matching: find.text('Неизвестно'),
        );
        for (var i = 0; i < 4; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          if (Focus.of(tester.element(unknownText)).hasFocus) break;
        }
        expect(Focus.of(tester.element(unknownText)).hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(tester.state(status), same(statusState));
        expect(
          tester.widget<PopupMenuButton<String>>(status).initialValue,
          'unknown',
        );
        expect(find.text('Saved profile'), findsOneWidget);
        expect(tester.widget<TextField>(field).controller!.text, 'Saved');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(PopupMenuItem<String>), findsWidgets);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          tester.widget<PopupMenuButton<String>>(status).initialValue,
          'unknown',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        final tags = find.byKey(const ValueKey('profile-filter-tag'));
        expect(
          Focus.of(
            tester.element(
              find.descendant(of: tags, matching: find.text('Теги')),
            ),
          ).hasFocus,
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        final production = find.widgetWithText(
          PopupMenuItem<String>,
          'production',
        );
        final productionText = find.descendant(
          of: production,
          matching: find.text('production'),
        );
        for (var i = 0; i < 2; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          if (Focus.of(tester.element(productionText)).hasFocus) break;
        }
        expect(Focus.of(tester.element(productionText)).hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          tester.widget<PopupMenuButton<String>>(tags).initialValue,
          'production',
        );
        expect(find.text('Saved profile'), findsOneWidget);
        expect(client.sent, isEmpty);
        expect(client.queried, isEmpty);
        expect(client.refreshes, reads);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        model.dispose();
        await owner.close();
        await client.events.close();
        await client.readErrors.close();
      }
    });
  }

  for (final menuKind in ['profile-state', 'profile-tag', 'automation']) {
    for (final reduced in [false, true]) {
      for (final replaceEpoch in [false, true]) {
        testWidgets(
          'T188 private menu $menuKind reduced=$reduced epoch=$replaceEpoch',
          (tester) async {
            tester.view.physicalSize = const Size(1100, 1400);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final client = MutationClient();
            final owner = fixtures.ModelBootstrap(client)
              ..show(ReadinessState.ready);
            final model = ProfileController(bootstrap: owner);
            client.events.add(fixtures.snapshot());
            final reads = client.refreshes;
            var ready = true, epoch = 1;
            late StateSetter rebuild;
            final selected = <int>[];
            var more = 0;
            final semantics = tester.ensureSemantics();
            try {
              await tester.pumpWidget(
                StatefulBuilder(
                  builder: (context, setState) {
                    rebuild = setState;
                    return MaterialApp(
                      theme: BrandTheme.dark,
                      builder: (context, child) => PrivateSessionScope(
                        authorized: ready,
                        epoch: epoch,
                        child: MediaQuery(
                          data: MediaQuery.of(context)
                              .copyWith(disableAnimations: reduced),
                          child: child!,
                        ),
                      ),
                      home: Scaffold(
                        body: !ready
                            ? const Text('Locked')
                            : DeckPageInsets(
                                padding: const EdgeInsets.all(16),
                                child: menuKind == 'automation'
                                    ? AutomationLoadedTable(
                                        columns: const [
                                          'Название',
                                          'Состояние',
                                        ],
                                        rows: const [
                                          [Text('Private row'), Text('Готово')],
                                        ],
                                        onSelect: selected.add,
                                        hasMore: true,
                                        onMore: () => more++,
                                      )
                                    : ProfileList(controller: model),
                              ),
                      ),
                    );
                  },
                ),
              );
              await tester.pumpAndSettle();
              final menu = menuKind == 'automation'
                  ? find.byType(PopupMenuButton<String>)
                  : find.byKey(
                      ValueKey(
                        'profile-filter-${menuKind == 'profile-tag' ? 'tag' : 'state'}',
                      ),
                    );
              final lateSelection = tester
                  .widget<PopupMenuButton<String>>(menu)
                  .onSelected!;
              await tester.ensureVisible(menu);
              await tester.tap(menu);
              await tester.pump();
              if (reduced) {
                expect(
                  ModalRoute.of(
                    tester.element(find.byType(PopupMenuItem<String>).first),
                  )!.animation!.status,
                  AnimationStatus.completed,
                );
              }
              await tester.pumpAndSettle();
              expect(find.byType(PopupMenuItem<String>), findsWidgets);
              rebuild(() {
                if (replaceEpoch) {
                  epoch++;
                } else {
                  ready = false;
                }
              });
              await tester.pump();
              final retiringItems = find.byType(PopupMenuItem<String>);
              expect(
                find.descendant(of: retiringItems, matching: find.byType(Text)),
                findsNothing,
              );
              for (var i = 0; i < retiringItems.evaluate().length; i++) {
                if (retiringItems.at(i).hitTestable().evaluate().isNotEmpty) {
                  expect(
                    tester
                        .getSemantics(retiringItems.at(i))
                        .getSemanticsData()
                        .label,
                    isEmpty,
                  );
                }
              }
              await tester.pumpAndSettle();
              expect(find.byType(PopupMenuItem<String>), findsNothing);
              // Model a route result already queued before its retirement.
              lateSelection(
                menuKind == 'automation'
                    ? 'Готово'
                    : menuKind == 'profile-tag'
                    ? 'production'
                    : 'connected',
              );
              await tester.pumpAndSettle();
              if (replaceEpoch) {
                final caption = menuKind == 'profile-tag'
                    ? 'Теги'
                    : 'Состояние';
                expect(
                  find.descendant(of: menu, matching: find.text(caption)),
                  findsOneWidget,
                );
                expect(
                  find.text(
                    menuKind == 'automation' ? 'Private row' : 'Saved profile',
                  ),
                  findsOneWidget,
                );
              } else {
                expect(find.text('Locked'), findsOneWidget);
              }
              expect(client.sent, isEmpty);
              expect(client.queried, isEmpty);
              expect(client.refreshes, reads);
              expect(selected, isEmpty);
              expect(more, 0);
              expect(tester.takeException(), isNull);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              semantics.dispose();
              model.dispose();
              await owner.close();
              await client.events.close();
              await client.readErrors.close();
            }
          },
        );
      }
    }
  }
}
