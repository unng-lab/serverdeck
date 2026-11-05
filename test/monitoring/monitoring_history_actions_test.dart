import 'dart:collection';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/ui/deck_components.dart';
import 'package:serverdeck/monitoring/linux_metrics.dart';

import '../fixtures/monitoring_harness.dart';
import '../fixtures/monitoring_widgets.dart';

void main() {
  testWidgets(
    'new profile revision hides old history and retry during delayed or failed reconciliation',
    (tester) async {
      final w = MonitoringWidgetHarness();
      addTearDown(w.dispose);
      w.h.add(1, connected: true);
      await w.mount(tester);
      await tester.tap(find.text('Host1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Мониторинг'));
      await tester.pumpAndSettle();
      w.h.historyStore.failWrite = true;
      await w.tick(tester, 5);
      await tester.pumpAndSettle();
      expect(w.h.owner.history(mid(1), 1), isNotEmpty);
      expect(w.h.owner.historyError(mid(1), 1), isTrue);
      w.h.operations.items[0] = profile(1, revision: 2, connectionRevision: 2);
      await w.controller.refresh();
      w.h.operations.holdList = Completer<void>();
      final reconcile = w.h.owner.reconcile();
      await tester.pumpAndSettle();
      expect(
        tester.widget<DeckHistory>(find.byType(DeckHistory)).points,
        isEmpty,
      );
      expect(find.text('История мониторинга недоступна'), findsNothing);
      expect(find.text('Повторить сохранение истории'), findsNothing);
      final writes = w.h.historyStore.writes;
      w.h.owner.retryHistory(mid(1), 2);
      await tester.pumpAndSettle();
      expect(w.h.historyStore.writes, writes);
      w.h.operations.failure = StateError('synthetic list failure');
      w.h.operations.holdList!.complete();
      await reconcile;
      await tester.pumpAndSettle();
      expect(
        tester.widget<DeckHistory>(find.byType(DeckHistory)).points,
        isEmpty,
      );
      w.h.operations.failure = null;
      w.h.historyStore.failWrite = false;
      await w.h.owner.reconcile();
      await tester.pumpAndSettle();
      await w.finish(tester);
    },
  );
  testWidgets(
    'Monitoring shows only selected server history without another collect',
    (tester) async {
      final w = MonitoringWidgetHarness();
      addTearDown(w.dispose);
      w.h.add(1, connected: true);
      w.h.add(2, connected: true);
      w.h.port.samples[mid(2)] = Queue.of([
        const LinuxSample(memoryPercent: 75, diskPercent: 80),
      ]);
      await w.mount(tester);
      final count = w.h.port.collected.length;
      await tester.tap(find.text('Host1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Мониторинг'));
      await tester.pumpAndSettle();
      final first = tester.widget<DeckHistory>(find.byType(DeckHistory));
      expect(first.points, isNotEmpty);
      expect((first.points.first as Map)['memoryUsedPercent'], 25);
      expect(first.maxPoints, 720);
      expect(first.periodLabel, 'Последний час');
      expect(first.fullSize, isTrue);
      expect(first.windowEnd!.millisecondsSinceEpoch, w.h.clock.utc());
      expect(first.quality, 'incomplete');
      expect(find.text('Качество истории не указано'), findsNothing);
      expect(
        find.text('Последний час · значения от 0 до 100%'),
        findsOneWidget,
      );
      await tester.tap(find.text('Host2'));
      await tester.pumpAndSettle();
      final second = tester.widget<DeckHistory>(find.byType(DeckHistory));
      final source = (second.points.first as Map)['receivedAt'];
      expect((second.points.first as Map)['memoryUsedPercent'], 75);
      expect(source, isNotNull);
      expect(w.h.port.collected, hasLength(count));
      expect(
        find.byKey(
          const ValueKey('history-00000002-0000-4000-8000-000000000000'),
        ),
        findsOneWidget,
      );
      await w.finish(tester);
    },
  );
  testWidgets(
    'empty history and storage error retry action do not expose raw failures',
    (tester) async {
      final w = MonitoringWidgetHarness(autoAllowed: false);
      addTearDown(w.dispose);
      w.h.add(1);
      w.h.historyStore.failRead = true;
      await w.mount(tester);
      await tester.tap(find.text('Host1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Мониторинг'));
      await tester.pumpAndSettle();
      expect(find.text('Истории пока нет.'), findsOneWidget);
      expect(find.text('История мониторинга недоступна'), findsOneWidget);
      expect(find.textContaining('synthetic'), findsNothing);
      w.h.historyStore.failRead = false;
      await tester.ensureVisible(find.text('Повторить сохранение истории'));
      await tester.tap(find.text('Повторить сохранение истории'));
      await tester.pumpAndSettle();
      expect(find.text('История мониторинга недоступна'), findsNothing);
      expect(w.h.port.attempts, isEmpty);
      await w.finish(tester);
    },
  );
}
