import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/brand_theme.dart';
import '../theme/brand_tokens.dart';

/// Presentation meaning supplied by the owner of the operation/observation.
enum DeckTone {
  neutral,
  available,
  unavailable,
  unknown,
  warning,
  error,
  running,
  success,
}

BrandColors _colors(BuildContext context) =>
    Theme.of(context).extension<BrandColors>()!;

String _role(DeckTone tone) => tone == DeckTone.neutral ? 'muted' : tone.name;

IconData _symbol(DeckTone tone) => switch (tone) {
  DeckTone.neutral => Icons.info_outline,
  DeckTone.available => Icons.circle_outlined,
  DeckTone.unavailable => Icons.close,
  DeckTone.unknown => Icons.help_outline,
  DeckTone.warning => Icons.warning_amber_rounded,
  DeckTone.error => Icons.report_outlined,
  DeckTone.running => Icons.timelapse,
  DeckTone.success => Icons.check,
};

/// A surface is focusable only when it has an enabled action.
class DeckSurface extends StatefulWidget {
  const DeckSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(BrandSpacing.space16),
    this.selected = false,
    this.error = false,
    this.enabled = true,
    this.onTap,
    this.semanticLabel,
    this.focusNode,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool selected;
  final bool error;
  final bool enabled;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final FocusNode? focusNode;

  @override
  State<DeckSurface> createState() => _DeckSurfaceState();
}

class _DeckSurfaceState extends State<DeckSurface> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    final interactive = widget.onTap != null;
    final active = interactive && widget.enabled;
    final surface =
        colors[widget.selected
            ? 'selected'
            : !widget.enabled
            ? 'raised'
            : active && _hovered
            ? 'hover'
            : 'surface'];
    Widget child = Container(
      padding: widget.padding,
      constraints: interactive
          ? const BoxConstraints(
              minWidth: BrandGeometry.minTarget,
              minHeight: BrandGeometry.minTarget,
            )
          : null,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(BrandGeometry.radiusCard),
        border: Border.all(
          color:
              colors[widget.error
                  ? 'error'
                  : interactive
                  ? 'control'
                  : 'border'],
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle.merge(
          style: BrandTypography.body.copyWith(
            color: colors[widget.enabled ? 'text' : 'disabled'],
          ),
          child: widget.child,
        ),
      ),
    );
    if (interactive) {
      child = Padding(
        padding: const EdgeInsets.all(
          BrandGeometry.focusGap + BrandGeometry.focusWidth,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(BrandGeometry.radiusCard),
            focusNode: widget.focusNode,
            onTap: active ? widget.onTap : null,
            canRequestFocus: active,
            onHover: (value) => setState(() => _hovered = value),
            onFocusChange: (value) => setState(() => _focused = value),
            splashFactory: NoSplash.splashFactory,
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            child: child,
          ),
        ),
      );
      child = CustomPaint(
        painter: _SurfaceFocusPainter(colors['focus'], active && _focused),
        child: child,
      );
    }
    return Semantics(
      container: true,
      label: widget.semanticLabel,
      selected: widget.selected,
      button: interactive,
      enabled: interactive ? widget.enabled : null,
      child: child,
    );
  }
}

class _SurfaceFocusPainter extends CustomPainter {
  const _SurfaceFocusPainter(
    this.color,
    this.focused, {
    this.radius = BrandGeometry.radiusCard + 3,
  });
  final Color color;
  final bool focused;
  final double radius;
  @override
  void paint(Canvas canvas, Size size) {
    if (!focused) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(1),
        Radius.circular(radius),
      ),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = BrandGeometry.focusWidth,
    );
  }

  @override
  bool shouldRepaint(covariant _SurfaceFocusPainter oldDelegate) =>
      color != oldDelegate.color ||
      focused != oldDelegate.focused ||
      radius != oldDelegate.radius;
}

/// A bounded read-only text region with its own keyboard scroll target.
///
/// The traversable node is the real SelectableText node. Plain navigation keys
/// scroll this viewport, bypassing EditableText's nested scrollable; selection
/// modifiers and copy retain Flutter's normal read-only text actions.
class DeckBoundedTextView extends StatefulWidget {
  const DeckBoundedTextView({
    super.key,
    this.text,
    this.style,
    this.leading,
    this.contentPadding = EdgeInsets.zero,
  });

