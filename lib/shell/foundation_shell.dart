import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:serverdeck_protocol/models.dart' show ReadinessState, ErrorCode;

import '../theme/brand_assets.dart';
import '../theme/brand_theme.dart';
import '../theme/brand_tokens.dart';
import '../ui/deck_components.dart';
import 'readiness_view.dart';

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

/// Navigation is local UI state; service readiness gates every private child.
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
    this.targetName,
    this.targetAddress,
    this.recoveryAction,
  });

  final ReadinessState state;
  final ErrorCode? reason;
  final VoidCallback? onRetry;
  final bool retryInProgress;
  final Widget? servers, settings, software;
  final String? targetName, targetAddress;
  final Widget? recoveryAction;

  @override
  State<FoundationShell> createState() => _FoundationShellState();
}

class _FoundationShellState extends State<FoundationShell> {
  FoundationSection _section = FoundationSection.servers;
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
      return ReadinessView(
        state: widget.state,
        reason: widget.reason,
        onRetry: widget.onRetry,
        retryInProgress: widget.retryInProgress,
      );
    }
    return switch (_section) {
      FoundationSection.servers =>
        widget.servers ??
            const _Unavailable('Управление профилями пока недоступно'),
      FoundationSection.settings =>
        widget.settings ?? const _Unavailable('Настройки пока недоступны'),
      FoundationSection.software =>
        widget.software ??
            const _Unavailable(
              'Управление ПО будет доступно после подключения к серверу',
            ),
      FoundationSection.logs => _SectionGuide(
        message: 'Общий список журналов пока недоступен',
        nextStep: 'Журнал доступен в карточке сервера при действующем доступе и доверии к SSH-ключу.',
        onServers: () => _select(FoundationSection.servers),
      ),
      FoundationSection.jobs => _SectionGuide(
        message: 'Общий список заданий пока недоступен',
        nextStep: 'Задания и их результаты доступны в карточке сервера при действующем доступе и доверии.',
        onServers: () => _select(FoundationSection.servers),
      ),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ConstrainedBox(
                      key: const ValueKey('foundation-page-context'),
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight * .35,
                      ),
                      child: DeckBoundedTextView(
                        text: name != null && address != null
                            ? '$name · $address'
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                        leading: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                _section.label,
                                key: const ValueKey('foundation-page-title'),
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            if (ready) ...[
                              const SizedBox(height: 8),
                              const DeckStatus(
                                label: 'Локальная служба готова',
                                tone: DeckTone.available,
                              ),
                              if (name != null && address != null) ...[
                                const SizedBox(height: 8),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Focus(
                        key: const ValueKey('foundation-feature-slot'),
                        focusNode: _featureFocus,
                        canRequestFocus: false,
                        child: _content(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _SectionGuide extends StatelessWidget {
  const _SectionGuide({
    required this.message,
    required this.nextStep,
    required this.onServers,
  });
  final String message, nextStep;
  final VoidCallback onServers;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(vertical: BrandSpacing.space16),
    child: DeckNotice(
      message: message,
      nextStep: nextStep,
      tone: DeckTone.neutral,
      actions: [
        OutlinedButton(onPressed: onServers, child: const Text('К серверам')),
      ],
    ),
  );
}

class _Unavailable extends StatelessWidget {
  const _Unavailable(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}
