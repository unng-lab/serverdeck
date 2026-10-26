import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/servers/metrics_history.dart';
import 'package:serverdeck/theme/brand_theme.dart';

import '../support/design_host.dart';
import '../support/design_scenarios.dart';

Finder get _feature => find.byKey(const ValueKey('foundation-feature-slot'));
Finder get _featureScroll =>
    find.descendant(of: _feature, matching: find.byType(Scrollable)).first;
Finder get _valuesFocus =>
    find.byKey(const ValueKey('metrics-history-values-focus'));

FocusNode _valuesNode(WidgetTester tester) =>
    tester.widget<Focus>(_valuesFocus).focusNode!;

Rect _visibleBounds(WidgetTester tester, Finder finder) {
  var bounds =
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  tester.element(finder).visitAncestorElements((element) {
    if (element.widget is Scrollable) {
      bounds = bounds.intersect(
        tester.getRect(
          find.byElementPredicate((candidate) => identical(candidate, element)),
        ),
      );
    }
    return true;
  });
  return bounds;
}

bool _contains(Rect outer, Rect inner) =>
    inner.width > 0 &&
    inner.height > 0 &&
    inner.left >= outer.left - .1 &&
    inner.right <= outer.right + .1 &&
    inner.top >= outer.top - .1 &&
    inner.bottom <= outer.bottom + .1;

bool _visible(WidgetTester tester, Finder finder) =>
    _contains(_visibleBounds(tester, finder), tester.getRect(finder));

Future<void> _dragTo(WidgetTester tester, Finder target, Finder scroll) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (_visible(tester, target)) return;
    final viewport = tester.getRect(scroll);
    final rect = tester.getRect(target);
    final distance = rect.top < viewport.top
        ? viewport.top - rect.top
        : viewport.bottom - rect.bottom;
    await tester.dragFrom(
      Offset(viewport.right - 6, viewport.top + 8),
      Offset(0, distance.clamp(-100, 100)),
    );
    await tester.pumpAndSettle();
  }
  expectDesignVisible(tester, target);
}

Future<void> _focusByTab(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    final widget = target.evaluate().isEmpty ? null : tester.widget(target);
    if (widget != null &&
        (widget is EditableText
            ? widget.focusNode.hasFocus
            : Focus.of(tester.element(target)).hasFocus)) {
      if (widget is! EditableText) {
        await _keyScrollTo(tester, target);
        expectDesignVisible(tester, target);
      } else {
        _expectFocusedText(tester, target);
      }
      return;
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
  }
  fail('Tab traversal did not reach $target');
}

void _expectFocusedText(WidgetTester tester, Finder finder) {
  final widget = tester.widget<EditableText>(finder);
  expect(widget.focusNode.hasFocus, isTrue);
  final render = tester.state<EditableTextState>(finder).renderEditable;
  final offset = widget.controller.selection.extentOffset;
  expect(offset, greaterThanOrEqualTo(0));
  final caret = render
      .getLocalRectForCaret(TextPosition(offset: offset))
      .shift(render.localToGlobal(Offset.zero));
  expect(
    _contains(_visibleBounds(tester, finder), caret),
    isTrue,
    reason:
        'The keyboard focus caret of ${widget.controller.text} '
        '($caret) must be inside ${_visibleBounds(tester, finder)}',
  );
  final indicator = find.ancestor(
    of: finder,
    matching: find.byKey(const ValueKey('metrics-history-row-focus')),
  );
  expectDesignVisible(tester, indicator);
  final size = tester.getSize(indicator);
  expect(size.width, greaterThanOrEqualTo(44));
  expect(size.height, greaterThanOrEqualTo(44));
  expect(
    tester.renderObject(indicator),
    paints..rrect(
      rrect: RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(1),
        const Radius.circular(8),
      ),
      color: Theme.of(tester.element(finder))
          .extension<BrandColors>()!['focus'],
      strokeWidth: 2,
      style: PaintingStyle.stroke,
    ),
  );
  final textBounds = tester.getRect(finder);
  final ringBounds = tester.getRect(indicator);
  expect(textBounds.left - ringBounds.left, greaterThanOrEqualTo(4));
  expect(ringBounds.right - textBounds.right, greaterThanOrEqualTo(4));
}

