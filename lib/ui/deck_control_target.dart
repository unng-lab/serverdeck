import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Keeps native minimum targets in a smaller source-visible layout box.
/// Taller multiline content keeps its full height.
class DeckControlTarget extends SingleChildRenderObjectWidget {
  const DeckControlTarget({
    super.key,
    required this.visibleHeight,
    this.visibleWidth,
    required super.child,
  });
  final double visibleHeight;
  final double? visibleWidth;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderControlTarget(visibleHeight, visibleWidth);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderControlTarget renderObject,
  ) {
    renderObject.visibleHeight = visibleHeight;
    renderObject.visibleWidth = visibleWidth;
  }
}

class _RenderControlTarget extends RenderShiftedBox {
  _RenderControlTarget(this._visibleHeight, this._visibleWidth) : super(null);
  double _visibleHeight;
  double? _visibleWidth;
  set visibleWidth(double? value) {
    if (value == _visibleWidth) return;
    _visibleWidth = value;
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  set visibleHeight(double value) {
    if (value == _visibleHeight) return;
    _visibleHeight = value;
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  double _height(double childHeight) => childHeight > 44.000001
      ? childHeight
      : math.min(childHeight, _visibleHeight);
  Rect get _target => child == null
      ? Offset.zero & size
      : (child!.parentData! as BoxParentData).offset & child!.size;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final measured = child!.getDryLayout(constraints);
    return constraints.constrain(
      Size(_visibleWidth ?? measured.width, _height(measured.height)),
    );
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _visibleWidth ?? child?.getMinIntrinsicWidth(height) ?? 0;
  @override
  double computeMaxIntrinsicWidth(double height) =>
      _visibleWidth ?? child?.getMaxIntrinsicWidth(height) ?? 0;
  @override
  double computeMinIntrinsicHeight(double width) =>
      _height(child?.getMinIntrinsicHeight(width) ?? 0);
  @override
  double computeMaxIntrinsicHeight(double width) =>
      _height(child?.getMaxIntrinsicHeight(width) ?? 0);
  @override
  void performLayout() {
    child!.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(
      Size(_visibleWidth ?? child!.size.width, _height(child!.size.height)),
    );
    (child!.parentData! as BoxParentData).offset = Offset(
      (size.width - child!.size.width) / 2,
      (size.height - child!.size.height) / 2,
    );
  }

  @override
  Rect get semanticBounds => _target;
  @override
  Rect get paintBounds =>
      _target.expandToInclude(Offset.zero & size).inflate(4);
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!_target.contains(position)) return false;
    if (!hitTestChildren(result, position: position)) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null)
      context.paintChild(
        child!,
        offset + (child!.parentData! as BoxParentData).offset,
      );
  }
}

/// Allows a small native target overflow through noninteractive layout parents.
/// Empty space still produces no hit: only the child's real handlers receive it.
class DeckHitOverflow extends SingleChildRenderObjectWidget {
  const DeckHitOverflow({super.key, required super.child, this.outset = 4});
  final double outset;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHitOverflow(outset);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderHitOverflow renderObject,
  ) => renderObject.outset = outset;
}

class _RenderHitOverflow extends RenderProxyBox {
  _RenderHitOverflow(this._outset);
  double _outset;
  set outset(double value) {
    if (_outset == value) return;
    _outset = value;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  Rect get paintBounds => super.paintBounds.inflate(_outset);
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (child == null ||
        size.isEmpty ||
        !(Offset.zero & size).inflate(_outset).contains(position))
      return false;
    final inside = Offset(
      position.dx.clamp(0.0, size.width - .000001),
      position.dy.clamp(0.0, size.height - .000001),
    );
    final hit = result.addWithPaintOffset(
      offset: position - inside,
      position: position,
      hitTest: (result, transformed) =>
          child!.hitTest(result, position: transformed),
    );
    if (hit) result.add(BoxHitTestEntry(this, position));
    return hit;
  }
}
