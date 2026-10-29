import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/brand_theme.dart';

/// A native readonly editor. Only selection and the displayed value live here.
class DeckReadonlyInput extends StatefulWidget {
  const DeckReadonlyInput({
    super.key,
    required this.value,
    this.multiline = false,
  });
  final String value;
  final bool multiline;
  @override
  State<DeckReadonlyInput> createState() => _DeckReadonlyInputState();
}

class _DeckReadonlyInputState extends State<DeckReadonlyInput> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant DeckReadonlyInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.value = TextEditingValue(
        text: widget.value,
        // An updated readonly value has no editable draft to preserve. Its end
        // is always a valid UTF-16 boundary, including empty or shorter values.
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var decoration = deckFormDecoration(context);
    if (widget.multiline) {
      decoration = decoration.copyWith(
        prefixIconConstraints: decoration.prefixIconConstraints!.copyWith(
          minHeight: 60,
          maxHeight: 60,
        ),
      );
    }
    final wrap =
        widget.multiline || MediaQuery.textScalerOf(context).scale(14) > 14;
    return TextField(
      controller: _controller,
      readOnly: true,
      enableInteractiveSelection: true,
      maxLines: wrap ? null : 1,
      textAlignVertical: wrap
          ? TextAlignVertical.top
          : TextAlignVertical.center,
      style: deckFormTextStyle(context),
      decoration: decoration,
    );
  }
}

// Shared outline keeps a native >=44 editor target while painting the
// canonical smaller control. Taller multiline editors keep their full height.
class DeckInputBorder extends OutlineInputBorder {
  DeckInputBorder(this.visible, this.control, {this.focus})
    : super(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: control),
        gapPadding: 0,
      );
  final double visible;
  final Color control;
  final Color? focus;
  Rect _rect(Rect rect) {
    final height = rect.height > 44.000001
        ? rect.height
        : math.min(rect.height, visible);
    return Rect.fromLTWH(
      rect.left,
      rect.center.dy - height / 2,
      rect.width,
      height,
    );
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      super.getOuterPath(_rect(rect), textDirection: textDirection);
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      super.getInnerPath(_rect(rect), textDirection: textDirection);
  @override
  void paintInterior(
    Canvas canvas,
    Rect rect,
    Paint paint, {
    TextDirection? textDirection,
  }) => super.paintInterior(
    canvas,
    _rect(rect),
    paint,
    textDirection: textDirection,
  );
  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0,
    double gapPercentage = 0,
    TextDirection? textDirection,
  }) {
    final shape = _rect(rect);
    super.paint(
      canvas,
      shape,
      gapStart: gapStart,
      gapExtent: gapExtent,
      gapPercentage: gapPercentage,
      textDirection: textDirection,
    );
    if (focus != null)
      canvas.drawRRect(
        RRect.fromRectAndRadius(shape.inflate(3), const Radius.circular(11)),
        Paint()
          ..color = focus!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
  }

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is DeckInputBorder
      ? DeckInputBorder(
          visible,
          Color.lerp(a.control, control, t)!,
          focus: Color.lerp(
            a.focus ?? Colors.transparent,
            focus ?? Colors.transparent,
            t,
          ),
        )
      : super.lerpFrom(a, t);
  @override
  bool operator ==(Object other) =>
      other is DeckInputBorder &&
      other.visible == visible &&
      other.control == control &&
      other.focus == focus;
  @override
  int get hashCode => Object.hash(visible, control, focus);
}

InputDecoration deckFormDecoration(BuildContext context) {
  final colors = Theme.of(context).extension<BrandColors>()!;
  final phone = MediaQuery.sizeOf(context).width <= 520;
  final visible = phone ? 44.0 : 42.0;
  final border = DeckInputBorder(visible, colors['control']);
  return InputDecoration(
    isDense: true,
    visualDensity: VisualDensity.standard,
    filled: true,
    fillColor: colors['bg'],
    constraints: const BoxConstraints(minHeight: 44),
    // Dense InputDecorator loosens minHeight for its painted container. Keep
    // the native minimum through its inset slot, without adding padding to
    // multiline content. Material 3 contributes the remaining 4px input gap.
    prefixIcon: const SizedBox.shrink(),
    prefixIconConstraints: BoxConstraints.tightFor(
      width: Theme.of(context).useMaterial3 ? 8 : 12,
      height: 44,
    ),
    contentPadding: EdgeInsets.symmetric(
      horizontal: 12,
      vertical: phone ? 11 : 10,
    ),
    border: border,
    enabledBorder: border,
    disabledBorder: border,
    focusedBorder: DeckInputBorder(
      visible,
      colors['control'],
      focus: colors['focus'],
    ),
    errorBorder: DeckInputBorder(visible, colors['error']),
    focusedErrorBorder: DeckInputBorder(
      visible,
      colors['error'],
      focus: colors['focus'],
    ),
  );
}

TextStyle deckFormTextStyle(BuildContext context, {bool monospace = false}) =>
    (monospace ? BrandTypography.log : BrandTypography.body).copyWith(
      fontSize: 14,
      height: MediaQuery.sizeOf(context).width <= 520 ? 22 / 14 : 20 / 14,
      color: Theme.of(context).colorScheme.onSurface,
    );
