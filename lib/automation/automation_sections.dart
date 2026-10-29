import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:serverdeck_protocol/automation/profile_records.dart';
import 'package:serverdeck_protocol/automation/models.dart' show AutomationBody;
import 'package:serverdeck_protocol/models.dart';

import '../theme/brand_assets.dart';
import '../theme/brand_theme.dart';
import '../theme/brand_tokens.dart';
import '../theme/motion.dart';
import '../ui/deck_components.dart';
import '../ui/deck_page.dart';
import '../ui/deck_workspace_overlay.dart';
import '../ui/deck_icon.dart';
import '../ui/deck_control_target.dart';
import '../ui/deck_table_controls.dart';
import '../ui/deck_input_border.dart';
import '../shell/private_session.dart';
import 'automation_forms.dart';
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

bool _jsonObject(String source) {
  try {
    return jsonDecode(source) is Map<String, Object?>;
  } on FormatException {
    return false;
  }
}

bool _profileBodyValid(String source) {
  try {
    AutomationBody.fromJson(
      (jsonDecode(source) as Map).cast<String, Object?>(),
    );
    return true;
  } catch (_) {
    return false;
  }
}

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
  Widget build(BuildContext context) => child;
}

/// Canonical rows remain one table surface on wide layouts and become labelled
/// cards on phones or large text. Only loaded owner records reach this widget.
class AutomationRecordTable extends StatelessWidget {
  const AutomationRecordTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onSelect,
    this.selected = -1,
    this.footer,
    this.caption,
    this.showFooter = true,
  });
  final String? caption;
  final bool showFooter;
  final List<String> columns;
  final List<List<Widget>> rows;
  final ValueChanged<int>? onSelect;
  final int selected;
  final Widget? footer;
  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width <= 520;
    final colors = deckColors(context);
    Widget content(List<Widget> cells, {required bool header}) {
      if (phone) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors['border'])),
                ),
                child: DefaultTextStyle.merge(
                  style: BrandTypography.table.copyWith(
                    fontSize: 15,
                    height: 22 / 15,
                    fontFamily: BrandAssets.semiboldFamily,
                    fontWeight: BrandTypography.semiboldWeight,
                    fontVariations: BrandTypography.semiboldVariations,
                  ),
                  child: cells.first,
                ),
              ),
              if (cells.length > 1) ...[
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, c) => Wrap(
                    spacing: 12,
                    runSpacing: 14,
                    children: [
                      for (var i = 1; i < cells.length; i++)
                        SizedBox(
                          width: (c.maxWidth - 12) / 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                columns[i],
                                style: BrandTypography.caption.copyWith(
                                  color: colors['muted'],
                                ),
                              ),
                              const SizedBox(height: 4),
                              cells[i],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < cells.length; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: header ? 10 : 12,
                ),
                child: !header && i == 0
                    ? DefaultTextStyle.merge(
                        style: const TextStyle(
                          fontFamily: BrandAssets.semiboldFamily,
                          fontWeight: BrandTypography.semiboldWeight,
                          fontVariations: BrandTypography.semiboldVariations,
                        ),
                        child: cells[i],
                      )
                    : cells[i],
              ),
            ),
        ],
      );
    }

    Widget line(List<Widget> cells, {bool header = false, int index = -1}) {
      final selectedRow = !header && index == selected;
      final radius = BorderRadius.circular(phone ? 10 : 0);
      return Container(
        decoration: BoxDecoration(
          color:
              colors[header
                  ? 'raised'
                  : selectedRow
                  ? 'selected'
                  : 'surface'],
          borderRadius: phone ? radius : null,
          border: phone
              ? Border.all(color: colors['border'])
              : (header ? rows.isNotEmpty : index < rows.length - 1)
              ? Border(bottom: BorderSide(color: colors['border']))
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            hoverColor: colors['hover'],
            onTap: index < 0 || onSelect == null
                ? null
                : () => onSelect!(index),
            child: DefaultTextStyle(
              style: BrandTypography.table.copyWith(color: colors['text']),
              child: content(cells, header: header),
            ),
          ),
        ),
      );
    }

    final children = <Widget>[
      if (caption != null) ...[
        Container(
          decoration: phone
              ? BoxDecoration(
                  color: colors['surface'],
                  border: Border.all(color: colors['border']),
                  borderRadius: BorderRadius.circular(9),
                )
              : null,
          padding: const EdgeInsets.all(14),
          child: Text(
            caption!,
            style: BrandTypography.caption.copyWith(color: colors['muted']),
          ),
        ),
        if (phone) const SizedBox(height: 10),
      ],
      if (!phone)
        line(
          columns
              .map(
                (label) => Text(
                  label,
                  style: BrandTypography.tableHeader.copyWith(
                    color: colors['muted'],
                  ),
                ),
              )
              .toList(),
          header: true,
        ),
      for (var i = 0; i < rows.length; i++) ...[
        if (phone && i > 0) const SizedBox(height: 10),
        Semantics(
          selected: selected == i,
          button: onSelect != null,
          child: line(rows[i], index: i),
        ),
      ],
      if (showFooter)
        Container(
          decoration: phone
              ? null
              : BoxDecoration(
                  border: Border(top: BorderSide(color: colors['border'])),
                ),
          padding: phone
              ? const EdgeInsets.only(top: 12)
              : const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: DefaultTextStyle(
            style: BrandTypography.caption.copyWith(color: colors['muted']),
            child: DeckHitOverflow(
              outset: 7,
              child: footer ?? Text('Получено записей: ${rows.length}'),
            ),
          ),
        ),
    ];
    final table = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
    return phone ? table : DeckPanel(padding: EdgeInsets.zero, child: table);
  }
}

class AutomationLoadedTable extends StatefulWidget {
  const AutomationLoadedTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onSelect,
    this.selected = -1,
    this.footer,
    this.hasMore = false,
    this.onMore,
  });
  final List<String> columns;
  final List<List<Widget>> rows;
  final ValueChanged<int>? onSelect;
  final int selected;
  final Widget? footer;
  final bool hasMore;
  final VoidCallback? onMore;
  @override
  State<AutomationLoadedTable> createState() => _AutomationLoadedTableState();
}

class _AutomationLoadedTableState extends State<AutomationLoadedTable> {
  final query = TextEditingController();
  String? status;
  int page = 0;
  bool awaitingPage = false;
  int? _statusMenuEpoch;
  bool _filterSessionCurrent() {
    if (!mounted) return false;
    final session = PrivateSessionScope.maybeOf(context);
    return session == null
        ? _statusMenuEpoch == null
        : session.authorized && session.epoch == _statusMenuEpoch;
  }

  String text(Widget value) => switch (value) {
    Text() => value.data ?? '',
    DeckStatus() => value.label,
    _ => '',
  };
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AutomationLoadedTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (awaitingPage && widget.rows.length > oldWidget.rows.length) {
      page++;
      awaitingPage = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final stateColumn = widget.columns.indexWhere(
      (label) => label == 'Состояние' || label == 'Доступность',
    );
    final states = stateColumn < 0
        ? <String>[]
        : widget.rows.map((row) => text(row[stateColumn])).toSet().toList();
    final indices = [
      for (var i = 0; i < widget.rows.length; i++)
        if (widget.rows[i]
                .map(text)
                .join(' ')
                .toLowerCase()
                .contains(query.text.toLowerCase()) &&
            (status == null ||
                stateColumn < 0 ||
                text(widget.rows[i][stateColumn]) == status))
          i,
    ];
    final last = indices.isEmpty ? 0 : (indices.length - 1) ~/ 20;
    final current = page.clamp(0, last);
    final visible = indices.skip(current * 20).take(20).toList();
    return DeckHitOverflow(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DeckHitOverflow(
            child: LayoutBuilder(
              builder: (context, c) {
                final phone = MediaQuery.sizeOf(context).width <= 520;
                final filters = DeckHitOverflow(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      DeckFilterChip(
                        label: 'Все ${indices.length}',
                        active: status == null,
                        onPressed: () => setState(() {
                          query.clear();
                          status = null;
                          page = 0;
                          awaitingPage = false;
                        }),
                      ),
                      if (stateColumn >= 0)
                        DeckControlTarget(
                          visibleHeight: DeckFilterChip.visibleHeight(context),
                          child: PopupMenuButton<String>(
                            tooltip: 'Состояние',
                            initialValue: status ?? '',
                            popUpAnimationStyle: Motion.reduced(context)
                                ? AnimationStyle.noAnimation
                                : null,
                            onSelected: (next) {
                              if (!_filterSessionCurrent()) return;
                              setState(() {
                                status = next == '' ? null : next;
                                page = 0;
                                awaitingPage = false;
                              });
                            },
                            itemBuilder: (_) {
                              final epoch = PrivateSessionScope.maybeOf(context)
                                  ?.epoch;
                              _statusMenuEpoch = epoch;
                              return [
                                PopupMenuItem(
                                  value: '',
                                  child: PrivateDialogGate(
                                    launchEpoch: epoch,
                                    builder: (_) => const Text('Все состояния'),
                                  ),
                                ),
                                for (final state in states)
                                  PopupMenuItem(
                                    value: state,
                                    child: PrivateDialogGate(
                                      launchEpoch: epoch,
                                      builder: (_) => Text(state),
                                    ),
                                  ),
                              ];
                            },
                            style: DeckFilterChip.style(
                              context,
                              active: status != null,
                            ),
                            icon: Semantics(
                              selected: status != null,
                              child: DeckFilterChip.content(
                                context,
                                status ?? 'Состояние',
                                active: status != null,
                                icon: 'filter',
                              ),
                            ),
                          ),
                        ),
                      const DeckFilterChip(
                        label: 'Теги',
                        trailing: 'chevron',
                        tooltip: 'В данных этого списка нет меток; фильтр по меткам недоступен.',
                      ),
                    ],
                  ),
                );
                return Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: phone ? 12 : 10,
                  runSpacing: phone ? 12 : 10,
                  children: [
                    DeckHitOverflow(
                      child: SizedBox(
                        width: c.maxWidth.clamp(0.0, 360.0).toDouble(),
                        child: DeckSearchField(
                          controller: query,
                          onChanged: (_) => setState(() {
                            page = 0;
                            awaitingPage = false;
                          }),
                        ),
                      ),
                    ),
                    filters,
                  ],
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.sizeOf(context).width <= 520 ? 13 : 16),
          AutomationRecordTable(
            columns: widget.columns,
            rows: [for (final i in visible) widget.rows[i]],
            selected: visible.indexOf(widget.selected),
            onSelect: widget.onSelect == null
                ? null
                : (i) => widget.onSelect!(visible[i]),
            footer: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.footer != null) widget.footer!,
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Получено записей: ${widget.rows.length} · показано: ${visible.length}',
                      style: BrandTypography.caption,
                    ),
                    DeckHitOverflow(
                      outset: 7,
                      child: Wrap(
                        spacing: MediaQuery.sizeOf(context).width <= 520
                            ? 3
                            : 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Tooltip(
                            message: current > 0 ? 'Предыдущая страница' : 'Предыдущая страница · Нет другой загруженной страницы',
                            child: DeckPagerButton(
                              reverse: true,
                              onPressed: current > 0
                                  ? () => setState(() => page = current - 1)
                                  : null,
                            ),
                          ),
                          Tooltip(
                            message: 'Это текущая загруженная страница; переход на произвольный номер не поддерживается.',
                            child: DeckPagerButton(
                              selected: true,
                              page: current + 1,
                            ),
                          ),
                          Tooltip(
                            message: current < last || widget.hasMore
                                ? 'Следующая страница'
                                : 'Следующая страница · Нет другой загруженной страницы',
                            child: DeckPagerButton(
                              onPressed: current < last
                                  ? () => setState(() => page = current + 1)
                                  : widget.hasMore && widget.onMore != null
                                  ? () {
                                      awaitingPage = true;
                                      widget.onMore!();
                                    }
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TwoPanels extends StatelessWidget {
  const _TwoPanels({
    required this.left,
    required this.right,
    this.form = false,
  });
  final Widget left, right;
  final bool form;
  @override
  Widget build(BuildContext context) {
    if (form) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final wide = MediaQuery.sizeOf(context).width > 960;
          final available = constraints.maxWidth - (wide ? 20 : 0);
          return Flex(
            direction: wide ? Axis.horizontal : Axis.vertical,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: wide ? available * 165 / 265 : available,
                child: left,
              ),
              if (wide) const SizedBox(width: 20),
              if (wide) SizedBox(width: available * 100 / 265, child: right),
            ],
          );
        },
      );
    }
    final gap = MediaQuery.sizeOf(context).width <= 960 ? 14.0 : 20.0;
    return MediaQuery.sizeOf(context).width > 760 &&
            MediaQuery.textScalerOf(context).scale(14) < 27
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: form ? 506 : 1, child: left),
              SizedBox(width: gap),
              Expanded(flex: form ? 307 : 1, child: right),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              left,
              SizedBox(height: deckSectionGap(context)),
              right,
            ],
          );
  }
}

