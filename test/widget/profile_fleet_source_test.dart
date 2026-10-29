import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/profiles/profile_form.dart';
import 'package:serverdeck/profiles/profile_list.dart';
import 'package:serverdeck/profiles/profile_presentation.dart';
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_components.dart';
import 'package:serverdeck/ui/deck_icon.dart';
import 'package:serverdeck/ui/deck_page.dart';
import 'package:serverdeck/ui/deck_table_controls.dart';
import 'package:serverdeck_protocol/models.dart';

import '../contract/mutation_controller_test.dart' show MutationClient;
import '../contract/profile_controller_test.dart' as fixtures;
import '../support/design_fonts.dart';
import 'deck_components_test.dart' show pixels;

TextStyle _style(WidgetTester tester, Finder text) =>
    (tester.renderObject<RenderParagraph>(text).text as TextSpan).style!;

void main() {
  setUpAll(loadDesignFonts);
  late MutationClient client;
  late fixtures.ModelBootstrap owner;
  late ProfileController model;
  late GlobalKey boundary;
  final opened = <ProfileView>[];
  setUp(() {
    boundary = GlobalKey();
    opened.clear();
    client = MutationClient();
    owner = fixtures.ModelBootstrap(client)..show(ReadinessState.ready);
    model = ProfileController(bootstrap: owner);
    client.events.add(fixtures.snapshot());
  });
  tearDown(() async {
    model.dispose();
    await owner.close();
    await client.events.close();
    await client.readErrors.close();
  });

  Future<void> mount(
    WidgetTester tester,
    Size frame,
    bool dark,
    double scale,
  ) async {
    tester.view.physicalSize = frame;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? BrandTheme.dark : BrandTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: boundary,
          child: FoundationShell(
            state: ReadinessState.ready,
            servers: ProfileList(controller: model, onOpenProfile: opened.add),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final frame in const [
    Size(1100, 760),
    Size(800, 600),
    Size(390, 800),
    Size(360, 800),
  ]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'T214 actual fleet source composition $frame $dark $scale',
          (tester) async {
            await mount(tester, frame, dark, scale);
            final phone = frame.width <= 520;
            final caption = find.text('серверов в пространстве');
            final summary = find
                .ancestor(of: caption, matching: find.byType(DeckPanel))
                .first;
            final actions = find
                .ancestor(
                  of: find.widgetWithText(OutlinedButton, 'Фильтры'),
                  matching: find.byType(DeckActions),
                )
                .first;
            expect(
              tester.getRect(summary).top - tester.getRect(actions).bottom,
              closeTo(18, .1),
            );
            expect(
              tester.getRect(find.byType(DeckSearchField)).top -
                  tester.getRect(summary).bottom,
              closeTo(20, .1),
            );
            expect(_style(tester, caption).fontSize, phone ? 14 : 13);
            expect(_style(tester, find.text('1')).fontSize, phone ? 30 : 32);
            expect(_style(tester, find.text('1')).letterSpacing, -1);
            final unknown = find.text('1 неизвестно');
            expect(_style(tester, unknown).fontSize, 12);
            expect(_style(tester, unknown).height! * 12, phone ? 20 : 18);
            expect(
              tester.getSize(
                find.byKey(const ValueKey('fleet-marker-unknown')),
              ),
              const Size(5, 5),
            );
            if (frame.width == 1100 && scale == 1) {
              expect(tester.getRect(summary).top, closeTo(242, .1));
              expect(tester.getSize(summary).height, closeTo(78, .1));
              expect(
                tester.getRect(unknown).right,
                closeTo(tester.getRect(summary).right - 21, .1),
              );
            }
            final title = find.text('Saved profile');
            expect(_style(tester, title).fontSize, phone ? 16 : 15);
            expect(
              _style(tester, title).height! * (phone ? 16 : 15),
              phone ? 24 : 22,
            );
            final identity = find
                .ancestor(of: title, matching: find.byType(Row))
                .first;
            final logo = find.descendant(
              of: identity,
              matching: find.byWidgetPredicate(
                (w) => w is DeckIcon && w.name == 'server',
              ),
            );
            final logoBox = find
                .ancestor(of: logo, matching: find.byType(Container))
                .first;
            expect(
              tester.getRect(title).left - tester.getRect(logoBox).right,
              closeTo(10, .1),
            );
            expect(
              tester.getRect(logoBox).center.dy,
              closeTo(tester.getRect(identity).center.dy, .1),
            );
            final menu = find.descendant(
              of: identity,
              matching: find.byType(PopupMenuButton<String>),
            );
            if (phone) {
              expect(
                tester.getRect(menu).center.dy,
                closeTo(tester.getRect(identity).center.dy, .1),
              );
            } else {
              expect(
                tester.getRect(menu).top,
                closeTo(tester.getRect(identity).top, .1),
              );
            }
            for (final entry in [
              ('Открыть сервер', 'arrow'),
              ('Изменить', 'edit'),
            ]) {
              final button = find
                  .ancestor(
                    of: find.text(entry.$1),
                    matching: find.byWidgetPredicate(
                      (w) => w is ButtonStyleButton,
                    ),
                  )
                  .first;
              expect(
                tester
                    .widget<DeckButtonLabel>(
                      find.descendant(
                        of: button,
                        matching: find.byType(DeckButtonLabel),
                      ),
                    )
                    .icon,
                entry.$2,
              );
            }
            final open = find.widgetWithText(FilledButton, 'Открыть сервер');
            await tester.ensureVisible(open);
            await tester.tap(open);
            await tester.pumpAndSettle();
            expect(opened.single, same(model.profiles.single));
            expect(client.sent, isEmpty);
            expect(client.queried, isEmpty);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final label in ['Saved profile', 'Открыть сервер', 'Изменить']) {
    testWidgets(
      'T214 native focus and state survive card rearrangement $label',
      (tester) async {
        await mount(tester, const Size(1100, 1000), true, 1);
        final title = find.text(label);
        final button = find
            .ancestor(
              of: title,
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
            )
            .first;
        final state = tester.state(button);
        final focus = Focus.of(tester.element(title));
        focus.requestFocus();
        await tester.pumpAndSettle();
        for (final width in [800.0, 390.0, 360.0, 1100.0]) {
          tester.view.physicalSize = Size(width, 1000);
          await tester.pumpAndSettle();
          expect(tester.state(button), same(state));
          expect(focus.hasPrimaryFocus, isTrue);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        if (label == 'Изменить') {
          expect(
            tester.widget<ProfileForm>(find.byType(ProfileForm)).initial,
            same(model.profiles.single),
          );
        } else {
          expect(opened.single.id, model.profiles.single.id);
        }
        expect(client.sent, isEmpty);
        expect(client.queried, isEmpty);
      },
    );
  }

  for (final width in [520.0, 521.0, 760.0, 761.0]) {
    testWidgets('T214 fleet uses source device boundaries $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.dark,
          home: const Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ProfileFleetSummary(
                total: 1,
                connected: 0,
                attention: 0,
                unknown: 1,
              ),
            ),
          ),
        ),
      );
      final panel = tester.getRect(find.byType(DeckPanel));
      final group = find
          .ancestor(
            of: find.text('серверов в пространстве'),
            matching: find.byType(Row),
          )
          .first;
      if (width <= 760) {
        expect(tester.getSize(group).width, closeTo(panel.width - 34, .1));
        expect(panel.height, closeTo(102, .1));
      } else {
        expect(tester.getSize(group).width, lessThan(panel.width - 42));
        expect(panel.height, closeTo(78, .1));
      }
      expect(_style(tester, find.text('1')).fontSize, width <= 520 ? 30 : 32);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('T214 auto margin affects only the first wrapped fleet run', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.dark,
        home: const Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 644,
              child: ProfileFleetSummary(
                total: 500,
                connected: 1,
                attention: 0,
                unknown: 499,
              ),
            ),
          ),
        ),
      ),
    );
    final panel = tester.getRect(find.byType(DeckPanel));
    expect(panel.height, closeTo(114, .1));
    expect(
      tester.getRect(find.text('0 требуют внимания')).right,
      closeTo(panel.right - 21, .1),
    );
    expect(
      tester
          .getRect(
            find
                .ancestor(
                  of: find.text('499 неизвестно'),
                  matching: find.byType(Row),
                )
                .first,
          )
          .left,
      closeTo(panel.left + 21, .1),
    );
    expect(
      tester.getRect(find.text('499 неизвестно')).top,
      closeTo(panel.top + 77, .1),
    );
    expect(tester.takeException(), isNull);
  });

  for (final width in [1100.0, 390.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'T214 title focus outline hover and native fringe $width $dark',
        (tester) async {
          await mount(tester, Size(width, 1000), dark, 1);
          final title = find.text('Saved profile');
          final button = find
              .ancestor(of: title, matching: find.byType(TextButton))
              .first;
          await tester.ensureVisible(button);
          final rect = tester.getRect(button);
          final point = Offset(rect.left + 1, rect.center.dy);
          final gap = Offset(rect.left + 3, rect.center.dy);
          final colors = dark ? BrandColors.dark : BrandColors.light;
          final focus = Focus.of(tester.element(title));
          focus.requestFocus();
          await tester.pumpAndSettle();
          expect(await pixels(tester, boundary, [point, gap]), [
            colors['focus'],
            colors['surface'],
          ]);
          focus.unfocus();
          await tester.pumpAndSettle();
          final mouse = await tester.createGesture(
            kind: ui.PointerDeviceKind.mouse,
          );
          await mouse.addPointer();
          addTearDown(mouse.removePointer);
          await mouse.moveTo(rect.center);
          await tester.pumpAndSettle();
          expect(_style(tester, title).color, colors['accent']);
          expect(await pixels(tester, boundary, [point, gap]), [
            colors['surface'],
            colors['surface'],
          ]);
          await tester.tapAt(point);
          await tester.pumpAndSettle();
          expect(opened.single.id, model.profiles.single.id);
          expect(client.sent, isEmpty);
          expect(client.queried, isEmpty);
        },
      );
    }
  }

  testWidgets('T214 edit still opens the exact existing profile locally', (
    tester,
  ) async {
    await mount(tester, const Size(1100, 900), true, 1);
    final edit = find.widgetWithText(OutlinedButton, 'Изменить');
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(
      tester.widget<ProfileForm>(find.byType(ProfileForm)).initial,
      same(model.profiles.single),
    );
    expect(client.sent, isEmpty);
    expect(client.queried, isEmpty);
  });
}
