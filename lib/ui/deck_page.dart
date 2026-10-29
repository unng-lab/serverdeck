import 'package:flutter/material.dart';

import '../theme/brand_assets.dart';
import '../theme/brand_theme.dart';
import 'deck_icon.dart';
import 'deck_action_flow.dart';
import 'deck_control_target.dart';

BrandColors deckColors(BuildContext context) =>
    Theme.of(context).extension<BrandColors>()!;

/// Read-only presentation insets belong to page scroll content, not its viewport.
class DeckPageInsets extends InheritedWidget {
  const DeckPageInsets({
    super.key,
    required this.padding,
    required super.child,
  });
  final EdgeInsetsGeometry padding;

  static EdgeInsetsGeometry of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DeckPageInsets>()?.padding ??
      EdgeInsets.zero;

  @override
  bool updateShouldNotify(DeckPageInsets oldWidget) =>
      padding != oldWidget.padding;
}

/// A page's context scrolls together with its content at every text size.
class DeckPage extends StatelessWidget {
  const DeckPage({
    super.key,
    required this.title,
    this.description,
    this.eyebrow,
    this.contextBar,
    this.actions = const [],
    required this.child,
  });
  final String title;
  final String? description, eyebrow;
  final Widget? contextBar;
  final List<Widget> actions;
  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: PageStorageKey('deck-page-$title'),
    padding: DeckPageInsets.of(context),
    child: _DeckContentStorage(
      builder: (actionsKey) => DeckHitOverflow(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DeckHitOverflow(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final phone = MediaQuery.sizeOf(context).width <= 520;
                  final desktop = MediaQuery.sizeOf(context).width > 1060;
                  final heading = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (eyebrow != null) ...[
                        Text(
                          eyebrow!.toUpperCase(),
                          style: BrandTypography.caption.copyWith(
                            fontSize: phone ? 10 : 11,
                            height: phone ? 16 / 10 : 16 / 11,
                            fontFamily: BrandAssets.semiboldFamily,
                            fontWeight: BrandTypography.semiboldWeight,
                            fontVariations: BrandTypography.semiboldVariations,
                            letterSpacing: phone ? 1.4 : 1.6,
                            color: deckColors(context)['accent'],
                          ),
                        ),
                        SizedBox(height: phone ? 4 : 6),
                      ],
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: BrandTypography.title.copyWith(
                            letterSpacing: phone ? -.6 : -.5,
                          ),
                        ),
                      ),
                      if (description != null) ...[
                        SizedBox(height: phone ? 5 : 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 580),
                          child: Text(
                            description!,
                            style: BrandTypography.body.copyWith(
                              height: 22 / 14,
                              color: deckColors(context)['muted'],
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                  final buttons = DeckActionFlow(
                    key: actionsKey,
                    expand: phone,
                    centerChildren: phone,
                    controlInset: phone ? 0 : 4,
                    children: actions,
                  );
                  return MediaQuery.sizeOf(context).width > 700
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: heading),
                            if (actions.isNotEmpty) ...[
                              const SizedBox(width: 16),
                              DeckHitOverflow(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: DeckHitOverflow(
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: desktop
                                            ? 300
                                            : constraints.maxWidth - 266,
                                      ),
                                      child: IntrinsicWidth(child: buttons),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            heading,
                            SizedBox(height: phone ? 14 : 12),
                            if (actions.isNotEmpty) buttons,
                          ],
                        );
                },
              ),
            ),
            SizedBox(height: MediaQuery.sizeOf(context).width <= 520 ? 20 : 24),
            if (contextBar != null) ...[
              contextBar!,
              const SizedBox(height: 16),
            ],
            DeckHitOverflow(child: child),
          ],
        ),
      ),
    ),
  );
}

/// A scroll offset and an unkeyed Expansible must never share a storage entry.
/// The page keeps its outer scroll namespace; child sections get a separate bucket.
class _DeckContentStorage extends StatefulWidget {
  const _DeckContentStorage({required this.builder});
  final Widget Function(GlobalKey actionsKey) builder;
  @override
  State<_DeckContentStorage> createState() => _DeckContentStorageState();
}

