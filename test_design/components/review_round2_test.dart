import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/ui/deck_components.dart';

import '../../tool/component_catalog.dart';
import '../../tool/component_catalog/examples.dart';
import '../support/component_cases.dart';

void main() {
  testWidgets(
    'text-only editable code copies its current draft across rebuilds',
    (tester) async {
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
      Widget view(bool dark) => componentHarness(
        const DeckCode(label: 'JSON', text: '{"old":true}', readOnly: false),
        dark: dark,
      );
      await tester.pumpWidget(view(true));
      const raw = '  {"new":"точно"}\n';
      await tester.enterText(find.byType(TextFormField), raw);
      await tester.pumpWidget(view(false));
      await tester.tap(find.text('Скопировать JSON'));
      await tester.pumpAndSettle();
      expect(copied, raw);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byType(TextFormField),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        raw,
      );
    },
  );
  testWidgets(
    'tree owns selection and unavailable exposes no active callbacks',
    (tester) async {
      await tester.pumpWidget(
        componentHarness(const ComponentExample(id: 'C27')),
      );
      await tester.tap(find.text('Выбрать').at(1));
      await tester.pump();
      expect(
        tester.widget<DeckPathTree>(find.byType(DeckPathTree)).selectedId,
        'config',
      );
      await tester.pumpWidget(
        componentHarness(
          const ComponentExample(
            key: ValueKey('selected'),
            id: 'C27',
            state: 'selected',
          ),
        ),
      );
      expect(
        tester.widget<DeckPathTree>(find.byType(DeckPathTree)).selectedId,
        'config',
      );
      await tester.pumpWidget(
        componentHarness(
          const ComponentExample(
            key: ValueKey('unavailable'),
            id: 'C27',
            state: 'unavailable',
          ),
        ),
      );
      expect(find.byType(DeckPathTree), findsNothing);
      expect(find.textContaining('Источник файлов недоступен'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is ButtonStyleButton && w.onPressed != null ||
              w is IconButton && w.onPressed != null,
        ),
        findsNothing,
      );
    },
  );
  testWidgets(
    'actual catalog selector resets fixtures but theme and size preserve draft',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ComponentCatalogApp());
      void chooseComponent(String id) => tester
          .widget<DropdownButton<String>>(
            find.byType(DropdownButton<String>).first,
          )
          .onChanged!(id);
      void chooseState(String state) => tester
          .widget<DropdownButton<String>>(
            find.byType(DropdownButton<String>).last,
          )
          .onChanged!(state);
      chooseComponent('C19');
      await tester.pumpAndSettle();
      expect(find.text('server-demo-014'), findsNothing);
      chooseState('expanded');
      await tester.pumpAndSettle();
      expect(find.text('server-demo-014'), findsOneWidget);
      chooseState('default');
      await tester.pumpAndSettle();
      expect(find.text('server-demo-014'), findsNothing);
      chooseComponent('C13');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'saved draft');
      await tester.tap(find.text('Светлая тема'));
      await tester.pumpAndSettle();
      tester
          .widget<DropdownButton<double>>(find.byType(DropdownButton<double>))
          .onChanged!(360);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'saved draft',
      );
    },
  );
  testWidgets('C25 example contains removed with absent after and unchanged', (
    tester,
  ) async {
    await tester.pumpWidget(
      componentHarness(const ComponentExample(id: 'C25')),
    );
    final entries = tester.widget<DeckDiff>(find.byType(DeckDiff)).entries;
    final removed = entries.singleWhere(
      (entry) => entry.change == DeckChange.removed,
    );
    expect(removed.before, 'legacy');
    expect(removed.after, null);
    expect(entries.any((entry) => entry.change == DeckChange.unchanged), true);
    expect(find.textContaining('Удалено'), findsOneWidget);
  });
}
