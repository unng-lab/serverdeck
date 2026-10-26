import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/profiles/profile_list.dart';
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck_protocol/models.dart' show ReadinessState;

import 'design_scenarios.dart';

Future<void>? _fontsLoaded;

Future<void> loadDesignFonts() => _fontsLoaded ??= _loadDesignFonts();

Future<void> _loadDesignFonts() async {
  final sans = FontLoader('Noto Sans')
    ..addFont(rootBundle.load('assets/brand/fonts/NotoSans-Regular.ttf'))
    ..addFont(rootBundle.load('assets/brand/fonts/NotoSans-SemiBold.ttf'));
  final mono = FontLoader('Noto Sans Mono')
    ..addFont(rootBundle.load('assets/brand/fonts/NotoSansMono-Regular.ttf'));
  final unicode = FontLoader('Noto Sans SC')
    ..addFont(rootBundle.load('assets/brand/fonts/NotoSansSC-Variable.ttf'));
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await Future.wait([sans.load(), mono.load(), unicode.load(), icons.load()]);
}

/// One bounded, reduced-motion production fixture for assertions and captures.
/// Main sections use real FoundationShell; extracted modal bodies use their
/// actual production widget. No native connection or permission is synthesized.
class DesignFixtureHost {
  DesignFixtureHost(
    this.binding,
    this.harness,
    this.frame,
    this.theme, {
    this.textScale = 1,
  }) : fixture = binding.build(harness);

  final AcceptanceBinding binding;
  final DesignScenarioHarness harness;
  final Size frame;
  ThemeMode theme;
  double textScale;
  final Widget fixture;
  final boundaryKey = GlobalKey();

  String get baselineState => switch (binding.screenId) {
    '05-server-list' => 'profile-expanded',
    '12-credential-input' => 'credential-password',
    '31-recent-operations' => 'history-open',
    '36-ai-grants' => 'grants-expanded',
    '38-mcp-client-config' => 'configuration-visible',
    _ => binding.states.first,
  };

  bool get _modal => {
    '07-profile-create',
    '08-profile-edit',
    '09-profile-delete',
    '10-host-trust',
    '12-credential-input',
    '19-plan-approval',
    '23-log-record',
    '33-profile-authoring',
    '35-plan-parameters',
    '37-ai-grant-form',
    '39-delegations',
    '40-executor-binding',
    '85-settings-form',
  }.contains(binding.screenId);

  bool get _ownScroll =>
      binding.group == 'A01' ||
      binding.group == 'A02' ||
      binding.screenId == '84-settings';

  Widget _home() {
    if (_modal || binding.group == 'A01') return Scaffold(body: fixture);
    final content = _ownScroll
        ? fixture
        : SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: fixture,
          );
    return FoundationShell(
      state: ReadinessState.ready,
      targetName: harness.profiles.selected?.name,
      targetAddress: harness.profiles.selected == null
          ? null
          : '${harness.profiles.selected!.address}:${harness.profiles.selected!.port}',
      servers: binding.screenId == '31-recent-operations'
          ? ProfileList(controller: harness.profiles)
          : content,
      software: content,
      settings: content,
      recoveryAction: binding.screenId == '31-recent-operations'
          ? fixture
          : null,
    );
  }

  Widget _app() => RepaintBoundary(
    key: boundaryKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: Motion.theme(BrandTheme.light, true),
      darkTheme: Motion.theme(BrandTheme.dark, true),
      themeMode: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: _home(),
    ),
  );

  Future<void> setTheme(WidgetTester tester, ThemeMode next) async {
    theme = next;
    await tester.pumpWidget(_app());
    await tester.pump();
  }

  Future<void> setTextScale(WidgetTester tester, double next) async {
    textScale = next;
    await tester.pumpWidget(_app());
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await harness.close();
  }
}

