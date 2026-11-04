import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/ui/deck_components.dart';

import '../../tool/component_catalog/examples.dart';
import '../support/component_cases.dart';

void main() {
  testWidgets('bounded code scrolls by keyboard without changing raw content', (
    tester,
  ) async {
    final raw = List.generate(300, (i) => 'line $i: точный текст').join('\n');
    final controller = TextEditingController(text: raw);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      componentHarness(
        DeckCode(label: 'Текст', controller: controller, maxHeight: 180),
      ),
    );
    final text = find.descendant(
      of: find.byType(DeckBoundedTextView),
      matching: find.byType(SelectableText),
    );
    tester.widget<SelectableText>(text).focusNode!.requestFocus();
    await tester.pump();
    final scroll = tester.widget<SingleChildScrollView>(
      find.descendant(
        of: find.byType(DeckBoundedTextView),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    expect(scroll.controller!.offset, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    expect(scroll.controller!.offset, greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(
      scroll.controller!.offset,
      scroll.controller!.position.maxScrollExtent,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(scroll.controller!.offset, 0);
    expect(controller.text, raw);
  });
  testWidgets('editable code copies exact current text and stays bounded', (
    tester,
  ) async {
    final controller = TextEditingController(text: '{"old":true}');
    addTearDown(controller.dispose);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData')
          copied = (call.arguments as Map)['text'] as String;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      componentHarness(
        DeckCode(
          label: 'JSON',
          controller: controller,
          readOnly: false,
          maxHeight: 180,
        ),
      ),
    );
    final raw =
        '  {"new": "точный текст"}\n${List.generate(200, (i) => 'line $i').join('\n')}';
    await tester.enterText(find.byType(TextFormField), raw);
    await tester.pump();
    await tester.tap(find.text('Скопировать JSON'));
    await tester.pumpAndSettle();
    expect(copied, raw);
    expect(controller.text, raw);
    expect(tester.getSize(find.byType(TextFormField)).height, 180);
    await tester.pumpWidget(
      componentHarness(
        DeckCode(label: 'JSON', controller: controller, maxHeight: 180),
      ),
    );
    controller.text = 'readonly changed';
    await tester.pump();
    expect(find.text('readonly changed'), findsOneWidget);
    expect(tester.getSize(find.byType(DeckBoundedTextView)).height, 180);
  });
  testWidgets(
    'field preserves draft across theme/resize, validates, and secret reveal is explicit',
    (tester) async {
      final draft = TextEditingController(text: 'demo-secret');
      addTearDown(draft.dispose);
      final form = GlobalKey<FormState>();
      Widget view(bool dark) => componentHarness(
        Form(
          key: form,
          child: DeckTextField(
            label: 'Пароль доступа с длинной подписью',
            controller: draft,
            secret: true,
            validator: (value) =>
                value == null || value.isEmpty ? 'Введите пароль' : null,
          ),
        ),
        dark: dark,
        scale: 2,
      );
      await tester.pumpWidget(view(true));
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField)).controller,
        draft,
      );
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).obscureText,
        true,
      );
      await tester.tap(find.byTooltip('Показать пароль'));
      await tester.pump();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).obscureText,
        false,
      );
      await tester.pumpWidget(view(false));
      await tester.pump();
      expect(draft.text, 'demo-secret');
      await tester.enterText(find.byType(TextFormField), '');
      expect(form.currentState!.validate(), false);
      await tester.pump();
      expect(find.text('Введите пароль'), findsOneWidget);
      expect(tester.takeException(), null);
    },
  );

  testWidgets(
    'late pending completion after retirement does not update a new button',
    (tester) async {
      final delayed = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        componentHarness(
          DeckButton(
            onPressed: () {
              calls++;
              return delayed.future;
            },
            child: const Text('Применить'),
          ),
        ),
      );
      await tester.tap(find.text('Применить'));
      await tester.pumpWidget(componentHarness(const Text('Доступ отозван')));
      delayed.complete();
      await tester.pump();
      expect(calls, 1);
      expect(find.text('Применить'), findsNothing);
      expect(tester.takeException(), null);
    },
  );

  testWidgets(
    'empty, no-results, unavailable and error have different actions',
    (tester) async {
      var retries = 0, clears = 0;
      for (final state in [
        DeckDataState.empty,
        DeckDataState.noResults,
        DeckDataState.error,
        DeckDataState.unavailable,
      ]) {
        await tester.pumpWidget(
          componentHarness(
            DeckCollectionState(
              state: state,
              onRetry: () => retries++,
              onClearSearch: () => clears++,
            ),
          ),
        );
        if (state == DeckDataState.error) {
          await tester.tap(find.text('Повторить чтение'));
        } else
          expect(find.text('Повторить чтение'), findsNothing);
        if (state == DeckDataState.noResults) {
          await tester.tap(find.text('Очистить поиск'));
        } else
          expect(find.text('Очистить поиск'), findsNothing);
      }
      expect(retries, 1);
      expect(clears, 1);
    },
  );

  testWidgets('copy reports exact authorized value and clipboard failure', (
    tester,
  ) async {
    String? copied;
    var fail = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          if (fail) throw PlatformException(code: 'unavailable');
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      componentHarness(const DeckCopyButton(value: '192.0.2.14:22')),
    );
    await tester.tap(find.text('Скопировать'));
    await tester.pumpAndSettle();
    expect(copied, '192.0.2.14:22');
    expect(find.text('Скопировано'), findsOneWidget);
    fail = true;
    await tester.tap(find.text('Скопировать'));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось скопировать'), findsOneWidget);
  });

  testWidgets(
    'confirmation Escape cancels and restores focus without destructive callback',
    (tester) async {
      var effects = 0;
      await tester.pumpWidget(
        componentHarness(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialog) => DeckDialogLayout(
                  title: 'Удалить профиль?',
                  child: const Text('Локальные параметры будут удалены'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialog),
                      child: const Text('Отмена'),
                    ),
                    DeckButton(
                      kind: DeckButtonKind.danger,
                      onPressed: () {
                        effects++;
                        Navigator.pop(dialog);
                      },
                      child: const Text('Удалить'),
                    ),
                  ],
                ),
              ),
              child: const Text('Открыть диалог'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Открыть диалог'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Удалить профиль?'), findsNothing);
      expect(effects, 0);
    },
  );

  testWidgets(
    'path expansion is controlled and unavailable node cannot select',
    (tester) async {
      var selection = '';
      var expanded = <String>{};
      await tester.pumpWidget(
        componentHarness(
          StatefulBuilder(
            builder: (context, setState) => DeckPathTree(
              path: const ['/', 'etc'],
              nodes: const [
                DeckPathNode(
                  id: 'root',
                  label: 'etc',
                  children: [
                    DeckPathNode(id: 'file', label: 'config.yaml'),
                    DeckPathNode(
                      id: 'private',
                      label: 'private',
                      available: false,
                      reason: 'Нет прав',
                    ),
                  ],
                ),
              ],
              expandedIds: expanded,
              onExpansionChanged: (value) => setState(() => expanded = value),
              onSelected: (value) => selection = value,
            ),
          ),
        ),
      );
      expect(find.text('config.yaml'), findsNothing);
      await tester.tap(find.byTooltip('Раскрыть etc'));
      await tester.pump();
      expect(find.text('config.yaml'), findsOneWidget);
      final controls = tester
          .widgetList<TextButton>(find.byType(TextButton))
          .toList();
      expect(controls.last.onPressed, null);
      expect(selection, '');
    },
  );

  testWidgets(
    'plan keeps mandatory context visible while technical details are collapsed',
    (tester) async {
      await tester.pumpWidget(
        componentHarness(
          const DeckPlanSummary(
            target: 'atlas-db',
            effects: 'Перезапуск службы',
            scope: 'Только выбранный сервер',
            deadline: '10:46 UTC',
            details: Text('opaque plan id'),
          ),
        ),
      );
      for (final text in [
        'atlas-db',
        'Перезапуск службы',
        'Только выбранный сервер',
        '10:46 UTC',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      expect(find.text('opaque plan id'), findsNothing);
    },
  );

  testWidgets(
    'actual examples respond to form validation, tabs, menu and pagination',
    (tester) async {
      await tester.pumpWidget(
        componentHarness(const ComponentExample(id: 'C13')),
      );
      await tester.enterText(find.byType(TextFormField), '');
      await tester.tap(find.text('Сохранить'));
      await tester.pump();
      expect(find.text('Введите имя'), findsOneWidget);
      expect(find.textContaining('Форма проверена'), findsNothing);
      await tester.pumpWidget(
        componentHarness(
          const ComponentExample(key: ValueKey('tabs'), id: 'C16'),
        ),
      );
      await tester.tap(find.text('Журнал'));
      await tester.pump();
      expect(
        find.descendant(
          of: find.byWidgetPredicate(
            (widget) =>
                widget is DeckButton && widget.kind == DeckButtonKind.primary,
          ),
          matching: find.text('Журнал'),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(
        componentHarness(
          const ComponentExample(key: ValueKey('pages'), id: 'C08'),
        ),
      );
      await tester.tap(find.text('Далее'));
      await tester.pump();
      expect(find.textContaining('Страница 2'), findsOneWidget);
    },
  );

  testWidgets(
    'diff distinguishes missing sides and conflict instead of fabricating zeros',
    (tester) async {
      await tester.pumpWidget(
        componentHarness(
          const DeckDiff(
            entries: [
              DeckDifference(
                label: 'Новое значение',
                after: '4',
                change: DeckChange.added,
              ),
              DeckDifference(
                label: 'Параметр',
                before: '1',
                after: '2',
                change: DeckChange.conflict,
              ),
            ],
          ),
        ),
      );
      expect(find.text('Нет данных'), findsOneWidget);
      expect(find.textContaining('Конфликт'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    },
  );
}
