import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/theme/brand_theme.dart';

import '../support/design_automation_fixtures.dart';
import '../support/design_server_fixtures.dart';
import '../support/design_host.dart' show loadDesignFonts;

void main() {
  setUpAll(loadDesignFonts);
  test('observed target change then restoration retires a retained consent callback before paint', () {
    final captured = [DesignServerFixtures.profile(connectionRevision: '2')];
    final metadata = ValueNotifier(captured);
    final current = automationReviewGuard(
      () => automationTargetsUnchanged(
        [DesignServerFixtures.serverId],
        captured,
        metadata.value,
      ),
    );
    void observe() {
      current();
    }

    metadata.addListener(observe);
    var effects = 0;
    void retainedCallback() {
      if (current()) effects++;
    }

    expect(current(), isTrue);
    // Both changes are observed synchronously, with no pump/redraw in between.
    metadata.value = [
      DesignServerFixtures.profile(
        address: '192.0.2.99',
        connectionRevision: '2',
      ),
    ];
    metadata.value = [DesignServerFixtures.profile(connectionRevision: '2')];
    retainedCallback();
    expect(effects, 0);
    expect(current(), isFalse);
    final fresh = automationReviewGuard(
      () => automationTargetsUnchanged(
        [DesignServerFixtures.serverId],
        captured,
        metadata.value,
      ),
    );
    expect(fresh(), isTrue);
    metadata.removeListener(observe);
    metadata.dispose();
  });
  testWidgets('approval names its actual server before consent', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.light,
        home: Scaffold(
          body: AutomationPlanDecisionDialog(
            now: DesignAutomationFixtures.presentationNow,
            plan: DesignAutomationFixtures.plan(),
            serverProfiles: [
              DesignServerFixtures.profile(connectionRevision: '2'),
            ],
            automationProfile: DesignAutomationFixtures.profile(),
            approve: true,
            onBack: () {},
            onConfirm: () {},
          ),
        ),
      ),
    );
    expect(find.text('Синтетический сервер · 192.0.2.44:2222'), findsOneWidget);
  });

  testWidgets(
    'authoring JSON label remains complete after actual phone scroll',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final name = TextEditingController(text: 'Профиль');
      final description = TextEditingController(text: 'Описание');
      final body = TextEditingController(text: '{}');
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: AutomationProfileEditorDialog(
              name: name,
              description: description,
              body: body,
              validating: false,
              canValidate: true,
              onBodyChanged: (_) {},
              onClose: () {},
              onSave: () {},
              onValidate: () {},
            ),
          ),
        ),
      );
      final field = find.byType(TextField).last;
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      final label = find.text('Шаги и параметры профиля (JSON)');
      await tester.ensureVisible(label);
      await tester.pumpAndSettle();
      final paragraph = tester.renderObject<RenderParagraph>(label);
      expect(paragraph.didExceedMaxLines, isFalse);
      final text = paragraph.text.toPlainText();
      final lastGlyph = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: text.length - 1, extentOffset: text.length),
      );
      expect(lastGlyph, isNotEmpty);
      expect(
        lastGlyph.every(
          (box) => box.left >= 0 && box.right <= paragraph.size.width + 0.01,
        ),
        isTrue,
      );
      expect(tester.getRect(label).top, greaterThanOrEqualTo(0));
      expect(tester.getRect(label).bottom, lessThanOrEqualTo(800));
      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel('Шаги и параметры профиля (JSON)'),
        findsWidgets,
      );
      semantics.dispose();
      await tester.pumpWidget(const SizedBox());
      name.dispose();
      description.dispose();
      body.dispose();
    },
  );
}
