import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:serverdeck_protocol/connections.dart';
import 'package:serverdeck_protocol/executor_enrollment.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/models.dart';

import '../theme/brand_assets.dart';
import '../theme/brand_theme.dart';
import '../theme/brand_tokens.dart';
import '../theme/motion.dart';
import '../ui/deck_components.dart';
import '../ui/deck_icon.dart';
import '../ui/deck_page.dart';
import '../ui/deck_table_controls.dart';
import 'server_compositions.dart';
import 'metrics_history.dart';

/// Display context of an existing panel dispatch, never execution authority.
enum ServerPresentationOperation {
  read,
  connectionWrite,
  trustConfirm,
  trustRevoke,
  executorWrite,
}

/// Connection presentation only; the owning panel retains every operation.
class ServerConnectionSection extends StatelessWidget {
  const ServerConnectionSection({
    super.key,
    required this.connection,
    required this.trust,
    required this.busy,
    required this.error,
    required this.hasTrustChallenge,
    required this.onRefresh,
    required this.onProbeTrust,
    required this.onConfirmTrust,
    required this.onConnect,
    required this.onDisconnect,
    required this.onRevokeTrust,
    required this.onCancel,
    this.operation = ServerPresentationOperation.read,
    this.trustWriteAcknowledged = false,
    this.busyLabel = 'Выполняется операция сервера',
  });

  final ConnectionSnapshot? connection;
  final HostTrustSnapshot? trust;
  final bool busy, hasTrustChallenge;
  final String? error;
  final String busyLabel;
  final ServerPresentationOperation operation;
  final bool trustWriteAcknowledged;
  final VoidCallback onRefresh,
      onProbeTrust,
      onConfirmTrust,
      onConnect,
      onDisconnect,
      onRevokeTrust,
      onCancel;

  @override
  Widget build(BuildContext context) => DeckSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _connectionSummary(this),
        const SizedBox(height: BrandSpacing.space12),
        _connectionActions(this),
      ],
    ),
  );
}

/// A compact identity badge projects only the matching connection snapshot.
class ServerConnectionBadge extends StatelessWidget {
  const ServerConnectionBadge({super.key, required this.connection});
  final ConnectionSnapshot? connection;

  @override
  Widget build(BuildContext context) {
    final state = connection?.state;
    final interested = connection?.interested == true;
    final role = switch (state) {
      'connected' => 'available',
      'connecting' || 'closing' => 'running',
      null => 'unknown',
      _ => 'unavailable',
    };
    final color = Theme.of(context).extension<BrandColors>()![role];
    final label = switch (state) {
      'connected' => interested ? 'Подключён' : 'Подключён другим клиентом',
      'connecting' => 'Подключение',
      'closing' => 'Отключение',
      'disconnected' => 'Подключение не установлено',
      _ => 'Состояние подключения не получено',
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: BrandTypography.caption.copyWith(
              height: 20 / 12,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// Runtime and fixtures share this complete status/actions/history composition.
class ServerOverviewSection extends StatelessWidget {
  const ServerOverviewSection({
    super.key,
    required this.connection,
    required this.state,
    this.profile,
    this.currentFingerprint,
    this.onCloseChangedKey,
  });
  final ServerConnectionSection connection;
  final Map<String, Object?>? state;
  final ProfileView? profile;
  final String? currentFingerprint;
  final VoidCallback? onCloseChangedKey;
  @override
  Widget build(BuildContext context) {
    if (connection.error == 'TRUST_CHANGED')
      return ServerChangedKeySection(
        profile: profile,
        previousFingerprint: connection.trust?.trust?.key.fingerprint,
        currentFingerprint: currentFingerprint,
        onClose: onCloseChangedKey,
        onReview: connection.busy ? null : connection.onProbeTrust,
      );
    final metrics = state?['metrics'] as Map<String, Object?>?;
    final systemObservation = state?['system'] as Map<String, Object?>?;
    final system = systemObservation?['value'] as Map<String, Object?>?;
    final metricValues = metrics?['value'] as Map<String, Object?>?;
    String volume(Map<String, Object?>? part) {
      final used = part?['usedBytes'], total = part?['totalBytes'];
      if (used is num && total is num)
        return '${(used / 1073741824).toStringAsFixed(1).replaceAll('.', ',')} из ${(total / 1073741824).toStringAsFixed(1).replaceAll('.', ',')} ГБ';
      return part?['usedPercent'] == null ? '—' : '${part!['usedPercent']} %';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (connection.busy)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: DeckStatus(label: connection.busyLabel, pending: true),
          ),
        if (connection.error != null) ...[
          ServerOwnerStatus(
            key: const ValueKey('server-overview-error'),
            error: connection.error!,
            operation: connection.operation,
            trustWriteAcknowledged: connection.trustWriteAcknowledged,
          ),
          const SizedBox(height: 12),
        ],
        ServerResourceCards(state: state),
        const SizedBox(height: 20),
        ServerColumns(
          left: DeckPanel(
            title: 'Сведения о сервере',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ServerFactRows(
                  facts: {
                    'Сервер': profile == null
                        ? 'Не указан'
                        : '${profile!.name} · ${profile!.address}:${profile!.port}',
                    'Система':
                        '${(system?['os'] as Map<String, Object?>?)?['PRETTY_NAME'] ?? '—'} · ${system?['architecture'] ?? '—'}',
                    'Ядро': '${system?['kernel'] ?? '—'}',
                    'CPU': metricValues?['cpuPercent'] == null
                        ? '—'
                        : '${metricValues!['cpuPercent']} %',
                    'Память': volume(
                      metricValues?['memory'] as Map<String, Object?>?,
                    ),
                    'Корневой диск': volume(
                      metricValues?['rootDisk'] as Map<String, Object?>?,
                    ),
                    'Свежесть': _quality(metrics),
                    'Устаревание': 'Метрики после 15 секунд; сохранённые данные помечаются отдельно',
                  },
                ),
                const SizedBox(height: 16),
                _connectionSummary(connection, includeOwnerStatus: false),
                const SizedBox(height: 12),
                KeyedSubtree(
                  key: const ValueKey('server-overview-actions'),
                  child: _connectionActions(connection),
                ),
              ],
            ),
          ),
          right: DeckPanel(
            title: 'Процессор',
            description: 'Последние 10 минут · только реальные наблюдения',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ServerObservationChart(
                  rows: (state?['history'] as List? ?? const [])
                      .whereType<Map<String, Object?>>()
                      .toList(),
                  stale:
                      metrics?['stale'] == true ||
                      metrics?['quality'] == 'stale',
                ),
                const SizedBox(height: 16),
                if (_evictedEmptyHistory(state))
                  const Text(
                    'Кэш наблюдений удалён из-за ограничения ресурсов. Ранее полученная история недоступна.',
                  )
                else
                  MetricsHistory(
                    showPlots: false,
                    showHeading: false,
                    points: (state?['history'] as List? ?? const [])
                        .cast<Object?>(),
                    quality: _observationQuality(metrics),
                    stale: metrics?['stale'] == true,
                    source: metrics?['source'] as String?,
                    observedAt: metrics?['observedAt'] as String?,
                    receivedAt: metrics?['receivedAt'] as String?,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _ObservationContext(value: systemObservation),
        const SizedBox(height: 8),
        _ObservationContext(value: metrics),
      ],
    );
  }
}

class ServerChangedKeySection extends StatelessWidget {
  const ServerChangedKeySection({
    super.key,
    this.profile,
    this.previousFingerprint,
    this.currentFingerprint,
    this.onReview,
    this.onClose,
  });
  final ProfileView? profile;
  final String? previousFingerprint, currentFingerprint;
  final VoidCallback? onReview, onClose;
  @override
  Widget build(BuildContext context) => ServerStatusBody(
    title: 'SSH-ключ изменился',
    icon: 'info',
    emblemRole: 'accent',
    tone: DeckTone.warning,
    facts: {
      'Цель': profile == null
          ? 'Не подтверждена'
          : '${profile!.name} · ${profile!.address}:${profile!.port}',
      'Состояние': 'Ключ сервера отличается от сохранённого',
      'Ранее': previousFingerprint ?? 'Сохранённый отпечаток не предоставлен',
      'Сейчас':
          currentFingerprint ??
          'Новый отпечаток не получен. Выполните проверку ключа.',
      'Следующий шаг': 'Проверьте смену ключа по независимому каналу',
      'Блокировка': 'Чтение и запись остановлены до решения владельца',
    },
    actions: [
      FilledButton(
        clipBehavior: Clip.none,
        onPressed: onReview,
        child: const Text('Пересмотреть доверие'),
      ),
      OutlinedButton(
        clipBehavior: Clip.none,
        onPressed: onClose,
        child: const Text('Закрыть'),
      ),
    ],
  );
}

Widget _connectionSummary(
  ServerConnectionSection value, {
  bool includeOwnerStatus = true,
}) {
  final connected =
      value.connection?.state == 'connected' &&
      value.connection?.interested == true;
  final state = value.connection?.state;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const DeckSectionHeader(title: 'Подключение к серверу'),
      const SizedBox(height: BrandSpacing.space8),
      DeckStatus(
        label: switch (state) {
          'connected' => connected ? 'Подключён' : 'Подключён другим клиентом',
          'connecting' => 'Подключение',
          'closing' => 'Отключение',
          'disconnected' => 'Подключение не установлено',
          _ => 'Состояние подключения не получено',
        },
        tone: state == 'connected'
            ? DeckTone.available
            : state == 'connecting' || state == 'closing'
            ? DeckTone.running
            : state == null
            ? DeckTone.unknown
            : DeckTone.unavailable,
      ),
      if (value.busy && includeOwnerStatus) ...[
        const SizedBox(height: BrandSpacing.space8),
        DeckStatus(label: value.busyLabel, pending: true),
      ],
      if (value.error != null && includeOwnerStatus) ...[
        const SizedBox(height: BrandSpacing.space12),
        ServerOwnerStatus(
          key: const ValueKey('server-overview-error'),
          error: value.error!,
          operation: value.operation,
          trustWriteAcknowledged: value.trustWriteAcknowledged,
        ),
      ],
    ],
  );
}

/// The same safe owner-status projection is used by the live panel and tests.
/// A timeout without a write context does not establish an unknown write.
class ServerOwnerStatus extends StatelessWidget {
  const ServerOwnerStatus({
    super.key,
    required this.error,
    this.operation = ServerPresentationOperation.read,
    this.trustWriteAcknowledged = false,
  });
  final String error;
  final ServerPresentationOperation operation;
  final bool trustWriteAcknowledged;

