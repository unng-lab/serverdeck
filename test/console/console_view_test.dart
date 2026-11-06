import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/console/console_models.dart';
import 'package:serverdeck/console/console_owner.dart';
import 'package:serverdeck/console/console_view.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_components.dart';

import 'package:serverdeck/domain/actor.dart';
import 'package:serverdeck/domain/app_operations.dart';
import 'package:serverdeck/storage/records.dart';

import '../domain/command_gate_test.dart' show FakeState, epoch, profile;
import '../fixtures/domain_repository.dart';
import '../fixtures/feature_harness.dart' show featureId, FeatureClock;
import 'fakes.dart';

void main() {
  late DomainCommandGate gate;
  late FakeConsolePort port;
  late ConsoleOwner owner;
  setUp(() {
    final actors = ActorAuthority(epoch), state = FakeState();
    gate = DomainCommandGate(actors: actors, state: state);
    final repository = MemoryDomainRepository();
    repository.state.profiles[profile] = Profile()..profileId = profile;
    final clock = FeatureClock();
    var sequence = 100;
    port = FakeConsolePort(state.versions);
    owner = ConsoleOwner(
      actors: actors,
      gate: gate,
      state: state,
      repository: repository,
      connections: port,
      configuration: () => const ConsoleConfiguration(),
      newId: () => featureId(++sequence),
      monotonicNow: clock.monotonic,
      schedule: clock.schedule,
    );
  });
  tearDown(() async {
    await owner.dispose();
    await port.events.close();
    gate.stopAdmission();
    await gate.drain();
  });
  testWidgets(
    'selected session survives renderer detach and server navigation',
    (tester) async {
      late String second;
      await tester.runAsync(() async {
        await owner.openConsole(ConsoleCaller.ui(owner.actors.ui), profile);
        final opened = await owner.openConsole(
          ConsoleCaller.ui(owner.actors.ui),
          profile,
        );
        second = (opened.value!.console as ConsoleActionValue).sessionId;
        owner.selectSession(profile, second);
      });
      Widget host(String id) => MaterialApp(
        theme: BrandTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ConsoleView(
              owner: owner,
              profileId: id,
              connectionRevision: 1,
              serverLabel: id,
              username: 'root',
            ),
          ),
        ),
      );
      await tester.pumpWidget(host(profile));
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(ValueKey('console-session-$second')),
            )
            .initialValue,
        second,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(host(featureId(500)));
      await tester.pumpWidget(host(profile));
      expect(find.byKey(ValueKey('console-session-$second')), findsOneWidget);
      expect(owner.selectedSession(profile), second);
    },
  );
  testWidgets(
    'multiline consent binds exact payload to current lease; UI can take control',
    (tester) async {
      late ConsoleActionValue opened;
      await tester.runAsync(() async {
        opened =
            (await owner.openConsole(
                  ConsoleCaller.ui(owner.actors.ui),
                  profile,
                )).value!.console
                as ConsoleActionValue;
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ConsoleView(
                owner: owner,
                profileId: profile,
                connectionRevision: 1,
                serverLabel: 'Server',
                username: 'root',
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(DeckTerminal));
      await tester.pump();
      Future<void>? paste;
      await tester.runAsync(() async {
        tester.testTextInput.enterText('echo one\necho two');
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Вставить несколько строк?'), findsOneWidget);
      await tester.runAsync(() async {
        await owner.releaseConsole(
          ConsoleCaller.ui(owner.actors.ui),
          profile,
          opened.sessionId,
          generation: 1,
          leaseToken: opened.leaseToken!,
        );
        final actor = owner.actors.mcp(
          clientId: featureId(999),
          grantVersion: 1,
        );
        await owner.acquireConsole(
          ConsoleCaller.mcp(actor, ConsoleMcpBinding(actor)),
          profile,
          opened.sessionId,
          generation: 1,
          ownerEpoch: epoch,
          operationSequence: 1,
        );
      });
      await tester.tap(find.text('Подтвердить'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(port.openings.single.channel.writes, isEmpty);
      expect(
        tester.widget<DeckTerminal>(find.byType(DeckTerminal)).readOnly,
        true,
      );
      final takeover = tester.widget<DeckButton>(
        find.ancestor(
          of: find.text('Взять управление'),
          matching: find.byType(DeckButton),
        ),
      );
      await tester.runAsync(() async {
        await takeover.onPressed!();
      });
      await tester.pump();
      expect(
        tester.widget<DeckTerminal>(find.byType(DeckTerminal)).readOnly,
        false,
      );
      await tester.runAsync(() async {
        paste = tester
            .widget<DeckTerminal>(find.byType(DeckTerminal))
            .onPaste('echo one\necho two');
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Подтвердить'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() => paste!);
      expect(
        port.openings.single.channel.writes.single,
        'echo one\necho two'.codeUnits,
      );
    },
  );
  testWidgets(
    'console view opens explicitly and closes only its session with consent',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ConsoleView(
                owner: owner,
                profileId: profile,
                connectionRevision: 1,
                serverLabel: 'Server A',
                username: 'root',
              ),
            ),
          ),
        ),
      );
      expect(find.text('Server A'), findsOneWidget);
      expect(port.openings, isEmpty);
      DeckButton button(String label) => tester.widget<DeckButton>(
        find
            .ancestor(of: find.text(label), matching: find.byType(DeckButton))
            .first,
      );
      await tester.runAsync(() async {
        await button('Открыть консоль').onPressed!();
      });
      await tester.pump(const Duration(milliseconds: 400));
      expect(owner.sessionsFor(profile).length, 1);
      expect(find.text('Активна'), findsOneWidget);
      Future<void>? closing;
      await tester.runAsync(() async {
        closing = Future<void>.sync(button('Закрыть консоль').onPressed!);
      });
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text('Удалённые процессы могут продолжить работу.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Отмена'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() => closing!);
      expect(owner.sessionsFor(profile).length, 1);
      await tester.runAsync(() async {
        closing = Future<void>.sync(button('Закрыть консоль').onPressed!);
      });
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Подтвердить'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() => closing!);
      await tester.pump();
      expect(owner.sessionsFor(profile), isEmpty);
      expect(port.connected, isTrue);
    },
  );
  testWidgets('platform multiline cancel and changed server never send input', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await owner.openConsole(ConsoleCaller.ui(owner.actors.ui), profile);
    });
    Widget host(String id) => MaterialApp(
      theme: BrandTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ConsoleView(
            owner: owner,
            profileId: id,
            connectionRevision: 1,
            serverLabel: id,
            username: 'root',
          ),
        ),
      ),
    );
    await tester.pumpWidget(host(profile));
    Future<void> enter() async {
      await tester.tap(find.byType(DeckTerminal));
      await tester.pump();
      await tester.runAsync(() async {
        tester.testTextInput.enterText('first\nsecond');
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Вставить несколько строк?'), findsOneWidget);
      expect(port.openings.single.channel.writes, isEmpty);
    }

    await enter();
    await tester.tap(find.text('Отмена'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(port.openings.single.channel.writes, isEmpty);
    await enter();
    await tester.pumpWidget(host(featureId(500)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(find.text('Вставить несколько строк?'), findsNothing);
    expect(port.openings.single.channel.writes, isEmpty);
  });
}
