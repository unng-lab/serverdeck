import 'package:flutter/material.dart';

import '../ui/deck_components.dart';

/// A single owner-bound MCP route. Its nested Navigator owns every child prompt.
class OwnedSettingsRoute {
  DialogRoute<void>? _route;
  NavigatorState? _navigator;
  bool _retired = false;
  bool get isOpen => _route != null && !_retired;

  Future<void> show(
    BuildContext context, {
    required Widget child,
    String title = 'Настройки приложения',
    required VoidCallback onChanged,
  }) async {
    if (_retired || _route != null) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    late final DialogRoute<void> route;
    route = DialogRoute<void>(
      context: context,
      builder: (dialogContext) => DeckDialogLayout(
        title: title,
        child: SizedBox(
          height: MediaQuery.sizeOf(dialogContext).height * .6,
          child: Navigator(
            onGenerateRoute: (_) =>
                MaterialPageRoute<void>(builder: (_) => child),
          ),
        ),
        actions: [
          DeckButton(
            onPressed: () {
              if (route.isActive) navigator.removeRoute(route);
            },
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
    _route = route;
    _navigator = navigator;
    onChanged();
    try {
      await navigator.push<void>(route);
    } finally {
      if (identical(_route, route)) {
        _route = null;
        _navigator = null;
        onChanged();
      }
    }
  }

  void retire() {
    _retired = true;
    final route = _route, navigator = _navigator;
    _route = null;
    _navigator = null;
    if (route == null || navigator == null) return;
    // Retirement also occurs during owner build/dispose: mutate Navigator later.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator.mounted && route.isActive) navigator.removeRoute(route);
    });
  }
}
