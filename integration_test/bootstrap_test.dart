import 'support/runtime_hooks.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:serverdeck/main.dart' as app;
import 'package:serverdeck/profiles/recovery_view.dart';
import 'package:serverdeck/settings/settings_view.dart';
import 'package:serverdeck_protocol/models.dart' show ThemePreference;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgetsWithRuntimeHooks(
    'production UI launches locald and reaches authenticated readiness',
    (tester) async {
      app.main();
      final elapsed = Stopwatch()..start();
      while (elapsed.elapsed < const Duration(seconds: 30)) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('Локальная служба готова').evaluate().isNotEmpty) break;
      }
      expect(find.text('Локальная служба готова'), findsOneWidget);
      expect(find.text('Локальная служба недоступна'), findsNothing);
      final model = Stopwatch()..start();
      while (model.elapsed < const Duration(seconds: 10) &&
          find.text('Локальных профилей пока нет').evaluate().isEmpty) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Локальных профилей пока нет'), findsOneWidget);
      stdout.writeln('COMPILED_FLUTTER_MODEL_READ_PROVED');
      await tester.tap(find.text('Создать профиль'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('profile-name')),
        'Compiled profile',
      );
      await tester.enterText(
        find.byKey(const ValueKey('profile-address')),
        'пример.рф',
      );
      await tester.enterText(
        find.byKey(const ValueKey('profile-user')),
        'admin',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      final save = Stopwatch()..start();
      while (save.elapsed < const Duration(seconds: 15) &&
          find.text('Сохранено').evaluate().isEmpty) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Сохранено'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Новый профиль'), findsNothing);
      stdout.writeln('COMPILED_FLUTTER_KEYBOARD_SAVE_PROVED');
      expect(find.text('Compiled profile'), findsOneWidget);
      expect(find.textContaining('xn--e1afmkfd.xn--p1ai:22'), findsOneWidget);
      stdout.writeln('COMPILED_FLUTTER_PROFILE_CREATE_PROVED');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Настройки'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Изменить настройки'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<ThemePreference>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Светлая').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compiled profile').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Сохранить настройки'));
      await tester.tap(find.text('Сохранить настройки'));
      final settingsSave = Stopwatch()..start();
      while (settingsSave.elapsed < const Duration(seconds: 15) &&
          find.text('Сохранено').evaluate().isEmpty) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Сохранено'), findsOneWidget);
      await tester.ensureVisible(find.text('Закрыть'));
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
      expect(find.text('Тема: светлая'), findsOneWidget);
      expect(find.text('Уменьшение анимации: включено'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SettingsView),
          matching: find.text('Compiled profile · xn--e1afmkfd.xn--p1ai:22'),
        ),
        findsOneWidget,
      );
      stdout.writeln('COMPILED_FLUTTER_SETTINGS_SAVE_PROVED');
      await tester.pumpWidget(const SizedBox.shrink());
      final discovery = File(
        '${Platform.environment['LOCALAPPDATA']}\\ServerDeckNext\\v1\\runtime\\default.discovery',
      );
      final shutdown = Stopwatch()..start();
      while (discovery.existsSync() &&
          shutdown.elapsed < const Duration(seconds: 15)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(discovery.existsSync(), false);
      stdout.writeln('COMPILED_FLUTTER_BOOTSTRAP_PROVED');
      app.main();
      final reopen = Stopwatch()..start();
      while (reopen.elapsed < const Duration(seconds: 30) &&
          find.text('Compiled profile').evaluate().isEmpty) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Compiled profile'), findsWidgets);
      stdout.writeln('COMPILED_FLUTTER_PROFILE_REOPEN_PROVED');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Настройки'));
      await tester.pumpAndSettle();
      expect(find.text('Тема: светлая'), findsOneWidget);
      expect(find.text('Уменьшение анимации: включено'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SettingsView),
          matching: find.text('Compiled profile · xn--e1afmkfd.xn--p1ai:22'),
        ),
        findsOneWidget,
      );
      stdout.writeln('COMPILED_FLUTTER_SETTINGS_REOPEN_PROVED');
      await tester.tap(find.byTooltip('Недавние подтверждённые операции'));
      await tester.pumpAndSettle();
      expect(find.text('Создание профиля подтверждено'), findsOneWidget);
      expect(find.text('Изменение настроек подтверждено'), findsOneWidget);
      expect(
        find.textContaining('Автоматический повтор не выполняется'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Закрыть'));
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
      stdout.writeln('COMPILED_FLUTTER_STARTUP_RECENT_PROVED');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Серверы'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ExpansionTile),
          matching: find.text('Compiled profile'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Удалить профиль'));
      await tester.pumpAndSettle();
      expect(find.text('Удалить профиль').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Удалить профиль'));
      await tester.pumpAndSettle();
      final deleteContext = tester.element(find.text('Подтвердить удаление'));
      expect(MediaQuery.disableAnimationsOf(deleteContext), isTrue);
      expect(
        (ModalRoute.of(deleteContext) as TransitionRoute).transitionDuration,
        Duration.zero,
      );
      expect(
        Theme.of(deleteContext).expansionTileTheme.expansionAnimationStyle,
        AnimationStyle.noAnimation,
      );
      stdout.writeln('COMPILED_FLUTTER_REDUCED_MOTION_PROVED');
      expect(
        find.text('Удаляется локальный профиль; сервер не меняется'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Подтвердить удаление'));
      await tester.tap(find.text('Подтвердить удаление'));
      final deletion = Stopwatch()..start();
      while (deletion.elapsed < const Duration(seconds: 15) &&
          find.text('Удалено').evaluate().isEmpty) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Удалено'), findsOneWidget);
      await tester.ensureVisible(find.text('Закрыть'));
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
      expect(find.text('Локальных профилей пока нет'), findsOneWidget);
      expect(find.text('Compiled profile'), findsNothing);
      stdout.writeln('COMPILED_FLUTTER_PROFILE_DELETE_PROVED');
      await tester.pumpWidget(const SizedBox.shrink());
      final finalShutdown = Stopwatch()..start();
      while (discovery.existsSync() &&
          finalShutdown.elapsed < const Duration(seconds: 15)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(discovery.existsSync(), false);
      app.main();
      final emptyReopen = Stopwatch()..start();
      while (emptyReopen.elapsed < const Duration(seconds: 30) &&
          find.text('Локальных профилей пока нет').evaluate().isEmpty) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Локальных профилей пока нет'), findsOneWidget);
      expect(find.text('Compiled profile'), findsNothing);
      stdout.writeln('COMPILED_FLUTTER_EMPTY_REOPEN_PROVED');
      await tester.tap(find.byTooltip('Недавние подтверждённые операции'));
      await tester.pumpAndSettle();
      expect(find.text('Удаление профиля подтверждено'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byWidgetPredicate(
            (widget) => widget.key is RecentOperationReceiptKey,
          ),
        ),
        findsNWidgets(3),
      );
      await tester.ensureVisible(find.text('Закрыть'));
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
      stdout.writeln('COMPILED_FLUTTER_DELETED_RECENT_PROVED');
      await tester.pumpWidget(const SizedBox.shrink());
      final emptyShutdown = Stopwatch()..start();
      while (discovery.existsSync() &&
          emptyShutdown.elapsed < const Duration(seconds: 15)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(discovery.existsSync(), false);
    },
  );
}
