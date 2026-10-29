import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart' show SvgPicture, vg;
import 'package:serverdeck/profiles/profile_list.dart';
import 'package:serverdeck/shell/foundation_shell.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/theme/motion.dart';
import 'package:serverdeck_protocol/models.dart' show ReadinessState, ErrorCode;

import 'design_scenarios.dart';
export 'design_fonts.dart' show loadDesignFonts;

/// Await actual vector loaders and decoding, rather than photographing their
/// blank asynchronous placeholders. No application state or timeout is changed.
Future<void> loadDesignVectorAssets(WidgetTester tester) async {
  final elements = find.byType(SvgPicture).evaluate().toList();
  await tester.runAsync<void>(() async {
    await Future.wait([
      for (final element in elements)
        (element.widget as SvgPicture).bytesLoader.loadBytes(element),
    ]);
    await vg.waitForPendingDecodes();
  });
  await tester.pump();
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
    this.currentBase = false,
  }) : fixture = currentBase
           ? harness.buildCurrentOrigin(binding.screenId)
           : binding.build(harness);

  final AcceptanceBinding binding;
  final DesignScenarioHarness harness;
  final Size frame;
  ThemeMode theme;
  double textScale;
  final Widget fixture;
  final bool currentBase;
  final boundaryKey = GlobalKey();

  String get baselineState => switch (binding.screenId) {
    '05-server-list' => 'profile-cards',
    '12-credential-input' =>
      currentBase ? 'credential-private-key' : 'credential-password',
    '31-recent-operations' => 'history-page',
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
    if (currentBase) return _currentHome();
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

  FoundationSection get currentSection {
    final number = int.parse(binding.screenId.split('-').first);
    if (number == 13 ||
        number == 36 ||
        number == 37 ||
        number == 38 ||
        number == 84 ||
        number == 85)
      return FoundationSection.settings;
    if (number == 22 || number == 23) return FoundationSection.logs;
    if (number >= 16 && number <= 18) return FoundationSection.software;
    if (number == 19) return FoundationSection.jobs;
    if (number >= 27 && number <= 39 || number == 93 || number == 94)
      return FoundationSection.jobs;
    return FoundationSection.servers;
  }

  Widget _currentHome() {
    final number = int.parse(binding.screenId.split('-').first);
    final isPage = {
      4,
      5,
      6,
      7,
      8,
      9,
      11,
      12,
      13,
      16,
      17,
      18,
      22,
      27,
      28,
      29,
      30,
      31,
      32,
      34,
      36,
      38,
      84,
      85,
      93,
      94,
    }.contains(number);
    final modal = {10, 19, 23, 33, 35, 37, 39, 40}.contains(number);
    final content = isPage || modal
        ? fixture
        : SingleChildScrollView(child: fixture);
    final readiness = switch (number) {
      1 => ReadinessState.starting,
      2 => ReadinessState.unavailable,
      3 => ReadinessState.storageBlocked,
      _ => ReadinessState.ready,
    };
    return FoundationShell(
      state: readiness,
      section: currentSection,
      reason: number == 2
          ? ErrorCode.serviceUnavailable
          : number == 3
          ? ErrorCode.storageBlocked
          : null,
      onRetry: harness.counters.callback('retry'),
      contentBuilder: (_, _) => content,
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
    if (currentBase) await loadDesignVectorAssets(tester);
  }

  Future<void> setTextScale(WidgetTester tester, double next) async {
    textScale = next;
    await tester.pumpWidget(_app());
    await tester.pump();
    if (currentBase) await loadDesignVectorAssets(tester);
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
  bool currentBase = false,
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
    currentBase: currentBase,
  );
  await tester.pumpWidget(host._app());
  await tester.pump();
  if (currentBase) await loadDesignVectorAssets(tester);
  if (!currentBase &&
      (binding.screenId == '16-install-catalog' ||
          binding.screenId == '84-settings')) {
    final section = binding.screenId == '84-settings' ? 'settings' : 'software';
    final navigation = find.byKey(ValueKey('foundation-navigation-$section'));
    await tester.ensureVisible(navigation);
    await tester.pump();
    await tester.tap(navigation);
    await tester.pump();
  }
  switch (binding.screenId) {
    case '12-credential-input':
      final choice = currentBase
          ? 'Сохранить существующий'
          : 'Без секрета / удалить';
      await tester.ensureVisible(find.text(choice));
      await tester.tap(find.text(choice));
      await tester.pump();
      await tester.tap(
        find.text(currentBase ? 'Новый приватный ключ' : 'Новый пароль').last,
      );
      await tester.pump();
    case '31-recent-operations':
      if (currentBase) break;
      await tester.tap(find.byTooltip('Недавние подтверждённые операции'));
      await tester.pump();
    case '17-recipe-detail':
      if (!currentBase) break;
      // Establish the loaded selection through the production state API. The
      // catalogue header owns Choose program; the detail has no duplicate.
      host.harness.recipesKey.currentState!.selectFirst();
      await tester.pump();
    case '36-ai-grants' || '38-mcp-client-config':
      if (currentBase) break;
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
  if (currentBase) await loadDesignVectorAssets(tester);
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