/// The effective source description-list: ruled facts on wide pages, ordered
/// labels and values on phones or at the FA05 large-text override.
class AutomationFacts extends StatelessWidget {
  const AutomationFacts({
    super.key,
    required this.values,
    this.tableContext = false,
    this.styles = const {},
  });
  final Map<String, String> values;
  final bool tableContext;
  final Map<String, TextStyle> styles;
  @override
  Widget build(BuildContext context) {
    final colors = deckColors(context);
    final stacked = MediaQuery.sizeOf(context).width <= 520;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < values.length; i++)
          Builder(
            builder: (context) {
              final entry = values.entries.elementAt(i),
                  last = i == values.length - 1;
              final label = Text(
                entry.key,
                style: BrandTypography.caption.copyWith(
                  color: colors['muted'],
                  height: 20 / 12,
                ),
              );
              final value = Text(
                entry.value,
                style:
                    (tableContext ? BrandTypography.body : BrandTypography.log)
                        .copyWith(
                          fontSize: stacked ? 13 : 12,
                          height: stacked ? 22 / 13 : 20 / 12,
                          color: colors['text'],
                        )
                        .merge(styles[entry.key]),
              );
              if (stacked)
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
                      child: label,
                    ),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.only(top: 4, bottom: last ? 0 : 12),
                      decoration: BoxDecoration(
                        border: last
                            ? null
                            : Border(
                                bottom: BorderSide(color: colors['border']),
                              ),
                      ),
                      child: value,
                    ),
                  ],
                );
              Widget cell(Widget child) => Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  border: last
                      ? null
                      : Border(bottom: BorderSide(color: colors['border'])),
                ),
                child: child,
              );
              return LayoutBuilder(
                builder: (context, constraints) {
                  final available = constraints.maxWidth - 12;
                  final labelWidth = tableContext
                      ? (available * 7 / 27)
                            .clamp(110.0, double.infinity)
                            .toDouble()
                      : available / 2.3;
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: labelWidth, child: cell(label)),
                        const SizedBox(width: 12),
                        Expanded(child: cell(value)),
                      ],
                    ),
                  );
                },
              );
            },
          ),
      ],
    );
  }
}

/// The same page regions are used by the actual guarded transient route and
/// by an already hosted workspace page. The overlay gets its real caller box.
class AutomationWorkspaceOverlay extends StatelessWidget {
  const AutomationWorkspaceOverlay({
    super.key,
    required this.child,
    this.workspaceBounds,
    this.pageInsets,
  });
  final Widget child;
  final ValueGetter<Rect?>? workspaceBounds;
  final ValueGetter<EdgeInsetsGeometry>? pageInsets;
  @override
  Widget build(BuildContext context) => DeckWorkspaceOverlay(
    child: child,
    workspaceBounds: workspaceBounds,
    pageInsets: pageInsets,
  );
}

class AutomationFormPageFrame extends StatelessWidget {
  const AutomationFormPageFrame({
    super.key,
    required this.title,
    required this.child,
    this.tabs,
    this.actions = const [],
    this.description = 'Укажите параметры и проверьте их перед продолжением',
    this.eyebrow = 'Задания / Рабочее пространство',
    this.asPage = false,
    this.workspaceBounds,
    this.pageInsets,
    this.helper = const _BeforeContinue(),
  });
  final String title, description, eyebrow;
  final Widget child;
  final Widget? tabs, helper;
  final List<Widget> actions;
  final bool asPage;
  final ValueGetter<Rect?>? workspaceBounds;
  final ValueGetter<EdgeInsetsGeometry>? pageInsets;
  @override
  Widget build(BuildContext context) {
    final form = DeckPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: actions.isNotEmpty
                ? BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: deckColors(context)['border']),
                    ),
                  )
                : null,
            padding: MediaQuery.sizeOf(context).width <= 520
                ? const EdgeInsets.symmetric(horizontal: 16, vertical: 18)
                : const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Параметры',
                  style: BrandTypography.body.copyWith(
                    height: 22 / 14,
                    fontFamily: BrandAssets.semiboldFamily,
                    fontWeight: BrandTypography.semiboldWeight,
                    fontVariations: BrandTypography.semiboldVariations,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Проверьте выбранную цель и значения полей.',
                  style: BrandTypography.caption.copyWith(
                    color: deckColors(context)['muted'],
                    height: 20 / 12,
                  ),
                ),
                SizedBox(
                  height: MediaQuery.sizeOf(context).width <= 520 ? 20 : 18,
                ),
                child,
              ],
            ),
          ),
          if (actions.isNotEmpty)
            Container(
              padding: MediaQuery.sizeOf(context).width <= 520
                  ? const EdgeInsets.all(14)
                  : const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: deckColors(context)['raised'],
                border: Border(
                  top: BorderSide(color: deckColors(context)['border']),
                ),
              ),
              child: DeckFormActions(children: actions),
            ),
        ],
      ),
    );
    final page = DeckPage(
      title: title,
      description: description,
      eyebrow: eyebrow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tabs != null) ...[tabs!, const DeckTabsGap()],
          if (helper != null)
            _TwoPanels(left: form, right: helper!, form: true)
          else
            form,
        ],
      ),
    );
    return asPage
        ? page
        : AutomationWorkspaceOverlay(
            workspaceBounds: workspaceBounds,
            pageInsets: pageInsets,
            child: page,
          );
  }
}

class _BeforeContinue extends StatelessWidget {
  const _BeforeContinue({this.purpose});
  final String? purpose;
  @override
  Widget build(BuildContext context) => DeckPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: deckColors(context)['selected'],
            borderRadius: BorderRadius.circular(9),
          ),
          child: DeckIcon(
            'info',
            size: 20,
            color: deckColors(context)['accent'],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Перед продолжением',
          style: BrandTypography.body.copyWith(
            height: 22 / 14,
            fontFamily: BrandAssets.semiboldFamily,
            fontWeight: BrandTypography.semiboldWeight,
            fontVariations: BrandTypography.semiboldVariations,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          purpose ?? 'Проверьте значения и выбранный объект. Изменения, требующие выполнения на сервере, проходят через просмотр плана.',
          style: BrandTypography.caption.copyWith(
            height: 20 / 12,
            color: deckColors(context)['muted'],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Сохранение формы не заменяет подтверждение и отдельный запуск плана.',
          style: BrandTypography.caption.copyWith(
            height: 20 / 12,
            color: deckColors(context)['muted'],
          ),
        ),
      ],
    ),
  );
}

class _AutomationHero extends StatelessWidget {
  const _AutomationHero({
    super.key,
    required this.title,
    required this.state,
    required this.tone,
    this.contextLine,
  });
  final String title, state;
  final String? contextLine;
  final DeckTone tone;
  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width <= 520;
    final subtitleStyle = BrandTypography.body.copyWith(
      color: deckColors(context)['muted'],
      height: (phone ? 24 : 22) / 14,
    );
    return DeckPanel(
      padding: EdgeInsets.symmetric(
        vertical: phone ? 28 : 30,
        horizontal: phone ? 16 : 20,
      ),
      child: Column(
        children: [
          Container(
            width: phone ? 56 : 64,
            height: phone ? 56 : 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color:
                    deckColors(context)[tone == DeckTone.error
                        ? 'error'
                        : tone == DeckTone.warning
                        ? 'warning'
                        : tone == DeckTone.running
                        ? 'running'
                        : tone == DeckTone.available || tone == DeckTone.neutral
                        ? 'accent'
                        : 'unknown'],
              ),
            ),
            child: Center(
              child: DeckIcon(
                tone == DeckTone.error
                    ? 'close'
                    : tone == DeckTone.warning
                    ? 'warning'
                    : tone == DeckTone.running
                    ? 'clock'
                    : 'info',
                color:
                    deckColors(context)[tone == DeckTone.error
                        ? 'error'
                        : tone == DeckTone.warning
                        ? 'warning'
                        : tone == DeckTone.running
                        ? 'running'
                        : tone == DeckTone.unknown
                        ? 'unknown'
                        : 'accent'],
                size: 28,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: BrandTypography.title.copyWith(
              fontSize: phone ? 22 : 20,
              height: phone ? 30 / 22 : 28 / 20,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(state, textAlign: TextAlign.center, style: subtitleStyle),
                if (contextLine != null)
                  Text(
                    contextLine!,
                    textAlign: TextAlign.center,
                    style: subtitleStyle,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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

class AutomationPlanSteps extends StatelessWidget {
  const AutomationPlanSteps({
    super.key,
    required this.effects,
    required this.checks,
    this.recipes = const [],
  });
  final List<Map<String, Object?>> effects, checks, recipes;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (effects.isEmpty) const Text('Разрешённые эффекты не предоставлены'),
      for (var i = 0; i < effects.length; i++)
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            border: i == effects.length - 1
                ? null
                : Border(
                    bottom: BorderSide(color: deckColors(context)['border']),
                  ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: deckColors(context)['raised'],
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  '${i + 1}'.padLeft(2, '0'),
                  style: BrandTypography.log.copyWith(
                    fontSize: 11,
                    height: 18 / 11,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (effects[i]['kind'] == 'install_recipe')
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(
                              text:
                                  'Установить ПО по точному рецепту · версия ',
                            ),
                            TextSpan(
                              text: _value(effects[i]['version']),
                              style: BrandTypography.log,
                            ),
                          ],
                        ),
                      )
                    else
                      Text(
                        switch (effects[i]['kind']) {
                          'config_file' =>
                            'Изменить конфигурацию: ${_resource(effects[i]['resourceId'])}',
                          'service' || 'service_state' =>
                            'Изменить состояние: ${_resource(effects[i]['resourceId'])}',
                          _ =>
                            '${_value(effects[i]['kind'])} · ${_resource(effects[i]['resourceId'])}',
                        },
                        style: BrandTypography.table.copyWith(
                          fontFamily: BrandAssets.semiboldFamily,
                          fontWeight: BrandTypography.semiboldWeight,
                          fontVariations: BrandTypography.semiboldVariations,
                        ),
                      ),
                    if (effects[i]['values'] is Map) ...[
                      const SizedBox(height: 6),
                      AutomationFacts(
                        values: {
                          for (final entry in _object(
                            effects[i]['values'],
                          ).entries)
                            _field(entry.key): _value(entry.value),
                        },
                      ),
                    ],
                    for (final entry in effects[i].entries.where(
                      (entry) => const {
                        'state',
                        'enabled',
                        'arguments',
                        'operation',
                        'restart',
                        'dataLoss',
                        'downtime',
                      }.contains(entry.key),
                    ))
                      AutomationFacts(values: {entry.key: _value(entry.value)}),
                    for (final check in checks.where(
                      (row) => row['effectId'] == effects[i]['id'],
                    ))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _check(check['kind']),
                          style: BrandTypography.table.copyWith(
                            color: deckColors(context)['muted'],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      if (effects.isEmpty && checks.isNotEmpty)
        for (final check in checks) Text(_check(check['kind'])),
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

class _ParameterConstraints extends StatelessWidget {
  const _ParameterConstraints(this.values);
  final Map<String, Object?> values;
  final bool definitions = false;
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

class _AutomationExpansion extends StatelessWidget {
  const _AutomationExpansion({
    required this.title,
    this.tilePadding,
    this.childrenPadding,
    this.expandedCrossAxisAlignment,
    this.initiallyExpanded = false,
    this.children = const [],
  });
  final Widget title;
  final EdgeInsetsGeometry? tilePadding, childrenPadding;
  final CrossAxisAlignment? expandedCrossAxisAlignment;
  final bool initiallyExpanded;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: ExpansionTile(
      title: title,
      tilePadding: tilePadding,
      childrenPadding: childrenPadding,
      expandedCrossAxisAlignment: expandedCrossAxisAlignment,
      initiallyExpanded: initiallyExpanded,
      children: children,
    ),
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
  Widget build(BuildContext context) => _AutomationExpansion(
    title: DeckFocusLabel(child: Text(title)),
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.all(BrandSpacing.space12),
    expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        label: title,
        child: SizedBox(
          height: 240,
          width: double.infinity,
          child: DeckBoundedTextView(
            text: _pretty(value),
            style: BrandTypography.log,
          ),
        ),
      ),
    ],
  );
}

class _RecordStatus extends StatelessWidget {
  const _RecordStatus(this.label, {required this.symbol, required this.role});
  final String label, symbol, role;

  @override
  Widget build(BuildContext context) => DefaultTextStyle(
    style: BrandTypography.caption.copyWith(
      height: 20 / 12,
      color: deckColors(context)[role],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: SizedBox(
            width: 12,
            height: 20,
            child: Center(
              child: Text(
                symbol,
                textScaler: TextScaler.noScaling,
                style: const TextStyle(fontSize: 13, height: 20 / 13),
              ),
            ),
          ),
        ),
        const SizedBox(width: 5),
        Flexible(child: Text(label)),
      ],
    ),
  );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton(this.label, this.onPressed, {this.icon});

  final String label;
  final VoidCallback? onPressed;
  final String? icon;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    clipBehavior: Clip.none,
    onPressed: onPressed,
    child: icon == null
        ? Text(label)
        : DeckButtonLabel(icon: icon!, label: label),
  );
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
                  clipBehavior: Clip.none,
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
            clipBehavior: Clip.none,
            onPressed: onStopWaiting,
            child: const Text('Перестать ждать ответ'),
          ),
        ),
      ],
    ],
  );
}

