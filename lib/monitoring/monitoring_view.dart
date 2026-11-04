import 'package:flutter/material.dart' hide ConnectionState;

import '../domain/models.dart';
import '../domain/error_presentation.dart';
import '../ui/deck_components.dart';
import 'monitoring_models.dart';
import 'monitoring_owner.dart';

/// C02/C11 global recovery controls; no credentials or remote errors in this view.
class MonitoringControls extends StatelessWidget {
  const MonitoringControls({super.key, required this.owner});
  final MonitoringOwner owner;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: owner,
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (owner.startupBlocked)
          DeckNotice(
            title: 'Мониторинг ожидает запуска',
            message: 'Предыдущий запуск не завершился штатно. Автоматические подключения остановлены.',
            nextStep: 'Начните мониторинг, когда будете готовы подключиться к сохранённым серверам.',
            actions: [
              DeckButton(
                onPressed: owner.startExplicitly,
                child: const Text('Начать мониторинг'),
              ),
            ],
          ),
        if (owner.error != null)
          const DeckNotice(
            title: 'Мониторинг временно недоступен',
            message: 'Не удалось обновить список серверов для мониторинга.',
            nextStep: 'Список будет проверен повторно автоматически. Проверьте доступность локальных данных.',
          ),
      ],
    ),
  );
}

/// C07 header belongs to the profiles feature; C09/C10/C11/C18/C21 project metrics.
class MonitoringServerPanel extends StatelessWidget {
  const MonitoringServerPanel({
    super.key,
    required this.owner,
    required this.profileId,
    required this.header,
  });
  final MonitoringOwner owner;
  final String profileId;
  final Widget header;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: owner,
    child: header,
    builder: (context, child) => DeckSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child!,
          MonitoringReadings(
            snapshot: owner.snapshot(profileId),
            now: owner.now,
          ),
        ],
      ),
    ),
  );
}

class MonitoringReadings extends StatelessWidget {
  const MonitoringReadings({
    super.key,
    required this.snapshot,
    required this.now,
  });
  final MonitoringSnapshot snapshot;
  final Duration now;
  @override
  Widget build(BuildContext context) {
    final connection = snapshot.connection;
    final critical = snapshot.hasCritical(now),
        partial = snapshot.isPartial(now);
    final connected = connection?.state == ConnectionState.connected;
    Widget noticeFor(MonitoringReason reason, {String? metric}) {
      final notice = _reason(reason, connected: connected);
      return DeckNotice(
        title: metric == null ? notice.$1 : '$metric: ${notice.$1}',
        message: notice.$2,
        nextStep: notice.$3,
        tone: notice.$4,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (connection != null)
          DeckStatus(
            label: _connectionLabel(connection.state),
            tone: connected ? DeckTone.available : DeckTone.neutral,
          ),
        if (critical)
          const DeckStatus(label: 'Порог достигнут', tone: DeckTone.error),
        if (partial)
          const DeckStatus(label: 'Частичные данные', tone: DeckTone.warning),
        if (!critical && !partial)
          DeckStatus(
            label: snapshot.readings.values.every((r) => r.isFresh(now))
                ? 'Данные актуальны'
                : snapshot.collecting
                ? 'Собираем данные'
                : 'Нет свежих данных',
            tone: snapshot.collecting ? DeckTone.running : DeckTone.neutral,
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final kind in MetricKind.values)
              Expanded(
                child: DeckMetric(
                  label: kind.label,
                  value: snapshot.readings[kind]!.formattedPercent,
                  unit: '%',
                  contextLabel: _metricStatus(kind, snapshot.readings[kind]!),
                  tone: snapshot.readings[kind]!.isCritical(now)
                      ? DeckTone.error
                      : snapshot.readings[kind]!.isFresh(now)
                      ? DeckTone.available
                      : DeckTone.neutral,
                ),
              ),
          ],
        ),
        for (final kind in MetricKind.values)
          if (snapshot.readings[kind]!.displayAt != null)
            DeckKeyValue(
              label: '${kind.label}: обновлено',
              value: _time(snapshot.readings[kind]!),
            ),
        if (connection?.failureCode != null)
          DeckNotice(
            title: 'Состояние подключения',
            message: OperationPresentation.of(
              OperationFailure(connection!.failureCode!),
            ).message,
            nextStep: OperationPresentation.of(
              OperationFailure(connection.failureCode!),
            ).nextStep,
            tone: DeckTone.error,
          )
        else if (snapshot.statusReason != null)
          noticeFor(snapshot.statusReason!)
        else
          for (final kind in MetricKind.values)
            if (snapshot.readings[kind]!.reason != null &&
                snapshot.readings[kind]!.reason != MonitoringReason.baseline &&
                snapshot.readings[kind]!.reason != MonitoringReason.waiting)
              noticeFor(snapshot.readings[kind]!.reason!, metric: kind.label),
      ],
    );
  }

  String _metricStatus(MetricKind kind, MetricReading reading) {
    if (reading.isCritical(now)) return 'Порог достигнут: ${kind.label} ≥ 90%';
    if (reading.isFresh(now)) return 'Актуально';
    if (reading.percent != null) {
      return switch (reading.reason) {
        MonitoringReason.sourceUnavailable ||
        MonitoringReason.invalidResponse ||
        MonitoringReason.timeout ||
        MonitoringReason.outputLimit ||
        MonitoringReason.cleanupPending => 'Устарело: данные недоступны',
        _ => 'Устарело',
      };
    }
    if (reading.reason == MonitoringReason.baseline)
      return 'Ожидаем следующий замер CPU';
    return 'Нет данных';
  }

  String _time(MetricReading reading) {
    final at = DateTime.fromMillisecondsSinceEpoch(
      reading.displayAt!,
      isUtc: true,
    ).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
    final age = reading.receivedAt == null
        ? 0
        : (now - reading.receivedAt!).inSeconds.clamp(0, 2147483647);
    return '$stamp · $age с назад';
  }
}