class _DeckContentStorageState extends State<_DeckContentStorage> {
  final _bucket = PageStorageBucket();
  final _actionsKey = GlobalKey();
  @override
  Widget build(BuildContext context) =>
      PageStorage(bucket: _bucket, child: widget.builder(_actionsKey));
}

class DeckPanel extends StatelessWidget {
  const DeckPanel({
    super.key,
    this.title,
    this.description,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });
  final String? title, description;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = deckColors(context);
    final phone = MediaQuery.sizeOf(context).width <= 520;
    return Container(
      decoration: BoxDecoration(
        color: colors['surface'],
        border: Border.all(color: colors['border']),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Container(
                padding: phone
                    ? const EdgeInsets.all(14)
                    : const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors['border'])),
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title!,
                          style: BrandTypography.body.copyWith(
                            fontFamily: BrandAssets.semiboldFamily,
                            fontWeight: BrandTypography.semiboldWeight,
                            fontVariations: BrandTypography.semiboldVariations,
                            height: phone ? 22 / 14 : 20 / 14,
                          ),
                        ),
                        if (description != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            description!,
                            style: BrandTypography.caption.copyWith(
                              height: phone ? 20 / 12 : 18 / 12,
                              color: colors['muted'],
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (trailing != null) trailing!,
                  ],
                ),
              ),
            Padding(
              padding: phone && padding == const EdgeInsets.all(18)
                  ? const EdgeInsets.all(16)
                  : padding,
              child: DeckHitOverflow(child: child),
            ),
          ],
        ),
      ),
    );
  }
}

class DeckTabsGap extends StatelessWidget {
  const DeckTabsGap({super.key});
  @override
  Widget build(BuildContext context) =>
      SizedBox(height: MediaQuery.sizeOf(context).width <= 520 ? 16 : 20);
}

class DeckTabs extends StatefulWidget {
  const DeckTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int>? onSelected;
  @override
  State<DeckTabs> createState() => _DeckTabsState();
}