/// Real navigation/expansion actions establish the primary reference state.
/// These are UI-only actions; action counters and service calls are checked by
/// the adoption suite independently of capture success.
Future<DesignFixtureHost> mountDesignFixture(
  WidgetTester tester,
  AcceptanceBinding binding, {
  required Size frame,
  required ThemeMode theme,
  double textScale = 1,
  DesignFixtureOptions options = const DesignFixtureOptions(),
}) async {
  tester.view.physicalSize = frame;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = await DesignScenarioHarness.create(
    screenId: binding.screenId,
    options: options,
  );
  final host = DesignFixtureHost(
    binding,
    harness,
    frame,
    theme,
    textScale: textScale,
  );
  await tester.pumpWidget(host._app());
  await tester.pump();
  if (binding.screenId == '16-install-catalog' ||
      binding.screenId == '84-settings') {
    final section = binding.screenId == '84-settings' ? 'settings' : 'software';
    final navigation = find.byKey(ValueKey('foundation-navigation-$section'));
    await tester.ensureVisible(navigation);
    await tester.pump();
    await tester.tap(navigation);
    await tester.pump();
  }
  switch (binding.screenId) {
    case '05-server-list':
      final profile = find.descendant(
        of: find.byType(ExpansionTile),
        matching: find.text(harness.profiles.profiles.single.name),
      );
      await tester.scrollUntilVisible(
        profile,
        200,
        scrollable: find
            .descendant(
              of: find.byType(ProfileList),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(profile);
      await tester.pump();
      expect(profile.hitTestable(), findsOneWidget);
      await tester.tap(profile);
      await tester.pump();
    case '12-credential-input':
      await tester.ensureVisible(find.text('Без секрета / удалить'));
      await tester.tap(find.text('Без секрета / удалить'));
      await tester.pump();
      await tester.tap(find.text('Новый пароль').last);
      await tester.pump();
    case '31-recent-operations':
      await tester.tap(find.byTooltip('Недавние подтверждённые операции'));
      await tester.pump();
    case '36-ai-grants' || '38-mcp-client-config':
      await tester.tap(find.text('Доступ ИИ рабочего пространства'));
      await tester.pump();
      if (binding.screenId == '38-mcp-client-config') {
        await Scrollable.ensureVisible(
          tester.element(find.text('Конфигурация MCP').last),
          alignment: 0,
        );
        await tester.pump();
      }
    default:
      break;
  }
  await tester.pump();
  return host;
}

/// A second view of the same actual overview makes the compact plots visible
/// while retaining its history source/quality/time and persistent target.
Future<void> revealDesignGraphs(WidgetTester tester) async {
  final plots = find.byKey(const ValueKey('metrics-history-plots'));
  await Scrollable.ensureVisible(tester.element(plots), alignment: .85);
  await tester.pump();
}

/// On-screen evidence complements content finders, which also match clipped
/// scroll children. Every point of the target must be inside the physical
/// capture frame, and the target must intersect every ancestor scroll viewport.
void expectDesignVisible(WidgetTester tester, Finder finder) {
  final rect = tester.getRect(finder.first);
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(rect.width, greaterThan(0));
  expect(rect.height, greaterThan(0));
  expect(rect.left, greaterThanOrEqualTo(-.1));
  expect(rect.top, greaterThanOrEqualTo(-.1));
  expect(rect.right, lessThanOrEqualTo(size.width + .1));
  expect(rect.bottom, lessThanOrEqualTo(size.height + .1));
  tester.element(finder.first).visitAncestorElements((element) {
    if (element.widget is Scrollable) {
      final viewport = tester.getRect(
        find.byElementPredicate((value) => identical(value, element)),
      );
      expect(rect.top, greaterThanOrEqualTo(viewport.top - .1));
      expect(rect.bottom, lessThanOrEqualTo(viewport.bottom + .1));
    }
    return true;
  });
}

Finder designButton(String label) => find
    .ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    )
    .first;

Future<void> activateDesignButton(WidgetTester tester, String label) async {
  final button = designButton(label);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump();
}
