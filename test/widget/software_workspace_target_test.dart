import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/profiles/profile_list.dart';
import 'package:serverdeck/shell/base_workspace.dart';
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/software/software_panel.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck/ui/deck_components.dart';
import 'package:serverdeck_protocol/models.dart';

import '../contract/profile_controller_test.dart' as fixture;
import '../support/design_host.dart' show loadDesignFonts;
import '../support/design_scenarios.dart';

const _otherId = '33333333-3333-4333-8333-333333333333';

void main() {
  setUpAll(loadDesignFonts);

  testWidgets('software inherits the opened RAM target rather than saved A', (
    tester,
  ) async {
    final harness = await _open(tester);
    try {
      final target = harness.profiles.profiles.last;
      // Use the production list's navigation callback. No native authenticated
      // client is fabricated: the next page still exposes its actual target.
      tester.widget<ProfileList>(find.byType(ProfileList)).onOpenProfile!(
        target,
      );
      await tester.pumpAndSettle();
      await _navigate(tester, FoundationSection.software);
      expect(_softwareTarget(tester), target.id);
      expect(find.textContaining('Server B · 192.0.2.2'), findsOneWidget);
      _expectNoEffects(harness);
    } finally {
      await _close(tester, harness);
    }
  });

  testWidgets('software selection becomes the shared logs and jobs target', (
    tester,
  ) async {
    final harness = await _open(tester);
    try {
      await _navigate(tester, FoundationSection.software);
      expect(_softwareTarget(tester), fixture.profileId);
      await _choose(tester, 'Server B');
      expect(_softwareTarget(tester), _otherId);
      for (final section in [FoundationSection.logs, FoundationSection.jobs]) {
        await _navigate(tester, section);
        final selector = tester.widget<MotionDropdown<String>>(
          find.byType(MotionDropdown<String>),
        );
        expect(selector.initialValue, _otherId);
      }
      await _navigate(tester, FoundationSection.software);
      expect(_softwareTarget(tester), _otherId);
      await _choose(tester, 'Saved profile');
      await _navigate(tester, FoundationSection.logs);
      expect(
        tester
            .widget<MotionDropdown<String>>(find.byType(MotionDropdown<String>))
            .initialValue,
        fixture.profileId,
      );
      _expectNoEffects(harness);
    } finally {
      await _close(tester, harness);
    }
  });

  testWidgets('deleted explicit RAM target never falls back to saved A', (
    tester,
  ) async {
    final harness = await _open(tester);
    try {
      final target = harness.profiles.profiles.last;
      tester.widget<ProfileList>(find.byType(ProfileList)).onOpenProfile!(
        target,
      );
      await tester.pumpAndSettle();
      _publish(harness, revision: '3', includeOther: false);
      expect(harness.profiles.profiles, hasLength(1));
      await tester.pumpAndSettle();
      await _navigate(tester, FoundationSection.software);
      expect(_softwareTarget(tester), isNull);
      expect(find.text('Сервер не выбран'), findsOneWidget);
      expect(find.textContaining('Saved profile ·'), findsNothing);
      await _navigate(tester, FoundationSection.logs);
      expect(
        tester
            .widget<MotionDropdown<String>>(find.byType(MotionDropdown<String>))
            .initialValue,
        isNull,
      );
      _expectNoEffects(harness);
    } finally {
      await _close(tester, harness);
    }
  });

  testWidgets('a retired software chooser cannot change the new private page', (
    tester,
  ) async {
    final epoch = ValueNotifier(0);
    final harness = await _open(tester, epoch: epoch);
    try {
      await _navigate(tester, FoundationSection.software);
      await tester.tap(find.widgetWithText(TextButton, 'Изменить сервер'));
      await tester.pumpAndSettle();
      final oldChoice = tester
          .widget<DeckSurface>(
            find.ancestor(
              of: find.text('Server B'),
              matching: find.byType(DeckSurface),
            ),
          )
          .onTap!;
      epoch.value++;
      await tester.pumpAndSettle();
      oldChoice();
      await tester.pumpAndSettle();
      expect(_softwareTarget(tester), fixture.profileId);
      await _navigate(tester, FoundationSection.logs);
      expect(
        tester
            .widget<MotionDropdown<String>>(find.byType(MotionDropdown<String>))
            .initialValue,
        fixture.profileId,
      );
      _expectNoEffects(harness);
    } finally {
      await _close(tester, harness);
      epoch.dispose();
    }
  });

  testWidgets(
    'an earlier software callback stays retired after target restore',
    (tester) async {
      final harness = await _open(tester);
      try {
        await _navigate(tester, FoundationSection.software);
        final earlier = tester
            .widget<SoftwarePanel>(find.byType(SoftwarePanel))
            .onServerSelected!;
        earlier(_otherId);
        await tester.pumpAndSettle();
        expect(_softwareTarget(tester), _otherId);
        tester
            .widget<SoftwarePanel>(find.byType(SoftwarePanel))
            .onServerSelected!(fixture.profileId);
        await tester.pumpAndSettle();
        earlier(_otherId);
        await tester.pumpAndSettle();
        expect(_softwareTarget(tester), fixture.profileId);
        _expectNoEffects(harness);
      } finally {
        await _close(tester, harness);
      }
    },
  );

  testWidgets(
    'a late chooser result cannot replace a changed and restored target',
    (tester) async {
      final harness = await _open(tester);
      try {
        await _navigate(tester, FoundationSection.software);
        await tester.tap(find.widgetWithText(TextButton, 'Изменить сервер'));
        await tester.pumpAndSettle();
        final oldChoice = tester
            .widget<DeckSurface>(
              find.ancestor(
                of: find.text('Server B'),
                matching: find.byType(DeckSurface),
              ),
            )
            .onTap!;
        tester
            .widget<SoftwarePanel>(
              find.byType(SoftwarePanel, skipOffstage: false),
            )
            .onServerSelected!(_otherId);
        await tester.pumpAndSettle();
        tester
            .widget<SoftwarePanel>(
              find.byType(SoftwarePanel, skipOffstage: false),
            )
            .onServerSelected!(fixture.profileId);
        await tester.pumpAndSettle();
        oldChoice();
        await tester.pumpAndSettle();
        expect(_softwareTarget(tester), fixture.profileId);
        _expectNoEffects(harness);
      } finally {
        await _close(tester, harness);
      }
    },
  );
}

