import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck_protocol/models.dart';

import '../../lib/automation/automation_panel.dart';
import '../../lib/automation/automation_controller.dart';
import '../../lib/profiles/profile_controller.dart';
import '../../lib/settings/settings_controller.dart';

/// Real owner UI over the scenario's native service, with no replacement store.
Future<void> verifyMcpUi(
  WidgetTester tester,
  ProfileController model, {
  required String jobId,
  required String serverId,
}) async {
  void check(bool value) {
    if (!value) throw StateError('MCP_UI_MATRIX_FAILED');
  }

  final previousError = FlutterError.onError;
  var errors = 0;
  FlutterError.onError = (_) => errors++;
  final initial = model.settings!;
  final originalSize = tester.view.physicalSize;
  final originalRatio = tester.view.devicePixelRatio;

  Future<String> records() async {
    final reader = AutomationController(
      client: model.bootstrap.client.trustedClient!,
      serverId: serverId,
    );
    try {
      await tester.runAsync(reader.initialize);
      check(
        reader.error == null &&
            reader.profilesCursor == null &&
            reader.jobsCursor == null &&
            reader.approvalsNext == null &&
            reader.delegationsNext == null,
      );
      return jsonEncode({
        'profiles': reader.profiles.map((row) => row.toJson()).toList(),
        'grants': reader.grants,
        'jobs': reader.jobs,
        'approvals': reader.approvals,
        'delegations': reader.delegations,
      });
    } finally {
      reader.dispose();
    }
  }

  Future<void> frames() async {
    // Service polling can keep scheduling frames; never use unbounded settle.
    for (var n = 0; n < 5; n++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    check(errors == 0 && tester.takeException() == null);
    // AutomationPanel publishes controller errors through this live region.
    // Do not continue waiting for an enabled control after a service failure.
    check(
      find
          .descendant(
            of: find.byType(AutomationPanel),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.liveRegion == true,
            ),
          )
          .evaluate()
          .isEmpty,
    );
  }

  Future<void> until(bool Function() condition) async {
    final deadline = Stopwatch()..start();
    while (!condition()) {
      check(deadline.elapsed < const Duration(minutes: 2));
      await frames();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
    await frames();
  }

  Finder button(String label) => find.byWidgetPredicate(
    (widget) =>
        widget is ButtonStyleButton &&
        find
            .descendant(of: find.byWidget(widget), matching: find.text(label))
            .evaluate()
            .isNotEmpty,
  );

  bool focused(Finder target) {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context is! Element) return false;
    final element = tester.element(target);
    var inside = identical(context, element);
    context.visitAncestorElements((ancestor) {
      if (identical(ancestor, element)) inside = true;
      return !inside;
    });
    return inside;
  }

  Future<void> keyboardActivate(Finder target) async {
    check(target.evaluate().length == 1);
    await until(
      () => tester.widget<ButtonStyleButton>(target).onPressed != null,
    );
    await tester.ensureVisible(target);
    await frames();
    for (var n = 0; !focused(target) && n < 120; n++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump(const Duration(milliseconds: 20));
    }
    check(focused(target) && target.hitTestable().evaluate().length == 1);
    final current = FocusManager.instance.primaryFocus;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    try {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    } finally {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }
    await frames();
    check(FocusManager.instance.primaryFocus != current);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await frames();
    check(focused(target));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await frames();
  }

  Future<void> tapText(String text) async {
    final target = find.text(text);
    check(target.evaluate().length == 1);
    await until(
      () => find
          .ancestor(of: target, matching: find.byType(ListTile))
          .evaluate()
          .every((element) => (element.widget as ListTile).enabled),
    );
    await tester.ensureVisible(target);
    await frames();
    check(target.hitTestable().evaluate().length == 1);
    await tester.tap(target);
    await frames();
  }

  Future<void> theme(ThemePreference value, bool reduceMotion) async {
    final draft = SettingsController(model: model);
    try {
      check(draft.initialized && draft.editable);
      draft.edit(theme: value, reduceMotion: reduceMotion);
      await tester.runAsync(() async {
        await draft.save();
        await model.refresh();
      });
      check(
        model.loaded &&
            model.settings!.theme == value &&
            model.settings!.reduceMotion == reduceMotion,
      );
    } finally {
      draft.dispose();
    }
    await frames();
  }

  try {
    final before = await records();
    tester.view.devicePixelRatio = 1;
    for (final preference in [ThemePreference.light, ThemePreference.dark]) {
      await theme(preference, true);
      for (final size in const [
        Size(1100, 760),
        Size(800, 600),
        Size(360, 800),
        Size(390, 800),
      ]) {
        tester.view.physicalSize = size;
        await frames();
        // Open the actual workspace entry using traversal, not direct callback.
        await keyboardActivate(button('ИИ-доступ и Ansible-профили'));
        await until(() => find.byType(AutomationPanel).evaluate().isNotEmpty);
        final context = tester.element(find.byType(AutomationPanel).last);
        check(
          Theme.of(context).brightness ==
              (preference == ThemePreference.light
                  ? Brightness.light
                  : Brightness.dark),
        );
        check(MediaQuery.sizeOf(context) == size);
        final panel = find.descendant(
          of: find.byType(Dialog),
          matching: find.text('ИИ-доступ и Ansible-профили'),
        );
        check(panel.evaluate().length == 1);
        await tester.tap(panel);
        await until(() => find.text('fixture-motd-two').evaluate().isNotEmpty);
        await tapText('Доступ ИИ рабочего пространства');
        await until(() => button('Подключить ИИ').evaluate().isNotEmpty);
        await keyboardActivate(button('Подключить ИИ'));
        await until(() => find.byType(AlertDialog).evaluate().isNotEmpty);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await frames();
        check(find.byType(AlertDialog).evaluate().isEmpty);
        await keyboardActivate(button('Новый профиль'));
        await until(
          () => find.text('Новый Ansible-профиль').evaluate().isNotEmpty,
        );
        check(find.byType(TextField).evaluate().length == 3);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await frames();
        check(find.text('Новый Ansible-профиль').evaluate().isEmpty);
        await keyboardActivate(button('Закрыть'));
        await frames();
        check(find.byType(Dialog).evaluate().isEmpty);

        // Open the existing server and read its actual durable job in the UI.
        await tapText('fixture');
        await tapText('Автоматизация');
        await until(() => find.text(jobId).evaluate().isNotEmpty);
        await tapText(jobId);
        await until(
          () => find.text('Состояние: succeeded').evaluate().isNotEmpty,
        );
        await tapText('Запросы подтверждения этого сервера');
        await tapText('Делегированные версии');
        check(find.text('Состояние: succeeded').evaluate().isNotEmpty);
        await tapText('fixture');
        await frames();
      }
    }
    check(await records() == before);
  } finally {
    try {
      await theme(initial.theme, initial.reduceMotion);
    } finally {
      tester.view.physicalSize = originalSize;
      tester.view.devicePixelRatio = originalRatio;
      FlutterError.onError = previousError;
    }
  }
  check(errors == 0);
}
