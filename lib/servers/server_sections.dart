import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:serverdeck_protocol/connections.dart';
import 'package:serverdeck_protocol/executor_enrollment.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/models.dart';

import '../theme/brand_theme.dart';
import '../theme/brand_tokens.dart';
import '../theme/motion.dart';
import '../ui/deck_components.dart';
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
  });

  final ConnectionSnapshot? connection;
  final HostTrustSnapshot? trust;
  final bool busy, hasTrustChallenge;
  final String? error;
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

/// Runtime and fixtures share this complete status/actions/history composition.
class ServerOverviewSection extends StatelessWidget {
  const ServerOverviewSection({
    super.key,
    required this.connection,
    required this.state,
  });
  final ServerConnectionSection connection;
  final Map<String, Object?>? state;

  @override
  Widget build(BuildContext context) {
    final metrics = state?['metrics'] as Map<String, Object?>?;
    return DeckSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _connectionSummary(connection),
          const SizedBox(height: BrandSpacing.space16),
          ServerSystemSection(state: state, showHistory: false),
          const SizedBox(height: BrandSpacing.space16),
          if (_evictedEmptyHistory(state))
            _connectionActions(connection)
          else
            MetricsHistory(
              points: (state?['history'] as List? ?? const []).cast<Object?>(),
              quality: _observationQuality(metrics),
              stale: metrics?['stale'] == true,
              source: metrics?['source'] as String?,
              observedAt: metrics?['observedAt'] as String?,
              receivedAt: metrics?['receivedAt'] as String?,
              actions: _connectionActions(connection),
            ),
        ],
      ),
    );
  }
}