Future<void> _shiftTab(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
}

Future<void> _shiftTabTo(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    if (Focus.of(tester.element(target)).hasFocus) {
      await _keyScrollTo(tester, target);
      expectDesignVisible(tester, target);
      return;
    }
    await _shiftTab(tester);
  }
  fail('Shift+Tab traversal did not reach $target');
}

Finder _historyRow(Object? point) {
  final row = point! as Map<String, Object?>;
  return find.text(
    '${row['receivedAt']} UTC · CPU: ${row['cpuPercent']}% · '
    'RAM: ${row['memoryUsedPercent']}% · Диск /: ${row['rootDiskUsedPercent']}%',
  );
}

bool _visibleRow(WidgetTester tester, Object? point) {
  final finder = _historyRow(point);
  return finder.evaluate().isNotEmpty && _visible(tester, finder);
}

Future<void> _keyScrollTo(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (_visible(tester, target)) return;
    final viewport = _visibleBounds(tester, target);
    final rect = tester.getRect(target);
    await _keyStep(tester, rect.top < viewport.top);
  }
  expectDesignVisible(tester, target);
}

Future<void> _keyStep(WidgetTester tester, bool up) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(
    up ? LogicalKeyboardKey.arrowUp : LogicalKeyboardKey.arrowDown,
  );
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

List<Rect> _textLines(WidgetTester tester, Finder text) {
  final widget = tester.widget(text);
  final RenderBox render;
  final List<TextBox> boxes;
  if (widget is EditableText) {
    final editable = tester.state<EditableTextState>(text).renderEditable;
    render = editable;
    boxes = editable.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: widget.controller.text.length),
    );
  } else {
    final paragraph = tester.renderObject<RenderParagraph>(text);
    render = paragraph;
    boxes = paragraph.getBoxesForSelection(
      TextSelection(
        baseOffset: 0,
        extentOffset: paragraph.text.toPlainText().length,
      ),
    );
  }
  return [
    for (final box in boxes)
      box.toRect().shift(render.localToGlobal(Offset.zero)),
  ];
}

/// Covers every rendered line, including paragraphs taller than the viewport.
/// Only actual drag/key input changes the scroll offset; no ensureVisible/jumpTo.
Future<void> _readAllLines(
  WidgetTester tester,
  Finder text,
  Finder scroll, {
  required bool keyboard,
}) async {
  final seen = <int>{};
  var lineCount = 0;
  for (var attempt = 0; attempt < 120; attempt++) {
    if (text.evaluate().isNotEmpty) {
      final lines = _textLines(tester, text);
      lineCount = lines.length;
      expect(lineCount, greaterThan(0));
      final viewport = _visibleBounds(tester, text);
      for (var i = 0; i < lines.length; i++) {
        expect(lines[i].left, greaterThanOrEqualTo(viewport.left - .1));
        expect(lines[i].right, lessThanOrEqualTo(viewport.right + .1));
        if (_contains(viewport, lines[i])) seen.add(i);
      }
      if (seen.length == lineCount) return;
      final next =
          lines[Iterable<int>.generate(lines.length)
              .firstWhere((i) => !seen.contains(i))];
      final up = next.top < viewport.top;
      if (keyboard) {
        final widget = tester.widget(text);
        if (widget is EditableText && widget.focusNode.hasFocus) {
          await tester.sendKeyEvent(
            up ? LogicalKeyboardKey.arrowUp : LogicalKeyboardKey.arrowDown,
          );
          await tester.pumpAndSettle();
        } else {
          await _keyStep(tester, up);
        }
      } else {
        final view = tester.getRect(scroll);
        await tester.dragFrom(
          Offset(view.right - 6, view.center.dy),
          Offset(0, (up ? 1 : -1) * (view.height * .3).clamp(30, 80)),
        );
        await tester.pumpAndSettle();
      }
    } else {
      expect(
        keyboard,
        isFalse,
        reason: 'Keyboard traversal must build the row',
      );
      final view = tester.getRect(scroll);
      await tester.dragFrom(
        Offset(view.right - 6, view.center.dy),
        const Offset(0, -70),
      );
      await tester.pumpAndSettle();
    }
  }
  fail('Read ${seen.length}/$lineCount rendered lines of $text');
}

