import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/profiles/profile_form.dart';
import 'package:serverdeck/profiles/profile_list.dart';
import 'package:serverdeck/profiles/profile_presentation.dart';
import 'package:serverdeck/settings/settings_view.dart' as settings;
import 'package:serverdeck/settings/settings_form.dart';
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck/ui/deck_components.dart';
import 'package:serverdeck/ui/deck_control_target.dart';
import 'package:serverdeck/ui/deck_icon.dart';
import 'package:serverdeck/ui/deck_page.dart';
import 'package:serverdeck_protocol/models.dart';

import '../contract/mutation_controller_test.dart' show MutationClient;
import '../contract/profile_controller_test.dart' as fixture;
import '../support/design_host.dart' show loadDesignFonts;
import 'deck_components_test.dart' show pixels;

void main() {
  setUpAll(loadDesignFonts);
  late MutationClient client;
  late fixture.ModelBootstrap bootstrap;
  late ProfileController model;
  setUp(() {
    client = MutationClient();
    bootstrap = fixture.ModelBootstrap(client)..show(ReadinessState.ready);
    model = ProfileController(bootstrap: bootstrap);
    client.events.add(fixture.snapshot());
  });
  tearDown(() async {
    model.dispose();
    await bootstrap.close();
    await client.events.close();
    await client.readErrors.close();
  });

  Future<void> mount(
    WidgetTester tester,
    Widget child,
    Size frame,
    bool dark,
    double scale, {
    GlobalKey? boundaryKey,
  }) async {
    tester.view.physicalSize = frame;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: Motion.theme(dark ? BrandTheme.dark : BrandTheme.light, true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: boundaryKey,
          child: FoundationShell(state: ReadinessState.ready, servers: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    testWidgets('T217 settings preserves both source footer edges $dark', (
      tester,
    ) async {
      final boundary = GlobalKey();
      await mount(
        tester,
        SettingsForm(model: model, asPage: true),
        const Size(1100, 760),
        dark,
        1,
        boundaryKey: boundary,
      );
      final colors = dark ? BrandColors.dark : BrandColors.light;
      expect(
        await pixels(tester, boundary, const [
          Offset(300, 449),
          Offset(300, 450),
          Offset(300, 451),
          Offset(300, 519),
          Offset(300, 520),
        ]),
        [
          colors['border'],
          colors['border'],
          colors['raised'],
          colors['border'],
          colors['bg'],
        ],
      );
      expect(client.sent, isEmpty);
    });
  }

  testWidgets(
    'T217 real profile target is readonly and keeps its captured identity',
    (tester) async {
      final initial = model.profiles.single;
      await mount(
        tester,
        ProfileForm(model: model, initial: initial, asPage: true),
        const Size(1100, 760),
        true,
        1,
      );
      final target = find.byKey(const ValueKey('profile-target'));
      final editor = tester.widget<EditableText>(
        find.descendant(of: target, matching: find.byType(EditableText)),
      );
      expect(editor.readOnly, isTrue);
      expect(
        editor.controller.text,
        '${initial.name} · ${initial.address}:${initial.port}',
      );
      expect(editor.selectionEnabled, isTrue);
      expect(client.sent, isEmpty);
      expect(client.queried, isEmpty);
    },
  );

  for (final frame in const [
    Size(1100, 760),
    Size(800, 600),
    Size(390, 800),
    Size(360, 800),
  ]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'T215 readonly settings value preserves source geometry and full access $frame $dark $scale',
          (tester) async {
            await mount(
              tester,
              SettingsForm(model: model, asPage: true),
              frame,
              dark,
              scale,
            );
            final field = find.byKey(
              const ValueKey('settings-profile-selection-note'),
            );
            expect(field, findsOneWidget);
            final input = find.descendant(
              of: field,
              matching: find.byType(EditableText),
            );
            final editable = tester.widget<EditableText>(input);
            const value = 'Без подключения и подтверждения SSH-доверия';
            expect(editable.controller.text, value);
            expect(editable.readOnly, isTrue);
            expect(editable.selectionEnabled, isTrue);
            final target = find
                .ancestor(of: field, matching: find.byType(DeckControlTarget))
                .first;
            if (scale == 1) {
              expect(
                tester.getSize(target).height,
                closeTo(frame.width <= 520 ? 44 : 42, .1),
              );
              if (frame.width == 1100)
                expect(tester.getTopLeft(target).dy, closeTo(387, .1));
            } else {
              expect(editable.maxLines, isNull);
              expect(tester.getSize(target).height, greaterThan(44));
            }
            await tester.ensureVisible(field);
            await tester.tap(field);
            await tester.pumpAndSettle();
            expect(editable.focusNode.hasFocus, isTrue);
            editable.controller.selection = const TextSelection(
              baseOffset: 0,
              extentOffset: value.length,
            );
            await tester.pump();
            expect(
              editable.controller.selection.textInside(
                editable.controller.text,
              ),
              value,
            );
            expect(tester.testTextInput.isVisible, isFalse);
            expect(client.sent, isEmpty);
            expect(client.refreshes, 1);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'T190 credential-only footer stacks every action phone $scale',
      (tester) async {
        await mount(
          tester,
          ProfileForm(
            model: model,
            initial: model.profiles.single,
            asPage: true,
            credentialOnly: true,
          ),
          const Size(390, 800),
          true,
          scale,
        );
        final actions = find.byType(DeckFormActions);
        expect(actions, findsOneWidget);
        final buttons = find.descendant(
          of: actions,
          matching: find.byWidgetPredicate(
            (widget) => widget is ButtonStyleButton,
          ),
        );
        expect(buttons, findsNWidgets(4));
        final area = tester.getRect(actions);
        Rect? previous;
        for (final button in buttons.evaluate()) {
          final rect = tester.getRect(find.byWidget(button.widget));
          expect(rect.width, closeTo(area.width, .01));
          if (previous != null)
            expect(rect.top - previous.bottom, closeTo(10, .01));
          previous = rect;
        }
        expect(client.sent, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final width in [390.0, 800.0]) {
    testWidgets('T201 settings form hint-to-field source gap $width', (
      tester,
    ) async {
      await mount(
        tester,
        SettingsForm(model: model, asPage: true),
        Size(width, 800),
        true,
        1,
      );
      final hint = tester.getRect(
        find.text('Проверьте выбранную цель и значения полей.'),
      );
      final label = tester.getRect(find.text('Тема *'));
      expect(label.top - hint.bottom, width <= 520 ? 20 : 18);
      expect(client.sent, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final frame in const [
    Size(1100, 760),
    Size(800, 600),
    Size(390, 800),
    Size(360, 800),
  ]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        final variant = '${frame.width} dark=$dark scale=$scale';
        testWidgets(
          'PV02/03/05 captured edit field order and typography $variant',
          (tester) async {
            final initial = model.profiles.single;
            await mount(
              tester,
              ProfileForm(model: model, initial: initial, asPage: true),
              frame,
              dark,
              scale,
            );
            final grid = tester.widget<ProfileFieldGrid>(
              find.byType(ProfileFieldGrid),
            );
            expect(grid.children, hasLength(7));
            final labels = [
              'Сервер *',
              'Название *',
              'Адрес *',
              'Порт SSH *',
              'Пользователь SSH *',
              'Доступ',
              'Метки',
            ];
            final positions = [
              for (final label in labels) tester.getTopLeft(find.text(label)),
            ];
            for (var i = 1; i < positions.length; i++) {
              if (frame.width > 520 && scale == 1 && i.isOdd) {
                expect(positions[i].dy, closeTo(positions[i - 1].dy, 1));
                expect(positions[i].dx, greaterThan(positions[i - 1].dx));
              } else {
                expect(positions[i].dy, greaterThan(positions[i - 1].dy));
              }
            }
            for (final element in find.byType(ProfileFieldLabel).evaluate()) {
              final text = tester.widget<Text>(
                find.descendant(
                  of: find.byWidget(element.widget),
                  matching: find.byType(Text),
                ),
              );
              expect(text.style!.fontSize, 12);
              expect(text.style!.height, 20 / 12);
              expect(text.style!.fontWeight, BrandTypography.semiboldWeight);
            }
            expect(
              find.text('IP-адрес или доменное имя сервера'),
              findsOneWidget,
            );
            expect(find.text('Стандартный порт SSH — 22'), findsOneWidget);
            for (final key in [
              'profile-name',
              'profile-address',
              'profile-port',
              'profile-user',
            ]) {
              final input = find.byKey(ValueKey(key));
              await tester.ensureVisible(input);
              FocusManager.instance.primaryFocus?.unfocus();
              await tester.pumpAndSettle();
              final bounds = tester.getRect(input);
              await tester.tapAt(Offset(bounds.center.dx, bounds.bottom - .2));
              await tester.pumpAndSettle();
              expect(
                tester
                    .widget<EditableText>(
                      find.descendant(
                        of: input,
                        matching: find.byType(EditableText),
                      ),
                    )
                    .focusNode
                    .hasFocus,
                isTrue,
              );
            }
            await tester.enterText(
              find.byKey(const ValueKey('profile-name')),
              'Новый черновик 日本語',
            );
            expect(
              find.text('${initial.name} · ${initial.address}:${initial.port}'),
              findsOneWidget,
            );
            expect(
              tester.widget<ProfileForm>(find.byType(ProfileForm)).initial,
              same(initial),
            );
            if (frame.width > 960) {
              final helper = find
                  .ancestor(
                    of: find.text('Проверьте доступ'),
                    matching: find.byType(DeckPanel),
                  )
                  .first;
              final shield = find.descendant(
                of: helper,
                matching: find.byWidgetPredicate(
                  (widget) => widget is DeckIcon && widget.name == 'shield',
                ),
              );
              expect(tester.widget<DeckIcon>(shield).size, 20);
              final badge = find
                  .ancestor(of: shield, matching: find.byType(Container))
                  .first;
              expect(tester.getSize(badge), const Size(36, 36));
              final decoration =
                  tester.widget<Container>(badge).decoration! as BoxDecoration;
              expect(decoration.borderRadius, BorderRadius.circular(9));
            } else {
              expect(find.text('Проверьте доступ'), findsNothing);
            }
            if (frame.width <= 520) {
              final panel = tester.getRect(find.byType(DeckSurface).first);
              expect(positions.first.dx - panel.left, inInclusiveRange(16, 17));
            }
            expect(client.sent, isEmpty);
            expect(client.refreshes, 1);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );

        testWidgets('PV07 settings value cap and actual AI callback $variant', (
          tester,
        ) async {
          var opened = 0;
          await mount(
            tester,
            settings.SettingsView(
              controller: model,
              onAiAccess: () => opened++,
            ),
            frame,
            dark,
            scale,
          );
          final value = find.text('Тёмная');
          final row = find
              .ancestor(of: value, matching: find.byType(Row))
              .first;
          final label = find.text('Тема');
          final rowWidth = tester.getSize(row).width;
          expect(
            tester.getSize(value).width,
            lessThanOrEqualTo(rowWidth * .58 + .1),
          );
          expect(
            tester.getRect(label).right,
            closeTo(
              tester.getRect(value).left - (frame.width <= 520 ? 12 : 16),
              .1,
            ),
          );
          expect(tester.widget<Text>(value).style!.fontSize, 14);
          expect(tester.widget<Text>(value).style!.height, 20 / 14);
          final ai = find.widgetWithText(OutlinedButton, 'ИИ-доступ');
          expect(tester.widget<OutlinedButton>(ai).onPressed, isNotNull);
          await tester.ensureVisible(ai);
          await tester.tap(ai);
          await tester.pumpAndSettle();
          expect(opened, 1);
          expect(client.sent, isEmpty);
          expect(client.refreshes, 1);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  testWidgets(
    'PV01 status and tag filters remain visible and operate only on local data',
    (tester) async {
      await mount(
        tester,
        ProfileList(controller: model),
        const Size(800, 600),
        true,
        1,
      );
      final stateFilter = find.byKey(const ValueKey('profile-filter-state'));
      final tagFilter = find.byKey(const ValueKey('profile-filter-tag'));
      expect(find.text('Все 1'), findsOneWidget);
      expect(find.text('Состояние'), findsOneWidget);
      expect(find.text('Теги'), findsOneWidget);
      for (final entry in [
        (stateFilter, ['', 'connected', 'attention', 'unknown']),
        (tagFilter, ['', 'production']),
      ]) {
        await tester.ensureVisible(entry.$1);
        await tester.tap(entry.$1);
        await tester.pumpAndSettle();
        expect(
          tester
              .widgetList<PopupMenuItem<String>>(
                find.byType(PopupMenuItem<String>),
              )
              .map((item) => item.value),
          entry.$2,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(stateFilter);
      await tester.tap(stateFilter);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Неизвестно').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PopupMenuButton<String>>(
              find.byKey(const ValueKey('profile-filter-state')),
            )
            .initialValue,
        'unknown',
      );
      await tester.ensureVisible(tagFilter);
      await tester.tap(tagFilter);
      await tester.pumpAndSettle();
      await tester.tap(find.text('production').last);
      await tester.pumpAndSettle();
      expect(find.text('Saved profile'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('profile-filter-all')),
      );
      await tester.tap(find.byKey(const ValueKey('profile-filter-all')));
      await tester.pumpAndSettle();
      expect(stateFilter, findsOneWidget);
      expect(tagFilter, findsOneWidget);
      expect(client.sent, isEmpty);
      expect(client.refreshes, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('PV02 captured target advances only on explicit CAS reload', (
    tester,
  ) async {
    client.send = () async =>
        throw const LocalApiException(ErrorCode.revisionConflict);
    final initial = model.profiles.single;
    await mount(
      tester,
      ProfileForm(model: model, initial: initial, asPage: true),
      const Size(1100, 760),
      false,
      1,
    );
    final retainedFormState = tester.state(find.byType(ProfileForm));
    final retainedName = tester
        .widget<TextFormField>(find.byKey(const ValueKey('profile-name')))
        .controller!;
    await tester.enterText(
      find.byKey(const ValueKey('profile-name')),
      'Private draft',
    );
    await tester.ensureVisible(find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(client.sent.single.method, ApiMethod.profilesUpdate);
    final originalIntent = client.sent.single;
    final next = fixture.snapshot(revision: '2');
    final row =
        Map<String, Object?>.from(
            (next.profiles.result['profiles'] as List).single as Map,
          )
          ..['name'] = 'Explicitly reloaded target'
          ..['revision'] = '2';
    client.events.add(
      ClientSnapshot(
        ApiReply(fixture.fixtureGeneration, {
          'storeRevision': '2',
          'profiles': [row],
        }),
        next.settings,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('${initial.name} · ${initial.address}:${initial.port}'),
      findsOneWidget,
    );
    expect(tester.state(find.byType(ProfileForm)), same(retainedFormState));
    expect(find.byKey(const ValueKey('profile-name')), findsNothing);
    expect(find.text('Private draft'), findsNothing);
    final hiddenName = find.byKey(
      const ValueKey('profile-name'),
      skipOffstage: false,
    );
    expect(
      tester.widget<TextFormField>(hiddenName).controller,
      same(retainedName),
    );
    expect(tester.widget<TextFormField>(hiddenName).enabled, isFalse);
    expect(retainedName.text, 'Private draft');
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: hiddenName,
              matching: find.byType(EditableText, skipOffstage: false),
              skipOffstage: false,
            ),
          )
          .focusNode
          .hasFocus,
      isFalse,
    );
    expect(
      find.text(
        'Explicitly reloaded target · ${initial.address}:${initial.port}',
      ),
      findsNothing,
    );
    await tester.ensureVisible(find.text('Перечитать профиль'));
    await tester.tap(find.text('Перечитать профиль'));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(ProfileForm)), same(retainedFormState));
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('profile-name')))
          .controller,
      same(retainedName),
    );
    expect(
      find.text(
        'Explicitly reloaded target · ${initial.address}:${initial.port}',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('profile-name')))
          .controller!
          .text,
      'Explicitly reloaded target',
    );
    expect(client.sent, hasLength(1));
    await tester.ensureVisible(find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(client.sent, hasLength(2));
    expect(client.sent.last.id, isNot(originalIntent.id));
    expect(client.sent.last.method, ApiMethod.profilesUpdate);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final width in [390.0, 360.0]) {
    testWidgets('PV01 phone primary filter group fits one row width=$width', (
      tester,
    ) async {
      await mount(
        tester,
        ProfileList(controller: model),
        Size(width, 800),
        true,
        1,
      );
      final all = tester.getCenter(
        find.byKey(const ValueKey('profile-filter-all')),
      );
      final state = tester.getCenter(
        find.byKey(const ValueKey('profile-filter-state')),
      );
      final tag = tester.getCenter(
        find.byKey(const ValueKey('profile-filter-tag')),
      );
      expect(all.dy, closeTo(state.dy, 1));
      expect(state.dy, closeTo(tag.dy, 1));
      expect(all.dx, lessThan(state.dx));
      expect(state.dx, lessThan(tag.dx));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'PV06 full-width phone welcome actions width=$width dark=$dark scale=$scale',
          (tester) async {
            client.events.add(
              ClientSnapshot(
                ApiReply(fixture.fixtureGeneration, {
                  'storeRevision': '2',
                  'profiles': <Object?>[],
                }),
                ApiReply(fixture.fixtureGeneration, {
                  'storeRevision': '2',
                  'settings': const SettingsView().toJson(),
                }),
              ),
            );
            await mount(
              tester,
              ProfileList(controller: model, onAiAccess: () {}),
              Size(width, 800),
              dark,
              scale,
            );
            final add = find.widgetWithText(FilledButton, 'Добавить сервер');
            expect(
              find.descendant(of: add, matching: find.byType(DeckIcon)),
              findsNothing,
            );
            final ai = find
                .widgetWithText(OutlinedButton, 'Настроить ИИ-доступ')
                .last;
            final panel = tester.getRect(find.byType(DeckPanel));
            for (final action in [add, ai]) {
              expect(tester.getRect(action).left - panel.left, closeTo(19, 1));
              expect(
                panel.right - tester.getRect(action).right,
                closeTo(19, 1),
              );
            }
            final heading = tester.widget<Text>(
              find.text('Все серверы.\nОдин центр управления.'),
            );
            expect(heading.style!.letterSpacing, -1);
            final eyebrow = tester.widget<Text>(
              find.text('ВАШЕ РАБОЧЕЕ ПРОСТРАНСТВО'),
            );
            expect(eyebrow.style!.fontWeight, BrandTypography.semiboldWeight);
            expect(eyebrow.style!.letterSpacing, 1.6);
            final body = find.text(
              'Добавьте первое подключение, чтобы видеть состояние системы, ресурсы и программное обеспечение.',
            );
            expect(
              tester.widget<Text>(body).style!.color,
              deckColors(tester.element(body))['muted'],
            );
            expect(client.sent, isEmpty);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
}
