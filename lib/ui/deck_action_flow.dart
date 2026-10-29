import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Canonical action rows: ordinary wrapping, or CSS flex-grow on phone.
class DeckActionFlow extends MultiChildRenderObjectWidget {
  const DeckActionFlow({
    super.key,
    super.children,
    this.expand = false,
    this.basis,
    this.alignment = WrapAlignment.start,
    this.centerChildren = true,
    this.controlInset = 0,
    this.spacing = 8,
  });
  final bool expand, centerChildren;

  /// A zero basis distributes equal flex shares, clamped by min-content.
  final double? basis;
  final WrapAlignment alignment;
  final double controlInset;
  final double spacing;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderActionFlow(
    expand,
    basis,
    alignment,
    centerChildren,
    Directionality.of(context),
    controlInset,
    spacing,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderActionFlow renderObject,
  ) {
    renderObject.update(
      expand,
      basis,
      alignment,
      centerChildren,
      Directionality.of(context),
      controlInset,
      spacing,
    );
  }
}

class _ActionParentData extends ContainerBoxParentData<RenderBox> {}

class _ActionRun {
  _ActionRun(this.spacing);
  final double spacing;
  final children = <({RenderBox box, double basis})>[];
  double width = 0;
  void add(RenderBox box, double basis) {
    if (children.isNotEmpty) width += spacing;
    children.add((box: box, basis: basis));
    width += basis;
  }
}

class _RenderActionFlow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ActionParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ActionParentData> {
  _RenderActionFlow(
    this._expand,
    this._basis,
    this._alignment,
    this._centerChildren,
    this._direction,
    this._inset,
    this._spacing,
  );
  bool _expand, _centerChildren;
  double? _basis;
  WrapAlignment _alignment;
  TextDirection _direction;
  double _inset;
  double _spacing;

  void update(
    bool expand,
    double? basis,
    WrapAlignment alignment,
    bool centerChildren,
    TextDirection direction,
    double inset,
    double spacing,
  ) {
    if (_expand == expand &&
        _basis == basis &&
        _alignment == alignment &&
        _centerChildren == centerChildren &&
        _direction == direction &&
        _inset == inset &&
        _spacing == spacing)
      return;
    _expand = expand;
    _basis = basis;
    _alignment = alignment;
    _centerChildren = centerChildren;
    _direction = direction;
    _inset = inset;
    _spacing = spacing;
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ActionParentData)
      child.parentData = _ActionParentData();
  }

  Iterable<RenderBox> get _children sync* {
    var child = firstChild;
    while (child != null) {
      yield child;
      child = (child.parentData! as _ActionParentData).nextSibling;
    }
  }

  double _preferred(RenderBox child) => math.max(
    0.0,
    math.max(
          child.getMinIntrinsicWidth(double.infinity),
          _expand && _basis != null
              ? _basis!
              : child.getMaxIntrinsicWidth(double.infinity),
        ) -
        _inset * 2,
  );

  @override
  double computeMinIntrinsicWidth(double height) => _children.fold(
    0.0,
    (width, child) =>
        math.max(width, child.getMinIntrinsicWidth(height) - _inset * 2),
  );

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _children.fold(0.0, (width, child) => width + _preferred(child)) +
      math.max(0, childCount - 1) * _spacing;

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _layout(BoxConstraints(maxWidth: width), dry: true).height;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _layout(constraints, dry: true);

  Size _layout(BoxConstraints constraints, {required bool dry}) {
    if (firstChild == null) return constraints.constrain(Size.zero);
    final available = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : computeMaxIntrinsicWidth(double.infinity);
    final runs = <_ActionRun>[];
    for (final child in _children) {
      final basis = math.min(available, _preferred(child));
      if (runs.isEmpty ||
          (runs.last.children.isNotEmpty &&
              runs.last.width + _spacing + basis > available + .000001))
        runs.add(_ActionRun(_spacing));
      runs.last.add(child, basis);
    }
    final width = constraints.constrainWidth(
      _expand
          ? available
          : runs.fold(0.0, (value, run) => math.max(value, run.width)),
    );
    var y = 0.0;
    for (final run in runs) {
      final free = math.max(0.0, width - run.width);
      final grow = _expand ? free / run.children.length : 0.0;
      final widths = [for (final item in run.children) item.basis + grow];
      if (_expand && _basis == 0) {
        // CSS flex:1 starts at zero, freezes min-content violations, then
        // shares the remaining line among the other native controls.
        var remaining = width - (run.children.length - 1) * _spacing;
        final pending = [for (var i = 0; i < widths.length; i++) i];
        while (pending.isNotEmpty) {
          final share = remaining / pending.length;
          final frozen = [
            for (final i in pending)
              if (run.children[i].basis > share) i,
          ];
          if (frozen.isEmpty) {
            for (final i in pending) widths[i] = share;
            break;
          }
          for (final i in frozen) {
            widths[i] = run.children[i].basis;
            remaining -= widths[i];
            pending.remove(i);
          }
        }
      }
      final sizes = <Size>[];
      var height = 0.0;
      var index = 0;
      for (final item in run.children) {
        final childConstraints = BoxConstraints.tightFor(
          width: widths[index++] + _inset * 2,
        );
        final Size childSize;
        if (dry) {
          childSize = item.box.getDryLayout(childConstraints);
        } else {
          item.box.layout(childConstraints, parentUsesSize: true);
          childSize = item.box.size;
        }
        sizes.add(childSize);
        height = math.max(height, childSize.height - _inset * 2);
      }
      final (leading, extraGap) = _expand
          ? (0.0, 0.0)
          : switch (_alignment) {
              WrapAlignment.start => (0.0, 0.0),
              WrapAlignment.end => (free, 0.0),
              WrapAlignment.center => (free / 2, 0.0),
              WrapAlignment.spaceBetween => (
                0.0,
                run.children.length > 1
                    ? free / (run.children.length - 1)
                    : 0.0,
              ),
              WrapAlignment.spaceAround => (
                free / run.children.length / 2,
                free / run.children.length,
              ),
              WrapAlignment.spaceEvenly => (
                free / (run.children.length + 1),
                free / (run.children.length + 1),
              ),
            };
      var x = leading;
      for (var index = 0; index < run.children.length; index++) {
        final childSize = sizes[index];
        if (!dry) {
          (run.children[index].box.parentData! as _ActionParentData).offset =
              Offset(
                _direction == TextDirection.ltr
                    ? x - _inset
                    : width - x - childSize.width + _inset,
                y +
                    (_centerChildren
                        ? (height - (childSize.height - _inset * 2)) / 2
                        : 0) -
                    _inset,
              );
        }
        x += childSize.width - _inset * 2 + _spacing + extraGap;
      }
      y += height + _spacing;
    }
    return constraints.constrain(Size(width, y - _spacing));
  }

  @override
  void performLayout() => size = _layout(constraints, dry: false);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  Rect get paintBounds => (Offset.zero & size).inflate(4);
  @override
  Rect get semanticBounds => (Offset.zero & size).inflate(_inset);
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!(Offset.zero & size).inflate(_inset).contains(position)) return false;
    if (!hitTestChildren(result, position: position)) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