class _Identity {
  _Identity(WidgetTester tester, this.host)
    : profiles = host.harness.profiles,
      shell = tester.state(find.byType(Scaffold).first),
      history = find.byType(MetricsHistory).evaluate().isEmpty
          ? null
          : tester.state(find.byType(MetricsHistory)),
      reads = host.harness.client.reads.length,
      writes = host.harness.client.mutations.length,
      refreshes = host.harness.client.refreshes;
  final DesignFixtureHost host;
  final Object profiles, shell;
  final Object? history;
  final int reads, writes, refreshes;
  void check(WidgetTester tester, {int copies = 0}) {
    expect(host.harness.profiles, same(profiles));
    expect(tester.state(find.byType(Scaffold).first), same(shell));
    if (history != null) {
      expect(tester.state(find.byType(MetricsHistory)), same(history));
    }
    expect(host.harness.client.reads.length, reads);
    expect(host.harness.client.mutations.length, writes);
    expect(host.harness.client.refreshes, refreshes);
    expect(
      host.harness.counters.values,
      copies == 0 ? isEmpty : {'copyConfiguration': copies},
    );
    expectDesignVisible(tester, _target(host));
    expect(tester.takeException(), isNull);
  }
}

Future<void> _historyJourney(
  WidgetTester tester,
  DesignFixtureHost host,
  String quality, {
  required bool keyboard,
}) async {
  await _revealTarget(tester, host);
  final identity = _Identity(tester, host);
  final button = find.widgetWithText(TextButton, 'Значения истории');
  if (keyboard) await _focusByTab(tester, find.text('Значения истории'));
  for (final value in [
    'Источник: ssh:proc/stat+meminfo+net/dev+df',
    'Наблюдение: ${DesignServerFixtures.observedAt} · UTC',
    'Получено: ${DesignServerFixtures.observedAt} · UTC',
  ]) {
    await _readAllLines(
      tester,
      find.descendant(
        of: find.byType(MetricsHistory),
        matching: find.text(value),
      ),
      _featureScroll,
      keyboard: keyboard,
    );
    identity.check(tester);
  }
  final plots = find.byKey(const ValueKey('metrics-history-plots'));
  if (keyboard) {
    await _keyScrollTo(tester, plots);
  } else {
    await _dragTo(tester, plots, _featureScroll);
  }
  expectDesignVisible(tester, plots);
  _expectQuality(tester, quality);
  identity.check(tester);
  if (keyboard) {
    await _keyScrollTo(tester, button);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    await _dragTo(tester, button, _featureScroll);
    expect(button.hitTestable(), findsOneWidget);
    await tester.tap(button);
  }
  await tester.pumpAndSettle();
  final section = find.byKey(const ValueKey('metrics-history-values-section'));
  final values = find.byKey(const ValueKey('metrics-history-values'));
  if (keyboard) {
    await _keyScrollTo(tester, section);
  } else {
    await _dragTo(tester, section, _featureScroll);
  }
  expect(tester.getSize(section).height, lessThanOrEqualTo(280));
  expect(tester.getSize(_valuesFocus).height, greaterThanOrEqualTo(44));
  expect(tester.getSize(_valuesFocus).width, greaterThanOrEqualTo(44));
  expectDesignVisible(tester, section);
  final scroll = find.descendant(of: values, matching: find.byType(Scrollable));
  final points = DesignServerFixtures.history();
  for (final point in points) {
    final text = _historyRow(point);
    if (keyboard) await _focusByTab(tester, text);
    await _readAllLines(tester, text, scroll.first, keyboard: keyboard);
    expectDesignVisible(
      tester,
      find.byKey(const ValueKey('metrics-history-values-quality')),
    );
    _expectQuality(tester, quality);
    identity.check(tester);
  }
  if (keyboard) {
    for (var index = points.length - 2; index >= 0; index--) {
      await _shiftTab(tester);
      _expectFocusedText(tester, _historyRow(points[index]));
      await _readAllLines(
        tester,
        _historyRow(points[index]),
        scroll.first,
        keyboard: true,
      );
      expectDesignVisible(
        tester,
        find.byKey(const ValueKey('metrics-history-values-quality')),
      );
      identity.check(tester);
    }
    final focused = tester
        .widget<EditableText>(_historyRow(points.first))
        .focusNode;
    await _shiftTab(tester);
    expect(_valuesNode(tester).hasPrimaryFocus, isTrue);
    expectDesignVisible(tester, _valuesFocus);
    await _shiftTab(tester);
    await _shiftTabTo(tester, find.text('Значения истории'));
    expectDesignVisible(tester, button);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(focused.context?.mounted ?? false, isFalse);
    expect(focused.hasFocus, isFalse);
  } else {
    await _dragTo(tester, button, _featureScroll);
    await tester.tap(button);
  }
  await tester.pumpAndSettle();
  expect(values, findsNothing);
  await host.setTheme(
    tester,
    host.theme == ThemeMode.light ? ThemeMode.dark : ThemeMode.light,
  );
  identity.check(tester);
}

