import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/automation/automation_sections.dart';
import 'package:serverdeck/servers/metrics_history.dart';
import 'package:serverdeck/servers/server_sections.dart';
import 'package:serverdeck/theme/brand_assets.dart';
import 'package:serverdeck/ui/deck_components.dart';

import '../support/design_automation_state_cases.dart';
import '../support/design_foundation_state_cases.dart';
import '../support/design_host.dart';
import '../support/design_privacy_state_cases.dart';
import '../support/design_scenarios.dart';
import '../support/design_server_state_cases.dart';

const _captureDirectory = String.fromEnvironment('DESIGN_CAPTURE_DIR');
const _stateCaptureDirectory = String.fromEnvironment(
  'DESIGN_STATE_CAPTURE_DIR',
);
const _captureMode = String.fromEnvironment(
  'DESIGN_CAPTURE_MODE',
  defaultValue: 'baseline',
);
const _captureStage = String.fromEnvironment(
  'DESIGN_CAPTURE_STAGE',
  defaultValue: '003.1',
);
const _adaptive = _captureStage == '003.2' || _captureStage == '003.3';
const _captureTask = _captureStage == '003.3'
    ? 'T039'
    : _adaptive
    ? 'T030'
    : 'T020';
const _captureFrames = _adaptive
    ? [Size(1100, 760), Size(800, 600), Size(390, 800), Size(360, 800)]
    : [Size(1100, 760), Size(390, 800)];
const _captureThemes = [ThemeMode.light, ThemeMode.dark];
const _captureScales = _adaptive ? [1.0, 2.0] : [1.0];

