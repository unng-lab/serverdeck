import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/monitoring/linux_metrics.dart';
import 'package:serverdeck/monitoring/monitoring_models.dart';

import '../fixtures/monitoring_widgets.dart';
import '../fixtures/monitoring_harness.dart';

void main() {
  testWidgets(
    'startup gate exposes explicit start callback and no silent connection',
    (tester) async {
      final w = MonitoringWidgetHarness(autoAllowed: false);
      addTearDown(w.dispose);
      w.h.add(1);
      await w.mount(tester);
      expect(find.text('Начать мониторинг'), findsOneWidget);
      expect(w.h.port.attempts, isEmpty);
      await tester.tap(find.text('Начать мониторинг'));
      await tester.pumpAndSettle();
      expect(w.h.port.admitted, [mid(1)]);
      expect(find.text('Начать мониторинг'), findsNothing);
    },
  );
  testWidgets('stale high values never advertise current critical severity', (
    tester,
  ) async {
    final w = MonitoringWidgetHarness();
    addTearDown(w.dispose);
    w.h.add(1, connected: true);
    w.h.port.samples[mid(1)] = Queue.of([
      const LinuxSample(memoryPercent: 95, diskPercent: 20),
    ]);
    await w.mount(tester);
    expect(find.text('Порог достигнут'), findsOneWidget);
    w.h.port.holdCollections = true;
    await w.tick(tester, 15);
    await tester.pump();
    expect(find.text('95,0 %'), findsOneWidget);
    expect(find.text('Порог достигнут'), findsNothing);
    expect(find.text('Устарело'), findsWidgets);
    await w.finish(tester);
  });
  testWidgets(
    'partial invalid data retains old value with safe reason and next action',
    (tester) async {
      final w = MonitoringWidgetHarness();
      addTearDown(w.dispose);
      w.h.add(1, connected: true);
      await w.mount(tester);
      w.h.port.samples[mid(1)] = Queue.of([
        LinuxSample(
          cpu: CpuCounters([20, 0, 0, 180, 0, 0, 0, 0]),
          memoryReason: MonitoringReason.invalidResponse,
          diskPercent: 65,
        ),
      ]);
      await w.tick(tester, 5);
      await tester.pump();
      expect(find.text('Частичные данные'), findsOneWidget);
      expect(find.text('25,0 %'), findsOneWidget);
      expect(find.text('65,0 %'), findsOneWidget);
      expect(find.text('Устарело: данные недоступны'), findsOneWidget);
      expect(find.text('Сервер вернул непригодные данные.'), findsOneWidget);
    },
  );
  testWidgets('each failed source retains its own reason and next action', (
    tester,
  ) async {
    final w = MonitoringWidgetHarness();
    addTearDown(w.dispose);
    w.h.add(1, connected: true);
    await w.mount(tester);
    w.h.port.samples[mid(1)] = Queue.of([
      LinuxSample(
        cpu: CpuCounters([20, 0, 0, 180, 0, 0, 0, 0]),
        memoryReason: MonitoringReason.invalidResponse,
        diskReason: MonitoringReason.sourceUnavailable,
      ),
    ]);
    await w.tick(tester, 5);
    await tester.pump();
    expect(find.text('Частичные данные'), findsOneWidget);
    expect(find.text('RAM: Данные мониторинга недоступны'), findsOneWidget);
    expect(find.text('Диск /: Данные мониторинга недоступны'), findsOneWidget);
    expect(find.text('Сервер вернул непригодные данные.'), findsOneWidget);
    expect(
      find.text('Не удалось получить один или несколько показателей.'),
      findsOneWidget,
    );
    expect(find.textContaining('Проверьте Linux-счётчики'), findsOneWidget);
    expect(
      find.textContaining('Проверьте права и доступность sh'),
      findsOneWidget,
    );
    expect(find.text('Актуально'), findsOneWidget);
  });
  testWidgets('trust warning survives simultaneous monitoring warning', (
    tester,
  ) async {
    final w = MonitoringWidgetHarness();
    addTearDown(w.dispose);
    w.h.add(1);
    w.operations.trusts[mid(1)] = const TrustView(
      trustRevision: 1,
      observationRevision: 2,
      changed: true,
    );
    w.h.port.generations[mid(1)] = 1;
    w.h.port.views[mid(1)] = const ConnectionView(
      state: ConnectionState.needTrust,
    );
    await w.mount(tester);
    expect(find.text('Ключ сервера изменился'), findsOneWidget);
    expect(find.text('Ожидает подтверждения ключа'), findsOneWidget);
    expect(
      find.textContaining('подтвердите ключ или введите passphrase'),
      findsOneWidget,
    );
  });
  for (final reason in [
    MonitoringReason.timeout,
    MonitoringReason.outputLimit,
    MonitoringReason.cleanupPending,
    MonitoringReason.unsupportedOs,
  ]) {
    testWidgets('safe recovery text for $reason', (tester) async {
      final w = MonitoringWidgetHarness();
      addTearDown(w.dispose);
      w.h.add(1, connected: true);
      w.h.port.samples[mid(1)] = Queue.of([LinuxSample.failed(reason)]);
      await w.mount(tester);
      final text = switch (reason) {
        MonitoringReason.timeout => 'Замер не завершён',
        MonitoringReason.outputLimit => 'Замер отклонён',
        MonitoringReason.cleanupPending => 'Предыдущий сбор ещё закрывается',
        _ => 'Мониторинг недоступен для этой ОС',
      };
      expect(find.text(text), findsOneWidget);
      expect(find.text('Нет данных'), findsWidgets);
    });
  }
}
