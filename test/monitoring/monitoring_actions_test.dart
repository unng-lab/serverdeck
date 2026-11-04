import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/monitoring/linux_metrics.dart';
import 'package:serverdeck/monitoring/monitoring_models.dart';

import '../fixtures/monitoring_widgets.dart';
import '../fixtures/monitoring_harness.dart';

void main() {
  testWidgets(
    'server row shows live metrics, threshold cause and last update',
    (tester) async {
      final w = MonitoringWidgetHarness();
      addTearDown(w.dispose);
      w.h.add(1, connected: true);
      w.h.port.samples[mid(1)] = Queue.of([
        LinuxSample(
          cpu: CpuCounters([1, 0, 0, 99, 0, 0, 0, 0]),
          memoryPercent: 95,
          diskPercent: 25,
        ),
        LinuxSample(
          cpu: CpuCounters([2, 0, 0, 198, 0, 0, 0, 0]),
          memoryPercent: 20,
          diskPercent: 25,
        ),
      ]);
      await w.mount(tester);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == 'Host1',
        ),
        findsOneWidget,
      );
      expect(find.text('RAM'), findsOneWidget);
      expect(find.text('Диск /'), findsOneWidget);
      expect(find.text('95,0 %'), findsOneWidget);
      expect(find.text('Порог достигнут: RAM ≥ 90%'), findsOneWidget);
      expect(find.text('Порог достигнут'), findsOneWidget);
      expect(find.text('RAM: обновлено'), findsOneWidget);
      await w.tick(tester, 5);
      await tester.pump();
      expect(find.text('20,0 %'), findsOneWidget);
      expect(find.text('Порог достигнут'), findsNothing);
      expect(find.text('Порог достигнут: RAM ≥ 90%'), findsNothing);
      expect(find.text('1,0 %'), findsOneWidget);
    },
  );
  testWidgets(
    'search changes displayed rows but collection remains enabled for all',
    (tester) async {
      final w = MonitoringWidgetHarness();
      addTearDown(w.dispose);
      w.h.add(1, connected: true);
      w.h.add(2, connected: true);
      await w.mount(tester);
      await tester.enterText(find.byType(TextField).first, 'Host1');
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == 'Host1',
        ),
        findsOneWidget,
      );
      expect(find.text('Host2'), findsNothing);
      await w.tick(tester, 5);
      await tester.pump();
      expect(w.h.port.collected.where((id) => id == mid(2)).length, 2);
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump();
      expect(find.text('Host2'), findsOneWidget);
    },
  );
  testWidgets(
    'selection and explicit connect callback survive metric composition',
    (tester) async {
      final w = MonitoringWidgetHarness();
      addTearDown(w.dispose);
      w.h.add(1);
      w.h.port.generations[mid(1)] = 1;
      await w.mount(tester);
      await tester.tap(find.text('Host1'));
      await tester.pumpAndSettle();
      expect(w.controller.selected, mid(1));
      await tester.ensureVisible(find.text('Подключиться'));
      await tester.tap(find.text('Подключиться'));
      await tester.pumpAndSettle();
      expect(w.operations.manualConnects, 1);
      expect(w.h.port.connection(mid(1)).sessionId, isNotNull);
      expect(
        w.h.owner.snapshot(mid(1)).readings[MetricKind.memory]!.percent,
        25,
      );
    },
  );
  testWidgets('empty list still offers existing add-server form', (
    tester,
  ) async {
    final w = MonitoringWidgetHarness();
    addTearDown(w.dispose);
    await w.mount(tester);
    expect(find.text('Серверов пока нет'), findsOneWidget);
    expect(w.h.port.attempts, isEmpty);
    await tester.tap(find.text('Добавить сервер'));
    await tester.pumpAndSettle();
    expect(find.text('Профиль SSH'), findsOneWidget);
    expect(find.text('Сохранить'), findsOneWidget);
    await tester.ensureVisible(find.text('Отмена'));
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
  });
}
