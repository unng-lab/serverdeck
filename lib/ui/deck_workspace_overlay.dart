import 'package:flutter/material.dart';

import 'deck_page.dart';

/// A guarded modal route presents a full page inside its actual caller viewport.
/// The caller supplies live bounds, including a growing phone navigation bar.
class DeckWorkspaceOverlay extends StatefulWidget {
  const DeckWorkspaceOverlay({
    super.key,
    required this.child,
    this.workspaceBounds,
    this.pageInsets,
  });
  final Widget child;
  final ValueGetter<Rect?>? workspaceBounds;
  final ValueGetter<EdgeInsetsGeometry>? pageInsets;

  @override
  State<DeckWorkspaceOverlay> createState() => _DeckWorkspaceOverlayState();
}

class _DeckWorkspaceOverlayState extends State<DeckWorkspaceOverlay> {
  final _viewportKey = GlobalKey();
  Rect? _paintedBounds;
  Offset _paintedOrigin = Offset.zero;
  bool _measurementPending = false;

  Offset _viewportOrigin() {
    final render = _viewportKey.currentContext?.findRenderObject();
    return render is RenderBox && render.attached && render.hasSize
        ? render.localToGlobal(Offset.zero)
        : Offset.zero;
  }

  void _measureAfterLayout() {
    if (_measurementPending || widget.workspaceBounds == null) return;
    _measurementPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementPending = false;
      if (!mounted) return;
      // Both routes may lay out in the same frame. Read again after the caller
      // has laid out its larger text/topbar/navigation, then repaint only when
      // its actual box changed. An unchanged box never schedules another frame.
      if (widget.workspaceBounds?.call() != _paintedBounds ||
          _viewportOrigin() != _paintedOrigin)
        setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    // Text scale and keyboard changes can alter caller bounds while the modal
    // constraints stay unchanged; depend on the complete MediaQuery here.
    final media = MediaQuery.of(context);
    _measureAfterLayout();
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height),
        child: LayoutBuilder(
          key: _viewportKey,
          builder: (context, constraints) {
            final bounds = widget.workspaceBounds?.call();
            _paintedBounds = bounds;
            _paintedOrigin = _viewportOrigin();
            _measureAfterLayout();
            // A departed owner cannot keep its private page visible. The route's
            // existing private gate and dismiss handler retain lifecycle ownership.
            if (widget.workspaceBounds != null && bounds == null)
              return const SizedBox.shrink();
            final width = MediaQuery.sizeOf(context).width;
            final padding = width <= 520
                ? const EdgeInsets.fromLTRB(16, 22, 16, 24)
                : width <= 1060
                ? const EdgeInsets.all(24)
                : const EdgeInsets.fromLTRB(28, 26, 28, 24);
            final page = DeckPageInsets(
              padding: widget.pageInsets?.call() ?? padding,
              child: widget.child,
            );
            if (bounds == null)
              return Material(color: deckColors(context)['bg'], child: page);
            // DialogRoute may already have consumed SafeArea/view padding.
            // Convert global caller coordinates using this actual viewport.
            final visible = bounds
                .shift(-_paintedOrigin)
                .intersect(Offset.zero & constraints.biggest);
            if (visible.isEmpty) return const SizedBox.shrink();
            return Stack(
              children: [
                Positioned.fromRect(
                  rect: visible,
                  child: Material(
                    color: deckColors(context)['bg'],
                    child: page,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
