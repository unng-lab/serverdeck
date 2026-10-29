import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/brand_assets.dart';
import '../theme/brand_theme.dart';
import '../ui/deck_components.dart';
import '../ui/deck_icon.dart';
import '../ui/deck_page.dart';
import '../ui/deck_control_target.dart';

/// Layout of the current owner's counts; this widget never obtains observations.
class ProfileFleetSummary extends StatelessWidget {
  const ProfileFleetSummary({
    super.key,
    required this.total,
    required this.connected,
    required this.attention,
    required this.unknown,
  });
  final int total, connected, attention, unknown;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final phone = width <= 520;
    final stacked = width <= 760;
    final colors = deckColors(context);
    return DeckPanel(
      padding: stacked
          ? const EdgeInsets.all(16)
          : const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: LayoutBuilder(
        builder: (context, bounds) => _FleetWrap(
          autoMarginAfterFirst: !stacked,
          spacing: stacked ? 10 : 18,
          runSpacing: stacked ? 10 : 18,
          children: [
            SizedBox(
              width: stacked ? bounds.maxWidth : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$total',
                    style: BrandTypography.log.copyWith(
                      fontSize: phone ? 30 : 32,
                      height: phone ? 38 / 30 : 40 / 32,
                      letterSpacing: -1,
                      color: colors['text'],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'серверов в пространстве',
                      style: BrandTypography.body.copyWith(
                        fontSize: phone ? 14 : 13,
                        height: phone ? 22 / 14 : 20 / 13,
                        color: colors['muted'],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _FleetStatus(
              label: '$connected подключены',
              role: 'available',
              glyph: '●',
            ),
            _FleetStatus(
              label: '$attention требуют внимания',
              role: 'warning',
              glyph: '●',
            ),
            _FleetStatus(
              label: '$unknown неизвестно',
              role: 'unknown',
              glyph: '○',
            ),
          ],
        ),
      ),
    );
  }
}

class _FleetStatus extends StatelessWidget {
  const _FleetStatus({
    required this.label,
    required this.role,
    required this.glyph,
  });
  final String label, role, glyph;
  @override
  Widget build(BuildContext context) {
    final color = deckColors(context)[role];
    final line = MediaQuery.sizeOf(context).width <= 520 ? 20.0 : 18.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: SizedBox(
            width: 12,
            // A font fallback must not turn the source's tiny dot into a
            // full-size CJK circle. This marker is decorative, not text.
            child: Center(
              heightFactor: 1,
              child: Container(
                key: ValueKey('fleet-marker-$role'),
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: glyph == '○' ? null : color,
                  border: glyph == '○' ? Border.all(color: color) : null,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            style: BrandTypography.caption.copyWith(
              height: line / 12,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// CSS margin-right:auto on the first item only; other runs keep their gap.
class _FleetWrap extends Wrap {
  const _FleetWrap({
    required this.autoMarginAfterFirst,
    required super.children,
    required super.spacing,
    required super.runSpacing,
  }) : super(crossAxisAlignment: WrapCrossAlignment.center);
  final bool autoMarginAfterFirst;
  @override
  _FleetRenderWrap createRenderObject(BuildContext context) => _FleetRenderWrap(
    autoMarginAfterFirst,
    spacing: spacing,
    runSpacing: runSpacing,
    textDirection: Directionality.of(context),
  );
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _FleetRenderWrap renderObject,
  ) {
    super.updateRenderObject(context, renderObject);
    renderObject.autoMarginAfterFirst = autoMarginAfterFirst;
  }
}

class _FleetRenderWrap extends RenderWrap {
  _FleetRenderWrap(
    this._autoMarginAfterFirst, {
    required super.spacing,
    required super.runSpacing,
    required super.textDirection,
  }) : super(crossAxisAlignment: WrapCrossAlignment.center);
  bool _autoMarginAfterFirst;
  set autoMarginAfterFirst(bool value) {
    if (value == _autoMarginAfterFirst) return;
    _autoMarginAfterFirst = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    super.performLayout();
    final first = firstChild;
    if (!_autoMarginAfterFirst || first == null) return;
    final firstRect = (first.parentData! as WrapParentData).offset & first.size;
    var line = firstRect;
    final others = <RenderBox>[];
    for (
      var child = childAfter(first);
      child != null;
      child = childAfter(child)
    ) {
      final rect = (child.parentData! as WrapParentData).offset & child.size;
      if (rect.top < firstRect.bottom && rect.bottom > firstRect.top) {
        line = line.expandToInclude(rect);
        others.add(child);
      }
    }
    final rtl = textDirection == TextDirection.rtl;
    final free = rtl ? line.left : size.width - line.right;
    if (free <= 0) return;
    for (final child in others) {
      final data = child.parentData! as WrapParentData;
      data.offset += Offset(rtl ? -free : free, 0);
    }
  }
}

/// Shared composition for the existing profile editors, in a page or a dialog.
class ProfileEditorFrame extends StatelessWidget {
  const ProfileEditorFrame({
    super.key,
    required this.title,
    required this.child,
    required this.actions,
    this.description,
    this.target,
    this.asPage = false,
    this.showHelper = true,
    this.plan = false,
    this.actionReview,
    this.planNotice,
    this.footer,
  });
  final String title;
  final String? description;
  final Widget child;
  final Widget? target;
  final List<Widget> actions;
  final bool asPage, showHelper, plan;
  final Widget? actionReview, planNotice;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<BrandColors>()!;
    final panel = DeckSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors['border'])),
            ),
            padding: asPage && MediaQuery.sizeOf(context).width <= 520
                ? const EdgeInsets.symmetric(horizontal: 16, vertical: 18)
                : const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (target != null) ...[target!, const SizedBox(height: 20)],
                child,
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: colors['raised'],
              border: Border(top: BorderSide(color: colors['border'])),
            ),
            padding: MediaQuery.sizeOf(context).width <= 520
                ? const EdgeInsets.all(14)
                : const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: footer ?? DeckFormActions(children: actions),
          ),
        ],
      ),
    );
    if (plan) {
      final body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (planNotice != null) ...[
            planNotice!,
            SizedBox(height: deckSectionGap(context)),
          ],
          if (target != null) ...[
            DeckPanel(title: 'Параметры и условия', child: target!),
            SizedBox(height: deckSectionGap(context)),
          ],
          child,
          SizedBox(height: deckSectionGap(context)),
          if (actionReview != null) ...[
            Material(type: MaterialType.transparency, child: actionReview!),
            const SizedBox(height: 12),
          ],
          DeckActions(children: actions),
        ],
      );
      if (asPage) {
        return DeckPage(
          title: title,
          description: description,
          eyebrow: 'Серверы / РАБОЧЕЕ ПРОСТРАНСТВО',
          child: body,
        );
      }
      return DeckDialogLayout(title: title, maxWidth: 1000, child: body);
    }
    final helper = DeckPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors['selected'],
              borderRadius: BorderRadius.circular(9),
            ),
            child: DeckIcon('shield', size: 20, color: colors['accent']),
          ),
          const SizedBox(height: 14),
          Text(
            'Проверьте доступ',
            style: BrandTypography.body.copyWith(
              height: 22 / 14,
              fontFamily: BrandAssets.semiboldFamily,
              fontWeight: BrandTypography.semiboldWeight,
              fontVariations: BrandTypography.semiboldVariations,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Сравните отпечаток узла с доверенным источником при первом подключении.',
            style: BrandTypography.caption.copyWith(
              height: 20 / 12,
              color: colors['muted'],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Сохранение меняет локальный профиль. Подключение выполняется отдельным действием.',
            style: BrandTypography.caption.copyWith(
              height: 20 / 12,
              color: colors['muted'],
            ),
          ),
        ],
      ),
    );
    final composition = LayoutBuilder(
      builder: (context, constraints) {
        final wide = showHelper && MediaQuery.sizeOf(context).width > 960;
        final available = constraints.maxWidth - (wide ? 20 : 0);
        // The editor keeps the same Flex/SizedBox ancestry at every breakpoint.
        return Flex(
          direction: wide ? Axis.horizontal : Axis.vertical,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: wide ? available * 165 / 265 : available,
              child: panel,
            ),
            if (wide) const SizedBox(width: 20),
            if (wide) SizedBox(width: available * 100 / 265, child: helper),
          ],
        );
      },
    );
    if (asPage)
      return DeckPage(
        title: title,
        description: description,
        eyebrow: 'Серверы / РАБОЧЕЕ ПРОСТРАНСТВО',
        child: composition,
      );
    return DeckDialogLayout(title: title, maxWidth: 900, child: composition);
  }
}

