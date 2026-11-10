import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/receipt_book.dart';
import 'package:serverdeck/journals/journal_owner.dart';
import 'package:serverdeck/journals/journal_view.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/profiles/profile_view.dart';
import 'package:serverdeck/software/software_models.dart';
import 'package:serverdeck/software/software_owner.dart';
import 'package:serverdeck/software/software_view.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_components.dart';

import '../fixtures/feature_harness.dart' show featureTurns;
import '../journals/journal_owner_test.dart' show FakeJournalConnection;
import '../software/software_view_test.dart' show SoftwareWidgetHarness;
import 'server_workflow_test.dart' show WorkflowOperations;

void main() {
  late SoftwareWidgetHarness h;
  late FakeJournalConnection port;
  late JournalsOwner journals;
  late SoftwareOwner software;
  late ProfileController controller;
  setUp(() {
    h = SoftwareWidgetHarness();
    port = FakeJournalConnection()..connected = false;
    journals = JournalsOwner(
      repository: h.repository,
      actor: h.actors.ui,
      connections: port,
      newId: h.newId,
      utcNow: h.clock.now,
      monotonicNow: h.clock.monotonic,
      schedule: h.clock.schedule,
    );
    software = SoftwareOwner(
      gate: h.gate,
      repository: h.repository,
      receipts: ReceiptBook(h.signer, h.clock.now),
      newId: h.newId,
      utcNow: h.clock.now,
    );
    final operations = WorkflowOperations()..profile = h.profile;
    controller = ProfileController(
      operations: operations,
      actor: h.actors.ui,
      newId: h.newId,
      poll: false,
    );
  });
  testWidgets(
    'software logs opens same profile and clears intent for manual tabs',
    (tester) async {
      try {
        final saved = await tester.runAsync(
          () => software.save(
            h.actors.ui,
            h.profile.profileId,
            SoftwareCardInput(
              name: 'Redis',
              version: null,
              service: 'redis.service',
              dataPaths: [],
              configPaths: [],
            ),
            mutationId: h.newId(),
          ),
        );
        final id = saved!.value!.entityId;
        await tester.pumpWidget(
          MaterialApp(
            theme: BrandTheme.dark,
            home: Scaffold(
              body: ProfileViewPanel(
                pickKey: () async => null,
                controller: controller,
                software: software,
                journals: journals,
              ),
            ),
          ),
        );
        await tester.runAsync(() => featureTurns());
        await tester.pumpAndSettle();
        await tester.tap(find.text(h.profile.displayName));
        await tester.runAsync(() => featureTurns());
        await tester.pumpAndSettle();
        expect(find.byType(SoftwareView), findsOneWidget);
        await tester.runAsync(() => featureTurns());
        await tester.pumpAndSettle();
        tester
            .widget<DeckButton>(find.byKey(ValueKey('software-logs-$id')))
            .onPressed!();
        await tester.pump();
        await tester.runAsync(() => featureTurns());
        await tester.pumpAndSettle();
        final view = tester.widget<JournalView>(find.byType(JournalView));
        expect(view.profileId, h.profile.profileId);
        expect(view.connectionRevision, h.profile.connectionRevision);
        expect(view.initialService, 'redis.service');
        expect(find.text('Источник: redis.service'), findsOneWidget);
        expect(port.requests, isEmpty);
        tester.widget<DeckTabs>(find.byType(DeckTabs)).onSelected!(0);
        await tester.pumpAndSettle();
        tester.widget<DeckTabs>(find.byType(DeckTabs)).onSelected!(1);
        await tester.pumpAndSettle();
        expect(
          tester.widget<JournalView>(find.byType(JournalView)).initialService,
          isNull,
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await tester.runAsync(() async {
          await software.dispose();
          await journals.dispose();
          await port.stream.close();
          await h.dispose();
        });
      }
    },
  );
}