  @override
  Widget build(BuildContext context) {
    final uncertain = error == 'TIMEOUT' || error == 'SERVICE_UNAVAILABLE';
    if (operation == ServerPresentationOperation.trustConfirm &&
        trustWriteAcknowledged) {
      return DeckNotice(
        title: 'Ответ на запись получен; состояние не перечитано.',
        message: _error(error),
        nextStep: 'Перечитайте состояние доверия. Не подтверждайте прежний запрос повторно.',
        tone: DeckTone.warning,
      );
    }
    if (uncertain &&
        operation != ServerPresentationOperation.read &&
        operation != ServerPresentationOperation.trustRevoke) {
      return DeckNotice(
        title: 'Исход не подтверждён',
        message: _error(error),
        nextStep: 'Перечитайте состояние сервера и доверия перед новым действием. Автоматического повтора нет.',
        tone: DeckTone.unknown,
      );
    }
    return DeckNotice(
      message: _error(error),
      tone: switch (error) {
        'VALIDATION' ||
        'REVISION_CONFLICT' ||
        'TRUST_CHANGED' ||
        'TRUST_REQUIRED' ||
        'FORBIDDEN' ||
        'UNAUTHORIZED' ||
        'UNSUPPORTED' ||
        'CANCELLED' ||
        'CURSOR_EXPIRED' => DeckTone.warning,
        _ => DeckTone.error,
      },
    );
  }
}

Widget _connectionActions(ServerConnectionSection value) {
  final connected =
      value.connection?.state == 'connected' &&
      value.connection?.interested == true;
  return DeckActions(
    children: [
      _button('Обновить подключение', value.busy, value.onRefresh),
      _button('Получить SSH-ключ', value.busy, value.onProbeTrust),
      if (value.hasTrustChallenge)
        _button('Подтвердить SSH-ключ', value.busy, value.onConfirmTrust),
      _button(
        connected ? 'Отключить' : 'Подключить',
        value.busy,
        connected ? value.onDisconnect : value.onConnect,
      ),
      if (value.trust?.trust?.status == HostTrustStatus.trusted)
        _button(
          'Отозвать доверие к SSH-ключу',
          value.busy,
          value.onRevokeTrust,
        ),
      if (value.busy)
        TextButton(
          clipBehavior: Clip.none,
          onPressed: value.onCancel,
          child: const Text('Перестать ждать ответ'),
        ),
    ],
  );
}

/// Executor actions receive existing enrollment metadata and owner callbacks.
class ServerExecutorSection extends StatelessWidget {
  const ServerExecutorSection({
    super.key,
    required this.executor,
    required this.hasInspection,
    required this.busy,
    required this.onRefreshState,
    required this.onInspect,
    required this.onConfirm,
    required this.onRevoke,
  });

  final ExecutorEnrollment? executor;
  final bool hasInspection, busy;
  final VoidCallback onRefreshState, onInspect, onConfirm, onRevoke;

  @override
  Widget build(BuildContext context) => DeckPanel(
    title: 'Подготовка исполнителя',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Осмотр не устанавливает исполнитель. Привязка требует отдельного подтверждения проверенного SSH-ключа.',
        ),
        const SizedBox(height: 16),
        DeckStatus(
          label: executor == null
              ? 'Исполнитель не привязан'
              : 'Исполнитель привязан',
          tone: executor == null ? DeckTone.unknown : DeckTone.available,
        ),
        if (executor != null)
          DeckKeyValue(
            label: 'Идентификатор исполнителя',
            value: executor!.hostId,
            selectable: true,
          ),
        if (executor != null)
          DeckKeyValue(
            label: 'Версия runtime',
            value: executor!.runtimeVersion,
            selectable: true,
          ),
        const DeckKeyValue(
          label: 'Доступность',
          value: 'Чтение не требует установки исполнителя',
        ),
        const SizedBox(height: BrandSpacing.space12),
        DeckActions(
          children: [
            _button('Получить состояние', busy, onRefreshState),
            _button('Получить данные исполнителя', busy, onInspect),
            if (hasInspection)
              _button('Привязать исполнитель', busy, onConfirm),
            if (executor != null)
              _button('Отозвать привязку исполнителя', busy, onRevoke),
          ],
        ),
      ],
    ),
  );
}

/// Captured observations are display projections, never a source of authority.
class ServerSystemSection extends StatelessWidget {
  const ServerSystemSection({
    super.key,
    required this.state,
    this.showHistory = true,
  });

  final Map<String, Object?>? state;
  final bool showHistory;

  Map<String, Object?>? _value(String key) =>
      (state?[key] as Map<String, Object?>?)?['value'] as Map<String, Object?>?;

  @override
  Widget build(BuildContext context) {
    final metrics = _value('metrics'), system = _value('system');
    final memory = metrics?['memory'] as Map<String, Object?>?;
    final disk = metrics?['rootDisk'] as Map<String, Object?>?;
    final parent = state?['metrics'] as Map<String, Object?>?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DeckSectionHeader(title: 'Система и метрики'),
        const SizedBox(height: 16),
        ServerResourceCards(state: state),
        const SizedBox(height: 20),
        if (state?['cacheDropped'] == true)
          const DeckNotice(
            message: 'Кэш наблюдений удалён из-за ограничения ресурсов. Ранее полученная история недоступна.',
          ),
        DeckKeyValue(
          label: 'Система',
          value:
              '${(system?['os'] as Map<String, Object?>?)?['PRETTY_NAME'] ?? '—'} · ${system?['architecture'] ?? '—'} · ${system?['kernel'] ?? '—'}',
        ),
        _ObservationContext(value: state?['system'] as Map<String, Object?>?),
        const SizedBox(height: BrandSpacing.space8),
        Text(
          'CPU: ${metrics?['cpuPercent'] ?? '—'}% · RAM: ${memory?['usedPercent'] ?? '—'}% · Диск /: ${disk?['usedPercent'] ?? '—'}%',
          style: BrandTypography.table,
        ),
        _ObservationContext(value: parent),
        if (!_evictedEmptyHistory(state) &&
            (showHistory ||
                (state?['history'] as List? ?? const []).isNotEmpty))
          MetricsHistory(
            showPlots: showHistory,
            points: (state?['history'] as List? ?? const []).cast<Object?>(),
            quality: _observationQuality(parent),
            stale: parent?['stale'] == true,
            source: parent?['source'] as String?,
            observedAt: parent?['observedAt'] as String?,
            receivedAt: parent?['receivedAt'] as String?,
          ),
      ],
    );
  }
}