Widget _connectionSummary(ServerConnectionSection value) {
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
          _ => 'Подключение не установлено',
        },
        tone: state == 'connected'
            ? DeckTone.available
            : state == 'connecting' || state == 'closing'
            ? DeckTone.running
            : DeckTone.unavailable,
      ),
      if (value.busy) ...[
        const SizedBox(height: BrandSpacing.space8),
        const DeckStatus(label: 'Выполняется операция сервера', pending: true),
      ],
      if (value.error != null) ...[
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
  Widget build(BuildContext context) => DeckSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DeckSectionHeader(title: 'Исполнитель'),
        if (executor != null)
          DeckKeyValue(
            label: 'Идентификатор исполнителя',
            value: executor!.hostId,
            selectable: true,
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
        if (state?['cacheDropped'] == true)
          const DeckNotice(
            message: 'Кэш наблюдений удалён из-за ограничения ресурсов. Ранее полученная история недоступна.',
          ),
        DeckKeyValue(
          label: 'Система',
          value:
              '${system?['hostname'] ?? '—'} · ${system?['architecture'] ?? '—'} · ${system?['kernel'] ?? '—'}',
        ),
        _ObservationContext(value: state?['system'] as Map<String, Object?>?),
        const SizedBox(height: BrandSpacing.space8),
        Text(
          'CPU: ${metrics?['cpuPercent'] ?? '—'}% · RAM: ${memory?['usedPercent'] ?? '—'}% · Диск /: ${disk?['usedPercent'] ?? '—'}%',
          style: BrandTypography.table,
        ),
        _ObservationContext(value: parent),
        if (showHistory && !_evictedEmptyHistory(state))
          MetricsHistory(
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
class ServerLogsSection extends StatelessWidget {
  const ServerLogsSection({
    super.key,
    required this.logs,
    required this.filterController,
    required this.busy,
    required this.onLoad,
    required this.onPrevious,
    required this.onOpenRecord,
  });

  final Map<String, Object?>? logs;
  final TextEditingController filterController;
  final bool busy;
  final VoidCallback onLoad, onPrevious;
  final ValueChanged<Map<String, Object?>> onOpenRecord;

  @override
  Widget build(BuildContext context) {
    final records = logs?['records'] as List? ?? const [];
    final incomplete = _logsIncomplete(logs);
    final quality = logs?['quality'] == 'known' && incomplete
        ? 'incomplete'
        : logs?['quality'];
    return DeckSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DeckSectionHeader(
            title: 'Журнал сервера',
            description: 'Текущие записи и текстовый фильтр',
          ),
          const SizedBox(height: BrandSpacing.space16),
          TextField(
            controller: filterController,
            maxLength: 256,
            decoration: const InputDecoration(labelText: 'Фильтр журнала'),
          ),
          DeckActions(
            children: [
              _button('Получить журнал', busy, onLoad),
              if (logs?['nextCursor'] is String)
                _button('Предыдущие записи', busy, onPrevious),
            ],
          ),
          if (logs != null) ...[
            const SizedBox(height: BrandSpacing.space12),
            DeckStatus(
              label: '${_status(quality)} · записей: ${records.length}',
              tone: _qualityTone(quality),
            ),
            if (logs?['source'] != null)
              Text('Источник: ${logs!['source']} · UTC'),
            if (logs?['observedAt'] != null)
              Text('Наблюдение: ${logs!['observedAt']} · UTC'),
          ],
          if (incomplete)
            const DeckNotice(
              message:
                  'Журнал неполный: часть записей пропущена или ограничена.',
            ),
          for (final count in const {
            'dropped': 'Пропущено',
            'duplicates': 'Дубликатов',
            'parseErrors': 'Ошибок разбора',
          }.entries)
            if (logs?[count.key] case final int value when value > 0)
              Text('${count.value}: $value'),
          if (logs?['quality'] == 'known' && !incomplete && records.isEmpty)
            const Text('Записей по выбранному фильтру нет.'),
          if (logs != null &&
              (logs?['quality'] != 'known' || incomplete) &&
              records.isEmpty)
            const Text('Подтверждённые записи журнала не получены.'),
          if (records.isNotEmpty)
            SizedBox(
              height: 320,
              child: ListView.builder(
                itemCount: records.length,
                itemBuilder: (context, index) {
                  final row = records[index] as Map<String, Object?>;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: DeckFocusLabel(
                      child: Text(
                        '${row['timestamp']} UTC',
                        style: BrandTypography.caption,
                      ),
                    ),
                    subtitle: Text(
                      '${row['message']}',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: BrandTypography.log,
                    ),
                    trailing: const Tooltip(
                      message: 'Полная запись',
                      child: Icon(
                        Icons.open_in_full,
                        size: BrandGeometry.iconSize,
                      ),
                    ),
                    onTap: () => onOpenRecord(row),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
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
  });

  final ServerLogRecordContext recordContext;
  final Map<String, Object?> record;
  final VoidCallback onClose;

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
    return DeckDialogLayout(
      title: 'Запись журнала',
      target: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (profile != null) ...[
            Text(profile.name),
            Text('$address:${profile.port}'),
          ] else ...[
            Text(
              recordContext.serverId == null
                  ? 'Цель записи не указана'
                  : 'Цель записи: ${recordContext.serverId}',
            ),
            const DeckNotice(
              message:
                  'Параметры цели записи не подтверждены текущими сведениями',
              nextStep:
                  'Закройте окно и получите журнал для текущих параметров.',
            ),
          ],
          Text(source == null ? 'Источник не указан' : 'Источник: $source'),
          Text(
            record['timestamp'] == null
                ? 'Время записи: не указано'
                : 'Время записи: ${record['timestamp']} UTC',
          ),
          Text(
            observedAt == null
                ? 'Наблюдение: время не указано'
                : 'Наблюдение: $observedAt UTC',
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: DeckBoundedTextView(
          text: '${record['message']}',
          style: BrandTypography.log,
        ),
      ),
      actions: [TextButton(onPressed: onClose, child: const Text('Закрыть'))],
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
}) async =>
    await showMotionDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => ServerConfirmationDialog.revoke(
        profile: profile,
        title: title,
        child: child,
        confirmLabel: confirmLabel,
        onCancel: () => Navigator.pop(context, false),
        onConfirm: () => Navigator.pop(context, true),
      ),
    ) ??
    false;

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
        TextButton(onPressed: onCancel, child: const Text('Отмена')),
        FilledButton(onPressed: onConfirm, child: Text(confirmLabel)),
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
  });

  final HostTrustChallenge challenge;
  final ProfileView profile;
  final Listenable changes;
  final ProfileView? Function() currentProfile;
  final HostTrustChallenge? Function() currentChallenge;
  final VoidCallback onCancel, onConfirm;

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
  bool _retired = false;

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
    if (!_retired && _current) {
      widget.onConfirm();
    } else if (!_retired) {
      setState(() => _retired = true);
    }
  }

  @override
  void dispose() {
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
    return ServerConfirmationDialog(
      title: 'Подтвердить SSH-ключ',
      confirmLabel: 'Подтвердить',
      onCancel: widget.onCancel,
      onConfirm: _retired ? null : _confirm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DeckNotice(
            message: 'Сверьте отпечаток с ключом вашего сервера.',
          ),
          if (_retired) ...[
            const SizedBox(height: BrandSpacing.space12),
            const DeckNotice(
              message: 'Профиль или SSH-ключ изменился. Закройте подтверждение, перечитайте профиль и заново получите SSH-ключ для проверки адреса и отпечатка.',
              tone: DeckTone.warning,
            ),
          ],
          const SizedBox(height: BrandSpacing.space12),
          if (_bound) ...[
            DeckKeyValue(label: 'Сервер', value: _profile.name),
            DeckKeyValue(
              label: 'Проверяемый адрес',
              value: '$address:${_profile.port}',
              selectable: true,
            ),
          ],
          DeckKeyValue(
            label: 'Отпечаток SSH-ключа',
            value: _challenge.key.fingerprint,
            selectable: true,
          ),
          Text('Действует до ${_challenge.expiresAt} · UTC'),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const DeckFocusLabel(child: Text('Технические сведения')),
            children: [
              DeckKeyValue(
                label: 'Идентификатор профиля',
                value: _challenge.profileId,
                selectable: true,
              ),
            ],
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
  });

  final Map<String, Object?> inspection;
  final ProfileView profile;
  final Listenable changes;
  final ProfileView? Function() currentProfile;
  final Map<String, Object?>? Function() currentInspection;
  final VoidCallback onCancel, onConfirm;

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
  bool _retired = false;

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
    return ServerConfirmationDialog(
      title: 'Подтвердить исполнитель',
      confirmLabel: 'Привязать',
      onCancel: widget.onCancel,
      onConfirm: _retired ? null : _confirm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DeckNotice(
            message: 'Привязать исполнитель к этому серверу и его проверенному SSH-ключу?',
          ),
          if (_retired) ...[
            const SizedBox(height: BrandSpacing.space12),
            const DeckNotice(
              message: 'Профиль или проверка исполнителя изменились. Закройте подтверждение, перечитайте профиль и заново проверьте исполнитель перед привязкой.',
              tone: DeckTone.warning,
            ),
          ],
          const SizedBox(height: BrandSpacing.space12),
          if (!_retired) ...[
            DeckKeyValue(label: 'Сервер', value: _profile.name),
            DeckKeyValue(
              label: 'Проверяемый адрес',
              value: '$address:${_profile.port}',
              selectable: true,
            ),
          ],
          DeckKeyValue(
            label: 'SSH-ключ',
            value: _enrollment.connection.key.fingerprint,
            selectable: true,
          ),
          Text('Подтверждение действует до ${_inspection['expiresAt']} · UTC'),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const DeckFocusLabel(child: Text('Технические сведения')),
            children: [
              DeckKeyValue(
                label: 'Идентификатор профиля',
                value: _enrollment.serverId,
                selectable: true,
              ),
              DeckKeyValue(
                label: 'Идентификатор исполнителя',
                value: _enrollment.hostId,
                selectable: true,
              ),
              DeckKeyValue(
                label: 'Версия исполнителя',
                value: _enrollment.runtimeVersion,
                selectable: true,
                valueStyle: BrandTypography.log,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Widget _button(String text, bool busy, VoidCallback action) =>
    OutlinedButton(onPressed: busy ? null : action, child: Text(text));

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
