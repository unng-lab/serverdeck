import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart' show SvgPicture, SvgAssetLoader;
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/profiles/mutation_status.dart';
import 'package:serverdeck/profiles/profile_presentation.dart';
import 'package:serverdeck/servers/server_compositions.dart';
import 'package:path/path.dart' as paths;
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_icon.dart';
import 'package:serverdeck/ui/deck_page.dart';

import '../support/base_design_bindings.dart';
import '../support/design_host.dart';

const _captureDefine = String.fromEnvironment('BASE_DESIGN_CAPTURE_DIR');
const _sources = {
  'docs/design/ServerDeck-design.html':
      '7ceda8e4e79f736c48bd6ff24b572f75b5e05f2aa2e3d25dca95cbbecbe1b75d',
  'docs/design/screens.json':
      '8767675afc2dfb59e74fece2fdc3586ca31c795be7b29cf6b668ce238d702ed8',
  'docs/brandbook/tokens/serverdeck.tokens.json':
      '294b3fe4f7adcb1319f89fc4a2eb2872c8ba84a81cd05ccda610d9895da8a2d0',
};

const _primaryWidgets = <String, String>{
  '01-startup': 'ReadinessView',
  '02-service-unavailable': 'ReadinessView',
  '03-storage-blocked': 'ReadinessView',
  '04-empty-workspace': 'ProfileList',
  '05-server-list': 'ProfileList',
  '06-server-overview': 'ServerOverviewSection',
  '07-profile-create': 'ProfileForm',
  '08-profile-edit': 'ProfileForm',
  '09-profile-delete': 'ProfileDelete',
  '10-host-trust': 'ServerTrustConfirmation',
  '11-host-key-changed': 'ServerChangedKeySection',
  '12-credential-input': 'CredentialInput',
  '13-mutation-conflict': 'MutationReviewPage',
  '16-install-catalog': 'AutomationRecipesSection',
  '17-recipe-detail': 'AutomationRecipesSection',
  '18-install-preflight': 'AutomationPlanSection',
  '19-plan-approval': 'AutomationPlanDecisionDialog',
  '22-server-logs': 'ServerLogsSection',
  '23-log-record': 'ServerLogRecordDialog',
  '27-job-list': 'AutomationJobsSection',
  '28-job-detail': 'AutomationJobsSection',
  '29-job-unknown': 'AutomationJobsSection',
  '30-job-cancel': 'AutomationJobsSection',
  '31-recent-operations': 'RecentOperationsView',
  '32-automation-profiles': 'AutomationProfilesSection',
  '33-profile-authoring': 'AutomationProfileEditorDialog',
  '34-profile-revisions': 'AutomationProfileDetailSection',
  '35-plan-parameters': 'AutomationJsonEditorDialog',
  '36-ai-grants': 'AutomationGrantsSection',
  '37-ai-grant-form': 'AutomationJsonEditorDialog',
  '38-mcp-client-config': 'AutomationGrantsSection',
  '39-delegations': 'AutomationJsonEditorDialog',
  '40-executor-binding': 'ServerExecutorConfirmation',
  '84-settings': 'SettingsView',
  '85-settings-form': 'SettingsForm',
  '93-protected-effect-blocked': 'AutomationPlanSection',
  '94-plan-invalidated': 'AutomationPlanSection',
};

