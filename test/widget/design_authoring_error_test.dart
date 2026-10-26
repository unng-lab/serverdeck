import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_presentation.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/shell/private_session.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';

import '../support/design_host.dart' show loadDesignFonts;
import '../support/design_state_capture.dart';

class _AuthoringFlow {
  final name = TextEditingController(text: '  Профиль JSON  ');
  final description = TextEditingController(
    text: 'Точное описание\n\tЧерновик',
  );
  final body = TextEditingController(text: '{}');
  final submission = AutomationProfileDraftSubmission();
  int submits = 0, closes = 0, validations = 0;

  Widget app({required bool dark, required double scale}) => RepaintBoundary(
    key: designStateCaptureBoundaryKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: Motion.theme(dark ? BrandTheme.dark : BrandTheme.light, true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: PrivateSessionScope(authorized: true, epoch: 1, child: child!),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: OutlinedButton(
            onPressed: () => showMotionDialog<void>(
              context: context,
              barrierDismissible: true,
              builder: (dialog) => ListenableBuilder(
                listenable: submission,
                builder: (_, _) => AutomationProfileEditorDialog(
                  name: name,
                  description: description,
                  body: body,
                  validating: false,
                  canValidate: !submission.saving,
                  saving: submission.saving,
                  error: submission.error,
                  nameError: submission.nameError,
                  descriptionError: submission.descriptionError,
                  saveError: submission.saveError,
                  onBodyChanged: (_) {},
                  onClose: () {
                    closes++;
                    Navigator.pop(dialog);
                  },
                  onValidate: () => validations++,
                  onSave: () => submission
                      .save(
                        name: name.text,
                        description: description.text,
                        source: body.text,
                        current: () => dialog.mounted,
                        submit: (_, _, _) async => submits++,
                        resultError: () => null,
                        close: () {
                          closes++;
                          Navigator.pop(dialog);
                        },
                      )
                      .ignore(),
                ),
              ),
            ).ignore(),
            child: const Text('Открыть редактор'),
          ),
        ),
      ),
    ),
  );

  void dispose() {
    submission.dispose();
    name.dispose();
    description.dispose();
    body.dispose();
  }
}

void main() {
  setUpAll(loadDesignFonts);
  for (final dark in [false, true]) {
    for (final frame in const [
      Size(1100, 760),
      Size(800, 600),
      Size(390, 800),
      Size(360, 800),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'T105 F16 malformed Save ${frame.width.toInt()}x${frame.height.toInt()} ${dark ? 'dark' : 'light'} scale=$scale',
          (tester) async {
            tester.view.physicalSize = frame;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final semantics = tester.ensureSemantics();
            final flow = _AuthoringFlow();
            const source = ' \n{ "steps": [ ';
            final originalName = flow.name.text;
            final originalDescription = flow.description.text;
            try {
              await tester.pumpWidget(flow.app(dark: dark, scale: scale));
              await tester.tap(find.text('Открыть редактор'));
              await tester.pumpAndSettle();
              expect(
                find.byType(AutomationProfileEditorDialog),
                findsOneWidget,
              );
              expect(find.byType(Dialog), findsOneWidget);
              final field = find.byWidgetPredicate(
                (widget) =>
                    widget is TextField &&
                    identical(widget.controller, flow.body),
              );
              await tester.ensureVisible(field);
              await tester.enterText(field, source);
              tester.testTextInput.hide();
              await tester.pumpAndSettle();
              final save = find.widgetWithText(
                FilledButton,
                'Сохранить версию',
              );
              await tester.ensureVisible(save);
              await tester.pumpAndSettle();
              await tester.tap(save);
              await tester.pumpAndSettle();

              final message = automationDraftInputError(profileBody: true);
              expect(flow.submission.error, message);
              expect(flow.submits, 0);
              expect(flow.closes, 0);
              expect(flow.validations, 0);
              expect(flow.name.text, originalName);
              expect(flow.description.text, originalDescription);
              expect(flow.body.text, source);
              expect(
                tester.widget<TextField>(field).decoration!.errorText,
                message,
              );
              final error = find.text(message);
              expect(error, findsOneWidget);
              await tester.ensureVisible(error);
              await tester.pumpAndSettle();
              final paragraph = tester.renderObject<RenderParagraph>(error);
              expect(
                paragraph.didExceedMaxLines,
                isFalse,
                reason: 'The actual malformed-Save message must paint without ellipsis.',
              );
              expect(paragraph.text.toPlainText(), message);
              final boxes = paragraph.getBoxesForSelection(
                TextSelection(baseOffset: 0, extentOffset: message.length),
              );
              expect(boxes, isNotEmpty);
              for (final box in boxes) {
                final topLeft = paragraph.localToGlobal(
                  Offset(box.left, box.top),
                );
                final bottomRight = paragraph.localToGlobal(
                  Offset(box.right, box.bottom),
                );
                expect(topLeft.dx, greaterThanOrEqualTo(0));
                expect(topLeft.dy, greaterThanOrEqualTo(0));
                expect(bottomRight.dx, lessThanOrEqualTo(frame.width));
                expect(bottomRight.dy, lessThanOrEqualTo(frame.height));
              }
              final rect = tester.getRect(error);
              expect(rect.left, greaterThanOrEqualTo(0));
              expect(rect.right, lessThanOrEqualTo(frame.width));
              expect(rect.top, greaterThanOrEqualTo(0));
              expect(rect.bottom, lessThanOrEqualTo(frame.height));
              expect(find.bySemanticsLabel(message), findsWidgets);
              for (final action in [
                find.widgetWithText(TextButton, 'Закрыть'),
                save,
                find.widgetWithText(OutlinedButton, 'Проверить без сохранения'),
              ]) {
                await tester.ensureVisible(action);
                await tester.pumpAndSettle();
                expect(action.hitTestable(), findsOneWidget);
                expect(
                  tester.widget<ButtonStyleButton>(action).onPressed,
                  isNotNull,
                );
                expect(tester.getSize(action).width, greaterThanOrEqualTo(44));
                expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
              }
              await tester.ensureVisible(error);
              await tester.pumpAndSettle();
              await captureDesignState(
                tester,
                family: 'automation',
                caseIds: ['state-33-profile-authoring-validation'],
                phase: 't105-json-error-visible',
                theme: dark ? 'dark' : 'light',
                scale: scale,
                counters: {
                  'submitCallbacks': flow.submits,
                  'closeCallbacks': flow.closes,
                  'validationCallbacks': flow.validations,
                },
                assertions: [
                  'Actual malformed Save through production profile submission paints the full field-linked error without ellipsis.',
                  'Exact name, description and malformed JSON retained; zero submit, close or validation callbacks.',
                  'Full error is in frame and every action is reachable after dialog scroll with a 44px target.',
                ],
                scope: 'T105 JSON body error wrapping in the production profile editor and submission boundary.',
                limitations: [
                  'Borrowed submit callback boundary; no TrustedApiClient, service/RPC, native authority or durable-write acceptance.',
                  'Only the error checkpoint is pictured; action reachability is asserted separately after scrolling.',
                ],
              );
              expect(flow.submits, 0);
              expect(flow.closes, 0);
              expect(flow.validations, 0);
              expect(tester.takeException(), isNull);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              flow.dispose();
              semantics.dispose();
            }
          },
        );
      }
    }
  }
}
