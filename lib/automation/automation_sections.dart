import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:serverdeck_protocol/automation/profile_records.dart';
import 'package:serverdeck_protocol/models.dart';

import '../theme/brand_theme.dart';
import '../theme/brand_tokens.dart';
import '../ui/deck_components.dart';
import 'automation_presentation.dart';

/// Availability is calculated by the owner, including its pending request and
/// client lifetime. Presentation never decides whether an effect is admitted.
class AutomationActionAvailability {
  const AutomationActionAvailability({
    required this.read,
    required this.mutate,
    required this.select,
  });

  final bool read, mutate, select;
}

/// Existing grant metadata with freshness calculated by the owning panel.
class AutomationGrantPresentation {
  const AutomationGrantPresentation({
    required this.value,
    required this.current,
  });

  final Map<String, Object?> value;
  final bool current;
}

/// Display metadata only. IDs still come from the operation being reviewed.
/// A different selection must never stand in for a missing target.
class AutomationServerTargets extends StatelessWidget {
  const AutomationServerTargets({
    super.key,
    required this.serverIds,
    this.serverProfiles = const [],
    this.expectedIdentities = const {},
  });

  final List<String> serverIds;
  final List<ProfileView> serverProfiles;
  final Map<String, Map<String, Object?>> expectedIdentities;

  static ProfileView? resolve(
    String id,
    List<ProfileView> profiles, {
    Map<String, Object?> expectedIdentity = const {},
  }) {
    final matches = profiles.where((row) => row.id == id).toList();
    if (matches.length != 1) return null;
    final row = matches.single;
    final identity = {
      'serverRevision': row.revision,
      'connectionRevision': row.connectionRevision,
      // Existing plans use the wire name accessRevision for credentials.
      'accessRevision': row.credentialRevision,
      'trustRevision': row.trustRevision,
    };
    return expectedIdentity.entries.every(
          (entry) => identity[entry.key] == entry.value,
        )
        ? row
        : null;
  }

  static String address(ProfileView row) => row.address.contains(':')
      ? '[${row.address}]:${row.port}'
      : '${row.address}:${row.port}';

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (serverIds.isEmpty) const Text('Без доступа к серверам'),
      for (final id in serverIds)
        Builder(
          builder: (context) {
            final row = resolve(
              id,
              serverProfiles,
              expectedIdentity: expectedIdentities[id] ?? const {},
            );
            return row == null
                ? const DeckNotice(
                    message: 'Название и адрес целевого сервера недоступны',
                    nextStep: 'Обновите локальные профили и проверьте цель. Идентификатор доступен в технических деталях.',
                    tone: DeckTone.warning,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DeckKeyValue(label: 'Сервер', value: row.name),
                      DeckKeyValue(
                        label: 'Адрес',
                        value: address(row),
                        selectable: true,
                      ),
                    ],
                  );
          },
        ),
      if (serverIds.isNotEmpty)
        AutomationJsonView(
          title: 'Идентификаторы целевых серверов',
          value: {'serverIds': serverIds},
        ),
    ],
  );
}

List<String> _targetIds(Object? value) =>
    value is List ? value.whereType<String>().toList() : const [];

String _targetStamp(String id, List<ProfileView> profiles) => _pretty(
  profiles.where((row) => row.id == id).map((row) => row.toJson()).toList(),
);

bool automationTargetsUnchanged(
  List<String> ids,
  List<ProfileView> captured,
  List<ProfileView> current,
) => ids.every((id) => _targetStamp(id, captured) == _targetStamp(id, current));

/// One open presentation review cannot regain consent after its context changed.
/// Owners call this synchronously when observing context, before deferred paint.
bool Function() automationReviewGuard(bool Function() matches) {
  var retired = false;
  return () {
    retired = retired || !matches();
    return !retired;
  };
}

Map<String, Object?> _planIdentity(Map<String, Object?> plan) => {
  for (final field in [
    'serverRevision',
    'connectionRevision',
    'accessRevision',
    'trustRevision',
  ])
    field: plan[field],
};

bool automationPlanTargetAvailable(
  Map<String, Object?> plan,
  List<ProfileView> profiles,
) =>
    plan['serverId'] is String &&
    AutomationServerTargets.resolve(
          plan['serverId'] as String,
          profiles,
          expectedIdentity: _planIdentity(plan),
        ) !=
        null;

bool automationTargetsAvailable(List<String> ids, List<ProfileView> profiles) =>
    ids.every((id) => AutomationServerTargets.resolve(id, profiles) != null);

AutomationProfileRecord? _matchingProfile(
  Map<String, Object?> plan,
  AutomationProfileRecord? profile,
) =>
    profile?.id == plan['profileId'] &&
        profile?.workspaceId == plan['workspaceId']
    ? profile
    : null;

const _changedTargetMessage =
    'Контекст цели изменился. Закройте окно и заново проверьте действие.';

String _pretty(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);

Map<String, Object?> _object(Object? value) =>
    value is Map<String, Object?> ? value : const {};
List<Map<String, Object?>> _rows(Object? value) =>
    value is List ? value.whereType<Map<String, Object?>>().toList() : const [];
String _value(Object? value) => switch (value) {
  null => 'Не предоставлено',
  true => 'Да',
  false => 'Нет',
  List() => value.map(_value).join(', '),
  Map() when value.length == 1 && value.containsKey('param') =>
    'Параметр «${value['param']}»',
  Map() =>
    value.entries
        .map((entry) => '${entry.key}: ${_value(entry.value)}')
        .join('; '),
  _ => '$value',
};
String _time(Object? value) =>
    value == null ? 'Не предоставлено' : '$value (UTC)';