Future<void> _configurationJourney(
  WidgetTester tester,
  DesignFixtureHost host, {
  required bool keyboard,
}) async {
  await _revealTarget(tester, host);
  final identity = _Identity(tester, host);
  final detailsTitle = find.text('Команда и аргументы MCP');
  if (keyboard) await _focusByTab(tester, detailsTitle);
  final configuration = DesignAutomationFixtures.launchConfiguration();
  for (final text in [
    find.text('Конфигурация MCP').last,
    find.text(
      'Передайте клиенту ИИ команду и отдельные аргументы. Секрет доступа в этой конфигурации не показывается.',
    ),
    find.text(configuration['command'] as String),
    find.text((configuration['args'] as List).join(', ')),
  ]) {
    await _readAllLines(tester, text, _featureScroll, keyboard: keyboard);
    identity.check(tester);
  }
  if (keyboard) {
    await _keyScrollTo(tester, detailsTitle);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    await _dragTo(tester, detailsTitle, _featureScroll);
    await tester.tap(detailsTitle);
  }
  await tester.pumpAndSettle();
  final details = find
      .ancestor(of: detailsTitle, matching: find.byType(ExpansionTile))
      .first;
  await _readAllLines(
    tester,
    find.descendant(of: details, matching: find.byType(EditableText)),
    _featureScroll,
    keyboard: keyboard,
  );
  identity.check(tester);
  final copy = find.text('Скопировать конфигурацию');
  if (keyboard) {
    await _focusByTab(tester, copy);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    await _focusByTab(tester, detailsTitle);
    expectDesignVisible(tester, detailsTitle);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: details, matching: find.byType(EditableText)),
      findsNothing,
    );
    await _focusByTab(tester, copy);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
  } else {
    final button = find.ancestor(
      of: copy,
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    );
    await _dragTo(tester, button, _featureScroll);
    expect(button.hitTestable(), findsOneWidget);
    await tester.tap(button);
  }
  await tester.pumpAndSettle();
  identity.check(tester, copies: 1);
}

Finder _target(DesignFixtureHost host) {
  final profile = host.harness.profiles.selected!;
  return find.text('${profile.name} · ${profile.address}:${profile.port}');
}

Future<void> _revealTarget(WidgetTester tester, DesignFixtureHost host) async {
  final header = find.byKey(const ValueKey('foundation-page-context'));
  final scroll = find.descendant(of: header, matching: find.byType(Scrollable));
  await _dragTo(tester, _target(host), scroll);
  expectDesignVisible(tester, _target(host));
}