/// Opt-in synthetic visual evidence for T020/T030/T039. Normal runs write nothing.
/// Stage003.3 requires the matching command shell variable; earlier baseline
/// stages retain their explicitly labelled reconstructed-invocation fallback.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (_captureStage != '003.1' &&
      _captureStage != '003.2' &&
      _captureStage != '003.3') {
    throw ArgumentError.value(_captureStage, 'DESIGN_CAPTURE_STAGE');
  }
  if (_captureMode != 'baseline' && _captureMode != 'state') {
    throw ArgumentError.value(_captureMode, 'DESIGN_CAPTURE_MODE');
  }
  if (_captureMode == 'state' && _captureStage != '003.3') {
    throw ArgumentError('State capture requires DESIGN_CAPTURE_STAGE=003.3');
  }
  final stateDirectory = _stateCaptureDirectory.isNotEmpty
      ? _stateCaptureDirectory
      : Platform.environment['DESIGN_STATE_CAPTURE_DIR'] ?? '';
  final baselineDirectoryConfigured =
      _captureDirectory.isNotEmpty ||
      (Platform.environment['DESIGN_CAPTURE_DIR'] ?? '').isNotEmpty;
  if ((_captureMode == 'baseline' && stateDirectory.isNotEmpty) ||
      (_captureMode == 'state' && baselineDirectoryConfigured)) {
    throw ArgumentError(
      'Configure only the output directory for the selected DESIGN_CAPTURE_MODE',
    );
  }
  final selectedDirectory = _captureMode == 'state'
      ? stateDirectory
      : _captureDirectory;
  if (selectedDirectory.isEmpty) {
    test(
      'synthetic visual captures require an explicit output directory',
      () {},
      skip:
          'Baseline mode (the default) requires '
          '--dart-define=DESIGN_CAPTURE_DIR=<absolute repository '
          '.local/design-003/<stage> run path>; stages003.2/003.3 write '
          '560 primary plus184 supplementary PNGs. State mode requires '
          '--dart-define=DESIGN_CAPTURE_MODE=state, '
          '--dart-define=DESIGN_CAPTURE_STAGE=003.3 and '
          '--dart-define=DESIGN_STATE_CAPTURE_DIR=<absolute repository '
          '.local/design-003/003.3 fresh run path>. For003.3, set the matching '
          'DESIGN_CAPTURE_COMMAND or DESIGN_STATE_CAPTURE_COMMAND shell '
          'variable to the exact invocation. No captures or binding records '
          'are written in ordinary test runs.',
    );
    return;
  }

  if (_captureMode == 'state') {
    final suppliedCommand =
        Platform.environment['DESIGN_STATE_CAPTURE_COMMAND'];
    if (suppliedCommand == null || suppliedCommand.trim().isEmpty) {
      throw StateError(
        'Opt-in state capture requires DESIGN_STATE_CAPTURE_COMMAND',
      );
    }
    registerDesignFoundationStateCases(fullAdaptive: false);
    registerDesignServerStateCases(fullAdaptive: false);
    registerDesignAutomationStateCases(fullAdaptive: false);
    registerDesignPrivacyStateCases(fullAdaptive: false);
    return;
  }
  final suppliedCommand = Platform.environment['DESIGN_CAPTURE_COMMAND'];
  if (_captureStage == '003.3' &&
      (suppliedCommand == null || suppliedCommand.trim().isEmpty)) {
    throw StateError(
      'Stage003.3 baseline capture requires DESIGN_CAPTURE_COMMAND',
    );
  }

  late Directory output;
  late File records;
  late String command;
  late String commandSource;
  var captured = 0;
  var graphSupplements = 0;
  var adaptiveSupplements = 0;
  var correctedViewSupplements = 0;

  setUpAll(() async {
    await loadDesignFonts();
    output = await _prepareOutputDirectory(_captureDirectory);
    records = File.fromUri(output.uri.resolve('records.jsonl'));
    await records.writeAsString('');
    command = suppliedCommand != null && suppliedCommand.trim().isNotEmpty
        ? suppliedCommand
        : 'flutter test test/widget/design_capture_test.dart '
              '--dart-define=DESIGN_CAPTURE_STAGE=$_captureStage '
              '--dart-define=DESIGN_CAPTURE_MODE=$_captureMode '
              '--dart-define=DESIGN_CAPTURE_DIR="$_captureDirectory"';
    commandSource = suppliedCommand != null && suppliedCommand.trim().isNotEmpty
        ? 'DESIGN_CAPTURE_COMMAND shell environment'
        : 'reconstructed-test-invocation';
    expect(designBindings, hasLength(35));
  });

  for (final binding in designBindings) {
    for (final frame in _captureFrames) {
      for (final theme in _captureThemes) {
        for (final scale in _captureScales) {
          final dimensions = '${frame.width.toInt()}x${frame.height.toInt()}';
          final fileName =
              '${binding.screenId}-$dimensions-${theme.name}-${(scale * 100).toInt()}.png';
          testWidgets(
            '${binding.screenId} $dimensions ${theme.name} ${(scale * 100).toInt()}% visual capture',
            (tester) async {
              final host = await mountDesignFixture(
                tester,
                binding,
                frame: frame,
                theme: theme,
                textScale: scale,
              );
              // Widget/model cleanup must remain in runTest's FakeAsync scope.
              // An asynchronous addTearDown callback runs after that driver's
              // microtask loop and can wait forever on model/stream shutdown.
              try {
                await _decodeBrandImages(tester);
                expect(tester.takeException(), isNull);
                _expectDecodedImages(tester);

                final boundary = tester.renderObject<RenderRepaintBoundary>(
                  find.byKey(host.boundaryKey),
                );
                expect(boundary.size, frame);
                expect(boundary.debugNeedsPaint, isFalse);
                final record = <String, Object?>{
                  'screenId': binding.screenId,
                  'group': binding.group,
                  'ownerFile': binding.ownerFile,
                  'sourceOwners': binding.sourceOwners,
                  'ownerFR': binding.ownerFR,
                  'ownerAC': binding.ownerAC,
                  'notApplicableReason': binding.notApplicableReason,
                  'taskIds': binding.taskIds,
                  'captureTask': _captureTask,
                  'captureStage': _captureStage,
                  'state': host.baselineState,
                  'variant': _adaptive ? 'primary' : 'baseline',
                  'frame': {
                    'width': frame.width.toInt(),
                    'height': frame.height.toInt(),
                  },
                  'theme': theme.name,
                  'scale': scale,
                  'devicePixelRatio': 1.0,
                  'reducedMotion': true,
                  'imageReadiness':
                      'Bundled brand images decoded; all mounted RawImage '
                      'widgets have a non-null image after a frame.',
                  'decodedImageCount': find.byType(RawImage).evaluate().length,
                  'command': command,
                  'commandSource': commandSource,
                  'result': 'captured',
                  'scope': 'visual_capture',
                  'fixtureScope':
                      'Real production widgets/sections with synthetic '
                      'existing-protocol input; extracted sections are mounted '
                      'without their native controller/panel lifecycle.',
                  'callbackCounters': host.harness.counters.values,
                  'png': fileName,
                  'visualReference': 'docs/design/ServerDeck-design.html',
                  'limitations': [
                    'Primary captures show one baseline state per origin; '
                        'supplements cover only their named additional branch '
                        'or scroll view. Other applicable states are outside '
                        'this capture matrix.',
                    'Capture creation does not establish visual acceptance, '
                        'layout/semantics acceptance, or native effects/security '
                        'acceptance. Visual comparison and enclosing check exits '
                        'are recorded separately in stage evidence.',
                  ],
                };

                // Engine image completion and filesystem I/O need real async time,
                // rather than the widget test's fake animation clock.
                Future<void> saveCapture(
                  String outputName,
                  Map<String, Object?> metadata,
                ) async {
                  _expectDecodedImages(tester);
                  await tester.runAsync<void>(() async {
                    final image = await boundary.toImage(pixelRatio: 1);
                    try {
                      expect(image.width, frame.width.toInt());
                      expect(image.height, frame.height.toInt());
                      final png = await image.toByteData(
                        format: ui.ImageByteFormat.png,
                      );
                      if (png == null)
                        throw StateError('PNG encoding returned null');
                      await File.fromUri(output.uri.resolve(outputName))
                          .writeAsBytes(
                            png.buffer.asUint8List(
                              png.offsetInBytes,
                              png.lengthInBytes,
                            ),
                            flush: true,
                          );
                      await records.writeAsString(
                        '${jsonEncode(metadata)}\n',
                        mode: FileMode.append,
                        flush: true,
                      );
                    } finally {
                      image.dispose();
                    }
                  });
                }

                await saveCapture(fileName, record);
                captured++;
                if (!_adaptive && binding.screenId == '06-server-overview') {
                  await revealDesignGraphs(tester);
                  expectDesignVisible(
                    tester,
                    find.byKey(const ValueKey('metrics-history-plots')),
                  );
                  for (final context in [
                    'Данные получены',
                    'Источник: ssh:proc/stat+meminfo+net/dev+df',
                    'Наблюдение: ${DesignServerFixtures.observedAt} · UTC',
                    'Получено: ${DesignServerFixtures.observedAt} · UTC',
                  ]) {
                    expectDesignVisible(
                      tester,
                      find.descendant(
                        of: find.byType(MetricsHistory),
                        matching: find.text(context),
                      ),
                    );
                  }
                  final graphName = fileName.replaceFirst(
                    '.png',
                    '-graph-scroll.png',
                  );
                  await saveCapture(graphName, {
                    ...record,
                    'variant': 'graph-scroll',
                    'state': 'history-plots-visible',
                    'png': graphName,
                    'supplementTo': fileName,
                    'visibleContext': [
                      'persistent shell target',
                      'history quality',
                      'source',
                      'observedAt',
                      'receivedAt',
                    ],
                  });
                  graphSupplements++;
                }
                if (_adaptive &&
                    scale == 2 &&
                    (binding.screenId == '06-server-overview' ||
                        binding.screenId == '38-mcp-client-config')) {
                  Future<void> supplement(
                    String view,
                    String state,
                    List<(String, Finder)> visible,
                    List<String> limitations,
                  ) async {
                    final target = _shellTarget();
                    await _showCaptureContent(tester, target);
                    for (final entry in visible) {
                      expectDesignVisible(tester, entry.$2);
                    }
                    final name = fileName.replaceFirst('.png', '-$view.png');
                    await saveCapture(name, {
                      ...record,
                      'variant': view,
                      'state': state,
                      'png': name,
                      'supplementTo': fileName,
                      'visibleContext': [
                        'persistent shell target',
                        for (final entry in visible) entry.$1,
                      ],
                      'visibleGeometry': {
                        'persistent shell target': _geometry(tester, target),
                        for (final entry in visible)
                          entry.$1: _geometry(tester, entry.$2),
                      },
                      'limitations': [
                        ...(record['limitations'] as List),
                        ...limitations,
                      ],
                    });
                    adaptiveSupplements++;
                  }

                  if (binding.screenId == '06-server-overview') {
                    await _captureAdaptiveHistory(tester, supplement);
                  } else {
                    await _captureAdaptiveConfiguration(tester, supplement);
                  }
                }
                if (_adaptive && scale == 2) {
                  Future<void> correctedView(
                    String view,
                    List<(String, Finder)> visible,
                  ) async {
                    final name = fileName.replaceFirst('.png', '-$view.png');
                    for (final entry in visible) {
                      expectDesignVisible(tester, entry.$2);
                    }
                    await saveCapture(name, {
                      ...record,
                      'variant': view,
                      'state': '$view-visible',
                      'png': name,
                      'supplementTo': fileName,
                      'visibleContext': [for (final entry in visible) entry.$1],
                      'visibleGeometry': {
                        for (final entry in visible)
                          entry.$1: _geometry(tester, entry.$2),
                      },
                      'limitations': [
                        ...(record['limitations'] as List),
                        'This readable dialog slice shows the named elements. '
                            'The initial viewport and other dialog content are '
                            'separate views; no simultaneous whole-form or '
                            'persistent shell target visibility is claimed.',
                      ],
                    });
                    correctedViewSupplements++;
                  }

                  final labelView = switch (binding.screenId) {
                    '08-profile-edit' => (
                      'address-label',
                      'Адрес (IP или имя домена)',
                    ),
                    '12-credential-input' => (
                      'tags-label',
                      'Метки (одна на строку)',
                    ),
                    '33-profile-authoring' => (
                      'json-label',
                      'Шаги и параметры профиля (JSON)',
                    ),
                    _ => null,
                  };
                  if (labelView != null) {
                    final label = find.text(labelView.$2);
                    await _showCaptureContent(tester, label);
                    await correctedView(labelView.$1, [(labelView.$2, label)]);
                  }
                  if (binding.screenId == '12-credential-input') {
                    final passwordChoice = find.text('Новый пароль');
                    await _showCaptureContent(tester, passwordChoice);
                    expect(passwordChoice.hitTestable(), findsOneWidget);
                    await tester.tap(passwordChoice);
                    await tester.pumpAndSettle();
                    final keyChoice = find.text('Новый приватный ключ').last;
                    await _showCaptureContent(tester, keyChoice);
                    expect(keyChoice.hitTestable(), findsOneWidget);
                    await tester.tap(keyChoice);
                    await tester.pumpAndSettle();
                    for (final entry in const [
                      ('private-key-choice', 'Новый приватный ключ'),
                      ('private-key-label', 'Приватный ключ'),
                      (
                        'private-key-helper',
                        'Для ввода ключа включите показ или выберите файл',
                      ),
                      ('passphrase-label', 'Passphrase (необязательно)'),
                    ]) {
                      final label = find.text(entry.$2);
                      await _showCaptureContent(tester, label);
                      await correctedView(entry.$1, [(entry.$2, label)]);
                    }
                  }
                  if (binding.screenId == '40-executor-binding') {
                    final owner = find.byType(ServerExecutorConfirmation);
                    final profile = host.harness.trustProfile;
                    final name = find.descendant(
                      of: owner,
                      matching: find.text(profile.name),
                    );
                    final address = find.descendant(
                      of: owner,
                      matching: find.text(
                        AutomationServerTargets.address(profile),
                      ),
                    );
                    final nameField = find.ancestor(
                      of: name,
                      matching: find.byType(DeckKeyValue),
                    );
                    await _showCaptureContent(tester, nameField);
                    await correctedView('executor-target', [
                      ('exact executor server name', name),
                      ('exact executor address and port', address),
                    ]);
                    final fingerprint = find.descendant(
                      of: owner,
                      matching: find.text(DesignServerFixtures.key.fingerprint),
                    );
                    final deadline = find.text(
                      'Подтверждение действует до ${DesignServerFixtures.expiresAt} · UTC',
                    );
                    await _showCaptureContent(tester, fingerprint);
                    await correctedView('executor-fingerprint', [
                      ('captured executor SSH fingerprint', fingerprint),
                      ('captured inspection deadline', deadline),
                    ]);
                  }
                  if (const {
                    '19-plan-approval',
                    '35-plan-parameters',
                    '37-ai-grant-form',
                    '39-delegations',
                  }.contains(binding.screenId)) {
                    final targets = find.byType(AutomationServerTargets).first;
                    final targetWidget = tester.widget<AutomationServerTargets>(
                      targets,
                    );
                    expect(
                      targetWidget.serverIds,
                      contains(DesignAutomationFixtures.serverId),
                    );
                    final profile = AutomationServerTargets.resolve(
                      DesignAutomationFixtures.serverId,
                      targetWidget.serverProfiles,
                      expectedIdentity:
                          targetWidget
                              .expectedIdentities[DesignAutomationFixtures
                              .serverId] ??
                          const {},
                    );
                    expect(
                      profile,
                      isNotNull,
                      reason: 'Capture needs the exact authorized target',
                    );
                    final name = find.descendant(
                      of: targets,
                      matching: find.text(profile!.name),
                    );
                    final address = find.descendant(
                      of: targets,
                      matching: find.text(
                        AutomationServerTargets.address(profile),
                      ),
                    );
                    final nameField = find.ancestor(
                      of: name,
                      matching: find.byType(DeckKeyValue),
                    );
                    await _showCaptureContent(tester, nameField);
                    await correctedView('automation-target', [
                      ('exact automation target server name', name),
                      ('exact automation address and port', address),
                    ]);
                  }
                }
                expect(tester.takeException(), isNull);
              } finally {
                await host.close(tester);
              }
            },
          );
        }
      }
    }
  }

  tearDownAll(() {
    expect(
      captured,
      35 *
          _captureFrames.length *
          _captureThemes.length *
          _captureScales.length,
    );
    expect(
      graphSupplements,
      _adaptive ? 0 : _captureFrames.length * _captureThemes.length,
    );
    expect(
      adaptiveSupplements,
      _adaptive ? 10 * _captureFrames.length * _captureThemes.length : 0,
    );
    expect(
      correctedViewSupplements,
      _adaptive ? 13 * _captureFrames.length * _captureThemes.length : 0,
    );
  });
}

