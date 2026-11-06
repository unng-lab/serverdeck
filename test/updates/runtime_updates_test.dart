import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/runtime/runtime_coordinator.dart';
import 'package:serverdeck/runtime/runtime_view.dart';
import 'package:serverdeck/runtime/application_settings_view.dart';
import 'package:serverdeck/mcp/settings_controller.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/updates/update_owner.dart';

import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/profiles/profile_view.dart';

import '../runtime/fakes.dart';
import '../fixtures/feature_harness.dart';

final class _Port implements UpdatePort {
  int reads = 0, downloads = 0, checks = 0;
  @override
  Future<UpdateSnapshot> snapshot() async {
    reads++;
    return const UpdateSnapshot(
      currentVersion: '0.1.0',
      enabled: false,
      state: UpdateState.available,
      offer: UpdateOffer(
        version: '0.2.0',
        notes: 'Synthetic release notes',
        publishedUtc: 1700000000,
        setupSize: 1234,
        platform: 'windows-x64',
        bootstrapAbi: 1,
        storeFormat: 2,
        compatibility: 'compatible',
        compatibilityReason: 'Compatible',
      ),
    );
  }

  @override
  Future<bool> check() async {
    checks++;
    return true;
  }

  @override
  Future<bool> download(String version) async {
    downloads++;
    return true;
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<void> setEnabled(bool enabled) async {}
  @override
  Future<void> defer() async {}
}

void main() {
  testWidgets('current version status is retained by the server workspace', (
    tester,
  ) async {
    final platform = FakePlatform()..release.value = '7.6.4325';
    final store = FakeStore();
    final runtime = RuntimeCoordinator(
      platform: platform,
      store: store,
      epoch: 'owner',
    );
    addTearDown(runtime.dispose);
    addTearDown(platform.controller.close);
    await runtime.start();
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.light,
        home: RuntimeView(runtime: runtime),
      ),
    );
    final status = tester
        .widget<FoundationShell>(find.byType(FoundationShell))
        .status!;
    final h = FeatureHarness();
    final id = await h.create();
    h.repository.state.profiles[id]!.displayName = 'Synthetic server';
    final controller = ProfileController(
      operations: h.operations,
      actor: h.actors.ui,
      newId: h.newId,
      changes: h.connections.changes,
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.light,
          home: ProfileViewPanel(
            controller: controller,
            pickKey: () async => null,
            applicationStatus: status,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Версия ServerDeck'), findsOneWidget);
      expect(find.text('7.6.4325'), findsOneWidget);
      await tester.tap(find.text('Synthetic server'));
      await tester.pumpAndSettle();
      expect(find.text('7.6.4325'), findsOneWidget);
      expect(store.opens, 1);
      expect(h.sessions, isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      final closing = h.dispose();
      await tester.pump();
      await closing;
    }
  });
  testWidgets(
    'updates and MCP remain reachable in the same global settings owner',
    (tester) async {
      final h = FeatureHarness();
      final settings = McpSettingsController(
        owner: h.grants,
        actor: h.actors.ui,
        retryTransport: () async {},
        transportError: () => null,
        poll: false,
      );
      final port = _Port();
      final updates = UpdateOwner(port: port, currentVersion: '0.1.0');
      addTearDown(settings.dispose);
      addTearDown(updates.dispose);
      try {
        await updates.start();
        await tester.pumpWidget(
          MaterialApp(
            theme: BrandTheme.light,
            home: Scaffold(
              body: ApplicationSettingsView(updates: updates, mcp: settings),
            ),
          ),
        );
        expect(find.text('Synthetic release notes'), findsOneWidget);
        await tester.tap(find.text('MCP'));
        await tester.pumpAndSettle();
        expect(find.text('Доступ MCP'), findsOneWidget);
        expect(find.text('Разрешить MCP'), findsOneWidget);
        await tester.tap(find.text('Обновления'));
        await tester.pumpAndSettle();
        expect(find.text('Synthetic release notes'), findsOneWidget);
        expect(port.downloads, 0);
        expect(h.repository.state.grants, isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox());
        final cleanup = h.dispose();
        await tester.pump();
        await cleanup;
      }
    },
  );
  testWidgets(
    'global updates start only after storage readiness and retire nested consent',
    (tester) async {
      final platform = FakePlatform()..release.value = '7.6.4325';
      final store = FakeStore()..failOpen = true;
      final port = _Port();
      final updates = UpdateOwner(port: port, currentVersion: '0.1.0');
      final runtime = RuntimeCoordinator(
        platform: platform,
        store: store,
        epoch: 'owner',
      )..register(updates);
      addTearDown(runtime.dispose);
      addTearDown(platform.controller.close);
      await runtime.start();
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.light,
          home: RuntimeView(runtime: runtime, updates: updates),
        ),
      );
      expect(port.reads, 0);
      expect(find.text('7.6.4325'), findsOneWidget);
      expect(find.text('Настройки приложения'), findsNothing);
      store.failOpen = false;
      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle();
      expect(port.reads, 1);
      expect(find.text('7.6.4325'), findsOneWidget);
      expect(find.text('0.2.0'), findsNothing);
      await tester.tap(find.text('Настройки приложения'));
      await tester.pumpAndSettle();
      expect(find.textContaining('0.1.0'), findsWidgets);
      expect(find.text('Synthetic release notes'), findsOneWidget);
      await tester.ensureVisible(find.text('Подготовить обновление'));
      await tester.tap(find.text('Подготовить обновление'));
      await tester.pumpAndSettle();
      expect(port.downloads, 0);
      await runtime.requestExit();
      await tester.pumpAndSettle();
      expect(runtime.state, RuntimeState.terminated);
      expect(find.text('Synthetic release notes'), findsNothing);
      expect(port.downloads, 0);
      expect(port.checks, 0);
    },
  );
}