class AutomationRecipesSection extends StatefulWidget {
  const AutomationRecipesSection({
    super.key,
    required this.catalog,
    required this.canMutate,
    required this.onCreatePlan,
    this.onSelectionChanged,
    this.serverId,
    this.serverProfiles = const [],
  });
  final Map<String, Object?> catalog;
  final bool canMutate;
  final ValueChanged<String> onCreatePlan;
  final ValueChanged<bool>? onSelectionChanged;
  final String? serverId;
  final List<ProfileView> serverProfiles;
  @override
  State<AutomationRecipesSection> createState() =>
      AutomationRecipesSectionState();
}

String automationRecipeTitle(Map<String, Object?> row) => switch (row['id']) {
  'postgresql16' => 'PostgreSQL 16',
  'clickhouse' => 'ClickHouse',
  _ => _value(row['id']),
};

class AutomationRecipesSectionState extends State<AutomationRecipesSection> {
  String? selectedDigest;
  int _selectionEpoch = 0;

  @override
  void didUpdateWidget(covariant AutomationRecipesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serverId != widget.serverId ||
        !automationTargetsUnchanged(
          [if (oldWidget.serverId != null) oldWidget.serverId!],
          oldWidget.serverProfiles,
          widget.serverProfiles,
        ) ||
        _pretty(oldWidget.catalog) != _pretty(widget.catalog)) {
      _selectionEpoch++;
    }
  }

  String? get selectedRecipeTitle {
    final row = _rows(widget.catalog['recipes'])
        .where((row) => row['digest'] == selectedDigest)
        .firstOrNull;
    return row == null ? null : automationRecipeTitle(row);
  }

  void selectFirst() {
    final first = _rows(widget.catalog['recipes']).firstOrNull;
    if (first != null) selectRecipe(first['digest'] as String);
  }

  void selectRecipe(String digest) {
    if (!_rows(widget.catalog['recipes']).any((row) => row['digest'] == digest))
      return;
    setState(() {
      if (selectedDigest != digest) _selectionEpoch++;
      selectedDigest = digest;
    });
    widget.onSelectionChanged?.call(true);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows(widget.catalog['recipes']);
    final selected = rows
        .where((row) => row['digest'] == selectedDigest)
        .firstOrNull;
    if (selected == null)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AutomationLoadedTable(
            columns: const ['Программа', 'Версия', 'Доступность', 'Назначение'],
            rows: [
              for (final row in rows)
                [
                  Text(automationRecipeTitle(row)),
                  Text(_value(row['version']), style: BrandTypography.log),
                  Text(
                    widget.catalog['installEnabled'] == true
                        ? 'Нужна проверка'
                        : 'Установка недоступна',
                  ),
                  Text(_value(row['description'])),
                ],
            ],
            onSelect: (index) => selectRecipe(rows[index]['digest'] as String),
          ),
          for (final row in _rows(widget.catalog['unavailable']))
            DeckNotice(
              title: '${automationRecipeTitle(row)}: рецепт недоступен',
              message: _code(row['code']),
              tone: DeckTone.unavailable,
            ),
          const AutomationFreshness(
            source: 'Каталог точных рецептов · локальная служба',
          ),
        ],
      );
    final enabled =
        widget.canMutate && widget.catalog['installEnabled'] == true;
    final targetId = widget.serverId;
    final targets = List<ProfileView>.unmodifiable(widget.serverProfiles);
    final target = targetId == null
        ? null
        : AutomationServerTargets.resolve(targetId, targets);
    final epoch = _selectionEpoch;
    final catalogStamp = _pretty(widget.catalog);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DeckPanel(
          title: 'Сведения',
          child: AutomationFacts(
            values: {
              'Цель': targetId == null
                  ? 'Сервер не выбран'
                  : target == null
                  ? 'Сведения о цели недоступны'
                  : '${target.name} · ${AutomationServerTargets.address(target)}',
              'Программа': automationRecipeTitle(selected),
              'Версия': _value(selected['version']),
              'Среда': selected['environment'] == 'ubuntu24.04-amd64-systemd'
                  ? 'Ubuntu 24.04 · amd64 · systemd'
                  : _value(selected['environment']),
              'Подготовка': 'Требуются точный рецепт, доверенный репозиторий и исполнитель',
              'Сеть': _value(_object(selected['initialSettings'])['listener']),
              'Данные': 'Только чистая установка; существующие данные и конфигурация блокируют запуск',
            },
          ),
        ),
        const SizedBox(height: 20),
        DeckActions(
          children: [
            const Tooltip(
              message: 'Отдельная проверка готовности реализуется в пакете установки ПО (006).',
              child: FilledButton(
                clipBehavior: Clip.none,
                onPressed: null,
                child: Text('Проверить готовность'),
              ),
            ),
            _ActionButton(
              'Создать план',
              enabled
                  ? () {
                      if (!mounted ||
                          epoch != _selectionEpoch ||
                          widget.serverId != targetId ||
                          !widget.canMutate ||
                          widget.catalog['installEnabled'] != true ||
                          _pretty(widget.catalog) != catalogStamp ||
                          !automationTargetsUnchanged(
                            [if (targetId != null) targetId],
                            targets,
                            widget.serverProfiles,
                          ))
                        return;
                      widget.onCreatePlan(selected['digest'] as String);
                    }
                  : null,
            ),
            _ActionButton('Назад', () {
              setState(() {
                _selectionEpoch++;
                selectedDigest = null;
              });
              widget.onSelectionChanged?.call(false);
            }),
          ],
        ),
        const Text(
          'Отдельная проверка готовности появится в пакете установки ПО (006). «Создать план» сохраняет профиль и план; установка требует отдельного подтверждения и запуска.',
        ),
        AutomationJsonView(
          title: 'Лицензии, начальные настройки и точные условия',
          value: selected,
        ),
      ],
    );
  }
}

class AutomationProfilesSection extends StatefulWidget {
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
    this.onSelectVersion,
  });
  final List<AutomationProfileRecord> profiles;
  final String? selectedId;
  final bool loaded, hasMore;
  final AutomationActionAvailability actions;
  final ValueChanged<String> onSelect;
  final VoidCallback onMore;
  final Widget? beforeProfiles;
  final VoidCallback? onSelectVersion;
  @override
  State<AutomationProfilesSection> createState() =>
      _AutomationProfilesSectionState();
}

class _AutomationProfilesSectionState extends State<AutomationProfilesSection> {
  int tab = 0;
  String search = '';
  @override
  Widget build(BuildContext context) {
    final rows = widget.profiles
        .where(
          (row) =>
              row.archived == (tab == 1) &&
              '${row.name} ${row.description}'.toLowerCase().contains(
                search.toLowerCase(),
              ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.beforeProfiles != null) widget.beforeProfiles!,
        DeckTabs(
          labels: const ['Активные', 'Архив'],
          selected: tab,
          onSelected: (next) => setState(() => tab = next),
        ),
        const DeckTabsGap(),
        DeckActions(
          phoneBasis: 0,
          children: [
            _ActionButton(
              'Выбрать версию',
              widget.actions.read ? widget.onSelectVersion : null,
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (!widget.loaded)
          const DeckStatus(label: 'Профили ещё не прочитаны')
        else if (rows.isEmpty)
          const DeckEmptyState(
            title: 'Ansible-профилей пока нет',
            description: 'Создайте профиль или измените фильтр. Сохранение профиля не запускает действия на сервере.',
            icon: 'terminal',
          )
        else
          AutomationLoadedTable(
            hasMore: widget.hasMore,
            onMore: widget.actions.read ? widget.onMore : null,
            columns: const ['Профиль', 'Назначение', 'Версия', 'Состояние'],
            rows: [
              for (final row in rows)
                [
                  Text(row.name),
                  Text(row.description),
                  Text(
                    '${row.headRevision}',
                    style: BrandTypography.log,
                    textAlign: TextAlign.right,
                  ),
                  _RecordStatus(
                    row.archived ? 'Архив' : 'Активен',
                    symbol: row.archived ? '○' : '✓',
                    role: row.archived ? 'muted' : 'available',
                  ),
                ],
            ],
            selected: rows.indexWhere((row) => row.id == widget.selectedId),
            onSelect: widget.actions.select
                ? (index) => widget.onSelect(rows[index].id)
                : null,
          ),
        const AutomationFreshness(source: 'Ansible-профили · локальная служба'),
        if (widget.hasMore)
          _ActionButton(
            'Ещё профили',
            widget.actions.read ? widget.onMore : null,
          ),
      ],
    );
  }
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
    final changes = _rows(_object(comparison?['result'])['changes']);
    final previousDigest = comparison?['fromDigest'];
    final currentDigest = revision['digest'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DeckPanel(
          title: 'Сведения',
          child: AutomationFacts(
            values: {
              'Профиль': '${profile.name} · версия ${revision['revision']}',
              'profileId': profile.id,
              'Сравнение': comparison == null
                  ? 'Версия для сравнения не выбрана'
                  : 'Ревизия ${comparison!['fromRevision']} → ${comparison!['toRevision']}',
              'bodyDigest исходной версии': _value(previousDigest),
              'bodyDigest выбранной версии': _value(currentDigest),
              'Автор': revision.containsKey('authorGrantId')
                  ? (revision['authorGrantId'] == null
                        ? 'Владелец'
                        : 'ИИ · ${revision['authorGrantId']}')
                  : 'Не предоставлено',
              'Изменение': comparison == null
                  ? 'Сравнение не получено'
                  : changes.isEmpty
                  ? 'В полученном сравнении изменений нет'
                  : changes.map((row) => _value(row['path'])).join(', '),
              'Разрешения': 'Для новой версии потребуется отдельное согласие',
              'Совместимость полномочий': 'Даже одинаковое содержимое новой версии не наследует право исполнения',
            },
          ),
        ),
        const SizedBox(height: 20),
        if (comparison != null) ...[
          AutomationRecordTable(
            columns: const ['Параметр', 'Было', 'Стало'],
            rows: [
              for (final row in changes)
                [
                  Text(_value(row['path'])),
                  Text(_value(row['before'])),
                  Text(_value(row['after'])),
                ],
            ],
            caption:
                'Сравнение версий ${comparison!['fromRevision']} и ${comparison!['toRevision']}',
            showFooter: false,
          ),
          if (_object(comparison!['result'])['truncated'] == true)
            const DeckNotice(
              message: 'Сравнение неполное: часть изменений не получена',
              tone: DeckTone.warning,
            ),
          const SizedBox(height: 20),
        ],
        DeckPanel(
          title: 'Точные значения',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AutomationExactValue(
                label: 'bodyDigest исходной версии',
                value: _value(previousDigest),
              ),
              const SizedBox(height: 16),
              AutomationExactValue(
                label: 'bodyDigest выбранной версии',
                value: _value(currentDigest),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        DeckActions(
          children: [
            FilledButton(
              clipBehavior: Clip.none,
              onPressed: actions.read ? onSelectVersion : null,
              child: const Text('Выбрать версию'),
            ),
            _ActionButton(
              'Проверить версию',
              actions.read ? onValidate : null,
              icon: 'refresh',
            ),
            if (hasServer && !profile.archived)
              _ActionButton(
                'Создать план',
                actions.mutate ? onCreatePlan : null,
              ),
            _ActionButton('Сравнить версии', actions.read ? onCompare : null),
            if (!profile.archived) ...[
              _ActionButton('Изменить профиль', actions.mutate ? onEdit : null),
              if (hasServer)
                _ActionButton(
                  'Делегировать версию',
                  actions.mutate ? onDelegate : null,
                ),
              _ActionButton('Архивировать', actions.mutate ? onArchive : null),
            ],
          ],
        ),
        if (!hasServer)
          const DeckNotice(
            message: 'Создавать и проверять профиль можно без сервера. Для плана и запуска выберите сервер.',
            tone: DeckTone.neutral,
          ),
        if (validation != null) _Validation(validation!),
        AutomationJsonView(title: 'Шаги и параметры', value: revision['body']),
      ],
    );
  }
}

class AutomationExactValue extends StatelessWidget {
  const AutomationExactValue({
    super.key,
    required this.label,
    required this.value,
  });
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: BrandTypography.button),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: deckColors(context)['bg'],
          border: Border.all(color: deckColors(context)['border']),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SelectableText(
          value,
          style: BrandTypography.log.copyWith(
            color: deckColors(context)['accent'],
          ),
        ),
      ),
    ],
  );
}

