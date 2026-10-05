import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/ui/app.dart';

void main() {
  Future<void> start(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ServerDeckApp());
    await tester.pumpAndSettle();
  }

  testWidgets('BR-S01 profile validates port and supports session edits', (
    tester,
  ) async {
    await start(tester, const Size(1100, 760));
    await tester.tap(find.text('Добавить fixture'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('profile-name')),
      'Fixture edited',
    );
    await tester.enterText(find.byKey(const ValueKey('profile-port')), '0');
    await tester.tap(find.text('Сохранить в сессии'));
    await tester.pumpAndSettle();
    expect(find.text('Порт 1…65535'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('profile-port')), '2222');
    await tester.tap(find.text('Сохранить в сессии'));
    await tester.pumpAndSettle();
    expect(find.text('Fixture edited'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('profile-menu-lab-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Редактировать fixture'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('profile-name')),
      'Renamed Ubuntu',
    );
    await tester.tap(find.text('Сохранить в сессии'));
    await tester.pumpAndSettle();
    expect(find.text('Renamed Ubuntu'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('profile-menu-lab-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить профиль fixture'));
    await tester.pumpAndSettle();
    expect(find.text('Renamed Ubuntu'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('SC01 five demo views at desktop size', (tester) async {
    await start(tester, const Size(1100, 760));
    expect(find.textContaining('ДЕМО'), findsWidgets);
    for (final key in ['software', 'journal', 'metrics', 'jobs', 'servers']) {
      await tester.tap(find.byKey(ValueKey('nav-$key')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('SC01 narrow desktop without overflow', (tester) async {
    await start(tester, const Size(800, 600));
    for (final key in ['software', 'journal', 'metrics', 'jobs', 'servers']) {
      await tester.tap(find.byKey(ValueKey('nav-$key')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('BR-L03/L04 search and pause survive navigation', (tester) async {
    await start(tester, const Size(1100, 760));
    await tester.tap(find.byKey(const ValueKey('nav-journal')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('journal-search-lab-a')),
      'checkpoint',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('checkpoint complete'), findsWidgets);
    expect(find.textContaining('Started PostgreSQL'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('journal-pause')));
    await tester.tap(find.byKey(const ValueKey('nav-servers')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-journal')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Возобновить'), findsOneWidget);
    expect(find.textContaining('checkpoint complete'), findsWidgets);
  });
  testWidgets('BR-J01 fixture plan cannot execute', (tester) async {
    await start(tester, const Size(1100, 760));
    await tester.tap(find.byKey(const ValueKey('nav-jobs')));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('execute-job')),
    );
    expect(button.onPressed, isNull);
    expect(find.textContaining('helper'), findsWidgets);
  });
}
