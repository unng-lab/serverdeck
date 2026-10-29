import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/servers/server_compositions.dart';
import 'package:serverdeck/ui/deck_icon.dart';
import 'package:serverdeck_protocol/models.dart';

import '../support/design_automation_fixtures.dart';
import '../support/design_fonts.dart';
import '../support/design_server_fixtures.dart';

void main() {
  setUpAll(loadDesignFonts);
  for (final frame in const [
    Size(1100, 760),
    Size(800, 600),
    Size(390, 800),
    Size(360, 800),
  ]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'T178 actual preflight hero $frame dark=$dark scale=$scale',
          (tester) async {
            tester.view.physicalSize = frame;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final anchor = GlobalKey();
            var effects = 0;
            final base = DesignServerFixtures.profile(connectionRevision: '2');
            final profile = ProfileView(
              id: base.id,
              revision: base.revision,
              name: 'Рабочий сервер с длинным именем αβγ — отдел разработки',
              address: base.address,
              port: base.port,
              sshUser: base.sshUser,
              tags: base.tags,
              credentialRevision: base.credentialRevision,
              connectionRevision: base.connectionRevision,
              trustRevision: base.trustRevision,
              createdAt: base.createdAt,
              updatedAt: base.updatedAt,
              credentialKind: base.credentialKind,
              credentialConfigured: base.credentialConfigured,
            );
            final theme = dark ? BrandTheme.dark : BrandTheme.light;
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: AutomationPlanSection(
                      plan: DesignAutomationFixtures.plan(),
                      planAnchor: anchor,
                      showPreflight: true,
                      runnable: true,
                      expired: false,
                      actions: const AutomationActionAvailability(
                        read: true,
                        mutate: true,
                        select: true,
                      ),
                      serverProfiles: [profile],
                      currentServerId: DesignAutomationFixtures.serverId,
                      automationProfile: DesignAutomationFixtures.profile(),
                      sourceRevision: DesignAutomationFixtures.revision(),
                      onApprove: () => effects++,
                      onDeny: () => effects++,
                      onApply: () => effects++,
                      onRefresh: () => effects++,
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final hero = find.byKey(anchor);
            expect(hero, findsOneWidget);
            final phone = frame.width <= 520;
            final colors = theme.extension<BrandColors>()!;
            final state = find.descendant(
              of: hero,
              matching: find.text('План готов к подтверждению'),
            );
            final contextLine = find.descendant(
              of: hero,
              matching: find.textContaining('Цель:'),
            );
            for (final text in [state, contextLine]) {
              final widget = tester.widget<Text>(text);
              final style = DefaultTextStyle.of(tester.element(text)).style
                  .merge(widget.style);
              expect(style.color, colors['muted']);
              expect(style.fontSize, 14);
              expect(style.height, closeTo((phone ? 24 : 22) / 14, .001));
              expect(widget.textAlign, TextAlign.center);
              expect(tester.getSize(text).width, lessThanOrEqualTo(440.1));
            }
            expect(
              tester.widget<Text>(contextLine).data,
              contains(profile.name),
            );
            expect(
              tester.getRect(contextLine).top,
              closeTo(tester.getRect(state).bottom, 1),
            );
            final title = find.descendant(
              of: hero,
              matching: find.text('Проверка готовности к установке'),
            );
            final titleStyle = tester.widget<Text>(title).style!;
            expect(titleStyle.fontSize, phone ? 22 : 20);
            expect(titleStyle.height, closeTo(phone ? 30 / 22 : 28 / 20, .001));
            final emblem = find.descendant(
              of: hero,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Container &&
                    widget.decoration is BoxDecoration &&
                    (widget.decoration! as BoxDecoration).shape ==
                        BoxShape.circle,
              ),
            );
            expect(tester.getSize(emblem), Size.square(phone ? 56 : 64));
            expect(
              tester.getRect(title).top - tester.getRect(emblem).bottom,
              closeTo(18, 1),
            );
            expect(
              tester.getRect(state).top - tester.getRect(title).bottom,
              closeTo(8, 1),
            );
            final icon = tester.widget<DeckIcon>(
              find.descendant(of: emblem, matching: find.byType(DeckIcon)),
            );
            expect(icon.size, 28);
            expect(icon.color, colors['accent']);
            expect(effects, 0);
            expect(tester.takeException(), isNull);
            expect(
              tester.getRect(emblem).top - tester.getRect(hero).top,
              closeTo((phone ? 28 : 30) + 1, 1),
            );
            expect(
              tester.getRect(title).left,
              greaterThanOrEqualTo(
                tester.getRect(hero).left + (phone ? 16 : 20),
              ),
            );
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: const Scaffold(
                  body: SingleChildScrollView(
                    child: ServerStatusBody(
                      title: 'Проверка службы',
                      facts: {'Состояние': 'Запуск', 'Этап': 'Ожидание'},
                      actions: [],
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final status = find.byType(ServerStatusBody);
            final statusEmblem = find.descendant(
              of: status,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Container &&
                    widget.decoration is BoxDecoration &&
                    (widget.decoration! as BoxDecoration).shape ==
                        BoxShape.circle,
              ),
            );
            expect(
              tester.getRect(find.text('Проверка службы')).top -
                  tester.getRect(statusEmblem).bottom,
              closeTo(18, 1),
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
}
