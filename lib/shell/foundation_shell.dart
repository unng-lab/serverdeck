import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:serverdeck_protocol/models.dart' show ReadinessState, ErrorCode;

import '../theme/brand_theme.dart';
import '../ui/deck_icon.dart';
import '../ui/deck_page.dart';
import 'readiness_view.dart';

enum FoundationSection {
  servers('Серверы', Icons.dns_outlined, 'server'),
  software('ПО', Icons.apps_outlined, 'software'),
  logs('Журналы', Icons.article_outlined, 'logs'),
  jobs('Задания', Icons.task_alt_outlined, 'jobs'),
  settings('Настройки', Icons.settings_outlined, 'settings');

  const FoundationSection(this.label, this.icon, this.atlasIcon);
  final String label, atlasIcon;
  final IconData icon;
}

enum _NavigationLayout { phone, rail, sidebar }

class FoundationShell extends StatefulWidget {
  const FoundationShell({
    super.key,
    required this.state,
    this.reason,
    this.onRetry,
    this.retryInProgress = false,
    this.servers,
    this.settings,
    this.software,
    this.logs,
    this.jobs,
    this.targetName,
    this.targetAddress,
    this.recoveryAction,
    this.section,
    this.onSectionSelected,
    this.contentBuilder,
    this.onWorkspace,
  });
  final ReadinessState state;
  final ErrorCode? reason;
  final VoidCallback? onRetry, onWorkspace;
  final bool retryInProgress;
  final Widget? servers, settings, software, logs, jobs, recoveryAction;
  final String? targetName, targetAddress;
  final FoundationSection? section;
  final ValueChanged<FoundationSection>? onSectionSelected;
  final Widget Function(BuildContext, FoundationSection)? contentBuilder;
  @override
  State<FoundationShell> createState() => _FoundationShellState();
}