class _ObservationContext extends StatelessWidget {
  const _ObservationContext({required this.value});
  final Map<String, Object?>? value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DeckStatus(
        label: _quality(value),
        tone: _qualityTone(
          value?['stale'] == true ? 'stale' : _observationQuality(value),
        ),
      ),
      if (value?['truncated'] == true)
        const Text('Источник вернул ограниченные данные.'),
      if (value?['parseErrors'] case final int count when count > 0)
        Text('Ошибок разбора: $count'),
      if (value?['source'] != null) Text('Источник: ${value!['source']}'),
      if (value?['observedAt'] != null)
        Text('Наблюдение: ${value!['observedAt']} · UTC'),
      if (value?['receivedAt'] != null)
        Text('Получено: ${value!['receivedAt']} · UTC'),
    ],
  );
}

/// The selection and configuration freshness state remain with the owner.
class ServerConfigurationSection extends StatelessWidget {
  const ServerConfigurationSection({
    super.key,
    required this.resource,
    required this.busy,
    required this.onResourceChanged,
    required this.onRead,
    this.result,
  });

  final String resource;
  final bool busy;
  final ValueChanged<String?> onResourceChanged;
  final VoidCallback onRead;
  final Widget? result;

  @override
  Widget build(BuildContext context) => DeckSurface(
    child: DeckFormSection(
      title: 'Управляемая конфигурация',
      children: [
        DropdownButtonFormField<String>(
          initialValue: resource,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Управляемый ресурс'),
          items: const [
            DropdownMenuItem(
              value: 'system.motd',
              child: DeckFocusLabel(child: Text('Приветствие сервера')),
            ),
            DropdownMenuItem(
              value: 'postgresql.service',
              child: DeckFocusLabel(child: Text('Служба PostgreSQL')),
            ),
            DropdownMenuItem(
              value: 'postgresql.settings',
              child: DeckFocusLabel(child: Text('Настройки PostgreSQL')),
            ),
            DropdownMenuItem(
              value: 'clickhouse.service',
              child: DeckFocusLabel(child: Text('Служба ClickHouse')),
            ),
            DropdownMenuItem(
              value: 'clickhouse.settings',
              child: DeckFocusLabel(child: Text('Настройки ClickHouse')),
            ),
          ],
          onChanged: busy ? null : onResourceChanged,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: _button('Прочитать ресурс', busy, onRead),
        ),
        if (result != null) result!,
      ],
    ),
  );
}

/// Pure rendering of the owner's already aged configuration comparison.
class ServerConfigurationResult extends StatelessWidget {
  const ServerConfigurationResult({
    super.key,
    required this.value,
    required this.comparisonStatus,
  });

  final Map<String, Object?> value;
  final Object? comparisonStatus;

  @override
  Widget build(BuildContext context) {
    final observation = value['observation'] as Map<String, Object?>;
    final comparison = value['comparison'] as Map<String, Object?>;
    final desired = value['desired'] as Map<String, Object?>?;
    final expected = value['expected'] as Map<String, Object?>?;
    final differences = (comparison['differences'] as List)
        .cast<Map<String, Object?>>();
    final facts = observation['value'] as Map<String, Object?>?;
    final fields = facts?['values'] as Map<String, Object?>?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${observation['resourceId']} · ${_status(observation['status'])}',
        ),
        if (comparison['observedAt'] != null)
          Text('Наблюдение: ${comparison['observedAt']} · UTC'),
        Text(switch (comparisonStatus) {
          'matched' => 'Желаемые и фактические значения совпадают.',
          'drift' => 'Найдены расхождения с желаемыми значениями.',
          'stale' => 'Для сравнения нужны свежие данные.',
          'unmanaged' => 'Успешных применений настроек этого ресурса ещё нет.',
          _ => switch (comparison['reason']) {
            'target-changed' => 'После успешного применения изменились данные цели. Сравнение не подтверждено.',
            'recipe-evidence' =>
              'Данных рецепта для сравнения пока недостаточно.',
            _ => 'Сравнение пока не подтверждено.',
          },
        }),
        if (desired != null) ...[
          Text('Желаемая версия: ${desired['desiredRevision']}'),
          Text('Успешное применение: ${comparison['confirmedAt']} · UTC'),
          if (comparison['basis'] == 'file')
            const Text('Сравнивается управляемый файл конфигурации.'),
          if (comparison['basis'] == 'service')
            const Text('Сравниваются состояние службы и автозапуск.'),
          if (expected?['values'] case final Map<String, Object?> values)
            for (final field in values.entries)
              SelectableText('Желаемое ${field.key}: ${field.value}'),
          if (expected?['kind'] == 'service') ...[
            if (expected?['activeState'] != null)
              Text('Желаемое состояние: ${expected!['activeState']}'),
            if (expected?['unitFileState'] != null)
              Text('Желаемый автозапуск: ${expected!['unitFileState']}'),
          ],
          if (expected?['kind'] == 'recipe')
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'Рецепт: ${expected!['id']} '),
                  TextSpan(
                    text: '${expected['version']}',
                    style: BrandTypography.log,
                  ),
                ],
              ),
            ),
        ],
        if (differences.isNotEmpty) ...[
          const Text('Расхождения:'),
          for (final difference in differences)
            difference['field'] == 'fileDigest'
                ? const Text('Изменилось содержимое управляемого файла.')
                : SelectableText(
                    '${difference['field']}: ожидалось ${difference['desired']}, получено ${difference['observed']}',
                  ),
        ],
        if (facts == null)
          const Text('Подтверждённых данных пока нет.')
        else if (fields != null) ...[
          for (final field in fields.entries)
            SelectableText('${field.key}: ${field.value}'),
        ] else ...[
          if (facts['exists'] == false) const Text('Файл отсутствует.'),
          if (facts['activeState'] != null)
            Text('Состояние службы: ${facts['activeState']}'),
          if (facts['unitFileState'] != null)
            Text('Автозапуск: ${facts['unitFileState']}'),
        ],
      ],
    );
  }
}

/// A bounded log list with a filter controller and callbacks owned by the panel.
/// A controlled target choice; selecting never reads logs or connects a server.
class ServerLogTargetSelector extends StatelessWidget {
  const ServerLogTargetSelector({
    super.key,
    required this.profiles,
    required this.selectedId,
    required this.onSelected,
    this.changes,
    this.available,
  });
  final List<ProfileView> profiles;
  final String? selectedId;
  final ValueChanged<String>? onSelected;
  final Listenable? changes;
  final bool Function()? available;
  @override
  Widget build(BuildContext context) {
    final selected = profiles
        .where((profile) => profile.id == selectedId)
        .firstOrNull;
    final style = BrandTypography.caption.copyWith(height: 18 / 12);
    final measure = TextPainter(
      text: TextSpan(text: selected?.name ?? 'Выберите сервер', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = (measure.width + 48).clamp(96.0, 180.0);
    measure.dispose();
    return SizedBox(
      width: width,
      child: Semantics(
        label: 'Сервер для журнала',
        child: MotionDropdown<String>(
          initialValue: selected?.id,
          decoration: const InputDecoration(
            isDense: true,
            hintText: 'Выберите сервер',
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: [
            for (final profile in profiles)
              DropdownMenuItem(
                value: profile.id,
                child: Tooltip(
                  message:
                      '${profile.name} · ${profile.address.contains(':') ? '[${profile.address}]' : profile.address}:${profile.port}',
                  child: Semantics(
                    label:
                        '${profile.name} · ${profile.address}:${profile.port}',
                    child: Text(profile.name, style: style),
                  ),
                ),
              ),
          ],
          changes: changes,
          available: available,
          onChanged: onSelected == null
              ? null
              : (id) {
                  if (id == null ||
                      !(available?.call() ?? true) ||
                      !profiles.any((profile) => profile.id == id))
                    return;
                  onSelected!(id);
                },
        ),
      ),
    );
  }
}

class ServerLogsSection extends StatefulWidget {
  const ServerLogsSection({
    super.key,
    required this.logs,
    required this.filterController,
    required this.busy,
    required this.onLoad,
    required this.onPrevious,
    required this.onOpenRecord,
    this.profile,
    this.units = const [],
    this.selectedUnit,
    this.unitScope = false,
    this.onScopeChanged,
    this.onUnitChanged,
    this.canRead = true,
    this.canPrevious = true,
    this.showHeaderActions = true,
    this.targetSelector,
  });
  final ProfileView? profile;
  final Map<String, Object?>? logs;
  final TextEditingController filterController;
  final bool busy, unitScope, canRead, canPrevious;
  final bool showHeaderActions;
  final Widget? targetSelector;
  final List<String> units;
  final String? selectedUnit;
  final ValueChanged<bool>? onScopeChanged;
  final ValueChanged<String?>? onUnitChanged;
  final VoidCallback onLoad, onPrevious;
  final ValueChanged<Map<String, Object?>> onOpenRecord;
  @override
  State<ServerLogsSection> createState() => ServerLogsSectionState();
}

class ServerLogsSectionState extends State<ServerLogsSection> {
  bool _filters = false;
  final _search = FocusNode();
  final _recordsKey = GlobalKey();
  void focusSearch() {
    if (mounted) {
      _search.requestFocus();
      final target = _search.context;
      if (target != null && target.mounted)
        Scrollable.ensureVisible(target).ignore();
    }
  }

  void toggleFilters() {
    if (mounted) setState(() => _filters = !_filters);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Widget _disabledFilter(String label, String reason) => Tooltip(
    message: reason,
    child: OutlinedButton(
      clipBehavior: Clip.none,
      onPressed: null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              style: BrandTypography.caption.copyWith(height: 18 / 12),
            ),
          ),
          const SizedBox(width: 6),
          const DeckIcon('chevron', size: 16),
        ],
      ),
    ),
  );

