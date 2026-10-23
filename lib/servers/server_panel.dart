import 'dart:async';

import 'package:flutter/material.dart';
import 'package:serverdeck_protocol/host_trust.dart' show HostTrustStatus;
import 'package:serverdeck_windows/operational_auth_client.dart';

import 'server_controller.dart';
import 'metrics_history.dart';

/// Remote operations use the same service as MCP through a verified owner RPC.
class ServerPanel extends StatefulWidget {
  const ServerPanel({super.key, required this.client, required this.profileId});
  final TrustedApiClient client;
  final String profileId;
  @override
  State<ServerPanel> createState() => _ServerPanelState();
}

class _ServerPanelState extends State<ServerPanel> {
  late ServerController model;
  final _text = TextEditingController();
  String _resource = 'system.motd';
  @override
  void initState() {
    super.initState();
    _create();
  }

  void _create() {
    model = ServerController(
      client: widget.client,
      profileId: widget.profileId,
    );
    model.refresh().ignore();
  }

  @override
  void didUpdateWidget(covariant ServerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.client, widget.client) ||
        oldWidget.profileId != widget.profileId) {
      model.dispose();
      _create();
    }
  }

  @override
  void dispose() {
    model.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<bool> _confirm(String title, Widget content, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _trust() async {
    final challenge = model.trustChallenge;
    if (challenge == null) return;
    if (await _confirm(
          'Подтвердить SSH-ключ',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Сверьте отпечаток с ключом вашего сервера.'),
              const SizedBox(height: 12),
              SelectableText(challenge.key.fingerprint),
              const SizedBox(height: 8),
              Text('Действует до ${challenge.expiresAt}'),
            ],
          ),
          'Подтвердить',
        ) &&
        mounted &&
        identical(challenge, model.trustChallenge))
      await model.confirmTrust();
  }

  Future<void> _executor() async {
    final inspection = model.executorInspection;
    if (inspection == null) return;
    final enrollment = inspection['enrollment'] as Map<String, Object?>;
    final connection = enrollment['connection'] as Map<String, Object?>;
    final key = connection['key'] as Map<String, Object?>;
    if (await _confirm(
          'Подтвердить исполнитель',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Привязать исполнитель к этому серверу и его проверенному SSH-ключу?',
              ),
              const SizedBox(height: 12),
              const Text('Идентификатор сервера'),
              SelectableText(enrollment['hostId'] as String),
              const SizedBox(height: 8),
              const Text('SSH-ключ'),
              SelectableText(key['fingerprint'] as String),
              const SizedBox(height: 8),
              Text('Версия: ${enrollment['runtimeVersion']}'),
            ],
          ),
          'Привязать',
        ) &&
        mounted &&
        identical(inspection, model.executorInspection))
      await model.confirmExecutor();
  }

  Map<String, Object?>? _value(String key) =>
      (model.state?[key] as Map<String, Object?>?)?['value']
          as Map<String, Object?>?;
  String _quality(String key) {
    final part = model.state?[key] as Map<String, Object?>?;
    if (part?['stale'] == true)
      return 'Устаревшие данные: ${part?['receivedAt']}';
    return switch (part?['quality']) {
      'known' => 'Получено ${part?['receivedAt']}',
      'stale' => 'Устаревшие данные: ${part?['receivedAt']}',
      'denied' => 'Недостаточно прав',
      'unsupported' => 'Источник не поддерживается',
      'incomplete' => 'Получены неполные данные',
      _ => 'Данных пока нет',
    };
  }

  Widget _button(String text, Future<void> Function() action) => OutlinedButton(
    onPressed: model.busy ? null : () => action().ignore(),
    child: Text(text),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      final metrics = _value('metrics'), system = _value('system');
      final memory = metrics?['memory'] as Map<String, Object?>?;
      final disk = metrics?['rootDisk'] as Map<String, Object?>?;
      final connected =
          model.connection?.state == 'connected' &&
          model.connection?.interested == true;
      final logs = model.logs?['records'] as List? ?? const [];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(switch (model.connection?.state) {
            'connected' =>
              connected ? 'Подключён' : 'Подключён другим клиентом',
            'connecting' => 'Подключение',
            'closing' => 'Отключение',
            _ => 'Не подключён',
          }, style: Theme.of(context).textTheme.titleMedium),
          if (model.busy) const LinearProgressIndicator(),
          if (model.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _error(model.error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _button('Обновить подключение', model.refresh),
              _button('Получить SSH-ключ', model.probeTrust),
              if (model.trustChallenge != null)
                _button('Подтвердить SSH-ключ', _trust),
              _button(
                connected ? 'Отключить' : 'Подключить',
                connected ? model.disconnect : model.connect,
              ),
              if (model.trust?.trust?.status == HostTrustStatus.trusted)
                _button('Отозвать доверие к SSH-ключу', () async {
                  if (await _confirm(
                        'Отозвать доверие',
                        const Text(
                          'Доступ к серверу будет остановлен до нового подтверждения ключа.',
                        ),
                        'Отозвать',
                      ) &&
                      mounted)
                    await model.revokeTrust();
                }),
              if (model.busy)
                TextButton(
                  onPressed: () => model.cancel().ignore(),
                  child: const Text('Отменить'),
                ),
            ],
          ),
          const Divider(),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _button('Получить состояние', model.refreshState),
              _button('Получить данные исполнителя', model.inspectExecutor),
              if (model.executorInspection != null)
                _button('Привязать исполнитель', _executor),
              if (model.executor != null)
                _button('Отозвать привязку исполнителя', () async {
                  if (await _confirm(
                        'Отозвать привязку',
                        const Text(
                          'Новые изменения через этот исполнитель будут недоступны.',
                        ),
                        'Отозвать',
                      ) &&
                      mounted)
                    await model.revokeExecutor();
                }),
            ],
          ),
          if (model.executor != null)
            Text('Исполнитель: ${model.executor!.hostId}'),
          Text(
            'Система: ${system?['hostname'] ?? '—'} · ${system?['architecture'] ?? '—'} · ${system?['kernel'] ?? '—'}',
          ),
          Text(_quality('system')),
          Text(
            'CPU: ${metrics?['cpuPercent'] ?? '—'}% · RAM: ${memory?['usedPercent'] ?? '—'}% · Диск /: ${disk?['usedPercent'] ?? '—'}%',
          ),
          Text(_quality('metrics')),
          if (model.state?['history'] is List)
            MetricsHistory(
              points: (model.state!['history'] as List).cast<Object?>(),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _resource,
            decoration: const InputDecoration(labelText: 'Управляемый ресурс'),
            items: const [
              DropdownMenuItem(
                value: 'system.motd',
                child: Text('Приветствие сервера'),
              ),
              DropdownMenuItem(
                value: 'postgresql.service',
                child: Text('Служба PostgreSQL'),
              ),
              DropdownMenuItem(
                value: 'postgresql.settings',
                child: Text('Настройки PostgreSQL'),
              ),
              DropdownMenuItem(
                value: 'clickhouse.service',
                child: Text('Служба ClickHouse'),
              ),
              DropdownMenuItem(
                value: 'clickhouse.settings',
                child: Text('Настройки ClickHouse'),
              ),
            ],
            onChanged: model.busy
                ? null
                : (value) {
                    if (value != null) setState(() => _resource = value);
                  },
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: _button(
              'Прочитать ресурс',
              () => model.readConfiguration(_resource),
            ),
          ),
          if (model.configuration != null)
            _Configuration(value: model.configuration!),
          const Divider(),
          TextField(
            controller: _text,
            maxLength: 256,
            decoration: const InputDecoration(labelText: 'Фильтр журнала'),
          ),
          Wrap(
            spacing: 8,
            children: [
              _button(
                'Получить журнал',
                () => model.loadLogs(text: _text.text),
              ),
              if (model.logs?['nextCursor'] is String)
                _button(
                  'Предыдущие записи',
                  () => model.loadLogs(
                    text: _text.text,
                    cursor: model.logs!['nextCursor'] as String,
                  ),
                ),
            ],
          ),
          if (model.logs != null)
            Text(
              'UTC · ${_status(model.logs!['quality'])} · записей: ${logs.length}',
            ),
          if (model.logs?['gaps'] == true || model.logs?['truncated'] == true)
            const Text(
              'Журнал неполный: часть записей пропущена или ограничена.',
            ),
          if (model.logs?['quality'] == 'known' && logs.isEmpty)
            const Text('Записей по выбранному фильтру нет.'),
          if (model.logs != null &&
              model.logs?['quality'] != 'known' &&
              logs.isEmpty)
            const Text('Подтверждённые записи журнала не получены.'),
          if (logs.isNotEmpty)
            SizedBox(
              height: 320,
              child: ListView.builder(
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  final row = logs[index] as Map<String, Object?>;
                  return ListTile(
                    title: Text('${row['timestamp']}'),
                    subtitle: Text(
                      '${row['message']}',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.open_in_full),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('${row['timestamp']} UTC'),
                        content: SizedBox(
                          width: 640,
                          child: SingleChildScrollView(
                            child: SelectableText('${row['message']}'),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Закрыть'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      );
    },
  );
}

class _Configuration extends StatefulWidget {
  const _Configuration({required this.value});
  final Map<String, Object?> value;
  @override
  State<_Configuration> createState() => _ConfigurationState();
}

class _ConfigurationState extends State<_Configuration> {
  Timer? _age;
  Map<String, Object?> get value => widget.value;
  @override
  void initState() {
    super.initState();
    _scheduleAge();
  }

  @override
  void didUpdateWidget(covariant _Configuration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.value, widget.value)) _scheduleAge();
  }

  void _scheduleAge() {
    _age?.cancel();
    final comparison = value['comparison'] as Map<String, Object?>;
    if (!const {'matched', 'drift'}.contains(comparison['status'])) return;
    final observed = DateTime.tryParse('${comparison['observedAt']}');
    if (observed == null) return;
    final left = observed
        .add(const Duration(seconds: 15, milliseconds: 1))
        .difference(DateTime.now().toUtc());
    if (left <= Duration.zero) return;
    _age = Timer(left, () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _age?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final observation = value['observation'] as Map<String, Object?>;
    final comparison = value['comparison'] as Map<String, Object?>;
    var comparisonStatus = comparison['status'];
    if (const {'matched', 'drift'}.contains(comparisonStatus)) {
      final observed = DateTime.tryParse('${comparison['observedAt']}');
      final age = observed == null
          ? null
          : DateTime.now().toUtc().difference(observed);
      if (age == null || age.isNegative || age > const Duration(seconds: 15))
        comparisonStatus = 'stale';
    }
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
            Text('Рецепт: ${expected!['id']} ${expected['version']}'),
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
  'TRUST_REQUIRED' => 'Подтвердите SSH-ключ сервера.',
  'TRUST_CHANGED' ||
  'REVISION_CONFLICT' => 'Данные сервера изменились. Получите их повторно.',
  'EXECUTOR_UNAVAILABLE' =>
    'Исполнитель не настроен или недоступен на сервере.',
  'RUNTIME_INCOMPATIBLE' ||
  'INCOMPATIBLE' => 'Версия исполнителя не соответствует приложению.',
  'FORBIDDEN' => 'Недостаточно прав для этой операции.',
  'CANCELLED' => 'Операция отменена.',
  'TIMEOUT' =>
    'Время ожидания истекло. Проверьте состояние перед повторной попыткой.',
  'CURSOR_EXPIRED' => 'Страница журнала устарела. Получите журнал заново.',
  'NOT_READY' => 'Сначала подключитесь к серверу.',
  'NOT_FOUND' => 'Запрос устарел или сервер удалён. Получите данные повторно.',
  'RESOURCE_LIMIT' ||
  'HOST_BUSY' => 'Ресурс занят. Дождитесь завершения текущей операции.',
  _ => 'Операция не выполнена. Проверьте доступность сервиса.',
};
