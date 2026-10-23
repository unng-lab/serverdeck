import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:serverdeck_protocol/discovery.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_windows/client_bootstrap.dart';
import 'package:serverdeck_windows/mutex.dart';

import '../lib/main.dart' as app;
import '../lib/profiles/profile_list.dart';
import '../packages/serverdeck_windows/test/support/ui_actor.dart';
import 'support/runtime_hooks.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final profile = Platform.environment['LOCALAPPDATA'] ?? '';
  if (!RegExp(r'[\\/]\.local[\\/]foundation-ui-[a-f0-9]{32}[\\/]profile$')
      .hasMatch(profile)) {
    throw StateError('OWNED_ACCEPTANCE_FIXTURE_REQUIRED');
  }
  final role = Platform.environment['SERVERDECK_UI_ROLE'] ?? 'primary';
  if (!{'primary', 'observer', 'reopen'}.contains(role)) {
    throw StateError('ACTOR_ROLE_INVALID');
  }
  final signals = Directory('$profile/owner-recovery')..createSync();
  File signal(String name) => File('${signals.path}/$name');
  void publish(String name, [Map<String, Object?> value = const {}]) {
    final temporary = signal('$name.pending');
    temporary.writeAsStringSync(jsonEncode(value), flush: true);
    temporary.renameSync(signal(name).path);
  }

  Future<Map<String, Object?>> owner() => Isolate.run(() async {
    final environment = await TrustedClientBootstrapEnvironment.verify();
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

  testWidgetsWithRuntimeHooks('normal owner UI recovery role=$role', (
    tester,
  ) async {
    UiActor? originalOwner;
    UiActor? observer;
    var phase = 'start';
    Future<void> wait(bool Function() condition, {int seconds = 30}) async {
      final elapsed = Stopwatch()..start();
      while (!condition() && elapsed.elapsed < Duration(seconds: seconds)) {
        if (signal('failed').existsSync()) {
          throw StateError('OTHER_ACTOR_FAILED');
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(condition(), true, reason: '$role/$phase');
    }

    Future<void> nativeWait(bool Function() condition) async {
      await tester.runAsync(() async {
        final elapsed = Stopwatch()..start();
        while (!condition() &&
            !signal('failed').existsSync() &&
            elapsed.elapsed < const Duration(seconds: 30)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
      expect(condition(), true, reason: '$role/$phase');
    }

    Future<void> click(String text) async {
      final target = find.text(text);
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

    Future<void> save() async {
      await click('Сохранить');
      await wait(() => find.text('Сохранено').evaluate().isNotEmpty);
      await click('Закрыть');
    }

    final discovery = File(
      '$profile/ServerDeckNext/v1/runtime/default.discovery',
    );
    try {
      if (role == 'primary') {
        await Isolate.run(() async {
          final environment = await TrustedClientBootstrapEnvironment.verify();
          final namespace = await DiscoveryNamespace.forOwner(environment.sid);
          final lease = await MutexLease.acquire(
            namespace.mutexName,
            environment.sid,
          );
          try {
            if (!lease.isHeld) throw StateError('OWNER_NAMESPACE_OCCUPIED');
          } finally {
            await lease.close();
          }
        });
        originalOwner = await Isolate.run(UiActor.launchServiceOwner);
      } else if (role == 'observer') {
        UiActor.positionObserverWindow();
      }
      app.main();
      await wait(() => find.text('Создать профиль').evaluate().isNotEmpty);
      final model = tester
          .widget<ProfileList>(find.byType(ProfileList))
          .controller;
      final client = model.bootstrap.client;
      final initial = await owner();

      if (role == 'reopen') {
        phase = 'fresh-reopen';
        final previous =
            jsonDecode(signal('stage-finished').readAsStringSync()) as Map;
        expect(initial['generation'], isNot(previous['generation']));
        expect(model.profiles.single.name, 'Observer recovered');
        expect(model.storeRevision, '3');
        final recent = await client.read(ApiMethod.mutationsRecent, {
          'limit': 20,
        });
        expect(recent.result['receipts'], hasLength(3));
        await tester.pumpWidget(const SizedBox.shrink());
        await wait(() => !discovery.existsSync(), seconds: 90);
        publish('accepted', {
          'format': 1,
          'scenario': 'normal-owner-ui-loss-recovery-reopen',
          'storeRevision': '3',
          'receiptCount': 3,
          ...initial,
        });
        stdout.writeln('COMPILED_UI_NORMAL_OWNER_RECOVERY_FRESH_REOPEN_PROVED');
        return;
      }
      if (role == 'observer') {
        phase = 'observer-ready';
        await wait(() => find.text('Owner profile').evaluate().isNotEmpty);
        publish('observer-ready', initial);
        await nativeWait(() => signal('owner-terminated').existsSync());
        phase = 'observer-recover';
        await wait(
          () =>
              model.bootstrap.state == ReadinessState.ready &&
              client.generation != initial['generation'],
        );
        publish('observer-recovered', await owner());
        await wait(
          () => find.text('Retained owner draft').evaluate().isNotEmpty,
        );
        await edit('Retained owner draft', 'Observer recovered');
        await save();
        publish('observer-saved', await owner());
        await nativeWait(() => signal('finish-observer').existsSync());
        UiActor.closeCurrentWindow();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(seconds: 30));
        });
        throw StateError('OBSERVER_DID_NOT_CLOSE');
      }

      expect(initial['serverPid'], originalOwner!.pid);
      phase = 'durable-profile';
      await click('Создать профиль');
      await tester.enterText(
        find.byKey(const ValueKey('profile-name')),
        'Owner profile',
      );
      await tester.enterText(
        find.byKey(const ValueKey('profile-address')),
        '192.0.2.235',
      );
      await tester.enterText(
        find.byKey(const ValueKey('profile-user')),
        'synthetic',
      );
      await save();
      expect(model.storeRevision, '1');
      final launchedObserver = await Isolate.run(
        UiActor.launchOwnerRecoveryObserver,
      );
      observer = launchedObserver;
      await nativeWait(() => signal('observer-ready').existsSync());
      final peer =
          jsonDecode(signal('observer-ready').readAsStringSync()) as Map;
      expect(peer['uiPid'], launchedObserver.pid);
      expect(peer['serverPid'], originalOwner.pid);
      expect(peer['generation'], initial['generation']);
      await edit('Owner profile', 'Retained owner draft');
      phase = 'terminate-owned-normal-owner';
      expect(originalOwner.exitCode, 259);
      originalOwner.terminateIfLive();
      await nativeWait(() => originalOwner!.exitCode != 259);
      expect(originalOwner.exitCode, 73);
      publish('owner-terminated');
      phase = 'primary-recover';
      await wait(
        () =>
            model.bootstrap.state == ReadinessState.ready &&
            client.generation != initial['generation'],
      );
      final recovered = await owner();
      expect(recovered['serverPid'], isNot(originalOwner.pid));
      expect(recovered['generation'], isNot(initial['generation']));
      expect(find.text('Retained owner draft'), findsOneWidget);
      expect(model.storeRevision, '1');
      final beforeSave = await client.read(ApiMethod.mutationsRecent, {
        'limit': 20,
      });
      expect(beforeSave.result['receipts'], hasLength(1));
      await nativeWait(() => signal('observer-recovered').existsSync());
      final recoveredPeer =
          jsonDecode(signal('observer-recovered').readAsStringSync()) as Map;
      expect(recoveredPeer['serverPid'], recovered['serverPid']);
      expect(recoveredPeer['generation'], recovered['generation']);
      stdout.writeln(
        'COMPILED_UI_NORMAL_OWNER_LOSS_TWO_WINDOWS_DRAFT_NO_AUTOSAVE_PROVED',
      );
      await save();
      phase = 'observer-update';
      await nativeWait(() => signal('observer-saved').existsSync());
      await wait(() => find.text('Observer recovered').evaluate().isNotEmpty);
      expect(model.storeRevision, '3');
      final recent = await client.read(ApiMethod.mutationsRecent, {
        'limit': 20,
      });
      expect(recent.result['receipts'], hasLength(3));
      publish('finish-observer');
      await nativeWait(() => launchedObserver.exitCode != 259);
      expect(launchedObserver.exitCode, 0);
      final survivor = await owner();
      expect(survivor['serverPid'], recovered['serverPid']);
      expect(survivor['generation'], recovered['generation']);
      stdout.writeln(
        'COMPILED_UI_NORMAL_OWNER_RECOVERY_EXPLICIT_SAVES_SURVIVOR_PROVED',
      );
      publish('stage-finished', {'format': 1, ...survivor});
      await tester.pumpWidget(const SizedBox.shrink());
      await wait(() => !discovery.existsSync(), seconds: 90);
    } on Object catch (error) {
      publish('failed', {
        'role': role,
        'phase': phase,
        'errorKind': error.runtimeType.toString(),
      });
      rethrow;
    } finally {
      try {
        observer?.terminateIfLive();
      } finally {
        observer?.close();
        try {
          originalOwner?.terminateIfLive();
        } finally {
          originalOwner?.close();
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    }
  });
}
