import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:serverdeck_windows/engine_worker.dart';

import '../app.dart';
import '../shell/foundation_shell.dart';
import 'desktop_lifecycle.dart';
import 'native_desktop_platform.dart';

/// Tray lifetime survives removal of every private window subtree/client.
final class DesktopApplication extends StatefulWidget {
  const DesktopApplication({super.key});
  @override
  State<DesktopApplication> createState() => _DesktopApplicationState();
}

final class _DesktopApplicationState extends State<DesktopApplication>
    with WidgetsBindingObserver {
  late final DesktopLifetime _lifetime;
  late final StreamSubscription<DesktopViewState> _views;
  late DesktopViewState _view;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifetime = DesktopLifetime(
      engine: desktopEngineController(),
      platform: NativeDesktopPlatform(),
    );
    _view = _lifetime.view;
    _views = _lifetime.views.listen((view) {
      if (mounted) setState(() => _view = view);
    });
    _lifetime.initialize().ignore();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await _lifetime.closeWindow();
    // Only the lifecycle's native finishExit can destroy the process window.
    return AppExitResponse.cancel;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _views.cancel().ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _view.visible
      ? FoundationApp(
          key: ValueKey(_view.epoch),
          section: FoundationSection.values.byName(_view.section.name),
          navigationEpoch: _view.navigationEpoch,
          onSectionChanged: (section) => _lifetime.rememberSection(
            DesktopSection.values.byName(section.name),
          ),
        )
      : const SizedBox.shrink();
}
