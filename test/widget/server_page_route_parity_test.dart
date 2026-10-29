import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/servers/server_sections.dart';
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck/ui/deck_page.dart';
import 'package:serverdeck/ui/deck_workspace_overlay.dart';
import 'package:serverdeck_protocol/models.dart' show ReadinessState;

import '../support/design_fonts.dart';
import '../support/design_server_fixtures.dart';

void main() {
  setUpAll(loadDesignFonts);
  for (final dark in [false, true]) {
    testWidgets(
      'actual record route uses caller viewport through resize and returns focus $dark',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1100, 760);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetViewInsets);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        final scale = ValueNotifier(1.0);
        final workspaceKey = GlobalKey();
        final launcher = FocusNode();
        final profile = DesignServerFixtures.profile();
        final record = DesignServerFixtures.record(
          message: 'Captured exact message',
        );
        final recordContext = ServerLogRecordContext.capture(
          profile,
          DesignServerFixtures.logs(records: [record]),
        );
        var opened = 0, closed = 0;
        BuildContext? owner;
        Rect? bounds() {
          final context = workspaceKey.currentContext;
          if (context == null) return null;
          final render = context.findRenderObject();
          return render is RenderBox && render.attached && render.hasSize
              ? render.localToGlobal(Offset.zero) & render.size
              : null;
        }

        await tester.pumpWidget(
          ValueListenableBuilder<double>(
            valueListenable: scale,
            builder: (context, value, _) => MaterialApp(
              theme: Motion.theme(
                dark ? BrandTheme.dark : BrandTheme.light,
                true,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(value),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: FoundationShell(
                state: ReadinessState.ready,
                section: FoundationSection.logs,
                contentBuilder: (context, _) => Builder(
                  builder: (context) {
                    owner = context;
                    return SizedBox.expand(
                      key: workspaceKey,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: OutlinedButton(
                          focusNode: launcher,
                          onPressed: () {
                            opened++;
                            showMotionDialog<void>(
                              context: context,
                              barrierColor: Colors.transparent,
                              barrierDismissible: true,
                              builder: (dialog) => ServerLogRecordDialog(
                                workspaceBounds: bounds,
                                pageInsets: () => DeckPageInsets.of(owner!),
                                recordContext: recordContext,
                                record: record,
                                onClose: () {
                                  closed++;
                                  Navigator.pop(dialog);
                                },
                              ),
                            );
                          },
                          child: const Text('Открыть запись'),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        launcher.requestFocus();
        await tester.pump();
        await tester.tap(find.text('Открыть запись'));
        await tester.pumpAndSettle();
        final state = tester.element(find.byType(ServerLogRecordDialog));
        for (final size in const [
          Size(1100, 760),
          Size(800, 600),
          Size(390, 800),
          Size(360, 800),
        ]) {
          for (final textScale in [1.0, 2.0]) {
            tester.view.physicalSize = size;
            scale.value = textScale;
            await tester.pumpAndSettle();
            expect(
              tester.element(find.byType(ServerLogRecordDialog)),
              same(state),
            );
            final viewport = tester.getRect(
              find.descendant(
                of: find.byType(DeckWorkspaceOverlay),
                matching: find.byType(DeckPage),
              ),
            );
            expect(viewport, bounds());
            expect(viewport.left, greaterThanOrEqualTo(0));
            expect(viewport.right, lessThanOrEqualTo(size.width));
            expect(viewport.bottom, lessThanOrEqualTo(size.height));
            expect(find.text(profile.name), findsOneWidget);
            expect(
              find.text('${profile.address}:${profile.port}'),
              findsOneWidget,
            );
            expect(find.text('Captured exact message'), findsOneWidget);
            expect(opened, 1);
            expect(closed, 0);
            expect(tester.takeException(), isNull);
          }
        }
        tester.view.viewPadding = FakeViewPadding(top: 24, bottom: 16);
        tester.view.padding = FakeViewPadding(top: 24, bottom: 16);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(
            find.descendant(
              of: find.byType(DeckWorkspaceOverlay),
              matching: find.byType(DeckPage),
            ),
          ),
          bounds(),
        );
        for (final keyboard in [180.0, 0.0]) {
          tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
          // The OS removes bottom safe padding while the keyboard covers it;
          // viewPadding retains the physical device inset.
          tester.view.padding = FakeViewPadding(
            top: 24,
            bottom: keyboard > 0 ? 0 : 16,
          );
          await tester.pumpAndSettle();
          final viewport = tester.getRect(
            find.descendant(
              of: find.byType(DeckWorkspaceOverlay),
              matching: find.byType(DeckPage),
            ),
          );
          expect(viewport, bounds());
          expect(viewport.bottom, lessThanOrEqualTo(800 - keyboard));
          expect(
            tester.element(find.byType(ServerLogRecordDialog)),
            same(state),
          );
          expect(find.text('Captured exact message'), findsOneWidget);
          expect(opened, 1);
          expect(closed, 0);
          expect(tester.takeException(), isNull);
        }
        final close = find.widgetWithText(OutlinedButton, 'Закрыть');
        await tester.ensureVisible(close);
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(find.byType(ServerLogRecordDialog), findsNothing);
        expect(closed, 1);
        expect(launcher.hasFocus, isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
        launcher.dispose();
        scale.dispose();
      },
    );
  }
}
