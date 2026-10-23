import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:serverdeck_protocol/models.dart' show ThemePreference;

import 'bootstrap/bootstrap_controller.dart';
import 'bootstrap/trusted_native_bootstrap_host.dart';
import 'profiles/profile_controller.dart';
import 'profiles/profile_list.dart';
import 'profiles/startup_recovery.dart';
import 'profiles/recovery_view.dart';
import 'settings/settings_view.dart';
import 'shell/foundation_shell.dart';
import 'theme/brand_theme.dart';
import 'theme/motion.dart';

class FoundationApp extends StatefulWidget {
  const FoundationApp({super.key, this.bootstrap});
  final BootstrapController? bootstrap;
  @override
  State<FoundationApp> createState() => _FoundationAppState();
}

class _FoundationAppState extends State<FoundationApp>
    with WidgetsBindingObserver {
  late final BootstrapController controller;
  TrustedNativeBootstrapHost? _host;
  late final ProfileController profiles;
  late final StartupRecovery recovery;
  Future<void>? _closing;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final supplied = widget.bootstrap;
    if (supplied != null) {
      controller = supplied;
    } else {
      final host = TrustedNativeBootstrapHost();
      _host = host;
      controller = BootstrapController(
        client: host.client,
        prepare: host.prepare,
        ensureService: host.ensureService,
        recoverService: host.ensureService,
      );
      controller.retry().ignore();
    }
    profiles = ProfileController(bootstrap: controller);
    recovery = StartupRecovery(model: profiles);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _closeResources().ignore();
    super.dispose();
  }

  Future<void> _closeResources() => _closing ??= _close();

  Future<void> _close() async {
    _host?.dispose();
    recovery.dispose();
    profiles.dispose();
    try {
      await controller.close();
    } finally {
      await _host?.close();
    }
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    try {
      await _closeResources();
    } on Object {
      // Closing the window must remain possible after transport failure.
    }
    return AppExitResponse.exit;
  }

  @override
  Widget build(BuildContext context) => MediaQuery.fromView(
    view: View.of(context),
    child: Builder(
      builder: (context) => ListenableBuilder(
        listenable: profiles,
        builder: (context, child) => MaterialApp(
          title: 'ServerDeck',
          locale: const Locale('ru', 'RU'),
          supportedLocales: const [Locale('ru', 'RU')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: Motion.theme(
            BrandTheme.light,
            MediaQuery.disableAnimationsOf(context) ||
                (profiles.settings?.reduceMotion ?? false),
          ),
          darkTheme: Motion.theme(
            BrandTheme.dark,
            MediaQuery.disableAnimationsOf(context) ||
                (profiles.settings?.reduceMotion ?? false),
          ),
          themeAnimationStyle:
              MediaQuery.disableAnimationsOf(context) ||
                  (profiles.settings?.reduceMotion ?? false)
              ? AnimationStyle.noAnimation
              : null,
          themeMode: switch (profiles.settings?.theme) {
            ThemePreference.light => ThemeMode.light,
            ThemePreference.dark => ThemeMode.dark,
            _ => ThemeMode.system,
          },
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations:
                  MediaQuery.of(context).disableAnimations ||
                  (profiles.settings?.reduceMotion ?? false),
            ),
            child: child!,
          ),
          home: ListenableBuilder(
            listenable: controller,
            builder: (context, child) => FoundationShell(
              state: controller.state,
              reason: controller.reason,
              retryInProgress: controller.retryInProgress,
              recoveryAction: RecentOperationsButton(recovery: recovery),
              onRetry: () => controller.retry().ignore(),
              servers: RecoveryView(
                recovery: recovery,
                child: ProfileList(
                  controller: profiles,
                  controlClient: controller.client.trustedClient,
                ),
              ),
              settings: RecoveryView(
                recovery: recovery,
                child: SettingsView(controller: profiles),
              ),
              targetName: profiles.selected?.name,
              targetAddress: profiles.selected == null
                  ? null
                  : '${profiles.selected!.address}:${profiles.selected!.port}',
            ),
          ),
        ),
      ),
    ),
  );
}