class _DeckTabsState extends State<DeckTabs> {
  final _scroll = ScrollController();
  int? _focused;
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = widget.labels;
    final selected = widget.selected;
    final onSelected = widget.onSelected;
    final colors = deckColors(context);
    final phone = MediaQuery.sizeOf(context).width <= 520;
    return DeckHitOverflow(
      child: LayoutBuilder(
        builder: (context, constraints) {
          var stripHeight = phone ? 44.0 : 42.0;
          final widths = labels.map((label) {
            final text =
                TextPainter(
                  text: TextSpan(text: label, style: BrandTypography.table),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                )..layout(
                  maxWidth: (constraints.maxWidth - (phone ? 16 : 0)).clamp(
                    1.0,
                    double.infinity,
                  ),
                );
            final width = text.width + (phone ? 16 : 0);
            final height = text.height + (phone ? 13 : 12);
            if (height > stripHeight) stripHeight = height;
            text.dispose();
            return phone && width < 44 ? 44.0 : width;
          }).toList();
          final gutter = ((44 - stripHeight) / 2).clamp(0.0, 1.0);
          return CustomPaint(
            foregroundPainter: _TabFocusPainter(
              colors['focus'],
              widths: widths,
              height: stripHeight,
              focused: onSelected == null ? null : _focused,
              scroll: _scroll,
            ),
            child: Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors['border'])),
              ),
              child: DeckControlTarget(
                visibleHeight: stripHeight,
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: gutter),
                    child: Row(
                      children: [
                        for (var i = 0; i < labels.length; i++) ...[
                          if (i != 0) const SizedBox(width: 20),
                          DeckControlTarget(
                            visibleHeight: stripHeight,
                            visibleWidth: widths[i],
                            child: MergeSemantics(
                              child: Semantics(
                                selected: i == selected,
                                child: TextButton(
                                  onFocusChange: (focused) {
                                    final next = focused
                                        ? i
                                        : (_focused == i ? null : _focused);
                                    if (next != _focused)
                                      setState(() => _focused = next);
                                  },
                                  clipBehavior: Clip.none,
                                  onPressed: onSelected == null
                                      ? null
                                      : () => onSelected(i),
                                  style:
                                      TextButton.styleFrom(
                                        minimumSize: Size(
                                          44,
                                          stripHeight < 44 ? 44 : stripHeight,
                                        ),
                                        maximumSize: Size(
                                          widths[i] < 44 ? 44 : widths[i],
                                          double.infinity,
                                        ),
                                        padding: EdgeInsets.fromLTRB(
                                          phone ? 8 : 0,
                                          0,
                                          phone ? 8 : 0,
                                          phone ? 13 : 12,
                                        ),
                                        textStyle: BrandTypography.table,
                                        foregroundColor:
                                            colors[i == selected
                                                ? 'accent'
                                                : 'muted'],
                                        disabledForegroundColor:
                                            colors[i == selected
                                                ? 'accent'
                                                : 'muted'],
                                        shape: const RoundedRectangleBorder(),
                                      ).copyWith(
                                        backgroundBuilder:
                                            (context, states, child) =>
                                                CustomPaint(
                                                  painter: _DeckTabPainter(
                                                    colors,
                                                    visibleWidth: widths[i],
                                                    verticalInset: gutter,
                                                    selected: i == selected,
                                                    hovered: states.contains(
                                                      WidgetState.hovered,
                                                    ),
                                                  ),
                                                  child: child,
                                                ),
                                      ),
                                  child: Text(labels[i]),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// Paint only the keyboard outline outside the scroll viewport. Labels, hover
// fill and selection remain clipped by the native scroll view.
class _TabFocusPainter extends CustomPainter {
  _TabFocusPainter(
    this.color, {
    required this.widths,
    required this.height,
    required this.focused,
    required this.scroll,
  }) : super(repaint: scroll);
  final Color color;
  final List<double> widths;
  final double height;
  final ScrollController scroll;
  final int? focused;
  @override
  void paint(Canvas canvas, Size size) {
    final index = focused;
    if (index == null || index >= widths.length) return;
    // Layout can clamp the viewport without notifying scroll listeners.
    // Read its actual position when painting, after that correction.
    var left = -(scroll.hasClients ? scroll.offset : 0.0);
    for (var i = 0; i < index; i++) {
      left += widths[i] + 20;
    }
    canvas.save();
    canvas.clipRect((Offset.zero & size).inflate(4));
    canvas.drawRect(
      Rect.fromLTWH(left, 0, widths[index], height).inflate(3),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TabFocusPainter old) =>
      color != old.color ||
      widths != old.widths ||
      height != old.height ||
      focused != old.focused ||
      scroll != old.scroll;
}

class _DeckTabPainter extends CustomPainter {
  const _DeckTabPainter(
    this.colors, {
    required this.selected,
    required this.hovered,
    required this.verticalInset,
    required this.visibleWidth,
  });
  final BrandColors colors;
  final bool selected, hovered;
  final double verticalInset;
  final double visibleWidth;
  @override
  void paint(Canvas canvas, Size size) {
    final inset = size.height <= 44 ? verticalInset : 0.0;
    final horizontalInset = (size.width - visibleWidth) / 2;
    final rect = Rect.fromLTRB(
      horizontalInset,
      inset,
      size.width - horizontalInset,
      size.height - inset,
    );
    if (hovered) canvas.drawRect(rect, Paint()..color = colors['hover']);
    if (selected) {
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.bottom - 2, rect.width, 2),
        Paint()..color = colors['accent'],
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DeckTabPainter oldDelegate) =>
      colors != oldDelegate.colors ||
      verticalInset != oldDelegate.verticalInset ||
      visibleWidth != oldDelegate.visibleWidth ||
      selected != oldDelegate.selected ||
      hovered != oldDelegate.hovered;
}

class DeckEmptyState extends StatelessWidget {
  const DeckEmptyState({
    super.key,
    required this.title,
    required this.description,
    this.icon = 'server',
    this.actions = const [],
  });
  final String title, description, icon;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: deckColors(context)['raised'],
            borderRadius: BorderRadius.circular(16),
          ),
          child: DeckIcon(icon, size: 32, color: deckColors(context)['accent']),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: BrandTypography.title.copyWith(fontSize: 20, height: 28 / 20),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Text(
            description,
            textAlign: TextAlign.center,
            style: BrandTypography.body.copyWith(
              height: 22 / 14,
              color: deckColors(context)['muted'],
            ),
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 22),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: actions,
          ),
        ],
      ],
    ),
  );
}
