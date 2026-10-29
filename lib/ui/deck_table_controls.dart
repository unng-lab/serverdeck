import 'dart:math' as math;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../theme/brand_theme.dart';
import 'deck_control_target.dart';
import 'deck_icon.dart';
import 'deck_input_border.dart';

double _line(BuildContext context, double fontSize, double height) =>
    MediaQuery.textScalerOf(context).scale(fontSize) * height / fontSize;

class DeckSearchField extends StatelessWidget {
  const DeckSearchField({
    super.key,
    required this.controller,
    this.onChanged,
    this.onSubmitted,
    this.maxLength,
    this.inputKey,
    this.hintText,
    this.focusNode,
    this.labelText = 'Поиск по данным экрана',
  });
  final TextEditingController controller;
  final ValueChanged<String>? onChanged, onSubmitted;
  final int? maxLength;
  final Key? inputKey;
  final String? hintText;
  final FocusNode? focusNode;
  final String labelText;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<BrandColors>()!;
    final phone = MediaQuery.sizeOf(context).width <= 520;
    final fontSize = phone ? 14.0 : 13.0;
    final visible = math.max(
      phone ? 44.0 : 40.0,
      _line(context, fontSize, 20) + 16,
    );
    final native = math.max(44.0, visible);
    final style = BrandTypography.table.copyWith(
      fontSize: fontSize,
      height: 20 / fontSize,
    );
    final border = DeckInputBorder(visible, colors['control']);
    return DeckControlTarget(
      visibleHeight: visible,
      child: SizedBox(
        height: native,
        child: TextField(
          key: inputKey,
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          maxLength: maxLength,
          style: style,
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            isDense: true,
            counterText: maxLength == null ? null : '',
            constraints: BoxConstraints.tightFor(height: native),
            filled: true,
            fillColor: colors['surface'],
            labelText: hintText == null ? labelText : null,
            hintText: hintText,
            hintStyle: style.copyWith(color: colors['muted']),
            floatingLabelBehavior: FloatingLabelBehavior.never,
            labelStyle: style.copyWith(color: colors['muted']),
            contentPadding: const EdgeInsetsDirectional.only(
              top: 7,
              bottom: 7,
              end: 11,
            ),
            border: border,
            enabledBorder: border,
            disabledBorder: border,
            focusedBorder: DeckInputBorder(
              visible,
              colors['control'],
              focus: colors['focus'],
            ),
            prefixIconConstraints: BoxConstraints.tightFor(
              width: 30,
              height: native,
            ),
            prefixIcon: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 11, end: 4),
                child: DeckIcon('search', size: 15, color: colors['muted']),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The existing loaded-page controls; a selected page remains read-only.
class DeckPagerButton extends StatelessWidget {
  const DeckPagerButton({
    super.key,
    this.page,
    this.reverse = false,
    this.selected = false,
    this.onPressed,
  });
  final int? page;
  final bool reverse, selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<BrandColors>()!;
    final phone = MediaQuery.sizeOf(context).width <= 520;
    final minimum = phone ? 44.0 : 30.0;
    final text = TextPainter(
      text: TextSpan(
        text: page?.toString() ?? '',
        style: BrandTypography.button,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final visible = Size(
      math.max(minimum, page == null ? 30 : text.width + 14),
      math.max(minimum, (page == null ? 20 : text.height) + 6),
    );
    text.dispose();
    return DeckControlTarget(
      visibleWidth: visible.width,
      visibleHeight: visible.height,
      child: SizedBox(
        width: math.max(44, visible.width),
        height: math.max(44, visible.height),
        child: Semantics(
          selected: selected ? true : null,
          child: TextButton(
            clipBehavior: Clip.none,
            onPressed: onPressed,
            style: ButtonStyle(
              padding: const WidgetStatePropertyAll(EdgeInsets.zero),
              textStyle: const WidgetStatePropertyAll(BrandTypography.button),
              foregroundColor: WidgetStatePropertyAll(
                colors[selected
                    ? 'accent'
                    : onPressed == null
                    ? 'disabled'
                    : 'muted'],
              ),
              backgroundBuilder: (context, states, child) => CustomPaint(
                painter: _PagerPainter(colors, visible, selected, states),
                child: child,
              ),
            ),
            child: page == null
                ? RotatedBox(
                    quarterTurns: reverse ? 1 : 3,
                    child: const DeckIcon('chevron'),
                  )
                : Text('$page'),
          ),
        ),
      ),
    );
  }
}

class _PagerPainter extends CustomPainter {
  _PagerPainter(
    this.colors,
    this.visible,
    this.selected,
    Set<WidgetState> states,
  ) : states = Set.of(states);
  final BrandColors colors;
  final Size visible;
  final bool selected;
  final Set<WidgetState> states;
  @override
  void paint(Canvas canvas, Size size) {
    final shape = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: size.center(Offset.zero),
        width: visible.width,
        height: visible.height,
      ),
      const Radius.circular(5),
    );
    if (selected ||
        states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.pressed)) {
      canvas.drawRRect(
        shape,
        Paint()..color = colors[selected ? 'selected' : 'hover'],
      );
    }
    canvas.drawRRect(
      shape.deflate(.5),
      Paint()
        ..color = colors[selected ? 'accent' : 'control']
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    if (states.contains(WidgetState.focused)) {
      canvas.drawRRect(
        shape.inflate(3),
        Paint()
          ..color = colors['focus']
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PagerPainter oldDelegate) =>
      colors != oldDelegate.colors ||
      visible != oldDelegate.visible ||
      selected != oldDelegate.selected ||
      !setEquals(states, oldDelegate.states);
}

class DeckFilterChip extends StatelessWidget {
  const DeckFilterChip({
    super.key,
    required this.label,
    this.onPressed,
    this.active = false,
    this.icon,
    this.trailing,
    this.tooltip,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool active;
  final String? icon, trailing, tooltip;

  static double visibleHeight(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width <= 520;
    return math.max(
      phone ? 44.0 : 36.0,
      _line(context, 12, phone ? 20 : 18) + (phone ? 24 : 12),
    );
  }

  static TextStyle _textStyle(BuildContext context, bool active) {
    final colors = Theme.of(context).extension<BrandColors>()!;
    return BrandTypography.caption.copyWith(
      height: MediaQuery.sizeOf(context).width <= 520 ? 20 / 12 : 18 / 12,
      fontWeight: FontWeight.w400,
      color: colors[active ? 'accent' : 'muted'],
    );
  }

  static Widget content(
    BuildContext context,
    String label, {
    bool active = false,
    String? icon,
    String? trailing,
  }) {
    final color = Theme.of(context)
        .extension<BrandColors>()![active ? 'accent' : 'muted'];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          DeckIcon(icon, size: 12, color: color),
          const SizedBox(width: 6),
        ],
        Flexible(child: Text(label, style: _textStyle(context, active))),
        if (trailing != null) ...[
          const SizedBox(width: 6),
          DeckIcon(trailing, size: 12, color: color),
        ],
      ],
    );
  }

  static ButtonStyle style(BuildContext context, {bool active = false}) {
    final phone = MediaQuery.sizeOf(context).width <= 520;
    final colors = Theme.of(context).extension<BrandColors>()!;
    final visible = visibleHeight(context);
    return ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: phone ? 13 : 11,
          vertical: phone ? 12 : 6,
        ),
      ),
      textStyle: WidgetStatePropertyAll(_textStyle(context, active)),
      foregroundColor: WidgetStatePropertyAll(
        colors[active ? 'accent' : 'muted'],
      ),
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      side: const WidgetStatePropertyAll(BorderSide.none),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
      backgroundBuilder: (context, states, child) => CustomPaint(
        painter: _ChipPainter(
          colors,
          visible,
          active,
          states.contains(WidgetState.focused),
          states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width <= 520;
    final colors = Theme.of(context).extension<BrandColors>()!;
    final visible = visibleHeight(context);
    final labelWidget = content(
      context,
      label,
      active: active,
      icon: icon,
      trailing: trailing,
    );
    Widget native = onPressed != null
        ? OutlinedButton(
            clipBehavior: Clip.none,
            style: style(context, active: active),
            onPressed: onPressed,
            child: Semantics(selected: active, child: labelWidget),
          )
        : Semantics(
            enabled: false,
            child: CustomPaint(
              painter: _ChipPainter(colors, visible, active, false, false),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: phone ? 13 : 11,
                      vertical: phone ? 12 : 6,
                    ),
                    child: labelWidget,
                  ),
                ),
              ),
            ),
          );
    if (tooltip != null) native = Tooltip(message: tooltip, child: native);
    return DeckControlTarget(visibleHeight: visible, child: native);
  }
}

class _ChipPainter extends CustomPainter {
  const _ChipPainter(
    this.colors,
    this.visible,
    this.active,
    this.focused,
    this.hovered,
  );
  final BrandColors colors;
  final double visible;
  final bool active, focused, hovered;
  @override
  void paint(Canvas canvas, Size size) {
    final height = size.height > 44.000001
        ? size.height
        : math.min(size.height, visible);
    final rect = Rect.fromLTWH(
      0,
      (size.height - height) / 2,
      size.width,
      height,
    );
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(7));
    canvas.drawRRect(
      shape,
      Paint()
        ..color =
            colors[active
                ? 'selected'
                : hovered
                ? 'hover'
                : 'surface'],
    );
    canvas.drawRRect(
      shape.deflate(.5),
      Paint()
        ..color = colors[active ? 'accent' : 'control']
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    if (focused)
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(3), const Radius.circular(10)),
        Paint()
          ..color = colors['focus']
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
  }

  @override
  bool shouldRepaint(covariant _ChipPainter oldDelegate) =>
      colors != oldDelegate.colors ||
      visible != oldDelegate.visible ||
      active != oldDelegate.active ||
      focused != oldDelegate.focused ||
      hovered != oldDelegate.hovered;
}