String? _softwareTarget(WidgetTester tester) => tester
    .widget<SoftwareServerSelector>(find.byType(SoftwareServerSelector))
    .selectedId;

Future<void> _navigate(WidgetTester tester, FoundationSection section) async {
  final control = find.byKey(ValueKey('foundation-navigation-${section.name}'));
  await tester.ensureVisible(control);
  await tester.tap(control);
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String name) async {
  await tester.tap(find.widgetWithText(TextButton, 'Изменить сервер'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

Future<DesignScenarioHarness> _open(
  WidgetTester tester, {
  ValueNotifier<int>? epoch,
}) async {
  tester.view.physicalSize = const Size(1100, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = await DesignScenarioHarness.create();
  _publish(harness);
  Widget workspace(int value) => BaseWorkspace(
    profiles: harness.profiles,
    recovery: harness.recovery,
    client: null,
    state: ReadinessState.ready,
    privateEpoch: value,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: Motion.theme(BrandTheme.dark, true),
      home: epoch == null
          ? workspace(0)
          : ValueListenableBuilder<int>(
              valueListenable: epoch,
              builder: (_, value, _) => workspace(value),
            ),
    ),
  );
  await tester.pumpAndSettle();
  harness.client.reads.clear();
  harness.client.refreshes = 0;
  return harness;
}

void _publish(
  DesignScenarioHarness harness, {
  String revision = '2',
  bool includeOther = true,
}) {
  final base = fixture.snapshot(revision: revision);
  final first =
      (base.profiles.result['profiles'] as List).single as Map<String, Object?>;
  harness.client.events.add(
    ClientSnapshot(
      ApiReply(harness.client.generationId, {
        'storeRevision': revision,
        'profiles': [
          first,
          if (includeOther)
            {
              ...first,
              'id': _otherId,
              'name': 'Server B',
              'address': '192.0.2.2',
            },
        ],
      }),
      base.settings,
    ),
  );
}

void _expectNoEffects(DesignScenarioHarness harness) {
  expect(harness.profiles.settings!.selectedProfileId, fixture.profileId);
  expect(harness.client.mutations, isEmpty);
  expect(harness.client.reads, isEmpty);
  expect(harness.client.refreshes, 0);
}

Future<void> _close(WidgetTester tester, DesignScenarioHarness harness) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  await harness.close();
}