class AutomationFreshness extends StatelessWidget {
  const AutomationFreshness({super.key, required this.source, this.observedAt});
  final String source;
  final String? observedAt;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DeckIcon('clock', size: 12, color: deckColors(context)['muted']),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                observedAt == null
                    ? 'Время снимка не предоставлено'
                    : 'Снимок данных · $observedAt',
                style: BrandTypography.caption.copyWith(
                  color: deckColors(context)['muted'],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          source,
          style: BrandTypography.caption.copyWith(
            color: deckColors(context)['muted'],
          ),
        ),
      ],
    ),
  );
}

/// Readonly projection of an owner's validated blocked record. A reason is
/// never interpreted as evidence of a particular protected client or effect.
@immutable
class BlockedPlanDisplay {
  const BlockedPlanDisplay._({
    required this.plan,
    required this.reasons,
    required this.sourceSteps,
  });
  final Map<String, Object?> plan;
  final List<Map<String, Object?>> reasons, sourceSteps;
  static BlockedPlanDisplay? tryCreate(
    Map<String, Object?> plan, {
    required bool targetMatches,
    required bool expired,
    required bool invalidated,
  }) {
    if (!targetMatches ||
        expired ||
        invalidated ||
        plan['status'] != 'blocked' ||
        plan['id'] is! String ||
        plan['serverId'] is! String ||
        plan['profileId'] is! String ||
        plan['profileRevision'] is! int ||
        plan['profileDigest'] is! String ||
        plan['createdAt'] is! String ||
        plan['expiresAt'] is! String)
      return null;
    if (plan['reasons'] is! List ||
        plan['effects'] is! List ||
        plan['checks'] is! List ||
        (plan['effects'] as List).isNotEmpty ||
        (plan['checks'] as List).isNotEmpty)
      return null;
    final reasons = _rows(plan['reasons']);
    if (reasons.isEmpty ||
        reasons.length != (plan['reasons'] as List).length ||
        reasons.any(
          (reason) =>
              reason['code'] is! String ||
              reason['field'] is! String ||
              reason['stepId'] != null && reason['stepId'] is! String,
        ))
      return null;
    final snapshot = _readonlyPlanValue(plan) as Map<String, Object?>;
    final ids = reasons.map((row) => row['stepId']).whereType<String>().toSet();
    return BlockedPlanDisplay._(
      plan: Map.unmodifiable(snapshot),
      reasons: List.unmodifiable(
        _rows(snapshot['reasons'])
            .map((row) => Map<String, Object?>.unmodifiable(row)),
      ),
      sourceSteps: List.unmodifiable(
        _rows(snapshot['desired'])
            .where((step) => ids.contains(step['id']))
            .map((row) => Map<String, Object?>.unmodifiable(row)),
      ),
    );
  }
}

Object? _readonlyPlanValue(Object? value) => switch (value) {
  Map() => Map<String, Object?>.unmodifiable(
    value.map((key, child) => MapEntry('$key', _readonlyPlanValue(child))),
  ),
  List() => List<Object?>.unmodifiable(value.map(_readonlyPlanValue)),
  _ => value,
};

class AutomationPlanSection extends StatefulWidget {
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
    this.sourceRevision,
    this.onEditSource,
    this.onClose,
    this.currentServerId,
    this.historical = false,
    this.showPreflight = false,
    this.onViewPlan,
    this.onShowAuthorities,
    this.allowApply = true,
    this.showRefresh = true,
  });
  final Map<String, Object?> plan;
  final bool runnable,
      expired,
      historical,
      showPreflight,
      allowApply,
      showRefresh;
  final AutomationActionAvailability actions;
  final Key? planAnchor;
  final String? invalidReason, currentServerId;
  final List<ProfileView> serverProfiles;
  final AutomationProfileRecord? automationProfile;
  final Map<String, Object?>? sourceRevision;
  final VoidCallback onApprove, onDeny, onApply, onRefresh;
  final VoidCallback? onEditSource, onClose, onViewPlan, onShowAuthorities;
  @override
  State<AutomationPlanSection> createState() => _AutomationPlanSectionState();
}