String _connectionLabel(ConnectionState state) => switch (state) {
  ConnectionState.disconnected => 'Не подключён',
  ConnectionState.connecting => 'Подключаемся',
  ConnectionState.needTrust => 'Ожидает подтверждения ключа',
  ConnectionState.needPassphrase => 'Ожидает passphrase',
  ConnectionState.authenticating => 'Проверяем учётные данные',
  ConnectionState.connected => 'Подключён',
  ConnectionState.cancelled => 'Подключение отменено',
  ConnectionState.failed => 'Ошибка подключения',
};
(String, String, String, DeckTone) _reason(
  MonitoringReason reason, {
  required bool connected,
}) => switch (reason) {
  MonitoringReason.waiting => (
    'Ожидаем подключения',
    'Данные появятся после успешного SSH-подключения.',
    'При необходимости выберите сервер и подтвердите ключ или введите passphrase.',
    DeckTone.neutral,
  ),
  MonitoringReason.baseline => (
    'Ожидаем CPU',
    'Для CPU нужны два последовательных замера.',
    'Следующий замер выполняется автоматически.',
    DeckTone.neutral,
  ),
  MonitoringReason.unsupportedOs => (
    'Мониторинг недоступен для этой ОС',
    'Базовый мониторинг поддерживает Linux.',
    'Подключите Linux-сервер. После изменения среды переподключитесь.',
    DeckTone.warning,
  ),
  MonitoringReason.sourceUnavailable => (
    'Данные мониторинга недоступны',
    'Не удалось получить один или несколько показателей.',
    connected
        ? 'Проверьте права и доступность sh, uname, df и /proc на сервере. Сбор повторится автоматически.'
        : 'Выберите сервер и нажмите «Подключиться». Затем проверьте права и доступность Linux-счётчиков.',
    DeckTone.warning,
  ),
  MonitoringReason.invalidResponse => (
    'Данные мониторинга недоступны',
    'Сервер вернул непригодные данные.',
    'Проверьте Linux-счётчики и доступность df -Pk /. Следующий сбор выполняется автоматически.',
    DeckTone.warning,
  ),
  MonitoringReason.timeout => (
    'Замер не завершён',
    'Сервер не ответил на сбор за отведённое время.',
    'Проверьте доступность сервера. Следующий сбор выполняется автоматически.',
    DeckTone.warning,
  ),
  MonitoringReason.outputLimit => (
    'Замер отклонён',
    'Ответ сервера превысил допустимый объём.',
    'Проверьте окружение SSH и вывод Linux-счётчиков. Следующий сбор выполняется автоматически.',
    DeckTone.warning,
  ),
  MonitoringReason.cleanupPending => (
    'Предыдущий сбор ещё закрывается',
    'Новый канал не создаётся до завершения предыдущего.',
    'Дождитесь ответа сервера. Если ожидание не заканчивается, выберите сервер и переподключитесь.',
    DeckTone.warning,
  ),
  MonitoringReason.disconnected => (
    'Нет подключения',
    'Текущие нагрузки неизвестны.',
    'Выберите сервер и нажмите «Подключиться». Автоматического повторного подключения не будет.',
    DeckTone.neutral,
  ),
  MonitoringReason.paused => (
    'Мониторинг приостановлен',
    'Последние значения не являются текущими.',
    'Вернитесь на экран «Серверы», чтобы возобновить сбор.',
    DeckTone.neutral,
  ),
  MonitoringReason.stopped => (
    'Мониторинг остановлен',
    'Автоматический сбор сейчас не выполняется.',
    'Если доступен явный запуск, нажмите «Начать мониторинг».',
    DeckTone.neutral,
  ),
};
