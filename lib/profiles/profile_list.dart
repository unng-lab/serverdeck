import 'package:flutter/material.dart';
import 'package:serverdeck_protocol/connections.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';

import '../theme/brand_assets.dart';
import '../theme/brand_theme.dart';
import '../theme/motion.dart';
import '../ui/deck_components.dart';
import '../ui/deck_action_flow.dart';
import 'profile_presentation.dart';
import '../ui/deck_icon.dart';
import '../ui/deck_page.dart';
import '../ui/deck_control_target.dart';
import '../ui/deck_table_controls.dart';
import '../shell/private_session.dart';
import '../shell/error_view.dart';
import 'profile_controller.dart';
import 'profile_form.dart';
import 'profile_delete.dart';
import '../servers/server_panel.dart';
import '../servers/server_compositions.dart' show ServerObservationChart;
import '../automation/automation_panel.dart';

/// A borrowed current observation. The list never connects, samples or caches it.
class ProfileListObservation {
  const ProfileListObservation({
    required this.profileId,
    required this.connectionRevision,
    required this.credentialRevision,
    required this.trustRevision,
    this.connection,
    this.state,
    this.error,
  });
  final String profileId, connectionRevision, credentialRevision, trustRevision;
  final ConnectionSnapshot? connection;
  final Map<String, Object?>? state;
  final String? error;
  bool matches(ProfileView profile) =>
      profileId == profile.id &&
      connectionRevision == profile.connectionRevision &&
      credentialRevision == profile.credentialRevision &&
      trustRevision == profile.trustRevision &&
      (connection == null || connection!.profileId == profile.id) &&
      (state == null ||
          state!['serverId'] == profile.id &&
              (state!['identity'] as Map<String, Object?>?)?['profileId'] ==
                  profile.id &&
              (state!['identity']
                      as Map<String, Object?>?)?['connectionRevision'] ==
                  profile.connectionRevision &&
              (state!['identity']
                      as Map<String, Object?>?)?['credentialRevision'] ==
                  profile.credentialRevision &&
              (state!['identity'] as Map<String, Object?>?)?['trustRevision'] ==
                  profile.trustRevision) &&
      (connection?.identity == null ||
          connection!.identity!.connectionRevision ==
                  profile.connectionRevision &&
              connection!.identity!.credentialRevision ==
                  profile.credentialRevision &&
              connection!.identity!.trustRevision == profile.trustRevision);
  bool get connected => connection?.state == 'connected';
  bool get unknown => connection == null && error == null;
  bool get attention =>
      error != null ||
      ['system', 'metrics'].any((key) {
        final observation = state?[key] as Map<String, Object?>?;
        return observation?['stale'] == true ||
            observation?['truncated'] == true ||
            observation?['parseErrors'] is num &&
                (observation!['parseErrors'] as num) > 0 ||
            [
              'error',
              'incomplete',
              'stale',
              'unavailable',
              'denied',
              'dropped',
            ].contains(observation?['quality']);
      });
}

class ProfileList extends StatefulWidget {
  const ProfileList({
    super.key,
    required this.controller,
    this.controlClient,
    this.onOpenProfile,
    this.onAiAccess,
    this.observations = const [],
  });
  final ProfileController controller;
  final TrustedApiClient? controlClient;
  final ValueChanged<ProfileView>? onOpenProfile;
  final VoidCallback? onAiAccess;
  final List<ProfileListObservation> observations;
  @override
  State<ProfileList> createState() => _ProfileListState();
}