class _AutomationPlanSectionState extends State<AutomationPlanSection> {
  bool showReasons = false,
      showSource = false,
      showPrevious = false,
      viewedPlan = false;
  int tab = 0;
  @override
  void didUpdateWidget(covariant AutomationPlanSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plan['id'] != widget.plan['id']) {
      showReasons = showSource = showPrevious = false;
      viewedPlan = false;
      tab = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.plan;
    final targetMatches =
        automationPlanTargetAvailable(p, widget.serverProfiles) &&
        (widget.currentServerId == null ||
            widget.currentServerId == p['serverId']);
    final blocked = BlockedPlanDisplay.tryCreate(
      p,
      targetMatches: targetMatches,
      expired: widget.expired,
      invalidated: widget.invalidReason != null,
    );
    final invalid = widget.expired || widget.invalidReason != null;
    final source = widget.sourceRevision;
    final exactSource =
        source != null &&
        source['profileId'] == p['profileId'] &&
        source['revision'] == p['profileRevision'] &&
        source['digest'] == p['profileDigest'];
    final sourceMatches =
        targetMatches &&
        exactSource &&
        _matchingProfile(p, widget.automationProfile) != null &&
        widget.automationProfile?.archived == false;
    final title = invalid
        ? 'План требует новой проверки'
        : blocked != null
        ? 'План заблокирован'
        : 'Подтверждение плана';
    final target = AutomationServerTargets.resolve(
      '${p['serverId']}',
      widget.serverProfiles,
      expectedIdentity: _planIdentity(p),
    );
    final state = invalid
        ? (widget.expired ? 'Срок плана истёк' : 'План больше не действует')
        : blocked != null
        ? 'Исполнение не разрешено'
        : widget.runnable
        ? 'План готов к подтверждению'
        : 'План недоступен для исполнения';
    if (invalid) {
      final targetLabel = target == null
          ? 'Сведения о цели недоступны'
          : '${target.name} · ${AutomationServerTargets.address(target)}';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AutomationHero(
            key: widget.planAnchor,
            title: title,
            state: 'Состояние: $state',
            tone: DeckTone.warning,
            contextLine: 'Цель: $targetLabel',
          ),
          SizedBox(height: deckSectionGap(context)),
          const DeckNotice(
            title: 'Следующий шаг',
            message: 'Создать новый план и просмотреть актуальные эффекты',
            tone: DeckTone.warning,
          ),
          SizedBox(height: deckSectionGap(context)),
          DeckPanel(
            title: 'Параметры и условия',
            child: AutomationFacts(
              values: {
                'Цель': targetLabel,
                'План':
                    _matchingProfile(p, widget.automationProfile)?.name ??
                    _value(p['id']),
                'Состояние': state,
                'Причина': widget.invalidReason ?? 'Срок плана истёк',
                'Ранее выданное согласие': 'Не действует для новой проверки',
                'Следующий шаг':
                    'Создать новый план и просмотреть актуальные эффекты',
                'planId': _value(p['id']),
                'Digest плана': _value(p['digest']),
                'Исходная версия': _value(p['profileRevision']),
              },
            ),
          ),
          SizedBox(height: deckSectionGap(context)),
          const DeckPanel(
            title: 'Последствия',
            child: AutomationFacts(
              values: {
                'Следующий шаг':
                    'Создать новый план и просмотреть актуальные эффекты',
              },
            ),
          ),
          SizedBox(height: deckSectionGap(context)),
          DeckActions(
            children: [
              FilledButton(
                clipBehavior: Clip.none,
                onPressed: sourceMatches && widget.actions.mutate
                    ? widget.onEditSource
                    : null,
                child: const Text('Создать новый план'),
              ),
              _ActionButton(
                'Просмотреть прежний план',
                () => setState(() => showPrevious = !showPrevious),
              ),
              _ActionButton('Закрыть', widget.onClose),
            ],
          ),
          if (showPrevious) ...[
            AutomationJsonView(
              title: 'Неизменный план и технические детали',
              value: p,
            ),
            _ActionButton(
              'Обновить план',
              widget.actions.read ? widget.onRefresh : null,
            ),
          ],
        ],
      );
    }
    if (widget.showPreflight &&
        !viewedPlan &&
        !invalid &&
        blocked == null &&
        p['preflight'] is Map) {
      final preflight = _object(p['preflight']);
      return _Section(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AutomationHero(
              key: widget.planAnchor,
              title: 'Проверка готовности к установке',
              state: state,
              tone: widget.runnable ? DeckTone.available : DeckTone.warning,
              contextLine: target == null
                  ? 'Цель: сведения недоступны'
                  : 'Цель: ${target.name} · ${AutomationServerTargets.address(target)}',
            ),
            SizedBox(height: deckSectionGap(context)),
            _TwoPanels(
              left: DeckPanel(
                title: 'Состав плана и проверки',
                padding: EdgeInsets.zero,
                child: AutomationPlanSteps(
                  effects: _rows(p['effects']),
                  checks: _rows(p['checks']),
                  recipes: _rows(preflight['recipes']),
                ),
              ),
              right: DeckPanel(
                title: 'Параметры плана',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AutomationFacts(
                      values: {
                        'Цель': target == null
                            ? 'Сведения о цели недоступны'
                            : '${target.name} · ${AutomationServerTargets.address(target)}',
                        'Итог': state,
                        'Среда': _value(preflight['environment']),
                        'Исполнитель': _value(preflight['runtimeVersion']),
                        'planId': _value(p['id']),
                        'Digest плана': _value(p['digest']),
                        'Наблюдение': _value(p['createdAt']),
                        'Срок': _time(p['expiresAt']),
                        for (final entry in _object(p['exactParams']).entries)
                          entry.key: _value(entry.value),
                      },
                    ),
                    const Text(
                      'Полученный план содержит разрешённые эффекты и будущие проверки результата. Нового чтения сервера при просмотре не выполняется.',
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: deckSectionGap(context)),
            DeckActions(
              children: [
                FilledButton(
                  clipBehavior: Clip.none,
                  onPressed: () {
                    setState(() => viewedPlan = true);
                    widget.onViewPlan?.call();
                  },
                  child: const Text('Просмотреть план'),
                ),
                const Tooltip(
                  message: 'Отдельная проверка и обновление готовности реализуется в пакете установки ПО (006).',
                  child: OutlinedButton(
                    clipBehavior: Clip.none,
                    onPressed: null,
                    child: Text('Обновить проверку'),
                  ),
                ),
              ],
            ),
            const Text(
              'Отдельная проверка и обновление готовности реализуется в пакете установки ПО (006).',
            ),
            AutomationJsonView(
              title: 'Полученный результат проверки и план',
              value: p,
            ),
          ],
        ),
      );
    }
    return _Section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!invalid && blocked == null) ...[
            DeckTabs(
              labels: const [
                'План',
                'Запросы владельцу',
                'Устарел / истёк срок',
              ],
              selected: tab,
              onSelected: (next) {
                setState(() => tab = next);
                if (next == 1) widget.onShowAuthorities?.call();
              },
            ),
            const DeckTabsGap(),
          ],
          if (blocked != null)
            _AutomationHero(
              key: widget.planAnchor,
              title: title,
              state: state,
              tone: DeckTone.error,
              contextLine: target == null
                  ? 'Цель: сведения недоступны'
                  : 'Цель: ${target.name} · ${AutomationServerTargets.address(target)}',
            ),
          if (blocked != null) SizedBox(height: deckSectionGap(context)),
          if (widget.historical)
            const DeckNotice(
              message: 'Исторический план: запись не является результатом сегодняшней проверки.',
              tone: DeckTone.warning,
            ),
          if (invalid) ...[
            DeckNotice(
              title: 'Нужна новая проверка',
              message:
                  widget.invalidReason ??
                  'Создайте новый план. Прежний план нельзя запустить.',
              nextStep:
                  'Ранее выданное согласие не действует для нового плана.',
              tone: DeckTone.warning,
            ),
            SizedBox(height: deckSectionGap(context)),
          ],
          if (blocked != null) ...[
            const DeckNotice(
              title: 'Причина',
              message: 'План заблокирован по причинам, полученным от сервиса. Сведения о конкретном защищённом эффекте не предоставлены.',
              tone: DeckTone.error,
            ),
            SizedBox(height: deckSectionGap(context)),
            _TwoPanels(
              left: DeckPanel(
                title: 'Состав плана и проверки',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Сервис не предоставил разрешённые эффекты и проверки для заблокированного плана.',
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      clipBehavior: Clip.none,
                      onPressed: () =>
                          setState(() => showReasons = !showReasons),
                      child: const Text('Просмотреть причины'),
                    ),
                    if (showReasons)
                      for (final reason in blocked.reasons) ...[
                        const Divider(height: 24),
                        DeckKeyValue(
                          label: 'Код',
                          value: _value(reason['code']),
                          selectable: true,
                        ),
                        Text(_code(reason['code'])),
                        DeckKeyValue(
                          label: 'Поле',
                          value: _value(reason['field']),
                        ),
                        DeckKeyValue(
                          label: 'Исходный шаг',
                          value: _value(reason['stepId']),
                        ),
                      ],
                    if (blocked.sourceSteps.isNotEmpty) ...[
                      OutlinedButton(
                        clipBehavior: Clip.none,
                        onPressed: () =>
                            setState(() => showSource = !showSource),
                        child: const Text('Открыть исходный шаг'),
                      ),
                      if (showSource) ...[
                        const Text(
                          'Исходный запрос; это не доказанный и не разрешённый эффект.',
                        ),
                        for (final step in blocked.sourceSteps) _Values(step),
                      ],
                    ],
                  ],
                ),
              ),
              right: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DeckPanel(
                    title: 'Параметры плана',
                    child: AutomationFacts(
                      values: {
                        'Цель': target == null
                            ? 'Сведения о цели недоступны'
                            : '${target.name} · ${AutomationServerTargets.address(target)}',
                        'Состояние плана': state,
                        'planId': _value(p['id']),
                        'Причины': _pretty(blocked.reasons),
                        'Создан': _value(p['createdAt']),
                        'Источник': exactSource
                            ? _value(source['digest'])
                            : 'Точная исходная версия недоступна',
                        'Найденный эффект': 'Сведения о конкретном защищённом эффекте не предоставлены',
                        for (final entry in _object(p['exactParams']).entries)
                          entry.key: _value(entry.value),
                      },
                    ),
                  ),
                  SizedBox(height: deckSectionGap(context)),
                  const DeckPanel(
                    title: 'Последствия и условия',
                    child: Text(
                      'Исполнение не разрешено. Сервис не передал идентичность эффекта.',
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: deckSectionGap(context)),
            DeckActions(
              children: [
                const Tooltip(
                  message: 'Сервис не передал идентичность эффекта',
                  child: FilledButton(
                    clipBehavior: Clip.none,
                    onPressed: null,
                    child: Text('Открыть запрещённый эффект'),
                  ),
                ),
                _ActionButton(
                  'Изменить исходный запрос',
                  sourceMatches && widget.actions.mutate
                      ? widget.onEditSource
                      : null,
                ),
                _ActionButton('Закрыть план', widget.onClose),
              ],
            ),
            if (!sourceMatches || !widget.actions.mutate)
              const Text(
                'Изменение недоступно: нет точной исходной версии или действующего права записи.',
              ),
          ] else if (tab == 1 && !invalid) ...[
            const DeckPanel(
              title: 'Запросы владельцу',
              child: Text(
                'Точное подтверждение выбранного плана выполняется отдельным действием. Текущее согласие не переносится на новый план.',
              ),
            ),
          ] else if (tab == 2 && !invalid) ...[
            const DeckPanel(
              title: 'Устарел / истёк срок',
              child: Text(
                'После изменения цели, доступа, доверия или истечения срока создайте новый план. Просмотр плана не обновляет согласие.',
              ),
            ),
          ] else ...[
            _TwoPanels(
              left: DeckPanel(
                title: 'Состав плана и проверки',
                padding: EdgeInsets.zero,
                child: AutomationPlanSteps(
                  effects: _rows(p['effects']),
                  checks: _rows(p['checks']),
                  recipes: _rows(_object(p['preflight'])['recipes']),
                ),
              ),
              right: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DeckPanel(
                    title: 'Параметры плана',
                    child: AutomationFacts(
                      values: {
                        'Цель': target == null
                            ? 'Сведения о цели недоступны'
                            : '${target.name} · ${AutomationServerTargets.address(target)}',
                        'Операция':
                            _matchingProfile(p, widget.automationProfile) ==
                                null
                            ? 'Название профиля недоступно'
                            : '${widget.automationProfile!.name} · версия ${p['profileRevision']}',
                        'Срок плана': _time(p['expiresAt']),
                        'Перерыв': 'Сервис не предоставил отдельную оценку',
                        'Эффекты': _rows(p['effects']).isEmpty
                            ? 'Не предоставлены'
                            : _rows(p['effects'])
                                  .map((row) => _value(row['kind']))
                                  .join(', '),
                        'Критерий успеха': _rows(p['checks']).isEmpty
                            ? 'Не предоставлен'
                            : _rows(p['checks'])
                                  .map((row) => _check(row['kind']))
                                  .join(', '),
                        'При изменении или expiry':
                            'Потребуется новая проверка и новый просмотр плана',
                        'planId': _value(p['id']),
                        'Digest плана': _value(p['digest']),
                        'profileId': _value(p['profileId']),
                        'revision': _value(p['profileRevision']),
                        'bodyDigest': _value(p['profileDigest']),
                        for (final entry in _object(p['exactParams']).entries)
                          entry.key: _value(entry.value),
                      },
                    ),
                  ),
                  SizedBox(height: deckSectionGap(context)),
                  const DeckPanel(
                    title: 'Последствия и условия',
                    child: Text(
                      'Подтверждение сохраняет согласие на этот точный план. Запуск задания выполняется отдельно.',
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: deckSectionGap(context)),
            for (final reason in _rows(p['reasons']))
              Text(_code(reason['code'])),
            if (!targetMatches ||
                _matchingProfile(p, widget.automationProfile) == null)
              const DeckNotice(
                message: 'Не удалось проверить цель и профиль плана',
                nextStep: 'Обновите локальные профили и план перед подтверждением или запуском.',
                tone: DeckTone.warning,
              ),
            DeckActions(
              children: [
                if (widget.runnable && !invalid) ...[
                  FilledButton(
                    clipBehavior: Clip.none,
                    child: const Text('Подтвердить план'),
                    onPressed:
                        widget.actions.mutate &&
                            targetMatches &&
                            _matchingProfile(p, widget.automationProfile) !=
                                null
                        ? widget.onApprove
                        : null,
                  ),
                  _ActionButton(
                    'Отклонить план',
                    widget.actions.mutate ? widget.onDeny : null,
                  ),
                  if (widget.allowApply)
                    FilledButton(
                      clipBehavior: Clip.none,
                      onPressed:
                          widget.actions.mutate &&
                              targetMatches &&
                              _matchingProfile(p, widget.automationProfile) !=
                                  null
                          ? widget.onApply
                          : null,
                      child: const Text('Запустить'),
                    ),
                ],
                if (invalid) ...[
                  _ActionButton(
                    'Создать новый план',
                    sourceMatches && widget.actions.mutate
                        ? widget.onEditSource
                        : null,
                  ),
                  _ActionButton(
                    'Просмотреть прежний план',
                    () => setState(() => showPrevious = !showPrevious),
                  ),
                  _ActionButton('Закрыть', widget.onClose),
                ],
                if (widget.onClose != null)
                  _ActionButton('Назад', widget.onClose),
                if (widget.showRefresh)
                  _ActionButton(
                    'Обновить план',
                    widget.actions.read ? widget.onRefresh : null,
                  ),
              ],
            ),
          ],
          if (!invalid || showPrevious)
            AutomationJsonView(
              title: 'Неизменный план и технические детали',
              value: p,
            ),
        ],
      ),
    );
  }
}

class AutomationJobsSection extends StatefulWidget {
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
    this.serverProfiles = const [],
    this.onDetailChanged,
    this.showHeaderActions = true,
    this.scopeSelector,
    this.onOpenServers,
  });
  final List<Map<String, Object?>> jobs, events;
  final Map<String, Object?>? job;
  final String? serverId;
  final List<ProfileView> serverProfiles;
  final ValueChanged<bool>? onDetailChanged;
  final Widget? scopeSelector;
  final VoidCallback? onOpenServers;
  final bool showHeaderActions;
  final bool loaded, hasMore, canCancel, canReconcile;
  final int droppedEvents;
  final AutomationActionAvailability actions;
  final VoidCallback onRefresh,
      onRefreshAuthorities,
      onMore,
      onShowPlan,
      onCancel,
      onReconcile;
  final ValueChanged<String> onSelect;
  @override
  State<AutomationJobsSection> createState() => _AutomationJobsSectionState();
}