/// Primary current003.4 layout matrix. A layout pass is never pixel acceptance.
/// Optional screenshots are candidates from real production components and fake
/// external boundaries; the independent HTML reference is never loaded at runtime.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final captureDirectory = _captureDefine.isNotEmpty
      ? _captureDefine
      : Platform.environment['BASE_DESIGN_CAPTURE_DIR'] ?? '';
  Directory? output;
  var captures = 0;
  var bottomCaptures = 0;
  setUpAll(() async {
    await loadDesignFonts();
    if (captureDirectory.isNotEmpty) {
      if (!paths.isAbsolute(captureDirectory))
        throw ArgumentError('BASE_DESIGN_CAPTURE_DIR must be absolute.');
      final root = paths.normalize(paths.absolute('.local/design-003/003.4'));
      final requested = paths.normalize(captureDirectory);
      if (!paths.isWithin(root, requested))
        throw ArgumentError(
          'Capture output must be a new run directory below .local/design-003/003.4.',
        );
      output = Directory(requested);
      if (output!.existsSync() && output!.listSync().isNotEmpty)
        throw StateError('Capture run directory must be empty.');
      await output!.create(recursive: true);
    }
  });

  test(
    'current37 registry and canonical source identities remain independent',
    () {
      expect(currentBaseBindings, hasLength(37));
      expect(
        currentBaseBindings.map((binding) => binding.screenId).toSet(),
        hasLength(37),
      );
      expect(
        currentBaseBindings
            .where((binding) => binding.screenId == '11-host-key-changed')
            .single
            .productionWidgets,
        contains('ServerChangedKeySection'),
      );
      expect(
        currentBaseBindings
            .where(
              (binding) => binding.screenId == '93-protected-effect-blocked',
            )
            .single
            .productionWidgets,
        contains('AutomationPlanSection'),
      );
      expect(
        currentBaseBindings.length *
            currentBaseFrames.length *
            currentBaseThemes.length *
            currentBaseScales.length,
        592,
      );
      for (final source in _sources.entries) {
        expect(
          sha256.convert(File(source.key).readAsBytesSync()).toString(),
          source.value,
          reason: source.key,
        );
      }
    },
  );

  testWidgets(
    'page scroll offset cannot become the late expansion bool state',
    (tester) async {
      var showDetail = false, showPage = true;
      var dark = false;
      late StateSetter update;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MaterialApp(
              theme: dark ? ThemeData.dark() : ThemeData.light(),
              home: Scaffold(
                body: showPage
                    ? DeckPage(
                        title: 'Storage regression',
                        child: Column(
                          children: [
                            const SizedBox(height: 900),
                            TextButton(
                              onPressed: () =>
                                  setState(() => showDetail = true),
                              child: const Text('Mount detail'),
                            ),
                            if (showDetail)
                              const Material(
                                child: ExpansionTile(
                                  title: Text('Late detail'),
                                  children: [Text('Detail body')],
                                ),
                              ),
                            const SizedBox(height: 400),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            );
          },
        ),
      );
      await tester.ensureVisible(find.text('Mount detail'));
      await tester.pump();
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      expect(position.pixels, greaterThan(0));
      await tester.tap(find.text('Mount detail'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Late detail'));
      await tester.tap(find.text('Late detail'));
      await tester.pumpAndSettle();
      expect(find.text('Detail body'), findsOneWidget);
      final offset = position.pixels;
      update(() => dark = true);
      await tester.pumpAndSettle();
      expect(position.pixels, offset);
      expect(find.text('Detail body'), findsOneWidget);
      update(() => showPage = false);
      await tester.pump();
      update(() => showPage = true);
      await tester.pumpAndSettle();
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels,
        closeTo(offset, .1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final binding in currentBaseBindings) {
    for (final frame in currentBaseFrames) {
      for (final theme in currentBaseThemes) {
        for (final scale in currentBaseScales) {
          final caseId =
              '${binding.screenId} ${frame.width.toInt()}x${frame.height.toInt()} ${theme.name} ${(scale * 100).round()}%';
          testWidgets('current base primary layout $caseId', (tester) async {
            final originalErrorHandler = FlutterError.onError;
            FlutterError.onError = (details) {
              FlutterError.dumpErrorToConsole(details);
              originalErrorHandler?.call(details);
            };
            final host = await mountDesignFixture(
              tester,
              binding,
              frame: frame,
              theme: theme,
              textScale: scale,
              currentBase: true,
            );
            try {
              await tester.pumpAndSettle();
              // Every page is observed in its actual shell, including public states.
              expect(
                find.byType(FoundationShell),
                findsOneWidget,
                reason: caseId,
              );
              expect(
                find.byWidgetPredicate(
                  (widget) =>
                      widget.runtimeType.toString() ==
                      _primaryWidgets[binding.screenId],
                ),
                findsWidgets,
                reason: 'Actual production owner composition for $caseId',
              );
              expect(tester.takeException(), isNull, reason: caseId);
              if (const {
                '27-job-list',
                '36-ai-grants',
              }.contains(binding.screenId)) {
                final facts = find.byWidgetPredicate(
                  (widget) => widget is AutomationFacts && widget.tableContext,
                );
                expect(facts, findsOneWidget);
                final padding = tester
                    .element(facts)
                    .findAncestorWidgetOfExactType<Padding>()!;
                final outer = tester.getRect(find.byWidget(padding));
                final inner = tester.getRect(facts);
                expect(inner.top - outer.top, 12);
                expect(outer.bottom - inner.bottom, 12);
                expect(inner.left - outer.left, frame.width <= 520 ? 16 : 18);
                expect(outer.right - inner.right, frame.width <= 520 ? 16 : 18);
              }
              if (const {
                '13-mutation-conflict',
                '36-ai-grants',
                '37-ai-grant-form',
                '38-mcp-client-config',
              }.contains(binding.screenId)) {
                final semantics = tester.ensureSemantics();
                try {
                  final navigation = find.byKey(
                    ValueKey(
                      frame.width <= 520
                          ? 'foundation-phone-navigation'
                          : 'foundation-sidebar',
                    ),
                  );
                  expect(navigation, findsOneWidget);
                  for (final section in [
                    FoundationSection.settings,
                    ...FoundationSection.values.where(
                      (section) => section != FoundationSection.settings,
                    ),
                  ]) {
                    final item = find.descendant(
                      of: navigation,
                      matching: find.byKey(
                        ValueKey('foundation-navigation-${section.name}'),
                      ),
                    );
                    expect(item, findsOneWidget);
                    final data = tester.getSemantics(item).getSemanticsData();
                    expect(data.label, section.label);
                    expect(data.flagsCollection.isButton, isTrue);
                    expect(
                      data.flagsCollection.isSelected,
                      section == FoundationSection.settings
                          ? ui.Tristate.isTrue
                          : ui.Tristate.isFalse,
                      reason:
                          'Current settings view stays in Settings: $caseId',
                    );
                  }
                  if (frame.width > 520) {
                    final breadcrumb = find.descendant(
                      of: find.byKey(const ValueKey('foundation-topbar')),
                      matching: find.byType(Wrap),
                    );
                    expect(breadcrumb, findsOneWidget);
                    expect(
                      tester
                          .widgetList<Text>(
                            find.descendant(
                              of: breadcrumb,
                              matching: find.byType(Text),
                            ),
                          )
                          .map((text) => text.data),
                      ['Рабочее пространство', '/', 'Настройки'],
                    );
                  }
                } finally {
                  semantics.dispose();
                }
              }
              if (binding.screenId == '13-mutation-conflict') {
                final page = tester.widget<MutationReviewPage>(
                  find.byType(MutationReviewPage),
                );
                expect(page.controller, same(host.harness.mutation));
                expect(page.settings, isTrue);
                final pageHeading = find.byWidgetPredicate(
                  (widget) =>
                      widget is Semantics &&
                      widget.properties.header == true &&
                      widget.child is Text &&
                      (widget.child! as Text).data ==
                          'Сохранение требует проверки',
                );
                expect(pageHeading, findsOneWidget);
                final hero = find.byType(ServerStatusBody);
                expect(hero, findsOneWidget);
                expect(
                  find.descendant(
                    of: hero,
                    matching: find.text('Сохранение требует проверки'),
                  ),
                  findsOneWidget,
                );
                expect(find.text('Состояние и следующие шаги'), findsOneWidget);
              }
              if (binding.screenId == '18-install-preflight') {
                expect(
                  find.text('Проверка готовности к установке'),
                  findsWidgets,
                );
              }
              if (binding.screenId == '35-plan-parameters') {
                final editor = tester.widget<AutomationJsonEditorDialog>(
                  find.byType(AutomationJsonEditorDialog),
                );
                expect(editor.parameterDefinitions.keys, ['greeting']);
              }
              if (binding.screenId == '37-ai-grant-form') {
                expect(find.text('Выдать доступ ИИ'), findsOneWidget);
              }
              if (binding.screenId == '39-delegations') {
                final editor = tester.widget<AutomationJsonEditorDialog>(
                  find.byType(AutomationJsonEditorDialog),
                );
                expect(editor.title, 'Делегирование версии');
                expect(editor.clientLabel, isNotNull);
                expect(find.text('ИИ-клиент *'), findsOneWidget);
                expect(find.text(editor.clientLabel!), findsOneWidget);
              }
              final sidebar = tester
                  .getSize(find.byKey(const ValueKey('foundation-sidebar')))
                  .width;
              expect(
                sidebar,
                frame.width <= 520
                    ? 0
                    : frame.width <= 1060
                    ? 68
                    : 210,
                reason: caseId,
              );
              expect(
                tester
                    .getSize(find.byKey(const ValueKey('foundation-topbar')))
                    .height,
                scale == 1
                    ? (frame.width <= 520 ? 62 : 56)
                    : greaterThanOrEqualTo(frame.width <= 520 ? 62 : 56),
                reason: caseId,
              );
              final slot = tester.getRect(
                find.byKey(const ValueKey('foundation-feature-slot')),
              );
              expect(slot.left, greaterThanOrEqualTo(0));
              expect(slot.right, lessThanOrEqualTo(frame.width + .1));
              expect(slot.height, greaterThan(0));
              for (final element in find.byType(DeckIcon).evaluate()) {
                final icon = element.widget as DeckIcon;
                expect(
                  File('assets/brand/icons/${icon.name}.svg').existsSync(),
                  isTrue,
                  reason: '${binding.screenId}: ${icon.name}',
                );
              }
              if (binding.screenId == '93-protected-effect-blocked') {
                expect(find.text('План заблокирован'), findsWidgets);
                expect(
                  find.textContaining(
                    'конкретном защищённом эффекте не предоставлены',
                  ),
                  findsWidgets,
                );
                expect(find.textContaining('NetBird'), findsNothing);
              }
              if (binding.screenId == '12-credential-input') {
                expect(
                  tester
                      .widget<ProfileFieldGrid>(find.byType(ProfileFieldGrid))
                      .children,
                  hasLength(6),
                );
                for (final label in [
                  'Цель *',
                  'Доступ *',
                  'Файл ключа',
                  'Приватный ключ *',
                  'Passphrase',
                  'Хранение',
                ]) {
                  expect(find.text(label), findsOneWidget);
                }
                final target = tester.getRect(find.text('Цель *'));
                final access = tester.getRect(find.text('Доступ *'));
                if (frame.width > 520 && scale == 1) {
                  expect(access.left, greaterThan(target.left));
                  expect(access.top, closeTo(target.top, .1));
                } else {
                  expect(access.left, closeTo(target.left, .1));
                  expect(access.top, greaterThan(target.top));
                }
                final keyInput = tester.widget<TextFormField>(
                  find.byKey(const ValueKey('credential-private-key')),
                );
                expect(keyInput.controller!.text, isEmpty);
                expect(
                  tester
                      .widget<TextField>(
                        find.descendant(
                          of: find.byKey(
                            const ValueKey('credential-private-key'),
                          ),
                          matching: find.byType(TextField),
                        ),
                      )
                      .obscureText,
                  isTrue,
                );
              }
              // Primary screenshot begins at the page origin; local chooser actions
              // used to enter a detail must not leave a search button as the origin.
              for (final element in find.byType(Scrollable).evaluate()) {
                final state =
                    (element as StatefulElement).state as ScrollableState;
                if (state.widget.axisDirection == AxisDirection.down &&
                    state.position.hasPixels)
                  state.position.jumpTo(state.position.minScrollExtent);
              }
              await tester.pump();
              expect(tester.takeException(), isNull, reason: caseId);
              if (output != null) {
                final logo = find.byWidgetPredicate(
                  (widget) =>
                      widget is SvgPicture &&
                      widget.bytesLoader is SvgAssetLoader &&
                      (widget.bytesLoader as SvgAssetLoader).assetName
                          .startsWith('assets/brand/logos/'),
                );
                expect(
                  logo,
                  findsOneWidget,
                  reason: 'The real visible brand asset',
                );
                final logoRect = tester.getRect(logo);
                final surface =
                    (theme == ThemeMode.dark
                            ? BrandTheme.dark
                            : BrandTheme.light)
                        .extension<BrandColors>()!['surface']
                        .toARGB32();
                final boundary =
                    host.boundaryKey.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                await tester.runAsync<void>(() async {
                  final image = await boundary.toImage(pixelRatio: 1);
                  try {
                    expect(image.width, frame.width.toInt());
                    expect(image.height, frame.height.toInt());
                    final rgba = await image.toByteData(
                      format: ui.ImageByteFormat.rawRgba,
                    );
                    if (rgba == null) throw StateError('RGBA read failed.');
                    var brandInk = 0;
                    for (
                      var y = logoRect.top.ceil().clamp(0, image.height);
                      y < logoRect.bottom.floor().clamp(0, image.height);
                      y++
                    ) {
                      for (
                        var x = logoRect.left.ceil().clamp(0, image.width);
                        x < logoRect.right.floor().clamp(0, image.width);
                        x++
                      ) {
                        final offset = (y * image.width + x) * 4;
                        final red = rgba.getUint8(offset),
                            green = rgba.getUint8(offset + 1),
                            blue = rgba.getUint8(offset + 2);
                        if ((red << 16 | green << 8 | blue) !=
                            surface & 0xffffff)
                          brandInk++;
                      }
                    }
                    expect(
                      brandInk,
                      greaterThan(20),
                      reason: 'Decoded canonical logo must paint; a blank SVG placeholder is not a candidate.',
                    );
                    final bytes = await image.toByteData(
                      format: ui.ImageByteFormat.png,
                    );
                    if (bytes == null) throw StateError('PNG encoding failed.');
                    final fileName =
                        '${binding.screenId}-${frame.width.toInt()}x${frame.height.toInt()}-${theme.name}-${(scale * 100).round()}.png';
                    final file = File(paths.join(output!.path, fileName));
                    await file.writeAsBytes(
                      bytes.buffer.asUint8List(
                        bytes.offsetInBytes,
                        bytes.lengthInBytes,
                      ),
                      flush: true,
                    );
                    await File(
                      paths.join(output!.path, 'candidates.jsonl'),
                    ).writeAsString(
                      '${jsonEncode({
                        'screenId': binding.screenId,
                        'frame': [frame.width, frame.height],
                        'theme': theme.name,
                        'textScale': scale,
                        'file': fileName,
                        'productionFixture': host.fixture.runtimeType.toString(),
                        'decodedBrandInkPixels': brandInk,
                        if (Platform.environment['GITHUB_SHA'] case final String revision when revision.isNotEmpty) 'sourceRevision': revision,
                        'scope': 'primary viewport layout candidate; independent pixel comparison not performed',
                        'nativeIntegration': 'not run',
                      })}\n',
                      mode: FileMode.append,
                      flush: true,
                    );
                    captures++;
                  } finally {
                    image.dispose();
                  }
                });
                final page = find.byType(DeckPage).first;
                final scrolls = find.descendant(
                  of: page,
                  matching: find.byType(Scrollable),
                );
                final scroll = scrolls
                    .evaluate()
                    .map(
                      (element) =>
                          (element as StatefulElement).state as ScrollableState,
                    )
                    .firstWhere(
                      (state) =>
                          state.widget.axisDirection == AxisDirection.down,
                    );
                if (scroll.position.maxScrollExtent > 1) {
                  final effects = Map<String, int>.of(
                    host.harness.counters.values,
                  );
                  final writes = host.harness.client.mutations.length;
                  final reads = host.harness.client.reads.length;
                  scroll.position.jumpTo(scroll.position.maxScrollExtent);
                  await tester.pumpAndSettle();
                  expect(
                    tester.takeException(),
                    isNull,
                    reason: '$caseId bottom viewport',
                  );
                  expect(host.harness.counters.values, effects);
                  expect(host.harness.client.mutations.length, writes);
                  expect(host.harness.client.reads.length, reads);
                  await tester.runAsync<void>(() async {
                    final image = await boundary.toImage(pixelRatio: 1);
                    try {
                      final bytes = await image.toByteData(
                        format: ui.ImageByteFormat.png,
                      );
                      if (bytes == null)
                        throw StateError('Bottom PNG encoding failed.');
                      final fileName =
                          '${binding.screenId}-${frame.width.toInt()}x${frame.height.toInt()}-${theme.name}-${(scale * 100).round()}-bottom.png';
                      await File(paths.join(output!.path, fileName))
                          .writeAsBytes(
                            bytes.buffer.asUint8List(
                              bytes.offsetInBytes,
                              bytes.lengthInBytes,
                            ),
                            flush: true,
                          );
                      bottomCaptures++;
                    } finally {
                      image.dispose();
                    }
                  });
                }
              }
            } finally {
              FlutterError.onError = originalErrorHandler;
              await host.close(tester);
            }
          });
        }
      }
    }
  }
  tearDownAll(() {
    if (output != null)
      stdout.writeln(
        'Current003.4 candidate PNGs written: $captures primary, $bottomCaptures bottom. Pixel comparison is not implied.',
      );
  });
}