class ProfileFieldLabel extends StatelessWidget {
  const ProfileFieldLabel({
    super.key,
    required this.label,
    this.required = false,
  });
  final String label;
  final bool required;
  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      text: label,
      children: [
        if (required)
          TextSpan(
            text: ' *',
            style: TextStyle(color: deckColors(context)['accent']),
          ),
      ],
    ),
    style: BrandTypography.caption.copyWith(
      height: 20 / 12,
      fontFamily: BrandAssets.semiboldFamily,
      fontWeight: BrandTypography.semiboldWeight,
      fontVariations: BrandTypography.semiboldVariations,
    ),
  );
}

class ProfileFieldGrid extends StatelessWidget {
  const ProfileFieldGrid({
    super.key,
    required this.children,
    this.fullWidthIndexes = const {},
  });
  final List<Widget> children;
  final Set<int> fullWidthIndexes;
  @override
  Widget build(BuildContext context) => DeckHitOverflow(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            MediaQuery.sizeOf(context).width > 520 &&
            MediaQuery.textScalerOf(context).scale(14) < 22;
        final width = wide
            ? (constraints.maxWidth - 14) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 14,
          runSpacing: MediaQuery.sizeOf(context).width <= 520 ? 20 : 18,
          children: [
            for (var index = 0; index < children.length; index++)
              DeckHitOverflow(
                child: SizedBox(
                  width: fullWidthIndexes.contains(index)
                      ? constraints.maxWidth
                      : width,
                  child: children[index],
                ),
              ),
          ],
        );
      },
    ),
  );
}