class _ProfileListState extends State<ProfileList> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'Profile search');
  final _createFocus = FocusNode(debugLabel: 'Add server');

  final _cardKeys = <String, ({GlobalKey identity, GlobalKey actions})>{};

  String? _tag, _status;
  int? _statusMenuEpoch, _tagMenuEpoch;
  bool _filters = false, _descending = false, _creating = false;
  bool _credentialOnly = false;
  ProfileView? _editing, _deleting, _opened;
  ProfileController get controller => widget.controller;
  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _createFocus.dispose();
    super.dispose();
  }

  ProfileListObservation? _observation(ProfileView profile) {
    for (final value in widget.observations) {
      if (value.matches(profile)) return value;
    }
    return null;
  }

  void _close() {
    setState(() {
      _creating = false;
      _credentialOnly = false;
      _editing = _deleting = _opened = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.loaded) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
      final target = controller.profiles.isEmpty ? _createFocus : _searchFocus;
      final targetContext = target.context;
      if (targetContext == null ||
          !targetContext.mounted ||
          !target.canRequestFocus)
        return;
      target.requestFocus();
      Scrollable.ensureVisible(targetContext).ignore();
    });
  }

  void _open(ProfileView profile) {
    if (widget.onOpenProfile != null) {
      widget.onOpenProfile!(profile);
    } else {
      setState(() => _opened = profile);
    }
  }

  void _ai() {
    if (widget.onAiAccess != null) {
      widget.onAiAccess!();
      return;
    }
    if (widget.controlClient == null) return;
    showMotionDialog<void>(
      context: context,
      builder: (dialog) => DeckDialogLayout(
        title: 'ИИ-доступ',
        maxWidth: 900,
        actions: [
          TextButton(
            clipBehavior: Clip.none,
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Закрыть'),
          ),
        ],
        child: AutomationPanel(
          client: widget.controlClient!,
          serverProfiles: controller.profiles,
        ),
      ),
    );
  }

  bool get _aiAvailable =>
      widget.onAiAccess != null || widget.controlClient != null;
  Widget _add({bool showIcon = true}) => showIcon
      ? FilledButton(
          clipBehavior: Clip.none,
          focusNode: _createFocus,
          onPressed: () => setState(() => _creating = true),
          child: const DeckButtonLabel(icon: 'plus', label: 'Добавить сервер'),
        )
      : FilledButton(
          clipBehavior: Clip.none,
          focusNode: _createFocus,
          onPressed: () => setState(() => _creating = true),
          child: const Text('Добавить сервер'),
        );
  Widget _aiButton(String label) => Tooltip(
    message: _aiAvailable ? label : 'ИИ-доступ доступен после подключения к авторизованной локальной службе.',
    child: OutlinedButton(
      clipBehavior: Clip.none,
      onPressed: _aiAvailable ? _ai : null,
      child: Text(label),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!controller.loaded) {
      _cardKeys.clear();
      final error = controller.error;
      if (error != null)
        return ReadErrorView(
          code: error,
          onReadAgain: () => controller.refresh().ignore(),
          onCheckService: () => controller.bootstrap.retry().ignore(),
        );
      return const Center(
        child: DeckStatus(label: 'Загрузка локальных профилей', pending: true),
      );
    }
    final currentIds = controller.profiles.map((profile) => profile.id).toSet();
    _cardKeys.removeWhere((id, _) => !currentIds.contains(id));
    if (_creating || _editing != null)
      return ProfileForm(
        model: controller,
        initial: _editing,
        credentialOnly: _credentialOnly,
        asPage: true,
        onClose: _close,
      );
    if (_deleting != null)
      return ProfileDelete(
        model: controller,
        initial: _deleting!,
        asPage: true,
        onClose: _close,
      );
    if (_opened case final profile?) return _fallbackDetail(profile);
    if (controller.profiles.isEmpty) return _welcome(context);
    final query = _search.text.trim().toLowerCase();
    final profiles =
        controller.profiles.where((profile) {
          final observation = _observation(profile);
          if (_tag != null && !profile.tags.contains(_tag)) return false;
          if (_status != null &&
              _status != 'connected' &&
              _status != 'attention' &&
              _status != 'unknown' &&
              observation?.connection?.state != _status)
            return false;
          if (_status == 'connected' && observation?.connected != true)
            return false;
          if (_status == 'attention' && observation?.attention != true)
            return false;
          if (_status == 'unknown' && observation?.unknown == false)
            return false;
          return query.isEmpty ||
              [
                profile.name,
                profile.address,
                ...profile.tags,
              ].any((value) => value.toLowerCase().contains(query));
        }).toList()..sort(
          (a, b) =>
              (_descending ? -1 : 1) *
              a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    final connected = controller.profiles
        .where((p) => _observation(p)?.connected == true)
        .length;
    final attention = controller.profiles
        .where((p) => _observation(p)?.attention == true)
        .length;
    final unknown = controller.profiles
        .where((p) => _observation(p)?.unknown != false)
        .length;
    return DeckPage(
      title: 'Серверы',
      eyebrow: 'Серверы / РАБОЧЕЕ ПРОСТРАНСТВО',
      description: 'Подключения, состояние и ресурсы ваших серверов',
      actions: [
        _add(),
        OutlinedButton(
          clipBehavior: Clip.none,
          onPressed: () => _searchFocus.requestFocus(),
          child: const DeckButtonLabel(icon: 'search', label: 'Найти сервер'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DeckActions(
            phoneBasis: 130,
            children: [
              OutlinedButton(
                clipBehavior: Clip.none,
                onPressed: () => setState(() => _filters = !_filters),
                child: const Text('Фильтры'),
              ),
              _aiButton('ИИ-доступ'),
            ],
          ),
          const SizedBox(height: 18),
          ProfileFleetSummary(
            total: controller.profiles.length,
            connected: connected,
            attention: attention,
            unknown: unknown,
          ),
          const SizedBox(height: 20),
          DeckHitOverflow(
            child: LayoutBuilder(
              builder: (context, bounds) {
                final phone = MediaQuery.sizeOf(context).width <= 520;
                return Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: phone ? 12 : 10,
                  runSpacing: phone ? 12 : 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DeckHitOverflow(
                      child: SizedBox(
                        width: bounds.maxWidth.clamp(0.0, 360.0).toDouble(),
                        child: DeckSearchField(
                          controller: _search,
                          focusNode: _searchFocus,
                          labelText: 'Поиск по имени, адресу или меткам',
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                    _filterGroup(),
                  ],
                );
              },
            ),
          ),
          if (_filters) ...[const SizedBox(height: 12), _filterControls()],
          SizedBox(height: MediaQuery.sizeOf(context).width <= 520 ? 13 : 16),
          if (profiles.isEmpty)
            DeckPanel(
              child: DeckEmptyState(
                title: 'Серверы не найдены',
                description: 'В локальном каталоге нет профилей, соответствующих выбранным условиям.',
                actions: [
                  OutlinedButton(
                    clipBehavior: Clip.none,
                    onPressed: () => setState(() {
                      _search.clear();
                      _tag = _status = null;
                    }),
                    child: const Text('Сбросить фильтры'),
                  ),
                ],
              ),
            )
          else
            for (final profile in profiles)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _card(context, profile),
              ),
          const SizedBox(height: 6),
          Text(
            'Локальный каталог · ${profiles.length} из ${controller.profiles.length} · Нет наблюдения — состояние неизвестно',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _filterControls() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton(
          clipBehavior: Clip.none,
          onPressed: () => setState(() => _descending = !_descending),
          child: Text(_descending ? 'Имя: Я–А' : 'Имя: А–Я'),
        ),
        TextButton(
          clipBehavior: Clip.none,
          onPressed: () => setState(() {
            _tag = _status = null;
            _search.clear();
          }),
          child: const Text('Сбросить фильтры'),
        ),
      ],
    );
  }

  Widget _filterGroup() {
    final tags =
        controller.profiles.expand((profile) => profile.tags).toSet().toList()
          ..sort();
    // Keep the two former tab filters available even when no rows match.
    final statuses = <String, String>{
      'connected': 'Подключены',
      for (final entry in const {
        'connecting': 'Подключение',
        'closing': 'Отключение',
        'disconnected': 'Не подключён',
      }.entries)
        if (controller.profiles.any(
          (profile) => _observation(profile)?.connection?.state == entry.key,
        ))
          entry.key: entry.value,
      'attention': 'Требуют внимания',
      if (controller.profiles.any(
        (profile) => _observation(profile)?.unknown != false,
      ))
        'unknown': 'Неизвестно',
    };
    return DeckHitOverflow(
      child: Wrap(
        key: const ValueKey('profile-filter-group'),
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DeckFilterChip(
            key: const ValueKey('profile-filter-all'),
            label: 'Все ${controller.profiles.length}',
            active: _status == null && _tag == null,
            onPressed: () => setState(() => _status = _tag = null),
          ),
          _profileFilterMenu(
            tags: false,
            caption: 'Состояние',
            selected: _status,
            options: {
              '': 'Состояние',
              ...statuses,
              if (_status != null && !statuses.containsKey(_status))
                _status!: 'Нет текущих наблюдений',
            },
          ),
          _profileFilterMenu(
            tags: true,
            caption: 'Теги',
            selected: _tag,
            options: {
              '': 'Теги',
              for (final tag in tags) tag: tag,
              if (_tag != null && !tags.contains(_tag)) _tag!: _tag!,
            },
          ),
        ],
      ),
    );
  }

  bool _filterSessionCurrent(int? epoch) {
    if (!mounted) return false;
    final session = PrivateSessionScope.maybeOf(context);
    return session == null
        ? epoch == null
        : session.authorized && session.epoch == epoch;
  }

  Widget _profileFilterMenu({
    required bool tags,
    required String caption,
    required String? selected,
    required Map<String, String> options,
  }) {
    final active = selected != null;
    return DeckControlTarget(
      visibleHeight: DeckFilterChip.visibleHeight(context),
      child: PopupMenuButton<String>(
        key: ValueKey('profile-filter-${tags ? 'tag' : 'state'}'),
        tooltip: caption,
        initialValue: selected ?? '',
        popUpAnimationStyle: Motion.reduced(context)
            ? AnimationStyle.noAnimation
            : null,
        onSelected: (value) {
          if (!_filterSessionCurrent(tags ? _tagMenuEpoch : _statusMenuEpoch))
            return;
          setState(() {
            if (tags) {
              _tag = value == '' ? null : value;
            } else {
              _status = value == '' ? null : value;
            }
          });
        },
        itemBuilder: (_) {
          final epoch = PrivateSessionScope.maybeOf(context)?.epoch;
          if (tags) {
            _tagMenuEpoch = epoch;
          } else {
            _statusMenuEpoch = epoch;
          }
          return [
            for (final entry in options.entries)
              PopupMenuItem<String>(
                value: entry.key,
                child: PrivateDialogGate(
                  launchEpoch: epoch,
                  builder: (_) => DeckFocusLabel(
                    child: Text(
                      entry.value,
                      style: BrandTypography.caption.copyWith(height: 18 / 12),
                    ),
                  ),
                ),
              ),
          ];
        },
        style: DeckFilterChip.style(context, active: active),
        icon: Semantics(
          selected: active,
          child: DeckFilterChip.content(
            context,
            options[selected] ?? caption,
            active: active,
            icon: tags ? null : 'filter',
            trailing: tags ? 'chevron' : null,
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, ProfileView profile) {
    final cardKeys = _cardKeys.putIfAbsent(
      profile.id,
      () => (identity: GlobalKey(), actions: GlobalKey()),
    );
    final phone = MediaQuery.sizeOf(context).width <= 520;
    final observation = _observation(profile);
    final status = observation?.error != null
        ? 'Ошибка: ${observation!.error}'
        : switch (observation?.connection?.state) {
            'connected' => 'Подключён',
            'connecting' => 'Подключение',
            'closing' => 'Отключение',
            'disconnected' => 'Не подключён',
            _ => 'Состояние подключения не получено',
          };
    final system = observation?.state?['system'] as Map<String, Object?>?;
    final systemValue = system?['value'] as Map<String, Object?>?;
    final identity = IntrinsicHeight(
      child: Row(
        key: cardKeys.identity,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            widthFactor: 1,
            alignment: Alignment.center,
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: deckColors(context)['raised'],
                border: Border.all(color: deckColors(context)['border']),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DeckIcon('server', color: deckColors(context)['accent']),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DeckHitOverflow(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DeckActionFlow(
                    controlInset: 4,
                    spacing: 0,
                    children: [
                      TextButton(
                        clipBehavior: Clip.none,
                        onPressed: () => _open(profile),
                        style: ButtonStyle(
                          padding: const WidgetStatePropertyAll(
                            EdgeInsets.all(4),
                          ),
                          minimumSize: WidgetStatePropertyAll(
                            Size(phone ? 52 : 44, phone ? 52 : 44),
                          ),
                          alignment: Alignment.centerLeft,
                          backgroundBuilder: (context, states, child) =>
                              child ?? const SizedBox.shrink(),
                          shape: const WidgetStatePropertyAll(
                            RoundedRectangleBorder(),
                          ),
                          side: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.focused)
                                ? BorderSide(
                                    color: deckColors(context)['focus'],
                                    width: 2,
                                  )
                                : BorderSide.none,
                          ),
                          foregroundColor: WidgetStateProperty.resolveWith(
                            (states) =>
                                deckColors(context)[states.contains(
                                      WidgetState.disabled,
                                    )
                                    ? 'disabled'
                                    : states.contains(WidgetState.hovered)
                                    ? 'accent'
                                    : 'text'],
                          ),
                        ),
                        child: Text(
                          profile.name,
                          style: TextStyle(
                            fontFamily: BrandAssets.semiboldFamily,
                            fontWeight: BrandTypography.semiboldWeight,
                            fontVariations: BrandTypography.semiboldVariations,
                            fontSize: phone ? 16 : 15,
                            height: phone ? 24 / 16 : 22 / 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    _address(profile),
                    style: const TextStyle(
                      fontFamily: BrandAssets.monoFont,
                      fontSize: 12,
                      height: 20 / 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            widthFactor: 1,
            alignment: phone ? Alignment.center : Alignment.topCenter,
            child: PopupMenuButton<String>(
              tooltip: 'Действия профиля ${profile.name}',
              icon: const DeckIcon('more'),
              onSelected: (value) => setState(() {
                if (value == 'edit' || value == 'credentials') {
                  _editing = profile;
                  _credentialOnly = value == 'credentials';
                }
                if (value == 'delete') _deleting = profile;
              }),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: Text('Редактировать профиль'),
                ),
                PopupMenuItem(
                  value: 'credentials',
                  child: Text('Настроить доступ'),
                ),
                PopupMenuItem(value: 'delete', child: Text('Удалить профиль')),
              ],
            ),
          ),
        ],
      ),
    );
    final state = Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DeckStatus(
          label: status,
          tone: observation?.attention == true
              ? DeckTone.warning
              : observation?.connected == true
              ? DeckTone.available
              : DeckTone.unknown,
        ),
        for (final tag in profile.tags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: deckColors(context)['raised'],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(tag, style: BrandTypography.caption),
          ),
      ],
    );
    final systemText = Text(
      systemValue == null
          ? 'Профиль сохранён · Нет данных о системе'
          : [
              (systemValue['os'] as Map<String, Object?>?)?['PRETTY_NAME'],
              systemValue['architecture'],
              'SSH',
            ].whereType<String>().join(' · '),
      style: BrandTypography.caption.copyWith(
        color: deckColors(context)['muted'],
      ),
    );
    final actions = Wrap(
      key: cardKeys.actions,
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton(
          clipBehavior: Clip.none,
          onPressed: () => _open(profile),
          child: const DeckButtonLabel(icon: 'arrow', label: 'Открыть сервер'),
        ),
        OutlinedButton(
          clipBehavior: Clip.none,
          onPressed: () => setState(() => _editing = profile),
          child: const DeckButtonLabel(icon: 'edit', label: 'Изменить'),
        ),
      ],
    );
    return DeckSurface(
      key: ValueKey(profile.id),
      selected: observation?.connected == true,
      padding: EdgeInsets.all(
        MediaQuery.sizeOf(context).width <= 520 ? 16 : 20,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              MediaQuery.sizeOf(context).width <= 760 ||
              MediaQuery.textScalerOf(context).scale(14) >= 22;
          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              identity,
              const SizedBox(height: 12),
              state,
              const SizedBox(height: 8),
              systemText,
              if (!compact) ...[const SizedBox(height: 18), actions],
            ],
          );
          final metrics = _metrics(context, observation);
          if (compact)
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                const SizedBox(height: 16),
                metrics,
                const SizedBox(height: 16),
                actions,
              ],
            );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: info),
              const SizedBox(width: 20),
              SizedBox(
                width: constraints.maxWidth < 720 ? 270 : 300,
                child: metrics,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _metrics(BuildContext context, ProfileListObservation? observation) {
    final envelope = observation?.state?['metrics'] as Map<String, Object?>?;
    final values = envelope?['value'] as Map<String, Object?>?;
    final memory = values?['memory'] as Map<String, Object?>?;
    final disk = values?['rootDisk'] as Map<String, Object?>?;
    final entries = [
      ('CPU', _validPercent(values?['cpuPercent']), 'cpuPercent', 'accent'),
      (
        'RAM',
        _validPercent(memory?['usedPercent']),
        'memoryUsedPercent',
        'chart2',
      ),
      (
        'Диск /',
        _validPercent(disk?['usedPercent']),
        'rootDiskUsedPercent',
        'chart3',
      ),
    ];
    final history = (observation?.state?['history'] as List? ?? const []);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      entries[i].$1,
                      style: BrandTypography.caption.copyWith(
                        color: deckColors(context)['muted'],
                      ),
                    ),
                    Text(
                      entries[i].$2 is num ? '${entries[i].$2} %' : '—',
                      style: BrandTypography.caption.copyWith(
                        fontFamily: BrandAssets.monoFont,
                      ),
                    ),
                    const SizedBox(height: 7),
                    if (history.isNotEmpty)
                      ServerObservationChart(
                        rows: history
                            .whereType<Map<String, Object?>>()
                            .toList(),
                        field: entries[i].$3,
                        role: entries[i].$4,
                        height: 25,
                        stale:
                            envelope?['stale'] == true ||
                            envelope?['quality'] == 'stale',
                      )
                    else
                      Container(
                        height: 25,
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: deckColors(context)['border'],
                            ),
                          ),
                        ),
                        child: Text(
                          'Нет данных',
                          style: BrandTypography.caption.copyWith(
                            color: deckColors(context)['muted'],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Text(
          envelope == null
              ? 'Измерения появятся после подключения'
              : 'Источник: ${envelope['source'] ?? 'Неизвестно'} · Наблюдение: ${envelope['observedAt'] ?? 'Нет данных'} · Получено: ${envelope['receivedAt'] ?? 'Нет данных'} · Качество: ${envelope['quality'] ?? 'Неизвестно'}${envelope['stale'] == true ? ' · Устарело' : ''}',
          style: BrandTypography.caption.copyWith(
            color: deckColors(context)['muted'],
          ),
        ),
        if (history.isNotEmpty)
          ExpansionTile(
            title: const Text('Текстовые значения метрик'),
            children: [
              for (final point in history)
                if (point is Map)
                  Text(
                    '${point['receivedAt'] ?? point['observedAt'] ?? 'Время неизвестно'} · CPU: ${point['cpuPercent'] ?? '—'} % · RAM: ${point['memoryUsedPercent'] ?? '—'} % · Диск /: ${point['rootDiskUsedPercent'] ?? '—'} %',
                  ),
            ],
          ),
      ],
    );
  }

  Widget _welcome(BuildContext context) => DeckPage(
    title: 'Первый запуск',
    eyebrow: 'Серверы / РАБОЧЕЕ ПРОСТРАНСТВО',
    description: 'Ваше локальное рабочее пространство готово к работе',
    actions: [
      OutlinedButton(
        clipBehavior: Clip.none,
        onPressed: () => setState(() => _creating = true),
        child: const DeckButtonLabel(icon: 'plus', label: 'Добавить сервер'),
      ),
      _aiButton('Настроить ИИ-доступ'),
    ],
    child: DeckPanel(
      padding: MediaQuery.sizeOf(context).width <= 520
          ? const EdgeInsets.symmetric(horizontal: 18, vertical: 24)
          : EdgeInsets.all(MediaQuery.sizeOf(context).width <= 760 ? 24 : 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: deckColors(context)['selected'],
              border: Border.all(color: deckColors(context)['accent']),
              borderRadius: BorderRadius.circular(14),
            ),
            child: DeckIcon(
              'server',
              size: 30,
              color: deckColors(context)['accent'],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'ВАШЕ РАБОЧЕЕ ПРОСТРАНСТВО',
            style: BrandTypography.caption.copyWith(
              color: deckColors(context)['accent'],
              fontFamily: BrandAssets.semiboldFamily,
              fontWeight: BrandTypography.semiboldWeight,
              fontVariations: BrandTypography.semiboldVariations,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Все серверы.\nОдин центр управления.',
            style: BrandTypography.title.copyWith(
              fontSize: MediaQuery.sizeOf(context).width <= 760 ? 28 : 34,
              letterSpacing: -1,
              height: MediaQuery.sizeOf(context).width <= 760
                  ? 38 / 28
                  : 44 / 34,
            ),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              'Добавьте первое подключение, чтобы видеть состояние системы, ресурсы и программное обеспечение.',
              style: BrandTypography.body.copyWith(
                height: 24 / 14,
                color: deckColors(context)['muted'],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (MediaQuery.sizeOf(context).width <= 520)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _add(showIcon: false),
                const SizedBox(height: 8),
                _aiButton('Настроить ИИ-доступ'),
              ],
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _add(showIcon: false),
                _aiButton('Настроить ИИ-доступ'),
              ],
            ),
          const SizedBox(height: 40),
          const Divider(height: 1),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              const steps = [
                (
                  '01',
                  'Добавьте подключение',
                  'Адрес, пользователь и доступ по SSH',
                ),
                (
                  '02',
                  'Проверьте доверие',
                  'Сравните ключ сервера и подтвердите его',
                ),
                (
                  '03',
                  'Получите первый снимок',
                  'Система, ресурсы и установленные компоненты',
                ),
              ];
              final wide =
                  MediaQuery.sizeOf(context).width > 520 &&
                  MediaQuery.textScalerOf(context).scale(14) < 22;
              return Wrap(
                spacing: 20,
                runSpacing: 22,
                children: [
                  for (final step in steps)
                    SizedBox(
                      width: wide
                          ? (constraints.maxWidth - 40) / 3
                          : constraints.maxWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.$1,
                            style: BrandTypography.caption.copyWith(
                              fontFamily: BrandAssets.monoFont,
                              color: deckColors(context)['accent'],
                              height: 20 / 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            step.$2,
                            style: BrandTypography.table.copyWith(
                              fontFamily: BrandAssets.semiboldFamily,
                              fontWeight: BrandTypography.semiboldWeight,
                              fontVariations:
                                  BrandTypography.semiboldVariations,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            step.$3,
                            style: BrandTypography.caption.copyWith(
                              color: deckColors(context)['muted'],
                              height: 20 / 12,
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
    ),
  );

  Widget _fallbackDetail(ProfileView profile) => DeckPage(
    title: profile.name,
    description: _address(profile),
    actions: [
      OutlinedButton(
        clipBehavior: Clip.none,
        onPressed: _close,
        child: const Text('Назад'),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Пользователь SSH: ${profile.sshUser}'),
        DeckStatus(
          label: profile.credentialConfigured
              ? 'Секрет доступа сохранён; содержимое не отображается'
              : 'Секрет доступа не задан',
        ),
        const SizedBox(height: 16),
        if (widget.controlClient != null)
          ServerPanel(client: widget.controlClient!, profile: profile)
        else
          const DeckNotice(
            message: 'Подключение к серверу пока недоступно',
            tone: DeckTone.neutral,
            nextStep: 'Локальный профиль можно редактировать и удалить.',
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              clipBehavior: Clip.none,
              onPressed: () => setState(() {
                _opened = null;
                _editing = profile;
              }),
              child: const Text('Редактировать профиль'),
            ),
            OutlinedButton(
              clipBehavior: Clip.none,
              onPressed: () => setState(() {
                _opened = null;
                _deleting = profile;
              }),
              child: const Text('Удалить профиль'),
            ),
          ],
        ),
      ],
    ),
  );
}

String _address(ProfileView profile) => profile.address.contains(':')
    ? '[${profile.address}]:${profile.port}'
    : '${profile.address}:${profile.port}';

num? _validPercent(Object? value) =>
    value is num && value.isFinite && value >= 0 && value <= 100 ? value : null;
