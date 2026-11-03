import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/brand_assets.dart';
import '../theme/brand_theme.dart';
import '../theme/brand_tokens.dart';
import '../ui/deck_components.dart';

enum ReadinessState { ready, unavailable }

enum FoundationSection {
  servers('Серверы', Icons.dns_outlined),
  software('ПО', Icons.apps_outlined),
  logs('Журналы', Icons.article_outlined),
  jobs('Задания', Icons.task_alt_outlined),
  settings('Настройки', Icons.settings_outlined);

  const FoundationSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum _NavigationLayout { phone, rail, sidebar }

/// C17 presentation shell. State and content are supplied by the caller.
class FoundationShell extends StatefulWidget {
  const FoundationShell({
    super.key,
    required this.state,
    this.requestedSection = FoundationSection.servers,
    this.navigationEpoch = 0,
    this.onSectionChanged,
    this.onRetry,
    this.retryInProgress = false,
    this.servers,
    this.settings,
    this.software,
    this.targetName,
    this.targetAddress,
    this.recoveryAction,
    this.status,
    this.fallbackContent,
  });

  final FoundationSection requestedSection;
  final int navigationEpoch;
  final ValueChanged<FoundationSection>? onSectionChanged;
  final ReadinessState state;
  final VoidCallback? onRetry;
  final bool retryInProgress;
  final Widget? servers, settings, software;
  final String? targetName, targetAddress;
  final Widget? recoveryAction;

  /// Optional owner-provided status and content for otherwise empty sections.
  final Widget? status, fallbackContent;

  @override
  State<FoundationShell> createState() => _FoundationShellState();
}

class _FoundationShellState extends State<FoundationShell> {
  late FoundationSection _section = widget.requestedSection;
  @override
  void didUpdateWidget(covariant FoundationShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigationEpoch != widget.navigationEpoch)
      _select(widget.requestedSection);
  }

  _NavigationLayout? _layout;
  final _featureFocus = FocusNode(debugLabel: 'Foundation content');
  final _navigationFocus = {
    for (final section in FoundationSection.values)
      section: FocusNode(debugLabel: 'Navigation ${section.name}'),
  };
  final _tooltipKeys = {
    for (final section in FoundationSection.values)
      section: GlobalKey<TooltipState>(),
  };
  final _navigationChildKeys = {
    for (final section in FoundationSection.values) section: GlobalKey(),
  };
  final _navigationStates = {
    for (final section in FoundationSection.values)
      section: WidgetStatesController({
        if (section == FoundationSection.servers) WidgetState.selected,
      }),
  };

  @override
  void dispose() {
    _featureFocus.dispose();
    for (final node in _navigationFocus.values) {
      node.dispose();
    }
    for (final controller in _navigationStates.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _select(FoundationSection section) {
    setState(() => _section = section);
    widget.onSectionChanged?.call(section);
    for (final entry in _navigationStates.entries) {
      entry.value.update(WidgetState.selected, entry.key == section);
    }
  }

  void _navigationTooltipFocus(FoundationSection section, bool focused) {
    if (!focused) {
      // Tooltip has no per-instance dismiss API. Retire only this tooltip's
      // state/overlay, preserving the real button subtree and its FocusNode.
      // Other hovered tooltips keep their native lifetime.
      setState(() => _tooltipKeys[section] = GlobalKey<TooltipState>());
      return;
    }
    final key = _tooltipKeys[section]!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // A rapid reverse traversal, resize or disposal must not revive an old
      // generation after its tooltip/button has already lost rail focus.
      _ensureNavigationTooltip(section, key);
    });
  }

  void _ensureNavigationTooltip(
    FoundationSection section,
    GlobalKey<TooltipState> key,
  ) {
    if (mounted &&
        _layout == _NavigationLayout.rail &&
        identical(_tooltipKeys[section], key) &&
        _navigationFocus[section]!.hasPrimaryFocus) {
      key.currentState?.ensureTooltipVisible();
    }
  }

