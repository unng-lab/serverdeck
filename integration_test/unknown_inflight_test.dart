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
import '../lib/profiles/profile_list.dart';
import '../lib/profiles/mutation_controller.dart';
import '../lib/profiles/mutation_status.dart';

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
  if (!{'primary', 'observer', 'reopen'}.contains(role) ||
      Platform.environment['SERVERDECK_UI_SCENARIO'] != 'unknown-inflight') {
    throw StateError('ACTOR_ROLE_INVALID');
  }
  final signals = Directory('$profile/ui-inflight')..createSync();
  File signal(String name) => File('${signals.path}/$name');
  void publish(String name, Map<String, Object?> value) {
    final pending = signal('$name.pending');
    pending.writeAsStringSync(jsonEncode(value), flush: true);
    pending.renameSync(signal(name).path);
  }

  Map<String, Object?> read(String name) => Map<String, Object?>.from(
    jsonDecode(signal(name).readAsStringSync()) as Map,
  );
  Future<Map<String, Object?>> owner() => Isolate.run(() async {
    final environment = await ClientBootstrapEnvironment.verify();
    final descriptor = await environment.discovery();
    if (descriptor == null) throw StateError('OWNER_MISSING');
    try {
      return {
        'uiPid': pid,
        'serverPid': descriptor.serverPid,
        'generation': descriptor.generation,
      };
    } finally {
      descriptor.close();
    }
  });

  testWidgetsWithRuntimeHooks('actual unknown inflight UI crash role=$role', (
    tester,
  ) async {
    NativeBootstrapHost? host;
    BootstrapController? supplied;
    LossClient? controlled;
    UiActor? child;
    var terminationAttempted = false;
    var phase = 'ready';
    Future<void> wait(bool Function() condition, {int seconds = 30}) async {
      final watch = Stopwatch()..start();
      while (!condition() && watch.elapsed < Duration(seconds: seconds)) {
        if (signal('failed').existsSync())
          throw StateError('OTHER_ACTOR_FAILED');
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(condition(), true, reason: 'inflight acceptance $phase');
    }

    Future<void> waitNative(
      bool Function() condition, {
      int seconds = 30,
    }) async {
      await tester.runAsync(() async {
        final watch = Stopwatch()..start();
        while (!condition() &&
            !signal('failed').existsSync() &&
            watch.elapsed < Duration(seconds: seconds)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      expect(condition(), true, reason: 'native inflight acceptance $phase');
    }

    Future<void> click(String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    Future<void> edit(String current, String replacement) async {
      if (find.text('Редактировать профиль').evaluate().isEmpty) {
        await tester.tap(
          find.descendant(
            of: find.byType(ExpansionTile),
            matching: find.text(current),
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
      await wait(() => find.text('Сохранено').evaluate().isNotEmpty);
      await click('Закрыть');
    }

    final discovery = File(
      '$profile/ServerDeckNext/v1/runtime/default.discovery',
    );
    try {
      if (role == 'observer') {
        UiActor.positionObserverWindow();
        final nativeHost = NativeBootstrapHost();
        host = nativeHost;
        final fixture = LossClient();
        controlled = fixture;
        final bootstrap = BootstrapController(
          client: fixture.client,
          prepare: () async {
            await nativeHost.prepare();
            await fixture.prepare();
          },
          ensureService: nativeHost.ensureService,
          recoverService: nativeHost.ensureService,
        );
        supplied = bootstrap;
        bootstrap.retry().ignore();
        runApp(FoundationApp(bootstrap: bootstrap));
      } else {
        app.main();
      }
      await wait(() => find.text('Создать профиль').evaluate().isNotEmpty);
      final initial = await owner();
      final model = tester
          .widget<ProfileList>(find.byType(ProfileList))
          .controller;
      final client = model.bootstrap.client;
      if (role == 'observer') {
        phase = 'arm';
        await wait(() => find.text('Pending profile').evaluate().isNotEmpty);
        await edit('Pending profile', 'Committed unknown');
        controlled!.transport.dropNextMethod = 'profiles.update';
        publish('observer-ready', initial);
        await waitNative(() => signal('send').existsSync());
        phase = 'drop';
        await tester.tap(find.text('Сохранить'));
        await tester.pump();
        await wait(() => controlled!.transport.replyDropped, seconds: 3);
        final mutation = tester
            .widget<MutationStatus>(find.byType(MutationStatus))
            .controller;
        expect(mutation.state, MutationPresentation.submitting);
        expect(find.text('Сохранено'), findsNothing);
        publish('reply-dropped', {
          ...initial,
          'requestId': controlled.transport.dropReplyId,
          'presentation': 'submitting',
        });
        // No status/retry/close is sent. The parent kills this retained child
        // within four seconds of its earlier send signal (RPC deadline is5s).
        await waitNative(() => false);
        throw StateError('CHILD_WAS_NOT_TERMINATED');
      }
      if (role == 'reopen') {
        phase = 'reopen';
        final earlier = read('stage-finished');
        expect(initial['uiPid'], isNot(earlier['uiPid']));
        expect(initial['generation'], isNot(earlier['generation']));
        expect(model.profiles.single.name, 'Survivor update');
        expect(model.storeRevision, '3');
        final recent = await client.read(ApiMethod.mutationsRecent, {
          'limit': 20,
        });
        final receipts = (recent.result['receipts'] as List).cast<Map>();
        expect(receipts, hasLength(3));
        expect(
          receipts.where(
            (receipt) => receipt['requestId'] == earlier['requestId'],
          ),
          hasLength(1),
        );
        await tester.tap(find.byTooltip('Недавние подтверждённые операции'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: find.byType(Dialog), matching: find.byType(Card)),
          findsNWidgets(3),
        );
        await click('Закрыть');
        await tester.pumpWidget(const SizedBox.shrink());
        await wait(() => !discovery.existsSync(), seconds: 90);
        publish('accepted', {
          'format': 1,
          'scenario': 'unknown-inflight-crash-reopen',
          'storeRevision': '3',
        });
        stdout.writeln(
          'COMPILED_UI_UNKNOWN_INFLIGHT_FRESH_PROCESS_NO_AUTOSAVE_PROVED',
        );
        return;
      }
      phase = 'create';
      await click('Создать профиль');
      await tester.enterText(
        find.byKey(const ValueKey('profile-name')),
        'Pending profile',
      );
      await tester.enterText(
        find.byKey(const ValueKey('profile-address')),
        '192.0.2.56',
      );
      await tester.enterText(
        find.byKey(const ValueKey('profile-user')),
        'fixture',
      );
      await click('Сохранить');
      await saved();
      final actor = await Isolate.run(UiActor.launchPendingObserver);
      child = actor;
      phase = 'actor-ready';
      await waitNative(() => signal('observer-ready').existsSync());
      final peer = read('observer-ready');
      expect(peer['uiPid'], actor.pid);
      expect(peer['uiPid'], isNot(initial['uiPid']));
      expect(peer['serverPid'], initial['serverPid']);
      expect(peer['generation'], initial['generation']);
      final pendingWatch = Stopwatch()..start();
      publish('send', {'format': 1});
      phase = 'terminate-pending';
      await waitNative(() => signal('reply-dropped').existsSync(), seconds: 3);
      final dropped = read('reply-dropped');
      expect(dropped['uiPid'], actor.pid);
      expect(dropped['presentation'], 'submitting');
      expect(pendingWatch.elapsed, lessThan(const Duration(seconds: 4)));
      terminationAttempted = true;
      actor.terminateIfLive();
      expect(pendingWatch.elapsed, lessThan(const Duration(seconds: 4)));
      await waitNative(() => actor.exitCode != 259);
      expect(actor.exitCode, 73);
      expect(pendingWatch.elapsed, lessThan(const Duration(seconds: 4)));
      final killElapsedMs = pendingWatch.elapsedMilliseconds;
      phase = 'survivor';
      await wait(() => find.text('Committed unknown').evaluate().isNotEmpty);
      expect(model.profiles.single.name, 'Committed unknown');
      expect((await owner())['generation'], initial['generation']);
      expect(model.storeRevision, '2');
      final recent = await client.read(ApiMethod.mutationsRecent, {
        'limit': 20,
      });
      final receipts = (recent.result['receipts'] as List).cast<Map>();
      expect(receipts, hasLength(2));
      expect(
        receipts.where(
          (receipt) => receipt['requestId'] == dropped['requestId'],
        ),
        hasLength(1),
      );
      await edit('Committed unknown', 'Survivor update');
      await click('Сохранить');
      await saved();
      expect(model.storeRevision, '3');
      expect((await owner())['generation'], initial['generation']);
      publish('stage-finished', {
        'format': 1,
        'scenario': 'unknown-inflight-crash',
        ...initial,
        'requestId': dropped['requestId'],
        'storeRevision': '3',
        'observerPid': actor.pid,
        'killElapsedMs': killElapsedMs,
      });
      stdout.writeln(
        'COMPILED_UI_UNKNOWN_INFLIGHT_KILL_SURVIVOR_SINGLE_EFFECT_PROVED',
      );
      phase = 'close';
      await tester.pumpWidget(const SizedBox.shrink());
      await wait(() => !discovery.existsSync(), seconds: 90);
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
          await host?.client.close();
          await host?.close();
        } finally {
          try {
            if (!terminationAttempted) child?.terminateIfLive();
          } finally {
            child?.close();
          }
        }
      }
    }
  });
}
