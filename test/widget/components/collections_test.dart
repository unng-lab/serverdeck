import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/ui/deck_components.dart';
import 'package:serverdeck/theme/brand_theme.dart';

import '../../support/component_cases.dart';

void main() {
  for (final width in [1100.0, 360.0]) {
    for (final state in [
      DeckDataState.data,
      DeckDataState.refreshing,
      DeckDataState.error,
    ]) {
      testWidgets(
        'bounded collection $width $state reserves all header space',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 400);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final rows = List.generate(
            1000,
            (i) => ComponentRow('$i', 'Сервер $i', '192.0.2.14'),
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: BrandTheme.dark,
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: Scaffold(
                  body: Column(
                    children: [
                      Expanded(
                        child: DeckCollection<ComponentRow>(
                          rows: rows,
                          idOf: (r) => r.id,
                          columns: componentColumns,
                          state: state,
                          onSortChanged: (_) {},
                          onRetry: () {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), null);
          final scroll = find.byType(CustomScrollView);
          await tester.drag(scroll, const Offset(0, -450));
          await tester.pumpAndSettle();
          expect(tester.takeException(), null);
          expect(find.byType(CustomScrollView), findsOneWidget);
        },
      );
    }
  }
  testWidgets('stable IDs survive reorder; row actions do not select', (
    tester,
  ) async {
    var selected = <String>{};
    var rows = componentRows;
    var opened = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      componentHarness(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return DeckCollection<ComponentRow>(
              rows: rows,
              idOf: (r) => r.id,
              columns: componentColumns,
              selection: DeckSelection.multiple,
              selectedIds: selected,
              onSelectionChanged: (ids) => setState(() => selected = ids),
              onOpen: (_) => opened++,
            );
          },
        ),
      ),
    );
    final webCheckbox = find.byWidgetPredicate(
      (widget) =>
          widget is Checkbox && widget.semanticLabel == 'Выбрать atlas-web',
    );
    await tester.tap(webCheckbox);
    await tester.pump();
    expect(selected, {'web'});
    rebuild(() => rows = componentRows.reversed.toList());
    await tester.pump();
    expect(tester.widget<Checkbox>(webCheckbox).value, true);
    await tester.tap(find.text('Открыть').first);
    await tester.pump();
    expect(opened, 1);
    expect(selected, {'web'});
    expect(find.text('Нет данных'), findsOneWidget);
  });

  testWidgets('sort cycles asc, desc, unsorted without changing input rows', (
    tester,
  ) async {
    DeckSort? sort;
    final events = <DeckSort?>[];
    await tester.pumpWidget(
      componentHarness(
        StatefulBuilder(
          builder: (context, setState) => DeckCollection<ComponentRow>(
            rows: componentRows,
            idOf: (r) => r.id,
            columns: componentColumns,
            sort: sort,
            onSortChanged: (next) => setState(() {
              sort = next;
              events.add(next);
            }),
          ),
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.textContaining('Сервер').first);
      await tester.pump();
    }
    expect(events[0]?.direction, DeckSortDirection.ascending);
    expect(events[1]?.direction, DeckSortDirection.descending);
    expect(events[2], null);
    expect(componentRows.first.id, 'web');
  });

  testWidgets('1000 records build lazily, not one widget per supplied record', (
    tester,
  ) async {
    var built = 0;
    final rows = List.generate(
      1000,
      (i) => ComponentRow('$i', 'Сервер $i', '192.0.2.14'),
    );
    await tester.pumpWidget(
      componentHarness(
        DeckCollection<ComponentRow>(
          rows: rows,
          idOf: (r) => r.id,
          columns: [
            DeckColumn(
              id: 'name',
              label: 'Сервер',
              value: (r) => r.name,
              builder: (context, row) {
                built++;
                return Text(row.name);
              },
            ),
          ],
        ),
      ),
    );
    expect(built, greaterThan(0));
    expect(built, lessThan(40));
  });

  testWidgets('pending button synchronously guards double activation', (
    tester,
  ) async {
    final completion = Completer<void>();
    var submissions = 0;
    await tester.pumpWidget(
      componentHarness(
        DeckButton(
          onPressed: () {
            submissions++;
            return completion.future;
          },
          child: const Text('Сохранить'),
        ),
      ),
    );
    await tester.tap(find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    expect(submissions, 1);
    completion.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
  });

  for (final dark in [true, false]) {
    for (final frame in componentFrames) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'collection layout ${dark ? 'dark' : 'light'} $frame $scale',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = frame;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(
              componentHarness(
                DeckCollection<ComponentRow>(
                  rows: componentRows,
                  idOf: (r) => r.id,
                  columns: componentColumns,
                ),
                dark: dark,
                scale: scale,
              ),
            );
            await tester.pump();
            expect(tester.takeException(), null);
            expect(find.text('atlas-web'), findsOneWidget);
            for (final element
                in find.byType(DeckCollection<ComponentRow>).evaluate()) {
              final box = element.renderObject! as RenderBox;
              expect(box.size.width, lessThanOrEqualTo(frame.width));
            }
          },
        );
      }
    }
  }
}