  String _address(ProfileView profile) =>
      '${profile.address.contains(':') ? '[${profile.address}]' : profile.address}:${profile.port}';

  String _time(Object? value) {
    final raw = value is String ? value : null;
    final parsed = raw == null ? null : DateTime.tryParse(raw)?.toUtc();
    if (parsed == null) return raw ?? 'Не указано';
    return '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}:${parsed.second.toString().padLeft(2, '0')}';
  }

  Widget _row(Map<String, Object?> row, int index, int count) {
    final colors = deckColors(context);
    final priority = '${row['priority']}';
    final priorityStyle = BrandTypography.log.copyWith(
      color: ['0', '1', '2', '3'].contains(priority)
          ? colors['error']
          : priority == '4'
          ? colors['warning']
          : priority == 'null'
          ? colors['muted']
          : colors['running'],
    );
    final unit = row['unit'] is String && (row['unit'] as String).isNotEmpty
        ? row['unit'] as String
        : null;
    final message = Text.rich(
      TextSpan(
        children: [
          if (unit != null)
            TextSpan(
              text: '$unit ',
              style: TextStyle(
                color: colors['muted'],
                fontFamily: BrandAssets.semiboldFamily,
                fontWeight: BrandTypography.semiboldWeight,
                fontVariations: BrandTypography.semiboldVariations,
              ),
            ),
          TextSpan(text: '${row['message']}'),
        ],
      ),
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
      style: BrandTypography.log,
    );
    final time = Tooltip(
      message: '${row['timestamp'] ?? 'Время записи не указано'} UTC',
      child: Text(
        _time(row['timestamp']),
        style: BrandTypography.log.copyWith(color: colors['muted']),
      ),
    );
    return Semantics(
      button: true,
      label: 'Полная запись ${row['timestamp']} UTC',
      child: InkWell(
        key: ValueKey('server-log-row-$index'),
        onTap: () => widget.onOpenRecord(row),
        child: DeckFocusLabel(
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            color: index == 0 ? colors['selected'] : colors['bg'],
            padding: EdgeInsets.symmetric(
              horizontal: MediaQuery.sizeOf(context).width <= 520 ? 8 : 10,
              vertical: MediaQuery.sizeOf(context).width <= 520 ? 5 : 1,
            ),
            child: LayoutBuilder(
              builder: (context, bounds) {
                final compact =
                    MediaQuery.sizeOf(context).width <= 520 ||
                    bounds.maxWidth < 440 ||
                    MediaQuery.textScalerOf(context).scale(14) > 14;
                if (compact)
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 70, child: time),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _priorityLabel(row['priority']),
                              style: priorityStyle,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      message,
                    ],
                  );
                final measure = TextPainter(
                  text: TextSpan(
                    text: _priorityLabel(row['priority']),
                    style: priorityStyle,
                  ),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                )..layout();
                final priorityWidth = measure.width.clamp(
                  120.0,
                  bounds.maxWidth * .4,
                );
                measure.dispose();
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 32,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          '${count - index}'.padLeft(4, '0'),
                          textAlign: TextAlign.right,
                          style: BrandTypography.log.copyWith(
                            fontSize: 10,
                            height: 20 / 10,
                            color: colors['control'],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(width: 70, child: time),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: priorityWidth,
                      child: Text(
                        _priorityLabel(row['priority']),
                        style: priorityStyle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: message),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logs = widget.logs;
    final records = logs?['records'] as List? ?? const [];
    final incomplete = _logsIncomplete(logs);
    final quality = logs?['quality'] == 'known' && incomplete
        ? 'incomplete'
        : logs?['quality'];
    final colors = deckColors(context);
    final matchedProfile = widget.profile == null || logs == null
        ? widget.profile
        : ServerLogRecordContext.capture(widget.profile!, logs).profile;
    final resultTarget = matchedProfile == null
        ? '${logs?['serverId'] ?? 'Цель не указана'}'
        : '${matchedProfile.name} · ${_address(matchedProfile)}';
    final source = '${logs?['source'] ?? 'Не получен'}';
    final counters = <String, String>{
      for (final entry in const {
        'dropped': 'Пропущено',
        'duplicates': 'Дубликатов',
        'parseErrors': 'Ошибок разбора',
      }.entries)
        if (logs?[entry.key] case final int value when value > 0)
          entry.value: '$value',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DeckTabs(
          labels: const ['Весь сервер', 'Выбранная служба'],
          selected: widget.unitScope ? 1 : 0,
          onSelected: (index) {
            widget.onScopeChanged?.call(index == 1);
            if (index == 1) setState(() => _filters = true);
          },
        ),
        const DeckTabsGap(),
        DeckPanel(
          title: 'Источник и качество данных',
          padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.sizeOf(context).width <= 520 ? 16 : 18,
            vertical: 12,
          ),
          child: ServerFactRows(
            tableContext: true,
            valueStyles: {
              for (final key in const [
                'Сервер',
                'Источник',
                'Время',
                'Буфер',
                'Пропуски',
                'Качество',
                'Ограничения',
              ])
                key: BrandTypography.caption.copyWith(
                  fontSize: MediaQuery.sizeOf(context).width <= 520 ? 13 : 12,
                  height: MediaQuery.sizeOf(context).width <= 520
                      ? 22 / 13
                      : 20 / 12,
                ),
            },
            facts: {
              'Сервер': resultTarget,
              'Источник': source,
              'Время': 'UTC',
              'Буфер': logs == null
                  ? 'Записи ещё не получены'
                  : 'Получено ${records.length} записей',
              'Пропуски': logs == null
                  ? 'Сведения не получены'
                  : incomplete
                  ? 'Часть записей пропущена или ограничена'
                  : 'Источник не сообщил о пропусках',
              'Качество': widget.busy
                  ? 'Выполняется операция сервера'
                  : _status(quality),
              'Ограничения':
                  'Нет данных, отказ прав и пустой результат различаются',
            },
          ),
        ),
        const SizedBox(height: 20),
        if (widget.showHeaderActions) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                clipBehavior: Clip.none,
                onPressed: focusSearch,
                child: const Text('Поиск'),
              ),
              OutlinedButton(
                clipBehavior: Clip.none,
                onPressed: toggleFilters,
                child: const Text('Фильтры'),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        LayoutBuilder(
          builder: (context, bounds) => Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: bounds.maxWidth < 360 ? bounds.maxWidth : 360,
                child: Semantics(
                  label: 'Фильтр журнала',
                  child: DeckSearchField(
                    inputKey: const ValueKey('server-log-search'),
                    controller: widget.filterController,
                    focusNode: _search,
                    hintText: 'Поиск в сообщениях',
                    maxLength: 256,
                    onSubmitted: (_) {
                      if (!widget.busy && widget.canRead) widget.onLoad();
                    },
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  widget.targetSelector ??
                      Tooltip(
                        message: 'Выбор цели доступен в рабочем пространстве',
                        child: OutlinedButton(
                          clipBehavior: Clip.none,
                          onPressed: null,
                          child: Text(
                            widget.profile?.name ?? 'Цель не выбрана',
                            style: BrandTypography.caption.copyWith(
                              height: 18 / 12,
                            ),
                          ),
                        ),
                      ),
                  _disabledFilter(
                    'Приоритет',
                    'Фильтр приоритета ещё не поддерживается источником',
                  ),
                  _disabledFilter(
                    'Период',
                    'Выбор периода ещё не поддерживается источником',
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_filters) ...[
          const SizedBox(height: 12),
          DeckPanel(
            title: 'Фильтры журнала',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    'unit-scope-${widget.unitScope}-${widget.units.join(',')}',
                  ),
                  initialValue: widget.units.contains(widget.selectedUnit)
                      ? widget.selectedUnit
                      : null,
                  decoration: const InputDecoration(labelText: 'Служба'),
                  isExpanded: true,
                  items: [
                    for (final unit in widget.units)
                      DropdownMenuItem(value: unit, child: Text(unit)),
                  ],
                  onChanged: widget.busy || !widget.unitScope
                      ? null
                      : widget.onUnitChanged,
                ),
                if (widget.units.isEmpty)
                  const Text(
                    'Список служб не получен. Сначала явно обновите данные сервера.',
                  ),
              ],
            ),
          ),
        ],
        if (logs != null && !widget.canPrevious) ...[
          const SizedBox(height: 12),
          const DeckNotice(
            message: 'Параметры фильтра изменены. Показан предыдущий полученный результат; выполните новое чтение.',
          ),
        ],
        if (widget.unitScope && !widget.canRead)
          const Text('Выберите полученную службу перед чтением журнала.'),
        const SizedBox(height: 16),
        DeckPanel(
          key: const ValueKey('server-log-panel'),
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                key: const ValueKey('server-log-toolbar'),
                decoration: BoxDecoration(
                  color: colors['raised'],
                  border: Border(bottom: BorderSide(color: colors['border'])),
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.sizeOf(context).width <= 520 ? 12 : 14,
                  vertical: 10,
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    DeckStatus(
                      label: widget.busy
                          ? 'Выполняется операция сервера'
                          : logs == null
                          ? 'Данных пока нет · UTC'
                          : '${_status(quality)} · UTC',
                      tone: widget.busy
                          ? DeckTone.running
                          : _qualityTone(quality),
                      pending: widget.busy,
                    ),
                    Text(
                      '$resultTarget · $source',
                      style: BrandTypography.log.copyWith(
                        fontSize: 12,
                        height: 20 / 12,
                      ),
                    ),
                    const Tooltip(
                      message: 'Пауза и потоковое получение появятся в расширенном наблюдении',
                      child: OutlinedButton(
                        clipBehavior: Clip.none,
                        onPressed: null,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DeckIcon('pause', size: 16),
                            SizedBox(width: 6),
                            Text('Пауза'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (incomplete)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: CustomPaint(
                    painter: _ServerLogGapPainter(colors['warning']),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DeckIcon(
                            'warning',
                            size: 16,
                            color: colors['warning'],
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Журнал неполный: часть записей пропущена или ограничена.',
                              style: BrandTypography.log.copyWith(
                                fontSize: 12,
                                height: 20 / 12,
                                color: colors['warning'],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (records.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    logs == null
                        ? 'Выполните явное чтение журнала выбранного сервера.'
                        : quality == 'known' && !incomplete
                        ? 'Записей по выбранному фильтру нет.'
                        : 'Подтверждённые записи журнала не получены.',
                  ),
                ),
              if (records.isNotEmpty)
                Container(
                  key: const ValueKey('server-log-viewport'),
                  color: colors['bg'],
                  padding: EdgeInsets.symmetric(
                    vertical: MediaQuery.sizeOf(context).width <= 520 ? 4 : 10,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.builder(
                      key: _recordsKey,
                      primary: false,
                      shrinkWrap: true,
                      itemCount: records.length,
                      itemBuilder: (context, index) => _row(
                        records[index] as Map<String, Object?>,
                        index,
                        records.length,
                      ),
                    ),
                  ),
                ),
              Container(
                key: const ValueKey('server-log-footer'),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors['border'])),
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.sizeOf(context).width <= 520 ? 12 : 14,
                  vertical: MediaQuery.sizeOf(context).width <= 520 ? 12 : 9,
                ),
                child: DefaultTextStyle(
                  style: BrandTypography.log.copyWith(
                    fontSize: 12,
                    height: 20 / 12,
                    color: colors['muted'],
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      Text('Буфер: ${records.length} записей · UTC'),
                      Text(
                        logs?['observedAt'] == null
                            ? 'Время наблюдения не предоставлено'
                            : 'Наблюдение: ${logs!['observedAt']} · UTC',
                      ),
                      if (logs?['nextCursor'] is String)
                        const Text('Доступны предыдущие записи'),
                      for (final entry in counters.entries)
                        Text(
                          '${entry.key}: ${entry.value}',
                          style: TextStyle(color: colors['warning']),
                        ),
                      if (logs?['gaps'] == true)
                        Text(
                          'Источник сообщил о разрыве',
                          style: TextStyle(color: colors['warning']),
                        ),
                      if (logs?['truncated'] == true)
                        Text(
                          'Буфер ограничен; остальные записи не получены',
                          style: TextStyle(color: colors['warning']),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        DeckActions(
          children: [
            FilledButton(
              clipBehavior: Clip.none,
              onPressed: widget.busy || !widget.canRead ? null : widget.onLoad,
              child: const Text('Получить журнал'),
            ),
            OutlinedButton(
              clipBehavior: Clip.none,
              onPressed:
                  widget.busy ||
                      !widget.canPrevious ||
                      logs?['nextCursor'] is! String
                  ? null
                  : widget.onPrevious,
              child: const Text('Предыдущие записи'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        ClipRRect(
          key: const ValueKey('server-log-limitations'),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: colors['surface'],
              border: Border.all(color: colors['border']),
              borderRadius: BorderRadius.circular(8),
            ),
            foregroundDecoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: colors['running'], width: 3),
              ),
            ),
            padding: MediaQuery.sizeOf(context).width <= 520
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 14)
                : const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: DeckIcon(
                    'info',
                    size: MediaQuery.sizeOf(context).width <= 520 ? 18 : 17,
                    color: colors['running'],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Безопасное отображение журнала',
                        style: BrandTypography.table.copyWith(
                          fontFamily: BrandAssets.semiboldFamily,
                          fontWeight: BrandTypography.semiboldWeight,
                          fontVariations: BrandTypography.semiboldVariations,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Пауза, период и приоритет пока недоступны. Чтение поддерживает службу, текст и курсор.',
                        style: BrandTypography.caption.copyWith(
                          height: 20 / 12,
                          color: colors['muted'],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DeckIcon('clock', size: 12, color: colors['muted']),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                records.isEmpty
                    ? 'Последняя запись: не получена'
                    : 'Последняя запись: ${(records.first as Map)['timestamp'] ?? 'Время не указано'} UTC',
                style: BrandTypography.caption.copyWith(
                  height: 18 / 12,
                  color: colors['muted'],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '$source · $resultTarget',
          style: BrandTypography.log.copyWith(
            fontSize: 12,
            height: 18 / 12,
            color: colors['muted'],
          ),
        ),
      ],
    );
  }
}

class _ServerLogGapPainter extends CustomPainter {
  const _ServerLogGapPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      for (var offset = 0.0; offset < metric.length; offset += 7) {
        canvas.drawPath(
          metric.extractPath(offset, (offset + 4).clamp(0, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ServerLogGapPainter oldDelegate) =>
      color != oldDelegate.color;
}

class ServerSoftwareSnapshot extends StatelessWidget {
  const ServerSoftwareSnapshot({
    super.key,
    required this.state,
    this.onOpenCatalog,
  });
  final Map<String, Object?>? state;
  final VoidCallback? onOpenCatalog;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (onOpenCatalog != null)
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            clipBehavior: Clip.none,
            onPressed: onOpenCatalog,
            child: const Text('Каталог установки'),
          ),
        ),
      const SizedBox(height: 16),
      for (final entry in const {
        'packages': 'Системные пакеты',
        'units': 'Службы',
      }.entries) ...[
        DeckPanel(
          title: entry.value,
          description: 'Последний полученный снимок',
          child: Builder(
            builder: (context) {
              final observation = state?[entry.key] as Map<String, Object?>?;
              final rows = observation?['value'] as List?;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ObservationContext(value: observation),
                  const SizedBox(height: 16),
                  if (rows == null)
                    const Text('Подтверждённые данные не получены.')
                  else if (rows.isEmpty)
                    Text(
                      observation?['quality'] == 'known'
                          ? 'Получен пустой результат.'
                          : 'Подтверждённые данные не получены.',
                    )
                  else
                    for (final row in rows.whereType<Map<String, Object?>>())
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final field in row.entries)
                              DeckKeyValue(
                                label: field.key,
                                value: '${field.value ?? '—'}',
                                selectable: true,
                              ),
                            const Divider(),
                          ],
                        ),
                      ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    ],
  );
}

/// Ephemeral display context captured from the same result as the selected row.
/// This value owns no request, cache, transport or authority.
class ServerLogRecordContext {
  const ServerLogRecordContext._({
    required this.serverId,
    required this.profile,
    required this.source,
    required this.observedAt,
  });

  factory ServerLogRecordContext.capture(
    ProfileView currentProfile,
    Map<String, Object?>? logs,
  ) {
    ConnectionIdentity? identity;
    if (logs?['identity'] case final Map<String, Object?> value) {
      try {
        identity = ConnectionIdentity.fromJson(value);
      } on FormatException {
        // Malformed read metadata cannot identify a display endpoint.
      }
    }
    String? text(Object? value) =>
        value is String && value.isNotEmpty ? value : null;
    final serverId = text(logs?['serverId']);
    final matches =
        serverId == currentProfile.id &&
        identity?.profileId == currentProfile.id &&
        identity?.connectionRevision == currentProfile.connectionRevision &&
        identity?.credentialRevision == currentProfile.credentialRevision &&
        identity?.trustRevision == currentProfile.trustRevision;
    return ServerLogRecordContext._(
      serverId: serverId,
      profile: matches ? currentProfile : null,
      source: text(logs?['source']),
      observedAt: text(logs?['observedAt']),
    );
  }

  final String? serverId, source, observedAt;
  final ProfileView? profile;
}

class ServerLogRecordDialog extends StatelessWidget {
  const ServerLogRecordDialog({
    super.key,
    required this.recordContext,
    required this.record,
    required this.onClose,
    this.asPage = false,
    this.workspaceBounds,
    this.pageInsets,
  });

  final ServerLogRecordContext recordContext;
  final Map<String, Object?> record;
  final VoidCallback onClose;
  final bool asPage;
  final ValueGetter<Rect?>? workspaceBounds;
  final ValueGetter<EdgeInsetsGeometry>? pageInsets;

  @override
  Widget build(BuildContext context) {
    final profile = recordContext.profile;
    final source = recordContext.source;
    final observedAt = recordContext.observedAt;
    final address = profile == null
        ? null
        : profile.address.contains(':') && !profile.address.startsWith('[')
        ? '[${profile.address}]'
        : profile.address;
    return ServerPlanDialog(
      title: 'Детали записи журнала',
      eyebrow: 'Журналы / Рабочее пространство',
      asPage: asPage,
      workspaceBounds: workspaceBounds,
      pageInsets: pageInsets,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (profile == null)
            const DeckNotice(
              message:
                  'Параметры цели записи не подтверждены текущими сведениями',
              nextStep:
                  'Закройте окно и получите журнал для текущих параметров.',
            ),
          DeckPanel(
            title: 'Сведения',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ServerFactRows(
                  facts: {
                    'Сервер':
                        profile?.name ??
                        (recordContext.serverId == null
                            ? 'Цель записи не указана'
                            : 'Цель записи: ${recordContext.serverId}'),
                    if (profile != null) 'Адрес': '$address:${profile.port}',
                    'Время': record['timestamp'] == null
                        ? 'Время записи: не указано'
                        : '${record['timestamp']} UTC',
                    'Источник': source ?? 'Источник не указан',
                    'Наблюдение': observedAt == null
                        ? 'Наблюдение: время не указано'
                        : '$observedAt UTC',
                    'Служба': '${record['unit'] ?? 'Не указана'}',
                    'Приоритет': _priorityLabel(record['priority']),
                    'Сообщение': '${record['message']}',
                  },
                  valueWidgets: {
                    'Сообщение': ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: DeckBoundedTextView(
                        text: '${record['message']}',
                        style: BrandTypography.log.copyWith(
                          fontSize: MediaQuery.sizeOf(context).width <= 520
                              ? 13
                              : 12,
                          height: MediaQuery.sizeOf(context).width <= 520
                              ? 22 / 13
                              : 20 / 12,
                        ),
                      ),
                    ),
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                clipBehavior: Clip.none,
                onPressed: () => Clipboard.setData(
                  ClipboardData(text: '${record['message']}'),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DeckIcon('copy'),
                    SizedBox(width: 8),
                    Flexible(child: Text('Скопировать запись')),
                  ],
                ),
              ),
              OutlinedButton(
                clipBehavior: Clip.none,
                onPressed: onClose,
                child: const Text('Закрыть'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The existing cancellable route; the owner retains every revoke operation.
Future<bool> showServerConfirmationDialog({
  required BuildContext context,
  required ProfileView profile,
  required String title,
  required Widget child,
  required String confirmLabel,
  Listenable? changes,
  ProfileView? Function()? currentProfile,
  bool Function()? currentOwner,
}) async =>
    await showMotionDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) =>
          changes != null && currentProfile != null && currentOwner != null
          ? ServerRevokeConfirmation(
              profile: profile,
              changes: changes,
              currentProfile: currentProfile,
              currentOwner: currentOwner,
              title: title,
              confirmLabel: confirmLabel,
              onCancel: () => Navigator.pop(context, false),
              onConfirm: () => Navigator.pop(context, true),
              child: child,
            )
          : ServerConfirmationDialog.revoke(
              profile: profile,
              title: title,
              child: child,
              confirmLabel: confirmLabel,
              onCancel: () => Navigator.pop(context, false),
              onConfirm: () => Navigator.pop(context, true),
            ),
    ) ??
    false;

/// Readonly correlation only; this predicate grants no connection authority.
bool serverConnectionMatchesProfile(
  ConnectionIdentity? identity,
  ProfileView profile,
) =>
    identity != null &&
    identity.profileId == profile.id &&
    identity.connectionRevision == profile.connectionRevision &&
    identity.credentialRevision == profile.credentialRevision &&
    identity.trustRevision == profile.trustRevision;

/// The displayed profile must remain the same even when a page owner is reused.
bool serverProfileReviewIsCurrent(ProfileView reviewed, ProfileView? current) =>
    current != null &&
    current.id == reviewed.id &&
    current.revision == reviewed.revision &&
    current.name == reviewed.name &&
    current.address == reviewed.address &&
    current.port == reviewed.port &&
    current.sshUser == reviewed.sshUser &&
    current.connectionRevision == reviewed.connectionRevision &&
    current.credentialRevision == reviewed.credentialRevision &&
    current.trustRevision == reviewed.trustRevision;

class ServerRevokeConfirmation extends StatefulWidget {
  const ServerRevokeConfirmation({
    super.key,
    required this.profile,
    required this.changes,
    required this.currentProfile,
    required this.currentOwner,
    required this.title,
    required this.child,
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
  });
  final ProfileView profile;
  final Listenable changes;
  final ProfileView? Function() currentProfile;
  final bool Function() currentOwner;
  final String title, confirmLabel;
  final Widget child;
  final VoidCallback onCancel, onConfirm;
  @override
  State<ServerRevokeConfirmation> createState() =>
      _ServerRevokeConfirmationState();
}

class _ServerRevokeConfirmationState extends State<ServerRevokeConfirmation> {
  late final _profile = widget.profile;
  bool _retired = false;
  bool get _current =>
      widget.currentOwner() &&
      serverProfileReviewIsCurrent(_profile, widget.currentProfile());
  @override
  void initState() {
    super.initState();
    _retired = !_current;
    widget.changes.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant ServerRevokeConfirmation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.changes, widget.changes)) {
      oldWidget.changes.removeListener(_changed);
      widget.changes.addListener(_changed);
    }
    _retired = _retired || !_current;
  }

  void _changed() {
    if (_retired || _current) return;
    _retired = true;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void _confirm() {
    if (!mounted) return;
    if (!_retired && _current) {
      widget.onConfirm();
    } else if (!_retired) {
      setState(() => _retired = true);
    }
  }

  @override
  void dispose() {
    _retired = true;
    widget.changes.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _retired = _retired || !_current;
    return ServerConfirmationDialog.revoke(
      profile: _profile,
      title: widget.title,
      confirmLabel: widget.confirmLabel,
      onCancel: widget.onCancel,
      onConfirm: _retired ? null : _confirm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.child,
          if (_retired)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: DeckNotice(
                message: 'Профиль или владелец изменился. Закройте подтверждение и заново проверьте выбранный сервер.',
                tone: DeckTone.warning,
              ),
            ),
        ],
      ),
    );
  }
}

/// Complete confirmation presentation; the owner retains route and consent.
class ServerConfirmationDialog extends StatelessWidget {
  const ServerConfirmationDialog({
    super.key,
    required this.title,
    required this.child,
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
  }) : _profile = null;

  const ServerConfirmationDialog.revoke({
    super.key,
    required ProfileView profile,
    required this.title,
    required this.child,
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
  }) : _profile = profile;

  final ProfileView? _profile;
  final String title, confirmLabel;
  final Widget child;
  final VoidCallback onCancel;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final address = profile == null
        ? null
        : profile.address.contains(':') && !profile.address.startsWith('[')
        ? '[${profile.address}]'
        : profile.address;
    return DeckDialogLayout(
      title: title,
      target: profile == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [Text(profile.name), Text('$address:${profile.port}')],
            ),
      child: child,
      actions: [
        TextButton(
          clipBehavior: Clip.none,
          onPressed: onCancel,
          child: const Text('Отмена'),
        ),
        FilledButton(
          clipBehavior: Clip.none,
          onPressed: onConfirm,
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

/// Presentation guard only. The service still owns challenge validity and CAS.
bool serverTrustReviewIsCurrent({
  required HostTrustChallenge challenge,
  required ProfileView profile,
  required ProfileView? currentProfile,
  required HostTrustChallenge? currentChallenge,
}) =>
    identical(challenge, currentChallenge) &&
    profile.id == challenge.profileId &&
    profile.revision == challenge.expectedRevision &&
    profile.connectionRevision == challenge.connectionRevision &&
    profile.credentialRevision == challenge.credentialRevision &&
    profile.trustRevision == challenge.trustRevision &&
    currentProfile != null &&
    currentProfile.id == profile.id &&
    currentProfile.revision == profile.revision &&
    currentProfile.connectionRevision == profile.connectionRevision &&
    currentProfile.credentialRevision == profile.credentialRevision &&
    currentProfile.trustRevision == profile.trustRevision &&
    currentProfile.address == profile.address &&
    currentProfile.port == profile.port;

/// The reviewed target is frozen for this dialog; changes retire its consent.
class ServerTrustConfirmation extends StatefulWidget {
  const ServerTrustConfirmation({
    super.key,
    required this.challenge,
    required this.profile,
    required this.changes,
    required this.currentProfile,
    required this.currentChallenge,
    required this.onCancel,
    required this.onConfirm,
    this.asPage = false,
    this.workspaceBounds,
    this.pageInsets,
  });

  final HostTrustChallenge challenge;
  final ProfileView profile;
  final Listenable changes;
  final ProfileView? Function() currentProfile;
  final HostTrustChallenge? Function() currentChallenge;
  final VoidCallback onCancel, onConfirm;
  final bool asPage;
  final ValueGetter<Rect?>? workspaceBounds;
  final ValueGetter<EdgeInsetsGeometry>? pageInsets;

  @override
  State<ServerTrustConfirmation> createState() =>
      _ServerTrustConfirmationState();
}

class _ServerTrustConfirmationState extends State<ServerTrustConfirmation> {
  late final HostTrustChallenge _challenge = widget.challenge;
  late final ProfileView _profile = widget.profile;
  late final bool _bound = serverTrustReviewIsCurrent(
    challenge: _challenge,
    profile: _profile,
    currentProfile: _profile,
    currentChallenge: _challenge,
  );
  bool _retired = false, _details = false;

  bool get _current =>
      identical(_challenge, widget.challenge) &&
      serverTrustReviewIsCurrent(
        challenge: _challenge,
        profile: _profile,
        currentProfile: widget.currentProfile(),
        currentChallenge: widget.currentChallenge(),
      );

  @override
  void initState() {
    super.initState();
    _retired = !_current;
    widget.changes.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant ServerTrustConfirmation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.changes, widget.changes)) {
      oldWidget.changes.removeListener(_changed);
      widget.changes.addListener(_changed);
    }
    _retired = _retired || !_current;
  }

  void _changed() {
    if (_retired || _current) return;
    _retired = true;
    // Profile metadata can change while the owning list is building. Retire
    // consent synchronously, then redraw the overlay outside that build.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void _confirm() {
    if (!mounted) return;
    if (!_retired && _current) {
      widget.onConfirm();
    } else if (!_retired) {
      setState(() => _retired = true);
    }
  }

  @override
  void dispose() {
    _retired = true;
    widget.changes.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _retired = _retired || !_current;
    final address =
        _profile.address.contains(':') && !_profile.address.startsWith('[')
        ? '[${_profile.address}]'
        : _profile.address;
    return ServerPlanDialog(
      title: 'Подтверждение SSH-ключа',
      asPage: widget.asPage,
      workspaceBounds: widget.workspaceBounds,
      pageInsets: widget.pageInsets,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_retired)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: DeckNotice(
                message: 'Профиль или SSH-ключ изменился. Закройте подтверждение, перечитайте профиль и заново получите SSH-ключ для проверки адреса и отпечатка.',
                tone: DeckTone.warning,
              ),
            ),
          ServerReviewBody(
            facts: {
              if (_bound)
                'Сервер': '${_profile.name} · $address:${_profile.port}',
              'Алгоритм': _challenge.key.format,
              'Отпечаток': _challenge.key.fingerprint,
              'Проверка': 'Сверьте отпечаток с ключом вашего сервера',
              'Срок проверки': '${_challenge.expiresAt} · UTC',
            },
            consequences: const {
              'Проверка': 'Сверьте отпечаток с ключом вашего сервера',
            },
            actions: [
              FilledButton(
                clipBehavior: Clip.none,
                onPressed: _retired ? null : _confirm,
                child: const Text('Подтвердить ключ'),
              ),
              OutlinedButton(
                clipBehavior: Clip.none,
                onPressed: widget.onCancel,
                child: const Text('Отмена'),
              ),
            ],
          ),
          TextButton(
            clipBehavior: Clip.none,
            onPressed: () => setState(() => _details = !_details),
            child: const Text('Технические сведения'),
          ),
          if (_details)
            DeckKeyValue(
              label: 'Идентификатор профиля',
              value: _challenge.profileId,
              selectable: true,
            ),
        ],
      ),
    );
  }
}

/// Binds readable target metadata to the exact inspected connection identity.
/// This presentation check grants no executor or service authority.
bool serverExecutorReviewIsCurrent({
  required Map<String, Object?> inspection,
  required ProfileView profile,
  required ProfileView? currentProfile,
  required Map<String, Object?>? currentInspection,
}) {
  final enrollment = ExecutorEnrollment.fromJson(
    inspection['enrollment'] as Map<String, Object?>,
  );
  final connection = enrollment.connection;
  return identical(inspection, currentInspection) &&
      inspection['serverId'] == enrollment.serverId &&
      profile.id == enrollment.serverId &&
      profile.id == connection.profileId &&
      profile.connectionRevision == connection.connectionRevision &&
      profile.credentialRevision == connection.credentialRevision &&
      profile.trustRevision == connection.trustRevision &&
      currentProfile != null &&
      currentProfile.id == profile.id &&
      currentProfile.revision == profile.revision &&
      currentProfile.name == profile.name &&
      currentProfile.address == profile.address &&
      currentProfile.port == profile.port &&
      currentProfile.connectionRevision == profile.connectionRevision &&
      currentProfile.credentialRevision == profile.credentialRevision &&
      currentProfile.trustRevision == profile.trustRevision;
}

/// A changed target or inspection permanently retires this displayed consent.
class ServerExecutorConfirmation extends StatefulWidget {
  const ServerExecutorConfirmation({
    super.key,
    required this.inspection,
    required this.profile,
    required this.changes,
    required this.currentProfile,
    required this.currentInspection,
    required this.onCancel,
    required this.onConfirm,
    this.onRevoke,
    this.asPage = false,
    this.workspaceBounds,
    this.pageInsets,
  });

  final Map<String, Object?> inspection;
  final ProfileView profile;
  final Listenable changes;
  final ProfileView? Function() currentProfile;
  final Map<String, Object?>? Function() currentInspection;
  final VoidCallback onCancel, onConfirm;
  final VoidCallback? onRevoke;
  final bool asPage;
  final ValueGetter<Rect?>? workspaceBounds;
  final ValueGetter<EdgeInsetsGeometry>? pageInsets;

  @override
  State<ServerExecutorConfirmation> createState() =>
      _ServerExecutorConfirmationState();
}

class _ServerExecutorConfirmationState
    extends State<ServerExecutorConfirmation> {
  late final _inspection = widget.inspection;
  late final _profile = widget.profile;
  late final _enrollment = ExecutorEnrollment.fromJson(
    _inspection['enrollment'] as Map<String, Object?>,
  );
  bool _retired = false, _details = false;

  bool get _current =>
      identical(_inspection, widget.inspection) &&
      serverExecutorReviewIsCurrent(
        inspection: _inspection,
        profile: _profile,
        currentProfile: widget.currentProfile(),
        currentInspection: widget.currentInspection(),
      );

  @override
  void initState() {
    super.initState();
    _retired = !_current;
    widget.changes.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant ServerExecutorConfirmation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.changes, widget.changes)) {
      oldWidget.changes.removeListener(_changed);
      widget.changes.addListener(_changed);
    }
    _retired = _retired || !_current;
  }

  void _changed() {
    if (_retired || _current) return;
    _retired = true;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void _confirm() {
    if (!mounted) return;
    if (!_retired && _current) {
      widget.onConfirm();
    } else if (!_retired) {
      setState(() => _retired = true);
    }
  }

  @override
  void dispose() {
    _retired = true;
    widget.changes.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _retired = _retired || !_current;
    final address =
        _profile.address.contains(':') && !_profile.address.startsWith('[')
        ? '[${_profile.address}]'
        : _profile.address;
    return ServerPlanDialog(
      title: 'Подготовка исполнителя',
      asPage: widget.asPage,
      workspaceBounds: widget.workspaceBounds,
      pageInsets: widget.pageInsets,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_retired)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: DeckNotice(
                message: 'Профиль или проверка исполнителя изменились. Закройте подтверждение, перечитайте профиль и заново проверьте исполнитель перед привязкой.',
                tone: DeckTone.warning,
              ),
            ),
          ServerReviewBody(
            factStyles: const {'Версия runtime': BrandTypography.log},
            facts: {
              if (!_retired)
                'Цель': '${_profile.name} · $address:${_profile.port}',
              'Идентификатор': _enrollment.hostId,
              'SSH-ключ': _enrollment.connection.key.fingerprint,
              'Версия runtime': _enrollment.runtimeVersion,
              'Изменение': 'Привязать исполнитель к этому серверу',
              'Срок проверки': '${_inspection['expiresAt']} · UTC',
              'Доступность': 'Чтение не требует установки исполнителя',
              'Runtime prerequisites': 'Осмотр только читает существующий исполнитель и ничего не устанавливает.',
            },
            consequences: const {
              'Изменение': 'Привязать исполнитель к этому серверу',
            },
            actions: [
              FilledButton(
                clipBehavior: Clip.none,
                onPressed: _retired ? null : _confirm,
                child: const Text('Привязать исполнитель'),
              ),
              Tooltip(
                message: widget.onRevoke == null
                    ? 'Отзыв доступен для существующей привязки на странице исполнителя'
                    : 'Отозвать существующую привязку',
                child: OutlinedButton(
                  clipBehavior: Clip.none,
                  onPressed: _retired || widget.onRevoke == null
                      ? null
                      : () {
                          if (mounted && !_retired && _current)
                            widget.onRevoke!();
                        },
                  child: const Text('Отозвать привязку'),
                ),
              ),
              OutlinedButton(
                clipBehavior: Clip.none,
                onPressed: widget.onCancel,
                child: const Text('Отмена'),
              ),
            ],
          ),
          TextButton(
            clipBehavior: Clip.none,
            onPressed: () => setState(() => _details = !_details),
            child: const Text('Технические сведения'),
          ),
          if (_details) ...[
            DeckKeyValue(
              label: 'Идентификатор профиля',
              value: _enrollment.serverId,
              selectable: true,
            ),
          ],
        ],
      ),
    );
  }
}

Widget _button(String text, bool busy, VoidCallback action) => OutlinedButton(
  clipBehavior: Clip.none,
  onPressed: busy ? null : action,
  child: Text(text),
);

String _quality(Map<String, Object?>? part) {
  if (part?['stale'] == true)
    return 'Устаревшие данные: ${part?['receivedAt']}';
  return switch (_observationQuality(part)) {
    'known' => 'Получено ${part?['receivedAt']}',
    'stale' => 'Устаревшие данные: ${part?['receivedAt']}',
    'denied' => 'Недостаточно прав',
    'unsupported' => 'Источник не поддерживается',
    'incomplete' => 'Получены неполные данные',
    'error' => 'Ошибка чтения',
    _ => 'Данных пока нет',
  };
}

bool _evictedEmptyHistory(Map<String, Object?>? state) =>
    state?['cacheDropped'] == true &&
    (state?['history'] as List? ?? const []).isEmpty;

bool _positive(Object? value) => value is int && value > 0;

String? _observationQuality(Map<String, Object?>? value) {
  final quality = value?['quality'] as String?;
  if (quality == 'known' &&
      (value?['truncated'] == true || _positive(value?['parseErrors'])))
    return 'incomplete';
  return quality;
}

bool _logsIncomplete(Map<String, Object?>? logs) =>
    logs?['quality'] == 'incomplete' ||
    logs?['gaps'] == true ||
    logs?['truncated'] == true ||
    _positive(logs?['dropped']) ||
    _positive(logs?['parseErrors']);

DeckTone _qualityTone(Object? quality) => switch (quality) {
  'known' => DeckTone.available,
  'stale' || 'incomplete' || 'denied' || 'unsupported' => DeckTone.warning,
  'error' => DeckTone.error,
  _ => DeckTone.unknown,
};

String _status(Object? value) => switch (value) {
  'known' => 'Данные получены',
  'stale' => 'Данные устарели',
  'incomplete' => 'Неполные данные',
  'denied' => 'Недостаточно прав',
  'unsupported' => 'Не поддерживается',
  'error' => 'Ошибка чтения',
  _ => 'Данных пока нет',
};

String _priorityLabel(Object? value) => switch ('$value') {
  '0' => 'Авария',
  '1' => 'Тревога',
  '2' => 'Критическая ошибка',
  '3' => 'Ошибка',
  '4' => 'Предупреждение',
  '5' => 'Уведомление',
  '6' => 'Информация',
  '7' => 'Отладка',
  'null' => 'Не указан',
  _ => 'Неизвестный приоритет: $value',
};

String _error(String code) => switch (code) {
  'VALIDATION' => 'Проверьте параметры операции сервера.',
  'UNAUTHORIZED' => 'Доступ к локальному сервису больше не подтверждён.',
  'UNSUPPORTED' => 'Операция не поддерживается текущим сервисом или сервером.',
  'STORAGE_BLOCKED' => 'Защищённое хранилище недоступно. Восстановите защиту хранилища перед повторной операцией.',
  'TRUST_REQUIRED' => 'Подтвердите SSH-ключ сервера.',
  'TRUST_CHANGED' => 'SSH-ключ сервера изменился. Сверьте новый ключ и подтвердите доверие заново.',
  'REVISION_CONFLICT' => 'Данные сервера изменились. Получите их повторно.',
  'EXECUTOR_UNAVAILABLE' =>
    'Исполнитель не настроен или недоступен на сервере.',
  'RUNTIME_INCOMPATIBLE' ||
  'INCOMPATIBLE' => 'Версия исполнителя не соответствует приложению.',
  'FORBIDDEN' => 'Недостаточно прав для этой операции.',
  'CANCELLED' => 'Ожидание ответа прекращено. Это не подтверждает результат операции сервера.',
  'TIMEOUT' =>
    'Время ожидания истекло. Проверьте состояние перед повторной попыткой.',
  'CURSOR_EXPIRED' => 'Страница журнала устарела. Получите журнал заново.',
  'NOT_READY' => 'Сначала подключитесь к серверу.',
  'NOT_FOUND' => 'Запрос устарел или сервер удалён. Получите данные повторно.',
  'RESOURCE_LIMIT' ||
  'HOST_BUSY' => 'Ресурс занят. Дождитесь завершения текущей операции.',
  _ => 'Операция не выполнена. Проверьте доступность сервиса.',
};
