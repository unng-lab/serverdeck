import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:serverdeck_protocol/automation/profile_records.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';

import 'automation_controller.dart';

class AutomationPanel extends StatefulWidget {
  const AutomationPanel({super.key, required this.client, this.serverId});
  final TrustedApiClient client;
  final String? serverId;
  @override
  State<AutomationPanel> createState() => _AutomationPanelState();
}

class _AutomationPanelState extends State<AutomationPanel> {
  late AutomationController model;
  Timer? _expiry;
  String pretty(Object? value) =>
      const JsonEncoder.withIndent('  ').convert(value);
  @override
  void initState() {
    super.initState();
    _create();
  }

  void _create() {
    model = AutomationController(
      client: widget.client,
      serverId: widget.serverId,
    )..addListener(_changed);
    model.initialize().ignore();
  }

  @override
  void didUpdateWidget(covariant AutomationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.client, widget.client) ||
        oldWidget.serverId != widget.serverId) {
      _expiry?.cancel();
      model.removeListener(_changed);
      model.dispose();
      _create();
    }
  }

  void _changed() {
    _expiry?.cancel();
    if (!mounted) return;
    setState(() {});
    final expiry = DateTime.tryParse('${model.plan?['expiresAt']}');
    if (expiry != null && expiry.isAfter(DateTime.now())) {
      _expiry = Timer(
        expiry.difference(DateTime.now()) + const Duration(milliseconds: 1),
        () {
          if (mounted) setState(() {});
        },
      );
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    model.removeListener(_changed);
    model.dispose();
    super.dispose();
  }

  Map<String, Object?> parse(String source) =>
      StrictCodec().decode(utf8.encode(source), maxBytes: 256 * 1024);
  Widget jsonView(String title, Object? value) => ExpansionTile(
    title: Text(title),
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(
            pretty(value),
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      ),
    ],
  );
  Widget button(String label, VoidCallback action, {bool mutation = false}) =>
      OutlinedButton(
        onPressed:
            (mutation
                ? model.canMutate
                : !model.busy && !widget.client.isClosed)
            ? action
            : null,
        child: Text(label),
      );

  Future<void> _jsonEditor(
    String title,
    Map<String, Object?> initial,
    Future<void> Function(Map<String, Object?>) submit,
  ) async {
    final input = TextEditingController(text: pretty(initial));
    String? error;
    try {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 720,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: input,
                      minLines: 8,
                      maxLines: 18,
                      decoration: const InputDecoration(labelText: 'JSON'),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    if (error != null) Text(error!),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Закрыть'),
              ),
              FilledButton(
                onPressed: () async {
                  final Future<void> work;
                  try {
                    final value = parse(input.text);
                    work = submit(value);
                  } catch (_) {
                    update(() => error = 'Проверьте JSON и типы значений');
                    return;
                  }
                  if (dialog.mounted) Navigator.pop(dialog);
                  await work;
                },
                child: const Text('Продолжить'),
              ),
            ],
          ),
        ),
      );
    } finally {
      input.dispose();
    }
  }

  Future<void> _editProfile({AutomationProfileRecord? existing}) async {
    final controller = model;
    final name = TextEditingController(text: existing?.name ?? 'Новый профиль');
    final description = TextEditingController(
      text: existing?.description ?? '',
    );
    final body = TextEditingController(
      text: pretty(
        existing == null
            ? {
                'format': 1,
                'environment': 'ubuntu24.04-amd64-systemd',
                'parameters': <String, Object?>{},
                'steps': [
                  {
                    'id': 'motd',
                    'kind': 'config_file',
                    'resourceId': 'system.motd',
                    'values': {'text': 'Managed by ServerDeck'},
                  },
                ],
              }
            : model.revision!['body'],
      ),
    );
    String? error;
    var validating = false;
    Map<String, Object?>? draftValidation;
    try {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(
              existing == null
                  ? 'Новый Ansible-профиль'
                  : 'Новая версия профиля',
            ),
            content: SizedBox(
              width: 720,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      maxLength: 100,
                      decoration: const InputDecoration(labelText: 'Название'),
                    ),
                    TextField(
                      controller: description,
                      maxLength: 2000,
                      decoration: const InputDecoration(labelText: 'Описание'),
                    ),
                    TextField(
                      controller: body,
                      onChanged: (_) => update(() => draftValidation = null),
                      minLines: 8,
                      maxLines: 16,
                      decoration: const InputDecoration(
                        labelText: 'Шаги и параметры профиля (JSON)',
                      ),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    if (existing != null)
                      Text(
                        'Основа: версия ${model.revision!['revision']}. Текущая версия: ${existing.headRevision}.',
                      ),
                    if (existing != null)
                      const Text(
                        'Для новой версии потребуется отдельное разрешение на запуск.',
                      ),
                    if (draftValidation != null)
                      SelectableText(pretty(draftValidation)),
                    if (error != null) Text(error!),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Закрыть'),
              ),
              FilledButton(
                onPressed: validating
                    ? null
                    : () async {
                        try {
                          final parsed = parse(body.text);
                          final work = model.saveProfile(
                            name: name.text,
                            description: description.text,
                            body: parsed,
                            existing: existing,
                          );
                          Navigator.pop(dialog);
                          await work;
                        } on FormatException {
                          update(
                            () => error = 'Проверьте формат профиля и допустимые значения',
                          );
                        }
                      },
                child: const Text('Сохранить версию'),
              ),
              OutlinedButton(
                onPressed: validating || model.busy
                    ? null
                    : () async {
                        final source = body.text;
                        try {
                          final input = parse(source);
                          update(() {
                            validating = true;
                            error = null;
                            draftValidation = null;
                          });
                          await controller.validateBody(input);
                          if (!mounted ||
                              !context.mounted ||
                              !identical(controller, model) ||
                              controller.client.isClosed)
                            return;
                          update(() {
                            if (body.text == source) {
                              draftValidation = model.validation;
                              error = model.error == null
                                  ? null
                                  : message(model.error!);
                            } else {
                              error =
                                  'Черновик изменён — проверьте его ещё раз';
                            }
                          });
                        } on FormatException {
                          if (context.mounted)
                            update(() => error = 'Проверьте формат JSON');
                        } finally {
                          if (context.mounted) update(() => validating = false);
                        }
                      },
                child: Text(
                  validating ? 'Проверка…' : 'Проверить без сохранения',
                ),
              ),
            ],
          ),
        ),
      );
    } finally {
      name.dispose();
      description.dispose();
      body.dispose();
    }
  }

  Future<void> _decision(Map<String, Object?> plan, bool approve) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(
          approve ? 'Подтвердить этот план?' : 'Отклонить этот план?',
        ),
        content: SizedBox(
          width: 720,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(dialog).height * .55,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    'Сервер: ${plan['serverId']}\nПрофиль: ${plan['profileId']} · версия ${plan['profileRevision']}\nПлан: ${plan['digest']}\nДействует до: ${plan['expiresAt']}',
                  ),
                  const SizedBox(height: 12),
                  const Text('Параметры и все действия'),
                  SelectableText(
                    pretty({
                      'parameters': plan['exactParams'],
                      'effects': plan['effects'],
                      'checks': plan['checks'],
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Назад'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(approve ? 'Подтвердить план' : 'Отклонить план'),
          ),
        ],
      ),
    );
    if (result == true && mounted)
      await model.approvePlan(plan, approve: approve);
  }

  Future<void> _delegate() async {
    final controller = model, selected = model.revision;
    final body = selected?['body'] as Map<String, Object?>?;
    if (body == null || selected == null) return;
    await controller.refreshGrants();
    if (!mounted || !identical(controller, model)) return;
    final eligible = controller.grants
        .where(
          (row) =>
              grantCurrent(row) &&
              (row['scopes'] as List).contains('apply') &&
              (row['scopes'] as List).contains('plan') &&
              (row['serverIds'] as List).contains(widget.serverId),
        )
        .toList();
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Выдайте клиенту ИИ права plan и apply на этот сервер в разделе доступа.',
          ),
        ),
      );
      return;
    }
    final grant = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Кому делегировать профиль?'),
        children: [
          for (final row in eligible)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, row),
              child: Text('${row['label']} · до ${row['expiresAt']}'),
            ),
        ],
      ),
    );
    if (grant == null || !mounted || !identical(controller, model)) return;
    final definitions = body['parameters'] as Map<String, Object?>;
    final predicates = <String, Object?>{};
    for (final row in definitions.entries) {
      final value = (row.value as Map<String, Object?>)['default'];
      predicates[row.key] = value is int
          ? {'type': 'integer', 'minimum': value, 'maximum': value}
          : {
              'type': 'enum',
              'values': [value],
            };
    }
    await _jsonEditor(
      'Делегирование «${grant['label']}» · версия ${selected['revision']}\n${selected['profileId']}\n${selected['digest']}',
      {'lifetimeSeconds': 3600, 'predicates': predicates},
      (value) => controller.createDelegation(
        displayedRevision: selected,
        grantId: grant['id'] as String,
        lifetimeSeconds: value['lifetimeSeconds'] as int,
        predicates: value['predicates'] as Map<String, Object?>,
      ),
    );
  }

  bool grantCurrent(Map<String, Object?> row) {
    final now = DateTime.now().toUtc();
    return row['revokedAt'] == null &&
        !DateTime.parse(row['issuedAt'] as String).isAfter(now) &&
        DateTime.parse(row['expiresAt'] as String).isAfter(now);
  }

  Future<void> _grantEditor({Map<String, Object?>? existing}) => _jsonEditor(
    existing == null
        ? 'Выдать ИИ доступ через MCP'
        : 'Изменить права и перевыпустить доступ',
    {
      'label': existing?['label'] ?? 'ИИ-клиент',
      'scopes':
          existing?['scopes'] ??
          (widget.serverId == null
              ? ['author']
              : ['read', 'logs', 'author', 'plan']),
      'serverIds':
          existing?['serverIds'] ??
          (widget.serverId == null ? <String>[] : [widget.serverId]),
      'lifetimeSeconds': existing == null
          ? 28800
          : DateTime.parse(existing['expiresAt'] as String)
                .difference(DateTime.parse(existing['issuedAt'] as String))
                .inSeconds,
    },
    (value) => model.saveGrant(value, existing: existing),
  );

  Widget grantManagement() => ExpansionTile(
    title: const Text('Доступ ИИ рабочего пространства'),
    children: [
      Wrap(
        spacing: 8,
        children: [
          button('Обновить клиентов', () => model.refreshGrants().ignore()),
          button(
            'Подключить ИИ',
            () => _grantEditor().ignore(),
            mutation: true,
          ),
        ],
      ),
      if (model.grantsLoaded && model.grants.isEmpty)
        const Text('Клиентов ИИ пока нет'),
      for (final row in model.grants)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: Text(
                '${row['label']}${row['revokedAt'] != null
                    ? ' · отозвано'
                    : !grantCurrent(row)
                    ? ' · срок истёк'
                    : ''}',
              ),
              subtitle: Text(
                'Права: ${(row['scopes'] as List).join(', ')}\nДействует до: ${row['expiresAt']}',
              ),
            ),
            jsonView('Серверы и выданные права', row),
            Wrap(
              spacing: 8,
              children: [
                if (grantCurrent(row))
                  button(
                    'Конфигурация MCP',
                    () => model
                        .configurationForGrant(row['id'] as String)
                        .ignore(),
                  ),
                if (row['revokedAt'] == null) ...[
                  button(
                    'Изменить права',
                    () => _grantEditor(existing: row).ignore(),
                    mutation: true,
                  ),
                  button('Отозвать доступ', () async {
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (dialog) => AlertDialog(
                        title: Text('Отозвать доступ «${row['label']}»?'),
                        content: const Text(
                          'Текущий шаг задания может завершиться. Следующие шаги потребуют действующих прав.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialog, false),
                            child: const Text('Назад'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dialog, true),
                            child: const Text('Отозвать доступ'),
                          ),
                        ],
                      ),
                    );
                    if (yes == true && mounted) await model.revokeGrant(row);
                  }, mutation: true),
                ],
              ],
            ),
          ],
        ),
      if (model.launchConfiguration != null) ...[
        jsonView('Команда и аргументы MCP', model.launchConfiguration),
        button(
          'Скопировать конфигурацию',
          () => Clipboard.setData(
            ClipboardData(text: pretty(model.launchConfiguration)),
          ).ignore(),
        ),
      ],
    ],
  );

  String message(String code) => switch (code) {
    'TRUST_REQUIRED' => 'Сначала подтвердите SSH-ключ сервера.',
    'EXECUTOR_UNAVAILABLE' => 'Executor сервера недоступен.',
    'APPROVAL_REQUIRED' => 'Для запуска подтвердите этот план.',
    'PLAN_STALE' => 'Состояние сервера изменилось. Создайте новый план.',
    'PLAN_EXPIRED' => 'Срок плана истёк. Создайте новый план.',
    'REVISION_CONFLICT' => 'Профиль изменился. Загрузите его заново.',
    'FORBIDDEN' => 'Недостаточно прав для операции.',
    'CANCELLED' => 'Ожидание результата остановлено.',
    'TIMEOUT' => 'Ответ не получен вовремя.',
    _ => 'Не удалось выполнить запрос: $code',
  };

  @override
  Widget build(BuildContext context) {
    final selected = model.profile,
        revision = model.revision,
        plan = model.plan,
        job = model.job;
    final deadline = DateTime.tryParse('${plan?['expiresAt']}');
    final runnable =
        plan?['status'] == 'runnable' &&
        deadline != null &&
        deadline.isAfter(DateTime.now());
    return Card(
      child: ExpansionTile(
        title: Text(
          widget.serverId == null
              ? 'ИИ-доступ и Ansible-профили'
              : 'Автоматизация',
        ),
        childrenPadding: const EdgeInsets.all(12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (model.busy) const LinearProgressIndicator(),
          if (model.error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Semantics(
                liveRegion: true,
                child: Text(message(model.error!)),
              ),
            ),
          if (model.pendingLabel != null && !model.busy)
            Wrap(
              spacing: 8,
              children: [
                Text('Запрос: ${model.pendingLabel}'),
                OutlinedButton(
                  onPressed: model.canRetry
                      ? () => model.retryPending().ignore()
                      : null,
                  child: const Text('Повторить тот же запрос'),
                ),
                TextButton(
                  onPressed: model.dismissPending,
                  child: const Text('Закрыть запрос'),
                ),
              ],
            ),
          if (model.busy)
            TextButton(
              onPressed: () => model.cancelInterest().ignore(),
              child: const Text('Перестать ждать ответ'),
            ),
          Wrap(
            spacing: 8,
            children: [
              button(
                'Обновить профили',
                () => model.refreshProfiles().ignore(),
              ),
              button(
                'Новый профиль',
                () => _editProfile().ignore(),
                mutation: true,
              ),
              if (widget.serverId != null)
                button('Рецепты установки', () => model.loadRecipes().ignore()),
            ],
          ),
          if (model.profilesLoaded && model.profiles.isEmpty)
            const Text('Ansible-профилей пока нет'),
          grantManagement(),
          for (final row in model.profiles)
            ListTile(
              title: Text(row.name),
              subtitle: Text(
                'Версия ${row.headRevision}${row.archived ? ' · архив' : ''}',
              ),
              selected: selected?.id == row.id,
              enabled: !model.busy,
              onTap: () => model.selectProfile(row.id).ignore(),
            ),
          if (model.profilesCursor != null)
            button(
              'Ещё профили',
              () => model.refreshProfiles(more: true).ignore(),
            ),
          if (selected != null && revision != null) ...[
            Text(
              '${selected.name} · версия ${revision['revision']}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SelectableText(
              'Профиль: ${selected.id}\nХеш: ${revision['digest']}',
            ),
            jsonView('Шаги и параметры', revision['body']),
            if (model.validation != null)
              jsonView('Результат проверки содержимого', model.validation),
            if (model.comparison != null)
              jsonView('Сравнение выбранных версий', model.comparison),
            Wrap(
              spacing: 8,
              children: [
                button(
                  'Выбрать версию',
                  () => _jsonEditor(
                    'Версия профиля',
                    {'revision': revision['revision']},
                    (value) => model.selectProfile(
                      selected.id,
                      version: value['revision'] as int,
                    ),
                  ).ignore(),
                ),
                button(
                  'Проверить версию',
                  () => model
                      .validateBody(revision['body'] as Map<String, Object?>)
                      .ignore(),
                ),
                button(
                  'Сравнить версии',
                  () => _jsonEditor('Сравнение шагов двух версий', {
                    'fromRevision': (revision['revision'] as int) > 1
                        ? (revision['revision'] as int) - 1
                        : 1,
                    'toRevision': revision['revision'],
                  }, model.compareVersions).ignore(),
                ),
                if (!selected.archived) ...[
                  button(
                    'Изменить профиль',
                    () => _editProfile(existing: selected).ignore(),
                    mutation: true,
                  ),
                  if (widget.serverId != null)
                    button('Создать план', () {
                      final parameters =
                          (revision['body']
                                  as Map<String, Object?>)['parameters']
                              as Map<String, Object?>;
                      _jsonEditor('Параметры плана', {
                        for (final row in parameters.entries)
                          row.key:
                              (row.value as Map<String, Object?>)['default'],
                      }, model.createPlan).ignore();
                    }, mutation: true),
                  if (widget.serverId != null)
                    button(
                      'Делегировать версию',
                      () => _delegate().ignore(),
                      mutation: true,
                    ),
                  button('Архивировать', () async {
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (dialog) => AlertDialog(
                        title: Text('Архивировать «${selected.name}»?'),
                        content: const Text(
                          'История версий и заданий сохранится.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialog, false),
                            child: const Text('Назад'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dialog, true),
                            child: const Text('Архивировать'),
                          ),
                        ],
                      ),
                    );
                    if (yes == true && mounted)
                      await model.archiveProfile(selected);
                  }, mutation: true),
                ],
              ],
            ),
          ],
          if (model.catalog != null)
            jsonView('Каталог рецептов и доступность установки', model.catalog),
          if (plan != null) ...[
            const Divider(),
            Text(
              'План · ${plan['status']}${deadline != null && !deadline.isAfter(DateTime.now()) ? ' · срок истёк' : ''}',
            ),
            SelectableText(
              'Версия профиля: ${plan['profileRevision']}\nХеш плана: ${plan['digest']}\nДействует до: ${plan['expiresAt']}',
            ),
            jsonView('Параметры, действия и проверки', {
              'parameters': plan['exactParams'],
              'effects': plan['effects'],
              'checks': plan['checks'],
              'reasons': plan['reasons'],
            }),
            Wrap(
              spacing: 8,
              children: [
                if (runnable) ...[
                  button(
                    'Подтвердить план',
                    () => _decision(plan, true).ignore(),
                    mutation: true,
                  ),
                  button(
                    'Отклонить план',
                    () => _decision(plan, false).ignore(),
                    mutation: true,
                  ),
                  button(
                    'Запустить',
                    () => model.applyPlan(plan).ignore(),
                    mutation: true,
                  ),
                ],
                button(
                  'Обновить план',
                  () => model.loadPlan(plan['id'] as String).ignore(),
                ),
              ],
            ),
          ],
          if (widget.serverId != null) ...[
            const Divider(),
            Wrap(
              spacing: 8,
              children: [
                button('Обновить задания', () => model.refreshJobs().ignore()),
                button(
                  'Обновить разрешения',
                  () => model.refreshAuthorities().ignore(),
                ),
              ],
            ),
            if (model.jobsLoaded && model.jobs.isEmpty)
              const Text('Заданий на этом сервере пока нет'),
            for (final row in model.jobs)
              Builder(
                builder: (context) {
                  final entry = row['job'] as Map<String, Object?>;
                  return ListTile(
                    title: Text('Задание · ${entry['state']}'),
                    subtitle: Text('${entry['id']}'),
                    enabled: !model.busy,
                    selected: job?['id'] == entry['id'],
                    onTap: () =>
                        model.selectJob(entry['id'] as String).ignore(),
                  );
                },
              ),
            if (model.jobsCursor != null)
              button(
                'Ещё задания',
                () => model.refreshJobs(more: true).ignore(),
              ),
            if (job != null) ...[
              Text('Состояние: ${job['state']}'),
              Wrap(
                spacing: 8,
                children: [
                  button(
                    'План задания',
                    () => model
                        .loadPlan(job['immutablePlanId'] as String)
                        .ignore(),
                  ),
                  if (!AutomationController.terminal.contains(job['state']) &&
                      job['cancelRequested'] != true)
                    button(
                      'Остановить после текущего шага',
                      () => model
                          .jobAction(job['id'] as String, reconcile: false)
                          .ignore(),
                      mutation: true,
                    ),
                  if (job['state'] == 'unknown')
                    button(
                      'Уточнить результат',
                      () => model
                          .jobAction(job['id'] as String, reconcile: true)
                          .ignore(),
                      mutation: true,
                    ),
                ],
              ),
              jsonView('Результат и проверки задания', job),
              jsonView(
                'Последние 200 полученных событий · пропущено в источнике: ${model.droppedEvents}',
                model.events,
              ),
            ],
            ExpansionTile(
              title: const Text('Запросы подтверждения этого сервера'),
              children: [
                if (model.authoritiesLoaded && model.approvals.isEmpty)
                  const Text('Запросов пока нет'),
                for (final row in model.approvals)
                  ListTile(
                    title: Text('${row['state']} · до ${row['expiresAt']}'),
                    subtitle: Text('План ${row['planId']}'),
                    enabled: !model.busy,
                    onTap: () =>
                        model.loadPlan(row['planId'] as String).ignore(),
                  ),
                if (model.approvalsNext != null)
                  button(
                    'Ещё запросы',
                    () => model.moreAuthorities(approvals: true).ignore(),
                  ),
              ],
            ),
            ExpansionTile(
              title: const Text('Делегированные версии'),
              children: [
                if (model.authoritiesLoaded && model.delegations.isEmpty)
                  const Text('Делегирований пока нет'),
                for (final row in model.delegations)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      jsonView(
                        'ИИ ${row['grantId']} · до ${row['expiresAt']}${row['revokedAt'] != null ? ' · отозвано' : ''}',
                        row,
                      ),
                      if (row['revokedAt'] == null)
                        button(
                          'Отозвать делегирование',
                          () => model.revokeDelegation(row).ignore(),
                          mutation: true,
                        ),
                    ],
                  ),
                if (model.delegationsNext != null)
                  button(
                    'Ещё делегирования',
                    () => model.moreAuthorities(approvals: false).ignore(),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
