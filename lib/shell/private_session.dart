import 'package:flutter/material.dart';

/// UI visibility follows the existing authorized bootstrap session.
/// This scope grants no authority and never changes service state.
class PrivateSessionScope extends InheritedWidget {
  const PrivateSessionScope({
    super.key,
    required this.authorized,
    required this.epoch,
    required super.child,
  });

  final bool authorized;
  final int epoch;

  static PrivateSessionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PrivateSessionScope>();

  @override
  bool updateShouldNotify(PrivateSessionScope oldWidget) =>
      authorized != oldWidget.authorized || epoch != oldWidget.epoch;
}

/// A retired consent/editor route never reappears in a new ready session.
class PrivateDialogGate extends StatefulWidget {
  const PrivateDialogGate({
    super.key,
    required this.launchEpoch,
    required this.builder,
  });

  final int? launchEpoch;
  final WidgetBuilder builder;

  @override
  State<PrivateDialogGate> createState() => _PrivateDialogGateState();
}

class _PrivateDialogGateState extends State<PrivateDialogGate> {
  bool _retired = false;
  bool _removalScheduled = false;

  @override
  Widget build(BuildContext context) {
    final session = PrivateSessionScope.maybeOf(context);
    if (widget.launchEpoch != null &&
        (session == null ||
            !session.authorized ||
            session.epoch != widget.launchEpoch)) {
      _retired = true;
    }
    if (!_retired) return widget.builder(context);

    // Remove private content in this build, before retiring the route. A route
    // covered by a nested picker/dialog must also be removed, not kept alive.
    if (!_removalScheduled) {
      _removalScheduled = true;
      final route = ModalRoute.of(context);
      final navigator = Navigator.maybeOf(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && route != null && route.isActive && navigator != null) {
          navigator.removeRoute(route);
        }
      });
    }
    return const SizedBox.shrink();
  }
}