typedef _SupplementCapture = Future<void> Function(
  String view,
  String state,
  List<(String, Finder)> visible,
  List<String> limitations,
);

Finder _shellTarget() => find.descendant(
  of: find.byKey(const ValueKey('foundation-page-context')),
  matching: find.byType(SelectableText),
);

Future<void> _showCaptureContent(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await Scrollable.ensureVisible(tester.element(finder), alignment: .05);
  await tester.pumpAndSettle();
  expectDesignVisible(tester, finder);
}

Map<String, double> _geometry(WidgetTester tester, Finder finder) {
  final rect = tester.getRect(finder);
  return {
    'left': rect.left,
    'top': rect.top,
    'width': rect.width,
    'height': rect.height,
  };
}

Future<void> _captureAdaptiveHistory(
  WidgetTester tester,
  _SupplementCapture capture,
) async {
  final history = find.byType(MetricsHistory);
  for (final entry in [
    ('history-source', 'Источник: ssh:proc/stat+meminfo+net/dev+df'),
    (
      'history-observed-utc',
      'Наблюдение: ${DesignServerFixtures.observedAt} · UTC',
    ),
    (
      'history-received-utc',
      'Получено: ${DesignServerFixtures.observedAt} · UTC',
    ),
  ]) {
    final text = find.descendant(of: history, matching: find.text(entry.$2));
    await _showCaptureContent(tester, text);
    await capture(
      entry.$1,
      '${entry.$1}-visible',
      [(entry.$1, text)],
      [
        'This readable view isolates one real history context field; other context '
            'is shown in the adjacent source/UTC/plots/values supplemental views.',
      ],
    );
  }
  final plots = find.byKey(const ValueKey('metrics-history-plots'));
  await _showCaptureContent(tester, plots);
  final quality = find.byKey(const ValueKey('metrics-history-plot-quality'));
  final visible = <(String, Finder)>[
    ('history plot block', plots),
    ('history plot quality', quality),
  ];
  for (final id in ['cpu', 'memory', 'disk']) {
    final plot = find.byKey(ValueKey('metrics-history-plot-$id'));
    expect(tester.getSize(plot).height, 25);
    visible.add(('$id plot', plot));
  }
  await capture('history-plots', 'history-plots-and-quality-visible', visible, [
    'The three actual25px plots and parent quality are visible; source/UTC '
        'are captured separately at the same theme/frame/scale.',
  ]);
  final button = find.widgetWithText(TextButton, 'Значения истории');
  await _showCaptureContent(tester, button);
  expect(button.hitTestable(), findsOneWidget);
  await tester.tap(button);
  await tester.pumpAndSettle();
  final valuesSection = find.byKey(
    const ValueKey('metrics-history-values-section'),
  );
  final valuesQuality = find.byKey(
    const ValueKey('metrics-history-values-quality'),
  );
  final first = find.text(
    '${DesignServerFixtures.observedAt} UTC · CPU: 0% · RAM: 0% · Диск /: 0%',
  );
  expect(tester.getSize(valuesSection).height, lessThanOrEqualTo(280));
  await _showCaptureContent(tester, valuesSection);
  await capture(
    'history-values',
    'history-expanded-first-sample-and-quality-visible',
    [
      ('expanded bounded values section', valuesSection),
      ('history values quality', valuesQuality),
      ('first UTC sample with percentages', first),
    ],
    [
      'The first actual raw sample is visible in the bounded text disclosure. '
          'Remaining source-order rows use its existing vertical scroll; this '
          'image does not claim all samples or quality states are visible at once.',
    ],
  );
}

