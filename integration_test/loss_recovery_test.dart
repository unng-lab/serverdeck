import 'support/runtime_hooks.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../lib/app.dart';
import '../lib/main.dart' as app;
import '../lib/bootstrap/bootstrap_controller.dart';
import '../lib/bootstrap/native_bootstrap_host.dart';

import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_windows/client_bootstrap.dart';

import '../packages/serverdeck_windows/test/support/ui_actor.dart';
import 'support/loss_client.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final profile = Platform.environment['LOCALAPPDATA'] ?? '';
  if (!RegExp(r'[\\/]\.local[\\/]foundation-ui-[a-f0-9]{32}[\\/]profile$')
      .hasMatch(profile)) {
    throw StateError('OWNED_ACCEPTANCE_FIXTURE_REQUIRED');
  }
  final role = Platform.environment['SERVERDECK_UI_ROLE'] ?? 'primary';
  if (!{'primary', 'observer', 'reopen'}.contains(role))
    throw StateError('ACTOR_ROLE_INVALID');
  final signals = Directory('$profile/ui-loss')..createSync();
  File signal(String name) => File('${signals.path}/$name');
  void publish(String name, [Map<String, Object?> value = const {}]) {
    final pending = signal('$name.pending');
    pending.writeAsStringSync(jsonEncode(value), flush: true);
    pending.renameSync(signal(name).path);
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

  testWidgetsWithRuntimeHooks('actual UI loss recovery role=$role', (
    tester,
  ) async {
    NativeBootstrapHost? host;
    BootstrapController? supplied;
    LossClient? controlled;
    UiActor? child;
    var phase = 'starting';
    Future<void> wait(
      bool Function() condition,
      String reason, {
      int seconds = 30,
    }) async {
      final watch = Stopwatch()..start();
      while (!condition() && watch.elapsed < Duration(seconds: seconds)) {
        if (signal('failed').existsSync())
          throw StateError('OTHER_ACTOR_FAILED');
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(condition(), true, reason: reason);
    }

    Future<void> waitNative(bool Function() condition, String reason) async {
      await tester.runAsync(() async {
        final watch = Stopwatch()..start();
        while (!condition() &&
            !signal('failed').existsSync() &&
            watch.elapsed < const Duration(seconds: 30)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
      expect(condition(), true, reason: reason);
    }

    Future<void> click(String label) async {
      final target = find.text(label);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
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

    Future<void> saved() async {
      await wait(
        () => find.text('Сохранено').evaluate().isNotEmpty,
        'known commit plus current readback',
      );
      await click('Закрыть');
      expect(find.byType(Dialog), findsNothing);
    }

    final discovery = File(
      '$profile/ServerDeckNext/v1/runtime/default.discovery',
    );
    try {
      if (role == 'primary') {
        final normalHost = NativeBootstrapHost();
        host = normalHost;
        final fixture = LossClient();
        controlled = fixture;
        final bootstrap = BootstrapController(
          client: fixture.client,
          prepare: () async {
            await normalHost.prepare();
            await fixture.prepare();
          },
          ensureService: normalHost.ensureService,
          recoverService: normalHost.ensureService,
        );
        supplied = bootstrap;
        bootstrap.retry().ignore();
        runApp(FoundationApp(bootstrap: bootstrap));
      } else {
        app.main();
      }
      await wait(
        () => find.text('Создать профиль').evaluate().isNotEmpty,
        'ready model and recent',
      );
      final initialOwner = await owner();
      if (role == 'reopen') {
        phase = 'reopen';
        final earlier =
            jsonDecode(signal('stage-finished').readAsStringSync()) as Map;
        expect(initialOwner['uiPid'], isNot(earlier['uiPid']));
        expect(initialOwner['generation'], isNot(earlier['generation']));
        expect(find.text('Request retry update'), findsOneWidget);
        await tester.tap(find.byTooltip('Недавние подтверждённые операции'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: find.byType(Dialog), matching: find.byType(Card)),
          findsNWidgets(3),
        );
        expect(find.text('Создание профиля подтверждено'), findsOneWidget);
        expect(find.text('Изменение профиля подтверждено'), findsNWidgets(2));
        await click('Закрыть');
        await tester.pumpWidget(const SizedBox.shrink());
        await wait(
          () => !discovery.existsSync(),
          'new process releases last lease',
          seconds: 90,
        );
        publish('accepted', {
          'format': 1,
          'scenario': 'ui-loss-status-retry-reopen',
        });
        stdout.writeln(
          'COMPILED_UI_LOSS_FRESH_PROCESS_THREE_EFFECTS_NO_AUTOSAVE_PROVED',
        );
        return;
      }
      if (role == 'observer') {
        UiActor.positionObserverWindow();
        await wait(
          () => find.text('Loss profile').evaluate().isNotEmpty,
          'initial profile',
        );
        publish('observer-ready', initialOwner);
        phase = 'observer-first';
        await wait(
          () => find.text('Reply lost update').evaluate().isNotEmpty,
          'other window committed lost reply',
        );
        publish('observer-first', await owner());
        phase = 'observer-second';
        await wait(
          () => find.text('Request retry update').evaluate().isNotEmpty,
          'other window committed retry',
        );
        publish('observer-second', await owner());
        await waitNative(
          () => signal('finish-observer').existsSync(),
          'primary accepts readbacks',
        );
        UiActor.closeCurrentWindow();
        await tester.pump(const Duration(seconds: 10));
        throw StateError('NATIVE_CLOSE_DID_NOT_EXIT');
      }
      phase = 'create';
      await click('Создать профиль');
      await tester.enterText(
        find.byKey(const ValueKey('profile-name')),
        'Loss profile',
      );
      await tester.enterText(
        find.byKey(const ValueKey('profile-address')),
        '192.0.2.55',
      );
      await tester.enterText(
        find.byKey(const ValueKey('profile-user')),
        'fixture',
      );
      await click('Сохранить');
      await saved();
      final actor = await Isolate.run(UiActor.launch);
      child = actor;
      await waitNative(
        () => signal('observer-ready').existsSync(),
        'second ready window',
      );
      final second =
          jsonDecode(signal('observer-ready').readAsStringSync()) as Map;
      expect(second['uiPid'], actor.pid);
      expect(second['generation'], initialOwner['generation']);
      expect(second['serverPid'], initialOwner['serverPid']);
      final client = controlled!.client;
      final transport = controlled.transport;
      phase = 'lost-reply';
      await edit('Loss profile', 'Reply lost update');
      transport.dropNextMethod = 'profiles.update';
      await click('Сохранить');
      await wait(
        () => find.text('Сохранение не подтверждено').evaluate().isNotEmpty,
        'real RPC deadline after lost reply',
      );
      expect(transport.replyDropped, true);
      expect(find.text('Сохранено'), findsNothing);
      expect(find.text('Reply lost update'), findsWidgets);
      expect(find.text('Повторить тот же запрос'), findsNothing);
      await waitNative(
        () => signal('observer-first').existsSync(),
        'observer sees committed lost reply',
      );
      await click('Проверить результат');
      await saved();
      final firstRead = await client.read(ApiMethod.mutationsRecent, {
        'limit': 20,
      });
      final firstReceipts = (firstRead.result['receipts'] as List).cast<Map>();
      expect(firstReceipts, hasLength(2));
      expect(
        firstReceipts.where((r) => r['requestId'] == transport.dropReplyId),
        hasLength(1),
      );
      expect(actor.exitCode, 259);
      expect(client.generation, initialOwner['generation']);
      stdout.writeln('COMPILED_UI_LOST_REPLY_STATUS_CURRENT_READBACK_PROVED');
      phase = 'lost-request';
      await edit('Reply lost update', 'Request retry update');
      transport.holdNextMethod = 'profiles.update';
      await click('Сохранить');
      await wait(
        () => find.text('Сохранение не подтверждено').evaluate().isNotEmpty,
        'held original RPC timeout',
      );
      expect(transport.requestHeld, true);
      expect(find.text('Сохранено'), findsNothing);
      final beforeRetry = await client.read(ApiMethod.profilesList);
      expect(beforeRetry.result['storeRevision'], '2');
      expect(
        ((beforeRetry.result['profiles'] as List).single as Map)['name'],
        'Reply lost update',
      );
      await click('Проверить результат');
      await wait(
        () => find.text('Повторить тот же запрос').evaluate().isNotEmpty,
        'not-found authorizes explicit same intent retry',
      );
      expect(find.text('Request retry update'), findsOneWidget);
      await click('Повторить тот же запрос');
      await saved();
      expect(transport.lateOriginalDelivered, true);
      await waitNative(
        () => signal('observer-second').existsSync(),
        'observer sees single retry effect',
      );
      final finalRead = await client.read(ApiMethod.profilesList);
      expect(finalRead.result['storeRevision'], '3');
      final current = (finalRead.result['profiles'] as List).single as Map;
      expect(current['name'], 'Request retry update');
      expect(current['revision'], '3');
      final recent = await client.read(ApiMethod.mutationsRecent, {
        'limit': 20,
      });
      final receipts = (recent.result['receipts'] as List).cast<Map>();
      expect(receipts, hasLength(3));
      expect(
        receipts.where((r) => r['requestId'] == transport.holdRequestId),
        hasLength(1),
      );
      for (final name in ['observer-first', 'observer-second']) {
        final peer = jsonDecode(signal(name).readAsStringSync()) as Map;
        expect(peer['generation'], initialOwner['generation']);
        expect(peer['serverPid'], initialOwner['serverPid']);
      }
      expect(actor.exitCode, 259);
      stdout.writeln(
        'COMPILED_UI_LOST_REQUEST_EXPLICIT_RETRY_LATE_ORIGINAL_SINGLE_EFFECT_PROVED',
      );
      phase = 'close';
      publish('finish-observer');
      await waitNative(() => actor.exitCode != 259, 'observer native close');
      expect(actor.exitCode, 0);
      expect((await owner())['generation'], initialOwner['generation']);
      publish('stage-finished', {
        'format': 1,
        'scenario': 'ui-loss-status-retry',
        ...initialOwner,
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await host!.client.close();
      await host.close();
      await wait(
        () => !discovery.existsSync(),
        'all owned sessions released',
        seconds: 90,
      );
    } on Object catch (error) {
      publish('failed-$role', {
        'phase': phase,
        'errorKind': error.runtimeType.toString(),
      });
      publish('failed', {
        'phase': phase,
        'errorKind': error.runtimeType.toString(),
      });
      rethrow;
    } finally {
      try {
        await supplied?.close();
      } finally {
        try {
          child?.terminateIfLive();
        } finally {
          try {
            child?.close();
          } finally {
            try {
              await controlled?.client.close();
            } finally {
              try {
                await host?.client.close();
              } finally {
                await host?.close();
              }
            }
          }
        }
      }
    }
  });
}