String _scope(Object? value) => switch (value) {
  'read' => 'Чтение состояния',
  'logs' => 'Чтение журналов',
  'author' => 'Создание и изменение профилей',
  'plan' => 'Создание планов',
  'apply' => 'Запуск заданий',
  _ => _value(value),
};
String _resource(Object? value) => switch (value) {
  'system.motd' => 'Приветствие сервера',
  'postgresql.settings' => 'Настройки PostgreSQL',
  'postgresql.service' => 'Служба PostgreSQL',
  'clickhouse.settings' => 'Настройки ClickHouse',
  'clickhouse.service' => 'Служба ClickHouse',
  'recipe.postgresql16' => 'Установка PostgreSQL 16',
  'recipe.clickhouse' => 'Установка ClickHouse',
  _ => _value(value),
};
String _field(String value) => switch (value) {
  'text' => 'Текст',
  'max_connections' => 'Максимум подключений',
  'shared_buffers_mb' => 'Общие буферы, МиБ',
  'max_server_memory_usage_mb' => 'Максимум памяти сервера, МиБ',
  _ => value,
};
String _check(Object? value) => switch (value) {
  'file_digest' => 'Проверить содержимое файла',
  'settings' => 'Проверить значения настроек',
  'service_state' => 'Проверить состояние службы',
  'service_enabled' => 'Проверить автозапуск службы',
  'service_restarted' => 'Подтвердить перезапуск службы',
  'sql' || 'local_sql' => 'Проверить локальный SQL-запрос',
  'recipe' => 'Проверить точный рецепт установки',
  'fresh_install' => 'Проверить отсутствие существующей установки и данных',
  'packages_qualified' => 'Проверить совместимость точных пакетов',
  'packages_exact' => 'Проверить точные версии пакетов',
  _ => _value(value),
};
String _code(Object? code) => switch (code) {
  'TRUST_REQUIRED' => 'Подтвердите SSH-ключ сервера в разделе «Серверы».',
  'TRUST_CHANGED' =>
    'Доверие серверу изменилось. Проверьте SSH-ключ и создайте новый план.',
  'EXECUTOR_UNAVAILABLE' =>
    'Executor сервера недоступен. Проверьте его привязку в разделе «Серверы».',
  'RUNTIME_INCOMPATIBLE' => 'Среда исполнения несовместима с этим планом.',
  'QUALIFICATION_REQUIRED' =>
    'Администратор должен подготовить точный совместимый рецепт.',
  'PLAN_STALE' => 'Состояние сервера изменилось. Создайте новый план.',
  'PLAN_EXPIRED' => 'Срок плана истёк. Создайте новый план.',
  'FORBIDDEN' => 'Недостаточно прав. Проверьте выданный доступ.',
  'UNKNOWN_OUTCOME' => 'Исход не подтверждён. Уточните результат задания.',
  'APPROVAL_REQUIRED' => 'Для запуска подтвердите этот точный план.',
  'CANCELLED' => 'Операция отменена.',
  'CHECK_FAILED' =>
    'Проверка не пройдена. Изучите результат и проверки задания.',
  'UNSUPPORTED' => 'Операция не поддерживается в текущем окружении.',
  _ => 'Причина: ${_value(code)}',
};
String _jobState(Object? state) => switch (state) {
  'queued' => 'В очереди',
  'running' => 'Выполняется',
  'cancel-requested' => 'Запрошена остановка после текущего шага',
  'succeeded' => 'Задание выполнено',
  'failed' => 'Задание завершилось ошибкой',
  'cancelled' => 'Задание остановлено',
  'cancelled-partial' => 'Задание остановлено с частичными изменениями',
  'unknown' => 'Исход не подтверждён',
  'reconciling' => 'Уточнение результата',
  _ => _value(state),
};
DeckTone _jobTone(Object? state) => switch (state) {
  'queued' || 'running' || 'reconciling' => DeckTone.running,
  'succeeded' => DeckTone.success,
  'failed' => DeckTone.error,
  'unknown' => DeckTone.unknown,
  'cancel-requested' || 'cancelled' || 'cancelled-partial' => DeckTone.warning,
  _ => DeckTone.neutral,
};
String _result(Object? result) => switch (result) {
  'passed' => 'Проверка пройдена',
  'failed' => 'Проверка не пройдена',
  'unknown' => 'Результат проверки неизвестен',
  'unsupported' => 'Проверка не поддерживается',
  'denied' => 'Недостаточно прав для проверки',
  'timeout' => 'Истекло время проверки',
  _ => _value(result),
};

class _Section extends StatelessWidget {
  const _Section({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: BrandSpacing.space8),
    child: child,
  );
}

class _Values extends StatelessWidget {
  const _Values(this.values);
  final Map<String, Object?> values;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (values.isEmpty) const Text('Параметров нет'),
      for (final entry in values.entries)
        DeckKeyValue(
          label: _field(entry.key),
          value: _value(entry.value),
          selectable: true,
        ),
    ],
  );
}

class _Program extends StatelessWidget {
  const _Program({
    required this.effects,
    required this.checks,
    this.showChecks = true,
    this.recipes = const [],
  });
  final List<Map<String, Object?>> effects, checks;
  final List<Map<String, Object?>> recipes;
  final bool showChecks;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const DeckSectionHeader(title: 'Действия'),
      if (effects.isEmpty) const Text('Действия не запланированы'),
      for (final effect in effects) ...[
        const SizedBox(height: BrandSpacing.space8),
        if (effect['kind'] == 'install_recipe')
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text:
                      'Установить ${switch (recipes.where((recipe) => recipe['digest'] == effect['recipeDigest']).firstOrNull?['id']) {
                        'postgresql16' => 'PostgreSQL 16',
                        'clickhouse' => 'ClickHouse',
                        _ => 'ПО по точному рецепту',
                      }} · версия ',
                ),
                TextSpan(
                  text: _value(effect['version']),
                  style: BrandTypography.log,
                ),
              ],
            ),
          )
        else
          Text(switch (effect['kind']) {
            'config_file' =>
              'Изменить конфигурацию: ${_resource(effect['resourceId'])}',
            'service' || 'service_state' =>
              'Изменить состояние: ${_resource(effect['resourceId'])}',
            'service_enabled' =>
              'Изменить автозапуск: ${_resource(effect['resourceId'])}',
            _ =>
              '${_value(effect['kind'])}: ${_resource(effect['resourceId'])}',
          }),
        if (effect['values'] is Map) _Values(_object(effect['values'])),
        if (effect['state'] != null)
          DeckKeyValue(
            label: 'Требуемое состояние',
            value: _value(effect['state']),
          ),
        if (effect['enabled'] != null)
          DeckKeyValue(label: 'Автозапуск', value: _value(effect['enabled'])),
      ],
      if (showChecks) ...[
        const SizedBox(height: BrandSpacing.space16),
        const DeckSectionHeader(title: 'Проверки после действий'),
        if (checks.isEmpty) const Text('Проверки не запланированы'),
        for (final check in checks)
          DeckKeyValue(
            label: _check(check['kind']),
            value: _resource(check['resourceId']),
          ),
      ],
    ],
  );
}

class _PlanSummary extends StatelessWidget {
  const _PlanSummary(
    this.plan, {
    this.serverProfiles = const [],
    this.automationProfile,
  });
  final Map<String, Object?> plan;
  final List<ProfileView> serverProfiles;
  final AutomationProfileRecord? automationProfile;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AutomationServerTargets(
        serverIds: [if (plan['serverId'] is String) plan['serverId'] as String],
        serverProfiles: serverProfiles,
        expectedIdentities: {
          if (plan['serverId'] is String)
            plan['serverId'] as String: _planIdentity(plan),
        },
      ),
      DeckKeyValue(
        label: 'Ansible-профиль',
        value:
            _matchingProfile(plan, automationProfile)?.name ??
            'Название профиля недоступно',
      ),
      DeckKeyValue(
        label: 'Версия профиля',
        value: _value(plan['profileRevision']),
      ),
      DeckKeyValue(
        label: 'Хеш версии профиля',
        value: _value(plan['profileDigest']),
        selectable: true,
      ),
      DeckKeyValue(label: 'Действует до', value: _time(plan['expiresAt'])),
      const SizedBox(height: BrandSpacing.space12),
      const DeckSectionHeader(title: 'Точные параметры'),
      _Values(_object(plan['exactParams'])),
      const SizedBox(height: BrandSpacing.space16),
      _Program(
        effects: _rows(plan['effects']),
        checks: _rows(plan['checks']),
        recipes: _rows(_object(plan['preflight'])['recipes']),
      ),
    ],
  );
}

class _Validation extends StatelessWidget {
  const _Validation(this.value);
  final Map<String, Object?> value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DeckStatus(
        label: value['valid'] == true
            ? 'Содержимое профиля проверено'
            : 'Исправьте содержимое профиля',
        tone: value['valid'] == true ? DeckTone.success : DeckTone.error,
      ),
      for (final issue in _rows(value['issues']))
        Text(
          '${_value(issue['field'])}: проверьте формат и допустимые значения (${_value(issue['code'])})',
        ),
      AutomationJsonView(title: 'Результат проверки содержимого', value: value),
    ],
  );
}

class _EditorPreview extends StatelessWidget {
  const _EditorPreview(this.value, {this.serverProfiles = const []});
  final Map<String, Object?> value;
  final List<ProfileView> serverProfiles;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (value['label'] != null)
        DeckKeyValue(label: 'Клиент ИИ', value: _value(value['label'])),
      if (value['scopes'] is List)
        DeckKeyValue(
          label: 'Выдаваемые права',
          value: (value['scopes'] as List).map(_scope).join(', '),
        ),
      if (value['serverIds'] is List)
        AutomationServerTargets(
          serverIds: _targetIds(value['serverIds']),
          serverProfiles: serverProfiles,
        ),
      if (value['lifetimeSeconds'] != null)
        DeckKeyValue(
          label: 'Срок после выдачи',
          value: '${_value(value['lifetimeSeconds'])} секунд',
        ),
      if (value['predicates'] is Map)
        _ParameterConstraints(_object(value['predicates'])),
      if (!value.containsKey('scopes') && !value.containsKey('predicates'))
        _Values(value),
    ],
  );
}

