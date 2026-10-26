import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:serverdeck_protocol/models.dart'
    show ThemePreference, ReadinessState, ErrorCode;

import 'bootstrap/bootstrap_controller.dart';
import 'bootstrap/local_api_client.dart';
import 'bootstrap/trusted_native_bootstrap_host.dart';
import 'profiles/profile_controller.dart';
import 'profiles/profile_list.dart';
import 'profiles/startup_recovery.dart';
import 'profiles/recovery_view.dart';
import 'settings/settings_view.dart';
import 'software/software_panel.dart';
import 'shell/foundation_shell.dart';
import 'shell/private_session.dart';
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
  late final StreamSubscription<ClientConnectionState> _privateConnections;
  late final StreamSubscription<ErrorCode> _privateErrors;
  late final StreamSubscription<ClientSnapshot> _privateSnapshots;
  late int _observedReadinessEpoch;
  late int _privateEpoch;
  bool _privateRevoked = false, _privateClientClosed = false;
  ErrorCode? _privateReason;
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
    _observedReadinessEpoch = controller.readinessEpoch;
    _privateEpoch = controller.readinessEpoch;
    controller.addListener(_observePrivateReadiness);
    _privateConnections = controller.client.states.listen((state) {
      if (!mounted) return;
      switch (state) {
        case ClientConnectionState.closed:
          _privateClientClosed = true;
          _retirePrivateSession(ErrorCode.serviceUnavailable);
        case ClientConnectionState.disconnected:
        case ClientConnectionState.connecting:
          _retirePrivateSession(ErrorCode.serviceUnavailable);
        case ClientConnectionState.connected:
          // A new transport alone never restores old private content. Wait
          // for the existing model to accept a current authorized snapshot.
          _privateClientClosed = false;
      }
    });
    _privateErrors = controller.client.snapshotErrors.listen((code) {
      if (code == ErrorCode.unauthorized) _retirePrivateSession(code);
    });
    _privateSnapshots = controller.client.snapshots.listen((snapshot) {
      // ProfileController subscribed first and remains the DTO/generation
      // owner. This is only a UI visibility gate, not new service authority.
      if (!mounted ||
          !_privateRevoked ||
          _privateClientClosed ||
          controller.state != ReadinessState.ready ||
          snapshot.generation != controller.client.generation ||
          !profiles.loaded ||
          profiles.storeRevision != snapshot.storeRevision) {
        return;
      }
      setState(() {
        _privateRevoked = false;
        _privateReason = null;
      });
    });
  }

  void _observePrivateReadiness() {
    if (!mounted || _observedReadinessEpoch == controller.readinessEpoch)
      return;
    setState(() {
      _observedReadinessEpoch = controller.readinessEpoch;
      _privateEpoch++;
      if (controller.state != ReadinessState.ready) {
        _privateRevoked = true;
        _privateReason = controller.reason;
      }
    });
  }

  void _retirePrivateSession(ErrorCode reason) {
    if (!mounted) return;
    setState(() {
      _privateEpoch++;
      _privateRevoked = true;
      _privateReason = reason;
    });
  }

  ReadinessState get _visibleReadiness =>
      controller.state == ReadinessState.ready && _privateRevoked
      ? ReadinessState.unavailable
      : controller.state;

  ErrorCode? get _visibleReason =>
      controller.state == ReadinessState.ready && _privateRevoked
      ? _privateReason
      : controller.reason;

  Widget _privateFeature(String section, Widget child) => KeyedSubtree(
    // A loss and recovery can happen before the next frame. Retire the old
    // owner even when that frame already has a current authorized snapshot.
    key: ValueKey('private-$section-$_privateEpoch'),
    child: child,
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_observePrivateReadiness);
    _privateConnections.cancel().ignore();
    _privateErrors.cancel().ignore();
    _privateSnapshots.cancel().ignore();
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
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => PrivateSessionScope(
                authorized: _visibleReadiness == ReadinessState.ready,
                epoch: _privateEpoch,
                child: child!,
              ),
            ),
          ),
          home: ListenableBuilder(
            listenable: controller,
            builder: (context, child) => FoundationShell(
              state: _visibleReadiness,
              reason: _visibleReason,
              retryInProgress: controller.retryInProgress,
              recoveryAction: RecentOperationsButton(recovery: recovery),
              onRetry: () => controller.retry().ignore(),
              servers: _privateFeature(
                'servers',
                RecoveryView(
                  recovery: recovery,
                  child: ProfileList(
                    controller: profiles,
                    controlClient: controller.client.trustedClient,
                  ),
                ),
              ),
              settings: _privateFeature(
                'settings',
                RecoveryView(
                  recovery: recovery,
                  child: SettingsView(controller: profiles),
                ),
              ),
              software: _privateFeature(
                'software',
                RecoveryView(
                  recovery: recovery,
                  child: SoftwarePanel(
                    profiles: profiles,
                    client: controller.client.trustedClient,
                  ),
                ),
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