  final String? text;
  final TextStyle? style;
  final Widget? leading;
  final EdgeInsetsGeometry contentPadding;

  @override
  State<DeckBoundedTextView> createState() => _DeckBoundedTextViewState();
}

class _DeckBoundedTextViewState extends State<DeckBoundedTextView> {
  final _focus = FocusNode(debugLabel: 'Bounded selectable text');
  final _scroll = ScrollController();
  bool _focused = false;

  @override
  void dispose() {
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _move({double? boundary, double? pages, double? lines}) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final line = MediaQuery.textScalerOf(context).scale(
      (widget.style?.fontSize ?? BrandTypography.body.fontSize!) *
          (widget.style?.height ?? BrandTypography.body.height!),
    );
    final target = boundary == null
        ? position.pixels +
              (pages ?? 0) * position.viewportDimension * .8 +
              (lines ?? 0) * line
        : boundary == 0
        ? position.minScrollExtent
        : position.maxScrollExtent;
    _scroll.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.home): () => _move(boundary: 0),
      const SingleActivator(LogicalKeyboardKey.end): () => _move(boundary: 1),
      const SingleActivator(LogicalKeyboardKey.pageUp): () => _move(pages: -1),
      const SingleActivator(LogicalKeyboardKey.pageDown): () => _move(pages: 1),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(lines: -1),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
          _move(lines: 1),
    },
    child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: CustomPaint(
        foregroundPainter: _SurfaceFocusPainter(
          _colors(context)['focus'],
          _focused,
          radius: BrandGeometry.radiusControl + 3,
        ),
        child: Padding(
          padding: const EdgeInsets.all(
            BrandGeometry.focusWidth + BrandGeometry.focusGap,
          ),
          child: SingleChildScrollView(
            controller: _scroll,
            primary: false,
            padding: widget.contentPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.leading != null) widget.leading!,
                if (widget.text != null)
                  SelectableText(
                    widget.text!,
                    focusNode: _focus,
                    style: widget.style,
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Adds an outline to the label of an existing stock InkWell without adding a
/// focus node or including an ExpansionTile's potentially large body.
///
/// Dropdown items also appear inside the closed form field. That branch keeps
/// its InputDecorator outline and original geometry; only the popup InkWell
/// receives this label outline.
class DeckFocusLabel extends StatelessWidget {
  const DeckFocusLabel({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    var insideInkWell = false;
    context.visitAncestorElements((element) {
      if (element.widget is DropdownButton) return false;
      if (element.widget is InkWell) {
        insideInkWell = true;
        return false;
      }
      return true;
    });
    if (!insideInkWell) return child;
    final focused = Focus.maybeOf(context)?.hasPrimaryFocus ?? false;
    return CustomPaint(
      painter: _SurfaceFocusPainter(
        _colors(context)['focus'],
        focused,
        radius: BrandGeometry.radiusControl + 3,
      ),
      child: Padding(
        padding: const EdgeInsets.all(
          BrandGeometry.focusWidth + BrandGeometry.focusGap,
        ),
        child: child,
      ),
    );
  }
}

class DeckSectionHeader extends StatelessWidget {
  const DeckSectionHeader({
    super.key,
    required this.title,
    this.description,
    this.trailing,
  });
  final String title;
  final String? description;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Wrap(
        spacing: BrandSpacing.space12,
        runSpacing: BrandSpacing.space8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          if (trailing != null) trailing!,
        ],
      ),
      if (description != null) ...[
        const SizedBox(height: BrandSpacing.space4),
        Text(
          description!,
          style: BrandTypography.body.copyWith(
            color: _colors(context)['muted'],
          ),
        ),
      ],
    ],
  );
}

class DeckStatus extends StatelessWidget {
  const DeckStatus({
    super.key,
    required this.label,
    this.tone = DeckTone.neutral,
    this.pending = false,
  });
  final String label;
  final DeckTone tone;
  final bool pending;
  @override
  Widget build(BuildContext context) {
    final effective = pending ? DeckTone.running : tone;
    final color = _colors(context)[_role(effective)];
    return Semantics(
      liveRegion: pending,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: SizedBox(
              width: BrandGeometry.iconSize,
              height: BrandGeometry.iconSize,
              child: pending && !MediaQuery.disableAnimationsOf(context)
                  ? CircularProgressIndicator(strokeWidth: 2, color: color)
                  : Icon(
                      _symbol(effective),
                      color: color,
                      size: BrandGeometry.iconSize,
                    ),
            ),
          ),
          const SizedBox(width: BrandSpacing.space8),
          Flexible(
            child: Text(
              label,
              style: BrandTypography.body.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class DeckNotice extends StatelessWidget {
  const DeckNotice({
    super.key,
    required this.message,
    this.title,
    this.nextStep,
    this.tone = DeckTone.warning,
    this.actions = const [],
  });
  final String message;
  final String? title;
  final String? nextStep;
  final DeckTone tone;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => DeckSurface(
    error: tone == DeckTone.error,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DeckStatus(label: title ?? message, tone: tone),
        if (title != null) ...[
          const SizedBox(height: BrandSpacing.space8),
          Text(message),
        ],
        if (nextStep != null) ...[
          const SizedBox(height: BrandSpacing.space8),
          Text(nextStep!),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: BrandSpacing.space12),
          DeckActions(children: actions),
        ],
      ],
    ),
  );
}

class DeckKeyValue extends StatelessWidget {
  const DeckKeyValue({
    super.key,
    required this.label,
    required this.value,
    this.selectable = false,
    this.valueStyle,
  });
  final String label;
  final String value;
  final bool selectable;

  /// An optional typography role for machine-readable values such as commands.
  /// Human-readable values keep their existing default typography.
  final TextStyle? valueStyle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: BrandSpacing.space4),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: BrandTypography.caption.copyWith(
            color: _colors(context)['muted'],
          ),
        ),
        const SizedBox(height: BrandSpacing.space4),
        if (selectable)
          SelectableText(
            value,
            style: (valueStyle ?? BrandTypography.body).copyWith(
              color: _colors(context)['text'],
            ),
          )
        else
          Text(
            value,
            style: valueStyle?.copyWith(color: _colors(context)['text']),
          ),
      ],
    ),
  );
}