class _ParameterConstraints extends StatelessWidget {
  const _ParameterConstraints(this.values, {this.definitions = false});
  final Map<String, Object?> values;
  final bool definitions;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (values.isEmpty)
        Text(
          definitions ? 'Параметров нет' : 'Ограничения параметров не заданы',
        ),
      for (final entry in values.entries)
        Builder(
          builder: (context) {
            final row = _object(entry.value);
            return DeckKeyValue(
              label: entry.key,
              value:
                  '${switch (row['type']) {
                    'integer' => 'Целое число от ${_value(row['minimum'])} до ${_value(row['maximum'])}',
                    'enum' => 'Одно из значений: ${_value(row['values'])}',
                    'boolean' => 'Да или нет',
                    'string' => 'Текст до ${_value(row['maxLength'])} символов',
                    _ => _value(entry.value),
                  }}${definitions ? '. По умолчанию: ${_value(row['default'])}' : ''}',
              selectable: true,
            );
          },
        ),
    ],
  );
}

class AutomationJsonView extends StatelessWidget {
  const AutomationJsonView({
    super.key,
    required this.title,
    required this.value,
  });

  final String title;
  final Object? value;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: DeckFocusLabel(child: Text(title)),
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.all(BrandSpacing.space12),
    expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
    children: [SelectableText(_pretty(value), style: BrandTypography.log)],
  );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton(this.label, this.onPressed);

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) =>
      OutlinedButton(onPressed: onPressed, child: Text(label));
}

class AutomationStatusSection extends StatelessWidget {
  const AutomationStatusSection({
    super.key,
    required this.busy,
    required this.openingRecipes,
    required this.canRetry,
    required this.onRetry,
    required this.onDismiss,
    required this.onStopWaiting,
    this.recipeConnectionError,
    this.error,
    this.pendingLabel,
    this.errorCode,
    this.operationLabel,
    this.writeOutcome,
  });

  final bool busy, openingRecipes, canRetry;
  final String? recipeConnectionError, error, pendingLabel;
  final String? errorCode, operationLabel;
  final AutomationWriteOutcome? writeOutcome;
  final VoidCallback onRetry, onDismiss, onStopWaiting;

  Widget _failureNotice({
    String? code,
    String? message,
    AutomationWriteOutcome? write,
    bool read = false,
  }) => _Section(
    child: DeckNotice(
      title: write?.unconfirmed == true
          ? 'Исход записи не подтверждён'
          : write != null
          ? 'Результат сохранённого запроса'
          : read
          ? 'Ошибка чтения'
          : null,
      message: code == null ? message! : automationMessage(code),
      nextStep: write?.unconfirmed == true
          ? 'Потерянный ответ не доказывает отсутствие изменений. Используйте только предусмотренные действия сохранённого запроса.'
          : null,
      tone: write?.unconfirmed == true
          ? DeckTone.unknown
          : const {
              'FORBIDDEN',
              'UNSUPPORTED',
              'VALIDATION',
              'REVISION_CONFLICT',
              'PLAN_STALE',
              'PLAN_EXPIRED',
            }.contains(code)
          ? DeckTone.warning
          : const {
              'SERVICE_UNAVAILABLE',
              'TIMEOUT',
              'DISCONNECTED',
              'CONNECTION_FAILED',
            }.contains(code)
          ? DeckTone.unavailable
          : DeckTone.error,
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (busy || openingRecipes)
        _Section(
          child: DeckStatus(
            label: openingRecipes
                ? 'Подключение и загрузка рецептов'
                : operationLabel ?? pendingLabel ?? 'Выполнение запроса',
            pending: true,
          ),
        ),
      if (recipeConnectionError != null)
        _Section(
          child: DeckNotice(
            message: recipeConnectionError!,
            tone: DeckTone.error,
          ),
        ),
      if (writeOutcome?.errorCode != null)
        _failureNotice(code: writeOutcome!.errorCode, write: writeOutcome),
      if (error != null || errorCode != null)
        _failureNotice(
          code: errorCode,
          message: error,
          read: writeOutcome != null,
        ),
      if (pendingLabel != null)
        _Section(
          child: DeckNotice(
            title: 'Сохранённый запрос',
            message: 'Запрос: $pendingLabel',
            nextStep: 'Повтор использует тот же запрос. Закрытие убирает его из интерфейса и не отменяет уже выполненные действия.',
            tone: DeckTone.warning,
            actions: [
              if (!busy) ...[
                _ActionButton(
                  'Повторить тот же запрос',
                  canRetry ? onRetry : null,
                ),
                TextButton(
                  onPressed: onDismiss,
                  child: const Text('Закрыть запрос'),
                ),
              ],
            ],
          ),
        ),
      if (busy) ...[
        const Text(
          'Остановка ожидания ответа не означает остановку задания на сервере.',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onStopWaiting,
            child: const Text('Перестать ждать ответ'),
          ),
        ),
      ],
    ],
  );
}

class AutomationProfileActions extends StatelessWidget {
  const AutomationProfileActions({
    super.key,
    required this.actions,
    required this.hasServer,
    required this.installationCatalog,
    required this.onRefresh,
    required this.onCreate,
    required this.onLoadRecipes,
  });

  final AutomationActionAvailability actions;
  final bool hasServer, installationCatalog;
  final VoidCallback onRefresh, onCreate, onLoadRecipes;

  @override
  Widget build(BuildContext context) => _Section(
    child: DeckActions(
      children: [
        _ActionButton('Обновить профили', actions.read ? onRefresh : null),
        _ActionButton('Новый профиль', actions.mutate ? onCreate : null),
        if (hasServer)
          _ActionButton(
            installationCatalog
                ? 'Подключиться и открыть рецепты'
                : 'Рецепты установки',
            actions.read ? onLoadRecipes : null,
          ),
      ],
    ),
  );
}

class AutomationRecipesSection extends StatelessWidget {
  const AutomationRecipesSection({
    super.key,
    required this.catalog,
    required this.canMutate,
    required this.onCreatePlan,
  });

  final Map<String, Object?> catalog;
  final bool canMutate;
  final ValueChanged<String> onCreatePlan;

