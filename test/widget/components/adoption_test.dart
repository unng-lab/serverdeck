import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/profiles/profile_list.dart';
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_components.dart';
import 'package:serverdeck_protocol/models.dart' hide SettingsView;

import '../../support/component_cases.dart';

const profile = ProfileView(
  id: 'profile-web',
  revision: '1',
  name: 'atlas-web',
  address: '192.0.2.14',
  port: 22,
  sshUser: 'demo-user',
  tags: [],
  credentialRevision: '1',
  connectionRevision: '1',
  trustRevision: '1',
  createdAt: '2026-11-01T10:00:00Z',
  updatedAt: '2026-11-01T10:00:00Z',
  credentialKind: CredentialKind.none,
  credentialConfigured: false,
);

/// A projection fixture only: it neither instantiates an engine nor asserts
/// service authorization. Tests exercise the real ProfileList composition.
class ProfileFixture extends ChangeNotifier implements ProfileController {
  @override
  bool get loaded => true;
  @override
  List<ProfileView> get profiles => const [profile];
  @override
  ProfileView? get selected => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'actual server list uses shared collection and keeps expansion at resize',
    (tester) async {
      final model = ProfileFixture();
      addTearDown(model.dispose);
      await tester.pumpWidget(componentHarness(ProfileList(controller: model)));
      expect(find.byType(DeckCollection<ProfileView>), findsOneWidget);
      await tester.tap(find.text('atlas-web'));
      await tester.pumpAndSettle();
      expect(find.text('Пользователь SSH: demo-user'), findsOneWidget);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpAndSettle();
      expect(find.text('Пользователь SSH: demo-user'), findsOneWidget);
      expect(tester.takeException(), null);
    },
  );

  testWidgets(
    'actual jobs use shared rows and gate selection without effects',
    (tester) async {
      var selected = 0;
      Widget jobs(bool allowed) => componentHarness(
        AutomationJobsSection(
          jobs: const [
            {
              'job': {
                'id': 'job-demo-1',
                'state': 'running',
                'updatedAt': '2026-11-01T10:42:18Z',
              },
            },
          ],
          jobObservations: const {},
          events: const [],
          loaded: true,
          hasMore: false,
          droppedEvents: 0,
          canCancel: false,
          canReconcile: false,
          actions: AutomationActionAvailability(
            read: true,
            mutate: false,
            select: allowed,
          ),
          onRefresh: () {},
          onRefreshAuthorities: () {},
          onSelect: (_) => selected++,
          onMore: () {},
          onShowPlan: () {},
          onCancel: () {},
          onReconcile: () {},
        ),
      );
      await tester.pumpWidget(jobs(false));
      expect(find.byType(DeckCollection<Map<String, Object?>>), findsOneWidget);
      expect(find.text('Открыть'), findsNothing);
      expect(selected, 0);
      await tester.pumpWidget(jobs(true));
      await tester.tap(find.text('Открыть'));
      expect(selected, 1);
    },
  );

  testWidgets(
    'shell uses shared page, preserves draft on resize, retires it on ready loss',
    (tester) async {
      final controller = TextEditingController(text: 'private draft');
      addTearDown(controller.dispose);
      var ready = true;
      Widget shell() => MaterialApp(
        theme: BrandTheme.dark,
        home: FoundationShell(
          state: ready ? ReadinessState.ready : ReadinessState.unavailable,
          targetName: 'private-target',
          targetAddress: '192.0.2.14',
          servers: TextField(controller: controller),
        ),
      );
      await tester.pumpWidget(shell());
      expect(find.byType(DeckPageBody), findsOneWidget);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(shell());
      await tester.pump();
      expect(find.text('private draft'), findsOneWidget);
      ready = false;
      await tester.pumpWidget(shell());
      await tester.pump();
      expect(find.text('private draft'), findsNothing);
      expect(find.textContaining('private-target'), findsNothing);
      expect(tester.takeException(), null);
    },
  );
}