class DeckActions extends StatelessWidget {
  const DeckActions({
    super.key,
    required this.children,
    this.alignment = WrapAlignment.start,
  });
  final List<Widget> children;
  final WrapAlignment alignment;
  @override
  Widget build(BuildContext context) => Wrap(
    alignment: alignment,
    spacing: BrandSpacing.space8,
    runSpacing: BrandSpacing.space8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: children,
  );
}

class DeckFormSection extends StatelessWidget {
  const DeckFormSection({
    super.key,
    required this.title,
    required this.children,
    this.description,
    this.trailing,
  });
  final String title;
  final String? description;
  final Widget? trailing;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      DeckSectionHeader(
        title: title,
        description: description,
        trailing: trailing,
      ),
      for (final child in children) ...[
        const SizedBox(height: BrandSpacing.space16),
        child,
      ],
    ],
  );
}

/// Layout only: route creation, consent, cancellation and focus restoration stay
/// with the caller and Flutter's existing dialog route.
class DeckDialogLayout extends StatelessWidget {
  const DeckDialogLayout({
    super.key,
    required this.title,
    required this.child,
    this.target,
    this.actions = const [],
    this.maxWidth = 620,
  });
  final String title;
  final Widget? target;
  final Widget child;
  final List<Widget> actions;
  final double maxWidth;
  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(BrandSpacing.space16),
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(BrandSpacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              namesRoute: true,
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            if (target != null) ...[
              const SizedBox(height: BrandSpacing.space12),
              target!,
            ],
            const SizedBox(height: BrandSpacing.space24),
            child,
            if (actions.isNotEmpty) ...[
              const SizedBox(height: BrandSpacing.space24),
              DeckActions(children: actions),
            ],
          ],
        ),
      ),
    ),
  );
}
