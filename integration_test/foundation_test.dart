import 'support/runtime_hooks.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:serverdeck/main.dart' as app;
import 'package:serverdeck_windows/client_bootstrap.dart';

import '../packages/serverdeck_windows/test/support/ui_actor.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final profile = Platform.environment['LOCALAPPDATA'] ?? '';
  if (!RegExp(r'[\\/]\.local[\\/]foundation-ui-[a-f0-9]{32}[\\/]profile$')
      .hasMatch(profile))
    throw StateError('OWNED_ACCEPTANCE_FIXTURE_REQUIRED');
  final signals = Directory('$profile/two-window')..createSync();
  File signal(String name) => File('${signals.path}/$name');
  void publish(String name, [Map<String, Object?> value = const {}]) {
    final pending = signal('$name.pending');
    pending.writeAsStringSync(jsonEncode(value), flush: true);
    pending.renameSync(signal(name).path);
  }

  final role = Platform.environment['SERVERDECK_UI_ROLE'] ?? 'primary';
  if (!const {
    'primary',
    'observer',
    'witness',
    'recovered',
    'reopen',
  }.contains(role)) {
    throw StateError('ACTOR_ROLE_INVALID');
  }
  final observer = role == 'observer';
  final recovered = role == 'recovered';
  final witness = role == 'witness' || recovered;
  final reopening = role == 'reopen';
  final concurrent =
      Platform.environment['SERVERDECK_UI_SCENARIO'] == 'concurrent-three';
  final crashing =
      Platform.environment['SERVERDECK_UI_SCENARIO'] == 'crash-observer';
  testWidgetsWithRuntimeHooks(
    'real UI observer=$observer witness=$witness reopen=$reopening concurrent=$concurrent crash=$crashing',
    (tester) async {
      final previousErrorHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        final name = 'framework-${role}';
        if (!signal(name).existsSync()) {
          publish(name, {
            'errorKind': details.exception.runtimeType.toString(),
            'library': details.library,
            'context': details.context?.toDescription(),
            'stack': details.stack?.toString().split('\n').take(8).toList(),
          });
        }
        previousErrorHandler?.call(details);
      };
      Future<void> wait(
        bool Function() condition,
        String reason, {
        int seconds = 30,
      }) async {
        final elapsed = Stopwatch()..start();
        while (!condition() && elapsed.elapsed < Duration(seconds: seconds)) {
          if (signal('failed').existsSync())
            throw StateError('OTHER_ACTOR_FAILED');
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(condition(), true, reason: reason);
      }

      Future<void> ready() async {
        app.main();
        await wait(
          () => find.text('Создать профиль').evaluate().isNotEmpty,
          'ready with model/recent',
        );
      }

      Future<void> waitNative(bool Function() condition, String reason) async {
        await tester.runAsync(() async {
          final deadline = Stopwatch()..start();
          while (!condition() &&
              !signal('failed').existsSync() &&
              deadline.elapsed < const Duration(seconds: 30)) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        });
        expect(condition(), true, reason: reason);
      }

      Future<void> click(String text) async {
        final target = find.text(text);
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      Future<void> save() async {
        await click('Сохранить');
        await wait(
          () => find.text('Сохранено').evaluate().isNotEmpty,
          'committed current-model readback',
          seconds: 15,
        );
        if (crashing) {
          await click('Закрыть');
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        }
        await tester.pumpAndSettle();
      }

      Future<void> edit(String name, String replacement) async {
        if (find.text('Редактировать профиль').evaluate().isEmpty) {
          await tester.tap(
            find.descendant(
              of: find.byType(ExpansionTile),
              matching: find.text(name),
            ),
          );
          await tester.pumpAndSettle();
        }
        await click('Редактировать профиль');
        await tester.enterText(
          find.byKey(const ValueKey('profile-name')),
          replacement,
        );
        await tester.pumpAndSettle();
      }

      Future<Map<String, Object?>> owner() => Isolate.run(() async {
        final environment = await ClientBootstrapEnvironment.verify();
        final descriptor = await environment.discovery();
        if (descriptor == null) throw StateError('OWNER_MISSING');
        try {
          return {
            'serverPid': descriptor.serverPid,
            'generation': descriptor.generation,
            'uiPid': pid,
          };
        } finally {
          descriptor.close();
        }
      });
      final discovery = File(
        '$profile/ServerDeckNext/v1/runtime/default.discovery',
      );
      UiActor? child;
      UiActor? third;
      var phase = 'starting';
      try {
        if (concurrent && !reopening && !witness) {
          if (observer) {
            publish('observer-boot-entry');
            await waitNative(
              () => signal('start').existsSync(),
              'start barrier',
            );
          } else {
            child = await Isolate.run(UiActor.launchConcurrentObserver);
            await waitNative(
              () => signal('observer-boot-entry').existsSync(),
              'second engine before bootstrap',
            );
            expect(discovery.existsSync(), false);
            publish('start');
          }
        }
        await ready();
        if (reopening) {
          final previous =
              jsonDecode(signal('stage-finished').readAsStringSync()) as Map;
          expect(pid, isNot(previous['uiPid']));
          final reopenedOwner = await owner();
          expect(reopenedOwner['generation'], isNot(previous['generation']));
          expect(find.text('Primary after close'), findsOneWidget);
          await tester.tap(find.byTooltip('Недавние подтверждённые операции'));
          await tester.pumpAndSettle();
          expect(
            find.descendant(
              of: find.byType(Dialog),
              matching: find.byType(Card),
            ),
            findsNWidgets(3),
          );
          expect(find.text('Создание профиля подтверждено'), findsOneWidget);
          expect(find.text('Изменение профиля подтверждено'), findsNWidgets(2));
          stdout.writeln(
            'COMPILED_TWO_UI_FRESH_PROCESS_REOPEN_NO_AUTOSAVE_PROVED',
          );
          await click('Закрыть');
          await tester.pumpWidget(const SizedBox.shrink());
          await wait(
            () => !discovery.existsSync(),
            'fresh process releases last session',
            seconds: 20,
          );
          publish('primary-accepted', {
            'format': 1,
            'scenario': crashing
                ? 'crash-observer-recover-reopen'
                : concurrent
                ? 'concurrent-three-cas-close-reopen'
                : 'two-window-cas-close-reopen',
          });
          return;
        }
        if (witness) {
          phase = 'witness-current-model';
          UiActor.positionObserverWindow(witness: true);
          await wait(
            () => find.text('Observer update').evaluate().isNotEmpty,
            'third window reads other committed update',
          );
          if (recovered) {
            phase = 'recovered-history';
            expect(find.text('Observer discarded draft'), findsNothing);
            await tester.tap(
              find.byTooltip('Недавние подтверждённые операции'),
            );
            await tester.pumpAndSettle();
            expect(
              find.descendant(
                of: find.byType(Dialog),
                matching: find.byType(Card),
              ),
              findsNWidgets(2),
            );
            expect(find.text('Создание профиля подтверждено'), findsOneWidget);
            expect(find.text('Изменение профиля подтверждено'), findsOneWidget);
            await click('Закрыть');
            publish('crash-recovered-history', {
              'format': 1,
              'committedReceipts': 2,
            });
          }
          publish('witness-ready', await owner());
          phase = 'witness-follow-primary';
          await wait(
            () => find.text('Primary after close').evaluate().isNotEmpty,
            'third window reads surviving primary commit',
          );
          publish('witness-updated', await owner());
          await waitNative(
            () => signal('finish-witness').existsSync(),
            'primary finished current readback',
          );
          UiActor.closeCurrentWindow();
          await tester.pump(const Duration(seconds: 10));
          throw StateError('NATIVE_CLOSE_DID_NOT_EXIT');
        }
        if (observer) {
          UiActor.positionObserverWindow();
          if (concurrent) {
            expect(find.text('Локальных профилей пока нет'), findsOneWidget);
            publish('observer-started', await owner());
          }
          await wait(
            () => find.text('Shared profile').evaluate().isNotEmpty,
            'second window current profile',
          );
          publish('observer-ready', await owner());
          await wait(
            () => signal('update').existsSync(),
            'primary draft is open',
          );
          await edit('Shared profile', 'Observer update');
          await save();
          publish('updated', await owner());
          if (crashing) {
            await edit('Observer update', 'Observer discarded draft');
            publish('crash-ready');
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(minutes: 2)),
            );
            throw StateError('EXPECTED_OWNED_CRASH_DID_NOT_OCCUR');
          }
          await wait(
            () => signal('finish').existsSync(),
            'primary accepts surviving window',
          );
          publish('observer-finished');
          UiActor.closeCurrentWindow();
          await tester.pump(const Duration(seconds: 10));
          throw StateError('NATIVE_CLOSE_DID_NOT_EXIT');
        }
        expect(find.text('Локальных профилей пока нет'), findsOneWidget);
        if (concurrent) {
          await waitNative(
            () => signal('observer-started').existsSync(),
            'concurrent clients both ready before create',
          );
          final secondOwner =
              jsonDecode(signal('observer-started').readAsStringSync()) as Map;
          final primaryOwner = await owner();
          expect(secondOwner['uiPid'], child!.pid);
          expect(secondOwner['uiPid'], isNot(pid));
          expect(secondOwner['serverPid'], primaryOwner['serverPid']);
          expect(secondOwner['generation'], primaryOwner['generation']);
          stdout.writeln('COMPILED_CONCURRENT_UI_START_SHARED_OWNER_PROVED');
        }
        await click('Создать профиль');
        await tester.enterText(
          find.byKey(const ValueKey('profile-name')),
          'Shared profile',
        );
        await tester.enterText(
          find.byKey(const ValueKey('profile-address')),
          '192.0.2.44',
        );
        await tester.enterText(
          find.byKey(const ValueKey('profile-user')),
          'fixture',
        );
        await tester.pumpAndSettle();
        await save();
        final initialOwner = await owner();
        await edit('Shared profile', 'Primary RAM draft');
        final UiActor launched =
            child ??
            await Isolate.run<UiActor>(
              crashing ? UiActor.launchCrashObserver : UiActor.launch,
            );
        child = launched;
        await tester.runAsync(() async {
          final deadline = Stopwatch()..start();
          while (!signal('observer-ready').existsSync() &&
              !signal('failed').existsSync() &&
              deadline.elapsed < const Duration(seconds: 30)) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        });
        expect(signal('observer-ready').existsSync(), true);
        final second =
            jsonDecode(signal('observer-ready').readAsStringSync()) as Map;
        expect(second['uiPid'], launched.pid);
        expect(second['uiPid'], isNot(pid));
        expect(second['serverPid'], initialOwner['serverPid']);
        expect(second['generation'], initialOwner['generation']);
        publish('update');
        await wait(
          () => signal('updated').existsSync(),
          'other window committed',
        );
        await tester.pump(const Duration(seconds: 3));
        expect(find.text('Primary RAM draft'), findsOneWidget);
        await click('Сохранить');
        await wait(
          () => find
              .textContaining('Профиль изменён другим окном')
              .evaluate()
              .isNotEmpty,
          'actual stale revision rejected',
        );
        expect(find.text('Сохранено'), findsNothing);
        expect(find.text('Primary RAM draft'), findsOneWidget);
        await click('Перечитать профиль');
        expect(find.text('Observer update'), findsWidgets);
        expect(find.text('Primary RAM draft'), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        stdout.writeln('COMPILED_TWO_UI_SHARED_OWNER_CAS_PROVED');
        if (concurrent) {
          final launchedThird = await Isolate.run(UiActor.launchWitness);
          third = launchedThird;
          await waitNative(
            () => signal('witness-ready').existsSync(),
            'third actual UI current model',
          );
          final witnessOwner =
              jsonDecode(signal('witness-ready').readAsStringSync()) as Map;
          expect(witnessOwner['uiPid'], launchedThird.pid);
          expect(witnessOwner['uiPid'], isNot(pid));
          expect(witnessOwner['uiPid'], isNot(launched.pid));
          expect(witnessOwner['serverPid'], initialOwner['serverPid']);
          expect(witnessOwner['generation'], initialOwner['generation']);
          expect(launched.exitCode, 259);
          stdout.writeln('COMPILED_THREE_UI_SHARED_OWNER_PROVED');
        }
        if (crashing) {
          await waitNative(
            () => signal('crash-ready').existsSync(),
            'observer unsent draft',
          );
          await edit('Observer update', 'Primary draft during crash');
          expect(launched.exitCode, 259);
          launched.terminateIfLive();
        } else {
          publish('finish');
        }
        // Native process completion does not depend on a Flutter frame arriving.
        await tester.runAsync(() async {
          final deadline = Stopwatch()..start();
          while (launched.exitCode == 259 &&
              deadline.elapsed < const Duration(seconds: 30)) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        });
        expect(launched.exitCode, crashing ? 73 : 0);
        if (crashing) {
          expect(find.text('Primary draft during crash'), findsOneWidget);
          final afterCrash = await owner();
          expect(afterCrash['serverPid'], initialOwner['serverPid']);
          expect(afterCrash['generation'], initialOwner['generation']);
          stdout.writeln(
            'COMPILED_UI_ABNORMAL_EXIT_DRAFT_OWNER_SURVIVES_PROVED',
          );
          final restarted = await Isolate.run(UiActor.launchRecovered);
          third = restarted;
          await waitNative(
            () => signal('witness-ready').existsSync(),
            'new UI recovers after crash',
          );
          final restartedOwner =
              jsonDecode(signal('witness-ready').readAsStringSync()) as Map;
          expect(restartedOwner['uiPid'], restarted.pid);
          expect(restartedOwner['uiPid'], isNot(pid));
          expect(restartedOwner['uiPid'], isNot(launched.pid));
          expect(restartedOwner['serverPid'], initialOwner['serverPid']);
          expect(restartedOwner['generation'], initialOwner['generation']);
          final historyProof = jsonDecode(
            signal('crash-recovered-history').readAsStringSync(),
          ) as Map;
          expect(historyProof['format'], 1);
          expect(historyProof['committedReceipts'], 2);
          stdout.writeln(
            'COMPILED_UI_CRASH_CURRENT_MODEL_RECENT_NO_AUTOSAVE_PROVED',
          );
          expect(find.text('Primary draft during crash'), findsOneWidget);
          await click('Отмена');
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
        } else {
          expect(signal('observer-finished').existsSync(), true);
        }
        await edit('Observer update', 'Primary after close');
        await save();
        final surviving = await owner();
        expect(surviving['serverPid'], initialOwner['serverPid']);
        expect(surviving['generation'], initialOwner['generation']);
        stdout.writeln(
          crashing
              ? 'COMPILED_UI_CRASH_EXPLICIT_SAVE_AFTER_RECOVERY_PROVED'
              : 'COMPILED_TWO_UI_NATIVE_CLOSE_ONE_SURVIVES_PROVED',
        );
        if (concurrent || crashing) {
          await waitNative(
            () => signal('witness-updated').existsSync(),
            'third sees committed survivor update',
          );
          final witnessOwner =
              jsonDecode(signal('witness-updated').readAsStringSync()) as Map;
          expect(witnessOwner['serverPid'], initialOwner['serverPid']);
          expect(witnessOwner['generation'], initialOwner['generation']);
          publish('finish-witness');
          await waitNative(() => third!.exitCode != 259, 'third native exit');
          expect(third!.exitCode, 0);
          expect((await owner())['generation'], initialOwner['generation']);
          stdout.writeln('COMPILED_THIRD_UI_CURRENT_READBACK_CLOSE_PROVED');
        }
        publish('stage-finished', surviving);
        await tester.pumpWidget(const SizedBox.shrink());
        await wait(
          () => !discovery.existsSync(),
          'last lease closes owner',
          seconds: 90,
        );
      } on Object catch (error) {
        final diagnostic = {
          'phase': phase,
          'role': role,
          'errorKind': error.runtimeType.toString(),
          if (error is AssertionError) 'assertion': error.toString(),
          'hasOldName': find.text('Observer update').evaluate().isNotEmpty,
          'hasFinalName': find
              .text('Primary after close')
              .evaluate()
              .isNotEmpty,
          'hasDialog': find.byType(Dialog).evaluate().isNotEmpty,
        };
        publish('failed-${role}', diagnostic);
        publish('failed', diagnostic);
        rethrow;
      } finally {
        FlutterError.onError = previousErrorHandler;
        try {
          child?.terminateIfLive();
        } finally {
          try {
            child?.close();
          } finally {
            try {
              third?.terminateIfLive();
            } finally {
              third?.close();
            }
          }
        }
      }
    },
  );
}