class _AutomationJobsSectionState extends State<AutomationJobsSection> {
  late bool showDetail = widget.job != null;
  int tab = 0;
  String search = '';
  String? stateFilter;
  bool filters = false;
  late bool eventsVisible = !const {
    'unknown',
    'cancel-requested',
  }.contains(widget.job?['state']);
  @override
  void didUpdateWidget(covariant AutomationJobsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.job?['id'] != widget.job?['id']) {
      eventsVisible = !const {
        'unknown',
        'cancel-requested',
      }.contains(widget.job?['state']);
      showDetail = widget.job != null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final outcome = _object(job?['outcome']);
    final rows = widget.jobs
        .map((row) => _object(row['job']))
        .where(
          (row) =>
              (tab == 0 ||
                  tab == 1 &&
                      const {
                        'queued',
                        'running',
                        'reconciling',
                        'cancel-requested',
                      }.contains(row['state']) ||
                  tab == 2 &&
                      const {
                        'failed',
                        'unknown',
                        'cancel-requested',
                        'cancelled',
                      }.contains(row['state'])) &&
              (stateFilter == null || row['state'] == stateFilter) &&
              '${row['id']} ${row['profileId']} ${row['state']}'
                  .toLowerCase()
                  .contains(search.toLowerCase()),
        )
        .toList();
    final target = AutomationServerTargets.resolve(
      widget.serverId ?? '',
      widget.serverProfiles,
    );
    final contextLine = target == null
        ? 'Сервер: ${widget.serverId ?? 'не выбран'}'
        : '${target.name} · ${AutomationServerTargets.address(target)}';
    final phoneTimeline = MediaQuery.sizeOf(context).width <= 520;
    final ordinal = TextPainter(
      text: TextSpan(
        text: '8' * widget.events.length.toString().length,
        style: BrandTypography.caption,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final minimumMarker = phoneTimeline ? 23.0 : 25.0;
    final markerSize = [
      minimumMarker,
      ordinal.width + 2,
      ordinal.height + 2,
    ].reduce((a, b) => a > b ? a : b);
    final markerColumn = markerSize > 25 ? markerSize : 25.0;
    ordinal.dispose();
    Widget eventTimeline() => DeckPanel(
      title: 'Ход выполнения',
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.events.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('События пока не получены'),
            ),
          for (var i = 0; i < widget.events.length; i++)
            Builder(
              builder: (context) {
                final event = widget.events[i];
                final success = event['checkResult'] == 'passed';
                final role = success
                    ? 'available'
                    : event['state'] == 'running'
                    ? 'running'
                    : 'unknown';
                final stamp = DateTime.tryParse('${event['timestamp']}')
                    ?.toUtc();
                final clock = stamp == null
                    ? 'Не предоставлено'
                    : '${stamp.hour.toString().padLeft(2, '0')}:${stamp.minute.toString().padLeft(2, '0')}:${stamp.second.toString().padLeft(2, '0')}';
                final title = event['kind'] == 'state'
                    ? 'Состояние задания'
                    : event['kind'] == 'dropped'
                    ? 'Пропуски событий'
                    : event['stepId'] == null
                    ? 'Ход задания'
                    : _value(event['stepId']);
                final detail = event['kind'] == 'dropped'
                    ? 'Пропущено событий: ${_value(event['droppedCount'])}'
                    : event['kind'] == 'state'
                    ? _jobState(event['state'])
                    : event['checkResult'] != null
                    ? 'Результат: ${_result(event['checkResult'])}'
                    : _value(event['safeCode']);
                final phone = MediaQuery.sizeOf(context).width <= 520;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (i + 1 < widget.events.length)
                      Positioned(
                        key: ValueKey('job-timeline-line-$i'),
                        left: (phone ? 14 : 20) + markerSize / 2 - .5,
                        top: (phone ? 14 : 12) + markerSize - 3,
                        bottom: -10,
                        width: 1,
                        child: ColoredBox(color: deckColors(context)['border']),
                      ),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: phone ? 14 : 20,
                        vertical: phone ? 14 : 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: markerColumn,
                            child: Align(
                              alignment: Alignment.topLeft,
                              heightFactor: 1,
                              child: Container(
                                key: ValueKey('job-timeline-marker-$i'),
                                width: markerSize,
                                height: markerSize,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: deckColors(
                                    context,
                                  )[success ? 'selected' : 'raised'],
                                  border: Border.all(
                                    color: deckColors(context)[role],
                                  ),
                                ),
                                child: success
                                    ? DeckIcon(
                                        'check',
                                        size: 13,
                                        color: deckColors(context)[role],
                                      )
                                    : Text(
                                        '${i + 1}',
                                        style: BrandTypography.caption.copyWith(
                                          color: deckColors(context)[role],
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          SizedBox(width: phone ? 10 : 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  title,
                                  style: BrandTypography.table.copyWith(
                                    fontFamily: BrandAssets.semiboldFamily,
                                    fontWeight: BrandTypography.semiboldWeight,
                                    fontVariations:
                                        BrandTypography.semiboldVariations,
                                  ),
                                ),
                                Text(
                                  detail,
                                  style: BrandTypography.caption.copyWith(
                                    color: deckColors(context)['muted'],
                                    height: 20 / 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: phone ? 10 : 12),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: phone ? 58 : double.infinity,
                            ),
                            child: Tooltip(
                              message: _time(event['timestamp']),
                              child: Text(
                                clock,
                                textAlign: TextAlign.right,
                                style: BrandTypography.log.copyWith(
                                  fontSize: 12,
                                  height: 20 / 12,
                                  color: deckColors(context)['muted'],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
    if (showDetail &&
        job != null &&
        (job['state'] == 'unknown' || job['cancelRequested'] == true)) {
      final unknown = job['state'] == 'unknown';
      final effects = switch (outcome['effects']) {
        'none' => 'Подтверждено отсутствие изменений',
        'confirmed' => 'Изменения подтверждены',
        'uncertain' => 'Возможны неподтверждённые изменения',
        _ => 'Не предоставлено',
      };
      final last = widget.events.lastOrNull;
      final lastText = last == null
          ? 'Не предоставлено'
          : '${_value(last['kind'])} · ${_value(last['stepId'])} · ${_time(last['timestamp'])}';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AutomationHero(
            title: unknown ? 'Неизвестный исход задания' : 'Остановка задания',
            state: unknown
                ? 'Состояние: Исход не подтверждён'
                : 'Состояние: Остановка запрошена',
            tone: unknown ? DeckTone.unknown : DeckTone.warning,
          ),
          SizedBox(height: deckSectionGap(context)),
          if (unknown) ...[
            const DeckNotice(
              title: 'Следующий шаг',
              message: 'Проверить прежнее задание',
              tone: DeckTone.warning,
            ),
            SizedBox(height: deckSectionGap(context)),
          ],
          DeckPanel(
            title: 'Контекст и проверка результата',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AutomationFacts(
                  values: unknown
                      ? {
                          'Задание': _value(job['id']),
                          'Цель': contextLine,
                          'Состояние': 'Исход не подтверждён',
                          'Последнее событие': lastText,
                          'Следующий шаг': 'Проверить прежнее задание',
                          'Ограничение':
                              'Новые конфликтующие изменения заблокированы',
                          'Повтор': 'Новый apply не запускается; проверяется прежний job',
                          'Изменения': effects,
                        }
                      : {
                          'Цель': contextLine,
                          'Состояние': 'Остановка запрошена',
                          'jobId': _value(job['id']),
                          'planId': _value(job['immutablePlanId']),
                          'cancelRequested': switch (job['cancelRequested']) {
                            true => 'Остановка запрошена',
                            false => 'Остановка не запрошена',
                            _ => 'Состояние запроса не получено',
                          },
                          'Текущий шаг': 'Не предоставлено',
                          'Уже выполнено': effects,
                          'Последствие': 'Автоматический откат не обещается',
                        },
                ),
                if (_rows(outcome['checks']).isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Проверки результата',
                    style: BrandTypography.button,
                  ),
                  for (final check in _rows(outcome['checks']))
                    Text(
                      '${_value(check['stepId'])} · ${_value(check['checkId'])}: ${_result(check['result'])}',
                    ),
                ],
              ],
            ),
          ),
          SizedBox(height: deckSectionGap(context)),
          DeckActions(
            children: [
              if (unknown) ...[
                FilledButton(
                  clipBehavior: Clip.none,
                  onPressed: widget.actions.mutate && widget.canReconcile
                      ? widget.onReconcile
                      : null,
                  child: const Text('Уточнить результат'),
                ),
                _ActionButton(
                  'Открыть план',
                  widget.actions.read ? widget.onShowPlan : null,
                ),
              ] else
                FilledButton(
                  clipBehavior: Clip.none,
                  onPressed: widget.actions.read
                      ? () => widget.onSelect(job['id'] as String)
                      : null,
                  child: const Text('Обновить состояние'),
                ),
              _ActionButton(
                unknown ? 'Показать события' : 'Открыть события',
                () => setState(() => eventsVisible = !eventsVisible),
              ),
            ],
          ),
          if (eventsVisible) ...[
            SizedBox(height: deckSectionGap(context)),
            eventTimeline(),
            DeckStatus(
              label:
                  'Получено событий: ${widget.events.length}. Пропущено в источнике: ${widget.droppedEvents}',
              tone: widget.droppedEvents > 0
                  ? DeckTone.warning
                  : DeckTone.neutral,
            ),
          ],
          AutomationJsonView(title: 'Результат и проверки задания', value: job),
          TextButton(
            clipBehavior: Clip.none,
            onPressed: () {
              setState(() => showDetail = false);
              widget.onDetailChanged?.call(false);
            },
            child: const Text('К заданиям'),
          ),
        ],
      );
    }
    return _Section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!showDetail) ...[
            DeckTabs(
              labels: const ['Все', 'Выполняются', 'Требуют внимания'],
              selected: tab,
              onSelected: (next) => setState(() => tab = next),
            ),
            const DeckTabsGap(),
            DeckPanel(
              title: 'Область просмотра',
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.sizeOf(context).width <= 520 ? 16 : 18,
                vertical: 12,
              ),
              trailing: widget.scopeSelector == null
                  ? null
                  : TextButton(
                      clipBehavior: Clip.none,
                      onPressed: () => showMotionDialog<void>(
                        context: context,
                        barrierDismissible: true,
                        builder: (_) => DeckDialogLayout(
                          title: 'Область просмотра',
                          child: widget.scopeSelector!,
                        ),
                      ),
                      child: const Text('Выбрать сервер'),
                    ),
              child: AutomationFacts(
                tableContext: true,
                values: {'Область': contextLine},
              ),
            ),
            SizedBox(height: MediaQuery.sizeOf(context).width <= 520 ? 16 : 20),
            DeckActions(
              phoneBasis: 130,
              children: [
                if (widget.showHeaderActions)
                  _ActionButton(
                    'Обновить задания',
                    widget.actions.read ? widget.onRefresh : null,
                  ),
                if (widget.showHeaderActions)
                  _ActionButton(
                    'Обновить разрешения',
                    widget.actions.read ? widget.onRefreshAuthorities : null,
                  ),
                OutlinedButton(
                  clipBehavior: Clip.none,
                  onPressed: widget.serverId == null
                      ? null
                      : () => setState(() => filters = !filters),
                  child: const Text('Фильтры'),
                ),
              ],
            ),
            if (filters) ...[
              const SizedBox(height: 12),
              DeckPanel(
                title: 'Фильтры заданий',
                child: DropdownButtonFormField<String>(
                  initialValue: stateFilter ?? '',
                  decoration: const InputDecoration(
                    labelText: 'Состояние задания',
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Все состояния'),
                    ),
                    for (final state in {
                      if (stateFilter != null) stateFilter!,
                      ...widget.jobs
                          .map((row) => _object(row['job'])['state'])
                          .whereType<String>(),
                    })
                      DropdownMenuItem(
                        value: state,
                        child: Text(_jobState(state)),
                      ),
                  ],
                  onChanged: (next) =>
                      setState(() => stateFilter = next == '' ? null : next),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Фильтры применяются к полученной странице этого сервера. Общая история всех серверов пока недоступна.',
              ),
            ],
            const SizedBox(height: 18),
            if (widget.serverId == null)
              DeckEmptyState(
                title: 'Выберите сервер',
                description: 'Задания доступны в контексте конкретного сервера. Общая история всех серверов пока недоступна. Выберите сервер в области просмотра или добавьте первое подключение.',
                icon: 'jobs',
                actions: [
                  if (widget.onOpenServers != null)
                    FilledButton(
                      clipBehavior: Clip.none,
                      onPressed: widget.onOpenServers,
                      child: const Text('К серверам'),
                    ),
                ],
              )
            else if (!widget.loaded)
              const DeckStatus(label: 'Задания ещё не прочитаны')
            else if (rows.isEmpty)
              const DeckEmptyState(
                title: 'Заданий на этом сервере пока нет',
                description: 'Обновите задания или измените локальный фильтр.',
                icon: 'jobs',
              )
            else
              AutomationLoadedTable(
                hasMore: widget.hasMore,
                onMore: widget.actions.read ? widget.onMore : null,
                columns: const [
                  'Задание',
                  'Операция',
                  'Источник',
                  'Состояние',
                  'Начало',
                ],
                rows: [
                  for (final row in rows)
                    [
                      Text(_value(row['id']), style: BrandTypography.log),
                      Text(
                        'Профиль ${_value(row['profileId'])} · v${_value(row['profileRevision'])}',
                      ),
                      Text(
                        row['grantId'] == null
                            ? 'Владелец'
                            : 'ИИ · ${row['grantId']}',
                      ),
                      DeckStatus(
                        label: _jobState(row['state']),
                        tone: _jobTone(row['state']),
                      ),
                      Text(_time(row['createdAt'])),
                    ],
                ],
                selected: rows.indexWhere((row) => row['id'] == job?['id']),
                onSelect: widget.actions.select
                    ? (index) {
                        widget.onSelect(rows[index]['id'] as String);
                        setState(() => showDetail = true);
                        widget.onDetailChanged?.call(true);
                      }
                    : null,
                footer: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Text(
                      'Получено: ${widget.jobs.length} · только выбранный сервер',
                    ),
                    if (widget.hasMore)
                      _ActionButton(
                        'Ещё задания',
                        widget.actions.read ? widget.onMore : null,
                      ),
                  ],
                ),
              ),
          ],
          if (job != null && showDetail) ...[
            _AutomationHero(
              title: job['state'] == 'unknown'
                  ? 'Неизвестный исход задания'
                  : job['cancelRequested'] == true
                  ? 'Остановка задания'
                  : 'Ход задания',
              state: 'Состояние: ${_jobState(job['state'])}',
              tone: _jobTone(job['state']),
            ),
            SizedBox(height: deckSectionGap(context)),
            if (job['state'] == 'unknown') ...[
              const DeckNotice(
                title: 'Исход не подтверждён',
                message: 'На сервере могли произойти изменения. Уточните результат перед следующим действием.',
                tone: DeckTone.unknown,
              ),
              SizedBox(height: deckSectionGap(context)),
            ],
            if (job['cancelRequested'] == true) ...[
              const DeckNotice(
                message: 'Остановка запрошена. Текущий шаг ещё может завершиться; дождитесь подтверждённого результата.',
              ),
              SizedBox(height: deckSectionGap(context)),
            ],
            _TwoPanels(
              left: eventsVisible
                  ? eventTimeline()
                  : const DeckPanel(
                      title: 'Ход выполнения',
                      child: Text('Полученные события скрыты локально.'),
                    ),
              right: DeckPanel(
                title: 'Контекст задания',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AutomationFacts(
                      values: {
                        'Задание': _value(job['id']),
                        'Цель': contextLine,
                        'Операция':
                            'Профиль ${_value(job['profileId'])} · версия ${_value(job['profileRevision'])}',
                        'Состояние': _jobState(job['state']),
                        'Основание':
                            _object(job['authorityRef'])['kind'] == 'approval'
                            ? 'Подтверждённый владельцем план'
                            : _value(_object(job['authorityRef'])['kind']),
                        'Источник': job['grantId'] == null
                            ? 'Владелец'
                            : 'ИИ · ${job['grantId']}',
                      },
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
                  ],
                ),
              ),
            ),
            SizedBox(height: deckSectionGap(context)),
            DeckStatus(
              label:
                  'Получено событий: ${widget.events.length}. Пропущено в источнике: ${widget.droppedEvents}',
              tone: widget.droppedEvents > 0
                  ? DeckTone.warning
                  : DeckTone.neutral,
            ),
            const SizedBox(height: 16),
            const Text(
              '«Остановить после текущего шага» запрашивает остановку задания. «Перестать ждать ответ» прекращает только ожидание в интерфейсе.',
            ),
            DeckActions(
              children: [
                _ActionButton(
                  'План задания',
                  widget.actions.read ? widget.onShowPlan : null,
                ),
                _ActionButton(
                  job['cancelRequested'] == true
                      ? 'Обновить состояние'
                      : 'Обновить',
                  widget.actions.read
                      ? () => widget.onSelect(job['id'] as String)
                      : null,
                ),
                _ActionButton(
                  eventsVisible ? 'Скрыть события' : 'Показать события',
                  () => setState(() => eventsVisible = !eventsVisible),
                ),
                if (widget.canCancel && job['state'] != 'unknown')
                  _ActionButton(
                    'Остановить после текущего шага',
                    widget.actions.mutate ? widget.onCancel : null,
                  ),
                if (widget.canReconcile)
                  _ActionButton(
                    'Уточнить результат',
                    widget.actions.mutate ? widget.onReconcile : null,
                  ),
              ],
            ),
            AutomationJsonView(
              title: 'Результат и проверки задания',
              value: job,
            ),
            AutomationJsonView(
              title: 'Данные полученных событий',
              value: widget.events,
            ),
            TextButton(
              clipBehavior: Clip.none,
              onPressed: () {
                setState(() => showDetail = false);
                widget.onDetailChanged?.call(false);
              },
              child: const Text('К заданиям'),
            ),
          ],
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
      _AutomationExpansion(
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
      _AutomationExpansion(
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

class AutomationGrantsSection extends StatefulWidget {
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
    this.showHeaderActions = true,
    this.onSelectionChanged,
    this.onConfigurationChanged,
  });

  final ValueChanged<Map<String, Object?>>? onSelectionChanged;
  final ValueChanged<bool>? onConfigurationChanged;
  final List<AutomationGrantPresentation> grants;
  final List<ProfileView> serverProfiles;
  final bool showHeaderActions;
  final bool loaded;
  final AutomationActionAvailability actions;
  final Map<String, Object?>? launchConfiguration;
  final VoidCallback onRefresh, onCreate, onCopyConfiguration;
  final ValueChanged<String> onConfigure;
  final ValueChanged<Map<String, Object?>> onEdit, onRevoke;

  @override
  State<AutomationGrantsSection> createState() =>
      _AutomationGrantsSectionState();
}

class _AutomationGrantsSectionState extends State<AutomationGrantsSection> {
  String? selectedId;
  bool configurationClosed = false;
  @override
  void didUpdateWidget(covariant AutomationGrantsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.launchConfiguration != widget.launchConfiguration)
      configurationClosed = false;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.launchConfiguration != null && !configurationClosed)
      return AutomationMcpConfigurationSection(
        configuration: widget.launchConfiguration!,
        grants: widget.grants,
        serverProfiles: widget.serverProfiles,
        canRead: widget.actions.read,
        onCopy: widget.onCopyConfiguration,
        onClose: () {
          setState(() => configurationClosed = true);
          widget.onConfigurationChanged?.call(false);
        },
      );
    final selected = widget.grants
        .where(
          (row) =>
              row.value['id'] ==
              (selectedId ?? widget.grants.firstOrNull?.value['id']),
        )
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeaderActions) ...[
          DeckActions(
            children: [
              _ActionButton(
                'Выдать доступ',
                widget.actions.mutate ? widget.onCreate : null,
              ),
              _ActionButton(
                'Изменить права',
                widget.actions.mutate &&
                        selected != null &&
                        selected.value['revokedAt'] == null
                    ? () => widget.onEdit(selected.value)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        DeckPanel(
          title: 'Область просмотра',
          padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.sizeOf(context).width <= 520 ? 16 : 18,
            vertical: 12,
          ),
          child: const AutomationFacts(
            tableContext: true,
            values: {
              'Истёкший grant':
                  'Не даёт новых вызовов; перевыпуск отдельным действием',
              'Author-only': 'Подготовка профилей без серверов; чтение целей и apply запрещены',
            },
          ),
        ),
        SizedBox(height: MediaQuery.sizeOf(context).width <= 520 ? 16 : 20),
        DeckActions(
          phoneBasis: 130,
          children: [
            _ActionButton(
              'Отозвать',
              widget.actions.mutate &&
                      selected != null &&
                      selected.value['revokedAt'] == null
                  ? () => widget.onRevoke(selected.value)
                  : null,
            ),
            _ActionButton(
              'Конфигурация MCP',
              widget.actions.read && selected?.current == true
                  ? () => widget.onConfigure(selected!.value['id'] as String)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (!widget.loaded)
          const DeckStatus(label: 'Клиенты ИИ ещё не прочитаны')
        else if (widget.grants.isEmpty)
          const DeckEmptyState(
            title: 'Клиентов ИИ пока нет',
            description: 'Выдайте отдельный доступ каждому клиенту.',
            icon: 'key',
          )
        else
          AutomationLoadedTable(
            columns: const ['Клиент', 'Права', 'Цели', 'Срок', 'Состояние'],
            rows: [
              for (final grant in widget.grants)
                [
                  Text(_value(grant.value['label'])),
                  Text((grant.value['scopes'] as List).map(_scope).join(' · ')),
                  Text(
                    _targetIds(grant.value['serverIds']).isEmpty
                        ? 'Без серверов'
                        : _targetIds(grant.value['serverIds'])
                              .map((id) {
                                final target = AutomationServerTargets.resolve(
                                  id,
                                  widget.serverProfiles,
                                );
                                return target == null
                                    ? 'Сведения о цели недоступны'
                                    : '${target.name} · ${AutomationServerTargets.address(target)}';
                              })
                              .join(', '),
                  ),
                  Text(_time(grant.value['expiresAt'])),
                  _RecordStatus(
                    grant.value['revokedAt'] != null
                        ? 'Отозван'
                        : grant.current
                        ? 'Действует'
                        : 'Истёк',
                    symbol: grant.value['revokedAt'] != null ? '×' : '○',
                    role: grant.value['revokedAt'] != null ? 'error' : 'muted',
                  ),
                ],
            ],
            selected: widget.grants.indexOf(selected ?? widget.grants.first),
            onSelect: (index) {
              setState(
                () => selectedId = widget.grants[index].value['id'] as String,
              );
              widget.onSelectionChanged?.call(widget.grants[index].value);
            },
          ),
        const AutomationFreshness(
          source: 'Локальная служба · доступ ИИ рабочего пространства',
        ),
        if (selected != null)
          AutomationJsonView(
            title: 'Доступ ИИ рабочего пространства',
            value: selected.value,
          ),
        TextButton(
          clipBehavior: Clip.none,
          onPressed: widget.actions.read ? widget.onRefresh : null,
          child: const Text('Обновить клиентов'),
        ),
      ],
    );
  }
}

class AutomationMcpConfigurationSection extends StatelessWidget {
  const AutomationMcpConfigurationSection({
    super.key,
    required this.configuration,
    required this.grants,
    required this.serverProfiles,
    required this.canRead,
    required this.onCopy,
    required this.onClose,
  });
  final Map<String, Object?> configuration;
  final List<AutomationGrantPresentation> grants;
  final List<ProfileView> serverProfiles;
  final bool canRead;
  final VoidCallback onCopy, onClose;
  @override
  Widget build(BuildContext context) {
    final args = configuration['args'];
    String? id;
    if (args is List) {
      final indices = [
        for (var i = 0; i < args.length - 1; i++)
          if (args[i] == '--grant-id') i,
      ];
      if (indices.length == 1 && args[indices.single + 1] is String)
        id = args[indices.single + 1] as String;
    }
    final matching = grants.where((row) => row.value['id'] == id).toList();
    final grant = matching.length == 1 ? matching.single : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DeckPanel(
          title: 'Сведения',
          child: AutomationFacts(
            values: {
              'Клиент': _value(grant?.value['label']),
              'Транспорт': 'stdio',
              'Команда': _value(configuration['command']),
              'Аргументы': _value(configuration['args']),
              'Доступ': 'Ограничен выданными правами',
              'Статус': 'Конфигурация получена',
            },
          ),
        ),
        const SizedBox(height: 20),
        DeckPanel(
          title: 'Точные значения',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AutomationExactValue(
                label: 'Команда',
                value: _value(configuration['command']),
              ),
              const SizedBox(height: 16),
              AutomationExactValue(
                label: 'Аргументы',
                value: _value(configuration['args']),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        DeckActions(
          children: [
            FilledButton(
              clipBehavior: Clip.none,
              onPressed: canRead ? onCopy : null,
              child: const DeckButtonLabel(
                icon: 'copy',
                label: 'Скопировать конфигурацию',
              ),
            ),
            _ActionButton('Закрыть', onClose),
          ],
        ),
        AutomationJsonView(
          title: 'Команда и аргументы MCP',
          value: configuration,
        ),
      ],
    );
  }
}

enum AutomationEditorKind { generic, planParameters, delegation }

class AutomationJsonEditorDialog extends StatelessWidget {
  const AutomationJsonEditorDialog({
    super.key,
    required this.title,
    this.eyebrow = 'Задания / Рабочее пространство',
    required this.input,
    required this.onClose,
    required this.onContinue,
    this.error,
    this.preview,
    this.purpose,
    this.target,
    this.clientLabel,
    this.contextDetails,
    this.formKind = AutomationEditorKind.generic,
    this.onChanged,
    this.serverProfiles = const [],
    this.targetServerIds = const [],
    this.contextCurrent = true,
    this.saving = false,
    this.requestRetained = false,
    this.canContinue = true,
    this.ownerStatus,
    this.parameterDefinitions = const {},
    this.submitLabel = 'Продолжить',
    this.asPage = false,
    this.workspaceBounds,
    this.pageInsets,
  });

  final String title, eyebrow;
  final AutomationEditorKind formKind;
  final TextEditingController input;
  final String? error, purpose, target, clientLabel;
  final Map<String, Object?>? preview, contextDetails;
  final List<ProfileView> serverProfiles;
  final List<String> targetServerIds;
  final bool contextCurrent;
  final bool saving, requestRetained, canContinue;
  final Widget? ownerStatus;
  final Map<String, Object?> parameterDefinitions;
  final String submitLabel;
  final bool asPage;
  final ValueGetter<Rect?>? workspaceBounds;
  final ValueGetter<EdgeInsetsGeometry>? pageInsets;
  bool get _locked => saving || requestRetained;
  final ValueChanged<String>? onChanged;
  final VoidCallback onClose, onContinue;

  bool get _targetsAvailable => automationTargetsAvailable([
    ...targetServerIds,
    ..._targetIds(preview?['serverIds']),
  ], serverProfiles);

  @override
  Widget build(BuildContext context) {
    final targetValue = targetServerIds.isEmpty
        ? 'Сведения о цели недоступны'
        : targetServerIds
              .map((id) {
                final row = AutomationServerTargets.resolve(id, serverProfiles);
                return row == null
                    ? 'Сведения о цели недоступны'
                    : '${row.name} · ${AutomationServerTargets.address(row)}';
              })
              .join(', ');
    String fact(String key) {
      final value = contextDetails?[key];
      return value is String || value is num ? '$value' : 'Не предоставлено';
    }

    final leading = <Widget>[
      if (formKind == AutomationEditorKind.planParameters) ...[
        AutomationFormValue(
          key: const ValueKey('automation-context-target'),
          label: 'Цель',
          value: targetValue,
          required: true,
        ),
        AutomationFormValue(
          key: const ValueKey('automation-context-profile'),
          label: 'Профиль',
          value: target ?? 'Не предоставлено',
          required: true,
        ),
      ],
      if (formKind == AutomationEditorKind.delegation) ...[
        AutomationFormValue(
          key: const ValueKey('automation-context-client'),
          label: 'ИИ-клиент',
          value: clientLabel ?? 'Не предоставлено',
          required: true,
        ),
        AutomationFormValue(
          key: const ValueKey('automation-context-profile'),
          label: 'Профиль',
          value: target ?? 'Не предоставлено',
          required: true,
        ),
        AutomationFormValue(label: 'profileId', value: fact('profileId')),
        AutomationFormValue(label: 'revision', value: fact('revision')),
        AutomationFormValue(
          label: 'bodyDigest (SHA-256)',
          value: fact('bodyDigest'),
        ),
        AutomationFormValue(
          key: const ValueKey('automation-context-target'),
          label: 'Цель',
          value: targetValue,
        ),
      ],
    ];
    final trailing = <Widget>[
      if (formKind == AutomationEditorKind.planParameters) ...[
        const AutomationFormValue(
          label: 'Проверка',
          value: 'Без записи на сервер',
        ),
        const AutomationFormValue(
          label: 'Следующий шаг',
          value: 'Получить план с эффектами и проверками',
        ),
      ],
      if (formKind == AutomationEditorKind.delegation)
        const AutomationFormValue(
          label: 'Делегирование',
          value: 'Только указанная ревизия',
        ),
    ];
    return AutomationFormPageFrame(
      title: title,
      eyebrow: eyebrow,
      asPage: asPage,
      workspaceBounds: workspaceBounds,
      pageInsets: pageInsets,
      helper: _BeforeContinue(purpose: purpose),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The source hides the decorative aside on compact/phone layouts.
          // Keep the owner's operation explanation in the actual form.
          if (purpose != null && MediaQuery.sizeOf(context).width <= 960) ...[
            Text(
              purpose!,
              style: BrandTypography.caption.copyWith(
                height: 20 / 12,
                color: deckColors(context)['muted'],
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (formKind == AutomationEditorKind.generic) ...[
            if (clientLabel != null)
              AutomationFormValue(label: 'ИИ-клиент', value: clientLabel!),
            if (target != null)
              AutomationFormValue(label: 'Профиль', value: target!),
            if (targetServerIds.isNotEmpty) ...[
              AutomationFormValue(
                label: 'Цель',
                value: targetServerIds
                    .map((id) {
                      final row = AutomationServerTargets.resolve(
                        id,
                        serverProfiles,
                      );
                      return row == null
                          ? 'Сведения о цели недоступны'
                          : '${row.name} · ${AutomationServerTargets.address(row)}';
                    })
                    .join(', '),
              ),
              const SizedBox(height: 20),
            ],
          ],
          if (!contextCurrent)
            const DeckNotice(
              message: _changedTargetMessage,
              tone: DeckTone.warning,
            ),
          AutomationStructuredDraft(
            key: const ValueKey('automation-structured-draft'),
            leadingFields: leading,
            trailingFields: trailing,
            input: input,
            enabled: !_locked && contextCurrent,
            onChanged: onChanged,
            serverProfiles: serverProfiles,
            parameterDefinitions: parameterDefinitions,
          ),
          if (!_jsonObject(input.text) && preview != null)
            AutomationFacts(
              values: {
                if (preview!['scopes'] is List)
                  'Права последнего просмотра': (preview!['scopes'] as List)
                      .map(_scope)
                      .join(', '),
                if (preview!['serverIds'] is List)
                  'Цели последнего просмотра':
                      _targetIds(preview!['serverIds']).isEmpty
                      ? 'Без доступа к серверам'
                      : _targetIds(preview!['serverIds'])
                            .map((id) {
                              final row = AutomationServerTargets.resolve(
                                id,
                                serverProfiles,
                              );
                              return row == null
                                  ? 'Сведения о цели недоступны'
                                  : '${row.name} · ${AutomationServerTargets.address(row)}';
                            })
                            .join(', '),
                if (preview!['lifetimeSeconds'] != null)
                  'Срок последнего просмотра':
                      '${preview!['lifetimeSeconds']} секунд',
              },
            ),
          const SizedBox(height: 16),
          _AutomationExpansion(
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: !_jsonObject(input.text),
            title: const Text('JSON · дополнительные сведения'),
            children: [
              Semantics(
                label: 'JSON',
                child: TextField(
                  controller: input,
                  enabled: !_locked,
                  readOnly: _locked,
                  onChanged: _locked ? null : onChanged,
                  minLines: 8,
                  maxLines: 18,
                  decoration: InputDecoration(
                    errorText: error,
                    errorMaxLines: 20,
                  ),
                  style: _locked
                      ? BrandTypography.log.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        )
                      : BrandTypography.log,
                ),
              ),
            ],
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
        FilledButton(
          clipBehavior: Clip.none,
          onPressed:
              contextCurrent && _targetsAvailable && canContinue && !_locked
              ? onContinue
              : null,
          child: Text(submitLabel),
        ),
        OutlinedButton(
          clipBehavior: Clip.none,
          onPressed: onClose,
          child: const Text('Отмена'),
        ),
      ],
    );
  }
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
    this.asPage = false,
    this.workspaceBounds,
    this.pageInsets,
  });

  final bool asPage;
  final ValueGetter<Rect?>? workspaceBounds;
  final ValueGetter<EdgeInsetsGeometry>? pageInsets;
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
  Widget build(BuildContext context) => _ProfileEditorPage(owner: this);
}

class _ProfileEditorPage extends StatefulWidget {
  const _ProfileEditorPage({required this.owner});
  final AutomationProfileEditorDialog owner;
  @override
  State<_ProfileEditorPage> createState() => _ProfileEditorPageState();
}

class _ProfileEditorPageState extends State<_ProfileEditorPage> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final w = widget.owner;
    return AutomationFormPageFrame(
      title: 'Редактор Ansible-профиля',
      asPage: w.asPage,
      workspaceBounds: w.workspaceBounds,
      pageInsets: w.pageInsets,
      tabs: DeckTabs(
        labels: const ['Назначение', 'Шаги', 'Параметры', 'Проверки'],
        selected: tab,
        onSelected: (next) => setState(() => tab = next),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AutomationProfileFields(
            showTabs: false,
            selectedSection: tab,
            body: w.body,
            enabled: w.contextCurrent && !w.saving && !w.requestRetained,
            onChanged: w.onBodyChanged,
            identityFields: [
              AutomationLabeledField(
                label: 'Название',
                required: true,
                child: TextField(
                  key: const ValueKey('automation-field-Название'),
                  controller: w.name,
                  enabled: w.contextCurrent && !w.saving && !w.requestRetained,
                  style: BrandTypography.body.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    height: MediaQuery.sizeOf(context).width <= 520
                        ? 22 / 14
                        : 20 / 14,
                  ),
                  decoration: deckFormDecoration(context)
                      .copyWith(errorText: w.nameError, errorMaxLines: 20),
                ),
              ),
              SizedBox(
                height: MediaQuery.sizeOf(context).width <= 520 ? 20 : 18,
              ),
              AutomationLabeledField(
                label: 'Описание',
                child: TextField(
                  key: const ValueKey('automation-field-Описание'),
                  controller: w.description,
                  enabled: w.contextCurrent && !w.saving && !w.requestRetained,
                  style: BrandTypography.log.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14,
                    height: MediaQuery.sizeOf(context).width <= 520
                        ? 22 / 14
                        : 20 / 14,
                  ),
                  minLines: 2,
                  maxLines: null,
                  decoration: deckFormDecoration(
                    context,
                  ).copyWith(errorText: w.descriptionError, errorMaxLines: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: BrandSpacing.space8),
          if (tab > 0 || !_profileBodyValid(w.body.text) || w.error != null)
            _AutomationExpansion(
              tilePadding: EdgeInsets.zero,
              initiallyExpanded: !_profileBodyValid(w.body.text),
              title: const Text('Шаги и параметры профиля (JSON)'),
              children: [
                Semantics(
                  label: 'Шаги и параметры профиля (JSON)',
                  child: TextField(
                    controller: w.body,
                    enabled:
                        w.contextCurrent && !w.saving && !w.requestRetained,
                    onChanged: w.onBodyChanged,
                    minLines: 8,
                    maxLines: 16,
                    decoration: InputDecoration(
                      errorText: w.error,
                      errorMaxLines: 20,
                    ),
                    style: BrandTypography.log.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          if (w.existing != null)
            Text(
              'Основа: версия ${w.baseRevision}. Текущая версия: ${w.existing!.headRevision}.',
            ),
          if (w.existing != null)
            const DeckNotice(
              message: 'Для новой версии потребуется отдельное разрешение на запуск.',
              tone: DeckTone.neutral,
            ),
          if (w.validation != null) _Validation(w.validation!),
          if (!w.contextCurrent)
            const DeckNotice(
              message: 'Контекст профиля изменился. Прежний редактор больше не может сохранять или подтверждать изменения.',
              tone: DeckTone.warning,
            ),
          if (w.ownerStatus != null) w.ownerStatus!,
          if (w.basisReview != null) w.basisReview!,
          if (w.saveError != null && w.ownerStatus == null)
            DeckNotice(
              title: w.saveUnconfirmed ? 'Исход записи не подтверждён' : null,
              message: w.saveError!,
              nextStep: w.saveUnconfirmed
                  ? 'Закройте редактор, чтобы использовать предусмотренные действия сохранённого запроса.'
                  : null,
              tone: w.saveUnconfirmed ? DeckTone.unknown : DeckTone.warning,
            ),
          if (w.saving)
            const DeckStatus(label: 'Сохранение профиля', pending: true),
          if (w.validating)
            const DeckStatus(
              label: 'Проверка содержимого профиля',
              pending: true,
            ),
        ],
      ),
      actions: [
        FilledButton(
          clipBehavior: Clip.none,
          onPressed: w.contextCurrent && !w.saving && w.canValidate
              ? w.onValidate
              : null,
          child: Text(w.validating ? 'Проверка…' : 'Проверить без сохранения'),
        ),
        OutlinedButton(
          clipBehavior: Clip.none,
          onPressed:
              !w.contextCurrent ||
                  w.validating ||
                  w.saving ||
                  w.requestRetained ||
                  !w.canSave
              ? null
              : w.onSave,
          child: const Text('Сохранить версию'),
        ),
        OutlinedButton(
          clipBehavior: Clip.none,
          onPressed: w.onClose,
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
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
            clipBehavior: Clip.none,
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
            clipBehavior: Clip.none,
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
    this.onAlternate,
    this.asPage = false,
    this.workspaceBounds,
    this.pageInsets,
  });

  final Map<String, Object?> plan;
  final bool approve;
  final VoidCallback onBack, onConfirm;
  final VoidCallback? onAlternate;
  final List<ProfileView> serverProfiles;
  final AutomationProfileRecord? automationProfile;
  final bool contextCurrent;
  final bool asPage;
  final ValueGetter<Rect?>? workspaceBounds;
  final ValueGetter<EdgeInsetsGeometry>? pageInsets;

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

  void _confirm() {
    if (_invalidated || !_current || !_canConsent) {
      if (mounted) {
        setState(() => _invalidated = _invalidated || !_current);
      }
      return;
    }
    widget.onConfirm();
  }

  @override
  Widget build(BuildContext context) {
    final content = DeckPage(
      title: 'Подтверждение плана',
      description: 'Проверьте цель, последствия и условия выбранного действия',
      eyebrow: 'Задания / Рабочее пространство',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_expired)
            const DeckNotice(
              title: 'Срок плана истёк',
              message:
                  'Создайте новый план. Прежнее согласие нельзя применить.',
              tone: DeckTone.warning,
            ),
          if (_invalidated || !_current)
            const DeckNotice(
              message: _changedTargetMessage,
              tone: DeckTone.warning,
            ),
          AutomationPlanSection(
            plan: _plan,
            serverProfiles: _serverProfiles,
            automationProfile: _profile,
            runnable: _plan['status'] == 'runnable',
            expired: _expired,
            allowApply: false,
            showRefresh: false,
            actions: AutomationActionAvailability(
              read: _current,
              mutate: !_invalidated && _current && _canConsent,
              select: _current,
            ),
            onApprove: _approve
                ? _confirm
                : widget.onAlternate ?? widget.onBack,
            onDeny: !_approve ? _confirm : widget.onAlternate ?? widget.onBack,
            onApply: () {},
            onRefresh: () {},
            onClose: widget.onBack,
          ),
        ],
      ),
    );
    return widget.asPage
        ? content
        : AutomationWorkspaceOverlay(
            workspaceBounds: widget.workspaceBounds,
            pageInsets: widget.pageInsets,
            child: content,
          );
  }
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
      TextButton(
        clipBehavior: Clip.none,
        onPressed: onBack,
        child: const Text('Назад'),
      ),
      FilledButton(
        clipBehavior: Clip.none,
        onPressed: onConfirm,
        child: Text(confirmLabel),
      ),
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