void _expectQuality(WidgetTester tester, String label) {
  final labels = find.descendant(
    of: find.byType(MetricsHistory),
    matching: find.text(label),
  );
  expect(
    labels.evaluate().any(
      (element) => _visible(
        tester,
        find.byElementPredicate((candidate) => identical(candidate, element)),
      ),
    ),
    isTrue,
    reason: '$label must be rendered with the displayed plots or text values',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDesignFonts);
  final overview = designBindings.singleWhere(
    (binding) => binding.screenId == '06-server-overview',
  );
  final configuration = designBindings.singleWhere(
    (binding) => binding.screenId == '38-mcp-client-config',
  );
  testWidgets(
    'same projection rebuild preserves chosen history scroll offsets',
    (tester) async {
      final points = DesignServerFixtures.history(count: 20);
      final host = await mountDesignFixture(
        tester,
        overview,
        frame: const Size(1100, 760),
        theme: ThemeMode.light,
        options: DesignFixtureOptions(points: points),
      );
      try {
        await _revealTarget(tester, host);
        final identity = _Identity(tester, host);
        await _focusByTab(tester, find.text('Значения истории'));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        final row = _historyRow(points[2]);
        await _focusByTab(tester, row);
        final values = find.byKey(const ValueKey('metrics-history-values'));
        final innerScroll = find
            .descendant(of: values, matching: find.byType(Scrollable))
            .first;
        await tester.drag(innerScroll, const Offset(0, 24));
        await tester.pumpAndSettle();
        final viewport = tester.getRect(_featureScroll);
        await tester.dragFrom(
          Offset(viewport.right - 6, viewport.top + 8),
          const Offset(0, 24),
        );
        await tester.pumpAndSettle();
        _expectFocusedText(tester, row);
        expectDesignVisible(
          tester,
          find.byKey(const ValueKey('metrics-history-values-quality')),
        );
        final inner = tester.state<ScrollableState>(innerScroll).position;
        final outer = tester.state<ScrollableState>(_featureScroll).position;
        final innerOffset = inner.pixels;
        final outerOffset = outer.pixels;
        // The owner can rebuild the presentation without changing its projection.
        tester.element(find.byType(MetricsHistory)).markNeedsBuild();
        await tester.pumpAndSettle();
        expect(
          inner.pixels,
          innerOffset,
          reason: 'Unchanged owner projection must preserve inner scroll',
        );
        expect(
          outer.pixels,
          outerOffset,
          reason: 'Unchanged owner projection must preserve outer scroll',
        );
        _expectFocusedText(tester, row);
        identity.check(tester);
      } finally {
        await host.close(tester);
      }
    },
  );
  testWidgets(
    '120 history rows keep keyboard access and bounded focus lifecycle',
    (tester) async {
      final points = DesignServerFixtures.history(count: 120);
      final host = await mountDesignFixture(
        tester,
        overview,
        frame: const Size(800, 600),
        theme: ThemeMode.light,
        textScale: 2,
        options: DesignFixtureOptions(stale: true, points: points),
      );
      FocusNode? retired;
      ScrollController? retiredController;
      try {
        await _revealTarget(tester, host);
        final identity = _Identity(tester, host);
        final disclosure = find.text('Значения истории');
        await _focusByTab(tester, disclosure);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        await _focusByTab(tester, _historyRow(points.first));
        final firstNode = tester
            .widget<EditableText>(_historyRow(points.first))
            .focusNode;
        final initialAreaNode = _valuesNode(tester);
        final initialController = tester
            .widget<ListView>(
              find.byKey(const ValueKey('metrics-history-values')),
            )
            .controller;
        retiredController = initialController;
        await host.setTheme(tester, ThemeMode.dark);
        await tester.pumpAndSettle();
        tester.view.physicalSize = const Size(1100, 760);
        await tester.pumpAndSettle();
        expect(
          tester.widget<EditableText>(_historyRow(points.first)).focusNode,
          same(firstNode),
        );
        expect(_valuesNode(tester), same(initialAreaNode));
        expect(
          tester
              .widget<ListView>(
                find.byKey(const ValueKey('metrics-history-values')),
              )
              .controller,
          same(initialController),
        );
        _expectFocusedText(tester, _historyRow(points.first));
        tester.view.physicalSize = const Size(800, 600);
        await tester.pumpAndSettle();
        expect(
          tester.widget<EditableText>(_historyRow(points.first)).focusNode,
          same(firstNode),
        );
        final values = find.byKey(const ValueKey('metrics-history-values'));
        await _shiftTab(tester);
        final areaNode = _valuesNode(tester);
        expect(areaNode.hasPrimaryFocus, isTrue);
        for (
          var page = 0;
          !_visibleRow(tester, points.last) && page < 120;
          page++
        ) {
          await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
          await tester.pumpAndSettle();
          expect(areaNode.hasPrimaryFocus, isTrue);
          expectDesignVisible(tester, _valuesFocus);
          expectDesignVisible(
            tester,
            find.byKey(const ValueKey('metrics-history-values-quality')),
          );
          identity.check(tester);
        }
        expectDesignVisible(tester, _historyRow(points.last));
        expect(
          find
              .descendant(of: values, matching: find.byType(EditableText))
              .evaluate()
              .length,
          lessThan(20),
        );
        expect(
          firstNode.context?.mounted ?? false,
          isFalse,
          reason:
              'Rows outside the bounded list cache must dispose their focus',
        );
        for (
          var page = 0;
          !_visibleRow(tester, points.first) && page < 120;
          page++
        ) {
          await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
          await tester.pumpAndSettle();
          expect(areaNode.hasPrimaryFocus, isTrue);
          expectDesignVisible(
            tester,
            find.byKey(const ValueKey('metrics-history-values-quality')),
          );
        }
        expectDesignVisible(tester, _historyRow(points.first));
        await _focusByTab(tester, _historyRow(points.first));
        final closingNode = tester
            .widget<EditableText>(_historyRow(points.first))
            .focusNode;
        await _shiftTab(tester);
        expect(areaNode.hasPrimaryFocus, isTrue);
        await _shiftTab(tester);
        await _shiftTabTo(tester, disclosure);
        expectDesignVisible(tester, disclosure);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(closingNode.context?.mounted ?? false, isFalse);
        expect(closingNode.hasFocus, isFalse);
        expect(values, findsNothing);
        identity.check(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        await _focusByTab(tester, _historyRow(points.first));
        retired = tester
            .widget<EditableText>(_historyRow(points.first))
            .focusNode;
      } finally {
        await host.close(tester);
      }
      expect(retired.context?.mounted ?? false, isFalse);
      expect(retired.hasFocus, isFalse);
      expect(retiredController!.hasClients, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'paging from focused history rows retains visible focus and chosen offset',
    (tester) async {
      final points = DesignServerFixtures.history(count: 120);
      final host = await mountDesignFixture(
        tester,
        overview,
        frame: const Size(800, 600),
        theme: ThemeMode.light,
        textScale: 2,
        options: DesignFixtureOptions(stale: true, points: points),
      );
      FocusNode? retiredRow;
      ScrollController? retiredController;
      try {
        await _revealTarget(tester, host);
        final identity = _Identity(tester, host);
        await _focusByTab(tester, find.text('Значения истории'));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        await _focusByTab(tester, _historyRow(points.first));
        final firstNode = tester
            .widget<EditableText>(_historyRow(points.first))
            .focusNode;
        final values = find.byKey(const ValueKey('metrics-history-values'));
        final controller = tester.widget<ListView>(values).controller!;
        retiredController = controller;
        final areaNode = _valuesNode(tester);

        Future<void> page(LogicalKeyboardKey key) async {
          final previous = controller.offset;
          final expected =
              (previous +
                      controller.position.viewportDimension *
                          .8 *
                          (key == LogicalKeyboardKey.pageDown ? 1 : -1))
                  .clamp(
                    controller.position.minScrollExtent,
                    controller.position.maxScrollExtent,
                  );
          await tester.sendKeyEvent(key);
          await tester.pumpAndSettle();
          expect(areaNode.hasPrimaryFocus, isTrue);
          expectDesignVisible(tester, _valuesFocus);
          expectDesignVisible(
            tester,
            find.byKey(const ValueKey('metrics-history-values-quality')),
          );
          _expectQuality(tester, 'Устаревшие данные');
          final offset = controller.offset;
          expect(offset, expected);
          // A normal owner rebuild must not reveal the formerly focused row.
          tester.element(find.byType(MetricsHistory)).markNeedsBuild();
          await tester.pumpAndSettle();
          expect(controller.offset, offset);
          expect(areaNode.hasPrimaryFocus, isTrue);
          expect(
            find
                .descendant(of: values, matching: find.byType(EditableText))
                .evaluate()
                .length,
            lessThan(20),
          );
          identity.check(tester);
        }

        // PageDown bubbles from the actual focused SelectableText, without
        // first moving focus to the scroll area with Shift+Tab.
        await page(LogicalKeyboardKey.pageDown);
        for (var attempt = 0; attempt < 120; attempt++) {
          if (controller.offset == controller.position.maxScrollExtent) break;
          await page(LogicalKeyboardKey.pageDown);
        }
        expect(controller.offset, controller.position.maxScrollExtent);
        expectDesignVisible(tester, _historyRow(points.last));
        expect(firstNode.context?.mounted ?? false, isFalse);
        await page(LogicalKeyboardKey.pageDown);
        await _focusByTab(tester, _historyRow(points.last));
        final lastNode = tester
            .widget<EditableText>(_historyRow(points.last))
            .focusNode;
        await page(LogicalKeyboardKey.pageUp);
        for (var attempt = 0; attempt < 120; attempt++) {
          if (controller.offset == controller.position.minScrollExtent) break;
          await page(LogicalKeyboardKey.pageUp);
        }
        expect(controller.offset, controller.position.minScrollExtent);
        expectDesignVisible(tester, _historyRow(points.first));
        expect(lastNode.context?.mounted ?? false, isFalse);
        await page(LogicalKeyboardKey.pageUp);

        // Leave the row's two-frame reveal pending when its paging event is
        // dispatched. An obsolete reveal must not undo that PageDown.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        retiredRow = tester
            .widget<EditableText>(_historyRow(points.first))
            .focusNode;
        expect(retiredRow.hasFocus, isTrue);
        await page(LogicalKeyboardKey.pageDown);
        expect(controller.offset, greaterThan(0));
      } finally {
        await host.close(tester);
      }
      expect(retiredRow.context?.mounted ?? false, isFalse);
      expect(retiredRow.hasFocus, isFalse);
      expect(retiredController.hasClients, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  for (final dimensions in designFrames) {
    final frame = Size(dimensions.width, dimensions.height);
    for (final theme in designThemes) {
      for (final scale in designTextScales) {
        for (final stale in [false, true]) {
          final quality = stale ? 'Устаревшие данные' : 'Данные получены';
          final name =
              '${frame.width.toInt()} ${theme.name} ${scale * 100}% '
              '${stale ? 'stale' : 'known'}';
          for (final keyboard in [false, true]) {
            testWidgets('history ${keyboard ? 'keyboard' : 'touch'} $name', (
              tester,
            ) async {
              final host = await mountDesignFixture(
                tester,
                overview,
                frame: frame,
                theme: theme,
                textScale: scale,
                options: DesignFixtureOptions(stale: stale),
              );
              try {
                await _historyJourney(
                  tester,
                  host,
                  quality,
                  keyboard: keyboard,
                );
              } finally {
                await host.close(tester);
              }
            });
          }
        }
        for (final keyboard in [false, true]) {
          testWidgets('configuration ${keyboard ? 'keyboard' : 'touch'} '
              '${frame.width.toInt()} ${theme.name} ${scale * 100}%', (
            tester,
          ) async {
            final host = await mountDesignFixture(
              tester,
              configuration,
              frame: frame,
              theme: theme,
              textScale: scale,
            );
            try {
              await _configurationJourney(tester, host, keyboard: keyboard);
            } finally {
              await host.close(tester);
            }
          });
        }
      }
    }
  }
}