Future<void> _captureAdaptiveConfiguration(
  WidgetTester tester,
  _SupplementCapture capture,
) async {
  for (final entry in [
    ('mcp-heading', find.text('Конфигурация MCP').last),
    ('mcp-command', find.text(r'C:\Synthetic\ServerDeck\mcp.exe')),
    (
      'mcp-arguments',
      find.text(
        '--app-root, C:\\Synthetic\\ServerDeck, --grant-id, ${DesignAutomationFixtures.grantId}',
      ),
    ),
  ]) {
    await _showCaptureContent(tester, entry.$2);
    await capture(
      entry.$1,
      '${entry.$1}-visible',
      [(entry.$1, entry.$2)],
      [
        'The configuration heading, full command and full arguments are separate '
            'readable views of the same real production section at200% text.',
      ],
    );
  }
  final title = find.text('Команда и аргументы MCP');
  await _showCaptureContent(tester, title);
  expect(title.hitTestable(), findsOneWidget);
  await tester.tap(title);
  await tester.pumpAndSettle();
  await _showCaptureContent(tester, title);
  final details = find.ancestor(
    of: title,
    matching: find.byType(AutomationJsonView),
  );
  final json = find.descendant(
    of: details,
    matching: find.byType(SelectableText),
  );
  final raw = tester.widget<SelectableText>(json).data!;
  expect(raw, contains('mcp.exe'));
  expect(raw, contains(DesignAutomationFixtures.grantId));
  // Full JSON can be taller than the frame. Verify a readable visible portion,
  // then describe that exact partial view rather than pretending it all fits.
  var intersection = tester
      .getRect(json)
      .intersect(
        Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio),
      );
  tester.element(json).visitAncestorElements((element) {
    if (element.widget is Scrollable) {
      intersection = intersection.intersect(
        tester.getRect(
          find.byElementPredicate((candidate) => identical(candidate, element)),
        ),
      );
    }
    return true;
  });
  expect(intersection.height, greaterThanOrEqualTo(80));
  expect(intersection.width, greaterThan(0));
  await capture(
    'mcp-details',
    'mcp-json-details-expanded-readable-start',
    [('expanded MCP technical details heading', title)],
    [
      'The technical JSON is expanded. Its beginning has a verified visible '
          'intersection of at least80px; remaining raw lines use the existing '
          'vertical page scroll. Full JSON simultaneous visibility is not claimed.',
    ],
  );
  final copy = designButton('Скопировать конфигурацию');
  await _showCaptureContent(tester, copy);
  expect(copy.hitTestable(), findsOneWidget);
  await capture(
    'mcp-copy',
    'mcp-copy-action-visible',
    [('configuration copy action', copy)],
    [
      'The existing copy action is visible and hit-testable. Captures do not '
          'activate it or claim a real clipboard/native MCP configuration.',
    ],
  );
}

