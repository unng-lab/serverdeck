import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/automation/automation_forms.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck/ui/deck_page.dart';

import '../support/design_automation_fixtures.dart';
import '../support/design_fonts.dart';
import '../support/base_design_bindings.dart';
import '../support/design_host.dart' show mountDesignFixture;
import 'deck_components_test.dart' show pixels;

void main() {
  for (final id in ['35-plan-parameters', '39-delegations']) {
    testWidgets(
      'T225 readonly context never becomes an outgoing draft field $id',
      (tester) async {
        final host = await mountDesignFixture(
          tester,
          currentBaseBindings.singleWhere((entry) => entry.screenId == id),
          frame: const Size(1100, 800),
          theme: ThemeMode.dark,
          textScale: 1,
          currentBase: true,
        );
        try {
          final label = id == '35-plan-parameters'
              ? 'greeting'
              : 'Срок, секунд';
          final field = find.byWidgetPredicate(
            (w) =>
                w is TextField && w.key == ValueKey('automation-field-$label'),
          );
          await tester.ensureVisible(field);
          await tester.enterText(
            field,
            id == '35-plan-parameters' ? 'Изменённый текст' : '1200',
          );
          await tester.pumpAndSettle();
          final draft = jsonDecode(host.harness.jsonInput.text) as Map;
          if (id == '35-plan-parameters') {
            expect(draft, {'greeting': 'Изменённый текст'});
          } else {
            expect(draft.keys.toSet(), {'lifetimeSeconds', 'predicates'});
            expect(draft['lifetimeSeconds'], 1200);
            expect((draft['predicates'] as Map)['greeting'], {
              'type': 'enum',
              'values': ['Привет'],
            });
          }
          expect(draft.containsKey('profileId'), isFalse);
          expect(draft.containsKey('bodyDigest'), isFalse);
          expect(host.harness.counters.values, isEmpty);
          final continueAction = find.widgetWithText(
            FilledButton,
            id == '35-plan-parameters' ? 'Создать план' : 'Делегировать версию',
          );
          await tester.ensureVisible(continueAction);
          await tester.tap(continueAction);
          await tester.pumpAndSettle();
          expect(host.harness.counters.values['continueEditor'], 1);
          expect(jsonDecode(host.harness.jsonInput.text), draft);
          const malformed = '{ "unexpected": [';
          host.harness.jsonInput.text = malformed;
          await tester.pumpAndSettle();
          expect(host.harness.jsonInput.text, malformed);
          final context = find.byKey(
            const ValueKey('automation-context-profile'),
          );
          expect(context, findsOneWidget);
          expect(
            tester
                .widget<TextField>(
                  find.descendant(
                    of: context,
                    matching: find.byType(TextField),
                  ),
                )
                .readOnly,
            isTrue,
          );
          final fixedContext = tester
              .widgetList<AutomationFormValue>(find.byType(AutomationFormValue))
              .map((field) => (label: field.label, value: field.value))
              .toList();
          const grantShaped =
              '{"scopes":[],"serverIds":[],"lifetimeSeconds":900,"label":"x"}';
          host.harness.jsonInput.text = grantShaped;
          await tester.pumpAndSettle();
          expect(host.harness.jsonInput.text, grantShaped);
          for (final field in fixedContext) {
            final retained = find.byWidgetPredicate(
              (widget) =>
                  widget is AutomationFormValue &&
                  widget.label == field.label &&
                  widget.value == field.value,
            );
            expect(retained, findsOneWidget);
            expect(
              tester
                  .widget<TextField>(
                    find.descendant(
                      of: retained,
                      matching: find.byType(TextField),
                    ),
                  )
                  .readOnly,
              isTrue,
            );
          }
          expect(host.harness.counters.values['continueEditor'], 1);
          expect(host.harness.client.mutations, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await host.close(tester);
        }
      },
    );
  }

  setUpAll(loadDesignFonts);
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'T190 form border paints the canonical height at desktop $scale',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: BrandTheme.dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: RepaintBoundary(
                key: boundary,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      AutomationValueField(
                        label: 'Название',
                        value: 'Значение',
                        enabled: true,
                        onChanged: (_) {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final body = tester.getRect(find.byType(TextField));
        final origin = tester.getTopLeft(find.byKey(boundary));
        final inset = scale == 1 ? 1.0 : 0.0;
        final colors = await pixels(tester, boundary, [
          Offset(body.center.dx - origin.dx, body.top + inset - origin.dy),
          Offset(
            body.center.dx - origin.dx,
            body.bottom - inset - 1 - origin.dy,
          ),
        ]);
        expect(colors, [
          BrandColors.dark['control'],
          BrandColors.dark['control'],
        ]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets('T190 requiredness is independent of numeric editing', (
    tester,
  ) async {
    final changes = <Object?>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.dark,
        home: Scaffold(
          body: Column(
            children: [
              AutomationValueField(
                label: 'Необязательное число',
                value: 3,
                enabled: true,
                numeric: true,
                onChanged: changes.add,
              ),
              AutomationValueField(
                label: 'Обязательная строка',
                value: '',
                enabled: true,
                required: true,
                onChanged: changes.add,
              ),
              AutomationValueField(
                label: 'Описание',
                value: '',
                enabled: true,
                onChanged: changes.add,
              ),
            ],
          ),
        ),
      ),
    );
    for (final (label, required) in [
      ('Необязательное число', false),
      ('Обязательная строка', true),
      ('Описание', false),
    ]) {
      final group = find.byWidgetPredicate(
        (widget) => widget is AutomationLabeledField && widget.label == label,
      );
      expect(tester.widget<AutomationLabeledField>(group).required, required);
    }
    await tester.enterText(
      find.byKey(const ValueKey('automation-field-Необязательное число')),
      '-',
    );
    expect(changes, ['-']);
    await tester.enterText(
      find.byKey(const ValueKey('automation-field-Обязательная строка')),
      '1.2.3',
    );
    expect(changes, ['-', '1.2.3']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('T190 required string contracts keep captions and semantics', (
    tester,
  ) async {
    final grant = TextEditingController(
      text: jsonEncode({
        'label': '',
        'scopes': ['read'],
        'serverIds': <String>[],
      }),
    );
    final document = DesignAutomationFixtures.body()
      ..['steps'] = [
        {
          'id': 'install',
          'kind': 'install_recipe',
          'recipeDigest': 'a' * 64,
          'version': '1.2.3',
        },
      ];
    final body = TextEditingController(text: jsonEncode(document));
    var changes = 0;
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  AutomationStructuredDraft(
                    input: grant,
                    enabled: true,
                    onChanged: (_) => changes++,
                  ),
                  AutomationProfileFields(
                    body: body,
                    enabled: true,
                    onChanged: (_) => changes++,
                    identityFields: const [],
                    showTabs: false,
                    selectedSection: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in [
        'Клиент',
        'Идентификатор шага',
        'Digest точного рецепта (SHA-256)',
        'Точная версия',
      ]) {
        final group = find.byWidgetPredicate(
          (widget) => widget is AutomationLabeledField && widget.label == label,
        );
        expect(
          tester.widget<AutomationLabeledField>(group).required,
          isTrue,
          reason: label,
        );
        expect(
          find.descendant(of: group, matching: find.text('$label *')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: group,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.isRequired == true,
            ),
          ),
          findsOneWidget,
        );
      }
      expect(changes, 0);
      expect(jsonDecode(body.text), document);
      expect(jsonDecode(grant.text)['label'], '');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      grant.dispose();
      body.dispose();
    }
  });
  testWidgets(
    'T190 target selector has external keyboard focus and original selection callback',
    (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      final changes = <Set<String>>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.dark,
          home: Scaffold(
            body: RepaintBoundary(
              key: boundary,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    AutomationDraftSelectionField(
                      label: 'Цели',
                      enabled: true,
                      selected: const {'a'},
                      options: const {'a': 'Сервер A', 'b': 'Сервер B'},
                      current: () => true,
                      onChanged: changes.add,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final bounds = tester.getRect(find.byType(AutomationDraftSelectionField));
      final origin = tester.getTopLeft(find.byKey(boundary));
      final paint = await pixels(tester, boundary, [
        Offset(
          bounds.center.dx - origin.dx,
          bounds.top + 20 + 7 - 3 - origin.dy,
        ),
      ]);
      expect(paint.single, BrandColors.dark['focus']);
      expect(changes, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сервер B'));
      await tester.tap(find.widgetWithText(FilledButton, 'Выбрать'));
      await tester.pumpAndSettle();
      expect(changes, [
        {'a', 'b'},
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final reduced in [false, true]) {
    testWidgets('T190 long enum value stays readable at200 reduced=$reduced', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final value = List.filled(64, 'Д').join();
      final input = TextEditingController(text: jsonEncode({'choice': value}));
      var changes = 0;
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: BrandTheme.dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                disableAnimations: reduced,
              ),
              child: child!,
            ),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: AutomationStructuredDraft(
                    input: input,
                    enabled: true,
                    onChanged: (_) => changes++,
                    parameterDefinitions: {
                      'choice': {
                        'type': 'enum',
                        'values': [value, 'Короткое'],
                        'default': value,
                      },
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.text(value)).height,
          greaterThanOrEqualTo(80),
        );
        expect(jsonDecode(input.text), {'choice': value});
        expect(changes, 0);
        await tester.tap(find.byType(MotionDropdown<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Короткое').last);
        await tester.pumpAndSettle();
        expect(jsonDecode(input.text), {'choice': 'Короткое'});
        expect(changes, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        input.dispose();
      }
    });
  }
  for (final width in [1100.0, 390.0]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'T190 scalar visible geometry and native editing $width dark=$dark scale=$scale',
          (tester) async {
            tester.view.physicalSize = Size(width, 800);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final semantics = tester.ensureSemantics();
            final values = <Object?>[];
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
                    body: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          AutomationValueField(
                            label: 'Число',
                            value: 7,
                            enabled: true,
                            numeric: true,
                            onChanged: values.add,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final field = find.byType(TextField);
              final phone = width <= 520;
              final bodyHeight = scale == 1
                  ? (phone ? 44.0 : 42.0)
                  : (phone ? 66.0 : 60.0);
              expect(
                tester.getSize(find.byType(AutomationValueField)).height,
                20 * scale + 7 + bodyHeight,
              );
              expect(tester.getSize(field).height, greaterThanOrEqualTo(44));
              expect(
                tester.getSemantics(field).rect.height,
                greaterThanOrEqualTo(44),
              );
              final bounds = tester.getRect(field);
              await tester.tapAt(Offset(bounds.center.dx, bounds.top + .2));
              await tester.pumpAndSettle();
              expect(
                tester
                    .widget<EditableText>(find.byType(EditableText))
                    .focusNode
                    .hasFocus,
                isTrue,
              );
              await tester.enterText(field, '-');
              await tester.enterText(field, '-3');
              await tester.enterText(field, '');
              expect(values, ['-', -3, '']);
              FocusManager.instance.primaryFocus?.unfocus();
              await tester.pumpAndSettle();
              final bottom = tester.getRect(field);
              await tester.tapAt(Offset(bottom.center.dx, bottom.bottom - .2));
              await tester.pumpAndSettle();
              expect(
                tester
                    .widget<EditableText>(find.byType(EditableText))
                    .focusNode
                    .hasFocus,
                isTrue,
              );
              expect(tester.takeException(), isNull);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              semantics.dispose();
            }
          },
        );
      }
    }
  }
  for (final width in [1100.0, 800.0, 390.0, 360.0]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'T190 authoring external captions and textarea $width dark=$dark scale=$scale',
          (tester) async {
            tester.view.physicalSize = Size(width, 800);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final name = TextEditingController(text: 'Профиль');
            final description = TextEditingController(text: 'Точное описание');
            final body = TextEditingController(
              text: jsonEncode(DesignAutomationFixtures.body()),
            );
            var saves = 0;
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
                      child: AutomationProfileEditorDialog(
                        asPage: true,
                        name: name,
                        description: description,
                        body: body,
                        validating: false,
                        canValidate: true,
                        onBodyChanged: (_) {},
                        onClose: () {},
                        onSave: () => saves++,
                        onValidate: () {},
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final input = find.byWidgetPredicate(
                (w) => w is TextField && w.controller == description,
              );
              final label = find.text('Описание');
              expect(
                tester.getRect(label).bottom,
                lessThan(tester.getRect(input).top),
              );
              expect(find.text('Название *'), findsOneWidget);
              expect(find.text('Описание *'), findsNothing);
              expect(
                tester.getSize(input).height,
                greaterThanOrEqualTo(scale == 1 ? 60 : 100),
              );
              expect(
                tester.widget<TextField>(input).decoration!.labelText,
                isNull,
              );
              final nameInput = find.byWidgetPredicate(
                (w) => w is TextField && w.controller == name,
              );
              final nameBounds = tester.getRect(nameInput);
              await tester.tapAt(
                Offset(nameBounds.center.dx, nameBounds.bottom - .2),
              );
              await tester.pumpAndSettle();
              expect(
                tester
                    .widget<EditableText>(
                      find.descendant(
                        of: nameInput,
                        matching: find.byType(EditableText),
                      ),
                    )
                    .focusNode
                    .hasFocus,
                isTrue,
              );
              await tester.ensureVisible(input);
              await tester.enterText(input, 'Первая строка\nВторая строка');
              expect(description.text, 'Первая строка\nВторая строка');
              expect(name.text, 'Профиль');
              expect(jsonDecode(body.text), DesignAutomationFixtures.body());
              expect(saves, 0);
              expect(tester.takeException(), isNull);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              name.dispose();
              description.dispose();
              body.dispose();
            }
          },
        );
      }
    }
  }
}