  Widget _navigationButton(
    FoundationSection section,
    _NavigationLayout layout,
  ) {
    final phone = layout == _NavigationLayout.phone;
    final rail = layout == _NavigationLayout.rail;
    final selected = section == _section;
    final labelStyle = phone
        ? BrandTypography.caption.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          )
        : BrandTypography.button;
    final button = OutlinedButton(
      key: ValueKey('foundation-navigation-${section.name}'),
      statesController: _navigationStates[section],
      focusNode: _navigationFocus[section],
      onPressed: () => _select(section),
      style: OutlinedButton.styleFrom(
        minimumSize: Size(BrandGeometry.minTarget, phone || rail ? 44 : 56),
        alignment: phone || rail ? Alignment.center : Alignment.centerLeft,
        padding: phone
            ? const EdgeInsets.symmetric(horizontal: 4, vertical: 8)
            : const EdgeInsets.all(12),
        textStyle: labelStyle,
      ),
      child: Semantics(
        selected: selected,
        label: section.label,
        excludeSemantics: true,
        child: phone
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(section.icon, size: BrandGeometry.iconSize),
                  const SizedBox(height: 4),
                  Text(
                    section.label,
                    textAlign: TextAlign.center,
                    style: labelStyle,
                  ),
                ],
              )
            : rail
            ? Icon(section.icon, size: BrandGeometry.iconSize)
            : Row(
                children: [
                  Icon(section.icon, size: BrandGeometry.iconSize),
                  const SizedBox(width: 12),
                  Expanded(child: Text(section.label, style: labelStyle)),
                ],
              ),
      ),
    );
    if (!rail) return button;
    return Focus(
      canRequestFocus: false,
      onFocusChange: (focused) => _navigationTooltipFocus(section, focused),
      child: Tooltip(
        key: _tooltipKeys[section],
        message: section.label,
        child: KeyedSubtree(key: _navigationChildKeys[section], child: button),
      ),
    );
  }

  Widget _sideNavigation(_NavigationLayout layout) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Image.asset(
            layout == _NavigationLayout.rail
                ? BrandAssets.mark(Theme.of(context).brightness)
                : BrandAssets.logo(Theme.of(context).brightness),
            width: layout == _NavigationLayout.rail
                ? BrandGeometry.markMinSize
                : BrandGeometry.logoMinWidth,
            height: layout == _NavigationLayout.rail ? 24 : 40,
            semanticLabel: 'ServerDeck',
          ),
        ),
        for (final section in FoundationSection.values)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: _navigationButton(section, layout),
          ),
      ],
    ),
  );

  double _phoneItemWidth(FoundationSection section, double availableWidth) {
    double measure(FontWeight weight) {
      final painter = TextPainter(
        text: TextSpan(
          text: section.label,
          style: BrandTypography.caption.copyWith(fontWeight: weight),
        ),
        textDirection: Directionality.of(context),
        locale: Localizations.maybeLocaleOf(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final measured = math.max(
      measure(FontWeight.w400),
      measure(FontWeight.w600),
    );
    return math.min(
      availableWidth,
      math.max(BrandGeometry.minTarget, measured.ceilToDouble() + 8),
    );
  }

  Widget _phoneNavigation() => SafeArea(
    top: false,
    child: ColoredBox(
      color: Theme.of(context).extension<BrandColors>()!['surface'],
      child: LayoutBuilder(
        builder: (context, constraints) => Padding(
          key: const ValueKey('foundation-phone-navigation'),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final section in FoundationSection.values)
                SizedBox(
                  width: _phoneItemWidth(section, constraints.maxWidth - 8),
                  child: _navigationButton(section, _NavigationLayout.phone),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  void _updateLayout(_NavigationLayout layout) {
    if (_layout == layout) return;
    final chromeHadFocus = _navigationFocus.values.any((node) => node.hasFocus);
    _layout = layout;
    if (!chromeHadFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _layout == layout && !_featureFocus.hasFocus) {
        _navigationFocus[_section]!.requestFocus();
        // The same externally owned node can remain focused while its rail
        // tooltip is recreated by a breakpoint change, without a focus event.
        _ensureNavigationTooltip(_section, _tooltipKeys[_section]!);
      }
    });
  }

  Widget _content() {
    if (widget.state != ReadinessState.ready) {
      return DeckCollectionState(
        state: DeckDataState.unavailable,
        onRetry: widget.retryInProgress ? null : widget.onRetry,
      );
    }
    return switch (_section) {
      FoundationSection.servers => widget.servers ?? const SizedBox.shrink(),
      FoundationSection.settings => widget.settings ?? const SizedBox.shrink(),
      FoundationSection.software => widget.software ?? const SizedBox.shrink(),
      _ => widget.fallbackContent ?? const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final layout = constraints.maxWidth <= BrandGeometry.phoneBreakpoint
          ? _NavigationLayout.phone
          : constraints.maxWidth <= BrandGeometry.compactBreakpoint
          ? _NavigationLayout.rail
          : _NavigationLayout.sidebar;
      _updateLayout(layout);
      final phone = layout == _NavigationLayout.phone;
      final sidebarWidth = switch (layout) {
        _NavigationLayout.phone => 0.0,
        _NavigationLayout.rail => BrandGeometry.railWidth,
        _NavigationLayout.sidebar => BrandGeometry.sidebarWidth,
      };
      final ready = widget.state == ReadinessState.ready;
      final name = ready ? widget.targetName : null;
      final address = ready ? widget.targetAddress : null;
      final colors = Theme.of(context).extension<BrandColors>()!;
      final contentPadding =
          constraints.maxWidth <= BrandGeometry.phoneBreakpoint
          ? BrandGeometry.contentPaddingPhone
          : BrandGeometry.contentPaddingOther;
      return Scaffold(
        appBar: AppBar(
          actions: ready && widget.recoveryAction != null
              ? [widget.recoveryAction!]
              : null,
          toolbarHeight: BrandGeometry.topbarHeight,
          title: layout != _NavigationLayout.sidebar
              ? Image.asset(
                  BrandAssets.logo(Theme.of(context).brightness),
                  width: BrandGeometry.logoMinWidth,
                  height: 36,
                  semanticLabel: 'ServerDeck',
                )
              : const Text('ServerDeck', style: BrandTypography.body),
        ),
        bottomNavigationBar:
            phone && MediaQuery.viewInsetsOf(context).bottom == 0
            ? _phoneNavigation()
            : null,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Keep the feature slot at the same position across size changes.
            SizedBox(
              key: const ValueKey('foundation-sidebar'),
              width: sidebarWidth,
              child: phone
                  ? null
                  : ColoredBox(
                      color: colors['surface'],
                      child: _sideNavigation(layout),
                    ),
            ),
            SizedBox(
              width: phone ? 0 : 1,
              child: const VerticalDivider(width: 1),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: contentPadding),
                child: DeckPageBody(
                  title: _section.label,
                  titleKey: const ValueKey('foundation-page-title'),
                  contextKey: const ValueKey('foundation-page-context'),
                  featureKey: const ValueKey('foundation-feature-slot'),
                  contextHeight: constraints.maxHeight * .35,
                  target: name != null && address != null
                      ? '$name · $address'
                      : null,
                  status: ready
                      ? widget.status ??
                            const DeckStatus(
                              label: 'Пример готов',
                              tone: DeckTone.available,
                            )
                      : null,
                  focusNode: _featureFocus,
                  child: _content(),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