  @override
  Widget build(BuildContext context) => _Section(
    child: DeckFormSection(
      title: 'Каталог установки',
      description: 'Точный рецепт сначала создаёт план. Установка запускается отдельным действием после проверки и согласия.',
      children: [
        const DeckNotice(
          title: 'Только чистая установка',
          message: 'Существующие данные и конфигурация блокируют установку; очистка не выполняется.',
        ),
        if (catalog['installEnabled'] != true)
          const DeckNotice(
            title: 'Установка недоступна',
            message: 'Администратор должен подготовить совместимый executor и точные рецепты.',
            tone: DeckTone.unavailable,
          ),
        for (final row in _rows(catalog['recipes']))
          DeckSurface(
            child: DeckFormSection(
              title: row['id'] == 'postgresql16'
                  ? 'PostgreSQL 16'
                  : 'ClickHouse',
              trailing: Text('${row['version']}', style: BrandTypography.log),
              children: [
                DeckKeyValue(
                  label: 'Окружение',
                  value: row['environment'] == 'ubuntu24.04-amd64-systemd'
                      ? 'Ubuntu 24.04 · amd64 · systemd'
                      : _value(row['environment']),
                ),
                if (row['initialSettings'] is Map)
                  DeckFormSection(
                    title: 'Начальные настройки',
                    children: [_Values(_object(row['initialSettings']))],
                  ),
                DeckFormSection(
                  title: 'Проверки перед установкой',
                  children: [
                    for (final check in row['prechecks'] as List)
                      Text(_check(check)),
                  ],
                ),
                DeckFormSection(
                  title: 'Лицензии',
                  children: [
                    for (final notice in row['licenseNotices'] as List)
                      Text(_value(notice)),
                  ],
                ),
                AutomationJsonView(
                  title: 'Точный рецепт, параметры и условия',
                  value: row,
                ),
                if (catalog['installEnabled'] == true)
                  DeckActions(
                    children: [
                      _ActionButton(
                        'План установки ${row['id'] == 'postgresql16' ? 'PostgreSQL 16' : 'ClickHouse'}',
                        canMutate
                            ? () => onCreatePlan(row['digest'] as String)
                            : null,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        for (final row in _rows(catalog['unavailable']))
          DeckNotice(
            title:
                '${row['id'] == 'postgresql16' ? 'PostgreSQL 16' : 'ClickHouse'}: рецепт недоступен',
            message: _code(row['code']),
            tone: DeckTone.unavailable,
          ),
        AutomationJsonView(
          title: 'Каталог рецептов и доступность установки',
          value: catalog,
        ),
      ],
    ),
  );
}

class AutomationProfilesSection extends StatelessWidget {
  const AutomationProfilesSection({
    super.key,
    required this.profiles,
    required this.loaded,
    required this.hasMore,
    required this.actions,
    required this.onSelect,
    required this.onMore,
    this.selectedId,
    this.beforeProfiles,
  });

  final List<AutomationProfileRecord> profiles;
  final String? selectedId;
  final bool loaded, hasMore;
  final AutomationActionAvailability actions;
  final ValueChanged<String> onSelect;
  final VoidCallback onMore;
  final Widget? beforeProfiles;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (loaded && profiles.isEmpty)
        const _Section(
          child: DeckNotice(
            message: 'Ansible-профилей пока нет',
            tone: DeckTone.neutral,
          ),
        ),
      if (beforeProfiles != null) beforeProfiles!,
      if (profiles.isNotEmpty)
        const _Section(child: DeckSectionHeader(title: 'Ansible-профили')),
      for (final row in profiles)
        _Section(
          child: DeckSurface(
            selected: selectedId == row.id,
            enabled: actions.select,
            onTap: () => onSelect(row.id),
            semanticLabel:
                '${row.name}, версия ${row.headRevision}${row.archived ? ', архив' : ''}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DeckSectionHeader(title: row.name),
                const SizedBox(height: BrandSpacing.space8),
                Text(
                  'Версия ${row.headRevision}${row.archived ? ' · архив' : ''}',
                ),
                if (row.description.isNotEmpty) Text(row.description),
              ],
            ),
          ),
        ),
      if (hasMore) _ActionButton('Ещё профили', actions.read ? onMore : null),
    ],
  );
}

class AutomationProfileDetailSection extends StatelessWidget {
  const AutomationProfileDetailSection({
    super.key,
    required this.profile,
    required this.revision,
    required this.hasServer,
    required this.actions,
    required this.onSelectVersion,
    required this.onValidate,
    required this.onCompare,
    required this.onEdit,
    required this.onCreatePlan,
    required this.onDelegate,
    required this.onArchive,
    this.validation,
    this.comparison,
  });

  final AutomationProfileRecord profile;
  final Map<String, Object?> revision;
  final Map<String, Object?>? validation, comparison;
  final bool hasServer;
  final AutomationActionAvailability actions;
  final VoidCallback onSelectVersion, onValidate, onCompare, onEdit;
  final VoidCallback onCreatePlan, onDelegate, onArchive;

  @override
  Widget build(BuildContext context) {
    final body = _object(revision['body']);
    return _Section(
      child: DeckSurface(
        child: DeckFormSection(
          title: '${profile.name} · версия ${revision['revision']}',
          description: 'Версия неизменна. Новая версия требует отдельного разрешения на запуск.',
          children: [
            if (profile.description.isNotEmpty) Text(profile.description),
            DeckStatus(
              label: profile.archived
                  ? 'Профиль в архиве'
                  : revision['revision'] == profile.headRevision
                  ? 'Текущая версия профиля'
                  : 'Выбрана предыдущая версия',
              tone: profile.archived ? DeckTone.neutral : DeckTone.available,
            ),
            if (!hasServer)
              const DeckNotice(
                message: 'Создавать и проверять профиль можно без сервера. Для плана и запуска выберите сервер.',
                tone: DeckTone.neutral,
              ),
            DeckFormSection(
              title: 'Параметры профиля',
              children: [
                _ParameterConstraints(
                  _object(body['parameters']),
                  definitions: true,
                ),
              ],
            ),
            _Program(
              effects: _rows(body['steps']),
              checks: const [],
              showChecks: false,
            ),
            if (validation != null) _Validation(validation!),
            if (comparison != null)
              DeckFormSection(
                title:
                    'Сравнение версий ${comparison!['fromRevision']} и ${comparison!['toRevision']}',
                children: [
                  if (_rows(_object(comparison!['result'])['changes']).isEmpty)
                    const Text('Изменений в полученном сравнении нет'),
                  for (final change in _rows(
                    _object(comparison!['result'])['changes'],
                  ))
                    DeckKeyValue(
                      label: _value(change['path']),
                      value:
                          'Было: ${_value(change['before'])}\nСтало: ${_value(change['after'])}',
                      selectable: true,
                    ),
                  if (_object(comparison!['result'])['truncated'] == true)
                    const DeckStatus(
                      label: 'Сравнение неполное: часть изменений не получена',
                      tone: DeckTone.warning,
                    ),
                  AutomationJsonView(
                    title: 'Сравнение выбранных версий',
                    value: comparison,
                  ),
                ],
              ),
            AutomationJsonView(
              title: 'Идентификатор и хеш версии',
              value: {
                'profileId': profile.id,
                'revision': revision['revision'],
                'digest': revision['digest'],
              },
            ),
            AutomationJsonView(title: 'Шаги и параметры', value: body),
            DeckActions(
              children: [
                _ActionButton(
                  'Выбрать версию',
                  actions.read ? onSelectVersion : null,
                ),
                _ActionButton(
                  'Проверить версию',
                  actions.read ? onValidate : null,
                ),
                _ActionButton(
                  'Сравнить версии',
                  actions.read ? onCompare : null,
                ),
                if (!profile.archived) ...[
                  _ActionButton(
                    'Изменить профиль',
                    actions.mutate ? onEdit : null,
                  ),
                  if (hasServer)
                    _ActionButton(
                      'Создать план',
                      actions.mutate ? onCreatePlan : null,
                    ),
                  if (hasServer)
                    _ActionButton(
                      'Делегировать версию',
                      actions.mutate ? onDelegate : null,
                    ),
                  _ActionButton(
                    'Архивировать',
                    actions.mutate ? onArchive : null,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AutomationPlanSection extends StatelessWidget {
  const AutomationPlanSection({
    super.key,
    required this.plan,
    required this.runnable,
    required this.expired,
    required this.actions,
    required this.onApprove,
    required this.onDeny,
    required this.onApply,
    required this.onRefresh,
    this.planAnchor,
    this.invalidReason,
    this.serverProfiles = const [],
    this.automationProfile,
  });

  final Map<String, Object?> plan;
  final bool runnable, expired;
  final AutomationActionAvailability actions;
  final Key? planAnchor;
  final String? invalidReason;
  final List<ProfileView> serverProfiles;
  final AutomationProfileRecord? automationProfile;
  final VoidCallback onApprove, onDeny, onApply, onRefresh;

  @override
  Widget build(BuildContext context) => _Section(
    child: DeckSurface(
      child: DeckFormSection(
        title: 'План',
        children: [
          DeckStatus(
            key: planAnchor,
            label: expired
                ? 'Срок плана истёк'
                : invalidReason != null
                ? 'План больше не действует'
                : runnable
                ? 'План готов к подтверждению'
                : 'План заблокирован',
            tone: expired || invalidReason != null || !runnable
                ? DeckTone.warning
                : DeckTone.available,
          ),
          if (expired)
            const Text('Создайте новый план. Прежний план нельзя запустить.'),
          if (invalidReason != null) Text(invalidReason!),
          for (final reason in _rows(plan['reasons']))
            Text(_code(reason['code'])),
          _PlanSummary(
            plan,
            serverProfiles: serverProfiles,
            automationProfile: automationProfile,
          ),
          const Text(
            'Подтверждение сохраняет согласие на этот точный план. Запуск задания выполняется отдельно.',
          ),
          AutomationJsonView(
            title: 'Неизменный план и технические детали',
            value: plan,
          ),
          if (!automationPlanTargetAvailable(plan, serverProfiles) ||
              _matchingProfile(plan, automationProfile) == null)
            const DeckNotice(
              message: 'Не удалось проверить цель и профиль плана',
              nextStep: 'Обновите локальные профили и план перед подтверждением или запуском.',
              tone: DeckTone.warning,
            ),
          DeckActions(
            children: [
              if (runnable && !expired && invalidReason == null) ...[
                _ActionButton(
                  'Подтвердить план',
                  actions.mutate &&
                          automationPlanTargetAvailable(plan, serverProfiles) &&
                          _matchingProfile(plan, automationProfile) != null
                      ? onApprove
                      : null,
                ),
                _ActionButton('Отклонить план', actions.mutate ? onDeny : null),
                FilledButton(
                  onPressed:
                      actions.mutate &&
                          automationPlanTargetAvailable(plan, serverProfiles) &&
                          _matchingProfile(plan, automationProfile) != null
                      ? onApply
                      : null,
                  child: const Text('Запустить'),
                ),
              ],
              _ActionButton('Обновить план', actions.read ? onRefresh : null),
            ],
          ),
        ],
      ),
    ),
  );
}

class AutomationJobsSection extends StatelessWidget {
  const AutomationJobsSection({
    super.key,
    required this.jobs,
    required this.events,
    required this.loaded,
    required this.hasMore,
    required this.droppedEvents,
    required this.canCancel,
    required this.canReconcile,
    required this.actions,
    required this.onRefresh,
    required this.onRefreshAuthorities,
    required this.onSelect,
    required this.onMore,
    required this.onShowPlan,
    required this.onCancel,
    required this.onReconcile,
    this.job,
    this.serverId,
  });

  final List<Map<String, Object?>> jobs, events;
  final Map<String, Object?>? job;
  final String? serverId;
  final bool loaded, hasMore, canCancel, canReconcile;
  final int droppedEvents;
  final AutomationActionAvailability actions;
  final VoidCallback onRefresh, onRefreshAuthorities, onMore, onShowPlan;
  final VoidCallback onCancel, onReconcile;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final outcome = _object(job?['outcome']);
    return _Section(
      child: DeckFormSection(
        title: 'Задания сервера',
        description: serverId == null
            ? 'Задания в текущем контексте сервера.'
            : 'Сервер: $serverId',
        children: [
          DeckActions(
            children: [
              _ActionButton(
                'Обновить задания',
                actions.read ? onRefresh : null,
              ),
              _ActionButton(
                'Обновить разрешения',
                actions.read ? onRefreshAuthorities : null,
              ),
            ],
          ),
          if (loaded && jobs.isEmpty)
            const DeckNotice(
              message: 'Заданий на этом сервере пока нет',
              tone: DeckTone.neutral,
            ),
          for (final row in jobs)
            Builder(
              builder: (context) {
                final entry = _object(row['job']);
                return DeckSurface(
                  enabled: actions.select,
                  selected: job?['id'] == entry['id'],
                  onTap: () => onSelect(entry['id'] as String),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DeckStatus(
                        label: _jobState(entry['state']),
                        tone: _jobTone(entry['state']),
                      ),
                      DeckKeyValue(
                        label: 'Задание',
                        value: _value(entry['id']),
                        selectable: true,
                      ),
                      if (entry['updatedAt'] != null)
                        DeckKeyValue(
                          label: 'Обновлено',
                          value: _time(entry['updatedAt']),
                        ),
                    ],
                  ),
                );
              },
            ),
          if (hasMore)
            _ActionButton('Ещё задания', actions.read ? onMore : null),
          if (job != null)
            DeckSurface(
              child: DeckFormSection(
                title: 'Выбранное задание',
                children: [
                  DeckStatus(
                    label: _jobState(job!['state']),
                    tone: _jobTone(job!['state']),
                  ),
                  if (job!['state'] == 'unknown')
                    const DeckNotice(
                      title: 'Исход не подтверждён',
                      message: 'На сервере могли произойти изменения. Уточните результат перед следующим действием.',
                      tone: DeckTone.unknown,
                    ),
                  if (job!['cancelRequested'] == true)
                    const DeckNotice(
                      message: 'Остановка запрошена. Текущий шаг ещё может завершиться; дождитесь подтверждённого результата.',
                    ),
                  if (outcome.isNotEmpty) ...[
                    DeckKeyValue(
                      label: 'Изменения',
                      value: switch (outcome['effects']) {
                        'none' => 'Подтверждено отсутствие изменений',
                        'confirmed' => 'Изменения подтверждены',
                        'uncertain' => 'Возможны неподтверждённые изменения',
                        _ => 'Не предоставлено',
                      },
                    ),
                    if (outcome['safeCode'] != null)
                      Text(_code(outcome['safeCode'])),
                    const DeckSectionHeader(title: 'Проверки результата'),
                    if (_rows(outcome['checks']).isEmpty)
                      const Text('Результаты проверок не предоставлены'),
                    for (final check in _rows(outcome['checks']))
                      DeckStatus(
                        label:
                            '${_value(check['stepId'])} · ${_value(check['checkId'])}: ${_result(check['result'])}',
                        tone: check['result'] == 'passed'
                            ? DeckTone.success
                            : check['result'] == 'failed'
                            ? DeckTone.error
                            : DeckTone.unknown,
                      ),
                  ],
                  const Text(
                    '«Остановить после текущего шага» запрашивает остановку задания. «Перестать ждать ответ» прекращает только ожидание в интерфейсе.',
                  ),
                  DeckActions(
                    children: [
                      _ActionButton(
                        'План задания',
                        actions.read ? onShowPlan : null,
                      ),
                      if (canCancel)
                        _ActionButton(
                          'Остановить после текущего шага',
                          actions.mutate ? onCancel : null,
                        ),
                      if (canReconcile)
                        _ActionButton(
                          'Уточнить результат',
                          actions.mutate ? onReconcile : null,
                        ),
                    ],
                  ),
                  DeckStatus(
                    label:
                        'Получено событий: ${events.length}. Пропущено в источнике: $droppedEvents',
                    tone: droppedEvents > 0
                        ? DeckTone.warning
                        : DeckTone.neutral,
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const DeckFocusLabel(
                      child: Text('Последние 200 полученных событий'),
                    ),
                    expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (events.isEmpty)
                        const Text('События пока не получены'),
                      for (final event in events)
                        DeckKeyValue(
                          label: _time(event['timestamp']),
                          value: event['kind'] == 'dropped'
                              ? 'Пропущено событий: ${_value(event['droppedCount'])}'
                              : event['kind'] == 'state'
                              ? _jobState(event['state'])
                              : '${event['stepId'] == null ? 'Ход задания' : _value(event['stepId'])}${event['checkResult'] == null ? '' : ': ${_result(event['checkResult'])}'}${event['safeCode'] == null ? '' : '. ${_code(event['safeCode'])}'}',
                        ),
                    ],
                  ),
                  AutomationJsonView(
                    title: 'Результат и проверки задания',
                    value: job,
                  ),
                  AutomationJsonView(
                    title: 'Данные полученных событий',
                    value: events,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class AutomationAuthoritiesSection extends StatelessWidget {
  const AutomationAuthoritiesSection({
    super.key,
    required this.approvals,
    required this.delegations,
    required this.loaded,
    required this.hasMoreApprovals,
    required this.hasMoreDelegations,
    required this.actions,
    required this.onOpenPlan,
    required this.onRevokeDelegation,
    required this.onMoreApprovals,
    required this.onMoreDelegations,
    this.now,
  });

  final List<Map<String, Object?>> approvals, delegations;
  final bool loaded, hasMoreApprovals, hasMoreDelegations;
  final AutomationActionAvailability actions;
  final ValueChanged<String> onOpenPlan;
  final ValueChanged<Map<String, Object?>> onRevokeDelegation;
  final VoidCallback onMoreApprovals, onMoreDelegations;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const DeckFocusLabel(
          child: Text('Запросы подтверждения этого сервера'),
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loaded && approvals.isEmpty) const Text('Запросов пока нет'),
          for (final row in approvals)
            _Section(
              child: DeckSurface(
                enabled: actions.select,
                onTap: () => onOpenPlan(row['planId'] as String),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DeckStatus(
                      label: switch (row['state']) {
                        'pending' => 'Ожидает подтверждения',
                        'approved' => 'План подтверждён',
                        'denied' => 'План отклонён',
                        'expired' => 'Срок подтверждения истёк',
                        'consumed' => 'Подтверждение использовано для задания',
                        _ => _value(row['state']),
                      },
                      tone: row['state'] == 'approved'
                          ? DeckTone.success
                          : DeckTone.neutral,
                    ),
                    DeckKeyValue(
                      label: 'Действует до',
                      value: _time(row['expiresAt']),
                    ),
                    DeckKeyValue(
                      label: 'План',
                      value: _value(row['planId']),
                      selectable: true,
                    ),
                  ],
                ),
              ),
            ),
          if (hasMoreApprovals)
            _ActionButton('Ещё запросы', actions.read ? onMoreApprovals : null),
        ],
      ),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const DeckFocusLabel(child: Text('Делегированные версии')),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loaded && delegations.isEmpty)
            const Text('Делегирований пока нет'),
          for (final row in delegations)
            _Section(
              child: DeckSurface(
                child: DeckFormSection(
                  title: row['revokedAt'] == null
                      ? automationDeadlineExpired(
                              row['expiresAt'],
                              now: now?.call(),
                            )
                            ? 'Срок делегирования истёк'
                            : 'Делегирование версии'
                      : 'Делегирование отозвано',
                  description: 'Запуск только указанных версий на перечисленных серверах в границах параметров.',
                  children: [
                    DeckKeyValue(
                      label: 'Клиент ИИ',
                      value: _value(row['grantId']),
                      selectable: true,
                    ),
                    DeckKeyValue(
                      label: 'Серверы',
                      value: _value(row['serverIds']),
                      selectable: true,
                    ),
                    DeckKeyValue(
                      label: 'Действует до',
                      value: _time(row['expiresAt']),
                    ),
                    for (final revision in _rows(row['profileRevisions']))
                      DeckKeyValue(
                        label: 'Профиль и точная версия',
                        value:
                            '${_value(revision['profileId'])} · версия ${_value(revision['revision'])}',
                        selectable: true,
                      ),
                    _ParameterConstraints(_object(row['predicates'])),
                    AutomationJsonView(
                      title: 'Хеши версий и детали делегирования',
                      value: row,
                    ),
                    if (row['revokedAt'] == null)
                      DeckActions(
                        children: [
                          _ActionButton(
                            'Отозвать делегирование',
                            actions.mutate
                                ? () => onRevokeDelegation(row)
                                : null,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          if (hasMoreDelegations)
            _ActionButton(
              'Ещё делегирования',
              actions.read ? onMoreDelegations : null,
            ),
        ],
      ),
    ],
  );
}

class AutomationGrantsSection extends StatelessWidget {
  const AutomationGrantsSection({
    super.key,
    required this.grants,
    required this.loaded,
    required this.actions,
    required this.onRefresh,
    required this.onCreate,
    required this.onConfigure,
    required this.onEdit,
    required this.onRevoke,
    required this.onCopyConfiguration,
    this.launchConfiguration,
    this.serverProfiles = const [],
  });

  final List<AutomationGrantPresentation> grants;
  final List<ProfileView> serverProfiles;
  final bool loaded;
  final AutomationActionAvailability actions;
  final Map<String, Object?>? launchConfiguration;
  final VoidCallback onRefresh, onCreate, onCopyConfiguration;
  final ValueChanged<String> onConfigure;
  final ValueChanged<Map<String, Object?>> onEdit, onRevoke;

  @override
  Widget build(BuildContext context) => _Section(
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const DeckFocusLabel(
        child: Text('Доступ ИИ рабочего пространства'),
      ),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DeckActions(
          children: [
            _ActionButton('Обновить клиентов', actions.read ? onRefresh : null),
            _ActionButton('Подключить ИИ', actions.mutate ? onCreate : null),
          ],
        ),
        if (loaded && grants.isEmpty)
          const _Section(
            child: DeckNotice(
              message: 'Клиентов ИИ пока нет',
              tone: DeckTone.neutral,
            ),
          ),
        for (final grant in grants)
          _Section(
            child: DeckSurface(
              child: DeckFormSection(
                title: _value(grant.value['label']),
                children: [
                  DeckStatus(
                    label: grant.value['revokedAt'] != null
                        ? 'Доступ отозван'
                        : grant.current
                        ? 'Доступ действует'
                        : 'Срок доступа истёк',
                    tone: grant.current ? DeckTone.available : DeckTone.warning,
                  ),
                  DeckKeyValue(
                    label: 'Выданные права',
                    value: (grant.value['scopes'] as List)
                        .map(_scope)
                        .join(', '),
                  ),
                  AutomationServerTargets(
                    serverIds: _targetIds(grant.value['serverIds']),
                    serverProfiles: serverProfiles,
                  ),
                  DeckKeyValue(
                    label: 'Действует до',
                    value: _time(grant.value['expiresAt']),
                  ),
                  const Text(
                    'Отзыв блокирует следующие шаги. Текущий шаг задания может завершиться.',
                  ),
                  AutomationJsonView(
                    title: 'Серверы и выданные права',
                    value: grant.value,
                  ),
                  DeckActions(
                    children: [
                      if (grant.current)
                        _ActionButton(
                          'Конфигурация MCP',
                          actions.read
                              ? () => onConfigure(grant.value['id'] as String)
                              : null,
                        ),
                      if (grant.value['revokedAt'] == null) ...[
                        _ActionButton(
                          'Изменить права',
                          actions.mutate ? () => onEdit(grant.value) : null,
                        ),
                        _ActionButton(
                          'Отозвать доступ',
                          actions.mutate ? () => onRevoke(grant.value) : null,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (launchConfiguration != null)
          _Section(
            child: DeckSurface(
              child: DeckFormSection(
                title: 'Конфигурация MCP',
                description: 'Передайте клиенту ИИ команду и отдельные аргументы. Секрет доступа в этой конфигурации не показывается.',
                children: [
                  DeckKeyValue(
                    label: 'Команда',
                    value: _value(launchConfiguration!['command']),
                    selectable: true,
                    valueStyle: BrandTypography.log,
                  ),
                  DeckKeyValue(
                    label: 'Аргументы',
                    value: _value(launchConfiguration!['args']),
                    selectable: true,
                    valueStyle: BrandTypography.log,
                  ),
                  AutomationJsonView(
                    title: 'Команда и аргументы MCP',
                    value: launchConfiguration,
                  ),
                  DeckActions(
                    children: [
                      _ActionButton(
                        'Скопировать конфигурацию',
                        actions.read ? onCopyConfiguration : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class AutomationJsonEditorDialog extends StatelessWidget {
  const AutomationJsonEditorDialog({
    super.key,
    required this.title,
    required this.input,
    required this.onClose,
    required this.onContinue,
    this.error,
    this.preview,
    this.purpose,
    this.target,
    this.contextDetails,
    this.onChanged,
    this.serverProfiles = const [],
    this.targetServerIds = const [],
    this.contextCurrent = true,
    this.saving = false,
    this.requestRetained = false,
    this.canContinue = true,
    this.ownerStatus,
  });

  final String title;
  final TextEditingController input;
  final String? error, purpose, target;
  final Map<String, Object?>? preview, contextDetails;
  final List<ProfileView> serverProfiles;
  final List<String> targetServerIds;
  final bool contextCurrent;
  final bool saving, requestRetained, canContinue;
  final Widget? ownerStatus;
  bool get _locked => saving || requestRetained;
  final ValueChanged<String>? onChanged;
  final VoidCallback onClose, onContinue;

  bool get _targetsAvailable => automationTargetsAvailable([
    ...targetServerIds,
    ..._targetIds(preview?['serverIds']),
  ], serverProfiles);

  @override
  Widget build(BuildContext context) => DeckDialogLayout(
    title: title,
    maxWidth: 720,
    target: target == null ? null : Text(target!),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!contextCurrent)
          const DeckNotice(
            message: _changedTargetMessage,
            tone: DeckTone.warning,
          ),
        if (targetServerIds.isNotEmpty)
          AutomationServerTargets(
            serverIds: targetServerIds,
            serverProfiles: serverProfiles,
          ),
        if (purpose != null) ...[
          Text(purpose!),
          const SizedBox(height: BrandSpacing.space16),
        ],
        if (preview != null) ...[
          _EditorPreview(preview!, serverProfiles: serverProfiles),
          const SizedBox(height: BrandSpacing.space16),
        ],
        TextField(
          controller: input,
          enabled: !_locked,
          readOnly: _locked,
          onChanged: _locked ? null : onChanged,
          minLines: 8,
          maxLines: 18,
          decoration: InputDecoration(
            labelText: 'JSON',
            errorText: error,
            errorMaxLines: 20,
          ),
          style: _locked
              ? BrandTypography.log.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                )
              : BrandTypography.log,
        ),
        if (ownerStatus != null) ...[
          const SizedBox(height: BrandSpacing.space16),
          ownerStatus!,
        ],
        if (contextDetails != null)
          AutomationJsonView(
            title: 'Точная версия и технические детали',
            value: contextDetails,
          ),
      ],
    ),
    actions: [
      TextButton(onPressed: onClose, child: const Text('Закрыть')),
      FilledButton(
        onPressed:
            contextCurrent && _targetsAvailable && canContinue && !_locked
            ? onContinue
            : null,
        child: const Text('Продолжить'),
      ),
    ],
  );
}

class AutomationProfileEditorDialog extends StatelessWidget {
  const AutomationProfileEditorDialog({
    super.key,
    required this.name,
    required this.description,
    required this.body,
    required this.validating,
    required this.canValidate,
    required this.onBodyChanged,
    required this.onClose,
    required this.onSave,
    required this.onValidate,
    this.existing,
    this.baseRevision,
    this.validation,
    this.error,
    this.nameError,
    this.descriptionError,
    this.saveError,
    this.canSave = true,
    this.saving = false,
    this.saveUnconfirmed = false,
    this.requestRetained = false,
    this.contextCurrent = true,
    this.ownerStatus,
    this.basisReview,
  });

  final TextEditingController name, description, body;
  final AutomationProfileRecord? existing;
  final int? baseRevision;
  final Map<String, Object?>? validation;
  final String? error, nameError, descriptionError, saveError;
  final bool validating, canValidate, canSave, saving, saveUnconfirmed;
  final bool requestRetained, contextCurrent;
  final Widget? ownerStatus, basisReview;
  final ValueChanged<String> onBodyChanged;
  final VoidCallback onClose, onSave, onValidate;

  @override
  Widget build(BuildContext context) => DeckDialogLayout(
    title: existing == null ? 'Новый Ansible-профиль' : 'Новая версия профиля',
    maxWidth: 720,
    child: DeckFormSection(
      title: 'Описание и содержимое',
      description: 'Сохранение создаёт неизменную версию профиля и не запускает действия на сервере.',
      children: [
        TextField(
          controller: name,
          enabled: contextCurrent && !saving && !requestRetained,
          style: Theme.of(context).textTheme.bodyLarge,
          decoration: InputDecoration(
            labelText: 'Название',
            errorText: nameError,
            errorMaxLines: 20,
          ),
        ),
        TextField(
          controller: description,
          enabled: contextCurrent && !saving && !requestRetained,
          style: Theme.of(context).textTheme.bodyLarge,
          maxLines: null,
          decoration: InputDecoration(
            labelText: 'Описание',
            errorText: descriptionError,
            errorMaxLines: 20,
          ),
        ),
        ExcludeSemantics(
          child: Text(
            'Шаги и параметры профиля (JSON)',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        const SizedBox(height: BrandSpacing.space8),
        Semantics(
          label: 'Шаги и параметры профиля (JSON)',
          child: TextField(
            controller: body,
            enabled: contextCurrent && !saving && !requestRetained,
            onChanged: onBodyChanged,
            minLines: 8,
            maxLines: 16,
            decoration: InputDecoration(errorText: error, errorMaxLines: 20),
            style: BrandTypography.log.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        if (existing != null)
          Text(
            'Основа: версия $baseRevision. Текущая версия: ${existing!.headRevision}.',
          ),
        if (existing != null)
          const DeckNotice(
            message:
                'Для новой версии потребуется отдельное разрешение на запуск.',
            tone: DeckTone.neutral,
          ),
        if (validation != null) _Validation(validation!),
        if (!contextCurrent)
          const DeckNotice(
            message: 'Контекст профиля изменился. Прежний редактор больше не может сохранять или подтверждать изменения.',
            tone: DeckTone.warning,
          ),
        if (ownerStatus != null) ownerStatus!,
        if (basisReview != null) basisReview!,
        if (saveError != null && ownerStatus == null)
          DeckNotice(
            title: saveUnconfirmed ? 'Исход записи не подтверждён' : null,
            message: saveError!,
            nextStep: saveUnconfirmed
                ? 'Закройте редактор, чтобы использовать предусмотренные действия сохранённого запроса.'
                : null,
            tone: saveUnconfirmed ? DeckTone.unknown : DeckTone.warning,
          ),
        if (saving)
          const DeckStatus(label: 'Сохранение профиля', pending: true),
        if (validating)
          const DeckStatus(
            label: 'Проверка содержимого профиля',
            pending: true,
          ),
      ],
    ),
    actions: [
      TextButton(onPressed: onClose, child: const Text('Закрыть')),
      FilledButton(
        onPressed:
            !contextCurrent ||
                validating ||
                saving ||
                requestRetained ||
                !canSave
            ? null
            : onSave,
        child: const Text('Сохранить версию'),
      ),
      OutlinedButton(
        onPressed: contextCurrent && !saving && canValidate ? onValidate : null,
        child: Text(validating ? 'Проверка…' : 'Проверить без сохранения'),
      ),
    ],
  );
}

class AutomationProfileBasisReview extends StatelessWidget {
  const AutomationProfileBasisReview({
    super.key,
    required this.submission,
    required this.canRead,
    required this.canAccept,
    required this.requestRetained,
    required this.onRead,
    required this.onAccept,
  });
  final AutomationProfileDraftSubmission submission;
  final bool canRead, canAccept, requestRetained;
  final VoidCallback onRead, onAccept;

  @override
  Widget build(BuildContext context) {
    final original = submission.initialBasis;
    if (original == null) return const SizedBox.shrink();
    final accepted = submission.acceptedBasis,
        candidate = submission.candidateBasis;
    return DeckFormSection(
      title: 'Основа черновика',
      children: [
        DeckKeyValue(
          label: 'Исходная версия черновика',
          value: '${original.revision}',
        ),
        DeckKeyValue(
          label: 'Хеш исходной версии',
          value: original.digest,
          selectable: true,
        ),
        DeckKeyValue(
          label: 'Ожидаемая текущая версия для записи',
          value: '${submission.currentBasis!.profile.headRevision}',
        ),
        if (accepted != null)
          DeckKeyValue(
            label: 'Хеш принятой основы',
            value: accepted.digest,
            selectable: true,
          ),
        if (submission.requiresNewBasis)
          const DeckNotice(
            message: 'Текущая версия изменилась. Перечитайте её и отдельно примите новую основу перед сохранением. Текст черновика сохранён.',
            tone: DeckTone.warning,
          ),
        if (submission.requiresNewBasis && requestRetained)
          const Text(
            'Закройте сохранённый запрос в этом редакторе, чтобы перечитать текущую версию. Черновик останется.',
          ),
        if (submission.canReadBasis)
          OutlinedButton(
            onPressed: canRead && !submission.basisLoading ? onRead : null,
            child: const Text('Перечитать текущую версию'),
          ),
        if (submission.basisLoading)
          const DeckStatus(
            label: 'Чтение текущей версии профиля',
            pending: true,
          ),
        if (candidate != null) ...[
          DeckKeyValue(
            label: 'Прочитанный профиль',
            value: candidate.profile.name,
          ),
          DeckKeyValue(label: 'Текущая версия', value: '${candidate.revision}'),
          DeckKeyValue(
            label: 'Хеш текущей версии',
            value: candidate.digest,
            selectable: true,
          ),
          const Text(
            'Принятие меняет только ожидаемую текущую версию для следующего сохранения. Содержимое черновика остаётся прежним.',
          ),
          if (requestRetained)
            const Text(
              'Сначала закройте сохранённый запрос в этом редакторе. Это не отменяет выполненные действия.',
            ),
          OutlinedButton(
            onPressed: canAccept && !requestRetained ? onAccept : null,
            child: const Text('Принять текущую версию как основу'),
          ),
        ],
      ],
    );
  }
}

class AutomationPlanDecisionDialog extends StatefulWidget {
  const AutomationPlanDecisionDialog({
    super.key,
    required this.plan,
    required this.approve,
    required this.onBack,
    required this.onConfirm,
    this.serverProfiles = const [],
    this.automationProfile,
    this.contextCurrent = true,
    this.now,
  });

  final Map<String, Object?> plan;
  final bool approve;
  final VoidCallback onBack, onConfirm;
  final List<ProfileView> serverProfiles;
  final AutomationProfileRecord? automationProfile;
  final bool contextCurrent;

  /// A presentation clock basis for deterministic synthetic fixtures. The live
  /// owner uses the real clock and retains its final admission/deadline check.
  final DateTime Function()? now;

  @override
  State<AutomationPlanDecisionDialog> createState() =>
      _AutomationPlanDecisionDialogState();
}

class _AutomationPlanDecisionDialogState
    extends State<AutomationPlanDecisionDialog> {
  late final Map<String, Object?> _plan =
      jsonDecode(jsonEncode(widget.plan)) as Map<String, Object?>;
  late final List<ProfileView> _serverProfiles = List.unmodifiable(
    widget.serverProfiles,
  );
  late final AutomationProfileRecord? _profile = _matchingProfile(
    _plan,
    widget.automationProfile,
  );
  late final bool _approve = widget.approve;
  bool _invalidated = false;
  bool _deadlineRetired = false;
  bool get _expired => _deadlineRetired =
      _deadlineRetired || automationPlanExpired(_plan, now: widget.now?.call());
  bool get _canConsent =>
      !_approve ||
      (automationPlanTargetAvailable(_plan, _serverProfiles) &&
          _profile != null);

  bool get _current =>
      mounted &&
      !_expired &&
      widget.contextCurrent &&
      widget.approve == _approve &&
      _pretty(widget.plan) == _pretty(_plan) &&
      automationTargetsUnchanged(
        [if (_plan['serverId'] is String) _plan['serverId'] as String],
        _serverProfiles,
        widget.serverProfiles,
      ) &&
      _pretty(
            _matchingProfile(widget.plan, widget.automationProfile)?.toJson(),
          ) ==
          _pretty(_profile?.toJson());

  @override
  void didUpdateWidget(covariant AutomationPlanDecisionDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    _invalidated = _invalidated || !_current;
  }

  @override
  Widget build(BuildContext context) => DeckDialogLayout(
    title: _approve ? 'Подтвердить этот план?' : 'Отклонить этот план?',
    maxWidth: 720,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _approve
              ? 'Вы подтверждаете только показанный неизменный план. Для запуска потребуется отдельное действие.'
              : 'Отклонение этого плана не запускает действий на сервере.',
        ),
        const SizedBox(height: BrandSpacing.space16),
        if (_expired)
          const DeckNotice(
            title: 'Срок плана истёк',
            message: 'Создайте новый план. Прежнее согласие нельзя применить.',
            tone: DeckTone.warning,
          ),
        if (_invalidated || !_current)
          const DeckNotice(
            message: _changedTargetMessage,
            tone: DeckTone.warning,
          ),
        _PlanSummary(
          _plan,
          serverProfiles: _serverProfiles,
          automationProfile: _profile,
        ),
        AutomationJsonView(title: 'Точный план и хеш', value: _plan),
      ],
    ),
    actions: [
      TextButton(onPressed: widget.onBack, child: const Text('Назад')),
      FilledButton(
        onPressed: _invalidated || !_current || !_canConsent
            ? null
            : () {
                if (_expired) {
                  setState(() {});
                  return;
                }
                if (!_invalidated && _current && _canConsent)
                  widget.onConfirm();
              },
        child: Text(_approve ? 'Подтвердить план' : 'Отклонить план'),
      ),
    ],
  );
}

class AutomationConfirmationDialog extends StatelessWidget {
  const AutomationConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.onBack,
    required this.onConfirm,
  });

  final String title, message, confirmLabel;
  final VoidCallback onBack, onConfirm;

  @override
  Widget build(BuildContext context) => DeckDialogLayout(
    title: title,
    child: Text(message),
    actions: [
      TextButton(onPressed: onBack, child: const Text('Назад')),
      FilledButton(onPressed: onConfirm, child: Text(confirmLabel)),
    ],
  );
}

class AutomationDelegationGrantDialog extends StatelessWidget {
  const AutomationDelegationGrantDialog({
    super.key,
    required this.grants,
    required this.onSelect,
  });

  final List<Map<String, Object?>> grants;
  final ValueChanged<Map<String, Object?>> onSelect;

  @override
  Widget build(BuildContext context) => DeckDialogLayout(
    title: 'Кому делегировать профиль?',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Выберите клиента с правами планирования и запуска на этот сервер.',
        ),
        for (final row in grants)
          _Section(
            child: DeckSurface(
              onTap: () => onSelect(row),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DeckSectionHeader(title: _value(row['label'])),
                  DeckKeyValue(
                    label: 'Действует до',
                    value: _time(row['expiresAt']),
                  ),
                  DeckKeyValue(
                    label: 'Права',
                    value: (row['scopes'] as List).map(_scope).join(', '),
                  ),
                  DeckKeyValue(
                    label: 'Серверы',
                    value: _value(row['serverIds']),
                    selectable: true,
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