Future<void> _decodeBrandImages(WidgetTester tester) async {
  final context = tester.element(find.byType(Scaffold).first);
  final failures = <String>[];
  await tester.runAsync<void>(() async {
    for (final asset in const [
      BrandAssets.lightLogo,
      BrandAssets.darkLogo,
      BrandAssets.lightMark,
      BrandAssets.darkMark,
    ]) {
      await precacheImage(
        AssetImage(asset),
        context,
        onError: (error, stack) => failures.add('$asset: $error'),
      );
    }
  });
  expect(failures, isEmpty, reason: 'Bundled brand images must decode');
  await tester.pump();
}

void _expectDecodedImages(WidgetTester tester) {
  for (final element in find.byType(RawImage).evaluate()) {
    final raw = element.widget as RawImage;
    expect(
      raw.image,
      isNotNull,
      reason: 'Mounted image must decode before capture',
    );
  }
}

Future<Directory> _prepareOutputDirectory(String configured) async {
  final requested = Directory(configured);
  if (!requested.isAbsolute) {
    throw ArgumentError.value(
      configured,
      'DESIGN_CAPTURE_DIR',
      'An absolute output path is required',
    );
  }
  final workspace = Directory(await Directory.current.resolveSymbolicLinks());
  final intended = Directory.fromUri(
    workspace.uri.resolve('.local/design-003/$_captureStage/'),
  );
  final normalized = Directory.fromUri(requested.uri.normalizePath());
  if (!_isAtOrUnder(normalized.path, intended.path)) {
    throw ArgumentError.value(
      configured,
      'DESIGN_CAPTURE_DIR',
      '$_captureTask captures belong under ${intended.path}',
    );
  }

  // Resolve the existing ancestor before creating anything, so a redirected
  // local output directory cannot cause writes outside the intended location.
  var ancestor = normalized;
  final missingSegments = <String>[];
  while (!await ancestor.exists()) {
    missingSegments.insert(
      0,
      ancestor.uri.pathSegments.where((part) => part.isNotEmpty).last,
    );
    final parent = ancestor.parent;
    if (parent.path == ancestor.path) {
      throw StateError('Cannot resolve the capture output directory');
    }
    ancestor = parent;
  }
  var resolved = Directory(await ancestor.resolveSymbolicLinks());
  for (final segment in missingSegments) {
    resolved = Directory.fromUri(
      resolved.uri.resolve('${Uri.encodeComponent(segment)}/'),
    );
  }
  if (!_isAtOrUnder(resolved.path, intended.path)) {
    throw ArgumentError.value(
      configured,
      'DESIGN_CAPTURE_DIR',
      'The resolved output path leaves ${intended.path}',
    );
  }
  if (_adaptive &&
      await resolved.exists() &&
      !(await resolved.list(followLinks: false).isEmpty)) {
    throw ArgumentError.value(
      configured,
      'DESIGN_CAPTURE_DIR',
      'Adaptive capture output must be fresh and empty; prior evidence is preserved',
    );
  }
  await resolved.create(recursive: true);
  return resolved;
}

bool _isAtOrUnder(String candidate, String parent) {
  String key(String path) {
    final normalized = path
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  final candidateKey = key(candidate);
  final parentKey = key(parent);
  return candidateKey == parentKey || candidateKey.startsWith('$parentKey/');
}