class _FoundationShellState extends State<FoundationShell> {
  FoundationSection _localSection = FoundationSection.servers;
  FoundationSection get _section => widget.section ?? _localSection;
  _NavigationLayout? _layout;
  final _featureFocus = FocusNode(debugLabel: 'Foundation content');
  final _workspaceFocus = FocusNode(debugLabel: 'Local workspace');
  final _navigationFocus = {
    for (final s in FoundationSection.values)
      s: FocusNode(debugLabel: 'Navigation ${s.name}'),
  };
  final _tooltipKeys = {
    for (final s in FoundationSection.values) s: GlobalKey<TooltipState>(),
  };
  final _navigationChildKeys = {
    for (final s in FoundationSection.values) s: GlobalKey(),
  };
  @override
  void dispose() {
    _featureFocus.dispose();
    _workspaceFocus.dispose();
    for (final node in _navigationFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _select(FoundationSection s) {
    setState(() => _localSection = s);
    widget.onSectionSelected?.call(s);
  }

  void _navigationTooltipFocus(FoundationSection s, bool focused) {
    if (!focused) {
      setState(() => _tooltipKeys[s] = GlobalKey<TooltipState>());
      return;
    }
    final key = _tooltipKeys[s]!;
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureTooltip(s, key));
  }

  void _ensureTooltip(FoundationSection s, GlobalKey<TooltipState> key) {
    if (mounted &&
        _layout == _NavigationLayout.rail &&
        identical(_tooltipKeys[s], key) &&
        _navigationFocus[s]!.hasPrimaryFocus) {
      key.currentState?.ensureTooltipVisible();
    }
  }

  Widget _navigationButton(FoundationSection s, _NavigationLayout layout) {
    final phone = layout == _NavigationLayout.phone,
        rail = layout == _NavigationLayout.rail;
    final selected = s == _section, colors = deckColors(context);
    final button = MergeSemantics(
      child: Semantics(
        selected: selected,
        label: rail ? s.label : null,
        child: TextButton(
          clipBehavior: Clip.none,
          key: ValueKey('foundation-navigation-${s.name}'),
          focusNode: _navigationFocus[s],
          onPressed: () => _select(s),
          style:
              TextButton.styleFrom(
                foregroundColor:
                    colors[selected ? (phone ? 'accent' : 'text') : 'muted'],
                padding: EdgeInsets.symmetric(
                  horizontal: phone
                      ? MediaQuery.textScalerOf(context).scale(12) > 12
                            ? 4
                            : 0
                      : rail
                      ? 0
                      : 12,
                  vertical: phone ? 6 : 10,
                ),
                minimumSize: Size(44, phone ? 52 : 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: phone
                    ? BrandTypography.caption
                    : BrandTypography.body,
              ).copyWith(
                backgroundBuilder: (context, states, child) => CustomPaint(
                  painter: _ChromeButtonPainter(
                    colors,
                    states,
                    selected: selected,
                  ),
                  child: child,
                ),
              ),
          child: phone
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DeckIcon(
                      s.atlasIcon,
                      color: colors[selected ? 'accent' : 'muted'],
                    ),
                    const SizedBox(height: 4),
                    Text(s.label, textAlign: TextAlign.center),
                  ],
                )
              : Row(
                  mainAxisAlignment: rail
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    DeckIcon(
                      s.atlasIcon,
                      color: colors[selected ? 'accent' : 'muted'],
                    ),
                    if (!rail) ...[
                      const SizedBox(width: 12),
                      Expanded(child: Text(s.label)),
                    ],
                  ],
                ),
        ),
      ),
    );
    final marked = phone
        ? button
        : Stack(
            clipBehavior: Clip.none,
            children: [
              button,
              if (selected)
                Positioned(
                  left: rail ? -10 : -12,
                  top: 9,
                  bottom: 9,
                  width: 3,
                  child: DecoratedBox(
                    key: const ValueKey('foundation-navigation-indicator'),
                    decoration: BoxDecoration(
                      color: colors['accent'],
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(3),
                      ),
                    ),
                  ),
                ),
            ],
          );
    if (!rail) return marked;
    return Focus(
      canRequestFocus: false,
      onFocusChange: (v) => _navigationTooltipFocus(s, v),
      child: Tooltip(
        key: _tooltipKeys[s],
        message: s.label,
        excludeFromSemantics: true,
        child: KeyedSubtree(key: _navigationChildKeys[s], child: marked),
      ),
    );
  }

  String get _serviceLabel => switch (widget.state) {
    ReadinessState.ready => 'Локальная служба · доступна',
    ReadinessState.starting => 'Локальная служба запускается',
    ReadinessState.storageBlocked => 'Локальное хранилище заблокировано',
    _ => 'Локальная служба недоступна',
  };
  Color get _serviceColor =>
      deckColors(context)[widget.state == ReadinessState.ready
          ? 'available'
          : widget.state == ReadinessState.starting
          ? 'running'
          : 'warning'];
  Widget _avatar() {
    final style = BrandTypography.log.copyWith(fontSize: 11, height: 1);
    final measure = TextPainter(
      text: TextSpan(text: 'OP', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final textExtent =
        (measure.width > measure.height ? measure.width : measure.height)
            .ceilToDouble() +
        2;
    measure.dispose();
    final extent = textExtent > 28 ? textExtent : 28.0;
    return Container(
      width: extent,
      height: extent,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: deckColors(context)['raised'],
        border: Border.all(color: deckColors(context)['border']),
        shape: BoxShape.circle,
      ),
      child: Text('OP', style: style),
    );
  }

  Widget _workspace(bool rail) => Tooltip(
    message: 'Локальное пространство',
    child: OutlinedButton(
      clipBehavior: Clip.none,
      key: const ValueKey('foundation-workspace'),
      focusNode: _workspaceFocus,
      onPressed:
          widget.onWorkspace ??
          () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Локальное пространство'),
              content: const Text(
                'Локальные профили и настройки этого устройства.',
              ),
              actions: [
                TextButton(
                  clipBehavior: Clip.none,
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Закрыть'),
                ),
              ],
            ),
          ),
      style:
          OutlinedButton.styleFrom(
            padding: EdgeInsets.symmetric(
              horizontal: rail ? 0 : 10,
              vertical: 10,
            ),
            minimumSize: Size(44, rail ? 44 : 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ).copyWith(
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(
                horizontal: rail ? 1 : 11,
                vertical: rail ? 9 : 11,
              ),
            ),
            backgroundBuilder: (context, states, child) => CustomPaint(
              painter: _ChromeButtonPainter(
                deckColors(context),
                states,
                workspace: true,
              ),
              child: child,
            ),
          ),
      child: Row(
        mainAxisAlignment: rail
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          Container(
            width: 25,
            height: 25,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: deckColors(context)['selected'],
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'LW',
              style: BrandTypography.button.copyWith(
                fontSize: 10,
                height: 1,
                color: deckColors(context)['accent'],
              ),
            ),
          ),
          if (!rail) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Локальное пространство',
                    style: BrandTypography.button,
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'Локальные профили',
                    style: BrandTypography.caption.copyWith(
                      color: deckColors(context)['muted'],
                      height: 18 / 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            DeckIcon('chevron', size: 13, color: deckColors(context)['muted']),
          ],
        ],
      ),
    ),
  );
  Widget _sideNavigation(_NavigationLayout layout) {
    final rail = layout == _NavigationLayout.rail;
    return LayoutBuilder(
      builder: (context, bounds) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: bounds.maxHeight),
          child: IntrinsicHeight(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                rail ? 10 : 16,
                rail ? 22 : 24,
                rail ? 10 : 16,
                rail ? 16 : 18,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: rail ? Alignment.center : Alignment.centerLeft,
                    child: SizedBox(
                      width: rail ? 32 : 160,
                      height: rail ? 32 : 48,
                      child: SvgPicture.asset(
                        'assets/brand/logos/${rail ? 'mark' : 'logo'}-${Theme.of(context).brightness.name}.svg',
                        semanticsLabel: 'ServerDeck',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  SizedBox(height: rail ? 22 : 18),
                  _workspace(rail),
                  SizedBox(height: rail ? 22 : 24),
                  for (final s in FoundationSection.values) ...[
                    _navigationButton(s, layout),
                    const SizedBox(height: 5),
                  ],
                  const Spacer(),
                  const SizedBox(height: 38),
                  if (rail) ...[
                    Tooltip(
                      message: _serviceLabel,
                      child: DeckIcon('shield', size: 14, color: _serviceColor),
                    ),
                    const SizedBox(height: 16),
                    Center(child: _avatar()),
                  ] else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DeckIcon(
                                'shield',
                                size: 14,
                                color: _serviceColor,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _serviceLabel,
                                  style: BrandTypography.caption.copyWith(
                                    color: _serviceColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Локальное хранилище',
                            style: BrandTypography.caption.copyWith(
                              height: 20 / 12,
                              color: deckColors(context)['muted'],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Divider(
                            height: 1,
                            color: deckColors(context)['border'],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _avatar(),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Оператор',
                                      style: BrandTypography.caption.copyWith(
                                        height: 20 / 12,
                                      ),
                                    ),
                                    Text(
                                      'Это устройство',
                                      style: BrandTypography.caption.copyWith(
                                        color: deckColors(context)['muted'],
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneNavigation() => DecoratedBox(
    decoration: BoxDecoration(
      color: deckColors(context)['surface'],
      border: Border(top: BorderSide(color: deckColors(context)['border'])),
    ),
    child: SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 68),
        child: Padding(
          key: const ValueKey('foundation-phone-navigation'),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: LayoutBuilder(
            builder: (context, bounds) {
              if (MediaQuery.textScalerOf(context).scale(12) <= 12) {
                return Row(
                  children: [
                    for (final s in FoundationSection.values)
                      Expanded(
                        child: _navigationButton(s, _NavigationLayout.phone),
                      ),
                  ],
                );
              }
              return Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final s in FoundationSection.values)
                    SizedBox(
                      width: _phoneItemWidth(s, bounds.maxWidth),
                      child: _navigationButton(s, _NavigationLayout.phone),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
  double _phoneItemWidth(FoundationSection section, double maximum) {
    final measure = TextPainter(
      text: TextSpan(text: section.label, style: BrandTypography.caption),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = (measure.width.ceilToDouble() + 8).clamp(44.0, maximum);
    measure.dispose();
    return width;
  }

  void _updateLayout(_NavigationLayout layout) {
    if (_layout == layout) return;
    final focused =
        _navigationFocus.values.any((node) => node.hasFocus) ||
        (layout == _NavigationLayout.phone && _workspaceFocus.hasFocus);
    _layout = layout;
    if (focused)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _layout == layout && !_featureFocus.hasFocus) {
          _navigationFocus[_section]!.requestFocus();
          _ensureTooltip(_section, _tooltipKeys[_section]!);
        }
      });
  }

  Widget _content() {
    if (widget.state != ReadinessState.ready)
      return ReadinessView(
        state: widget.state,
        reason: widget.reason,
        onRetry: widget.onRetry,
        retryInProgress: widget.retryInProgress,
      );
    if (widget.contentBuilder != null)
      return widget.contentBuilder!(context, _section);
    final child = switch (_section) {
      FoundationSection.servers => widget.servers,
      FoundationSection.software => widget.software,
      FoundationSection.logs => widget.logs,
      FoundationSection.jobs => widget.jobs,
      FoundationSection.settings => widget.settings,
    };
    return child ??
        DeckPage(
          title: _section.label,
          eyebrow: '${_section.label} / Рабочее пространство',
          child: const DeckPanel(
            child: DeckEmptyState(
              title: 'Выберите сервер',
              description: 'Данные этого раздела относятся к выбранной цели.',
            ),
          ),
        );
  }

  Widget _topbar(bool phone, bool desktop, double width) => Container(
    key: const ValueKey('foundation-topbar'),
    constraints: BoxConstraints(minHeight: phone ? 62 : 56),
    padding: EdgeInsets.symmetric(
      horizontal: phone
          ? 16
          : desktop
          ? 28
          : 24,
    ),
    decoration: BoxDecoration(
      color: deckColors(context)['surface'],
      border: Border(bottom: BorderSide(color: deckColors(context)['border'])),
    ),
    child: Row(
      children: [
        if (phone)
          SizedBox(
            width: 145,
            height: 44,
            child: SvgPicture.asset(
              'assets/brand/logos/logo-${Theme.of(context).brightness.name}.svg',
              semanticsLabel: 'ServerDeck',
            ),
          )
        else
          Expanded(
            child: DefaultTextStyle(
              style: BrandTypography.caption.copyWith(
                color: deckColors(context)['muted'],
              ),
              child: Wrap(
                spacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Рабочее пространство'),
                  const Text('/'),
                  Text(
                    _section.label,
                    style: TextStyle(color: deckColors(context)['text']),
                  ),
                ],
              ),
            ),
          ),
        if (phone) const Spacer(),
        if (!phone && width > 700) ...[
          const SizedBox(width: 12),
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: _serviceColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width * .3),
            child: Text(
              _serviceLabel,
              style: BrandTypography.caption.copyWith(color: _serviceColor),
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (widget.state == ReadinessState.ready &&
            widget.recoveryAction != null)
          widget.recoveryAction!,
        Tooltip(
          message: 'Уведомления: функция появится в наблюдаемости (009)',
          child: IconButton(
            onPressed: null,
            style: IconButton.styleFrom(
              foregroundColor: deckColors(context)['disabled'],
              disabledForegroundColor: deckColors(context)['disabled'],
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
            ).copyWith(backgroundBuilder: (context, states, child) => child!),
            icon: const DeckIcon('bell', size: 17),
            tooltip: 'Уведомления недоступны',
          ),
        ),
        SizedBox(width: phone ? 6 : 8),
        _avatar(),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final layout = constraints.maxWidth <= 520
          ? _NavigationLayout.phone
          : constraints.maxWidth <= 1060
          ? _NavigationLayout.rail
          : _NavigationLayout.sidebar;
      _updateLayout(layout);
      final phone = layout == _NavigationLayout.phone,
          desktop = layout == _NavigationLayout.sidebar;
      return Scaffold(
        bottomNavigationBar:
            phone && MediaQuery.viewInsetsOf(context).bottom == 0
            ? _phoneNavigation()
            : null,
        body: SafeArea(
          bottom: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                key: const ValueKey('foundation-sidebar'),
                width: phone
                    ? 0
                    : desktop
                    ? 210
                    : 68,
                decoration: BoxDecoration(
                  color: deckColors(context)['surface'],
                  border: Border(
                    right: BorderSide(color: deckColors(context)['border']),
                  ),
                ),
                child: phone ? null : _sideNavigation(layout),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _topbar(phone, desktop, constraints.maxWidth),
                    Expanded(
                      child: DeckPageInsets(
                        padding: EdgeInsets.fromLTRB(
                          phone
                              ? 16
                              : desktop
                              ? 28
                              : 24,
                          phone
                              ? 22
                              : desktop
                              ? 26
                              : 24,
                          phone
                              ? 16
                              : desktop
                              ? 28
                              : 24,
                          24,
                        ),
                        child: Focus(
                          key: const ValueKey('foundation-feature-slot'),
                          focusNode: _featureFocus,
                          canRequestFocus: false,
                          child: _content(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Shell frames have their source bounds; the general button theme reserves
/// an inset for compact 36px controls and must not shrink this chrome.
class _ChromeButtonPainter extends CustomPainter {
  _ChromeButtonPainter(
    this.colors,
    Set<WidgetState> states, {
    this.selected = false,
    this.workspace = false,
  }) : states = Set.of(states);
  final BrandColors colors;
  final Set<WidgetState> states;
  final bool selected, workspace;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final hovered =
        states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.pressed);
    final disabled = states.contains(WidgetState.disabled);
    final fill = disabled
        ? colors['raised']
        : selected
        ? colors['selected']
        : hovered
        ? colors['hover']
        : workspace
        ? colors['bg']
        : Colors.transparent;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(8)),
      Paint()..color = fill,
    );
    if (workspace) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds.deflate(.5), const Radius.circular(7.5)),
        Paint()
          ..color = colors['border']
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    if (states.contains(WidgetState.focused)) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds.inflate(3), const Radius.circular(11)),
        Paint()
          ..color = colors['focus']
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ChromeButtonPainter oldDelegate) => true;
}
