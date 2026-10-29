import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'dart:ui' show Tristate;

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_page.dart';
import 'package:serverdeck_protocol/models.dart' show ReadinessState;

import '../support/design_fonts.dart' show loadDesignFonts;

Widget _app({double scale = 1, Widget? child}) => MaterialApp(
  theme: BrandTheme.dark,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: FoundationShell(
    state: ReadinessState.ready,
    servers: child ?? const Text('Содержимое'),
  ),
);

Finder _navigation(FoundationSection section) =>
    find.byKey(ValueKey('foundation-navigation-${section.name}'));

void _frame(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUpAll(loadDesignFonts);

  for (final width in [1100.0, 800.0, 390.0]) {
    testWidgets('navigation has one named selected button at width$width', (
      tester,
    ) async {
      _frame(tester, Size(width, 800));
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(_app());
        await tester.pumpAndSettle();
        for (final selected in FoundationSection.values) {
          await tester.tap(_navigation(selected));
          await tester.pumpAndSettle();
          for (final section in FoundationSection.values) {
            final node = tester
                .getSemantics(_navigation(section))
                .getSemanticsData();
            expect(node.label, section.label);
            expect(node.flagsCollection.isButton, isTrue);
            expect(
              node.flagsCollection.isSelected,
              section == selected ? Tristate.isTrue : Tristate.isFalse,
            );
            expect(
              tester.semantics.simulatedAccessibilityTraversal().where((node) {
                final data = node.getSemanticsData();
                return data.label == section.label &&
                    data.flagsCollection.isButton;
              }),
              hasLength(1),
            );
          }
        }
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('canonical tab selection is part of its named button semantics', (
    tester,
  ) async {
    _frame(tester, const Size(390, 800));
    final semantics = tester.ensureSemantics();
    try {
      var selected = 0;
      await tester.pumpWidget(
        _app(
          scale: 2,
          child: StatefulBuilder(
            builder: (context, update) => DeckTabs(
              labels: const ['Основное', 'Сведения'],
              selected: selected,
              onSelected: (value) => update(() => selected = value),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var index = 0; index < 2; index++) {
        final button = find.widgetWithText(
          TextButton,
          ['Основное', 'Сведения'][index],
        );
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        final data = tester.getSemantics(button).getSemanticsData();
        expect(data.label, ['Основное', 'Сведения'][index]);
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.flagsCollection.isSelected, Tristate.isTrue);
        expect(selected, index);
      }
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'readonly canonical tabs retain selected and disabled semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _app(
            child: const DeckTabs(
              labels: ['Обзор', 'Сведения'],
              selected: 0,
              onSelected: null,
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final label in ['Обзор', 'Сведения']) {
          final button = find.widgetWithText(TextButton, label);
          expect(tester.widget<TextButton>(button).onPressed, isNull);
          final data = tester.getSemantics(button).getSemanticsData();
          expect(data.label, label);
          expect(data.flagsCollection.isButton, isTrue);
          expect(data.flagsCollection.isEnabled, Tristate.isFalse);
          expect(
            data.flagsCollection.isSelected,
            label == 'Обзор' ? Tristate.isTrue : Tristate.isFalse,
          );
        }
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('desktop source workspace frame and selected indicator', (
    tester,
  ) async {
    _frame(tester, const Size(1100, 760));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const ValueKey('foundation-workspace'))),
      const Rect.fromLTWH(16, 90, 177, 98),
    );
    expect(
      tester.getRect(
        find.byKey(const ValueKey('foundation-navigation-indicator')),
      ),
      const Rect.fromLTWH(4, 221, 3, 26),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact source mark, workspace, and first navigation positions',
    (tester) async {
      _frame(tester, const Size(800, 600));
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('foundation-workspace'))),
        const Rect.fromLTWH(10, 76, 47, 44),
      );
      expect(tester.getRect(_navigation(FoundationSection.servers)).top, 142);
      expect(find.text('OP'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disappearing workspace focus moves to selected phone section', (
    tester,
  ) async {
    _frame(tester, const Size(1100, 760));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    tester
        .widget<OutlinedButton>(
          find.byKey(const ValueKey('foundation-workspace')),
        )
        .focusNode!
        .requestFocus();
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(390, 800);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(_navigation(FoundationSection.servers))
          .focusNode!
          .hasPrimaryFocus,
      isTrue,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [360.0, 390.0]) {
    testWidgets('phone navigation grows in ordered rows at 200% width$width', (
      tester,
    ) async {
      _frame(tester, Size(width, 800));
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      final panel = find.byKey(const ValueKey('foundation-phone-navigation'));
      expect(tester.getSize(panel).height, 68);
      await tester.pumpWidget(_app(scale: 2));
      await tester.pumpAndSettle();
      final initials = tester.renderObject<RenderParagraph>(find.text('OP'));
      final firstInitial = initials
          .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 1),
          )
          .single;
      final lastInitial = initials
          .getBoxesForSelection(
            const TextSelection(baseOffset: 1, extentOffset: 2),
          )
          .single;
      expect(
        lastInitial.top,
        firstInitial.top,
        reason:
            'Scaled local-context initials must remain visible on one line.',
      );
      expect(tester.getSize(panel).height, greaterThan(68));
      final panelRect = tester.getRect(panel);
      Rect? previous;
      for (final section in FoundationSection.values) {
        final rect = tester.getRect(_navigation(section));
        expect(rect.left, greaterThanOrEqualTo(panelRect.left + 4));
        expect(rect.right, lessThanOrEqualTo(panelRect.right - 4));
        expect(rect.height, greaterThanOrEqualTo(52));
        expect(rect.bottom, lessThanOrEqualTo(panelRect.bottom - 6));
        if (previous != null) {
          expect(
            rect.top > previous.top || rect.left >= previous.right + 4,
            isTrue,
          );
        }
        previous = rect;
        await tester.tap(_navigation(section));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('header wraps actions inside the canonical 300px desktop group', (
    tester,
  ) async {
    _frame(tester, const Size(1100, 760));
    await tester.pumpWidget(
      _app(
        child: DeckPage(
          eyebrow: 'Серверы / Рабочее пространство',
          title: 'Первый запуск',
          description: 'Ваше локальное рабочее пространство готово к работе',
          actions: [
            OutlinedButton(
              onPressed: () {},
              child: const Text('Добавить сервер'),
            ),
            OutlinedButton(
              onPressed: () {},
              child: const Text('Настроить ИИ-доступ'),
            ),
          ],
          child: const SizedBox(key: ValueKey('page-body'), height: 10),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final first = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Добавить сервер'),
    );
    final second = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Настроить ИИ-доступ'),
    );
    // Desktop native targets extend 4px past their source-visible bounds.
    expect(first.left + 4, 772);
    expect(second.left + 4, 772);
    expect(second.top + 4, greaterThanOrEqualTo(first.bottom - 4 + 8));
    tester.view.physicalSize = const Size(800, 600);
    await tester.pumpAndSettle();
    final compactFirst = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Добавить сервер'),
    );
    final compactSecond = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Настроить ИИ-доступ'),
    );
    expect(compactSecond.top, compactFirst.top);
    expect(compactSecond.left + 4, compactFirst.right - 4 + 8);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page padding scrolls inside the full phone content viewport', (
    tester,
  ) async {
    _frame(tester, const Size(390, 800));
    await tester.pumpWidget(
      _app(
        child: DeckPage(
          title: 'Страница',
          child: Column(
            children: [
              for (var i = 0; i < 20; i++)
                SizedBox(height: 60, child: Text('Строка $i')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pageScroll = find
        .descendant(
          of: find.byType(DeckPage),
          matching: find.byType(SingleChildScrollView),
        )
        .first;
    final viewport = tester.getRect(pageScroll);
    final topbar = tester.getRect(
      find.byKey(const ValueKey('foundation-topbar')),
    );
    final navigation = tester.getRect(
      find.byKey(const ValueKey('foundation-phone-navigation')),
    );
    expect(viewport.top, topbar.bottom);
    expect(viewport.bottom, navigation.top);
    expect(tester.getRect(find.text('Страница')).top, viewport.top + 22);
    await tester.drag(pageScroll, const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Страница')).top, lessThan(viewport.top));
    expect(tester.getRect(pageScroll), viewport);
    expect(tester.takeException(), isNull);
  });
}
